#!/usr/bin/env bash
# Run in WSL: make a boot image that starts adb without RSA authorization from early boot, for catching bootloop logs.
# usage: bash tools/device/make_debug_boot.sh <in boot.img> <out boot.img>
# default.prop: ro.adb.secure=0 (no auth prompt), persist.sys.usb.config=mtp,adb (adbd on from the start)
set -e
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
WD=$(mktemp -d ~/s8rom/dbgboot_XXXX); cd "$WD"
cp ~/s8rom/twrp/magiskboot .
./magiskboot unpack "$IN" >/dev/null 2>&1
./magiskboot cpio ramdisk.cpio "extract default.prop default.prop" >/dev/null 2>&1
sed -i -e 's/^ro.adb.secure=.*/ro.adb.secure=0/' -e 's/^persist.sys.usb.config=.*/persist.sys.usb.config=mtp,adb/' default.prop
grep -q '^ro.adb.secure=' default.prop || echo 'ro.adb.secure=0' >> default.prop
grep -q '^persist.sys.usb.config=' default.prop || echo 'persist.sys.usb.config=mtp,adb' >> default.prop
./magiskboot cpio ramdisk.cpio "add 0644 default.prop default.prop" >/dev/null 2>&1
./magiskboot repack "$IN" new.img >/dev/null 2>&1
cp new.img "$OUT"
grep -E 'ro.adb.secure|persist.sys.usb.config|ro.debuggable' default.prop
echo "-> $OUT ($(stat -c %s "$OUT") bytes)"
cd ~ && rm -rf -- "$WD"
