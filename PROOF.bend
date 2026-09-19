# bendirstat: the proofs, by induction on the list, the entries of a
# directory as the nested case. A parallel let is two calls: the
# induction hypotheses on a directory's entries and on the rest of the
# list rewrite the spec's side into the fold's, and reflexivity closes.
import Base
import ./fs.bend as Fs
import ./LAWS.bend as Laws

def Laws.sum_is_total(xs):
  match xs:
    case Nil{}:
      {==}
    case Fs.FsFile{nm, sz} <> t:
      %Laws.sum_is_total(t) : {Nat.add(sz, Fs.top(Fs.sum(t))) == Nat.add(sz, _) : Nat}
      {==}
    case Fs.FsDir{nm, sz, ks} <> t:
      %Laws.sum_is_total(ks) : {Nat.add(Nat.add(sz, Fs.top(Fs.sum(ks))), Fs.top(Fs.sum(t))) == Nat.add(Nat.add(sz, _), Fs.total(t)) : Nat}
      %Laws.sum_is_total(t) : {Nat.add(Nat.add(sz, Fs.top(Fs.sum(ks))), Fs.top(Fs.sum(t))) == Nat.add(Nat.add(sz, Fs.top(Fs.sum(ks))), _) : Nat}
      {==}

def Laws.sum_keeps_names(xs):
  match xs:
    case Nil{}:
      {==}
    case Fs.FsFile{nm, sz} <> t:
      %Laws.sum_keeps_names(t) : {nm <> Fs.names(Fs.sum(t)) == nm <> _ : List<&2, String>}
      {==}
    case Fs.FsDir{nm, sz, ks} <> t:
      %Laws.sum_keeps_names(t) : {nm <> Fs.names(Fs.sum(t)) == nm <> _ : List<&2, String>}
      {==}

# a pair is the pair of its parts
def pair_is(p: Nat & Nat) -> {(Pair.fst(Nat, Nat, p), Pair.snd(Nat, Nat, p)) == p : Nat & Nat}:
  (a, b) = p
  {==}

def Laws.count_is_spec(xs):
  match xs:
    case Nil{}:
      {==}
    case Fs.FsFile{nm, sz} <> +t:
      %pair_is(Fs.count(t)) : {Fs.count.file(_) == (1n+Fs.files(t), Fs.dirs(t)) : Nat & Nat}
      %Equal.cong(Nat & Nat, Nat, Pair.fst(Nat, Nat), Fs.count(t), (Fs.files(t), Fs.dirs(t)), Laws.count_is_spec(t)) : {(1n+Pair.fst(Nat, Nat, Fs.count(t)), Pair.snd(Nat, Nat, Fs.count(t))) == (1n+_, Fs.dirs(t)) : Nat & Nat}
      %Equal.cong(Nat & Nat, Nat, Pair.snd(Nat, Nat), Fs.count(t), (Fs.files(t), Fs.dirs(t)), Laws.count_is_spec(t)) : {(1n+Pair.fst(Nat, Nat, Fs.count(t)), Pair.snd(Nat, Nat, Fs.count(t))) == (1n+Pair.fst(Nat, Nat, Fs.count(t)), _) : Nat & Nat}
      {==}
    case Fs.FsDir{nm, sz, +ks} <> +t:
      %pair_is(Fs.count(ks)) : {Fs.count.dir(_, Fs.count(t)) == (Nat.add(Fs.files(ks), Fs.files(t)), 1n+Nat.add(Fs.dirs(ks), Fs.dirs(t))) : Nat & Nat}
      %pair_is(Fs.count(t)) : {Fs.count.dir((Pair.fst(Nat, Nat, Fs.count(ks)), Pair.snd(Nat, Nat, Fs.count(ks))), _) == (Nat.add(Fs.files(ks), Fs.files(t)), 1n+Nat.add(Fs.dirs(ks), Fs.dirs(t))) : Nat & Nat}
      %Equal.cong(Nat & Nat, Nat, Pair.fst(Nat, Nat), Fs.count(ks), (Fs.files(ks), Fs.dirs(ks)), Laws.count_is_spec(ks)) : {(Nat.add(Pair.fst(Nat, Nat, Fs.count(ks)), Pair.fst(Nat, Nat, Fs.count(t))), 1n+Nat.add(Pair.snd(Nat, Nat, Fs.count(ks)), Pair.snd(Nat, Nat, Fs.count(t)))) == (Nat.add(_, Fs.files(t)), 1n+Nat.add(Fs.dirs(ks), Fs.dirs(t))) : Nat & Nat}
      %Equal.cong(Nat & Nat, Nat, Pair.fst(Nat, Nat), Fs.count(t), (Fs.files(t), Fs.dirs(t)), Laws.count_is_spec(t)) : {(Nat.add(Pair.fst(Nat, Nat, Fs.count(ks)), Pair.fst(Nat, Nat, Fs.count(t))), 1n+Nat.add(Pair.snd(Nat, Nat, Fs.count(ks)), Pair.snd(Nat, Nat, Fs.count(t)))) == (Nat.add(Pair.fst(Nat, Nat, Fs.count(ks)), _), 1n+Nat.add(Fs.dirs(ks), Fs.dirs(t))) : Nat & Nat}
      %Equal.cong(Nat & Nat, Nat, Pair.snd(Nat, Nat), Fs.count(ks), (Fs.files(ks), Fs.dirs(ks)), Laws.count_is_spec(ks)) : {(Nat.add(Pair.fst(Nat, Nat, Fs.count(ks)), Pair.fst(Nat, Nat, Fs.count(t))), 1n+Nat.add(Pair.snd(Nat, Nat, Fs.count(ks)), Pair.snd(Nat, Nat, Fs.count(t)))) == (Nat.add(Pair.fst(Nat, Nat, Fs.count(ks)), Pair.fst(Nat, Nat, Fs.count(t))), 1n+Nat.add(_, Fs.dirs(t))) : Nat & Nat}
      %Equal.cong(Nat & Nat, Nat, Pair.snd(Nat, Nat), Fs.count(t), (Fs.files(t), Fs.dirs(t)), Laws.count_is_spec(t)) : {(Nat.add(Pair.fst(Nat, Nat, Fs.count(ks)), Pair.fst(Nat, Nat, Fs.count(t))), 1n+Nat.add(Pair.snd(Nat, Nat, Fs.count(ks)), Pair.snd(Nat, Nat, Fs.count(t)))) == (Nat.add(Pair.fst(Nat, Nat, Fs.count(ks)), Pair.fst(Nat, Nat, Fs.count(t))), 1n+Nat.add(Pair.snd(Nat, Nat, Fs.count(ks)), _)) : Nat & Nat}
      {==}
