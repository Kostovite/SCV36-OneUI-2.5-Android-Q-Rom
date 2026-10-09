#!/sbin/sh
# Runs in TWRP (DEBUG ONLY): make the port start adb at boot without the RSA prompt, so logcat works even with a
# black screen. Edits /system/etc/prop.default inside the system image; a backup is kept as prop.default.orig.
# Undo: sh debug_adb.sh --undo
set -e
M=/mnt/s8sys
mkdir -p $M
umount $M 2>/dev/null || true
mount -o rw /dev/block/bootdevice/by-name/system $M
P=$M/system/etc/prop.default
B=$M/system/build.prop   # loaded after prop.default: its persist.sys.usb.config=none would win
if [ "$1" = "--undo" ]; then
  [ -f $P.orig ] && cp -a $P.orig $P && rm $P.orig && echo "restored original prop.default"
  [ -f $B.orig ] && cp -a $B.orig $B && rm $B.orig && echo "restored original build.prop"
else
  [ -f $P.orig ] || cp -a $P $P.orig
  [ -f $B.orig ] || cp -a $B $B.orig
  sed -i -e '/^ro\.adb\.secure=/d' -e '/^persist\.sys\.usb\.config=/d' -e '/^persist\.service\.adb\.enable=/d' $P $B
  printf 'ro.adb.secure=0\npersist.sys.usb.config=mtp,conn_gadget,adb\npersist.service.adb.enable=1\n' >> $P
  grep -E 'ro.adb.secure|usb.config|adb.enable' $P
fi
# a persisted value from the last boot (/data/property) overrides both files
[ "$1" = "--undo" ] || { mount /data 2>/dev/null || true; rm -f /data/property/persistent_properties /data/property/persist.sys.usb.config && echo "cleared saved persist.* properties"; }
ls -lZ $P $B
sync
umount $M
echo DEBUG_ADB_OK
