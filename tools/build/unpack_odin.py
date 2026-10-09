"""Extract and lz4-decompress members of a Samsung Odin .tar.md5.
usage: python tools/build/unpack_odin.py <file.tar.md5> <out_dir> [member-substring ...]
Sparse ext4 images (*.img.ext4) are additionally converted to raw *.raw.img."""
import sys, os, tarfile, struct, lz4.frame

def unsparse(src, dst):
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        magic, major, minor, fhs, chs, blk, total_blks, total_chunks, _ = struct.unpack('<IHHHHIIII', f.read(28))
        if magic != 0xED26FF3A:
            return False
        f.seek(fhs)
        for _ in range(total_chunks):
            ctype, _, csize, tsize = struct.unpack('<HHII', f.read(12))
            f.seek(chs - 12, 1)
            n = csize * blk
            if ctype == 0xCAC1:      # raw
                left = n
                while left:
                    buf = f.read(min(left, 1 << 24)); o.write(buf); left -= len(buf)
            elif ctype == 0xCAC2:    # fill
                fill = f.read(4) * (blk // 4)
                for _ in range(csize): o.write(fill)
            elif ctype == 0xCAC3:    # don't care
                o.seek(n, 1)
            elif ctype == 0xCAC4:    # crc
                f.read(4)
        o.truncate(total_blks * blk)
    return True

tar_path, out, *want = sys.argv[1:]
os.makedirs(out, exist_ok=True)
with tarfile.open(tar_path) as t:
    for m in t.getmembers():
        if not m.isfile() or (want and not any(w in m.name for w in want)):
            continue
        name = os.path.basename(m.name)
        src = t.extractfile(m)
        if name.endswith('.lz4'):
            name = name[:-4]
            dst = os.path.join(out, name)
            with lz4.frame.open(src) as z, open(dst, 'wb') as o:
                while True:
                    b = z.read(1 << 24)
                    if not b: break
                    o.write(b)
        else:
            dst = os.path.join(out, name)
            with open(dst, 'wb') as o: o.write(src.read())
        print('extracted', dst, os.path.getsize(dst))
        if name.endswith('.img.ext4'):
            raw = dst[:-len('.img.ext4')] + '.raw.img'
            if unsparse(dst, raw):
                os.remove(dst); print('  unsparsed ->', raw, os.path.getsize(raw))
