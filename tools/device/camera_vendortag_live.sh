#!/bin/bash
# Face unlock / camera2 on HAL1: install the vendor-tag patched arm64 libcamera_client + libandroid_runtime on the
# running phone (or roll back), then reboot (libandroid_runtime is preloaded by zygote).
#   see tools/patches/patch_camera_legacy_vendortags.py; stock copies go to /sdcard/s8port_vt_backup/
#   (TWRP rollback: copy them back to /system/system/lib64/ with the same names)
# usage: camera_vendortag_live.sh install|rollback
P=$(cd "$(dirname "$0")/../.." && pwd); . $P/tools/lib/env.sh
MODE=${1:?usage: camera_vendortag_live.sh install|rollback}
W=$(mktemp -d); trap 'rm -rf $W' EXIT
BK=/sdcard/s8port_vt_backup
R=$S8ROM/trees/g9600_root/system/lib64
LIBS="libcamera_client.so libandroid_runtime.so"
if [ "$MODE" = install ]; then
  python3 $P/tools/patches/patch_camera_legacy_vendortags.py client $R/libcamera_client.so $W/libcamera_client.so || exit 1
  python3 $P/tools/patches/patch_camera_legacy_vendortags.py runtime $R/libandroid_runtime.so $W/libandroid_runtime.so || exit 1
  for l in $LIBS; do phpush $W/$l /data/local/tmp/vt_$l || exit 1; done
  SRC=/data/local/tmp/vt_
else
  SRC=$BK/
fi
cat > $W/apply.sh <<EOF
for l in $LIBS; do [ -f $SRC\$l ] || { echo "missing $SRC\$l"; exit 1; }; done
mount -o rw,remount /
mkdir -p /data/local/tmp/sysrw $BK; mountpoint -q /data/local/tmp/sysrw || mount --bind / /data/local/tmp/sysrw
for l in $LIBS; do
  T=/data/local/tmp/sysrw/system/lib64/\$l
  [ -f $BK/\$l ] || cp -p \$T $BK/\$l
  L=\$(ls -Z \$T | cut -d' ' -f1)
  cat $SRC\$l > \$T.new && chmod 644 \$T.new && chown root:root \$T.new && chcon \$L \$T.new && mv \$T.new \$T
done
sync; md5sum /system/lib64/libcamera_client.so /system/lib64/libandroid_runtime.so $BK/*
reboot
EOF
phsh $W/apply.sh
