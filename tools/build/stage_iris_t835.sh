#!/usr/bin/env bash
# WSL: stage the Galaxy Tab S4 (SM-T835, MSM8998, Android 10) iris stack for the SCV36 One UI 2 port.
# usage: stage_iris_t835.sh <T835 system.raw.img> <out dir>
#   <out>/system/...      files (vendor ones under system/vendor, like the port image)
#   <out>/files.txt       "<path> <mode> <uid> <gid> <selinux label>" for every staged file
#
# Why T835 and not the G9600 (S9) iris the port carries: the S9 SecIrisService drives the IR camera through camera2
# (IRController type 1 = HAL_V3, CaptureRequest samsung.android.control.shootingMode) and its irisd/libIrisTlc speak
# the SDM845 sec_iris protocol -> on the S8 HAL + S8 TA: IllegalArgumentException + TA -13/-10. The T835 is the same
# SoC with the same iris sensor (S5K5E6, identical chromatix libs) and on Q still uses IRController type 0 = HAL_V1
# (SemCamera id 90, "shot-mode" 39, setIrisDataCallback) exactly like stock S8 Pie, which this S8 camera HAL serves.
# Its IIrisDaemon / IIrisService / IIrisServiceReceiver AIDL is identical to the G9600 framework's, all native imports
# resolve on the G9600 system, SecIrisService has the same platform cert. Kernel: our T830 Q tree already has
# SAMSUNG_SECURE_CAMERA, MSM_SEC_CCI_TA_NAME="sec_iris", the IRIS_I2C/GPIO ranges and the S2MPB02 IR LED (no stock
# iris symbol is missing).
#
# Trustlet: the stock S8 sec_iris/authhat from apnhlos (see the note at the end - the T835 TA is signed by another
# root and TZ rejects it). Also stages the S8 look for the iris app and the S8 fingerprint-enroll media.
set -e
SYS=$1; O=$2
rm -rf $O; mkdir -p $O/system; L=$O/files.txt; : > $L
get() {  # get <path in T835 img> <dest under $O> <mode> <gid> <label>
  mkdir -p $(dirname $O/$2)
  debugfs -R "dump $1 $O/$2" $SYS >/dev/null 2>&1
  [ -s $O/$2 ] || { echo "iris: missing $1"; exit 1; }
  chmod $3 $O/$2; echo "/$2 $3 0 $4 $5" >> $L
}
SL=u:object_r:system_lib_file:s0; SF=u:object_r:system_file:s0
get /system/bin/irisd system/bin/irisd 755 2000 u:object_r:irisd_exec:s0
for l in libIrisService.so libIrisTlc.so libIrisSensorListener.so hw/iris.default.so; do
  get /system/lib64/$l system/lib64/$l 644 0 $SL
done
# IrisTlc_GetAuthId: T835 request layout (type at +4, sid at +8) -> S8 TA layout (sid at +4); else every unlock
# fails with GetAuthId -40 (tools/patches/patch_iristlc_t835_authid.py)
python3 $(dirname $0)/../patches/patch_iristlc_t835_authid.py $O/system/lib64/libIrisTlc.so $O/system/lib64/libIrisTlc.so
get /system/priv-app/SecIrisService/SecIrisService.apk system/priv-app/SecIrisService/SecIrisService.apk 644 0 $SF
get /system/priv-app/IrisUserTest/IrisUserTest.apk system/priv-app/IrisUserTest/IrisUserTest.apk 644 0 $SF
# SecIrisService stays the stock, Samsung-signed T835 apk (a modified apk fails the signature check at the next
# boot and the package manager drops it). Its two problems are fixed from outside with static overlays:
#  - it reads config_keyguardComponent by the T835 framework-res id -> FrameworkS8Overlay gives that G9600 id the
#    value (tools/build/build_framework_overlay.sh)
#  - tablet UI (0 dp TextureViews = black enroll screen) -> IrisS8Overlay with the S8 phone UI, T835 IDs pinned
#    (tools/build/build_iris_overlay.sh)
bash $(dirname $0)/build_iris_overlay.sh $SYS
P=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p $O/system/vendor/overlay/IrisS8Overlay
cp $P/config/overlay/out/IrisS8Overlay.apk $O/system/vendor/overlay/IrisS8Overlay/IrisS8Overlay.apk
chmod 644 $O/system/vendor/overlay/IrisS8Overlay/IrisS8Overlay.apk
echo "/system/vendor/overlay/IrisS8Overlay 755 0 0 u:object_r:vendor_overlay_file:s0" >> $L
echo "/system/vendor/overlay/IrisS8Overlay/IrisS8Overlay.apk 644 0 0 u:object_r:vendor_overlay_file:s0" >> $L

# S8 fingerprint-enroll guide videos/animation in the G9600 BiometricSetting (it shows the S9 otherwise)
mkdir -p $O/system/priv-app/BiometricSetting
python3 $(dirname $0)/../patches/patch_fp_s8_media.py ~/s8rom/trees/g9600_root/system/priv-app/BiometricSetting/BiometricSetting.apk \
  ~/s8rom/port10/s8sys/priv-app/SecSettings/SecSettings.apk $O/bs.apk
zipalign -f -p 4 $O/bs.apk $O/system/priv-app/BiometricSetting/BiometricSetting.apk; rm -f $O/bs.apk
chmod 644 $O/system/priv-app/BiometricSetting/BiometricSetting.apk
echo "/system/priv-app/BiometricSetting/BiometricSetting.apk 644 0 0 $SF" >> $L

# Trustlet: the stock S8 sec_iris in /vendor/firmware_mnt/image (apnhlos, untouched). The T835 TA cannot be used:
# its cert chain ends in the Tab S4 root (pubkey sha256 5790b0..), this SoC's fused OEM root is the S8 one
# (faaa8e.., same as vaultkeeper) -> QSEECom_start_app errno 22 on every try. T835 irisd + S8 TA: InitLib ok,
# preEnroll / AuthHat ok.
echo "iris: $(wc -l < $L) entries staged"
