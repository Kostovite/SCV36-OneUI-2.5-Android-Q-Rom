#!/usr/bin/env bash
# WSL: SELinux policy file layout of S8 Pie (monolithic) vs the G9600 donor (split policy, mapping versions).
P=$(cd "$(dirname "$0")/../.." && pwd)
R=~/s8rom; W=$R/port10; G=$R/trees/g9600_root
echo "== S8 Pie /system/vendor/etc/selinux:"; ls $W/s8sys/vendor/etc/selinux 2>/dev/null | sed 's/^/  /' || echo "  (none)"
echo "== S8 Pie /system/etc/selinux:"; ls $W/s8sys/etc/selinux 2>/dev/null | sed 's/^/  /' || echo "  (none)"
echo "== donor /system/etc/selinux:"; ls $G/system/etc/selinux | sed 's/^/  /'
echo "== donor mapping versions:"; ls $G/system/etc/selinux/mapping 2>/dev/null | sed 's/^/  /'
echo "== S8 Pie ramdisk sepolicy files:"; ls $P/work/stock_CZE1/boot.img_unpacked/ramdisk | grep -iE 'sepolicy|contexts|selinux' | sed 's/^/  /'
