#!/usr/bin/env bash
# Runs in WSL. Compare what the Android-10 donor system expects (VNDK, SAR/init) against what the S8 Pie vendor provides.
R=~/s8rom
P=$(cd "$(dirname "$0")/../.." && pwd)
G=$R/trees/g9600_root/system
IMG=$P/work/stock_CZE1/system.raw.img
echo "== donor (G9600) key props"
for p in ro.build.version.release ro.build.version.sdk ro.product.first_api_level ro.treble.enabled \
         ro.vndk.version ro.vndk.lite ro.system.build.version.sdk; do
  printf '  %-30s %s\n' $p "$(grep -h "^$p=" $G/build.prop 2>/dev/null | head -1 | cut -d= -f2)"
done
echo "== donor VNDK apexes / vndk dirs"
ls -d $G/apex/com.android.vndk* 2>/dev/null | xargs -rn1 basename
ls -d $G/lib64/vndk-* 2>/dev/null | xargs -rn1 basename
echo "== S8 Pie vendor props"
debugfs -R "cat /vendor/build.prop" $IMG 2>/dev/null | grep -E 'vndk|ro.vendor.build.version|ro.product.vendor' | head
echo "== S8 Pie /system/lib64 vndk dirs (non-Treble keeps VNDK in system)"
debugfs -R "ls -p /lib64" $IMG 2>/dev/null | awk -F/ '$6 ~ /vndk/ {print "  "$6}'
