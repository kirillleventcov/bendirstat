# bendirstat: the laws. The human states them; PROOF.bend must prove
# them. They pin the parallel folds of fs.bend to their sequential
# specs: what the scanner's tree is summed to, what the fused pass that
# prep runs computes, and what is counted.
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
  {Fs.names(Fs.sum(xs)) == Fs.names(xs) : List<&2, Fs.Name>}

# LAW: summing changes nothing but sizes: cleared of its sizes, the
# summed tree is the scanned one, at every depth (sum_keeps_names holds
# only the top of the list).
law sum_keeps_shape:
  for xs: List<&2, Fs.Tree>
  {Fs.shape(Fs.sum(xs)) == Fs.shape(xs) : List<&2, Fs.Tree>}

# LAW: the fused pass is sort after sum: what prep runs is what the laws
# on sum describe, ordered.
law tidy_is_sort_sum:
  for xs: List<&2, Fs.Tree>
  {Fs.tidy(xs) == Fs.sort(Fs.sum(xs)) : List<&2, Fs.Tree>}

# LAW: the parallel count is the sequential count of files and of
# directories.
law count_is_spec:
  for xs: List<&2, Fs.Tree>
  {Fs.count(xs) == (Fs.files(xs), Fs.dirs(xs)) : Nat & Nat}
