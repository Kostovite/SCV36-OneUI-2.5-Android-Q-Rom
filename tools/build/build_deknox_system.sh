#!/usr/bin/env bash
# Run in WSL (needs sudo for loop mount): stock CZE1 system minus KnoxGuard & the Knox lock/attestation agents,
# no stock-recovery restore, /data encryption optional. Output: sparse ext4 for Odin (system.img.ext4).
# usage: SUDO_PW=... bash tools/build/build_deknox_system.sh
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
W=~/s8rom/sys; mkdir -p $W
S() { echo "$SUDO_PW" | sudo -S -p '' "$@"; }
IMG=$W/system_deknox.raw.img
cp --sparse=always $P/work/stock_CZE1/system.raw.img $IMG
MNT=$W/mnt; mkdir -p $MNT
S mount -o loop,rw -t ext4 $IMG $MNT
trap 'S umount $MNT 2>/dev/null || true' EXIT

for d in priv-app/KnoxGuard priv-app/Rlc priv-app/KLMSAgent priv-app/SKMSAgent priv-app/knoxanalyticsagent \
         app/KnoxAttestationAgent app/SecurityLogAgent app/DsmsAPK; do
  if [ -d "$MNT/$d" ]; then S rm -rf -- "$MNT/$d"; echo "removed $d"; else echo "absent  $d"; fi
done
# stock recovery would overwrite TWRP on every boot
S rm -f -- $MNT/recovery-from-boot.p && echo "removed recovery-from-boot.p"
# /data: forced FDE -> optional (rewrite in place so the file keeps its SELinux label)
F=$MNT/vendor/etc/fstab.qcom
sed 's/forceencrypt=footer/encryptable=footer/' $F > $W/fstab.new
S sh -c "cat $W/fstab.new > $F"
grep -n 'userdata' $F
ls -Z $F 2>/dev/null | awk '{print "label:", $1}'

# global (non-au) Samsung boot/shutdown animation from the G9600 Android 10 firmware. Same 1440x2960 panel, QMG v0x0f,
# which this Pie player already handles (its own crypt_*/shutdown.qmg are v0x0f). cat > keeps inode + SELinux label.
G=~/s8rom/trees/g9600_root/system/media
for f in bootsamsung.qmg bootsamsungloop.qmg shutdown.qmg; do
  S sh -c "cat $G/$f > $MNT/media/$f" && echo "boot animation: $f <- G9600 ($(stat -c %s $G/$f) bytes)"
done
# charging (.spi) assets are byte-identical between the two firmwares; the Android 10 charging look comes from the Q
# 'lpm' binary, which needs Q system libs -> it arrives with the One UI 2 system, not in this stock-Pie package.

S umount $MNT; trap - EXIT
e2fsck -fy $IMG >/dev/null 2>&1 || true
e2fsck -fn $IMG | tail -1
img2simg $IMG $W/system.img.ext4
mkdir -p $P/out/rom && cp $W/system.img.ext4 $P/out/rom/system_deknox_CZE1.img.ext4
ls -la $P/out/rom/
