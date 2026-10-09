#!/system/bin/sh
# Phone (root, our kernel): prepare a ONE-SHOT boot of the stock SCV36 kernel with our One UI 2 system, to tell whether
# the fingerprint failure is our kernel or the Q userspace. The test image (stock Image + our noverity DTBs + our
# ramdisk, out/kernel/test_stockkernel_in_recovery.img) goes into the RECOVERY partition; `adb reboot recovery` boots it
# once, any later reboot (or a crash) boots the boot partition = our kernel again. Restore TWRP afterwards
# (out/twrp/twrp_scv36_adbdefault.img).
# Stock driver = "fps,common" -> /dev/fps (stock init made /dev/esfp0 a symlink); our kernel = /dev/esfp0 itself, so
# every addition below is a no-op on our kernel.
set -e
T=/data/local/tmp/test_stockkernel_in_recovery.img
[ -s $T ] || { echo "missing $T"; exit 1; }
mount -o rw,remount /
FC=/vendor/etc/selinux/vendor_file_contexts
LBL=$(grep -E '^/dev/esfp0' $FC | awk '{print $2}' | head -1); echo "esfp0 label: ${LBL:-none}"
[ -n "$LBL" ] && ! grep -q '^/dev/fps ' $FC && echo "/dev/fps                  $LBL" >> $FC
grep -q '^/dev/fps ' /vendor/ueventd.rc || echo '/dev/fps                  0660   system     system' >> /vendor/ueventd.rc
RC=$(grep -l 'chown system system /dev/esfp0' /vendor/etc/init/*.rc | head -1); echo "fp rc: $RC"
grep -q 'symlink /dev/fps /dev/esfp0' $RC || sed -i 's|^    chmod 0660 /dev/esfp0|    symlink /dev/fps /dev/esfp0\n    chmod 0660 /dev/esfp0|' $RC
grep -n 'fps' $FC /vendor/ueventd.rc $RC
sync; mount -o ro,remount / || true
# forget the cached "Fail" so the HAL probes the sensor again on the test boot
rm -f /data/vendor/biometrics/type/type_check.dat /data/vendor/biometrics/meta/calib.dat
R=/dev/block/bootdevice/by-name/recovery
dd if=$T of=$R bs=4M 2>/dev/null; sync
SZ=$(stat -c %s $T); H1=$(sha1sum $T | cut -d' ' -f1); H2=$(head -c $SZ $R | sha1sum | cut -d' ' -f1)
[ "$H1" = "$H2" ] && echo "RECOVERY_SLOT=STOCK_KERNEL_TEST OK" || echo "WRITE_MISMATCH"
