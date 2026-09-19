// Fs.scan on the JS lane: one thread, readdirSync and lstatSync, the same
// tree as the C: FsFile{name, size} and FsDir{name, size, kids}, sizes as
// BigInt. Flags: 1 apparent sizes, 2 cross filesystems, 4 count every
// hard link. Answers the tree beside the count of unreadable entries.
function scan(path, flags, threads, probe) {
  const fs = require("fs");
  const p  = require("path");
  const apparent = (flags & 1) !== 0;
  const cross    = (flags & 2) !== 0;
  const links    = (flags & 4) !== 0;
  const seen     = new Set();
  let   errors   = 0n;
  const size = (st) => BigInt(apparent ? st.size : st.blocks * 512);
  const list = (items) => {
    let xs = { $: "Nil" };
    for (let i = items.length; i > 0; i -= 1) {
      xs = { $: "Con", head: items[i - 1], tail: xs };
    }
    return xs;
  };
  let root_dev = 0;
  const walk = (dir, name, own) => {
    const items = [];
    let names;
    try {
      names = fs.readdirSync(dir);
    } catch (e) {
      errors += 1n;
      return { $: "FsDir", name, size: own, kids: list(items) };
    }
    for (const nm of names) {
      const full = p.join(dir, nm);
      let st;
      try {
        st = fs.lstatSync(full);
      } catch (e) {
        errors += 1n;
        items.push({ $: "FsFile", name: nm, size: 0n });
        continue;
      }
      if (st.isDirectory()) {
        if (st.dev === root_dev || cross) {
          items.push(walk(full, nm, size(st)));
        } else {
          items.push({ $: "FsDir", name: nm, size: size(st), kids: list([]) });
        }
      } else {
        let sz = size(st);
        if (st.nlink > 1 && !links) {
          const key = st.dev + ":" + st.ino;
          if (seen.has(key)) {
            sz = 0n;
          } else {
            seen.add(key);
          }
        }
        items.push({ $: "FsFile", name: nm, size: sz });
      }
    }
    return { $: "FsDir", name, size: own, kids: list(items) };
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
  const tree = st.isDirectory() ? walk(clean, clean, size(st))
    : { $: "FsFile", name: clean, size: size(st) };
  return io_done({ $: "Tuple", fst: tree, snd: errors });
}
