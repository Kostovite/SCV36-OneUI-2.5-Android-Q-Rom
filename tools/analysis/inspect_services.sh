#!/usr/bin/env bash
# Run in WSL: pull services.jar (+ odex/vdex) and KnoxGuard permission files from the stock CZE1 system image.
P=$(cd "$(dirname "$0")/../.." && pwd)
IMG=$P/work/stock_CZE1/system.raw.img
W=~/s8rom/fw; mkdir -p $W; cd $W
D() { debugfs -R "$1" $IMG 2>/dev/null; }
D "dump -p /framework/services.jar $W/services.jar"
ls -la services.jar; unzip -l services.jar | tail -n +4 | head -8
echo "== oat files for services:"
D "ls -l /framework/oat/arm64" | grep -i services
D "ls -l /framework/arm64" | grep -i services
echo "== KnoxGuard / kgclient permission + init files:"
for d in /etc/permissions /etc/sysconfig /etc/init; do D "ls -p $d" | awk -F/ '$6!=""{print $6}' | grep -iE 'kg|knoxguard|kgclient|vaultkeeper' | sed "s#^#$d/#"; done
echo "== vaultkeeper / vk libs:"
for d in /lib64 /lib /vendor/lib64 /vendor/lib /vendor/bin /bin; do D "ls -p $d" | awk -F/ '$6!=""{print $6}' | grep -iE '^libvk|vaultkeeper|libkg' | sed "s#^#$d/#"; done
echo "== java:"; command -v java || echo "no java"
