#!/usr/bin/env python3
"""G9600 Q /system/lib/libcameraservice.so: let API1 getCameraInfo() reach Samsung hidden camera ids (iris = 90).

The iris stack (T835 SecIrisService, IRController HAL_V1) opens the IR camera with SemCamera.open(90) and first asks
CameraService::getCameraInfo(90). The camera side is all there: the T835 SehCameraProvider probes its hidden-id table
(.. 90, 91, 92) through the S8 HAL, which answers "mapping system camera id 90 -> 3", so the provider registers
device "90". But the G9600 getCameraInfo(int) is the AOSP one:
    if (cameraId < 0 || cameraId >= mNumberOfCameras) return ILLEGAL_ARGUMENT;      // 2 public cameras -> 90 rejected
    id = cameraId < mNormalDeviceIds.size() ? mNormalDeviceIds[cameraId] : "";
-> IRV1Controller "Camera failed to open: Fail to get camera info", the IR camera never starts.
The T835 build of the same function only rejects cameraId < 0 and uses std::to_string(cameraId) as the device id.
Patch (thumb, on top of patch_cameraservice_orientation.py; md5 4de7755d82b043fbfcc771bb4725be7a):
  86b7c: it ge; ldrge r0,[r6,#116]; it ge; cmpge r0,r7; bgt 86c04  ->  bge 86c04; nop x4   (only < 0 rejected)
  86c34: (log "not a normal id" + empty id)  ->  add r0,sp,#16; mov r1,r7; blx std::to_string(int); b 86c56
  cameraIdIntToStrLocked (API1 connect, "input id 90 invalid: valid range (0, 2)"): same rule - id >= size ->
  std::to_string(id), id < 0 -> "" (no log); and its inlined copy in cameraIdIntToStr(int) (what connect() calls).
Public ids 0/1 still go through mNormalDeviceIds; ids the provider does not know still fail in
CameraProviderManager::getCameraInfo (connect keeps its own hidden-id / iris-package checks).
usage: patch_cameraservice_hiddenid.py <in> <out>
"""
import hashlib, struct, sys

MD5 = '4de7755d82b043fbfcc771bb4725be7a'      # G9600ZHU9FZC1 + orientation patch
TO_STRING_INT_PLT = 0x10fde0                    # _ZNSt3__19to_stringEi (rel.plt idx 174, 16-byte ARM stubs)


def blx(a, t):
    """Thumb-2 BLX (immediate, T2) at a -> ARM target t."""
    off = t - ((a + 4) & ~3)
    assert off % 4 == 0 and -(1 << 24) <= off < (1 << 24)
    s = (off >> 24) & 1; i1 = (off >> 23) & 1; i2 = (off >> 22) & 1
    j1 = (~(i1 ^ s)) & 1; j2 = (~(i2 ^ s)) & 1
    hi = 0xf000 | (s << 10) | ((off >> 12) & 0x3ff)
    lo = 0xc000 | (j1 << 13) | (j2 << 11) | ((off >> 2) & 0x3ff) << 1
    return struct.pack('<HH', hi, lo)


assert blx(0x86c2e, 0x10fbd0) == bytes.fromhex('88f0d0ef')   # existing "blx 0x10fbd0" in this function

PATCHES = [
    (0x86b7c, bytes.fromhex('a8bf706fa8bfb8423edc'),                    # it ge; ldrge; it ge; cmpge; bgt 86c04
              bytes.fromhex('42da00bf00bf00bf00bf')),                    # bge 86c04; nop x4
    (0x86c34, None,                                                      # checked below (log + empty string)
              bytes.fromhex('04a83946') + blx(0x86c38, TO_STRING_INT_PLT) + bytes.fromhex('0be0')),
    # cameraIdIntToStrLocked(int) (API1 connect: "input id 90 invalid: valid range (0, 2)" -> connect to camera ""):
    #   86d90 (id < 0): ldrd r0,r1,[r1,#120]  -> b 86db8 (empty string); nop
    #   86d94 (id >= size): log + empty string -> mov r0,r5; mov r1,r2; blx to_string(int); add sp,#8; pop {r4,r5,r7,pc}
    (0x86d90, bytes.fromhex('d1e91e01'), bytes.fromhex('12e000bf')),
    (0x86d94, bytes.fromhex('081a4af6ab21'),
              bytes.fromhex('28461146') + blx(0x86d98, TO_STRING_INT_PLT) + bytes.fromhex('02b0b0bd')),
    # cameraIdIntToStr(int) -> String8, what API1 connect() calls: the Locked logic is inlined into it (same log
    # text), building a std::string at sp+8 that 86ec6.. turns into the String8.
    #   86ed4 (id < 0): ldrd r0,r1,[r7,#120] -> b 86efc (empty string); nop
    #   86ed8 (id >= size): log + empty -> add r0,sp,#8; mov r1,r6; blx to_string(int); b 86ec6 (normal-path tail)
    (0x86ed4, bytes.fromhex('d7e91e01'), bytes.fromhex('12e000bf')),
    (0x86ed8, bytes.fromhex('081a4af6ab211c4a'),
              bytes.fromhex('02a83146') + blx(0x86edc, TO_STRING_INT_PLT) + bytes.fromhex('f1e7')),
]

src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
if hashlib.md5(d).hexdigest() != MD5:
    sys.exit('libcameraservice.so: unexpected build (md5 %s) - re-check the offsets' % hashlib.md5(d).hexdigest())
# context: cmp r7,#0 before the bounds check; else-branch starts with the log literal loads, joins at 86c56
assert d[0x86b7a:0x86b7c] == bytes.fromhex('002f'), 'cmp r7,#0 not at 0x86b7a'
assert d[0x86c20:0x86c24] == bytes.fromhex('b94207dd'), 'cmp r1,r7; ble 86c34 not at 0x86c20'
assert d[0x86c34:0x86c38] == bytes.fromhex('3c4a3d4b'), 'else-branch literal loads not at 0x86c34'
assert d[0x86c56:0x86c5a] == bytes.fromhex('04a95846'), 'join (add r1,sp,#16; mov r0,fp) not at 0x86c56'
assert d[0x86d7a:0x86d7e] == bytes.fromhex('93420add'), 'cameraIdIntToStrLocked: cmp r3,r2; ble 86d94 not at 0x86d7a'
assert d[0x86db8:0x86dc8] == bytes.fromhex('c0ef1000002045f90d07286002b0b0bd'), 'empty-string tail not at 0x86db8'
assert d[0x86eb4:0x86eb8] == bytes.fromhex('b2420fdd'), 'cameraIdIntToStr: cmp r2,r6; ble 86ed8 not at 0x86eb4'
assert d[0x86ec6:0x86eca] == bytes.fromhex('9df80800'), 'cameraIdIntToStr: ldrb r0,[sp,#8] not at 0x86ec6'
assert d[0x86efc:0x86f02] == bytes.fromhex('c0ef100002a9'), 'cameraIdIntToStr: empty-string path not at 0x86efc'
for off, old, new in PATCHES:
    if old is not None:
        assert d[off:off + len(old)] == old, 'pattern not found at 0x%x' % off
    d[off:off + len(new)] = new
open(dst, 'wb').write(d)
print('libcameraservice: getCameraInfo accepts hidden camera ids (std::to_string) -> %s' % dst)
