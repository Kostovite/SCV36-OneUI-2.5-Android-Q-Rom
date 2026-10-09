#!/usr/bin/env bash
# DIAGNOSTIC ONLY (user-run): one-shot fingerprint A/B test image = stock SCV36 kernel (4.4.153) with Samsung DEFEX
# enforcement (task_defex_enforce) and the root restriction (sec_restrict_uid) returning "allow" - on the plain stock
# kernel One UI 2's vendor_init is SIGKILLed at 2.7 s. Our own kernel builds with both features off
# (tools/kernel/build_kernel.sh). The image only ever goes into the RECOVERY partition for a single `adb reboot recovery`;
# the boot partition keeps our kernel, and TWRP is restored afterwards.
# Output: out/kernel/test_stockkernel_nodefex.img
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
python3 - $P/work/stock_CZE1/boot.img_unpacked/Image ~/stock_Image_nodefex <<'PY'
import sys, struct
src, out = sys.argv[1:]
b = bytearray(open(src, 'rb').read())
TEXT = 0xffffff8008080000                      # _text of the stock kernel (~/re/stock.elf)
for name, va in (('task_defex_enforce', 0xffffff80083f3f18), ('sec_restrict_uid', 0xffffff80080b8cec)):
    o = va - TEXT
    print(name, hex(o), 'old', b[o:o+8].hex())
    b[o:o+8] = struct.pack('<II', 0x52800000, 0xd65f03c0)   # mov w0,#0 ; ret
open(out, 'wb').write(b); print('written', out, len(b))
PY
gzip -9 -n -c ~/stock_Image_nodefex > ~/stock_Image_nodefex.gz
cd $P && python3 tools/build/mkboot.py out/twrp_push/boot.img out/kernel/test_stockkernel_nodefex.img \
  --kernel ~/stock_Image_nodefex.gz --dtb out/kernel/jpn_dtbs_noverity_wqhd.dtb | cut -c1-120
md5sum out/kernel/test_stockkernel_nodefex.img
