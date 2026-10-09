"""Extract a (gzipped) newc cpio ramdisk. usage: python cpio_extract.py ramdisk.cpio.gz out_dir
Symlinks are written as text files '<name>.symlink' (Windows-safe); modes saved to _modes.txt."""
import sys, os, gzip
src, out = sys.argv[1:]
data = open(src, 'rb').read()
if data[:2] == b'\x1f\x8b': data = gzip.decompress(data)
os.makedirs(out, exist_ok=True)
modes = []; p = 0
while True:
    h = data[p:p+110]; assert h[:6] in (b'070701', b'070702'), h[:6]
    f = [int(h[6+8*i:14+8*i], 16) for i in range(13)]
    mode, fsize, nsize = f[1], f[6], f[11]
    p += 110; name = data[p:p+nsize-1].decode(); p = (p + nsize + 3) & ~3
    body = data[p:p+fsize]; p = (p + fsize + 3) & ~3
    if name == 'TRAILER!!!': break
    modes.append(f'{mode:o} {name}')
    dst = os.path.join(out, name)
    t = mode & 0o170000
    if t == 0o040000: os.makedirs(dst, exist_ok=True)
    elif t == 0o120000: open(dst + '.symlink', 'w').write(body.decode())
    elif t == 0o100000:
        os.makedirs(os.path.dirname(dst) or out, exist_ok=True); open(dst, 'wb').write(body)
open(os.path.join(out, '_modes.txt'), 'w').write('\n'.join(modes))
print(len(modes), 'entries')
