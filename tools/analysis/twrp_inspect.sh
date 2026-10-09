#!/usr/bin/env bash
# Run in WSL: unpack TWRP dreamqlte and stock SCV36 recovery with magiskboot; compare kernel, DTB models, fstab.
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
W=~/s8rom/twrp; mkdir -p $W/tw $W/stock
cd $W
[ -x magiskboot ] || { unzip -qj $P/downloads/magisk/Magisk-v30.7.apk lib/x86_64/libmagiskboot.so && mv libmagiskboot.so magiskboot && chmod 755 magiskboot; }
unpack() {  # $1 image, $2 dir
  (cd $2 && ../magiskboot unpack -h "$1" >/dev/null 2>&1 && mkdir -p rd && cd rd && ../../magiskboot cpio ../ramdisk.cpio extract >/dev/null 2>&1)
  echo "== $(basename $1)"; grep -E '^(name|cmdline|os_version)=' $2/header
  strings $2/kernel 2>/dev/null | grep -m1 'Linux version' || \
    (gzip -dc $2/kernel 2>/dev/null | strings | grep -m1 'Linux version') || true
  grep -aoE 'Samsung DREAMQ[^"\x00]*' $2/kernel | sort -u | tr '\n' ';'; echo
}
unpack $P/downloads/twrp/twrp-3.4.0-0-dreamqlte.img tw
unpack $P/work/stock_CZE1/recovery.img stock
echo "== TWRP recovery.fstab / twrp.fstab:"
cat tw/rd/etc/recovery.fstab tw/rd/etc/twrp.fstab 2>/dev/null | grep -vE '^#|^$'
echo "== TWRP props:"; grep -E 'ro.product.device|ro.build.version.release|ro.crypto|twrp' tw/rd/default.prop tw/rd/prop.default 2>/dev/null | head
echo "== stock recovery fstab:"; cat stock/rd/etc/recovery.fstab 2>/dev/null | grep -vE '^#|^$' | head -20
