"""Repack a Samsung (header v0) boot.img using a stock image as template.
usage: python tools/build/mkboot.py <template boot.img> <out.img> --kernel Image.gz [--dtb a.dtb ...] [--ramdisk r.cpio.gz]
                              [--cmdline "full cmdline"] [--cmdline-add "k=v ..."] [--osver-from other_boot.img]
Kernel = Image.gz with DTBs appended (Image.gz-dtb, as stock). Header fields (addresses, page size, os_version, board
name, cmdline) are kept from the template; sizes and the SHA-1 id are recomputed; SEANDROIDENFORCE footer appended."""
import argparse, hashlib, struct

ap = argparse.ArgumentParser()
ap.add_argument('template'); ap.add_argument('out')
ap.add_argument('--kernel', required=True)
ap.add_argument('--dtb', nargs='*', default=[])
ap.add_argument('--ramdisk')
ap.add_argument('--cmdline', help='replace the template cmdline')
ap.add_argument('--cmdline-add', default='')
ap.add_argument('--osver-from', help='take os_version/patch level from this boot.img (keymaster sees it)')
a = ap.parse_args()

t = open(a.template, 'rb').read()
assert t[:8] == b'ANDROID!'
ksz, kaddr, rsz, raddr, ssz, saddr, tags, page, hver, osver = struct.unpack('<10I', t[8:48])
assert hver == 0, 'only header v0 supported'
name = t[48:64]; cmd = t[64:576].rstrip(b'\0'); extra = t[608:1632]
pg = lambda n: (n + page - 1) // page * page
stock_ramdisk = t[page + pg(ksz): page + pg(ksz) + rsz]

kernel = open(a.kernel, 'rb').read() + b''.join(open(d, 'rb').read() for d in a.dtb)
ramdisk = open(a.ramdisk, 'rb').read() if a.ramdisk else stock_ramdisk
if a.cmdline:
    cmd = a.cmdline.encode()
if a.osver_from:
    o = open(a.osver_from, 'rb').read(48)
    assert o[:8] == b'ANDROID!'
    osver = struct.unpack('<I', o[44:48])[0]
if a.cmdline_add:
    cmd = (cmd.decode() + ' ' + a.cmdline_add).strip().encode()
assert len(cmd) < 512, 'cmdline too long for v0 header'

sha = hashlib.sha1()
for blob in (kernel, ramdisk, b''):
    sha.update(blob); sha.update(struct.pack('<I', len(blob)))
hdr = b'ANDROID!' + struct.pack('<10I', len(kernel), kaddr, len(ramdisk), raddr, 0, saddr, tags, page, 0, osver)
hdr += name + cmd.ljust(512, b'\0') + sha.digest().ljust(32, b'\0') + extra
hdr = hdr.ljust(page, b'\0')
img = hdr + kernel.ljust(pg(len(kernel)), b'\0') + ramdisk.ljust(pg(len(ramdisk)), b'\0')
img += b'SEANDROIDENFORCE'
open(a.out, 'wb').write(img)
v = osver >> 11; pl = osver & 0x7ff
print(f'{a.out}: os {v >> 14}.{(v >> 7) & 0x7f}.{v & 0x7f} patch {2000 + (pl >> 4)}-{pl & 0xf:02d}; {len(img)} bytes, kernel {len(kernel)} (+{len(a.dtb)} dtb), ramdisk {len(ramdisk)}, cmdline: {cmd.decode()}')
