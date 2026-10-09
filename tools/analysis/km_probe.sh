#!/usr/bin/env bash
# WSL: why does vendor.keymaster-3-0 exit 1 on the port? compare keystore/keymaster props + files S8 vs port vendor
T=~/s8rom/trees
ls -d $T/*
for f in $T/s8_vendor/vendor/build.prop $T/t835_vendor/build.prop $T/g9600_root/system/build.prop $T/s8_system/build.prop; do
  echo "== $f"; grep -E 'keystore|keymaster|gatekeeper|security.mdf|ro.hardware' $f 2>/dev/null
done
echo "== port vendor dirs"; ls -d ~/s8rom/*/ ; find ~/s8rom -maxdepth 3 -name 'build.prop' -path '*vendor*' 2>/dev/null
cat $T/s8_vendor/vendor/etc/init/android.hardware.keymaster@3.0-service.rc
strings $T/s8_vendor/vendor/lib64/hw/android.hardware.keymaster@3.0-impl.so | grep -iE 'keystore|mdfpp|ro\.|hw_get|module' | head -20
strings $T/s8_vendor/vendor/bin/hw/android.hardware.keymaster@3.0-service | grep -iE 'keymaster|ro\.|passthrough|fail' | head -20
