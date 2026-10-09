#!/usr/bin/env python3
"""G9600 Q /system/lib/libcameraservice.so: restore the Pie CameraClient display-orientation rule.

CameraClient::sendCommand(CAMERA_CMD_SET_DISPLAY_ORIENTATION = 3, degrees, arg2):
  Pie (AOSP):      transform = getOrientation(degrees, facing == FRONT)      -> front preview mirrored by the framework
  Q (Samsung):     arg2 == 1 -> unmirrored transform for every camera ("the app mirrors itself"), else as Pie
The S8 SamsungCamera 9.0 was written for Pie and passes arg2 = 1, while it also asks the HAL for its own horizontal
flip (sendCommand 1510 "VT flip mode"). On Q the framework mirror is then missing: FLIP_H before ROT_90 shows the
front preview upside down. Fix: `cmp.w r11, #1` (arg2) -> `cmp.w r11, #0x80000000`, i.e. the arg2 branch is never
taken and every client gets the Pie behaviour (normal apps pass arg2 = 0 and are unaffected).

Disassembly (thumb, G9600ZHU9FZC1 libcameraservice.so md5 a34e7469ffed7e77c3b0b132d2facfb0):
  a3440: f1bb 0f01   cmp.w r11, #0x1
  a3444: f040 80a6   bne.w 0xa3594      ; facing-based (Pie) path
usage: patch_cameraservice_orientation.py <in> <out>
"""
import hashlib, sys

OFF = 0xa3440                       # file offset == vaddr (first LOAD segment at 0)
OLD = bytes.fromhex('bbf1010f')     # cmp.w r11, #1
NEW = bytes.fromhex('bbf1004f')     # cmp.w r11, #0x80000000
NEXT = bytes.fromhex('40f0a680')    # bne.w 0xa3594 (sanity check of the context)
MD5 = 'a34e7469ffed7e77c3b0b132d2facfb0'

src, dst = sys.argv[1], sys.argv[2]
d = bytearray(open(src, 'rb').read())
if hashlib.md5(d).hexdigest() != MD5:
    sys.exit('libcameraservice.so: unexpected build (md5 %s) - re-check the offsets' % hashlib.md5(d).hexdigest())
assert d[OFF:OFF + 4] == OLD and d[OFF + 4:OFF + 8] == NEXT, 'pattern not found at 0x%x' % OFF
d[OFF:OFF + 4] = NEW
open(dst, 'wb').write(d)
print('libcameraservice: SET_DISPLAY_ORIENTATION arg2 branch disabled (Pie front-camera mirror) -> %s' % dst)
