#!/usr/bin/env bash
# WSL: compile the full split policy (as init does on boot) to verify the merged vendor policy before flashing.
T=~/s8rom/trees; P=$(cd "$(dirname "$0")/../.." && pwd)
SYS=$T/g9600_root/system/etc/selinux; V=$T/t835_vendor/etc/selinux
VEND=$P/config/sepolicy/vendor_sepolicy.merged.cil
cat $V/vendor_sepolicy.cil $P/config/sepolicy/s8_phone_hals.cil > $VEND
PROD=""; [ -f $T/g9600_root/system/product/etc/selinux/product_sepolicy.cil ] && PROD=$T/g9600_root/system/product/etc/selinux/product_sepolicy.cil
set -x
secilc -m -M true -G -N -c 30 -o /tmp/precompiled_sepolicy -f /dev/null \
  $SYS/plat_sepolicy.cil $SYS/mapping/29.0.cil $V/plat_pub_versioned.cil $VEND $PROD
set +x
ls -la /tmp/precompiled_sepolicy && cp /tmp/precompiled_sepolicy $P/config/sepolicy/precompiled_sepolicy.test
