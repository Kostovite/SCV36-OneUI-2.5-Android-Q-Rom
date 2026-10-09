#!/usr/bin/env bash
# WSL: dump S8 Pie /system/lib{,64} (HIDL interface libs live there on Pie) for transplant resolution.
P=$(cd "$(dirname "$0")/../.." && pwd)
I=$P/work/stock_CZE1/system.raw.img
D=~/s8rom/trees/s8_system; mkdir -p $D
for d in lib lib64; do [ -d $D/$d ] || debugfs -R "rdump /$d $D" $I 2>/dev/null; done
echo "S8 system libs: $(ls $D/lib64 | wc -l) lib64, $(ls $D/lib | wc -l) lib"
