#!/usr/bin/env python3
"""Parse a Qualcomm MCFG profile (mcfg_sw.mbn) and list the items it sets: NV item ids and EFS file paths (with a
short preview of small values). Best-effort format: 'MCFG' header, then items [len u32][type u8][attrib u8][u16]...
usage: mcfg_parse.py <mcfg_sw.mbn> [--grep REGEX]"""
import re, struct, sys

d = open(sys.argv[1], 'rb').read()
pat = re.compile(sys.argv[sys.argv.index('--grep') + 1], re.I) if '--grep' in sys.argv else None
o = d.find(b'MCFG')
if o < 0:
    sys.exit('no MCFG header')
fmt, cfg_type, nitems = struct.unpack_from('<HHI', d, o + 4)
p = o + 24   # 16-byte header + 8-byte config version
out = []
for i in range(nitems):
    if p + 8 > len(d):
        break
    ln, typ, attr = struct.unpack_from('<IBB', d, p)
    if ln < 8 or p + ln > len(d):
        break
    body = d[p + 8:p + ln]
    if typ == 1 and len(body) >= 4:                     # NV item: id u16, size u16, data
        nid, sz = struct.unpack_from('<HH', body, 0)
        out.append(f'NV {nid:<6d} {body[4:4 + sz][:16].hex()}')
    elif typ in (2, 4, 5) and len(body) >= 4:           # EFS file: [tag u16=1][len u16][path] [tag u16=2][len u16][data]
        q, path, data = 0, '', b''
        while q + 4 <= len(body):
            tag, tl = struct.unpack_from('<HH', body, q)
            val = body[q + 4:q + 4 + tl]
            if tag == 1:
                path = val.rstrip(b'\0').decode(errors='replace')
            elif tag == 2:
                data = val
            q += 4 + tl
        prev = data[:24].decode(errors='replace') if data[:1].isascii() and data[:1] != b'\0' else data[:12].hex()
        out.append(f'EFS {path} ({len(data)} B) {prev!r}')
    else:
        out.append(f'type{typ} len{ln}')
    p += ln
print(f'MCFG fmt={fmt} cfg_type={cfg_type} items={nitems} parsed={len(out)}')
for l in out:
    if not pat or pat.search(l):
        print(' ', l)
