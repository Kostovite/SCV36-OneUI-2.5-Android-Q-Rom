#!/usr/bin/env bash
# where does each NEEDED of the keymaster/gatekeeper stack resolve, and is it visible to the vendor namespace?
V=~/s8rom/port/vendor; S=~/s8rom/trees/g9600_root/system
LD=$S/etc/ld.config.29.txt; [ -f $LD ] || LD=$(ls $S/etc/ld.config*.txt | head -1); echo "ld.config: $LD"
LLNDK=$(grep -E '^namespace\.vndk\.link\.default\.shared_libs|^namespace\.default\.link\.system\.shared_libs' $LD | head -3)
echo "$LLNDK" | cut -c1-400
for f in bin/hw/android.hardware.keymaster@3.0-service lib64/hw/android.hardware.keymaster@3.0-impl.so lib64/libskeymaster3device.so lib64/libkeymaster3device.so lib64/hw/keystore.mdfpp.so lib64/libkeymaster_mdfpp.so lib64/libkeymaster_helper.so lib64/libkeymaster_portable.so lib64/libkeymaster_messages.so; do
  echo "== $f"
  for n in $(readelf -d $V/$f | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
    if [ -e $V/lib64/$n ]; then w=vendor; elif [ -e $S/lib64/vndk-sp-29/$n ]; then w=vndk-sp; elif [ -e $S/lib64/vndk-29/$n ]; then w=vndk;
    elif ls $S/apex/*/lib64/bionic/$n >/dev/null 2>&1 || ls $S/apex/*/lib64/$n >/dev/null 2>&1; then w=apex; elif [ -e $S/lib64/$n ]; then w="SYSTEM-ONLY"; else w=MISSING; fi
    echo "   $n -> $w"
  done
done
