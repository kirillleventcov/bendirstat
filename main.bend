# bendirstat: a disk usage analyzer in Bend.
#
#   bendirstat [path] [options]
#
# Scans the tree under path (the home directory by default) on every
# core, then prints where the space goes: the largest entries as a tree
# with bars, the largest files, and the space by extension. --gui opens
# a treemap of the tree.
#
#   bend main.bend -o bendirstat && ./bendirstat ~
import Base
import ./fs.bend as Fs
import ./fmt.bend as Fmt
import ./report.bend as Report
import ./treemap.bend as Treemap

# Options
# -------

type Opts is Data:
  Opts{path: String, depth: Nat, top: Nat, files: Nat, exts: Nat, flags: U32,
    threads: U32, color: Bool, gui: Bool, report: Bool, help: Bool, bad: String,
    snap: String}

def defaults(home: String) -> Opts:
  Opts{home, 2n, 12n, 15n, 12n, 0, 0, True{}, False{}, True{}, False{}, "", ""}

def usage() -> String:
  "bendirstat: where the disk space goes, fast.\n\n"
    ++ "usage: bendirstat [path] [options]\n\n"
    ++ "  path            the directory to scan (default: $HOME)\n"
    ++ "  --depth N       levels of the tree to print (default: 2)\n"
    ++ "  --top N         entries per directory to print (default: 12)\n"
    ++ "  --files N       largest files to print (default: 15)\n"
    ++ "  --exts N        extensions to print (default: 12)\n"
    ++ "  --apparent      apparent sizes, not allocated blocks\n"
    ++ "  --cross-fs      descend into other filesystems\n"
    ++ "  --links         count every hard link, not the first only\n"
    ++ "  --jobs N        scanner threads (default: one per CPU)\n"
    ++ "  --gui           open the treemap window\n"
    ++ "  --snapshot F    write the treemap as a PPM image to F\n"
    ++ "  --no-report     skip the text report\n"
    ++ "  --plain         no colors\n"
    ++ "  -h, --help      this text (the runtime keeps --help: use -h)\n"

# A token of the command line, classified so the parser can match it.
type Tok is Data:
  TDepth{}
  TTop{}
  TFiles{}
  TExts{}
  TApparent{}
  TCross{}
  TLinks{}
  TThreads{}
  TGui{}
  TNoReport{}
  TPlain{}
  THelp{}
  TSnap{}
  TNum{n: Nat}
  TText{s: String}

def tok.num(+s: String, m: Maybe<&2, Nat>) -> Tok:
  match m:
    case Some{n}:
      TNum{n}
    case None{}:
      TText{s}

def tok.13(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TSnap{}
    case False{}:
      tok.num(s, Nat.read(s))

def tok.12(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      THelp{}
    case False{}:
      tok.13(s, String.eq(s, "--snapshot"))

def tok.11(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TPlain{}
    case False{}:
      tok.12(s, Bool.or(String.eq(s, "--help"), String.eq(s, "-h")))

def tok.10(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TNoReport{}
    case False{}:
      tok.11(s, String.eq(s, "--plain"))

def tok.9(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TGui{}
    case False{}:
      tok.10(s, String.eq(s, "--no-report"))

def tok.8(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TThreads{}
    case False{}:
      tok.9(s, String.eq(s, "--gui"))

def tok.7(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TLinks{}
    case False{}:
      tok.8(s, String.eq(s, "--jobs"))

def tok.6(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TCross{}
    case False{}:
      tok.7(s, String.eq(s, "--links"))

def tok.5(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TApparent{}
    case False{}:
      tok.6(s, String.eq(s, "--cross-fs"))

def tok.4(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TExts{}
    case False{}:
      tok.5(s, String.eq(s, "--apparent"))

def tok.3(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TFiles{}
    case False{}:
      tok.4(s, String.eq(s, "--exts"))

def tok.2(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TTop{}
    case False{}:
      tok.3(s, String.eq(s, "--files"))

def tok.1(+s: String, hit: Bool) -> Tok:
  match hit:
    case True{}:
      TDepth{}
    case False{}:
      tok.2(s, String.eq(s, "--top"))

def tok(+s: String) -> Tok:
  tok.1(s, String.eq(s, "--depth"))

def parse(ts: List<Tok>, o: Opts) -> Opts:
  match ts o:
    case Nil{} Opts{path, depth, top, files, exts, flags, threads, color, gui,
      report, help, bad, snap}:
      Opts{path, depth, top, files, exts, flags, threads, color, gui, report,
        help, bad, snap}
    case TDepth{} <> TNum{n} <> rest Opts{path, depth, top, files, exts, flags,
      threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, n, top, files, exts, flags, threads, color, gui,
        report, help, bad, snap})
    case TTop{} <> TNum{n} <> rest Opts{path, depth, top, files, exts, flags,
      threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, n, files, exts, flags, threads, color, gui,
        report, help, bad, snap})
    case TFiles{} <> TNum{n} <> rest Opts{path, depth, top, files, exts, flags,
      threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, n, exts, flags, threads, color, gui,
        report, help, bad, snap})
    case TExts{} <> TNum{n} <> rest Opts{path, depth, top, files, exts, flags,
      threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, n, flags, threads, color, gui,
        report, help, bad, snap})
    case TThreads{} <> TNum{n} <> rest Opts{path, depth, top, files, exts,
      flags, threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, flags, U32.from_nat(n),
        color, gui, report, help, bad, snap})
    case TApparent{} <> rest Opts{path, depth, top, files, exts, flags,
      threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, (flags .|. 1 : U32),
        threads, color, gui, report, help, bad, snap})
    case TCross{} <> rest Opts{path, depth, top, files, exts, flags, threads,
      color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, (flags .|. 2 : U32),
        threads, color, gui, report, help, bad, snap})
    case TLinks{} <> rest Opts{path, depth, top, files, exts, flags, threads,
      color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, (flags .|. 4 : U32),
        threads, color, gui, report, help, bad, snap})
    case TGui{} <> rest Opts{path, depth, top, files, exts, flags, threads,
      color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, flags, threads, color,
        True{}, report, help, bad, snap})
    case TNoReport{} <> rest Opts{path, depth, top, files, exts, flags,
      threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, flags, threads, color,
        gui, False{}, help, bad, snap})
    case TPlain{} <> rest Opts{path, depth, top, files, exts, flags, threads,
      color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, flags, threads, False{},
        gui, report, help, bad, snap})
    case THelp{} <> rest Opts{path, depth, top, files, exts, flags, threads,
      color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, flags, threads, color,
        gui, report, True{}, bad, snap})
    case TSnap{} <> TText{s} <> rest Opts{path, depth, top, files, exts, flags,
      threads, color, gui, report, help, bad, snap}:
      parse(rest, Opts{path, depth, top, files, exts, flags, threads, color,
        gui, report, help, bad, s})
    case TText{s} <> rest Opts{path, depth, top, files, exts, flags, threads,
      color, gui, report, help, bad, snap}:
      parse(rest, Opts{s, depth, top, files, exts, flags, threads, color, gui,
        report, help, bad, snap})
    case TNum{n} <> rest Opts{path, depth, top, files, exts, flags, threads,
      color, gui, report, help, bad, snap}:
      parse(rest, Opts{Nat.show(n), depth, top, files, exts, flags, threads,
        color, gui, report, help, bad, snap})
    case t <> rest Opts{path, depth, top, files, exts, flags, threads, color,
      gui, report, help, bad, snap}:
      Opts{path, depth, top, files, exts, flags, threads, color, gui, report,
        help, "an option is missing its value; see --help", snap}

# Run
# ---

def section(+color: Bool, title: String) -> String:
  "\n" ++ Fmt.paint(color, "1", title) ++ "\n"

def unreadable(+color: Bool, +errors: Nat) -> String:
  match errors:
    case 0n:
      ""
    case 1n+p:
      Fmt.paint(color, "31", ", " ++ Nat.show(1n+p) ++ " unreadable")

def summary(
  +color: Bool, +sz: Nat, cs: Nat & Nat, +errors: Nat, +scan_ms: Nat,
  +prep_ms: Nat
) -> String:
  (files, dirs) = cs
  Fmt.paint(color, "1", Fmt.human(sz)) ++ " in " ++ Fmt.commas(files)
    ++ " files and " ++ Fmt.commas(dirs) ++ " directories"
    ++ Fmt.paint(color, "2", "  (scanned in " ++ Nat.show(scan_ms)
      ++ " ms, summed and sorted in " ++ Nat.show(prep_ms) ++ " ms")
    ++ unreadable(color, errors) ++ Fmt.paint(color, "2", ")")

def times(+color: Bool, +t1: Nat, +t2: Nat, +t3: Nat, +t4: Nat, +t5: Nat) ->
  String:
  Fmt.paint(color, "2", "report: tree " ++ Nat.show(Nat.sub(t3, t2))
    ++ " ms, files " ++ Nat.show(Nat.sub(t4, t3)) ++ " ms, extensions "
    ++ Nat.show(Nat.sub(t5, t4)) ++ " ms")

def show_report(
  on: Bool, +tree: Fs.Tree, errors: Nat, scan_ms: Nat, prep_ms: Nat, depth: Nat,
  top: Nat, files: Nat, exts: Nat, +color: Bool, +t2: Nat
) -> IO(Unit):
  match on:
    case True{}:
      do IO<Unit>:
        IO.print(summary(color, Fs.size(tree), Fs.count([tree]), errors, scan_ms,
          prep_ms) ++ section(color, "Largest entries")
          ++ Report.tree(tree, depth, top, color))
        +t3 : Nat <- IO.now()
        IO.print(section(color, "Largest files")
          ++ Report.files(tree, files, color))
        +t4 : Nat <- IO.now()
        IO.print(section(color, "By extension")
          ++ Report.extensions(tree, exts, color))
        +t5 : Nat <- IO.now()
        IO.print("\n" ++ times(color, t2, t2, t3, t4, t5))
    case False{}:
      IO.pure(Unit, Unit{})

def show_snap(tree: Fs.Tree, snap: String, none: Bool) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Treemap.snapshot(tree, snap)

def show_gui(on: Bool, tree: Fs.Tree) -> IO(Unit):
  match on:
    case True{}:
      Treemap.open(tree)
    case False{}:
      IO.pure(Unit, Unit{})

def analyze(
  scanned: Fs.Tree & Nat, t0: Nat, +t1: Nat, depth: Nat, top: Nat, files: Nat,
  exts: Nat, color: Bool, gui: Bool, report: Bool, +snap: String
) -> IO(Unit):
  (raw, errors) = scanned
  do IO<Unit>:
    +tree : Fs.Tree = Fs.prep(raw)
    +size : Nat = Fs.size(tree)
    +t2 : Nat <- IO.now()
    show_report(report, tree, errors, Nat.sub(t1, t0), Nat.sub(t2, t1), depth,
      top, files, exts, color, t2)
    show_snap(tree, snap, String.is_empty(snap))
    show_gui(gui, tree)

# the scan's answer, or the failure named after the path
def scanned(
  +path: String, r: Result<&1, &1, U32 & String, Fs.Tree & Nat>
) -> IO(Fs.Tree & Nat):
  match r:
    case Done{v}:
      IO.pure(Fs.Tree & Nat, v)
    case Fail{(code, msg)}:
      IO.die(Fs.Tree & Nat, 1, "bendirstat: " ++ path ++ ": " ++ msg)

def run.scan(
  +path: String, depth: Nat, top: Nat, files: Nat, exts: Nat, flags: U32,
  threads: U32, color: Bool, gui: Bool, report: Bool, snap: String
) -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    r : Result<&1, &1, U32 & String, Fs.Tree & Nat> <- Fs.scan(path, flags,
      threads, Fs.probe(1n+t0))
    got : Fs.Tree & Nat <- scanned(path, r)
    t1 : Nat <- IO.now()
    analyze(got, t0, t1, depth, top, files, exts, color, gui, report, snap)

def run.go(o: Opts, stop: Bool) -> IO(Unit):
  match o stop:
    case Opts{path, depth, top, files, exts, flags, threads, color, gui, report,
      help, +bad, snap} True{}:
      IO.print(usage() ++ Fmt.paint(Bool.not(String.is_empty(bad)), "31", bad))
    case Opts{path, depth, top, files, exts, flags, threads, color, gui, report,
      help, bad, snap} False{}:
      run.scan(path, depth, top, files, exts, flags, threads, color, gui, report,
        snap)

def run(o: Opts) -> IO(Unit):
  Opts{path, depth, top, files, exts, flags, threads, color, gui, report, +help,
    +bad, snap} = o
  run.go(Opts{path, depth, top, files, exts, flags, threads, color, gui, report,
    help, bad, snap}, Bool.or(help, Bool.not(String.is_empty(bad))))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    home : Result<&1, &1, U32 & String, String> <- IO.get_env("HOME")
    run(parse(List.map(~String, ~Tok, ~(s => tok(s)), args),
      defaults(Result.default(&1, &1, U32 & String, String, home, "."))))
