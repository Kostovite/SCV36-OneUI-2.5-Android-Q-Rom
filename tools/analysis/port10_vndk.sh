#!/usr/bin/env bash
# Runs in WSL. Work out the vndk-28 set the S8 Pie vendor needs on an Android-10 system:
# every DT_NEEDED of every vendor ELF that is not provided by the vendor itself and is not an LL-NDK library.
set -e
R=~/s8rom; P=$(cd "$(dirname "$0")/../.." && pwd)
G=$R/trees/g9600_root/system; IMG=$P/work/stock_CZE1/system.raw.img
W=$R/port10; mkdir -p $W; cd $W
command -v readelf >/dev/null || { echo "readelf missing (binutils)"; exit 1; }
# 1. dump S8 Pie /system (vendor lives in /system/vendor) once
if [ ! -d s8sys ]; then mkdir s8sys; debugfs -R "rdump / $W/s8sys" $IMG >/dev/null 2>&1; fi
echo "s8 system dumped: $(du -sm s8sys | cut -f1) MiB"
V=s8sys/vendor
# 2. Android 10 vndk_lite linker config from AOSP (android-10.0.0_r47)
if [ ! -s ld.config.vndk_lite.txt ]; then
  curl -s "https://android.googlesource.com/platform/system/core/+/refs/tags/android-10.0.0_r47/rootdir/etc/ld.config.vndk_lite.txt?format=TEXT" | base64 -d > ld.config.vndk_lite.txt
fi
echo "ld.config.vndk_lite.txt: $(wc -l < ld.config.vndk_lite.txt) lines, namespaces: $(grep -c '^namespace\..*\.isolated' ld.config.vndk_lite.txt)"
# 3. LL-NDK list of the donor (these stay Android-10 versions, they are ABI-stable by design)
sort -u $G/etc/llndk.libraries.29.txt > llndk.txt; echo "llndk libs: $(wc -l < llndk.txt)"
# 4. needed libs of all vendor ELFs, per ABI
for abi in lib lib64; do
  find $V -type f \( -name '*.so' -o -path '*/bin/*' \) | while read f; do
    if [ "$abi" = lib64 ]; then readelf -h "$f" 2>/dev/null | grep -q AArch64 || continue; else readelf -h "$f" 2>/dev/null | grep -q 'ARM$' || continue; fi
    readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'
  done | sort -u > needed_$abi.txt
  ls $V/$abi $V/$abi/hw $V/$abi/egl $V/$abi/soundfx 2>/dev/null | grep '\.so$' | sort -u > vendorprov_$abi.txt
  comm -23 needed_$abi.txt vendorprov_$abi.txt | comm -23 - llndk.txt > fromsys_$abi.txt
  echo "== $abi: vendor needs $(wc -l < needed_$abi.txt) libs, $(wc -l < fromsys_$abi.txt) must come from system (non-LLNDK)"
done
echo "== lib64 from system (first 60):"; head -60 fromsys_lib64.txt | tr '\n' ' '; echo
