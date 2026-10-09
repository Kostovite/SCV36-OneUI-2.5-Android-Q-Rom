#!/usr/bin/env bash
# Dump S8 stock vendor and the donor S9 system tree into WSL ext4 (~/s8rom/trees) for size/debloat analysis.
P=$(cd "$(dirname "$0")/../.." && pwd)
W=$P/work
T=~/s8rom/trees; mkdir -p $T/s8_vendor $T/s9_root
df -h ~ | tail -1
[ -e $T/s8_vendor/vendor ] || debugfs -R "rdump /vendor $T/s8_vendor" $W/stock_CZE1/system.raw.img 2>/dev/null
[ -e $T/s9_root/system ] || debugfs -R "rdump /system $T/s9_root" $W/donor_SCV38/system.raw.img 2>/dev/null
echo "S8 /system/vendor: $(du -sm $T/s8_vendor/vendor | cut -f1) MiB"
echo "S9 /system:        $(du -sm $T/s9_root/system | cut -f1) MiB"
echo "== S9 biggest dirs"; du -sm $T/s9_root/system/* 2>/dev/null | sort -rn | head -12
echo "== S9 biggest apps (app + priv-app + preload)"
du -sm $T/s9_root/system/{app,priv-app,preload}/* 2>/dev/null | sort -rn | head -60 | awk '{n=split($2,a,"/"); printf "%5d %s/%s\n",$1,a[n-1],a[n]}'
