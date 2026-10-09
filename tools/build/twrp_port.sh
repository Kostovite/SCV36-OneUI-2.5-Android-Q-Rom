#!/usr/bin/env bash
# Run in WSL: port TWRP 3.4.0 dreamqlte to SCV36 = TWRP ramdisk + SCV36 kernel/JPN DTBs + fixed fstab.
# Builds two variants in out/twrp/: _stockkernel (SCV36 CZE1 recovery kernel) and _qkernel (our perf kernel + JPN DTBs).
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
W=~/s8rom/twrp; cd $W   # tw/ and stock/ unpacked by tools/analysis/twrp_inspect.sh
mkdir -p $P/out/twrp

# fstab: /modem on SCV36 is apnhlos (vfat firmware); 'modem' is the raw modem image (stock mounts it as /mdm)
sed -e 's#^/modem\t\tvfat\t/dev/block/bootdevice/by-name/modem#/modem\t\tvfat\t/dev/block/bootdevice/by-name/apnhlos#' \
    tw/rd/etc/recovery.fstab > recovery.fstab.scv36
printf '/preload\text4\t/dev/block/bootdevice/by-name/hidden\t\t\t\t\tflags=display="Preload";backup=1\n' >> recovery.fstab.scv36
diff tw/rd/etc/recovery.fstab recovery.fstab.scv36 || true

build() {  # $1 variant, $2 raw kernel Image, $3 concatenated DTBs
  rm -rf b && mkdir b && cd b
  ../magiskboot unpack -h $P/downloads/twrp/twrp-3.4.0-0-dreamqlte.img >/dev/null 2>&1
  # magiskboot re-gzips "kernel" (TWRP original format) and appends "kernel_dtb" after it = Image.gz-dtb
  cp "$2" kernel; cp "$3" kernel_dtb
  ../magiskboot cpio ramdisk.cpio "add 0640 etc/recovery.fstab ../recovery.fstab.scv36" >/dev/null
  # stock Samsung bootloader expects the board name; TWRP cmdline (selinux permissive) kept as is
  sed -i "s/^name=.*/name=SRPPL09B000RU/" header
  ../magiskboot repack $P/downloads/twrp/twrp-3.4.0-0-dreamqlte.img new.img >/dev/null 2>&1
  printf 'SEANDROIDENFORCE' >> new.img
  cp new.img $P/out/twrp/twrp-3.4.0-scv36_$1.img
  echo "$1: $(stat -c %s new.img) bytes; $(grep '^cmdline=' header | cut -c1-60)..."
  cd ..
}
# stock recovery unpacked by magiskboot: kernel = raw Image, kernel_dtb = JPN DTBs
build stockkernel $W/stock/kernel $W/stock/kernel_dtb
# our kernel: Image.gz + stock JPN DTBs (same order as stock: rev12, rev11, rev09)
gzip -dc $P/out/kernel/Image.gz > qkernel-Image
build qkernel $W/qkernel-Image $W/stock/kernel_dtb
# verify: each image must unpack to a gzip kernel + 3 JPN DTBs
for f in $P/out/twrp/*.img; do
  rm -rf v && mkdir v && (cd v && ../magiskboot unpack $f >/dev/null 2>&1)
  echo "$(basename $f): kernel $(strings v/kernel | grep -m1 -oE 'Linux version [^ ]+'), dtbs: $(grep -aoc 'DREAMQ PROJECT JPN' v/kernel_dtb)"
done
ls -la $P/out/twrp/
