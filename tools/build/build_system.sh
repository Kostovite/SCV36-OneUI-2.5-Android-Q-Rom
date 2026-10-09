#!/usr/bin/env bash
# WSL (needs sudo: SUDO_PW env): build the One UI 2 port system image for the SCV36 from the G9600 Android 10 image.
#   G9600 system (labels preserved) - debloat + T835/S8 vendor in /system/vendor + /vendor & /odm links
#   + G9600 odm (multi-CSC, IMS sipdb) with Vietnamese XXV as default CSC, resized to the S8 system partition.
# Output: out/rom/system_oneui2_s8.img (raw ext4) and .img.ext4 (sparse)
set -e
P=$(cd "$(dirname "$0")/../.." && pwd); C=$P/config
W=~/s8rom/port; V=$W/vendor; M=$W/mnt; IMG=$W/system.img
S() { echo "$SUDO_PW" | sudo -S -p '' "$@"; }
command -v setfattr >/dev/null || S env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq attr >/dev/null
mountpoint -q $M && S umount $M
mkdir -p $M $P/out/rom

cp $P/work/donor_G9600/system.raw.img $IMG
e2fsck -fy $IMG >/dev/null
resize2fs $IMG 1146880 >/dev/null          # = S8 system partition (PIT: 1146880 x 4 KiB)
S mount -o loop,rw $IMG $M
trap 'S umount $M 2>/dev/null || true' EXIT

# 1) debloat
n=0; grep -vE '^\s*(#|$)' $C/debloat_g9600.txt | while read -r a; do S rm -rf "$M/system/$a"; done
echo "debloated: $(grep -cvE '^\s*(#|$)' $C/debloat_g9600.txt) apps"

# 2) vendor into /system/vendor, root /vendor -> /system/vendor (S8 has no vendor partition)
S rm -f $M/system/vendor
S mkdir -p $M/system/vendor
S rsync -a $V/ $M/system/vendor/
S chown -R 0:2000 $M/system/vendor/bin; S chmod -R 0755 $M/system/vendor/bin
S rm -rf $M/vendor && S ln -s /system/vendor $M/vendor

# 3) odm: G9600 odm content in /system/vendor/odm, root /odm -> /vendor/odm; XXV (Vietnam) default CSC
S mkdir -p $W/odm_src && [ -d $W/odm_src/etc ] || S debugfs -R "rdump / $W/odm_src" $P/work/donor_G9600/odm.raw.img >/dev/null 2>&1
S rsync -a $W/odm_src/ $M/system/vendor/odm/ --exclude lost+found
OMC=$M/system/vendor/odm/etc/omc
S cp -a $P/work/donor_G960F/odm_tree/etc/omc/XXV $OMC/
# copied from the Windows mount: uid 1000 / mode 0777 -> root 0755/0644 like the rest of the odm
S chown -R 0:0 $OMC/XXV; S find $OMC/XXV -type d -exec chmod 0755 {} +; S find $OMC/XXV -type f -exec chmod 0644 {} +
# (never pipe into S: sudo -S reads the password from stdin) - write via temp files
echo XXV > $W/sales_code.dat; S cp $W/sales_code.dat $OMC/sales_code.dat
{ S cat $OMC/sales_code_list.dat; echo XXV; } | grep -E '^[A-Z0-9]{3}$' | sort -u > $W/sales_code_list.dat
S cp $W/sales_code_list.dat $OMC/sales_code_list.dat
S rm -rf $M/odm && S ln -s /vendor/odm $M/odm
echo "odm: omc CSCs = $(ls $OMC | grep -E '^[A-Z0-9]{3}$' | tr '\n' ' ')default=$(S cat $OMC/sales_code.dat)"

# 3b) S8 camera companion ISP + OIS firmware: the kernel msm_companion3 / msm_ois drivers open /system/etc/firmware/*
S mkdir -p $M/system/etc
S debugfs -R "rdump /etc/firmware $M/system/etc" $P/work/stock_CZE1/system.raw.img >/dev/null 2>&1
S chown -R 0:0 $M/system/etc/firmware; S chmod 0755 $M/system/etc/firmware; S chmod 0644 $M/system/etc/firmware/*
S setfattr -h -n security.selinux -v u:object_r:system_file:s0 $M/system/etc/firmware
# files: vendor_firmware_file - the drivers open them from the camera HAL process, which may not read system_file
for f in $M/system/etc/firmware/*; do S setfattr -h -n security.selinux -v u:object_r:vendor_firmware_file:s0 $f; done
echo "camera fw: $(ls $M/system/etc/firmware | wc -l) files in /system/etc/firmware"

# 4) SELinux labels for everything we added (vendor + odm), plus the root links
SE=$M/system/vendor/etc/selinux; PLATFC=$M/system/etc/selinux/plat_file_contexts
S python3 $P/tools/build/label_tree.py $M /system/vendor /vendor $PLATFC $SE/vendor_file_contexts
# odm is read through /odm: label it as a real /odm partition (as /vendor/odm the vendor "/(vendor|system/vendor)(/.*)?"
# rule wins -> vendor_file, which coredomain apps (scs, ePDG, IMS) may not read -> CSC customer.xml EACCES)
S python3 $P/tools/build/label_tree.py $M /system/vendor/odm /odm $PLATFC
S setfattr -h -n security.selinux -v u:object_r:vendor_file:s0 $M/vendor
S setfattr -h -n security.selinux -v u:object_r:vendor_file:s0 $M/odm
for f in bin/hw/sec.android.hardware.nfc@1.2-service bin/hw/android.hardware.wifi@1.0-service etc/selinux/precompiled_sepolicy lib64/libwifi-hal.so; do
  echo "label: $(S getfattr -h --absolute-names --only-values -n security.selinux $M/system/vendor/$f | tr -d '\000')  /vendor/$f"
done
# safety: the sudo password must never end up inside the image
S grep -rlF "$SUDO_PW" $M/system/vendor/odm 2>/dev/null && { echo "password leaked into image"; exit 1; } || true

df -m $M | tail -1 | awk '{print "space: used " $3 " MiB, free " $4 " MiB"}'
sync; S umount $M; trap - EXIT
e2fsck -fy $IMG >/dev/null || true
e2fsck -fn $IMG | tail -1
cp $IMG $P/out/rom/system_oneui2_s8.img
img2simg $P/out/rom/system_oneui2_s8.img $P/out/rom/system_oneui2_s8.img.ext4
ls -la $P/out/rom/system_oneui2_s8.img*
