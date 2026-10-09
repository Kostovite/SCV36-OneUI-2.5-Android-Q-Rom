#!/sbin/sh
# Runs in TWRP: recreate /data (userdata) as a clean ext4 filesystem. ERASES ALL DATA incl. internal storage.
# Inode tables are fully initialised now (lazy_itable_init=0): the port kernel panicked in ext4lazyinit on a
# TWRP-wiped filesystem ("Something is wrong with group 0", /data is mounted errors=panic).
D=/dev/block/bootdevice/by-name/userdata
umount /sdcard 2>/dev/null; umount /data 2>/dev/null; umount /data 2>/dev/null
grep -q " /data " /proc/mounts && { echo "/data still mounted - stop and retry"; exit 1; }
if command -v mke2fs >/dev/null; then
  mke2fs -F -t ext4 -b 4096 -E lazy_itable_init=0,lazy_journal_init=0 $D || exit 1
else
  make_ext4fs $D || exit 1
fi
e2fsck -fn $D || { echo "fsck reports problems after format"; exit 1; }
mount $D /data && mkdir -p /data/media/0 && umount /data
echo FORMAT_OK
