#!/usr/bin/env bash
# WSL: collect a release into out/release/<date>/ (NOT for git: Samsung binaries):
#   AP_OneUI2_SCV36_<date>.tar.md5   Odin fresh install = boot (release, no root) + recovery (TWRP) + system (lz4)
#   s8port_update_<date>.zip         newest out/rom/s8port_update_*.zip (TWRP update / second step of a fresh install)
#   twrp_scv36.img, boot_release_noroot.img, INSTALL.md, SHA256SUMS
# Run after: build_vendor.sh, build_system.sh, make_vendor_push.sh, make_release_boot.sh, make_flashable_zip.sh.
# usage: make_release.sh [boot.img] [twrp.img]
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
BOOT=${1:-$P/out/kernel/boot_release_noroot.img}; TWRP=${2:-$P/out/twrp/twrp_scv36_adbdefault.img}
SYS=$P/out/rom/system_oneui2_s8.img.ext4; ZIP=$(ls -t $P/out/rom/s8port_update_*.zip | head -1)
D=$(date +%Y%m%d); R=$P/out/release/$D; mkdir -p $R
for f in $BOOT $TWRP $SYS $ZIP; do [ -s $f ] || { echo "release: missing $f"; exit 1; }; done
# the zip must carry this boot image
cmp -s $BOOT <(unzip -p $ZIP boot.img) || { echo "release: $ZIP has a different boot.img than $BOOT"; exit 1; }
# Odin cannot open packages >= 4 GiB: system goes in as Samsung-style LZ4 (independent 1 MiB blocks + content size)
W=${S8ROM:-$HOME/s8rom}/release; mkdir -p $W
lz4 -1 -B6 --content-size -f $SYS $W/system.img.ext4.lz4
python3 -c 'import lz4.frame' 2>/dev/null || pip3 install --user -q lz4
python3 $P/tools/build/odin_tar.py $R/AP_OneUI2_SCV36_$D.tar.md5 \
  $BOOT=boot.img $TWRP=recovery.img $W/system.img.ext4.lz4=system.img.ext4.lz4
cp $ZIP $R/s8port_update_$D.zip
cp $TWRP $R/twrp_scv36.img; cp $BOOT $R/boot_release_noroot.img; cp $P/docs/INSTALL.md $R/
(cd $R && sha256sum AP_*.tar.md5 *.zip *.img > SHA256SUMS && cat SHA256SUMS)
rm -f $W/system.img.ext4.lz4
# GitHub release assets must be < 2 GiB: the Odin package goes up in parts (INSTALL.md: copy /b ... / cat to join;
# SHA256SUMS keeps the hash of the joined file). The whole .tar.md5 stays in $R for local use.
AP=AP_OneUI2_SCV36_$D.tar.md5
if [ $(stat -c %s $R/$AP) -ge 2000000000 ]; then
  (cd $R && rm -f $AP.part* && split -b 1900M -d -a 1 $AP $AP.part && sha256sum $AP.part* >> SHA256SUMS && ls -la $AP.part*)
fi
ls -la $R
