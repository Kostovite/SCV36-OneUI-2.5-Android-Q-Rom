#!/usr/bin/env bash
# WSL: VNDK-28 pieces in S8 Pie system vs what the G9600 Q system has.
P=$(cd "$(dirname "$0")/../.." && pwd)
I=$P/work/stock_CZE1/system.raw.img
S=~/s8rom/trees/g9600_root/system
L() { debugfs -R "ls -p $1" $I 2>/dev/null | awk -F/ '$6!=""&&$6!="."&&$6!=".."{print $6}'; }
echo "== S8 Pie /lib64 vndk dirs:"; L /lib64 | grep -i vndk
echo "== S8 Pie /etc ld.config:"; L /etc | grep -i 'ld.config\|vndk'
for d in vndk-28 vndk-sp-28 vndk vndk-sp; do n=$(L /lib64/$d | wc -l); [ $n -gt 0 ] && echo "S8 /lib64/$d: $n files ($(debugfs -R "ls -l /lib64/$d" $I 2>/dev/null | awk '{s+=$6} END{printf "%.0f MiB", s/1048576}'))"; done
echo "== S8 vendor props:"; debugfs -R "cat /vendor/default.prop" $I 2>/dev/null | grep -iE 'vndk|treble'
echo "== G9600 /etc ld.config + vndk txt:"; ls $S/etc | grep -iE 'ld.config|vndk'
echo "== G9600 linkerconfig for 28?"; grep -l 'vndk-28\|VNDK_VER' $S/etc/ld.config* 2>/dev/null
