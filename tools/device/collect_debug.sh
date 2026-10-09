#!/usr/bin/env bash
# Collect debug info from the SCV36 over adb. Read-only: nothing on the phone is modified.
# Usage (Git Bash):  bash tools/device/collect_debug.sh            -> basic info, no root needed
#                    bash tools/device/collect_debug.sh --root     -> also last_kmsg/pstore/dmesg + EFS/modem backup (needs Magisk su)
set -u
OUT="$(dirname "$0")/../debug/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
echo "Waiting for device (enable USB debugging, accept the RSA prompt)..."
adb wait-for-device

adb shell getprop > "$OUT/getprop.txt"
{
  echo "== Key properties =="
  for p in ro.product.model ro.product.device ro.product.board ro.hardware ro.board.platform \
           ro.boot.bootloader ro.build.PDA ro.build.version.release ro.build.version.security_patch \
           ro.csc.sales_code ro.boot.warranty_bit ro.warranty_bit ro.boot.flash.locked \
           ro.boot.verifiedbootstate ro.boot.veritymode ro.boot.em.status ro.boot.ddrinfo \
           sys.oem_unlock_allowed ro.oem_unlock_supported ro.frp.pst ro.security.vaultkeeper.feature \
           ro.config.knox ro.config.tima ro.config.rkp ro.boot.selinux ro.crypto.state ro.crypto.type \
           ro.treble.enabled ro.boot.hardware.revision; do
    printf '%-40s %s\n' "$p" "$(adb shell getprop "$p" | tr -d '\r')"
  done
  echo
  echo "Binary (bit) revision = 5th char from end of ro.boot.bootloader, e.g. SCV36KDU[1]CSF1"
} | tee "$OUT/summary.txt"

adb shell cat /proc/cmdline        > "$OUT/cmdline.txt"     2>&1
adb shell cat /proc/version        > "$OUT/kernel_version.txt" 2>&1
adb shell ls -l /dev/block/bootdevice/by-name/ > "$OUT/partitions.txt" 2>&1
adb shell cat /proc/partitions     > "$OUT/proc_partitions.txt" 2>&1
adb shell mount                    > "$OUT/mounts.txt" 2>&1
adb shell pm list packages -f      > "$OUT/packages.txt" 2>&1
adb shell "pm list packages | grep -iE 'knox|security|vaultkeeper|rlc|felica|kddi|au\.|docomo'" > "$OUT/packages_knox_carrier.txt" 2>&1
adb logcat -b all -d               > "$OUT/logcat_all.txt" 2>&1
adb logcat -b crash -d             > "$OUT/logcat_crash.txt" 2>&1
adb shell dumpsys device_policy    > "$OUT/dumpsys_device_policy.txt" 2>&1
adb shell dumpsys package com.samsung.android.kgclient > "$OUT/dumpsys_kgclient.txt" 2>&1

if [ "${1:-}" = "--root" ]; then
  echo "Root mode: pulling kernel logs and backing up EFS/modem partitions (read-only dd)."
  R() { adb shell su -c "$1"; }
  R "cat /proc/last_kmsg"                    > "$OUT/last_kmsg.txt" 2>&1
  R "cat /sys/fs/pstore/* 2>/dev/null"       > "$OUT/pstore.txt" 2>&1
  R "dmesg"                                  > "$OUT/dmesg.txt" 2>&1
  R "dmesg | grep -iE 'defex|knox|rkp|tima|verity|avb|rmm|vaultkeeper|proca|five|selinux'" > "$OUT/dmesg_security.txt" 2>&1
  R "ls -la /data/log /data/system/dropbox; cat /data/log/* 2>/dev/null | tail -n 3000" > "$OUT/data_log.txt" 2>&1
  BK="$OUT/partition_backup"; mkdir -p "$BK"
  for part in efs sec_efs persist modemst1 modemst2 fsg fsc steady param keydata keyrefuge; do
    if R "test -e /dev/block/bootdevice/by-name/$part" >/dev/null 2>&1; then
      R "dd if=/dev/block/bootdevice/by-name/$part of=/sdcard/_bk_$part.img bs=4096" >/dev/null 2>&1 \
        && adb pull "/sdcard/_bk_$part.img" "$BK/$part.img" >/dev/null 2>&1 \
        && R "rm /sdcard/_bk_$part.img" >/dev/null 2>&1 \
        && echo "  backed up $part"
    fi
  done
  echo "KEEP $BK SAFE - it holds your IMEI/baseband data and cannot be regenerated."
fi
echo "Done -> $OUT"
