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

def label(color: Bool, +nm: String, dir: Bool) -> String:
  match dir:
    case True{}:
      Fmt.paint(color, "1;34", nm ++ "/")
    case False{}:
      nm

# one row: size, bar, share, then the entry at its place in the tree
def line(
  +color: Bool, prefix: String, last: Bool, nm: String, +sz: Nat, +total: Nat,
  dir: Bool
) -> String:
  Fmt.pad(Fmt.human(sz), 10n) ++ " "
    ++ Fmt.paint(color, "36", Fmt.bar(sz, total, 12n)) ++ " "
    ++ Fmt.pad(Fmt.pct(sz, total), 6n) ++ "  "
    ++ Fmt.paint(color, "2", prefix ++ glyph(last)) ++ label(color, nm, dir)

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
              line(color, prefix, last, nm, sz, total, False{})
                <> rows(t, m, depth, limit, prefix, total, color, rest)
        case Fs.FsDir{nm, sz, ks}:
          match n:
            case 0n:
              more(color, prefix, total, stats(Fs.FsDir{nm, sz, ks} <> t)) <> rest
            case 1n++m:
              match depth:
                case 0n:
                  +last = List.is_empty(&2, Fs.Tree, t)
                  line(color, prefix, last, nm, sz, total, True{})
                    <> rows(t, m, depth, limit, prefix, total, color, rest)
                case 1n++d:
                  +last = List.is_empty(&2, Fs.Tree, t)
                  line(color, prefix, last, nm, sz, total, True{})
                    <> rows(ks, limit, d, limit, prefix ++ deeper(last), total,
                      color, rows(t, m, depth, limit, prefix, total, color, rest))

# the root's row: no glyph, the whole bar
def root(+color: Bool, nm: String, +sz: Nat, dir: Bool) -> String:
  Fmt.pad(Fmt.human(sz), 10n) ++ " " ++ Fmt.paint(color, "36", Fmt.bar(sz, sz, 12n))
    ++ " " ++ Fmt.pad(Fmt.pct(sz, sz), 6n) ++ "  " ++ label(color, nm, dir)

# the tree report: the root, then its entries down to depth levels,
# limit entries per directory
def tree(t: Fs.Tree, depth: Nat, limit: Nat, +color: Bool) -> String:
  match t:
    case Fs.FsFile{nm, sz}:
      root(color, nm, sz, False{})
    case Fs.FsDir{nm, +sz, ks}:
      +lim = limit
      String.join(root(color, nm, sz, True{})
        <> rows(ks, lim, Nat.sub(depth, 1n), lim, "", sz, color, Nil{}), "\n")

# Largest files
# -------------

# a kept file: its size, name and the path of its directory (shared,
# not copied, until the row is printed)
type Big is Data:
  Big{size: Nat, name: String, dir: String}

def big.size(b: Big) -> Nat:
  match b:
    case Big{sz, nm, d}:
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

# b inserted in the ordered xs, at most k kept; first says b goes
# before the head
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

# the file joins the kept list when it beats the k-th kept; its path is
# built only then, and the threshold is read off the new list
def consider(
  +k: Nat, sz: Nat, prefix: String, nm: String, beats: Bool,
  kept: List<&2, Big> & Nat
) -> List<&2, Big> & Nat:
  match beats kept:
    case True{} Tuple{+bs, mn}:
      +b = {Big{sz, nm, prefix} : Big}
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
  xs: List<&2, Fs.Tree>, +k: Nat, +prefix: String, kept: List<&2, Big> & Nat
) -> List<&2, Big> & Nat:
  match xs:
    case Nil{}:
      kept
    case Fs.FsFile{nm, +sz} <> t:
      (bs, +mn) = kept
      biggest(t, k, prefix, consider(k, sz, prefix, nm, Nat.is_gt(sz, mn), (bs, mn)))
    case Fs.FsDir{nm, sz, ks} <> t:
      a b = biggest(ks, k, prefix ++ nm ++ "/", kept.new()) biggest(t, k, prefix, kept)
      big.merge.go(a, b, k)

def big.row(+color: Bool, +total: Nat, b: Big) -> String:
  match b:
    case Big{+sz, nm, d}:
      Fmt.pad(Fmt.human(sz), 10n) ++ " " ++ Fmt.pad(Fmt.pct(sz, total), 6n)
        ++ "  " ++ Fmt.paint(color, "2", d) ++ nm

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
      files.fin(color, sz, biggest(ks, k, nm ++ "/", kept.new()))

# Extensions
# ----------
#
# An extension is packed into one Nat: six bits a character, at most
# seven characters, so the tally is a hash table of three arrays (codes,
# sizes, counts) written in place, and no string is built per file.

type Ext is Data:
  Ext{name: String, size: Nat, count: Nat}

def ext.size(e: Ext) -> Nat:
  match e:
    case Ext{nm, sz, c}:
      sz

def ext.ge(a: Ext, b: Ext) -> Bool:
  Nat.is_ge(ext.size(a), ext.size(b))

def dot(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Char.is_eq(c, '.')

# the symbol of a character: letters 1-26 (either case), digits 27-36,
# a few marks after, 0 for any other
def sym(c: Char) -> Nat:
  +x = Char.to_u32(c)
  Bool.pick(Nat, Bool.and(U32.is_ge(x, 97), U32.is_le(x, 122)),
    U32.to_nat(U32.sub(x, 96)),
    Bool.pick(Nat, Bool.and(U32.is_ge(x, 65), U32.is_le(x, 90)),
      U32.to_nat(U32.sub(x, 64)),
      Bool.pick(Nat, Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)),
        U32.to_nat(U32.sub(x, 21)),
        Bool.pick(Nat, U32.is_eq(x, 45), 37n,
          Bool.pick(Nat, U32.is_eq(x, 95), 38n,
            Bool.pick(Nat, U32.is_eq(x, 43), 39n,
              Bool.pick(Nat, U32.is_eq(x, 126), 40n, 0n)))))))

# the character of a symbol
def unsym(d: Nat) -> Char:
  +x = U32.from_nat(d)
  Chr{Bool.pick(U32, U32.is_le(x, 26), U32.add(x, 96),
    Bool.pick(U32, U32.is_le(x, 36), U32.add(x, 21),
      Bool.pick(U32, U32.is_eq(x, 37), 45,
        Bool.pick(U32, U32.is_eq(x, 38), 95,
          Bool.pick(U32, U32.is_eq(x, 39), 43, 126)))))}

# the code of the text after the last dot of a name: one pass, code
# and len restart at every dot, bad notes a symbol outside the set;
# isdot says whether the head is a dot. 1 stands for no extension, 2 for
# one too long or odd; a real code is 3 or more.
def ext.fin(+code: Nat, dotted: Bool, +len: Nat, bad: Bool) -> Nat:
  match dotted bad:
    case False{} _:
      1n
    case True{} True{}:
      2n
    case True{} False{}:
      Bool.pick(Nat, Bool.or(Nat.is_gt(len, 7n), Nat.is_eq(len, 0n)), 2n,
        Nat.add(code, 3n))

def ext.code(
  s: String, isdot: Bool, +code: Nat, +dotted: Bool, +len: Nat, +bad: Bool
) -> Nat:
  match s:
    case SNil{}:
      ext.fin(code, dotted, len, bad)
    case SCon{c, +t}:
      match isdot:
        case True{}:
          ext.code(t, dot(t), 0n, True{}, 0n, False{})
        case False{}:
          +d = sym(c)
          ext.code(t, dot(t),
            Bool.pick(Nat, Nat.is_lt(len, 7n), Nat.add(Nat.mul(code, 64n), d), code),
            dotted, 1n+len, Bool.or(bad, Nat.is_eq(d, 0n)))

def ext.of(nm: String) -> Nat:
  +s = nm
  ext.code(s, dot(s), 0n, False{}, 0n, False{})

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

# The tally: 2^14 slots, a code's home slot is code mod 16381, the
# next slot on a clash. The table is three arrays threaded through.
type Tally is Type:
  Tally{codes: Array<Nat>, sizes: Array<Nat>, counts: Array<Nat>}

def tally.new() -> Tally:
  Tally{[0n : Nat^14n], [0n : Nat^14n], [0n : Nat^14n]}

def tally.bump.fin(
  codes: Array<Nat>, counts: Array<Nat>, +i: U32, +sz: Nat, r: Array<Nat> & Nat
) -> Tally:
  (sizes, old) = r
  Tally{codes, Array.set(Nat, sizes, i, Nat.add(old, sz)), counts}

def tally.bump.go(
  codes: Array<Nat>, sizes: Array<Nat>, +i: U32, +sz: Nat, n: Nat,
  r: Array<Nat> & Nat
) -> Tally:
  (counts, old) = r
  tally.bump.fin(codes, Array.set(Nat, counts, i, Nat.add(n, old)), i, sz,
    Array.get(Nat, sizes, i))

# adds sz bytes and n files to slot i, which holds code (or is empty
# and takes it)
def tally.bump(t: Tally, +i: U32, code: Nat, sz: Nat, n: Nat) -> Tally:
  Tally{codes, sizes, counts} = t
  tally.bump.go(Array.set(Nat, codes, i, code), sizes, i, sz, n,
    Array.get(Nat, counts, i))

# is slot i free, or the slot of code? The array comes back beside it.
def tally.probe.fin(+code: Nat, r: Array<Nat> & Nat) -> Array<Nat> & Bool:
  (codes, +at) = r
  (codes, Bool.or(Nat.is_eq(at, 0n), Nat.is_eq(at, code)))

def tally.probe(codes: Array<Nat>, +i: U32, code: Nat) -> Array<Nat> & Bool:
  tally.probe.fin(code, Array.get(Nat, codes, i))

# fuel probes on from slot i, whose verdict rides in pr, to the slot of
# code: an empty one or its own
def tally.put.go(
  fuel: Nat, pr: Array<Nat> & Bool, sizes: Array<Nat>, counts: Array<Nat>,
  +i: U32, +code: Nat, sz: Nat, n: Nat
) -> Tally:
  match fuel:
    case 0n:
      (codes, stop) = pr
      Tally{codes, sizes, counts}
    case 1n+f:
      (codes, stop) = pr
      match stop:
        case True{}:
          tally.bump(Tally{codes, sizes, counts}, i, code, sz, n)
        case False{}:
          +j = U32.and(U32.add(i, 1), 16383)
          tally.put.go(f, tally.probe(codes, j, code), sizes, counts, j, code, sz,
            n)

# adds n files of sz bytes to the row of code
def tally.put.n(t: Tally, +code: Nat, sz: Nat, n: Nat) -> Tally:
  Tally{codes, sizes, counts} = t
  +i = U32.from_nat(Nat.mod(code, 16381n))
  tally.put.go(16384n, tally.probe(codes, i, code), sizes, counts, i, code, sz, n)

def tally.put(t: Tally, code: Nat, sz: Nat) -> Tally:
  tally.put.n(t, code, sz, 1n)

# two tallies as one: the rows of b added to a
def tally.merge.go(
  cs: List<Nat>, ss: List<Nat>, ns: List<Nat>, a: Tally
) -> Tally:
  match cs ss ns:
    case 0n <> ct s <> st n <> nt:
      tally.merge.go(ct, st, nt, a)
    case c <> ct s <> st n <> nt:
      tally.merge.go(ct, st, nt, tally.put.n(a, c, s, n))
    case _ _ _:
      a

def tally.merge(a: Tally, b: Tally) -> Tally:
  Tally{codes, sizes, counts} = b
  tally.merge.go(Array.to_list(~Nat, codes), Array.to_list(~Nat, sizes),
    Array.to_list(~Nat, counts), a)

# the tally of every file under xs; a directory's entries and the rest
# of the list are tallied in parallel, each into a fresh table, k
# levels down
def exts(xs: List<&2, Fs.Tree>, +k: Nat, t: Tally) -> Tally:
  match xs:
    case Nil{}:
      t
    case Fs.FsFile{nm, sz} <> rest:
      exts(rest, k, tally.put(t, ext.of(nm), sz))
    case Fs.FsDir{nm, sz, ks} <> rest:
      match k:
        case 0n:
          exts(rest, k, exts(ks, 0n, t))
        case 1n++j:
          a b = exts(ks, j, tally.new()) exts(rest, j, t)
          tally.merge(b, a)

# the filled slots as a list
def tally.rows(
  cs: List<Nat>, ss: List<Nat>, ns: List<Nat>, acc: List<&2, Ext>
) -> List<&2, Ext>:
  match cs ss ns:
    case 0n <> ct s <> st n <> nt:
      tally.rows(ct, st, nt, acc)
    case c <> ct s <> st n <> nt:
      tally.rows(ct, st, nt, Ext{ext.name(c), s, n} <> acc)
    case _ _ _:
      acc

def tally.list(t: Tally) -> List<&2, Ext>:
  Tally{codes, sizes, counts} = t
  tally.rows(Array.to_list(~Nat, codes), Array.to_list(~Nat, sizes),
    Array.to_list(~Nat, counts), Nil{})

def ext.row(+color: Bool, +total: Nat, e: Ext) -> String:
  match e:
    case Ext{nm, +sz, c}:
      Fmt.pad(Fmt.human(sz), 10n) ++ " " ++ Fmt.pad(Fmt.pct(sz, total), 6n) ++ " "
        ++ Fmt.pad(Fmt.commas(c), 11n) ++ "  " ++ Fmt.paint(color, "33", nm)

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
        List.sort(~Ext, ~ext.ge, tally.list(exts(ks, 8n, tally.new()))), k)), "\n")
