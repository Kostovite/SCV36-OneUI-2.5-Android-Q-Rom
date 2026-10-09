"""Wrap images into an Odin-flashable .tar.md5 (ustar + trailing md5 line, like Samsung's own packages).
usage: python tools/build/odin_tar.py <out AP_xxx.tar.md5> <file>=<name in tar> [...]
e.g.   python tools/build/odin_tar.py out/odin/AP_root.tar.md5 out/test/boot_stock_magisk.img=boot.img
A name ending in .lz4 (e.g. system.img.ext4.lz4) is compressed on the fly in Samsung's LZ4 frame format
(independent 1 MiB blocks, content size + checksum). Use it for big images: Odin fails with
"Can't open the specified file (Line: 2006)" on packages larger than 4 GiB."""
import hashlib, os, re, sys, tarfile
import lz4.frame

out, *items = sys.argv[1:]
# Odin fails with "Can't open the specified file (Line: 2006)" on names with characters like '+'
assert re.fullmatch(r'[A-Za-z0-9_.-]+', os.path.basename(out)), f'use only A-Z a-z 0-9 _ . - in the Odin file name: {out}'
os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
tmp = out[:-4] if out.endswith('.md5') else out


def lz4_samsung(src, dst):
    size = os.path.getsize(src)
    # python-lz4 on Windows truncates the 64-bit content size -> "ERROR_frameSize_wrong" for >= 4 GiB inputs
    assert size < 4 << 30, (f'{src} is >= 4 GiB: compress it in WSL first '
                            f'(lz4 -1 -B6 --content-size {os.path.basename(src)}) and pass the .lz4 file')
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        c = lz4.frame.LZ4FrameCompressor(block_size=lz4.frame.BLOCKSIZE_MAX1MB, block_linked=False,
                                         content_checksum=True, compression_level=0)
        o.write(c.begin(source_size=size))
        for chunk in iter(lambda: f.read(1 << 24), b''):
            o.write(c.compress(chunk))
        o.write(c.flush())


with tarfile.open(tmp, 'w', format=tarfile.USTAR_FORMAT) as t:
    for it in items:
        src, name = it.split('=', 1)
        packed = src
        if name.endswith('.lz4') and not src.endswith('.lz4'):
            packed = tmp + '.' + name + '.part'
            lz4_samsung(src, packed)
            print(f'  lz4 {name}: {os.path.getsize(src):,} -> {os.path.getsize(packed):,} bytes')
        ti = t.gettarinfo(packed, arcname=name)
        ti.uid = ti.gid = 0; ti.uname = ti.gname = ''; ti.mode = 0o644
        with open(packed, 'rb') as f:
            t.addfile(ti, f)
        if packed != src:
            os.remove(packed)
md5 = hashlib.md5()
with open(tmp, 'rb') as f:
    for chunk in iter(lambda: f.read(1 << 24), b''):
        md5.update(chunk)
if tmp != out:
    with open(tmp, 'ab') as f:
        f.write(f'{md5.hexdigest()}  {os.path.basename(tmp)}\n'.encode())
    os.replace(tmp, out)
size = os.path.getsize(out)
print(out, f'{size:,}', 'bytes, md5', md5.hexdigest())
if size >= 4 << 30:
    print('WARNING: package >= 4 GiB - Odin will fail with "Can\'t open the specified file (Line: 2006)"; use .lz4 names')
