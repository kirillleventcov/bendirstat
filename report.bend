# report.bend: the text report over a prepared tree: the tree of the
# largest entries with bars, the largest files, and the space by
# extension.
import Base
import ./fs.bend as Fs
import ./fmt.bend as Fmt

# Tree
# ----

def glyph(last: Bool) -> String:
  match last:
    case True{}:
      "└── "
    case False{}:
      "├── "

def deeper(last: Bool) -> String:
  match last:
    case True{}:
      "    "
    case False{}:
      "│   "

def label(color: Bool, +s: String, dir: Bool) -> String:
  match dir:
    case True{}:
      Fmt.paint(color, "1;34", Fmt.slashed(s))
    case False{}:
      s

# one row: size, bar, share, then the entry at its place in the tree
def line(
  +color: Bool, prefix: String, last: Bool, s: String, +sz: Nat, +total: Nat,
  dir: Bool
) -> String:
  Fmt.pad(Fmt.human(sz), 10n) ++ " "
    ++ Fmt.paint(color, "36", Fmt.bar(sz, total, 12n)) ++ " "
    ++ Fmt.pad(Fmt.pct(sz, total), 6n) ++ "  "
    ++ Fmt.paint(color, "2", prefix ++ glyph(last)) ++ label(color, s, dir)

# the count and size of a list's entries
def stats.put(+sz: Nat, r: Nat & Nat) -> Nat & Nat:
  (c, s) = r
  (1n+c, Nat.add(s, sz))

def stats(xs: List<&2, Fs.Tree>) -> Nat & Nat:
  match xs:
    case Nil{}:
      (0n, 0n)
    case h <> t:
      stats.put(Fs.size(h), stats(t))

# the row that stands for the entries past the budget
def more(+color: Bool, prefix: String, +total: Nat, cs: Nat & Nat) -> String:
  (c, s) = cs
  line(color, prefix, True{}, "… " ++ Nat.show(c) ++ " more", s, total, False{})

# the rows of a directory's entries xs, above rest: n entries remain in
# the budget, limit is the budget of a directory below, depth how far
# down to go
def rows(
  xs: List<&2, Fs.Tree>, +n: Nat, +depth: Nat, +limit: Nat, +prefix: String,
  +total: Nat, +color: Bool, rest: List<&2, String>
) -> List<&2, String>:
  match xs:
    case Nil{}:
      rest
    case h <> +t:
      match h:
        case Fs.FsFile{nm, sz}:
          match n:
            case 0n:
              more(color, prefix, total, stats(Fs.FsFile{nm, sz} <> t)) <> rest
            case 1n++m:
              +last = List.is_empty(&2, Fs.Tree, t)
              line(color, prefix, last, Fs.text(nm), sz, total, False{})
                <> rows(t, m, depth, limit, prefix, total, color, rest)
        case Fs.FsDir{nm, sz, ks}:
          match n:
            case 0n:
              more(color, prefix, total, stats(Fs.FsDir{nm, sz, ks} <> t)) <> rest
            case 1n++m:
              match depth:
                case 0n:
                  +last = List.is_empty(&2, Fs.Tree, t)
                  line(color, prefix, last, Fs.text(nm), sz, total, True{})
                    <> rows(t, m, depth, limit, prefix, total, color, rest)
                case 1n++d:
                  +last = List.is_empty(&2, Fs.Tree, t)
                  line(color, prefix, last, Fs.text(nm), sz, total, True{})
                    <> rows(ks, limit, d, limit, prefix ++ deeper(last), total,
                      color, rows(t, m, depth, limit, prefix, total, color, rest))

# the root's row: no glyph, the whole bar
def root(+color: Bool, s: String, +sz: Nat, dir: Bool) -> String:
  Fmt.pad(Fmt.human(sz), 10n) ++ " " ++ Fmt.paint(color, "36", Fmt.bar(sz, sz, 12n))
    ++ " " ++ Fmt.pad(Fmt.pct(sz, sz), 6n) ++ "  " ++ label(color, s, dir)

# the tree report: the root, then its entries down to depth levels,
# limit entries per directory
def tree(t: Fs.Tree, depth: Nat, limit: Nat, +color: Bool) -> String:
  match t:
    case Fs.FsFile{nm, sz}:
      root(color, Fs.text(nm), sz, False{})
    case Fs.FsDir{nm, +sz, ks}:
      +lim = limit
      String.join(root(color, Fs.text(nm), sz, True{})
        <> rows(ks, lim, Nat.sub(depth, 1n), lim, "", sz, color, Nil{}), "\n")

# Largest files
# -------------

# a kept file: its size, its name, and the names of the directories it
# is in, innermost first (a cell a directory, shared by its files); the
# path's text is built only for the rows printed
type Big is Data:
  Big{size: Nat, name: Fs.Name, dirs: List<&2, Fs.Name>}

def big.size(b: Big) -> Nat:
  match b:
    case Big{sz, nm, ds}:
      sz

def big.ge(a: Big, b: Big) -> Bool:
  Nat.is_ge(big.size(a), big.size(b))

# the size of the k-th kept file, 0 when fewer than k are kept
def big.min(xs: List<&2, Big>, k: Nat) -> Nat:
  match xs k:
    case Nil{} _:
      0n
    case b <> t 0n:
      0n
    case b <> t 1n+j:
      match j:
        case 0n:
          big.size(b)
        case 1n+i:
          big.min(t, 1n+i)

# the kept list beside the size of its k-th file (0 while it is short)
def kept.new() -> List<&2, Big> & Nat:
  (Nil{}, 0n)

# a kept list beside its threshold
def kept.of(+bs: List<&2, Big>, +k: Nat) -> List<&2, Big> & Nat:
  (bs, big.min(bs, k))

# does b go before the head of xs? (at the end of an empty one)
def before(+b: Big, xs: List<&2, Big>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case h <> t:
      big.ge(b, h)

# b inserted in the ordered xs, at most k kept; goes says b goes before
# the head
def big.ins(xs: List<&2, Big>, +b: Big, k: Nat, goes: Bool) -> List<&2, Big>:
  match xs k:
    case xs2 0n:
      Nil{}
    case Nil{} 1n+j:
      [b]
    case h <> +t 1n+j:
      match goes:
        case True{}:
          b <> List.take(&2, Big, h <> t, j)
        case False{}:
          h <> big.ins(t, b, j, before(b, t))

# the file joins the kept list when it beats the k-th kept
def consider(
  +k: Nat, sz: Nat, dirs: List<&2, Fs.Name>, nm: Fs.Name, beats: Bool,
  kept: List<&2, Big> & Nat
) -> List<&2, Big> & Nat:
  match beats kept:
    case True{} Tuple{+bs, mn}:
      +b = {Big{sz, nm, dirs} : Big}
      kept.of(big.ins(bs, b, k, before(b, bs)), k)
    case False{} k2:
      k2

# does the head of xs go before the head of ys?
def first(xs: List<&2, Big>, ys: List<&2, Big>) -> Bool:
  match xs ys:
    case Nil{} y:
      False{}
    case x Nil{}:
      True{}
    case a <> at b <> bt:
      big.ge(a, b)

# the k largest of two ordered lists, in order; fuel bounds the merge
def big.mrg(
  fuel: Nat, +as: List<&2, Big>, +bs: List<&2, Big>, k: Nat, afirst: Bool
) -> List<&2, Big>:
  match fuel:
    case 0n:
      Nil{}
    case 1n+f:
      match as bs k:
        case a b 0n:
          Nil{}
        case Nil{} b 1n+j:
          List.take(&2, Big, b, 1n+j)
        case a Nil{} 1n+j:
          List.take(&2, Big, a, 1n+j)
        case a <> +at b <> +bt 1n+j:
          match afirst:
            case True{}:
              a <> big.mrg(f, at, b <> bt, j, first(at, b <> bt))
            case False{}:
              b <> big.mrg(f, a <> at, bt, j, first(a <> at, bt))

def big.merge(+a: List<&2, Big>, +b: List<&2, Big>, +k: Nat) -> List<&2, Big> & Nat:
  kept.of(big.mrg(Nat.add(k, k), a, b, k, first(a, b)), k)

def big.merge.go(a: List<&2, Big> & Nat, b: List<&2, Big> & Nat, +k: Nat) ->
  List<&2, Big> & Nat:
  (as, am) = a
  (bs, bm) = b
  big.merge(as, bs, k)

# the k largest files under xs joined to kept, largest first: a loop over
# a directory's entries, a fork into each subdirectory
def biggest(
  xs: List<&2, Fs.Tree>, +k: Nat, +dirs: List<&2, Fs.Name>,
  kept: List<&2, Big> & Nat
) -> List<&2, Big> & Nat:
  match xs:
    case Nil{}:
      kept
    case Fs.FsFile{nm, +sz} <> t:
      (bs, +mn) = kept
      biggest(t, k, dirs, consider(k, sz, dirs, nm, Nat.is_gt(sz, mn), (bs, mn)))
    case Fs.FsDir{nm, sz, ks} <> t:
      a b = biggest(ks, k, nm <> dirs, kept.new()) biggest(t, k, dirs, kept)
      big.merge.go(a, b, k)

# the text of a file's directories, outermost first, before acc
def dirs.text(ds: List<&2, Fs.Name>, acc: String) -> String:
  match ds:
    case Nil{}:
      acc
    case d <> rest:
      dirs.text(rest, Fmt.slashed(Fs.text(d)) ++ acc)

def big.row(+color: Bool, +total: Nat, b: Big) -> String:
  match b:
    case Big{+sz, nm, ds}:
      Fmt.pad(Fmt.human(sz), 10n) ++ " " ++ Fmt.pad(Fmt.pct(sz, total), 6n)
        ++ "  " ++ Fmt.paint(color, "2", dirs.text(ds, "")) ++ Fs.text(nm)

def big.rows(+color: Bool, +total: Nat, bs: List<&2, Big>) -> List<&2, String>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      big.row(color, total, b) <> big.rows(color, total, t)

# the report of the k largest files under the root t
def files.fin(+color: Bool, +total: Nat, kept: List<&2, Big> & Nat) -> String:
  (bs, mn) = kept
  String.join(big.rows(color, total, bs), "\n")

def files(t: Fs.Tree, k: Nat, +color: Bool) -> String:
  match t:
    case Fs.FsFile{nm, sz}:
      ""
    case Fs.FsDir{nm, +sz, ks}:
      files.fin(color, sz, biggest(ks, k, [nm], kept.new()))

# Extensions
# ----------
#
# An extension is packed into one Nat: six bits a character, at most
# seven characters. It is read off the end of a name, a byte at a time,
# back to the last dot, so most names are touched for a few bytes. The
# tally is a trie on that code, two bits a level: an empty one is free,
# a file costs a path down it, and two merge in the time of their
# smaller, so every directory forks as the sums do.

# the symbol of a byte: letters 1-26 (either case), digits 27-36, a few
# marks after, 0 for any other
def sym(+b: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(Nat.is_ge(b, 97n), Nat.is_le(b, 122n)), Nat.sub(b, 96n),
    Bool.pick(Nat, Bool.and(Nat.is_ge(b, 48n), Nat.is_le(b, 57n)), Nat.sub(b, 21n),
      Bool.pick(Nat, Bool.and(Nat.is_ge(b, 65n), Nat.is_le(b, 90n)), Nat.sub(b, 64n),
        Bool.pick(Nat, Nat.is_eq(b, 45n), 37n,
          Bool.pick(Nat, Nat.is_eq(b, 95n), 38n,
            Bool.pick(Nat, Nat.is_eq(b, 43n), 39n,
              Bool.pick(Nat, Nat.is_eq(b, 126n), 40n, 0n)))))))

# the character of a symbol
def unsym(d: Nat) -> Char:
  +x = U32.from_nat(d)
  Chr{Bool.pick(U32, U32.is_le(x, 26), U32.add(x, 96),
    Bool.pick(U32, U32.is_le(x, 36), U32.add(x, 21),
      Bool.pick(U32, U32.is_eq(x, 37), 45,
        Bool.pick(U32, U32.is_eq(x, 38), 95,
          Bool.pick(U32, U32.is_eq(x, 39), 43, 126)))))}

# A scan from the end of a name: still seeking the dot, with the code of
# the len characters past it so far (the first seven), bad when one is
# outside the symbols, and mul the place of the next; or done, with the
# extension's code.
type Seek is Data:
  ESeek{code: Nat, len: Nat, bad: Bool, mul: Nat}
  EDone{code: Nat}

# 1 stands for no extension, 2 for one too long or odd; a real code is
# 3 or more
def ext.fin(+code: Nat, +len: Nat, bad: Bool) -> Nat:
  match bad:
    case True{}:
      2n
    case False{}:
      Bool.pick(Nat, Bool.or(Nat.is_gt(len, 7n), Nat.is_eq(len, 0n)), 2n,
        Nat.add(code, 3n))

# one more symbol, d; room says the code has room for it (a match, not
# a pick: both sides of a pick are computed, and past seven symbols the
# next place is no longer a native Nat)
def ext.push(room: Bool, +d: Nat, +code: Nat, +len: Nat, bad: Bool, +mul: Nat) ->
  Seek:
  match room:
    case True{}:
      ESeek{Nat.add(code, Nat.mul(d, mul)), 1n+len, Bool.or(bad, Nat.is_eq(d, 0n)),
        Nat.mul(mul, 64n)}
    case False{}:
      ESeek{code, 1n+len, Bool.or(bad, Nat.is_eq(d, 0n)), mul}

# one more byte, b, read backwards; dot says it is the dot
def ext.step(dot: Bool, +b: Nat, +code: Nat, +len: Nat, bad: Bool, +mul: Nat) ->
  Seek:
  match dot:
    case True{}:
      EDone{ext.fin(code, len, bad)}
    case False{}:
      ext.push(Nat.is_lt(len, 7n), sym(b), code, len, bad, mul)

# the bytes of a chunk, last first, into the scan; fuel bounds them
def ext.chunk(fuel: Nat, st: Seek, +c: Nat) -> Seek:
  match fuel:
    case 0n:
      st
    case 1n+f:
      match st:
        case EDone{x}:
          EDone{x}
        case ESeek{code, len, bad, mul}:
          match c:
            case 0n:
              ESeek{code, len, bad, mul}
            case 1n++p:
              +b = Nat.mod(1n+p, 256n)
              ext.chunk(f, ext.step(Nat.is_eq(b, 46n), b, code, len, bad, mul),
                Nat.div(1n+p, 256n))

# the scan of a name: its later chunks first
def ext.scan(nm: Fs.Name) -> Seek:
  match nm:
    case Fs.NEnd{}:
      ESeek{0n, 0n, False{}, 1n}
    case Fs.NMore{c, rest}:
      ext.chunk(6n, ext.scan(rest), c)

def ext.res(st: Seek) -> Nat:
  match st:
    case EDone{x}:
      x
    case ESeek{code, len, bad, mul}:
      1n

# the code of the text after the last dot of a name
def ext.of(nm: Fs.Name) -> Nat:
  ext.res(ext.scan(nm))

# the text of a code, fuel characters at most
def ext.decode(fuel: Nat, +code: Nat, acc: String) -> String:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      match code:
        case 0n:
          acc
        case 1n++p:
          ext.decode(f, Nat.div(1n+p, 64n), SCon{unsym(Nat.mod(1n+p, 64n)), acc})

def ext.name(code: Nat) -> String:
  match code:
    case 0n:
      "(none)"
    case 1n:
      "(none)"
    case 2n:
      "(other)"
    case 3n+c:
      ext.decode(7n, c, "")

# The tally: a trie on the code, the digit at place p (a power of 4)
# choosing the branch. Codes are under 2^43, so two differ within 22
# levels, and the places stay native.
type Tally is Data:
  TTip{}
  TLeaf{code: Nat, size: Nat, count: Nat}
  TNode{a: Tally, b: Tally, c: Tally, d: Tally}

def digit(+code: Nat, +p: Nat) -> Nat:
  Nat.mod(Nat.div(code, p), 4n)

# is t the leaf of code?
def tally.same(t: Tally, +code: Nat) -> Bool:
  match t:
    case TLeaf{c, s, n}:
      Nat.is_eq(c, code)
    case t2:
      False{}

# a node holding one tally, at digit i
def tally.lift(+i: Nat, l: Tally) -> Tally:
  match i:
    case 0n:
      TNode{l, TTip{}, TTip{}, TTip{}}
    case 1n:
      TNode{TTip{}, l, TTip{}, TTip{}}
    case 2n:
      TNode{TTip{}, TTip{}, l, TTip{}}
    case i2:
      TNode{TTip{}, TTip{}, TTip{}, l}

# adds n files of sz bytes to the row of code, at place p; same and i
# are the verdicts on t: is it code's leaf, and code's digit here. fuel
# bounds the descent (a level costs one, or two when a leaf splits).
def tally.put(
  fuel: Nat, t: Tally, same: Bool, +i: Nat, +code: Nat, +p: Nat, +sz: Nat,
  +n: Nat
) -> Tally:
  match fuel:
    case 0n:
      t
    case 1n+f:
      match t:
        case TTip{}:
          TLeaf{code, sz, n}
        case TLeaf{+c, s, m}:
          match same:
            case True{}:
              TLeaf{c, Nat.add(s, sz), Nat.add(m, n)}
            case False{}:
              tally.put(f, tally.lift(digit(c, p), TLeaf{c, s, m}), False{}, i, code,
                p, sz, n)
        case TNode{+a, +b, +c, +d}:
          match i:
            case 0n:
              TNode{tally.put(f, a, tally.same(a, code),
                digit(code, Nat.mul(p, 4n)), code, Nat.mul(p, 4n), sz, n), b, c, d}
            case 1n:
              TNode{a, tally.put(f, b, tally.same(b, code),
                digit(code, Nat.mul(p, 4n)), code, Nat.mul(p, 4n), sz, n), c, d}
            case 2n:
              TNode{a, b, tally.put(f, c, tally.same(c, code),
                digit(code, Nat.mul(p, 4n)), code, Nat.mul(p, 4n), sz, n), d}
            case i2:
              TNode{a, b, c, tally.put(f, d, tally.same(d, code),
                digit(code, Nat.mul(p, 4n)), code, Nat.mul(p, 4n), sz, n)}

# adds n files of sz bytes to the row of code, in a tally at place p
def tally.add(+t: Tally, +code: Nat, +p: Nat, sz: Nat, n: Nat) -> Tally:
  tally.put(64n, t, tally.same(t, code), digit(code, p), code, p, sz, n)

# two tallies at place p as one
def tally.merge(fuel: Nat, a: Tally, b: Tally, +p: Nat) -> Tally:
  match fuel:
    case 0n:
      a
    case 1n+ +f:
      match a b:
        case TTip{} b2:
          b2
        case a2 TTip{}:
          a2
        case TLeaf{c, s, n} b2:
          tally.add(b2, c, p, s, n)
        case a2 TLeaf{c, s, n}:
          tally.add(a2, c, p, s, n)
        case TNode{a0, a1, a2, a3} TNode{b0, b1, b2, b3}:
          +q = Nat.mul(p, 4n)
          TNode{tally.merge(f, a0, b0, q), tally.merge(f, a1, b1, q),
            tally.merge(f, a2, b2, q), tally.merge(f, a3, b3, q)}

# the tally of every file under xs, joined to t; a directory's entries
# and the rest of the list are tallied in parallel
def exts(xs: List<&2, Fs.Tree>, t: Tally) -> Tally:
  match xs:
    case Nil{}:
      t
    case Fs.FsFile{nm, sz} <> rest:
      exts(rest, tally.add(t, ext.of(nm), 1n, sz, 1n))
    case Fs.FsDir{nm, sz, ks} <> rest:
      a b = exts(ks, TTip{}) exts(rest, t)
      tally.merge(64n, b, a, 1n)

# A row of the report: an extension's code, bytes and files.
type Ext is Data:
  Ext{code: Nat, size: Nat, count: Nat}

# larger first; of two the same size, the lower code, so the order does
# not hang on the tally's layout
def ext.ge(a: Ext, b: Ext) -> Bool:
  match a b:
    case Ext{ca, +sa, na} Ext{cb, +sb, nb}:
      Bool.or(Nat.is_gt(sa, sb), Bool.and(Nat.is_eq(sa, sb), Nat.is_le(ca, cb)))

# the rows of a tally, before acc
def tally.rows(t: Tally, acc: List<&2, Ext>) -> List<&2, Ext>:
  match t:
    case TTip{}:
      acc
    case TLeaf{c, s, n}:
      Ext{c, s, n} <> acc
    case TNode{a, b, c, d}:
      tally.rows(a, tally.rows(b, tally.rows(c, tally.rows(d, acc))))

def ext.row(+color: Bool, +total: Nat, e: Ext) -> String:
  match e:
    case Ext{code, +sz, c}:
      Fmt.pad(Fmt.human(sz), 10n) ++ " " ++ Fmt.pad(Fmt.pct(sz, total), 6n) ++ " "
        ++ Fmt.pad(Fmt.commas(c), 11n) ++ "  " ++ Fmt.paint(color, "33", ext.name(code))

def ext.rows(+color: Bool, +total: Nat, es: List<&2, Ext>) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      ext.row(color, total, e) <> ext.rows(color, total, t)

# the report of the k largest extensions under the root t
def extensions(t: Fs.Tree, k: Nat, +color: Bool) -> String:
  match t:
    case Fs.FsFile{nm, sz}:
      ""
    case Fs.FsDir{nm, +sz, ks}:
      String.join(ext.rows(color, sz, List.take(&2, Ext,
        List.sort(~Ext, ~ext.ge, tally.rows(exts(ks, TTip{}), Nil{})), k)), "\n")
