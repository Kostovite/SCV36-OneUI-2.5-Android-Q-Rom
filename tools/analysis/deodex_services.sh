#!/usr/bin/env bash
# Run in WSL: deodex stock CZE1 services via the oat (services.odex + services.vdex side by side) -> smali,
# then locate the KnoxGuard service and where SystemServer starts it. Samsung Pie stores CompactDex (cdex001),
# which baksmali only reads through the oat/vdex container.
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
IMG=$P/work/stock_CZE1/system.raw.img
T=~/s8rom/tools_bin
W=~/s8rom/fw; mkdir -p $W/oat; cd $W
for f in services.odex services.vdex; do
  debugfs -R "dump -p /framework/oat/arm64/$f $W/oat/$f" $IMG 2>/dev/null
done
# boot classpath oat files are needed to resolve framework classes when deodexing
mkdir -p $W/boot
for f in $(debugfs -R "ls -p /framework/arm64" $IMG 2>/dev/null | awk -F/ '$6 ~ /^boot.*\.(oat|vdex)$/ {print $6}'); do
  debugfs -R "dump -p /framework/arm64/$f $W/boot/$f" $IMG 2>/dev/null
done
echo "dex entries in services.odex:"; java -jar $T/baksmali.jar list dex $W/oat/services.odex 2>&1 | head -5
rm -rf $W/smali && mkdir -p $W/smali
n=0
for e in $(java -jar $T/baksmali.jar list dex $W/oat/services.odex 2>/dev/null); do
  java -jar $T/baksmali.jar d -a 28 -b "" "$W/oat/services.odex/$e" -o $W/smali/classes$n 2>&1 | tail -3
  n=$((n+1))
done
echo "smali files: $(find $W/smali -name '*.smali' | wc -l)"
echo "== KnoxGuard classes:"; grep -rli 'knoxguard' $W/smali --include='*.smali' | sed "s#$W/smali/##" | head -25
echo "== SystemServer start site:"; grep -rn -i 'knoxguard' $(find $W/smali -name SystemServer.smali) | head -10
