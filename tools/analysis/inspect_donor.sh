#!/usr/bin/env bash
# Read-only look at the donor (SCV38, Android 10) images with debugfs. Run inside WSL.
REPO=$(cd "$(dirname "$0")/../.." && pwd)
W=$REPO/work
OUT=$W/donor_SCV38/inspect; mkdir -p "$OUT"
D() { debugfs -R "$2" "$1" 2>/dev/null; }
names() { D "$1" "ls -p $2" | awk -F/ '$6!=""{print $6}'; }
usage() {  # used size from superblock: (block count - free blocks) * block size
  debugfs -R stats "$1" 2>/dev/null | awk -F: '/^Block count/{c=$2}/^Free blocks/{f=$2}/^Block size/{b=$2}END{printf "%s: total %.0f MiB, used %.0f MiB\n", FILENAME_, c*b/1048576, (c-f)*b/1048576}' FILENAME_="$(basename "$1")"
}
for img in $W/stock_CZE1/system.raw.img $W/donor_SCV38/system.raw.img $W/donor_SCV38/vendor.raw.img $W/donor_SCV38/odm.raw.img; do usage "$img"; done

S=$W/donor_SCV38/system.raw.img
echo "== donor system root:"; names $S / | tr '\n' ' '; echo
# system-as-root images keep the real /system under /system
if D $S "stat /system/build.prop" | grep -q Inode; then P=/system; echo "(system-as-root layout)"; else P=; fi
D $S "dump -p $P/build.prop $OUT/system_build.prop"
D $W/donor_SCV38/vendor.raw.img "dump -p /build.prop $OUT/vendor_build.prop"
D $W/donor_SCV38/vendor.raw.img "dump -p /etc/fstab.qcom $OUT/vendor_fstab.qcom"
D $W/donor_SCV38/vendor.raw.img "dump -p /etc/vintf/manifest.xml $OUT/vendor_manifest.xml"
D $S "dump -p $P/etc/vintf/compatibility_matrix.device.xml $OUT/system_compat_matrix.xml"
names $S $P/priv-app > $OUT/ls_priv-app.txt
names $S $P/app > $OUT/ls_app.txt
names $S $P/etc/init > $OUT/ls_etc_init.txt
names $W/donor_SCV38/vendor.raw.img /lib64/hw > $OUT/ls_vendor_lib64_hw.txt
names $W/donor_SCV38/odm.raw.img / > $OUT/ls_odm_root.txt
wc -l $OUT/ls_*.txt
grep -E 'ro.build.(version.(release|sdk|security_patch)|display.id)|ro.product.(system.)?(model|device)|ro.treble|ro.vndk|ro.config.knox|ro.build.version.oneui|ro.system.build.version' $OUT/system_build.prop
grep -E 'ro.vndk|ro.board|ro.product.vendor.(model|device)|ro.vendor.build.version.sdk' $OUT/vendor_build.prop
