#!/usr/bin/env bash
# WSL: pack out/twrp_push (boot.img, vendor.tar, vendor_labels.sh, apply_vendor.sh, system_add.tar) into a TWRP
# flashable zip: out/rom/s8port_update_<date>.zip (installer: installer/update-binary).
# Run after build_vendor.sh + make_vendor_push.sh (+ boot.img; make_vendor_push.sh copies installer/twrp/* there).
set -e
P=$(cd "$(dirname "$0")/../.." && pwd); O=$P/out/twrp_push; Z=~/s8rom/port/zip
command -v zip >/dev/null || { echo "$SUDO_PW" | sudo -S -p '' apt-get install -y -qq zip >/dev/null; }
rm -rf $Z; mkdir -p $Z/META-INF/com/google/android
tr -d '\r' < $P/installer/update-binary > $Z/META-INF/com/google/android/update-binary
echo '# dummy - the installer is update-binary (shell)' > $Z/META-INF/com/google/android/updater-script
for f in boot.img vendor.tar vendor_labels.sh apply_vendor.sh system_add.tar; do
  [ -s $O/$f ] || { echo "missing $O/$f"; exit 1; }
  case $f in *.sh) tr -d '\r' < $O/$f > $Z/$f ;; *) ln -s $O/$f $Z/$f ;; esac
done
OUT=$P/out/rom/s8port_update_$(date +%Y%m%d_%H%M).zip; mkdir -p $P/out/rom; rm -f $OUT
(cd $Z && zip -r -1 -q $OUT META-INF boot.img vendor.tar vendor_labels.sh apply_vendor.sh system_add.tar)
unzip -l $OUT | tail -n +4 | head -n -2
ls -la $OUT; md5sum $OUT
