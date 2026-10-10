#!/bin/bash
# Face unlock: install the S8 Pie face engine on the running phone (or roll back), then restart faced.
#   install : /system/lib64/libsecfr_engine.so = stock S8 Pie libsecfr_engine.so with NEEDED libQSEEComAPI.so ->
#             libQSEEComAPI_system.so (patchelf). Why: the S9 (G9600) engine talks to the S8 sec_fr TA with the S9
#             shared-buffer layout (total 0x110000, frame 0x90000, header 0x6000..) while the S8 TA expects the S8 one
#             (0xf0000 / 0x70000 / 0x800..) -> enrollment can never work. libFaceService/face.default are identical.
#   rollback: puts the S9 engine back from /sdcard/libsecfr_engine_g9600_backup.so
# usage: face_s8engine_live.sh install|rollback
P=$(cd "$(dirname "$0")/../.." && pwd); . $P/tools/lib/env.sh
MODE=${1:?usage: face_s8engine_live.sh install|rollback}
W=$(mktemp -d); trap 'rm -rf $W' EXIT
BK=/sdcard/libsecfr_engine_g9600_backup.so
if [ "$MODE" = install ]; then
  cp $S8ROM/trees/s8_system/lib64/libsecfr_engine.so $W/libsecfr_engine.so
  patchelf --replace-needed libQSEEComAPI.so libQSEEComAPI_system.so $W/libsecfr_engine.so
  readelf -d $W/libsecfr_engine.so | grep -q 'libQSEEComAPI_system.so' || { echo "patchelf failed"; exit 1; }
  phpush $W/libsecfr_engine.so /data/local/tmp/libsecfr_engine.so || exit 1
  SRC=/data/local/tmp/libsecfr_engine.so
else
  SRC=$BK
fi
cat > $W/apply.sh <<EOF
[ -f $SRC ] || { echo "missing $SRC"; exit 1; }
mount -o rw,remount /
mkdir -p /data/local/tmp/sysrw; mountpoint -q /data/local/tmp/sysrw || mount --bind / /data/local/tmp/sysrw
T=/data/local/tmp/sysrw/system/lib64/libsecfr_engine.so
[ -f $BK ] || cp -p \$T $BK
L=\$(ls -Z \$T | cut -d' ' -f1)
cat $SRC > \$T; chmod 644 \$T; chown root:root \$T; chcon \$L \$T; sync
md5sum /system/lib64/libsecfr_engine.so
logcat -c; stop faced; start faced; sleep 3; echo "faced pid: \$(pidof faced)"
logcat -d | grep -i -E "CANNOT LINK|dlopen failed|secfr|faced" | tail -5
EOF
phsh $W/apply.sh
