# scan.bend: the scanner, a foreign effect. It lives apart from fs.bend
# so that the proofs, which import fs.bend, rely on no foreign code.
import Base
import ./fs.bend as Fs

# scan(path, flags, threads, probe): the tree under path beside the
# count of entries it could not read. flags: 1 apparent sizes (else
# allocated blocks), 2 cross filesystems, 4 count every hard link (else
# the first only). threads: 0 for one per CPU. probe: Fs.probe(), from
# which the effect reads the tags of FsFile and FsDir (CID() cannot name
# another module's constructors).
def scan(path: String, flags: U32, threads: U32, probe: Fs.Tree) ->
  IO(Result<&1, &1, U32 & String, Fs.Tree & Nat>):
  import "./effs/fs_scan.c"
  import "./effs/fs_scan.js"
