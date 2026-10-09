#!/usr/bin/env bash
# Run in WSL: boot/charging animation assets in stock S8 (CZE1) vs G9600 (Android 10) system/media.
P=$(cd "$(dirname "$0")/../.." && pwd)
echo "== S8 stock /media:"
debugfs -R "ls -l /media" $P/work/stock_CZE1/system.raw.img 2>/dev/null | awk '$NF ~ /\.(qmg|spi|txt)$/ {print $6, $NF}'
echo "== G9600 /system/media:"
ls -l ~/s8rom/trees/g9600_root/system/media | awk '$NF ~ /\.(qmg|spi|txt)$/ {print $5, $NF}'
echo "== lpm (power-off charging) binaries:"
debugfs -R "ls -l /bin" $P/work/stock_CZE1/system.raw.img 2>/dev/null | awk '$NF ~ /lpm/ {print "S8:", $6, $NF}'
ls -l ~/s8rom/trees/g9600_root/system/bin | awk '$NF ~ /lpm/ {print "G9600:", $5, $NF}'
echo "== qmg headers (format/version):"
for f in ~/s8rom/trees/g9600_root/system/media/bootsamsung.qmg; do echo "G9600 $(basename $f): $(head -c 16 $f | xxd -p)"; done
debugfs -R "cat /media/bootsamsung.qmg" $P/work/stock_CZE1/system.raw.img 2>/dev/null | head -c 16 | xxd -p | sed 's/^/S8 bootsamsung.qmg: /'
debugfs -R "cat /media/charging_New_Fast.spi" $P/work/stock_CZE1/system.raw.img 2>/dev/null | head -c 16 | xxd -p | sed 's/^/S8 charging_New_Fast.spi: /'
head -c 16 ~/s8rom/trees/g9600_root/system/media/charging_New_Fast.spi 2>/dev/null | xxd -p | sed 's/^/G9600 charging_New_Fast.spi: /'
echo "== S8 stock qmg versions (byte 2 = QMG format version):"
for f in bootsamsung.qmg bootsamsungloop.qmg crypt_bootsamsung.qmg crypt_bootsamsungloop.qmg shutdown.qmg; do
  printf '  %-28s ' $f; debugfs -R "cat /media/$f" $P/work/stock_CZE1/system.raw.img 2>/dev/null | head -c 8 | xxd -p
done
echo "== G9600 qmg versions:"
for f in bootsamsung.qmg bootsamsungloop.qmg crypt_bootsamsung.qmg shutdown.qmg; do
  printf '  %-28s ' $f; head -c 8 ~/s8rom/trees/g9600_root/system/media/$f | xxd -p
done
