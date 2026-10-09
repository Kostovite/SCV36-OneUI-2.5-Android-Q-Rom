#!/usr/bin/env bash
# Patch a boot.img with Magisk on the PC (WSL), same steps as the Magisk app's boot_patch.sh.
# usage: bash tools/build/magisk_patch.sh <in boot.img> <out boot.img>
# KEEPVERITY/KEEPFORCEENCRYPT=true: stock /system and encrypted /data stay valid, no wipe needed.
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
APK=$P/downloads/magisk/Magisk-v30.7.apk
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
WD=$(mktemp -d ~/s8rom/magisk_XXXX)
cd "$WD"
unzip -qj "$APK" lib/x86_64/libmagiskboot.so assets/boot_patch.sh assets/stub.apk \
  lib/arm64-v8a/libmagiskinit.so lib/arm64-v8a/libmagisk.so lib/arm64-v8a/libinit-ld.so
mv libmagiskboot.so magiskboot; mv libmagiskinit.so magiskinit; mv libmagisk.so magisk; mv libinit-ld.so init-ld
chmod 755 magiskboot
# minimal stand-ins for util_functions.sh (we run on a PC, not the phone)
ui_print() { echo "$1"; }
abort() { echo "$1"; exit 1; }
grep_prop() { sed -n "s/^$1=//p" "$2" | head -1; }
export -f ui_print abort grep_prop
cp "$IN" boot.img
SOURCEDMODE=1 BOOTMODE=false KEEPVERITY=true KEEPFORCEENCRYPT=true RECOVERYMODE=false LEGACYSAR=false \
  bash -c '. ./boot_patch.sh boot.img'
cp new-boot.img "$OUT"
./magiskboot cpio ramdisk.cpio "ls" 2>/dev/null | grep -E 'overlay.d|\.backup|^.* init$' | head -8
echo "patched -> $OUT ($(stat -c %s "$OUT") bytes)"
cd ~ && rm -rf -- "$WD"
