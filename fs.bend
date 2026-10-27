# fs.bend: the scanned tree and the pure work over it.
#
# A Tree is a file with its size or a directory with its own inode size
# and its entries, as the scanner lays it. sum turns every directory's
# size into the total under it, in parallel over the tree; sort orders
# every directory's entries by size, descending; tidy does both in one
# pass. total is the sequential spec that LAWS.bend holds sum to, and
# sort after sum the spec it holds tidy to. Sizes are bytes, as Nat
# (native up to 2^48 - 1: 256 TiB).
import Base

# Name
# ----
#
# A name is its UTF-8 bytes, six to a chunk: a Nat (a native word under
# 2^48) with the first byte highest. No byte of a file name is 0, so a
# chunk's value tells how many bytes it holds. A name is a cell per six
# bytes where a String is a cell (and a count) per character: as Strings
# the names were most of the tree's memory and of the time to lay it out.
# text decodes one for printing.

type Name is Data:
  NEnd{}
  NMore{bytes: Nat, rest: Name}

# the bytes of a chunk, before acc; fuel bounds them
def chunk.bytes(fuel: Nat, +c: Nat, acc: List<&2, Nat>) -> List<&2, Nat>:
  match fuel:
    case 0n:
      acc
    case 1n+f:
      match c:
        case 0n:
          acc
        case 1n++p:
          chunk.bytes(f, Nat.div(1n+p, 256n), Nat.mod(1n+p, 256n) <> acc)

# the bytes of a name, in order
def bytes(nm: Name) -> List<&2, Nat>:
  match nm:
    case NEnd{}:
      Nil{}
    case NMore{c, rest}:
      chunk.bytes(6n, c, bytes(rest))

# what a byte starts in UTF-8: 0 a character of its own, 1 to 3 one
# that many continuation bytes follow, 4 nothing valid
def utf8.cls(+b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(b, 128n), 0n,
    Bool.pick(Nat, Nat.is_lt(b, 194n), 4n,
      Bool.pick(Nat, Nat.is_lt(b, 224n), 1n,
        Bool.pick(Nat, Nat.is_lt(b, 240n), 2n,
          Bool.pick(Nat, Nat.is_lt(b, 245n), 3n, 4n)))))

# the payload bits of a lead byte of class k
def utf8.lead(+b: Nat, +k: Nat) -> Nat:
  match k:
    case 0n:
      b
    case 1n:
      Nat.sub(b, 192n)
    case 2n:
      Nat.sub(b, 224n)
    case k2:
      Nat.sub(b, 240n)

def utf8.is_cont(+b: Nat) -> Bool:
  Bool.and(Nat.is_ge(b, 128n), Nat.is_lt(b, 192n))

# the verdicts on the head of a byte list: its class, and whether it
# continues a character
def utf8.head.cls(bs: List<&2, Nat>) -> Nat:
  match bs:
    case Nil{}:
      0n
    case b <> t:
      utf8.cls(b)

def utf8.head.cont(bs: List<&2, Nat>) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case b <> t:
      utf8.is_cont(b)

# a code with a continuation byte's six bits after it
def utf8.more(code: Nat, +b: Nat) -> Nat:
  Nat.add(Nat.mul(code, 64n), Nat.sub(b, 128n))

def chr(+n: Nat) -> Char:
  Chr{U32.from_nat(n)}

def bad() -> Char:
  Chr{65533}

# a lead byte b of class k, then the text of t: a character, a bad byte,
# or the start of a longer character
def utf8.start(+b: Nat, +k: Nat, rest: Nat -> Nat -> String) -> String:
  match k:
    case 0n:
      SCon{chr(b), rest(0n, 0n)}
    case 4n:
      SCon{bad(), rest(0n, 0n)}
    case 1n+n:
      rest(1n+n, utf8.lead(b, 1n+n))

# UTF-8 decoding: need continuation bytes are due for the character code
# so far; cont and k are the verdicts on the head. A byte that breaks a
# character becomes U+FFFD and starts afresh, as the runtime decodes.
def utf8.go(
  bs: List<&2, Nat>, +need: Nat, cont: Bool, k: Nat, +code: Nat
) -> String:
  match bs need cont:
    case Nil{} 0n _:
      SNil{}
    case Nil{} 1n+p _:
      SCon{bad(), SNil{}}
    case +b <> +t 0n _:
      utf8.start(b, k, n => c => utf8.go(t, n, utf8.head.cont(t),
        utf8.head.cls(t), c))
    case +b <> +t 1n True{}:
      SCon{chr(utf8.more(code, b)), utf8.go(t, 0n, utf8.head.cont(t),
        utf8.head.cls(t), 0n)}
    case +b <> +t n True{}:
      utf8.go(t, Nat.sub(n, 1n), utf8.head.cont(t), utf8.head.cls(t),
        utf8.more(code, b))
    case +b <> +t n False{}:
      SCon{bad(), utf8.start(b, k, n => c => utf8.go(t, n, utf8.head.cont(t),
        utf8.head.cls(t), c))}

# the text of a name
def text(nm: Name) -> String:
  +bs = bytes(nm)
  utf8.go(bs, 0n, utf8.head.cont(bs), utf8.head.cls(bs), 0n)

# Tree
# ----

type Tree is Data:
  FsFile{name: Name, size: Nat}
  FsDir{name: Name, size: Nat, kids: List<&2, Tree>}

# an empty directory, where no entry is found
def blank() -> Tree:
  FsDir{NEnd{}, 0n, Nil{}}

# a directory holding a file, each named by one chunk: the scanner reads
# the tags of FsFile, FsDir, NMore and NEnd off it
def probe() -> Tree:
  FsDir{NMore{1n, NEnd{}}, 0n, [FsFile{NMore{1n, NEnd{}}, 0n}]}

def size(t: Tree) -> Nat:
  match t:
    case FsFile{nm, sz}:
      sz
    case FsDir{nm, sz, ks}:
      sz

def name(t: Tree) -> Name:
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

def sum.dir(nm: Name, sz: Nat, +ks: List<&2, Tree>, rest: List<&2, Tree>) ->
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
def names(xs: List<&2, Tree>) -> List<&2, Name>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      name(h) <> names(t)

# spec: a list with every size cleared, the names and entries kept at
# every depth
def shape(xs: List<&2, Tree>) -> List<&2, Tree>:
  match xs:
    case Nil{}:
      Nil{}
    case FsFile{nm, sz} <> t:
      FsFile{nm, 0n} <> shape(t)
    case FsDir{nm, sz, ks} <> t:
      FsDir{nm, 0n, shape(ks)} <> shape(t)

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

# every directory summed and its entries ordered, in one pass: what sort
# gives after sum (law tidy_is_sort_sum), with half the nodes built. A
# directory's entries and the rest of its list are done in parallel.
def tidy.dir(nm: Name, sz: Nat, +ks: List<&2, Tree>, rest: List<&2, Tree>) ->
  List<&2, Tree>:
  FsDir{nm, Nat.add(sz, top(ks)), List.sort(~Tree, ~ge, ks)} <> rest

def tidy(xs: List<&2, Tree>) -> List<&2, Tree>:
  match xs:
    case Nil{}:
      Nil{}
    case FsFile{nm, sz} <> t:
      FsFile{nm, sz} <> tidy(t)
    case FsDir{nm, sz, ks} <> t:
      a b = tidy(ks) tidy(t)
      tidy.dir(nm, sz, a, b)

# the scanned root, summed and sorted
def prep.dir(nm: Name, sz: Nat, +ks: List<&2, Tree>) -> Tree:
  FsDir{nm, Nat.add(sz, top(ks)), List.sort(~Tree, ~ge, ks)}

def prep(t: Tree) -> Tree:
  match t:
    case FsFile{nm, sz}:
      FsFile{nm, sz}
    case FsDir{nm, sz, ks}:
      prep.dir(nm, sz, tidy(ks))

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
