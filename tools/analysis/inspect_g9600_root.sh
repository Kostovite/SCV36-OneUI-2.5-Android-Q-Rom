#!/usr/bin/env bash
# WSL: SAR root of the G9600 system image (entries at /, vendor/odm mountpoints, /system/vendor) + odm omc layout.
P=$(cd "$(dirname "$0")/../.." && pwd)
I=$P/work/donor_G9600/system.raw.img
echo "== / :"; debugfs -R "ls -l /" $I 2>/dev/null | awk '{print $2, $NF}' | tr '\n' ' '; echo
echo "== stat /vendor /odm /system/vendor:"
for p in /vendor /odm /system/vendor /system/odm; do printf '%-16s ' $p; debugfs -R "stat $p" $I 2>/dev/null | grep -oE 'Type: [a-z]+|Fast link dest: "[^"]*"' | tr '\n' ' '; echo; done
echo "== selinux xattr of /system/vendor:"; debugfs -R "ea_list /system/vendor" $I 2>/dev/null
echo "== fs block count vs S8 partition (1146880):"; debugfs -R stats $I 2>/dev/null | grep -E 'Block count|Block size|Filesystem features'
echo "== G9600 odm:"; debugfs -R "ls -p /etc/omc" $P/work/donor_G9600/odm.raw.img 2>/dev/null | awk -F/ '$6!=""&&$6!="."&&$6!=".."{print $6}' | tr '\n' ' '; echo
echo "== tools:"; for t in setfattr getfattr e2fsck resize2fs img2simg; do printf '%s: ' $t; command -v $t || echo MISSING; done
