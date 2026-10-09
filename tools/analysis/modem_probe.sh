#!/usr/bin/env bash
# WSL (boot 8): modem firmware paths, fstab mounts and per_mgr / pd_mapper rc entries, port vs S8 Pie.
V=~/s8rom/port/vendor; TV=~/s8rom/trees/t835_vendor; S8=~/s8rom/trees/s8_vendor/vendor; G=~/s8rom/trees/g9600_root
echo "== firmware_directories"; grep -h firmware_directories $G/ueventd.rc $G/system/etc/ueventd.rc $V/ueventd.rc 2>/dev/null
echo "== modem.* blobs present in port vendor / g9600 system"; find $V $G/system -iname 'modem.*' -o -iname 'mba.mbn' 2>/dev/null | head
echo "== firmware_mnt mount in fstabs"; grep -h -E 'firmware|modem|apnhlos|dsp' $V/etc/fstab* $S8/etc/fstab* 2>/dev/null
echo "== per_mgr/pd_mapper rc: port vs S8 pie"
for f in $V/etc/init/hw/init.target.rc $S8/etc/init/hw/init.target.rc; do echo "-- $f"; grep -A6 -E 'service vendor\.(per_mgr|pd_mapper|per_proxy)' $f; done
