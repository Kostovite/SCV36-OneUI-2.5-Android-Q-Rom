#!/usr/bin/env python3
"""G9600 Q arm64 framework libs: let camera2 apps use vendor keys on HAL1 (legacy shim) cameras.

All S8 cameras run HAL1 (persist.camera.HAL3.enabled=0), so a camera2 client (the S9 face service BioFaceFr_V3) gets
the in-process legacy shim (CameraDeviceUserShim). Its CameraMetadataNative buffers never get a vendor id
(CAMERA_METADATA_INVALID_VENDOR_ID), and on a HIDL device the app process only has the per-vendor-id
VendorTagDescriptorCache (cameraserver's global VendorTagDescriptor is empty). So:
  - CaptureRequest.Builder.set(samsung.android.control.shootingMode) -> nativeGetTagFromKeyLocal -> cache lookup with
    the invalid id -> "Could not find tag for key" (face enroll error 10003), even though the HAL declares the tag;
  - writing the value -> get_local_camera_metadata_tag_type(invalid id) -> global vendor_tag_ops (unset) -> no type.
Patches (only 64-bit app processes; cameraserver is 32-bit and keeps the stock libs):
  lib64/libcamera_client.so (md5 b14dccbe7cc79cdf39ccf627e3353d1e)
    VendorTagDescriptorCache::getVendorTagDescriptor(id, desc) 0x54cd8: walk the node list for id; if it is not there
    and id == INVALID, return the first provider's descriptor (there is one provider) instead of NAME_NOT_FOUND.
  lib64/libandroid_runtime.so (md5 845c8a1be1a9c1b6442598f7d1eebfa6)
    CameraMetadata_setupGlobalVendorTagDescriptor, cache branch: after setAsGlobalVendorTagCache(cache) == OK also
    VendorTagDescriptor::setAsGlobalVendorTagDescriptor(first cache entry) -> invalid-id tag type/name lookups work.
    Room: the "getCameraVendorTagCache failed" branch drops its log line (0x1c3e98..), code cave at 0x1c3eb0.
Real vendor ids keep resolving through the cache as before. Encodings assembled with aarch64-linux-gnu-as.
usage: patch_camera_legacy_vendortags.py client|runtime <in> <out>
"""
import hashlib, struct, sys

LIBS = {
    'client': ('b14dccbe7cc79cdf39ccf627e3353d1e', [
        # ldr x9,[x0,#24]; cbz x9,54d94; mov x19,x2; mov x10,x9; 1: ldr x11,[x9,#16]; cmp x11,x1; b.eq 54da8;
        # ldr x9,[x9]; cbnz x9,1b; cmn x1,#1; b.ne 54d94; mov x9,x10; b 54da8
        (0x54cd8, 'f940080a b40005ca d100054b aa0203f3 ea0a016c 540000e0 eb01015f aa0103e8 540000a8 9aca0828 '
                  '9b0a8508 14000002 8a010168',
                  'f9400c09 b40005c9 aa0203f3 aa0903ea f940092b eb01017f 540005c0 f9400129 b5ffff89 b100043f '
                  '540004a1 aa0a03e9 14000028'),
    ]),
    'runtime': ('845c8a1be1a9c1b6442598f7d1eebfa6', [
        # error branch (after clearGlobalVendorTagCache): ldp w8,w9,[sp,#8]; mov w20,wzr; mov w22,wzr; cmn w8,#8;
        # csel w19,w9,wzr,eq; b 1c3ef8
        # cave 1c3eb0: mov w20,w0; mov w22,#1; cbnz w20,1c3ef8; ldr x8,[sp,#24]; ldr x8,[x8,#24]; cbz x8,1c3ef8;
        #              add x0,x8,#24; bl setAsGlobalVendorTagDescriptor@plt; b 1c3ef8; nop x5
        (0x1c3e98, '910003e8 910023e0 9401f8a4 f94003e4 d0fff661 d0fff682 d0fff663 9118d421 910dc842 9119b463 '
                   '321f07e0 9401d13b 910003e0 9401d711 294127e8 2a1f03f4 2a1f03f6 3100211f 1a9f0133 14000005',
                   '294127e8 2a1f03f4 2a1f03f6 3100211f 1a9f0133 14000013 2a0003f4 52800036 35000214 f9400fe8 '
                   'f9400d08 b40001a8 91006100 9401f8a1 1400000a d503201f d503201f d503201f d503201f d503201f'),
        # after bl setAsGlobalVendorTagCache: mov w20,w0; mov w22,#1 -> b 1c3eb0; nop
        (0x1c3ef0, '2a0003f4 320003f6', '17fffff0 d503201f'),
    ]),
}


def words(s):
    return b''.join(struct.pack('<I', int(w, 16)) for w in s.split())


which, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
md5, patches = LIBS[which]
data = bytearray(open(src, 'rb').read())
have = hashlib.md5(data).hexdigest()
if have != md5:
    sys.exit(f'{src}: md5 {have}, expected {md5}')
for off, old, new in patches:
    old, new = words(old), words(new)
    assert len(old) == len(new)
    if data[off:off + len(old)] != old:
        sys.exit(f'{src}: unexpected bytes at {off:#x}')
    data[off:off + len(new)] = new
open(dst, 'wb').write(data)
print(f'{dst}: {which} patched, md5 {hashlib.md5(data).hexdigest()}')
