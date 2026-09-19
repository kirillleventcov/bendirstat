# fs.bend: the scanned tree and the pure work over it.
#
# A Tree is a file with its size or a directory with its own inode size
# and its entries, as the scanner lays it. sum turns every directory's
# size into the total under it, in parallel over the tree; sort orders
# every directory's entries by size, descending. total is the sequential
# spec that LAWS.bend holds sum to. Sizes are bytes, as Nat (native up
# to 2^48 - 1: 256 TiB).
import Base

# Tree
# ----

type Tree is Data:
  FsFile{name: String, size: Nat}
  FsDir{name: String, size: Nat, kids: List<&2, Tree>}

# scan(path, flags, threads, probe): the tree under path beside the
# count of entries it could not read. flags: 1 apparent sizes (else
# allocated blocks), 2 cross filesystems, 4 count every hard link (else
# the first only). threads: 0 for one per CPU. probe: an FsDir the
# program built at runtime, by which the C side learns whether Tree is
# a shared type (see effs/fs_scan.c).
def scan(path: String, flags: U32, threads: U32, probe: Tree) ->
  IO(Result<&1, &1, U32 & String, Tree & Nat>):
  import "./effs/fs_scan.c"
  import "./effs/fs_scan.js"

def probe(+n: Nat) -> Tree:
  FsDir{Nat.show(n), n, [FsFile{Nat.show(n), n}]}

def size(t: Tree) -> Nat:
  match t:
    case FsFile{nm, sz}:
      sz
    case FsDir{nm, sz, ks}:
      sz

def name(t: Tree) -> String:
  match t:
    case FsFile{nm, sz}:
      nm
    case FsDir{nm, sz, ks}:
      nm

def is_dir(t: Tree) -> Bool:
  match t:
    case FsFile{nm, sz}:
      False{}
    case FsDir{nm, sz, ks}:
      True{}

def kids(t: Tree) -> List<&2, Tree>:
  match t:
    case FsFile{nm, sz}:
      Nil{}
    case FsDir{nm, sz, ks}:
      ks

# Sizes
# -----

# the sizes at the top of a list, added up
def top(xs: List<&2, Tree>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case h <> t:
      Nat.add(size(h), top(t))

# spec: every byte under a list, sequentially
def total(xs: List<&2, Tree>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case FsFile{nm, sz} <> t:
      Nat.add(sz, total(t))
    case FsDir{nm, sz, ks} <> t:
      Nat.add(Nat.add(sz, total(ks)), total(t))

def sum.dir(nm: String, sz: Nat, +ks: List<&2, Tree>, rest: List<&2, Tree>) ->
  List<&2, Tree>:
  FsDir{nm, Nat.add(sz, top(ks)), ks} <> rest

# every directory's size becomes the total under it; the entries of a
# directory and the rest of its list are summed in parallel
def sum(xs: List<&2, Tree>) -> List<&2, Tree>:
  match xs:
    case Nil{}:
      Nil{}
    case FsFile{nm, sz} <> t:
      FsFile{nm, sz} <> sum(t)
    case FsDir{nm, sz, ks} <> t:
      a b = sum(ks) sum(t)
      sum.dir(nm, sz, a, b)

# the names at the top of a list, in order
def names(xs: List<&2, Tree>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      name(h) <> names(t)

# Counts
# ------

# spec: the files under a list, sequentially
def files(xs: List<&2, Tree>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case FsFile{nm, sz} <> t:
      1n+files(t)
    case FsDir{nm, sz, ks} <> t:
      Nat.add(files(ks), files(t))

# spec: the directories under a list, sequentially
def dirs(xs: List<&2, Tree>) -> Nat:
  match xs:
    case Nil{}:
      0n
    case FsFile{nm, sz} <> t:
      dirs(t)
    case FsDir{nm, sz, ks} <> t:
      1n+Nat.add(dirs(ks), dirs(t))


# files and directories under a list, as a pair, in parallel
def count.file(r: Nat & Nat) -> Nat & Nat:
  (f, d) = r
  (1n+f, d)

def count.dir(a: Nat & Nat, b: Nat & Nat) -> Nat & Nat:
  (af, ad) = a
  (bf, bd) = b
  (Nat.add(af, bf), 1n+Nat.add(ad, bd))

def count(xs: List<&2, Tree>) -> Nat & Nat:
  match xs:
    case Nil{}:
      (0n, 0n)
    case FsFile{nm, sz} <> t:
      count.file(count(t))
    case FsDir{nm, sz, ks} <> t:
      a b = count(ks) count(t)
      count.dir(a, b)

# Order
# -----

def ge(a: Tree, b: Tree) -> Bool:
  Nat.is_ge(size(a), size(b))

# every directory's entries ordered by size, descending, in parallel
def sort(xs: List<&2, Tree>) -> List<&2, Tree>:
  match xs:
    case Nil{}:
      Nil{}
    case FsFile{nm, sz} <> t:
      FsFile{nm, sz} <> sort(t)
    case FsDir{nm, sz, ks} <> t:
      a b = sort(ks) sort(t)
      FsDir{nm, sz, List.sort(~Tree, ~ge, a)} <> b

# the scanned root, summed and sorted
def prep.dir(nm: String, sz: Nat, +ks: List<&2, Tree>) -> Tree:
  FsDir{nm, Nat.add(sz, top(ks)), List.sort(~Tree, ~ge, ks)}

def prep(t: Tree) -> Tree:
  match t:
    case FsFile{nm, sz}:
      FsFile{nm, sz}
    case FsDir{nm, sz, ks}:
      prep.dir(nm, sz, sort(sum(ks)))

# Lookup
# ------

# the entry at an index of a list, or nothing
def at(xs: List<&2, Tree>, i: Nat) -> Maybe<&2, Tree>:
  List.get(&2, Tree, xs, i)

# the entry down a path of indexes from a tree, or nothing
def walk(path: List<&2, Nat>, t: Tree) -> Maybe<&2, Tree>:
  match path:
    case Nil{}:
      Some{t}
    case i <> rest:
      Maybe.bind(&2, Tree, Tree, at(kids(t), i), u => walk(rest, u))
