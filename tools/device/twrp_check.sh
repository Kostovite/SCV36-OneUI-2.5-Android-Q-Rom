#!/sbin/sh
# Runs ON the phone inside TWRP (pushed by twrp_check.ps1). Checks that TWRP can see and use storage.
B=/dev/block/bootdevice/by-name
echo "== TWRP / kernel"
getprop ro.twrp.version; uname -r
echo "== block devices present"
for p in system userdata cache efs hidden apnhlos modem boot recovery; do
  [ -e $B/$p ] && echo "  ok  $p -> $(readlink $B/$p)" || echo "  MISSING $p"
done
echo "== filesystem types (blkid)"
for p in system userdata cache efs hidden; do echo "  $p: $(blkid $B/$p 2>/dev/null | grep -oE 'TYPE="[^"]+"' || echo 'no fs / encrypted / blank')"; done

try_mount() {  # $1 mountpoint $2 partition $3 opts
  mkdir -p $1
  if grep -q " $1 " /proc/mounts || mount -t ext4 -o $3 $B/$2 $1 2>/dev/null; then
    echo "  mounted $1 ($2, $3)"; return 0
  else echo "  FAILED to mount $1 ($2)"; return 1; fi
}
echo "== mount tests"
try_mount /system_check system ro && { grep -m1 'ro.build.display.id' /system_check/build.prop /system_check/system/build.prop 2>/dev/null; umount /system_check; }
try_mount /efs efs ro && { echo "  efs entries: $(ls /efs | wc -l)"; }
try_mount /cache cache rw && echo "  cache free: $(df -h /cache | tail -1 | awk '{print $4}')"
try_mount /preload hidden ro
if try_mount /data userdata rw; then
  echo "  data free: $(df -h /data | tail -1 | awk '{print $4}')"
  mkdir -p /data/media/0
  dd if=/dev/urandom of=/data/media/0/.twrp_rw_test bs=1048576 count=32 2>/dev/null
  A=$(md5sum /data/media/0/.twrp_rw_test | cut -d' ' -f1); sync; echo 3 > /proc/sys/vm/drop_caches
  Bm=$(md5sum /data/media/0/.twrp_rw_test | cut -d' ' -f1); rm -f /data/media/0/.twrp_rw_test
  [ "$A" = "$Bm" ] && echo "  data write/read 32 MiB: OK" || echo "  data write/read: MISMATCH"
else
  echo "  -> /data not mountable: in TWRP do Wipe > Format Data > type yes, then re-run this check"
fi
echo "== kernel log: storage errors"
dmesg | grep -iE 'ufs.*(err|fail)|ext4.*error|I/O error|mmc.*error' | tail -8
echo "  ($(dmesg | grep -ciE 'ufs.*(err|fail)|I/O error') storage error lines total)"
echo "== touch input devices"
cat /proc/bus/input/devices 2>/dev/null | grep -E 'Name=' | sed 's/^/  /'
