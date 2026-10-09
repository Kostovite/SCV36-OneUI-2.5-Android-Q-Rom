#!/usr/bin/env bash
# Run in WSL: remove dm-verity (verify/avb) flags from the early-mount fstab inside the stock SCV36 JPN DTBs.
# Input: the 3 stock DTBs; output: out/kernel/jpn_dtbs_noverity.dtb (concatenated, ready to append to Image.gz).
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
W=$(mktemp -d ~/s8rom/dtb_XXXX); cd "$W"
cp ~/s8rom/twrp/magiskboot .
cat $P/work/kernel_gap/stock_dtb0.dtb $P/work/kernel_gap/stock_dtb1.dtb $P/work/kernel_gap/stock_dtb2.dtb > dtbs
echo "== before:"; ./magiskboot dtb dtbs print -f 2>&1 | grep -A3 -iE 'fstab|system' | head -14
./magiskboot dtb dtbs patch && echo "patched"
echo "== after:";  ./magiskboot dtb dtbs print -f 2>&1 | grep -A3 -iE 'fstab|system' | head -14
mkdir -p $P/out/kernel && cp dtbs $P/out/kernel/jpn_dtbs_noverity.dtb
grep -ac 'verify' dtbs | sed 's/^/remaining "verify" strings: /'
cd ~ && rm -rf -- "$W"
