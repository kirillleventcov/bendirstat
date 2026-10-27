// scan on the JS lane: one thread, readdirSync and lstatSync, the same
// tree as the C: FsFile{name, size} and FsDir{name, size, kids}, sizes as
// numbers (exact to 2^53), names as Fs.Name (the UTF-8 bytes, six to a
// number, the first byte highest). Flags: 1 apparent sizes, 2 cross
// filesystems, 4 count every hard link. The probe,
// FsDir{NMore{_, NEnd{}}, _, [FsFile{_, _}]}, gives the tags. Answers the
// tree beside the count of unreadable entries. Paths are Buffers, so a
// name that is not UTF-8 keeps its bytes and still opens, as on the C side.
function scan(path, flags, threads, probe) {
  const DIR  = probe.$;
  const FILE = probe.kids.head.$;
  const MORE = probe.name.$;
  const END  = probe.name.rest.$;
  const named = (b) => {
    let nm = { $: END };
    for (let i = Math.ceil(b.length / 6); i > 0; i -= 1) {
      let c = 0;
      for (let j = (i - 1) * 6; j < Math.min(i * 6, b.length); j += 1) {
        c = c * 256 + b[j];
      }
      nm = { $: MORE, bytes: c, rest: nm };
    }
    return nm;
  };
  const fs = require("fs");
  const slash = Buffer.from("/");
  const join  = (dir, nm) => Buffer.concat(
    dir[dir.length - 1] === 47 ? [dir, nm] : [dir, slash, nm]);
  const apparent = (flags & 1) !== 0;
  const cross    = (flags & 2) !== 0;
  const links    = (flags & 4) !== 0;
  const seen     = new Set();
  let   errors   = 0;
  const size = (st) => apparent ? st.size : st.blocks * 512;
  const list = (items) => {
    let xs = { $: CID(Nil) };
    for (let i = items.length; i > 0; i -= 1) {
      xs = { $: CID(Con), head: items[i - 1], tail: xs };
    }
    return xs;
  };
  let root_dev = 0;
  const walk = (dir, name, own) => {
    const items = [];
    let names;
    try {
      names = fs.readdirSync(dir, { encoding: "buffer" });
    } catch (e) {
      errors += 1;
      return { $: DIR, name: named(name), size: own, kids: list(items) };
    }
    for (const nm of names) {
      const full = join(dir, nm);
      let st;
      try {
        st = fs.lstatSync(full);
      } catch (e) {
        errors += 1;
        items.push({ $: FILE, name: named(nm), size: 0 });
        continue;
      }
      if (st.isDirectory()) {
        if (st.dev === root_dev || cross) {
          items.push(walk(full, nm, size(st)));
        } else {
          items.push({ $: DIR, name: named(nm), size: size(st), kids: list([]) });
        }
      } else {
        let sz = size(st);
        if (st.nlink > 1 && !links) {
          const key = st.dev + ":" + st.ino;
          if (seen.has(key)) {
            sz = 0;
          } else {
            seen.add(key);
          }
        }
        items.push({ $: FILE, name: named(nm), size: sz });
      }
    }
    return { $: DIR, name: named(name), size: own, kids: list(items) };
  };
  let clean = path;
  while (clean.length > 1 && clean.endsWith("/")) {
    clean = clean.slice(0, -1);
  }
  let st;
  try {
    st = fs.statSync(clean);
  } catch (e) {
    return io_fail(Math.abs(e.errno ?? 2));
  }
  root_dev = st.dev;
  const root = Buffer.from(clean, "utf8");
  const tree = st.isDirectory() ? walk(root, root, size(st))
    : { $: FILE, name: named(root), size: size(st) };
  return io_done({ $: CID(Tuple), fst: tree, snd: errors });
}

io_eff(CID(scan), scan);
