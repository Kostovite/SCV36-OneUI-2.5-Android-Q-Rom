#!/usr/bin/env bash
# WSL: package the port vendor for a fast TWRP update (no full system reflash):
#   out/twrp_push/vendor.tar        - ~/s8rom/port/vendor (owners/modes kept, no xattrs)
#   out/twrp_push/vendor_labels.sh  - chcon for every entry (labels computed like the image build)
#   out/twrp_push/system_add.tar    - files for /system itself (S8 camera companion ISP / OIS firmware: the kernel
#                                     msm_companion3 / msm_ois drivers open /system/etc/firmware/* directly)
set -e
P=$(cd "$(dirname "$0")/../.." && pwd); W=~/s8rom/port; V=$W/vendor; O=$P/out/twrp_push
SYSSE=~/s8rom/trees/g9600_root/system/etc/selinux
mkdir -p $O
# label_tree walks <root>/<prefix>; use a staging root so the prefix is /system/vendor like in the image
STAGE=$W/stage; rm -rf $STAGE; mkdir -p $STAGE/system; ln -s $V $STAGE/system/vendor
# SCV38 (S9 au, Q) ISDB-T TV stack, see tools/build/stage_tv_scv38.sh (default OFF, S8PORT_TV38=1 to include; no ISDB-T in VN). Its vendor half (tuner
# HAL + VINTF fragment) goes through vendor.tar so it gets vendor_file_contexts labels; removed from $V again below.
TV38=$W/tv38; TV38V=""
if [ "${S8PORT_TV38:-0}" = 1 ]; then
  bash $P/tools/build/stage_tv_scv38.sh ~/s9fw/system.raw.img ~/s9fw/vendor.raw.img $TV38
  TV38V=$(cd $TV38/system/vendor && find . -type f | sed 's#^\./##')
  for f in $TV38V; do [ -e $V/$f ] && { echo "tv38: $f already in the port vendor"; exit 1; }; done
  (cd $TV38/system/vendor && cp -a --parents $TV38V $V/)
fi
python3 $P/tools/build/label_tree.py --emit-sh $O/vendor_labels.sh $STAGE /system/vendor /vendor \
  $SYSSE/plat_file_contexts $V/etc/selinux/vendor_file_contexts
# debug builds only (S8PORT_DEBUG=1, kernel branch s8-q-port with the s8dbg hooks): the boot-watchdog cancel trigger
if [ "${S8PORT_DEBUG:-0}" = 1 ]; then
  cp $P/installer/debug/s8dbg.rc $V/etc/init/s8dbg.rc
  echo 'chcon -h u:object_r:vendor_configs_file:s0 "$V/etc/init/s8dbg.rc"' >> $O/vendor_labels.sh
fi
# TWRP-side installer scripts next to the payload (out/twrp_push is what the PC scripts and the zip use)
cp $P/installer/twrp/* $O/
# owners like the image build (tools/build/build_system.sh): root everywhere, bin/ root:shell 0755 (the tree is owned by the
# WSL user = uid 1000 = "system" on Android)
tar -C $V --numeric-owner --owner=0 --group=0 -cf $O/vendor.tar .
rm -f $V/etc/init/s8dbg.rc
for f in $TV38V; do rm -f $V/$f; done
SA=$W/system_add; rm -rf $SA; mkdir -p $SA/etc   # (debugfs rdump refuses an existing target dir)
S8IMG=$P/work/stock_CZE1/system.raw.img
debugfs -R "rdump /etc/firmware $SA/etc" $S8IMG >/dev/null 2>&1
[ -f $SA/etc/firmware/ois_fw_sec.bin ] || { echo "S8 /system/etc/firmware not extracted"; exit 1; }
# (no FM radio app: the SCV36 board has no FM chip - its FM I2C bus is disabled in the JPN DT and GPIO 99/100/129
#  are wired to the ISDB-T TV tuner; the installer removes the HybridRadio that boot 17's build added)
# Camera app: the One UI 2 SamsungCamera 10.5 (camera2) needs the S9 HAL's samsung.android.* vendor tags
# (availablePreviewStreamConfigurations, availableFeatures, ...) that the S8 QCamera HAL never publishes -> NPE on the
# preview size. The S8's own SamsungCamera 9.0 (SemCamera / HAL1 parameters, same platform key, privapp whitelist
# already covers it) + the S8 /system/cameradata (feature list for this sensor set) replace it; installer drops the
# S9 apk + oat + app data. S9-only cameradata files (AR emoji, single take models) stay.
mkdir -p $SA/priv-app/SamsungCamera
debugfs -R "dump /priv-app/SamsungCamera/SamsungCamera.apk $SA/priv-app/SamsungCamera/SamsungCamera.apk" $S8IMG >/dev/null 2>&1
debugfs -R "rdump /cameradata $SA" $S8IMG >/dev/null 2>&1
[ -s $SA/priv-app/SamsungCamera/SamsungCamera.apk ] && [ -f $SA/cameradata/camera-feature.xml ] || { echo "S8 camera app not extracted"; exit 1; }
# SamsungCamera 9.0 registers a ContentObserver on com.samsung.android.provider.stickerprovider (PlugInStickerLoader,
# from Camera.loadHeavyResources); Q throws SecurityException for an unknown authority -> the app crashed a few
# seconds after start / on camera switch (core_20261008_011231). Provider = stock S8 priv-app StickerProvider (not in
# the G9600 system; requests no privileged permissions -> no privapp whitelist needed).
mkdir -p $SA/priv-app/StickerProvider
debugfs -R "dump /priv-app/StickerProvider/StickerProvider.apk $SA/priv-app/StickerProvider/StickerProvider.apk" $S8IMG >/dev/null 2>&1
[ -s $SA/priv-app/StickerProvider/StickerProvider.apk ] || { echo "S8 StickerProvider not extracted"; exit 1; }
# Front preview upside down in SamsungCamera 9.0: Q CameraClient skips the front-camera mirror when
# SET_DISPLAY_ORIENTATION has arg2 == 1 (Pie ignored arg2) -> Pie rule restored (tools/patches/patch_cameraservice_orientation.py)
mkdir -p $SA/lib
python3 $P/tools/patches/patch_cameraservice_orientation.py ~/s8rom/trees/g9600_root/system/lib/libcameraservice.so $SA/lib/libcameraservice.so
# Iris: API1 getCameraInfo(90) rejected by the AOSP bounds check although the provider registers hidden device "90"
# -> T835 rule (only id < 0 rejected, id = std::to_string) (tools/patches/patch_cameraservice_hiddenid.py)
python3 $P/tools/patches/patch_cameraservice_hiddenid.py $SA/lib/libcameraservice.so $SA/lib/libcameraservice.so
# SemCamera framework: post COMMON_SHOT_PREVIEW_STARTED for the S8 HAL (tools/patches/patch_semcamera.sh); the installer
# removes the stale G9600 semcamera odex/vdex
mkdir -p $SA/framework
bash $P/tools/patches/patch_semcamera.sh ~/s8rom/trees/g9600_root/system/framework/semcamera.jar $SA/framework/semcamera.jar
# Iris (Tab S4 Q iris stack + S8 trustlet) and the S8 fingerprint-enroll media (tools/build/stage_iris_t835.sh):
# system half + its owner/mode/label list (apply_vendor.sh applies every etc/s8port_*_files.txt). The iris UI overlay
# itself goes into vendor/overlay through build_vendor.sh.
IR=$W/iris; bash $P/tools/build/stage_iris_t835.sh $P/work/donor_T835/system.raw.img $IR
(cd $IR/system && for d in $(ls -A | grep -vx vendor); do cp -a $d $SA/; done)
grep -v '^/system/vendor/' $IR/files.txt > $SA/etc/s8port_iris_files.txt
# ISDB-T TV (SCV36 One-Seg/Full-Seg): stock app + middleware, see tools/build/stage_tv.sh
# 2026-10-09: default OFF again (S8PORT_TV=1 to include) - ISDB-T has no broadcasts in Vietnam (DVB-T2), user request.
# Was re-enabled earlier: the 1912/0021 freeze was the audio HAL crash loop,
# not TV. Live-tested: SDtvService runs as oneseg_mw and registers ISDtvService.SDtvStackService.
[ "${S8PORT_TV:-0}" = 1 ] && bash $P/tools/build/stage_tv.sh $S8IMG ~/s8rom/trees/s8_vendor/vendor $SA
# SCV38 TV, system half + its exact owner/mode/label list (apply_vendor.sh re-applies it after the generic chcon pass)
if [ "${S8PORT_TV38:-0}" = 1 ]; then
  (cd $TV38/system && for d in $(ls -A | grep -vx vendor); do cp -a $d $SA/; done)
  grep -v '^/system/vendor/' $TV38/files.txt > $SA/etc/s8port_tv38_files.txt
fi
# no "./" entry: extracting it over /system copies the staging dir's mode onto /system (see apply_vendor.sh)
(cd $SA && tar --numeric-owner --owner=0 --group=0 -cf $O/system_add.tar $(ls -A))
tar -tvf $O/system_add.tar | tail -n +2 | awk '{print "  system_add:", $6, $3}'
ls -la $O/vendor.tar $O/vendor_labels.sh; wc -l < $O/vendor_labels.sh
grep -E 'keymaster@3.0-service"|IWifiExt|wifi@1.0-service"' $O/vendor_labels.sh | head -3
