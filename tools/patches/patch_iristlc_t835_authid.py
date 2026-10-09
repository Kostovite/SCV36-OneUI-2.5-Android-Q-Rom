#!/usr/bin/env python3
"""T835 (Tab S4, Q) /system/lib64/libIrisTlc.so -> request layout of the S8 sec_iris TA for IrisTlc_GetAuthId.

The port runs the T835 irisd/libIrisTlc against the stock S8 sec_iris trustlet (the T835 TA is signed by another
root). Enrollment works, but every unlock fails: "authenticate IrisTlc_GetAuthId fail(-40)" -> error 1 ("iris
sensor not responding"). GetAuthId (cmd 13) hands the TA the sealed secure id (/data/system/users/0/bio/ir/sid.dat):
  S8 libIrisTlc (= S8 TA):  req[0]=13, sid at req+4,  len at req+1028                 (GetAuthId(out, sid, len))
  T835 libIrisTlc:          req[0]=13, type at req+4, sid at req+8, len at req+1032   (GetAuthId(out, type, sid, len))
-> the S8 TA unseals a blob shifted by 4 bytes and fails. (Inside the enroll session it still answered from its
in-memory id, which is why enrollment reported an authenticator id.) Every other IrisTlc request layout matches.
Patch (aarch64, IrisTlc_GetAuthId @0x6a58, file offset == vaddr):
  6b00 add x0, x20, #8          -> add x0, x20, #4
  6b10 str w21, [x20, #1032]    -> str w21, [x20, #1028]
  6b14 str w22, [x20, #4]       -> nop   (the type would overwrite the first sid word)
usage: patch_iristlc_t835_authid.py <in> <out>
"""
import hashlib, struct, sys

MD5 = 'a20ce3a89bc87164f4e11420d48149ec'   # SM-T835 Q libIrisTlc.so
PATCHES = [(0x6b00, 0x91002280, 0x91001280),
           (0x6b10, 0xb9040a95, 0xb9040695),
           (0x6b14, 0xb9000696, 0xd503201f)]
CONTEXT = [(0x6ae8, 0x528001a8),   # mov w8, #13   (cmd GetAuthId)
           (0x6b0c, 0x97ffeb33)]   # bl memcpy

src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
if hashlib.md5(d).hexdigest() != MD5:
    sys.exit('libIrisTlc.so: unexpected build (md5 %s)' % hashlib.md5(d).hexdigest())
for off, ins in CONTEXT:
    assert struct.unpack_from('<I', d, off)[0] == ins, 'context mismatch at 0x%x' % off
for off, old, new in PATCHES:
    assert struct.unpack_from('<I', d, off)[0] == old, 'pattern not found at 0x%x' % off
    struct.pack_into('<I', d, off, new)
open(dst, 'wb').write(d)
print('libIrisTlc: GetAuthId uses the S8 TA layout (sid at +4, len at +1028) -> %s' % dst)
