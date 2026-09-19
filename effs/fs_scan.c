// Fs.scan: a parallel walk of a directory tree on helper threads.
// ================================================================
//
// The effect takes a path, a flags word, a thread count and a probe
// node, and answers the tree beside the count of entries it could not
// read. The walk is a pool of threads over a shared stack of
// directories: each thread opens one, lists it with getdents64, asks
// statx for every entry, appends the entries to the directory's node
// and pushes the subdirectories. Nodes live in per-thread arenas.
//
// The pack step, on the loop's thread, lays the arena tree out as Bend
// terms: FsFile{name, size} and FsDir{name, size, kids}, sizes as Nat
// immediates. A type whose values the program shares carries a
// reference count in front of every node, so every field must be
// sealed; the runtime keeps no per-type flag, so the probe (an FsDir
// the program built on its heap) tells: its fields are sealed exactly
// when Fs is shared. Con cells and strings follow the IO_HOTS mask.

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>

#define FS_APPARENT 1  // apparent sizes (st_size), not allocated blocks
#define FS_CROSS    2  // descend into other filesystems (mount points)
#define FS_LINKS    4  // count every hard link (default: first one only)

#define FS_BUF   (1 << 16)
#define FS_CHUNK (1 << 20)

typedef struct FsNode {
  struct FsNode* kids;  // a directory's entries, in scan order
  struct FsNode* next;  // the next sibling
  u64            size;  // bytes: allocated, or apparent under FS_APPARENT
  u32            dir;   // 1 for a directory
  u32            len;   // the name's length
  char           name[];
} FsNode;

typedef struct FsTask {
  struct FsTask* next;
  FsNode*        node;
  char*          path;
  u32            root;  // the root may be a symlink: open it followed
} FsTask;

typedef struct {
  pthread_mutex_t lock;
  pthread_cond_t  bell;
  FsTask*         todo;
  u64             pending;
  u32             threads;
  u32             flags;
  u64             root_dev;
  _Atomic u64     errors;
  FsNode*         root;
  u64             began;
  u64             walked;
  // hard links seen: open addressing over (dev, ino) pairs
  pthread_mutex_t hlock;
  u64*            hset;
  u64             hcap;
  u64             hlen;
  // every arena chunk, freed after the pack
  pthread_mutex_t alock;
  char**          chunks;
  u64             nchunks;
} FsScan;

typedef struct {
  char*   at;
  char*   end;
  FsScan* scan;
} FsArena;

// Arena
// -----

static void* fs_chunk(FsScan* s, u64 bytes) {
  char* p = io_mem(malloc(bytes));
  pthread_mutex_lock(&s->alock);
  if ((s->nchunks & (s->nchunks + 1)) == 0) {
    s->chunks = io_mem(realloc(s->chunks, (2 * s->nchunks + 2) * sizeof(char*)));
  }
  s->chunks[s->nchunks++] = p;
  pthread_mutex_unlock(&s->alock);
  return p;
}

static FsNode* fs_node(FsArena* a, const char* name, u32 len) {
  u64 bytes = (sizeof(FsNode) + len + 1 + 15) & ~15ull;
  if (a->at == NULL || (u64)(a->end - a->at) < bytes) {
    u64 n = bytes > FS_CHUNK ? bytes : FS_CHUNK;
    a->at  = fs_chunk(a->scan, n);
    a->end = a->at + n;
  }
  FsNode* n = (FsNode*)a->at;
  a->at += bytes;
  n->kids = NULL;
  n->next = NULL;
  n->size = 0;
  n->dir  = 0;
  n->len  = len;
  memcpy(n->name, name, len);
  n->name[len] = 0;
  return n;
}

// Hard links
// ----------

static u64 fs_hmix(u64 dev, u64 ino) {
  u64 h = (ino ^ (dev * 0x9E3779B97F4A7C15ull)) * 0xBF58476D1CE4E5B9ull;
  return (h ^ (h >> 31)) | 1;
}

// true when (dev, ino) was seen before; records it otherwise
static bool fs_hseen(FsScan* s, u64 dev, u64 ino) {
  pthread_mutex_lock(&s->hlock);
  if (s->hcap == 0 || s->hlen * 2 >= s->hcap) {
    u64  cap = s->hcap == 0 ? 1024 : s->hcap * 2;
    u64* set = io_mem(calloc(cap * 2, sizeof(u64)));
    for (u64 i = 0; i < s->hcap; i += 1) {
      if (s->hset[2 * i] != 0) {
        u64 j = fs_hmix(s->hset[2 * i + 1], s->hset[2 * i]) & (cap - 1);
        while (set[2 * j] != 0) {
          j = (j + 1) & (cap - 1);
        }
        set[2 * j]     = s->hset[2 * i];
        set[2 * j + 1] = s->hset[2 * i + 1];
      }
    }
    free(s->hset);
    s->hset = set;
    s->hcap = cap;
  }
  u64 key = ino == 0 ? ~0ull : ino;
  u64 j   = fs_hmix(dev, key) & (s->hcap - 1);
  bool seen = false;
  for (;;) {
    if (s->hset[2 * j] == 0) {
      s->hset[2 * j]     = key;
      s->hset[2 * j + 1] = dev;
      s->hlen += 1;
      break;
    }
    if (s->hset[2 * j] == key && s->hset[2 * j + 1] == dev) {
      seen = true;
      break;
    }
    j = (j + 1) & (s->hcap - 1);
  }
  pthread_mutex_unlock(&s->hlock);
  return seen;
}

// Walk
// ----

static char* fs_join(const char* dir, u64 dn, const char* name, u32 nn) {
  bool  slash = dn > 0 && dir[dn - 1] == '/';
  char* p = io_mem(malloc(dn + 1 + nn + 1));
  memcpy(p, dir, dn);
  if (!slash) {
    p[dn++] = '/';
  }
  memcpy(p + dn, name, nn);
  p[dn + nn] = 0;
  return p;
}

static u64 fs_size_of(FsScan* s, const struct statx* st) {
  return s->flags & FS_APPARENT ? st->stx_size : (u64)st->stx_blocks * 512;
}

static void fs_push(FsScan* s, FsTask* head, FsTask* tail, u64 n) {
  pthread_mutex_lock(&s->lock);
  tail->next  = s->todo;
  s->todo     = head;
  s->pending += n;
  pthread_cond_broadcast(&s->bell);
  pthread_mutex_unlock(&s->lock);
}

static void fs_dir(FsScan* s, FsArena* a, char* buf, FsTask* t) {
  FsNode* node = t->node;
  int     fd   = open(t->path, O_RDONLY | O_DIRECTORY | O_CLOEXEC
    | (t->root ? 0 : O_NOFOLLOW));
  if (fd < 0) {
    atomic_fetch_add(&s->errors, 1);
    return;
  }
  u64     dn   = strlen(t->path);
  FsNode* last = NULL;
  FsTask* head = NULL;
  FsTask* tail = NULL;
  u64     n    = 0;
  for (;;) {
    long got = syscall(SYS_getdents64, fd, buf, FS_BUF);
    if (got <= 0) {
      if (got < 0) {
        atomic_fetch_add(&s->errors, 1);
      }
      break;
    }
    for (long off = 0; off < got;) {
      struct dirent64* d = (struct dirent64*)(buf + off);
      off += d->d_reclen;
      const char* nm = d->d_name;
      if (nm[0] == '.' && (nm[1] == 0 || (nm[1] == '.' && nm[2] == 0))) {
        continue;
      }
      u32 len = (u32)strlen(nm);
      struct statx st;
      bool ok = statx(fd, nm, AT_SYMLINK_NOFOLLOW | AT_NO_AUTOMOUNT
        | AT_STATX_DONT_SYNC, STATX_TYPE | STATX_NLINK | STATX_INO
        | STATX_SIZE | STATX_BLOCKS, &st) == 0;
      FsNode* k = fs_node(a, nm, len);
      u64     dev = 0;
      if (ok) {
        k->dir  = S_ISDIR(st.stx_mode);
        k->size = fs_size_of(s, &st);
        dev     = makedev(st.stx_dev_major, st.stx_dev_minor);
        if (!k->dir && st.stx_nlink > 1 && !(s->flags & FS_LINKS)
          && fs_hseen(s, dev, st.stx_ino)) {
          k->size = 0;
        }
      } else {
        atomic_fetch_add(&s->errors, 1);
        k->dir = d->d_type == DT_DIR;
      }
      if (last == NULL) {
        node->kids = k;
      } else {
        last->next = k;
      }
      last = k;
      if (k->dir && (ok && (dev == s->root_dev || (s->flags & FS_CROSS)))) {
        FsTask* task = io_mem(malloc(sizeof *task));
        task->node = k;
        task->path = fs_join(t->path, dn, nm, len);
        task->root = 0;
        task->next = head;
        head = task;
        if (tail == NULL) {
          tail = task;
        }
        n += 1;
      }
    }
  }
  close(fd);
  if (n > 0) {
    fs_push(s, head, tail, n);
  }
}

static void* fs_worker(void* arg) {
  FsScan* s   = arg;
  FsArena a   = { NULL, NULL, s };
  char*   buf = io_mem(malloc(FS_BUF));
  for (;;) {
    pthread_mutex_lock(&s->lock);
    while (s->todo == NULL && s->pending > 0) {
      pthread_cond_wait(&s->bell, &s->lock);
    }
    FsTask* t = s->todo;
    if (t == NULL) {
      pthread_mutex_unlock(&s->lock);
      break;
    }
    s->todo = t->next;
    pthread_mutex_unlock(&s->lock);
    fs_dir(s, &a, buf, t);
    free(t->path);
    free(t);
    pthread_mutex_lock(&s->lock);
    s->pending -= 1;
    if (s->pending == 0) {
      pthread_cond_broadcast(&s->bell);
    }
    pthread_mutex_unlock(&s->lock);
  }
  free(buf);
  return NULL;
}

// The helper thread's part: the whole walk.
static void scan_call(IoWork* w) {
  FsScan* s    = (FsScan*)w->data;
  char*   path = w->text;
  u64     n    = strlen(path);
  while (n > 1 && path[n - 1] == '/') {
    path[--n] = 0;
  }
  struct statx st;
  if (statx(AT_FDCWD, path, AT_NO_AUTOMOUNT | AT_STATX_DONT_SYNC, STATX_TYPE
    | STATX_SIZE | STATX_BLOCKS, &st) != 0) {
    w->code = (u32)errno;
    return;
  }
  FsArena a    = { NULL, NULL, s };
  FsNode* root = fs_node(&a, path, (u32)n);
  root->size   = fs_size_of(s, &st);
  root->dir    = S_ISDIR(st.stx_mode);
  s->root      = root;
  s->root_dev  = makedev(st.stx_dev_major, st.stx_dev_minor);
  if (!root->dir) {
    return;
  }
  FsTask* t = io_mem(malloc(sizeof *t));
  t->node = root;
  t->path = io_mem(strdup(path));
  t->root = 1;
  t->next = NULL;
  s->todo    = t;
  s->pending = 1;
  u32 k = s->threads;
  pthread_t* tids = io_mem(malloc(k * sizeof(pthread_t)));
  for (u32 i = 0; i < k; i += 1) {
    if (pthread_create(&tids[i], NULL, fs_worker, s) != 0) {
      err_fail("pthread_create");
    }
  }
  for (u32 i = 0; i < k; i += 1) {
    pthread_join(tids[i], NULL);
  }
  free(tids);
  s->walked = io_tick();
}

// Pack
// ----

static Term fs_seal(Env e, Term t, bool hot) {
  return hot ? rfc_seal(e, t) : t;
}

static Term fs_term(Env e, FsNode* n, bool hot) {
  Term name = io_str(e, n->name, n->len);
  u64  size = n->size > NAT_IMM ? NAT_IMM : n->size;
  if (!n->dir) {
    Loc l = heap_alloc(e, cls_fit(2));
    e.mem[l]     = fs_seal(e, name, hot);
    e.mem[l + 1] = size;
    return term_ctr(CID_FSFILE, l);
  }
  // the chain is in scan order; a list conses from the end
  FsNode* rev = NULL;
  for (FsNode* k = n->kids; k != NULL;) {
    FsNode* nx = k->next;
    k->next = rev;
    rev = k;
    k = nx;
  }
  Term xs = term_pak(CID_NIL, 0);
  for (FsNode* k = rev; k != NULL; k = k->next) {
    xs = io_node(e, CID_CON, fs_term(e, k, hot), xs, IO_HOTS & 16);
  }
  Loc l = heap_alloc(e, cls_fit(3));
  e.mem[l]     = fs_seal(e, name, hot);
  e.mem[l + 1] = size;
  e.mem[l + 2] = fs_seal(e, xs, hot);
  return term_ctr(CID_FSDIR, l);
}

static void scan_free(FsScan* s) {
  for (u64 i = 0; i < s->nchunks; i += 1) {
    free(s->chunks[i]);
  }
  free(s->chunks);
  free(s->hset);
  pthread_mutex_destroy(&s->lock);
  pthread_mutex_destroy(&s->hlock);
  pthread_mutex_destroy(&s->alock);
  pthread_cond_destroy(&s->bell);
  free(s);
}

static Term scan_pack(Env e, IoWork* w) {
  FsScan* s = (FsScan*)w->data;
  Term r;
  if (w->code != 0) {
    r = io_fail(e, w->code, NULL);
  } else {
    bool hot  = w->word != 0;
    Term tree = fs_term(e, s->root, hot);
    u64  errs = atomic_load(&s->errors);
    r = io_done(e, io_tup(e, tree, errs > NAT_IMM ? NAT_IMM : errs));
    if (getenv("BENDIRSTAT_DEBUG") != NULL) {
      u64 packed = io_tick();
      fprintf(stderr, "fs_scan: %u threads, walk %llu ms, pack %llu ms, %s\n",
        s->threads, (unsigned long long)((s->walked - s->began) / 1000000),
        (unsigned long long)((packed - s->walked) / 1000000),
        hot ? "sealed" : "raw");
    }
  }
  free(w->text);
  scan_free(s);
  return r;
}

// Is Fs a shared type? The probe is an FsDir the program built on its
// heap: the emitter seals every field of a shared type's node.
static bool fs_probe_hot(Env e, Term probe) {
  Loc  l   = term_peek(e, probe);
  bool hot = term_rfc(e.mem[l]) || term_rfc(e.mem[l + 2]);
  term_sink(e, probe);
  return hot;
}

Term scan_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  w->text = io_cstr(e, f[0], &n);
  u32 threads = (u32)f[2];
  if (threads == 0) {
    long c = cpu_count();
    threads = c < 1 ? 1 : (u32)c;
  }
  w->word = fs_probe_hot(e, f[3]);
  if (io_nul(w->text, n) || n == 0) {
    free(w->text);
    return io_fail(e, EINVAL, "Fs.scan: an empty path or one with a NUL");
  }
  FsScan* s = io_mem(calloc(1, sizeof *s));
  pthread_mutex_init(&s->lock, NULL);
  pthread_mutex_init(&s->hlock, NULL);
  pthread_mutex_init(&s->alock, NULL);
  pthread_cond_init(&s->bell, NULL);
  s->flags   = (u32)f[1];
  s->threads = threads > 128 ? 128 : threads;
  s->began   = io_tick();
  w->data    = (char*)s;
  w->code    = 0;
  return io_work(w, scan_call, scan_pack);
}

static void __attribute__((constructor)) scan_use(void) {
  io_eff(CID_SCAN, scan_run, 0);
}
