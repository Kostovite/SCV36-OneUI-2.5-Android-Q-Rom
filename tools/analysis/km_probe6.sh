#!/usr/bin/env bash
# WSL (boot 7): soft-keymaster libs and pd-mapper / per_mgr / pm-service in S8 Pie vs the port vendor.
S8=~/s8rom/trees/s8_vendor/vendor; S8S=~/s8rom/trees/s8_system; V=~/s8rom/port/vendor; G=~/s8rom/trees/g9600_root/system
echo "== soft keymaster libs: S8 pie system / vndk-28? / q vndk-29"
ls -la $S8S/lib64 | grep -E 'softkeymaster|keymaster'; ls $G/lib64/vndk-29 | grep -E 'keymaster'
echo "== pd_mapper / per_mgr / pm-service"
for t in $S8 $V; do echo "-- $t"; ls $t/bin | grep -iE 'pd.mapper|pm-service|pm-proxy|per_mgr|per.proxy'; grep -rlE 'pd_mapper|per_mgr|pm-service' $t/etc/init | head; done
grep -rh -A4 -E 'service vendor\.(pd_mapper|per_mgr)' $V/etc/init | head -20
echo "== kernel qrtr"; grep -E 'QRTR|IPC_ROUTER|MSM_PIL|SERVICE_LOCATOR' ~/s8rom/kernel/*/out/.config 2>/dev/null | head; ls ~/s8rom/kernel
