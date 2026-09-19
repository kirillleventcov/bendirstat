# bendirstat: the laws. The human states them; PROOF.bend must prove
# them. They pin the parallel folds of fs.bend to their sequential
# specs: what the scanner's tree is summed to, and what is counted.
import Base
import ./fs.bend as Fs

# LAW: the parallel sum gives every directory the bytes under it: the
# sizes at the top of a summed list add up to the sequential total.
law sum_is_total:
  for xs: List<&2, Fs.Tree>
  {Fs.top(Fs.sum(xs)) == Fs.total(xs) : Nat}

# LAW: summing keeps the entries: the same names, in the same order.
law sum_keeps_names:
  for xs: List<&2, Fs.Tree>
  {Fs.names(Fs.sum(xs)) == Fs.names(xs) : List<&2, String>}

# LAW: the parallel count is the sequential count of files and of
# directories.
law count_is_spec:
  for xs: List<&2, Fs.Tree>
  {Fs.count(xs) == (Fs.files(xs), Fs.dirs(xs)) : Nat & Nat}
