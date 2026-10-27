# treemap.bend: the treemap window.
#
# The layout splits a directory's entries (sorted by size) in two where
# the running size passes half, and its box along the longer side in
# the same ratio, down to one entry a box; a subdirectory's box is laid
# out the same way inside, when it is big enough to show anything. The
# two halves are laid out in parallel. The frame is an Image quadtree:
# a cell carries the boxes that touch it, a box that holds a cell is
# opened into its entries, and a cell inside one file's box (or none)
# is a single Pix. Hover shows the entry under the pointer in the
# title; a click zooms into the top-level entry under it; a right
# click, Backspace or Up zooms out; Esc or Close quits.
import Base
import ./fs.bend as Fs
import ./fmt.bend as Fmt
import ./report.bend as Report

# Layout
# ------

# A laid-out entry: pixel bounds (x1, y1 exclusive), its index among
# its directory's entries, its name and size; a directory holds the
# layout of its entries, none when its box was too small.
type Lay is Data:
  LFile{x0: U32, y0: U32, x1: U32, y1: U32, idx: Nat, name: Fs.Name, size: Nat,
    color: U32}
  LDir{x0: U32, y0: U32, x1: U32, y1: U32, idx: Nat, name: Fs.Name, size: Nat,
    kids: List<&2, Lay>}

def width() -> U32:
  1280

def height() -> U32:
  800

# the quadtree covers 2048 x 2048
def depth() -> Nat:
  11n

def levels() -> Nat:
  24n

def bg() -> U32:
  1710618

def dir_color() -> U32:
  5000268

# the palette, by extension
def palette(i: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, [5011624, 16090392, 14964054,
    7518130, 5546059, 15649339, 11696546, 16752038, 10319197, 12234924,
    3902387, 14053781, 8759272, 15702058, 4166848, 12496307], i), 8421504)

# a shade of c: its channels scaled by num / den
def channel(+c: U32, +shift: Nat, +num: U32, +den: U32) -> U32:
  U32.shln(U32.min(255, U32.div(U32.mul(U32.and(U32.shrn(c, shift), 255), num),
    den)), shift)

def shade(+c: U32, +num: U32, +den: U32) -> U32:
  U32.or(channel(c, 16n, num, den),
    U32.or(channel(c, 8n, num, den), channel(c, 0n, num, den)))

# a small hash of a name's bytes, to vary the shade of like files
def hash.go(bs: List<&2, Nat>, +h: U32) -> U32:
  match bs:
    case Nil{}:
      h
    case b <> t:
      hash.go(t, U32.add(U32.mul(h, 31), U32.from_nat(b)))

def color_of(nm: Fs.Name) -> U32:
  +n = nm
  +h = hash.go(Fs.bytes(n), 7)
  shade(palette(Nat.mod(Nat.add(Report.ext.of(n), U32.to_nat(h)), 16n)),
    U32.add(13, U32.mod(U32.shrn(h, 8n), 5)), 15)

# a size as F32, for ratios
def f32(+n: Nat) -> F32:
  Bool.pick(F32, Nat.is_le(n, 4294967295n), U32.to_f32(U32.from_nat(n)),
    F32.mul(U32.to_f32(U32.from_nat(Nat.div(n, 65536n))), 65536.0))

def px(f: F32) -> U32:
  F32.to_u32(F32.round(f))

# The cut of a sorted list: the entries up to where the running size
# passes half, their size and count, and the rest with its size.
type Cut is Data:
  Cut{left: List<&2, Fs.Tree>, lsum: Nat, llen: Nat, right: List<&2, Fs.Tree>,
    rsum: Nat}

# stop says the head starts the right part
def cut.go(
  items: List<&2, Fs.Tree>, +half: Nat, +total: Nat, +acc: Nat, +len: Nat,
  left: List<&2, Fs.Tree>, stop: Bool
) -> Cut:
  match items:
    case Nil{}:
      Cut{List.reverse(&2, Fs.Tree, left), acc, len, Nil{}, Nat.sub(total, acc)}
    case +h <> t:
      match stop:
        case True{}:
          Cut{List.reverse(&2, Fs.Tree, left), acc, len, h <> t, Nat.sub(total, acc)}
        case False{}:
          +acc2 = Nat.add(acc, Fs.size(h))
          cut.go(t, half, total, acc2, 1n+len, h <> left, Nat.is_ge(acc2, half))

def cut(items: List<&2, Fs.Tree>, +total: Nat) -> Cut:
  cut.go(items, Nat.div(total, 2n), total, 0n, 0n, Nil{}, False{})

def cut.left(c: Cut) -> List<&2, Fs.Tree>:
  match c:
    case Cut{l, ls, ln, r, rs}:
      l

def cut.lsum(c: Cut) -> Nat:
  match c:
    case Cut{l, ls, ln, r, rs}:
      ls

def cut.llen(c: Cut) -> Nat:
  match c:
    case Cut{l, ls, ln, r, rs}:
      ln

def cut.right(c: Cut) -> List<&2, Fs.Tree>:
  match c:
    case Cut{l, ls, ln, r, rs}:
      r

def cut.rsum(c: Cut) -> Nat:
  match c:
    case Cut{l, ls, ln, r, rs}:
      rs

# the left part's share of the box, lsum of total
def frac(+lsum: Nat, +total: Nat) -> F32:
  Bool.pick(F32, Nat.is_eq(total, 0n), 0.5, F32.div(f32(lsum), f32(total)))

# the box (x0, y0, x1, y1) is wider than tall: it splits at an x
def wide(+x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bool:
  F32.is_ge(F32.sub(x1, x0), F32.sub(y1, y0))

def mid(+lo: F32, +hi: F32, +t: F32) -> F32:
  F32.add(lo, F32.mul(F32.sub(hi, lo), t))

# is the box too small to lay out entries inside?
def small(+x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bool:
  Bool.or(F32.is_lt(F32.sub(x1, x0), 4.0), F32.is_lt(F32.sub(y1, y0), 4.0))

# the entries of a directory (sorted by size, total in all) laid out in
# the box, depth levels of subdirectories inside; fuel bounds the cuts
# (the count of entries is enough), and is 0 for a box too small to
# lay out. idx0 is the index of the first entry.
def lay(
  +depth: Nat, fuel: Nat, items: List<&2, Fs.Tree>, +total: Nat, +idx0: Nat,
  +x0: F32, +y0: F32, +x1: F32, +y1: F32
) -> List<&2, Lay>:
  match depth:
    case 0n:
      Nil{}
    case 1n++d:
      match fuel:
        case 0n:
          Nil{}
        case 1n++f:
          match items:
            case Nil{}:
              Nil{}
            case Fs.FsFile{nm, sz} <> Nil{}:
              +n = nm
              [LFile{px(x0), px(y0), px(x1), px(y1), idx0, n, sz, color_of(n)}]
            case Fs.FsDir{nm, +sz, +ks} <> Nil{}:
              +tiny = small(x0, y0, x1, y1)
              [LDir{px(x0), px(y0), px(x1), px(y1), idx0, nm, sz,
                lay(d, Bool.pick(Nat, tiny, 0n, List.length(&2, Fs.Tree, ks)), ks,
                  sz, 0n, F32.add(x0, 1.0), F32.add(y0, 1.0), x1, y1)}]
            case h <> t:
              # the cut is taken apart before the fork: each half owns
              # its part, and no task reads a node another one holds
              +c = cut(h <> t, total)
              +w = wide(x0, y0, x1, y1)
              +fr = frac(cut.lsum(c), total)
              +xm = mid(x0, x1, fr)
              +ym = mid(y0, y1, fr)
              # every argument is computed before the fork: on Bend 2.0.39 a
              # parallel call whose arguments read a shared local (cut.left(c)
              # here, cut.right(c) there) can lose its result on more than
              # one thread ("frontier drained without a result")
              l = cut.left(c)
              ls = cut.lsum(c)
              r = cut.right(c)
              rs = cut.rsum(c)
              i1 = Nat.add(idx0, cut.llen(c))
              ax1 = Bool.pick(F32, w, xm, x1)
              ay1 = Bool.pick(F32, w, y1, ym)
              bx0 = Bool.pick(F32, w, xm, x0)
              by0 = Bool.pick(F32, w, y0, ym)
              a b = lay(depth, f, l, ls, idx0, x0, y0, ax1, ay1)
                lay(depth, f, r, rs, i1, bx0, by0, x1, y1)
              List.append(&2, Lay, a, b)

# the layout of a directory's entries over the window
def layout(t: Fs.Tree) -> List<&2, Lay>:
  match t:
    case Fs.FsFile{nm, sz}:
      [LFile{0, 0, width(), height(), 0n, nm, sz, 5011624}]
    case Fs.FsDir{nm, +sz, +ks}:
      lay(levels(), List.length(&2, Fs.Tree, ks), ks, sz, 0n, 0.0, 0.0,
        U32.to_f32(width()), U32.to_f32(height()))

# Draw
# ----

def box.x0(l: Lay) -> U32:
  match l:
    case LFile{x0, y0, x1, y1, i, nm, sz, c}:
      x0
    case LDir{x0, y0, x1, y1, i, nm, sz, ks}:
      x0

def box.y0(l: Lay) -> U32:
  match l:
    case LFile{x0, y0, x1, y1, i, nm, sz, c}:
      y0
    case LDir{x0, y0, x1, y1, i, nm, sz, ks}:
      y0

def box.x1(l: Lay) -> U32:
  match l:
    case LFile{x0, y0, x1, y1, i, nm, sz, c}:
      x1
    case LDir{x0, y0, x1, y1, i, nm, sz, ks}:
      x1

def box.y1(l: Lay) -> U32:
  match l:
    case LFile{x0, y0, x1, y1, i, nm, sz, c}:
      y1
    case LDir{x0, y0, x1, y1, i, nm, sz, ks}:
      y1

def has_kids(l: Lay) -> Bool:
  match l:
    case LFile{x0, y0, x1, y1, i, nm, sz, c}:
      False{}
    case LDir{x0, y0, x1, y1, i, nm, sz, ks}:
      Bool.not(List.is_empty(&2, Lay, ks))

# does the cell at (x, y) of side s overlap the box?
def hits(+x: U32, +y: U32, +s: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) ->
  Bool:
  ((x < x1) && (x0 < x + s) && (y < y1) && (y0 < y + s) : U32)

# does the box hold the whole cell?
def inside(+x: U32, +y: U32, +s: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) ->
  Bool:
  ((x0 <= x) && (x + s <= x1) && (y0 <= y) && (y + s <= y1) : U32)

def hit.box(+l: Lay, +x: U32, +y: U32, +s: U32) -> Bool:
  hits(x, y, s, box.x0(l), box.y0(l), box.x1(l), box.y1(l))

# a box to open: a directory with entries that holds the whole cell
def open.box(+l: Lay, +x: U32, +y: U32, +s: U32) -> Bool:
  Bool.and(has_kids(l), inside(x, y, s, box.x0(l), box.y0(l), box.x1(l), box.y1(l)))

def hit.head(xs: List<&2, Lay>, +x: U32, +y: U32, +s: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case h <> t:
      hit.box(h, x, y, s)

def open.head(xs: List<&2, Lay>, +x: U32, +y: U32, +s: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case h <> t:
      open.box(h, x, y, s)

# the boxes of xs that touch the cell, a directory holding the cell
# opened into its entries; hit and open are the verdicts on the head
def cands(
  xs: List<&2, Lay>, hit: Bool, open: Bool, +x: U32, +y: U32, +s: U32,
  acc: List<&2, Lay>
) -> List<&2, Lay>:
  match xs:
    case Nil{}:
      acc
    case LFile{x0, y0, x1, y1, i, nm, sz, c} <> +t:
      match hit:
        case False{}:
          cands(t, hit.head(t, x, y, s), open.head(t, x, y, s), x, y, s, acc)
        case True{}:
          cands(t, hit.head(t, x, y, s), open.head(t, x, y, s), x, y, s,
            LFile{x0, y0, x1, y1, i, nm, sz, c} <> acc)
    case LDir{x0, y0, x1, y1, i, nm, sz, +ks} <> +t:
      match hit:
        case False{}:
          cands(t, hit.head(t, x, y, s), open.head(t, x, y, s), x, y, s, acc)
        case True{}:
          match open:
            case False{}:
              cands(t, hit.head(t, x, y, s), open.head(t, x, y, s), x, y, s,
                LDir{x0, y0, x1, y1, i, nm, sz, ks} <> acc)
            case True{}:
              cands(t, hit.head(t, x, y, s), open.head(t, x, y, s), x, y, s,
                cands(ks, hit.head(ks, x, y, s), open.head(ks, x, y, s), x, y, s,
                  acc))

def cands.of(+xs: List<&2, Lay>, +x: U32, +y: U32, +s: U32) -> List<&2, Lay>:
  cands(xs, hit.head(xs, x, y, s), open.head(xs, x, y, s), x, y, s, Nil{})

# the left and top pixel lines of a box are a gap, unless the box is
# too thin to spare them
def gap(+lo: U32, +hi: U32) -> U32:
  Bool.pick(U32, U32.is_ge(U32.sub(hi, lo), 3), U32.add(lo, 1), lo)

# a cell inside one box's interior (past its gap), or in none, is one
# color
def flat(cs: List<&2, Lay>, +x: U32, +y: U32, +s: U32) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case LFile{+x0, +y0, +x1, +y1, i, nm, sz, c} <> Nil{}:
      inside(x, y, s, gap(x0, x1), gap(y0, y1), x1, y1)
    case LDir{+x0, +y0, +x1, +y1, i, nm, sz, ks} <> Nil{}:
      inside(x, y, s, gap(x0, x1), gap(y0, y1), x1, y1)
    case cs2:
      False{}

# the color of a box's interior
def fill(l: Lay) -> U32:
  match l:
    case LFile{x0, y0, x1, y1, i, nm, sz, c}:
      c
    case LDir{x0, y0, x1, y1, i, nm, sz, ks}:
      dir_color()

# the color of a flat cell
def flat.color(cs: List<&2, Lay>) -> U32:
  match cs:
    case Nil{}:
      bg()
    case c <> rest:
      fill(c)

# the color of one pixel: the first box holding it, its gap lines dark
def pixel(cs: List<&2, Lay>, +x: U32, +y: U32) -> U32:
  match cs:
    case Nil{}:
      bg()
    case +c <> rest:
      Bool.pick(U32, hits(x, y, 1, box.x0(c), box.y0(c), box.x1(c), box.y1(c)),
        Bool.pick(U32, Bool.or(U32.is_lt(x, gap(box.x0(c), box.x1(c))),
          U32.is_lt(y, gap(box.y0(c), box.y1(c)))), bg(), fill(c)),
        pixel(rest, x, y))

# the image of the cell at (x, y) of side 2^k over the boxes cs that
# touch it; one is flat when its verdict says so
def draw(+k: Nat, +x: U32, +y: U32, +cs: List<&2, Lay>, isflat: Bool) -> Image:
  match k:
    case 0n:
      Pix{pixel(cs, x, y)}
    case 1n++e:
      match isflat:
        case True{}:
          Pix{flat.color(cs)}
        case False{}:
          +h = U32.shln(1, e)
          +xr = U32.add(x, h)
          +yb = U32.add(y, h)
          +c00 = cands.of(cs, x, y, h)
          +c10 = cands.of(cs, xr, y, h)
          +c01 = cands.of(cs, x, yb, h)
          +c11 = cands.of(cs, xr, yb, h)
          # the verdicts before the fork, as in lay
          f00 = flat(c00, x, y, h)
          f10 = flat(c10, xr, y, h)
          f01 = flat(c01, x, yb, h)
          f11 = flat(c11, xr, yb, h)
          tl tr bl br = draw(e, x, y, c00, f00) draw(e, xr, y, c10, f10)
            draw(e, x, yb, c01, f01) draw(e, xr, yb, c11, f11)
          Qua{tl, tr, bl, br}

def render(boxes: List<&2, Lay>) -> Image:
  +side = U32.shln(1, depth())
  +cs = cands.of(boxes, 0, 0, side)
  draw(depth(), 0, 0, cs, flat(cs, 0, 0, side))

# Hover
# -----

def holds(+l: Lay, +x: U32, +y: U32) -> Bool:
  hits(x, y, 1, box.x0(l), box.y0(l), box.x1(l), box.y1(l))

def holds.head(xs: List<&2, Lay>, +x: U32, +y: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case h <> t:
      holds(h, x, y)

def entry(+path: String, nm: Fs.Name, +sz: Nat, +total: Nat, dir: Bool) -> String:
  path ++ Fs.text(nm) ++ Bool.pick(String, dir, "/", "") ++ "  " ++ Fmt.human(sz) ++ "  "
    ++ Fmt.pct(sz, total)

# the deepest entry under (x, y), with its path from the shown root;
# in is the verdict on the head
def under(
  xs: List<&2, Lay>, in: Bool, +x: U32, +y: U32, +path: String, +total: Nat
) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case LFile{x0, y0, x1, y1, i, nm, sz, c} <> +t:
      match in:
        case False{}:
          under(t, holds.head(t, x, y), x, y, path, total)
        case True{}:
          Some{entry(path, nm, sz, total, False{})}
    case LDir{x0, y0, x1, y1, i, +nm, +sz, +ks} <> +t:
      match in:
        case False{}:
          under(t, holds.head(t, x, y), x, y, path, total)
        case True{}:
          Maybe.or(&2, String,
            under(ks, holds.head(ks, x, y), x, y, path ++ Fs.text(nm) ++ "/", total),
            Some{entry(path, nm, sz, total, True{})})

def under.of(+xs: List<&2, Lay>, +x: U32, +y: U32, +path: String, +total: Nat) ->
  Maybe<&2, String>:
  under(xs, holds.head(xs, x, y), x, y, path, total)

# the index of the top-level directory under (x, y), if one is there
def dir_at(xs: List<&2, Lay>, in: Bool, +x: U32, +y: U32) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case LFile{x0, y0, x1, y1, i, nm, sz, c} <> +t:
      match in:
        case False{}:
          dir_at(t, holds.head(t, x, y), x, y)
        case True{}:
          None{}
    case LDir{x0, y0, x1, y1, i, nm, sz, ks} <> +t:
      match in:
        case False{}:
          dir_at(t, holds.head(t, x, y), x, y)
        case True{}:
          Some{i}

def dir_at.of(+xs: List<&2, Lay>, +x: U32, +y: U32) -> Maybe<&2, Nat>:
  dir_at(xs, holds.head(xs, x, y), x, y)

# State
# -----

# the whole tree, the path of indexes to the shown directory, its
# layout and image, the title shown, the pointer
type View is Data:
  View{root: Fs.Tree, path: List<&2, Nat>, lay: List<&2, Lay>, img: Image,
    title: String, mx: U32, my: U32}

# What a frame's events ask for.
type Act is Data:
  Act{quit: Bool, up: Bool, zoom: Bool, mx: U32, my: U32, moved: Bool}

def act.of(events: List<Event>, a: Act) -> Act:
  match events a:
    case Nil{} a2:
      a2
    case Key{27, True{}} <> rest Act{quit, up, zoom, mx, my, moved}:
      act.of(rest, Act{True{}, up, zoom, mx, my, moved})
    case Key{127, True{}} <> rest Act{quit, up, zoom, mx, my, moved}:
      act.of(rest, Act{quit, True{}, zoom, mx, my, moved})
    case Key{63232, True{}} <> rest Act{quit, up, zoom, mx, my, moved}:
      act.of(rest, Act{quit, True{}, zoom, mx, my, moved})
    case Key{code, down} <> rest a2:
      act.of(rest, a2)
    case Mouse{x, y, 0, True{}} <> rest Act{quit, up, zoom, mx, my, moved}:
      act.of(rest, Act{quit, up, True{}, x, y, True{}})
    case Mouse{x, y, b, True{}} <> rest Act{quit, up, zoom, mx, my, moved}:
      act.of(rest, Act{quit, True{}, zoom, x, y, True{}})
    case Mouse{x, y, b, down} <> rest a2:
      act.of(rest, a2)
    case Move{x, y} <> rest Act{quit, up, zoom, mx, my, moved}:
      act.of(rest, Act{quit, up, zoom, x, y, True{}})
    case Close{} <> rest Act{quit, up, zoom, mx, my, moved}:
      act.of(rest, Act{True{}, up, zoom, mx, my, moved})
    case e <> rest a2:
      act.of(rest, a2)

# the text of the shown directory: its path from the root
def crumbs(path: List<&2, Nat>, root: Fs.Tree, acc: String) -> String:
  match path root:
    case Nil{} r:
      acc ++ Fs.text(Fs.name(r))
    case i <> rest Fs.FsFile{nm, sz}:
      acc ++ Fs.text(nm)
    case i <> rest Fs.FsDir{+nm, sz, ks}:
      crumbs(rest, Maybe.default(&2, Fs.Tree, Fs.at(ks, i), Fs.FsDir{nm, 0n, Nil{}}),
        acc ++ Fmt.slashed(Fs.text(nm)))

# the view of the directory at path, laid out and drawn
def show(+root: Fs.Tree, +path: List<&2, Nat>, +mx: U32, +my: U32) -> View:
  +cur = Maybe.default(&2, Fs.Tree, Fs.walk(path, root), Fs.blank())
  +boxes = layout(cur)
  View{root, path, boxes, render(boxes), crumbs(path, root, ""), mx, my}

# the shown directory's path, without a trailing separator
def shown(+root: Fs.Tree, +path: List<&2, Nat>) -> String:
  crumbs(path, root, "")

def title.of(+v: View) -> String:
  View{+root, +path, boxes, img, title, mx, my} = v
  +cur = Maybe.default(&2, Fs.Tree, Fs.walk(path, root), Fs.blank())
  +base = "bendirstat  " ++ shown(root, path) ++ "  " ++ Fmt.human(Fs.size(cur))
  Maybe.default(&2, String, Maybe.map(&2, String, String,
    s => base ++ "   ▸ " ++ s, under.of(boxes, mx, my, "", Fs.size(cur))), base)

# the view after a zoom in at the pointer (a directory there), out, or
# neither
def zoom.in(v: View, target: Maybe<&2, Nat>) -> View:
  match v target:
    case v2 None{}:
      v2
    case View{root, path, boxes, img, title, mx, my} Some{i}:
      show(root, List.append(&2, Nat, path, [i]), mx, my)

def zoom.out(v: View) -> View:
  View{root, +path, boxes, img, title, mx, my} = v
  show(root, List.take(&2, Nat, path,
    Nat.sub(List.length(&2, Nat, path), 1n)), mx, my)

def apply.zoom(v: View, zoom: Bool, up: Bool) -> View:
  match v zoom up:
    case View{root, path, +boxes, img, title, +mx, +my} True{} _:
      zoom.in(View{root, path, boxes, img, title, mx, my}, dir_at.of(boxes, mx, my))
    case v2 False{} True{}:
      zoom.out(v2)
    case v2 False{} False{}:
      v2

def apply.move(v: View, moved: Bool, x: U32, y: U32) -> View:
  match v moved:
    case View{root, path, boxes, img, title, mx, my} True{}:
      View{root, path, boxes, img, title, x, y}
    case v2 False{}:
      v2

def apply(v: View, a: Act) -> Maybe<&1, View>:
  match a:
    case Act{True{}, up, zoom, x, y, moved}:
      None{}
    case Act{False{}, up, zoom, x, y, moved}:
      Some{apply.move(apply.zoom(v, zoom, up), moved, x, y)}

# Loop
# ----

def retitle.go(win: Window, now: String, same: Bool) -> IO(Window):
  match same:
    case True{}:
      IO.pure(Window, win)
    case False{}:
      Window.set_title(win, now)

def retitle(win: Window, +v: View, +was: String) -> IO(Window):
  +now = title.of(v)
  retitle.go(win, now, String.eq(now, was))

def image.of(v: View) -> View & Image:
  View{root, path, boxes, +img, title, mx, my} = v
  (View{root, path, boxes, img, title, mx, my}, img)

# a frame: show the image, take the events, act, and hand the window
# and the view to rest (the next frame); the loop recurses through it
def next(
  win: Window, v: Maybe<&1, View>, was: String, rest: Window -> View -> IO(Unit)
) -> IO(Unit):
  match v:
    case None{}:
      Window.close(win)
    case Some{+v2}:
      do IO<Unit>:
        win2 : Window <- retitle(win, v2, was)
        rest(win2, v2)

def turn(
  fr: Window & Image & List<Event>, +v: View, rest: Window -> View -> IO(Unit)
) -> IO(Unit):
  (win, image, events) = fr
  do IO<Unit>:
    Unit <- IO.pure(Unit, Image.drop(image))
    next(win, apply(v, act.of(events, Act{False{}, False{}, False{}, 0, 0,
      False{}})), title.of(v), rest)

def step(win: Window, vi: View & Image, rest: Window -> View -> IO(Unit)) ->
  IO(Unit):
  (v, img) = vi
  do IO<Unit>:
    fr : Window & Image & List<Event> <- Window.frame(win, img)
    turn(fr, v, rest)

def loop(fuel: Nat, win: Window, v: View) -> IO(Unit):
  match fuel:
    case 0n:
      Window.close(win)
    case 1n+f:
      step(win, image.of(v), w => v2 => loop(f, w, v2))

def open(+t: Fs.Tree) -> IO(Unit):
  do IO<Unit>:
    win : Window <- IO.try(Window, Window.open("bendirstat", width(), height()))
    win2 : Window <- Window.set_title(win, title.of(show(t, Nil{}, 0, 0)))
    loop(U32.to_nat(4294967295), win2, show(t, Nil{}, 0, 0))

# Snapshot
# --------

def image_only(v: View) -> Image:
  View{root, path, boxes, img, title, mx, my} = v
  img

# the color of pixel (x, y) of an image over 2^k
def at(k: Nat, img: Image, +x: U32, +y: U32) -> U32:
  match k img:
    case _ Pix{c}:
      c
    case 0n Qua{tl, tr, bl, br}:
      at(0n, tl, x, y)
    case 1n++e Qua{tl, tr, bl, br}:
      +h = U32.shln(1, e)
      +right = U32.is_ge(x, h)
      +below = U32.is_ge(y, h)
      at(e, Bool.pick(Image, right, Bool.pick(Image, below, br, tr),
        Bool.pick(Image, below, bl, tl)), U32.and(x, U32.sub(h, 1)),
        U32.and(y, U32.sub(h, 1)))

# the bytes of a row's pixels, from x down, before acc
def row(x: Nat, +y: U32, +img: Image, acc: List<&2, U32>) -> List<&2, U32>:
  match x:
    case 0n:
      acc
    case 1n++p:
      +c = at(depth(), img, U32.from_nat(p), y)
      row(p, y, img, U32.and(U32.shrn(c, 16n), 255) <> U32.and(U32.shrn(c, 8n), 255)
        <> U32.and(c, 255) <> acc)

# the bytes of the rows from y down, before acc
def rows(y: Nat, +img: Image, acc: List<&2, U32>) -> List<&2, U32>:
  match y:
    case 0n:
      acc
    case 1n++p:
      rows(p, img, row(U32.to_nat(width()), U32.from_nat(p), img, acc))

def codes(cs: List<&2, Char>) -> List<&2, U32>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      Char.to_u32(c) <> codes(t)

def header() -> List<&2, U32>:
  codes(String.to_list("P6\n" ++ U32.show(width()) ++ " " ++ U32.show(height())
    ++ "\n255\n"))

def ppm(img: Image) -> List<&2, U32>:
  +i = img
  List.append(&2, U32, header(), rows(U32.to_nat(height()), i, Nil{}))

def written(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    Unit <- IO.pass(Unit, res)
    File.close(f)

# writes the treemap of t as a binary PPM at path
def snapshot(+t: Fs.Tree, path: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f,
      ppm(image_only(show(t, Nil{}, 0, 0))))
    written(r)
