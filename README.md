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

Bend 2 (`curl -fsSL https://bend-lang.com/install.sh | sh`) and clang 14+.
On Linux the treemap window needs `libx11-dev`.

```
bend main.bend -o bendirstat     # build the native binary
./bendirstat                     # scan $HOME and print the report
./bendirstat /usr/share --gui    # scan a path and open the treemap
bend PROOF.bend                  # check the laws: "All terms check."
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
fs.bend        the tree, the scanner effect, and the parallel folds over it
report.bend    the text report: the tree with bars, largest files, extensions
treemap.bend   the layout, the quadtree rasterizer, and the window loop
fmt.bend       sizes, shares, bars, colors
main.bend      the command line
effs/          the scanner effect: fs_scan.c (native) and fs_scan.js
LAWS.bend      the claims about the parallel folds
PROOF.bend     their proofs
```

**Scanning** is a foreign effect, `Fs.scan`, written in C the way Base's own
effects are. A pool of threads (one per CPU) works a shared stack of
directories: each thread opens one, lists it with `getdents64`, asks `statx`
for every entry, appends the entries to an arena and pushes the
subdirectories. The finished arena is laid out as Bend terms on the event
loop's thread: `FsFile{name, size}` and `FsDir{name, size, kids}`, sizes as
native `Nat` immediates, so a 338 GiB tree needs no bignums. Bend's runtime
refcounts a type only when the program shares it, and reads it raw
otherwise; the effect takes a probe node built by the program and inspects
its fields to learn which, so the C stays right whatever the Bend side does
with the tree.

**Everything after the scan is pure Bend.** `sum` gives every directory the
total under it and `sort` orders every directory's entries by size, both as
fork-join folds: a directory's entries and the rest of its list are handled
by a parallel let, so the runtime spreads the tree over every core. The
report's largest-files pass keeps a bounded ordered list per subtree and
merges them up the tree, again in parallel; the extension tally packs each
extension into one `Nat` (six bits a character) and counts in in-place
arrays, so no string is built per file. The treemap layout and the frame are
parallel the same way.

**The laws** pin the parallel folds to sequential specifications, in the
style of Bend's `pure_par_sum` demo:

- `sum_is_total`: the sizes at the top of a summed list add up to the
  sequential total of every byte under it;
- `sum_keeps_names`: summing keeps the entries, in order;
- `count_is_spec`: the parallel count is the sequential count of files and
  directories.

`bend PROOF.bend` fails while any law is open or false.

## Numbers

Home directory, 1,867,846 files and 188,236 directories, 338 GiB, warm cache,
16 threads:

| step                                  | time    |
|---------------------------------------|---------|
| walk (C, 16 threads)                  | 300 ms  |
| lay the tree out as Bend terms        | 200 ms  |
| sum and sort (Bend, parallel)         | 520 ms  |
| report: tree, files, extensions       | 800 ms  |
| `du -s ~` for comparison              | 3150 ms |

Peak memory is about 950 MiB for that tree, roughly 450 bytes an entry, most
of it the names (Bend strings are lists of characters).
