#!/usr/bin/env python3
"""Make the S8 Pie fingerprint.default.so (HAL 2.1) acceptable to the G9600 fingerprint@3.0 service.
Boot 18: "Wrong fp version. Expected 768, got 513" / "Can't open HAL module". The service compares
fingerprint_device_t.common.version (hw_device_t +4) with exactly 0x300. Both modules build the same device struct
(0xf8 bytes, identical ss_fingerprint_* function-pointer slots 112..208 - checked by disassembly), so only the
version differs: the 8-byte {'HWDT', 0x201} constant the S8 open() loads, and HMI.module_api_version.
usage: python3 patch_fp_module_version.py <vendor>/lib64/hw/fingerprint.default.so"""
import re, subprocess, sys

f = sys.argv[1]
b = bytearray(open(f, 'rb').read())
new = b'TDWH\x00\x03\x00\x00'
if b.count(new) == 1:
    print('already patched'); sys.exit(0)
old = b'TDWH\x01\x02\x00\x00'            # little-endian u32 tag 'HWDT' + u32 version 0x201
assert b.count(old) == 1, 'device header constant count %d' % b.count(old)
b[b.find(old):b.find(old) + 8] = new

# HMI (hw_module_t): tag 'HWMT', u16 module_api_version, u16 hal_api_version
syms = subprocess.run(['readelf', '-sW', f], capture_output=True, text=True).stdout
hmi = int(next(l.split()[1] for l in syms.splitlines() if l.strip().endswith(' HMI')), 16)
for l in subprocess.run(['readelf', '-SW', f], capture_output=True, text=True).stdout.splitlines():
    m = re.search(r'\]\s+\S+\s+\S+\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)', l)
    if m and int(m.group(1), 16) and int(m.group(1), 16) <= hmi < int(m.group(1), 16) + int(m.group(3), 16):
        o = int(m.group(2), 16) + hmi - int(m.group(1), 16)
        break
assert b[o:o + 4] == b'TMWH' and b[o + 4:o + 6] == b'\x01\x02', 'unexpected HMI header %r' % bytes(b[o:o + 8])
b[o + 4:o + 6] = b'\x00\x03'
open(f, 'wb').write(b)
print('fingerprint module version 0x201 -> 0x300 (device header + HMI @%#x)' % o)
