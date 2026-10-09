#!/usr/bin/env bash
# WSL: build + live-install (or roll back) the Secure Folder services.jar patch (tools/patches/patch_knox_securefolder.sh).
# usage: knox_sf_live.sh install | rollback      then reboot the phone (single TWRP bounce on the debug kernel)
# install: builds ~/research/services_knox.jar from the G9600 services.jar, backs up the phone's services.jar + its
#          oat files to /sdcard/knox_sf_backup (once), installs the patched jar, removes the stale services
#          odex/vdex/art (ART recompiles it at boot). KnoxGuard is not touched.
set -e
. "$(dirname "$0")/../lib/env.sh"; P=$S8PORT; J=~/research/services_knox.jar
case "$1" in
install)
  bash $P/tools/patches/patch_knox_securefolder.sh ~/s8rom/trees/g9600_root/system/framework/services.jar $J
  phpush $J /data/local/tmp/services_knox.jar
  cat > /tmp/knox_inst.sh <<'X'
mount -o rw,remount /
mkdir -p /data/local/tmp/sysrw; mountpoint -q /data/local/tmp/sysrw || mount --bind / /data/local/tmp/sysrw
F=/data/local/tmp/sysrw/system/framework; B=/sdcard/knox_sf_backup
if [ ! -d $B ]; then mkdir -p $B/oat/arm64; cp -p $F/services.jar $B/; cp -p $F/oat/arm64/services.* $B/oat/arm64/ 2>/dev/null; fi
rm -f $F/services.jar; cp /data/local/tmp/services_knox.jar $F/services.jar
chown 0:0 $F/services.jar; chmod 644 $F/services.jar; chcon u:object_r:system_file:s0 $F/services.jar
rm -f $F/oat/arm64/services.odex $F/oat/arm64/services.vdex $F/oat/arm64/services.art
sync; ls -lZ $F/services.jar; ls $F/oat/arm64 | grep -c services; echo "knox: installed - reboot now"
X
  phsh /tmp/knox_inst.sh | grep -v pushed ;;
rollback)
  cat > /tmp/knox_rb.sh <<'X'
mount -o rw,remount /
mkdir -p /data/local/tmp/sysrw; mountpoint -q /data/local/tmp/sysrw || mount --bind / /data/local/tmp/sysrw
F=/data/local/tmp/sysrw/system/framework; B=/sdcard/knox_sf_backup
[ -f $B/services.jar ] || { echo "no backup"; exit 1; }
rm -f $F/services.jar; cp $B/services.jar $F/services.jar
for f in $B/oat/arm64/services.*; do [ -f $f ] && cp $f $F/oat/arm64/; done
chown 0:0 $F/services.jar $F/oat/arm64/services.*; chmod 644 $F/services.jar $F/oat/arm64/services.*
chcon u:object_r:system_file:s0 $F/services.jar $F/oat/arm64/services.*
sync; echo "knox: rolled back - reboot now"
X
  phsh /tmp/knox_rb.sh | grep -v pushed ;;
*) echo "usage: $0 install|rollback"; exit 1 ;;
esac
