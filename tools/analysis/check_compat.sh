#!/usr/bin/env bash
# WSL: can the G9600 Android 10 system run on the S8 Pie vendor? + G9600 debloat candidates by size.
S=~/s8rom/trees/g9600_root/system
P=$(cd "$(dirname "$0")/../.." && pwd)
echo "== sepolicy mapping files on G9600 system:"; ls $S/system/etc/selinux/mapping 2>/dev/null || ls $S/etc/selinux/mapping
echo "== VNDK libs available (vndk-28 needed by Pie vendor):"; ls -d $S/apex/*vndk* $S/lib64/vndk-* $S/lib/vndk-* 2>/dev/null
echo "== S8 vendor VNDK + sepolicy version:"
debugfs -R "cat /vendor/etc/selinux/plat_sepolicy_vers.txt" $P/work/stock_CZE1/system.raw.img 2>/dev/null
debugfs -R "cat /vendor/build.prop" $P/work/stock_CZE1/system.raw.img 2>/dev/null | grep -E 'vndk|first_api|treble'
echo "== G9600 apps by size (MiB) - top 60:"
cd $S; du -sm app/* priv-app/* preload/* 2>/dev/null | sort -rn | head -60 | awk '{printf "%s:%s  ", $2, $1} NR%5==0{print ""}'; echo
echo "== hidden image (preloads, separate partition on S9) contents:"
debugfs -R "ls -p /IUS" $P/work/donor_G9600/hidden.raw.img 2>/dev/null | awk -F/ '$6!=""{print $6}' | head -20 | tr '\n' ' '; echo
