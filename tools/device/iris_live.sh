#!/usr/bin/env bash
# WSL: live install / rollback of the T835 iris stack (tools/build/stage_iris_t835.sh output in ~/iris_stage) on the phone.
# usage: iris_live.sh install | rollback      (then reboot: rc + bind mount + irisd start at boot)
# install: backs up every file it replaces to /sdcard/iris_g9600_backup (once), copies the staged files with the
#          exact mode/owner/label from files.txt, logs every new path to /sdcard/s8port_iris_files.txt.
# Writes /system via the bind-of-/ trick (Magisk overlays /system/lib(64)); replacing existing files is visible at
# once, new files after the reboot. Never touches apnhlos (read-only partition) - the rc bind-mounts over it.
set -e
. "$(dirname "$0")/../lib/env.sh"; ST=~/iris_stage
case "$1" in
install)
  (cd $ST && tar --numeric-owner -cf ~/iris_stage.tar system files.txt)
  phpush ~/iris_stage.tar /data/local/tmp/iris_stage.tar
  cat > /tmp/iris_inst.sh <<'X'
S=/data/local/tmp/iris_stage; rm -rf $S; mkdir -p $S; cd $S && tar -xf ../iris_stage.tar
mount -o rw,remount /
mkdir -p /data/local/tmp/sysrw; mountpoint -q /data/local/tmp/sysrw || mount --bind / /data/local/tmp/sysrw
R=/data/local/tmp/sysrw; B=/sdcard/iris_g9600_backup; L=/sdcard/s8port_iris_files.txt
first=0; [ -d $B ] || { mkdir -p $B; first=1; }
# earlier installs bind-mounted a T835-trustlet copy over apnhlos (TZ rejects that TA) -> drop the rc + the copy
rm -f $R/system/vendor/etc/init/s8_iris.rc; rm -rf $R/system/vendor/firmware/apnhlos_iris
: > $L; n=0
while read p m u g l; do
  if [ -d "$S$p" ]; then
    [ -d "$R$p" ] || { mkdir "$R$p"; echo "NEWDIR $p" >> $L; }
    chmod $m "$R$p"; chown $u:$g "$R$p"; chcon $l "$R$p"; continue
  fi
  if [ -e "$R$p" ]; then
    [ -e "$B$p" ] || { mkdir -p "$B$(dirname $p)"; cp -p "$R$p" "$B$p"; }   # keeps the first (stock) copy
    echo "REPLACED $p" >> $L
  else
    echo "NEW $p" >> $L
  fi
  rm -f "$R$p"; cp "$S$p" "$R$p"; chmod $m "$R$p"; chown $u:$g "$R$p"; chcon $l "$R$p"; n=$((n+1))
done < $S/files.txt
# app data of the S9 (HAL_V3) SecIrisService: dex caches of the replaced apk
rm -rf /data/dalvik-cache/*/system@priv-app@SecIrisService@* /data/dalvik-cache/*/system@priv-app@IrisUserTest@* 2>/dev/null
rm -rf $R/system/priv-app/BiometricSetting/oat /data/dalvik-cache/*/system@priv-app@BiometricSetting@* 2>/dev/null
echo "iris: installed $n files; backup $B (first=$first)"; grep -c REPLACED $L; sync
ls -lZ /system/bin/irisd /system/priv-app/SecIrisService/SecIrisService.apk /system/priv-app/BiometricSetting/BiometricSetting.apk
X
  phsh /tmp/iris_inst.sh | grep -v pushed ;;
rollback)
  cat > /tmp/iris_rb.sh <<'X'
mount -o rw,remount /
mkdir -p /data/local/tmp/sysrw; mountpoint -q /data/local/tmp/sysrw || mount --bind / /data/local/tmp/sysrw
R=/data/local/tmp/sysrw; B=/sdcard/iris_g9600_backup; L=/sdcard/s8port_iris_files.txt
grep '^REPLACED ' $L | cut -d' ' -f2 | while read p; do
  rm -f "$R$p"; cp -p "$B$p" "$R$p"   # (backup on /sdcard has no SELinux label -> set the plat_file_contexts one)
  case $p in /system/bin/irisd) l=irisd_exec;; /system/lib64/*) l=system_lib_file;; *) l=system_file;; esac
  chcon u:object_r:$l:s0 "$R$p"
  if [ $p = /system/bin/irisd ]; then chown 0:2000 "$R$p"; chmod 755 "$R$p"; else chown 0:0 "$R$p"; chmod 644 "$R$p"; fi
done
grep '^NEW ' $L | cut -d' ' -f2 | while read p; do rm -f "$R$p"; done
grep '^NEWDIR ' $L | cut -d' ' -f2 | sort -r | while read p; do rmdir "$R$p" 2>/dev/null; done
rm -rf /data/dalvik-cache/*/system@priv-app@SecIrisService@* /data/dalvik-cache/*/system@priv-app@IrisUserTest@* 2>/dev/null
sync; echo "iris: rolled back (reboot to apply)"
X
  phsh /tmp/iris_rb.sh | grep -v pushed ;;
*) echo "usage: $0 install|rollback"; exit 1 ;;
esac
