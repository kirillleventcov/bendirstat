# bendirstat

A disk usage analyzer written in [Bend](https://bend-lang.com): it scans a
directory tree on every core, sums and sorts it in parallel, prints where the
space goes, and draws a treemap you can zoom into. Think `qdirstat` or `dust`,
with the pure parts formally specified in `LAWS.bend` and proven in
`PROOF.bend`.

```
$ bendirstat ~
338.1 GiB in 1,867,846 files and 188,236 directories  (scanned in 509 ms, summed and sorted in 525 ms)

Largest entries
 338.1 GiB ████████████ 100.0%  /home/user/
 182.7 GiB ██████░░░░░░  54.0%  ├── media/
  82.2 GiB ██░░░░░░░░░░  24.3%  ├── .local/
  40.9 GiB █░░░░░░░░░░░  12.1%  ├── src/
   ...
Largest files
   9.8 GiB   2.9%  /home/user/.local/share/.../assets.bin
   ...
By extension
  55.7 GiB  16.4%     214,554  (none)
  15.5 GiB   4.6%      53,248  dll
   ...
```

On a 16-thread desktop with an NVMe drive and a warm page cache, the whole run on a home
directory of 1.87 million files takes about 2 seconds; `du -s` alone takes 3.2
seconds on the same tree.

## Build and run

Bend 2.0.39 or newer (`curl -fsSL https://bend-lang.com/install.sh | sh`)
and clang 14+. On Linux the treemap window needs `libx11-dev`. The scanner
uses the runtime's internals, which carry no ABI promise between Bend
releases: rebuild after every `bend update`.

```
bend main.bend -o bendirstat     # build the native binary
./bendirstat                     # scan $HOME and print the report
./bendirstat /usr/share --gui    # scan a path and open the treemap
bend PROOF.bend                  # check the laws: "ALL PROOFS CHECK"
bend PROOF.bend --verdict        # recheck with the Lean kernel (Lean 4.34)
```

`bend main.bend -- <path>` runs the JavaScript lane instead of building; it
is fine for small trees but its scanner is single-threaded and the deep
recursion over a million-entry tree overflows the JS stack, so build the
binary for real use.

## Options

```
bendirstat [path] [options]

  path            the directory to scan (default: $HOME)
  --depth N       levels of the tree to print (default: 2)
  --top N         entries per directory to print (default: 12)
  --files N       largest files to print (default: 15)
  --exts N        extensions to print (default: 12)
  --apparent      apparent sizes, not allocated blocks
  --cross-fs      descend into other filesystems
  --links         count every hard link, not the first only
  --jobs N        scanner threads (default: one per CPU)
  --gui           open the treemap window
  --snapshot F    write the treemap as a PPM image to F
  --no-report     skip the text report
  --plain         no colors
  -h              this text (the runtime keeps --help for itself)
```

Sizes are allocated blocks (what `df` sees), like `du`; `--apparent` switches
to file lengths (`du -b`). Mount points are shown but not entered unless
`--cross-fs`, as in QDirStat. A file with several hard links is counted once.
The runtime keeps its own flags (`--threads`, `--gpu`, `--help`), which is
why the scanner's is `--jobs` and the tool's help is `-h`. `BENDIRSTAT_DEBUG=1` prints the scanner's walk and
pack times.

## The treemap

`--gui` opens a 1280x800 window. Every file is a box, colored by extension;
directories are opened into their entries as long as there is room. Hover
shows the entry under the pointer with its size and share in the title;
a left click zooms into the top-level directory under the pointer; a right
click, Backspace or Up zooms out; Esc or closing the window quits.

The layout is a size-balanced binary split: a directory's entries, sorted by
size, are cut where the running size passes half, and the box is cut along
its longer side in the same ratio; the two halves are laid out in parallel,
down to one entry a box. The frame is Bend's `Image` quadtree: each cell
carries the boxes that touch it, a directory holding a cell is opened into
its entries, and a cell inside one file's box (or none) is a single pixel
block, so the whole frame forks four ways per level on every core.

`--snapshot out.ppm` writes the same image headless (convert it with
`magick out.ppm out.png`).

## How it works

```
fs.bend        the tree, names, and the parallel folds over it
scan.bend      the scanner effect (apart, so the proofs import no foreign code)
report.bend    the text report: the tree with bars, largest files, extensions
treemap.bend   the layout, the quadtree rasterizer, and the window loop
fmt.bend       sizes, shares, bars, colors
main.bend      the command line
effs/          the scanner effect: fs_scan.c (native) and fs_scan.js
LAWS.bend      the claims about the parallel folds
PROOF.bend     their proofs
```

**Scanning** is a foreign effect, `Scan.scan`, written in C the way Base's own
effects are. A pool of threads (one per CPU) works a shared stack of
directories: each thread opens one, lists it with `getdents64`, asks `statx`
for every entry, appends the entries to an arena and pushes the
subdirectories. The finished arena is laid out as Bend terms on the event
loop's thread: `FsFile{name, size}` and `FsDir{name, size, kids}`, sizes as
native `Nat` immediates (up to 256 TiB). A name is an `Fs.Name`: its UTF-8
bytes, six to a native `Nat`, a cell per six bytes where a `String` costs a
cell and a reference count per character; it is decoded to text only for
the rows printed. Bend's runtime refcounts a constructor only when the
program shares it, and the compiler records which; the effect follows that
record. `CID()` in an effect names only its own module's and Base's
constructors, so the program passes a probe value, and the effect reads the
tags of `FsFile`, `FsDir` and the name cells off it.

**Everything after the scan is pure Bend.** `tidy` gives every directory the
total under it and orders its entries by size in one fork-join pass (the
law `tidy_is_sort_sum` holds it to `sort` after `sum`): a directory's
entries and the rest of its list are handled by a parallel let, so the
runtime spreads the tree over every core. The report's largest-files pass
keeps a bounded ordered list per subtree and merges them up the tree, again
in parallel, carrying each file's directories as a shared chain of names,
so a path is built only for the rows printed. The extension tally reads
each name backwards from its end to the last dot (most names are touched
for a few bytes), packs the extension into one `Nat` (six bits a
character), and counts in a trie on that code, two bits a level: an empty
tally is free and two merge in the time of the smaller, so every directory
forks. The treemap layout and the frame are parallel the same way.

**The laws** pin the parallel folds to sequential specifications, in the
style of Bend's `pure_par_sum` demo:

- `sum_is_total`: the sizes at the top of a summed list add up to the
  sequential total of every byte under it;
- `sum_keeps_names`: summing keeps the entries, in order;
- `sum_keeps_shape`: summing changes nothing but sizes, at every depth;
- `tidy_is_sort_sum`: the fused pass `prep` runs is `sort` after `sum`;
- `count_is_spec`: the parallel count is the sequential count of files and
  directories.

`bend PROOF.bend` fails while any law is open or false.

## Numbers

Home directory, 1,867,846 files and 188,236 directories, 338 GiB, warm cache,
16 threads, measured before the packed names and the fused pass:

| step                                  | time    |
|---------------------------------------|---------|
| walk (C, 16 threads)                  | 300 ms  |
| lay the tree out as Bend terms        | 200 ms  |
| sum and sort (Bend, parallel)         | 520 ms  |
| report: tree, files, extensions       | 800 ms  |
| `du -s ~` for comparison              | 3150 ms |

Peak memory was about 950 MiB for that tree, roughly 450 bytes an entry,
most of it the names as Strings.

A synthetic tree of 954,561 files and 45,449 directories in tmpfs, 4 vCPUs,
Bend 2.0.39, before and after the packed names, the fused pass and the
extension trie (typical of four runs each):

| step                                  | before        | after   |
|---------------------------------------|---------------|---------|
| walk (C, 4 threads, unchanged)        | 440-530 ms    | same    |
| lay the tree out as Bend terms        | 260-1600 ms   | 100 ms  |
| sum and sort                          | 130 ms        | 46 ms   |
| report: tree                          | 65 ms         | 28 ms   |
| report: largest files                 | 150 ms        | 60 ms   |
| report: extensions                    | 440 ms        | 80 ms   |
| whole run, wall clock                 | 2.2-3.2 s     | 1.0 s   |
| peak memory                           | 477 MiB       | 170 MiB |

`du -s` takes 1.7 s on the same tree.
