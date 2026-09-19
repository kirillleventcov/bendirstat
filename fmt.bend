# fmt.bend: text for sizes, shares and bars.
import Base

# "1.5 GiB": the largest binary unit under the size, to a tenth
def dec.fin(qr: Nat & Nat) -> String:
  (q, r) = qr
  Nat.show(q) ++ "." ++ Nat.show(r)

# a count of tenths as "q.r"
def dec(tenths: Nat) -> String:
  dec.fin(Nat.divmod(tenths, 10n))

def scaled.fin(unit: String, qr: Nat & Nat) -> String:
  (t, r) = qr
  dec(t) ++ " " ++ unit

# n in units of base, to a tenth
def scaled(n: Nat, base: Nat, unit: String) -> String:
  scaled.fin(unit, Nat.divmod(Nat.mul(n, 10n), base))

# small: n is under base * 1024, so this unit is the one
def human.go(units: List<&2, String>, +n: Nat, +base: Nat, small: Bool) ->
  String:
  match units:
    case Nil{}:
      scaled(n, base, "PiB")
    case u <> rest:
      match small:
        case True{}:
          scaled(n, base, u)
        case False{}:
          +b2 = Nat.mul(base, 1024n)
          human.go(rest, n, b2, Nat.is_lt(n, Nat.mul(b2, 1024n)))

def human.fin(+n: Nat, bytes: Bool) -> String:
  match bytes:
    case True{}:
      Nat.show(n) ++ " B"
    case False{}:
      human.go(["KiB", "MiB", "GiB", "TiB"], n, 1024n,
        Nat.is_lt(n, 1048576n))

def human(+n: Nat) -> String:
  human.fin(n, Nat.is_lt(n, 1024n))

# n as a share of total, "12.3%"
def pct.fin(qr: Nat & Nat) -> String:
  (q, r) = qr
  Nat.show(q) ++ "." ++ Nat.show(r) ++ "%"

# tenths of a percent of n over total; a big total is measured in KiB
# first, so n * 1000 stays under the largest Nat
def pct.go(+n: Nat, +total: Nat, big: Bool) -> Nat:
  match big:
    case True{}:
      Nat.div(Nat.mul(Nat.div(n, 1024n), 1000n), Nat.div(total, 1024n))
    case False{}:
      Nat.div(Nat.mul(n, 1000n), total)

def pct(+n: Nat, total: Nat) -> String:
  match total:
    case 0n:
      "0.0%"
    case 1n++p:
      pct.fin(Nat.divmod(pct.go(n, 1n+p, Nat.is_gt(p, 1073741823n)), 10n))

# a bar of w cells, n / total of them filled
def bar.fin(+w: Nat, +filled: Nat) -> String:
  String.repeat("█", Nat.min(filled, w))
    ++ String.repeat("░", Nat.sub(w, filled))

def bar(+n: Nat, total: Nat, +w: Nat) -> String:
  match total:
    case 0n:
      bar.fin(w, 0n)
    case 1n++p:
      bar.fin(w, Nat.div(Nat.mul(n, w), 1n+p))

# s padded with spaces on the left to w cells
def pad(+s: String, w: Nat) -> String:
  String.repeat(" ", Nat.sub(w, String.length(s))) ++ s

# s padded with spaces on the right to w cells
def padr(+s: String, w: Nat) -> String:
  s ++ String.repeat(" ", Nat.sub(w, String.length(s)))

# a count with thousands separators: 1234567 -> 1,234,567
def commas.go(cs: List<&2, Char>, +i: Nat, acc: String) -> String:
  match cs:
    case Nil{}:
      acc
    case c <> rest:
      match i:
        case 0n:
          commas.go(rest, 2n, SCon{c, SCon{',', acc}})
        case 1n+j:
          commas.go(rest, j, SCon{c, acc})

def commas(n: Nat) -> String:
  commas.go(String.to_list(String.reverse(Nat.show(n))), 3n, "")

# ANSI
# ----

def esc(code: String) -> String:
  "\u{1b}[" ++ code ++ "m"

def paint(on: Bool, code: String, +s: String) -> String:
  match on:
    case True{}:
      esc(code) ++ s ++ esc("0")
    case False{}:
      s
