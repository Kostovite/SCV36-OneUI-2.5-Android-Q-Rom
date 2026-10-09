#!/usr/bin/env python3
"""Binary patch for the T835 (Q) msm8998 libgrallocutils.so (lib + lib64): NV21 row stride like the S8 Pie gralloc.

Camera previews were striped in every app while captured photos were fine (2026-10-07). The S8 Pie QCamera2 HAL1 fills
its gralloc preview buffers (HAL_PIXEL_FORMAT_YCrCb_420_SP, 1440x1080) with its own padding: stride 1440, chroma at
1440*1080. gralloc1::GetAlignedWidthAndHeight (reverse engineered from both libs):
  S8 Pie : YCrCb_420_SP -> aligned_w = ALIGN(w, 16)                             (= 1440, matches the HAL)
  T835 Q : YCrCb_420_SP -> w in {176, 352, 720} ? ALIGN(w, 16) : ALIGN(w, AdrenoMemInfo::GetGpuPixelAlignment())
           (Adreno 540 linear alignment -> 1472) -> the display reads every row 32 px further than the HAL wrote.
Snapshots use HAL-allocated ION buffers, not gralloc, hence fine. Patch: send NV21 down the ALIGN(w, 16) path again.
  lib64: format jump table byte for 0x11 (table @0x16d7, targets 0x3ca0 + 4*b): 0x50 (GPU-align path @0x3de0) -> 0x00
         (0x3ca0 = add w8,w22,#0xf; and w22,w8,#~0xf).
  lib  : Thumb @0x38b8 "blx AdrenoMemInfo::GetInstance" (after cmp r4,#0x11; bne) -> "b.n 0x38fc" (ALIGN 16) + nop.
usage: patch_gralloc_nv21.py <vendor dir>"""
import hashlib, sys

V = sys.argv[1]
PATCHES = {
    'lib64/libgrallocutils.so': [(0x16d8, bytes([0x50]), bytes([0x00]))],
    'lib/libgrallocutils.so': [(0x38b8, None, bytes.fromhex('20e0') + bytes.fromhex('00bf'))],   # b.n 0x38fc ; nop
}
# context checked before patching (file offsets == vaddrs for these .text/.rodata ranges, verified below)
CHECK = {
    'lib64/libgrallocutils.so': [(0x3ca0, bytes.fromhex('c83e0011166d1c12'))],  # add/and #0xf
    'lib/libgrallocutils.so': [(0x38b4, bytes.fromhex('112c')), (0x38fc, bytes.fromhex('07f10f00'))],     # cmp r4,#0x11 ; add.w r0,r7,#0xf
}


def vaddr_to_off(data, va):
    import struct
    e_phoff = struct.unpack_from('<Q' if data[4] == 2 else '<I', data, 0x20 if data[4] == 2 else 0x1c)[0]
    if data[4] == 2:
        phentsize, phnum = struct.unpack_from('<HH', data, 0x36)
        for i in range(phnum):
            p_type, _, p_off, p_va, _, p_fsz = struct.unpack_from('<IIQQQQ', data, e_phoff + i * phentsize)
            if p_type == 1 and p_va <= va < p_va + p_fsz:
                return p_off + va - p_va
    else:
        phentsize, phnum = struct.unpack_from('<HH', data, 0x2a)
        for i in range(phnum):
            p_type, p_off, p_va, _, p_fsz = struct.unpack_from('<IIIII', data, e_phoff + i * phentsize)
            if p_type == 1 and p_va <= va < p_va + p_fsz:
                return p_off + va - p_va
    raise SystemExit('vaddr %#x not mapped' % va)


for rel, patches in PATCHES.items():
    path = '%s/%s' % (V, rel)
    data = bytearray(open(path, 'rb').read())
    done = all(data[vaddr_to_off(data, va):vaddr_to_off(data, va) + len(new)] == new for va, _, new in patches)
    if done:
        print('already patched', rel); continue
    for va, want in CHECK[rel]:
        o = vaddr_to_off(data, va)
        assert data[o:o + len(want)] == want, '%s: unexpected bytes @%#x: %s' % (rel, va, data[o:o + len(want)].hex())
    for va, old, new in patches:
        o = vaddr_to_off(data, va)
        if old is not None:
            assert data[o:o + len(old)] == old, '%s: unexpected bytes @%#x' % (rel, va)
        data[o:o + len(new)] = new
    open(path, 'wb').write(data)
    print('patched', rel, hashlib.md5(data).hexdigest()[:12])
