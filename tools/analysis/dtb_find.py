#!/usr/bin/env python3
"""Find device-tree node paths whose 'compatible' contains a string, in a (possibly concatenated) DTB file.
usage: dtb_find.py <file.dtb> <compatible substring>"""
import struct, sys
data = open(sys.argv[1], 'rb').read(); want = sys.argv[2].encode()
off, seen = 0, set()
while True:
    off = data.find(b'\xd0\x0d\xfe\xed', off)
    if off < 0: break
    tot, ostruct, ostr = struct.unpack_from('>III', data, off + 4)
    if not (64 < tot < 4 << 20 and ostruct < tot and ostr < tot):
        off += 4; continue
    p, path = off + ostruct, []
    while p < off + tot and (path or p == off + ostruct):
        tok, = struct.unpack_from('>I', data, p); p += 4
        if tok == 1:
            e = data.index(b'\0', p); path.append(data[p:e].decode() or '/'); p = (e + 4) & ~3
        elif tok == 2:
            path.pop()
            if not path: break
        elif tok == 3:
            ln, no = struct.unpack_from('>II', data, p); p += 8
            name = data[off + ostr + no: data.index(b'\0', off + ostr + no)]
            val = data[p:p + ln]; p = (p + ln + 3) & ~3
            if name == b'compatible' and want in val:
                seen.add('/'.join(path).replace('//', '/'))
        elif tok == 9: break
    off += max(tot, 4)
print('\n'.join(sorted(seen)) or 'not found')
