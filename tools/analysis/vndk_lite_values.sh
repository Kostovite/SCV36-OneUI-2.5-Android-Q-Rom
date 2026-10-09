#!/usr/bin/env bash
# WSL: collect the values needed to fill AOSP Q's ld.config.vndk_lite.txt template.
P=$(cd "$(dirname "$0")/../.." && pwd)
S=~/s8rom/trees/g9600_root/system
I=$P/work/stock_CZE1/system.raw.img
O=$P/config/vndk_lite
echo "== shared_libs lines in G9600 ld.config.29.txt:"
grep -nE 'shared_libs' $S/etc/ld.config.29.txt | cut -c1-140 | head -20
debugfs -R "cat /etc/vndksp.libraries.28.txt" $I > $O/vndksp.libraries.28.txt 2>/dev/null
debugfs -R "cat /etc/llndk.libraries.28.txt" $I > $O/s8_llndk.libraries.28.txt 2>/dev/null
cp $S/etc/llndk.libraries.29.txt $O/ 2>/dev/null
echo "== files:"; wc -l $O/*.txt
ls $S/etc | grep -iE 'libraries'
