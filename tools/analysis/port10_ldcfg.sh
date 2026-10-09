#!/usr/bin/env bash
# WSL: linker config (ld.config*), vndk-sp-28 / vndk-28 presence: G9600 donor vs S8 Pie.
R=~/s8rom; P=$(cd "$(dirname "$0")/../.." && pwd)
G=$R/trees/g9600_root/system; IMG=$P/work/stock_CZE1/system.raw.img
echo "== donor /system/etc ld.config*"; ls $G/etc | grep -i 'ld.config' | sed 's/^/  /'
echo "== S8 Pie /system/etc ld.config*"; debugfs -R "ls -p /etc" $IMG 2>/dev/null | awk -F/ '$6 ~ /ld.config/ {print "  "$6}'
echo "== S8 Pie vndk-sp-28 count"; debugfs -R "ls -p /lib64/vndk-sp-28" $IMG 2>/dev/null | awk -F/ '$6 ~ /\.so$/' | wc -l
echo "== S8 Pie: is there a vndk-28 dir?"; debugfs -R "ls -p /lib64" $IMG 2>/dev/null | awk -F/ '$6 ~ /^vndk-28$/ {print "  yes"}'
echo "== S8 vendor /vendor/lib64/hw count"; debugfs -R "ls -p /vendor/lib64/hw" $IMG 2>/dev/null | awk -F/ '$6 ~ /\.so$/' | wc -l
