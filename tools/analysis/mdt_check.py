#!/usr/bin/env python3
"""Compare modem.mdt program headers with the split blob sizes (modem.bNN). usage: mdt_check.py <dir with modem.mdt + bNN>"""
import os, struct, sys
d = sys.argv[1]
m = open(os.path.join(d, 'modem.mdt'), 'rb').read()
cls = m[4]
if cls == 1:
    phoff, = struct.unpack_from('<I', m, 0x1c); phentsize, phnum = struct.unpack_from('<HH', m, 0x2a)
else:
    phoff, = struct.unpack_from('<Q', m, 0x20); phentsize, phnum = struct.unpack_from('<HH', m, 0x36)
lo, hi = None, 0
for i in range(phnum):
    o = phoff + i * phentsize
    if cls == 1:
        typ, off, va, pa, fsz, msz, flg, al = struct.unpack_from('<8I', m, o)
    else:
        typ, flg, off, va, pa, fsz, msz, al = struct.unpack_from('<IIQQQQQQ', m, o)
    b = os.path.join(d, 'modem.b%02d' % i)
    real = os.path.getsize(b) if os.path.exists(b) else None
    mark = '' if real in (None, fsz) else '  <-- MISMATCH'
    if typ == 1 and msz:
        lo = pa if lo is None else min(lo, pa); hi = max(hi, pa + msz)
    print(f'seg {i:2d} type {typ:#x} pa {pa:#010x} filesz {fsz:10d} memsz {msz:10d} file {real}{mark}')
print(f'image span {lo:#x}..{hi:#x} = {hi-lo:#x} bytes')
