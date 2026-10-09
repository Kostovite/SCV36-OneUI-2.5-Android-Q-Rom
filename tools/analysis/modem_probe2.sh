#!/usr/bin/env bash
# WSL (boot 8): S8 fstabs, ueventd firmware directories and firmware images on disk.
T=~/s8rom/trees
echo "== S8 fstab files"; find $T/s8_vendor $T/s8_system ~/s8rom/fw -iname 'fstab*' 2>/dev/null | head
for f in $(find $T/s8_vendor $T/s8_system ~/s8rom/fw -iname 'fstab*' 2>/dev/null | head -5); do echo "-- $f"; grep -E 'firmware|modem|apnhlos|dsp' $f; done
echo "== S8 ueventd firmware dirs"; grep -rh firmware_directories $T/s8_vendor $T/s8_system 2>/dev/null
echo "== S8 firmware images on disk"; ls -la ~/s8rom/fw 2>/dev/null | head -30
