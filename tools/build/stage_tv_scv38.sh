#!/usr/bin/env bash
# WSL: stage the SCV38 (Galaxy S9 au, Android 10) ISDB-T TV stack for the One UI 2 port.
# usage: stage_tv_scv38.sh <SCV38 system.raw.img> <SCV38 vendor.raw.img> <out dir>
#   <out>/system/...           files (vendor ones under system/vendor, like the port image)
#   <out>/files.txt            "<path> <mode> <uid> <gid> <selinux label>" for every staged file, labels as in SCV38
#
# Why it fits the SCV36: the SCV38 tuner is the FC8350 (FCI FC83xx family). Its vendor HAL
# (vendor.samsung.hardware.dtvtuner@1.0-service, source TUNNER_FC83XX/oneseg_tunner_hal_FC83XX.c) talks to /dev/isdbt
# with the same 't' ioctl set (0..29, incl. TUNER_SELECT_2 / PKT_MODE / RF_BER) that our FC8300 driver implements.
# Middleware = Fujisoft "FS1SEG" (app jp.co.fsi.fs1seg, /system/bin/dtvserver -> dtvmgr, libDtv*), Full-Seg TRMP is
# software (OpenSSL, /data/dtv) - no TEE app. All imports resolve against the G9600 Q system (both are S9 / Q).
# SELinux: the T835 Q vendor policy already has the identical dtvserver / digital_tv_fullseg / dtv_data_file rules and
# contexts, the G9600 plat_service_contexts has dtv.mgr / dtv.server / dtvbml.server / sd.service. Only the VINTF
# manifest entry for IDtvTuner is missing -> vendor/etc/vintf/manifest/dtvtuner.xml.
set -e
SYS=$1; VEN=$2; O=$3
rm -rf $O; mkdir -p $O/system; L=$O/files.txt; : > $L
get() {  # get <img> <path in img> <dest under $O> <mode> <gid> <label>
  mkdir -p $(dirname $O/$3)
  debugfs -R "dump $2 $O/$3" $1 >/dev/null 2>&1
  [ -s $O/$3 ] || { echo "tv38: missing $2"; exit 1; }
  chmod $4 $O/$3      # (debugfs dump does not keep the mode; vendor.tar carries it for the HAL)
  echo "/$3 $4 0 $5 $6" >> $L
}
SL=u:object_r:system_lib_file:s0; SF=u:object_r:system_file:s0
get $SYS /system/bin/dtvserver system/bin/dtvserver 755 2000 u:object_r:dtvserver_exec:s0
get $SYS /system/bin/dtvmgr system/bin/dtvmgr 755 2000 $SF
for l in $(debugfs -R "ls /system/lib64" $SYS 2>/dev/null | tr -s ' \t' '\n' | grep -E '^(libDtv|libdtvsdserver|libsdvm)[A-Za-z_]*\.so$'); do
  get $SYS /system/lib64/$l system/lib64/$l 644 0 $SL
done
for a in lib lib64; do
  get $SYS /system/$a/vendor.samsung.hardware.dtvtuner@1.0.so system/$a/vendor.samsung.hardware.dtvtuner@1.0.so 644 0 $SL
done
get $SYS /system/priv-app/FsDtvApp/FsDtvApp.apk system/priv-app/FsDtvApp/FsDtvApp.apk 644 0 $SF
# app lib/arm64 entries are symlinks to /system/lib64 (staged above) -> "L" = symlink, target in the mode field
mkdir -p $O/system/priv-app/FsDtvApp/lib/arm64
for l in libDtv_jni.so libDtvBml_jni.so; do
  ln -sf /system/lib64/$l $O/system/priv-app/FsDtvApp/lib/arm64/$l
  echo "/system/priv-app/FsDtvApp/lib/arm64/$l L:/system/lib64/$l 0 0 $SF" >> $L
done
get $SYS /system/etc/permissions/privapp-permissions-jp.co.fsi.fs1seg.xml system/etc/permissions/privapp-permissions-jp.co.fsi.fs1seg.xml 644 0 $SF
get $SYS /system/etc/init/init.fsidtv.rc system/etc/init/init.fsidtv.rc 644 0 $SF
for f in $(debugfs -R "ls /system/etc/multimedia" $SYS 2>/dev/null | tr -s ' \t' '\n' | grep -vE '^(\.|\.\.|[0-9]+|\([0-9]+\))$'); do
  get $SYS /system/etc/multimedia/$f system/etc/multimedia/$f 644 0 $SF
done
# media/dtv: sounds, BML graphics and the BML font
for d in sound font bml/sound bml/graphic; do
  for f in $(debugfs -R "ls /system/media/dtv/$d" $SYS 2>/dev/null | tr -s ' \t' '\n' | grep '^dtv-rsc-'); do
    get $SYS /system/media/dtv/$d/$f system/media/dtv/$d/$f 644 0 $SF
  done
done
# vendor side: tuner HAL
get $VEN /bin/hw/vendor.samsung.hardware.dtvtuner@1.0-service system/vendor/bin/hw/vendor.samsung.hardware.dtvtuner@1.0-service 755 2000 u:object_r:digital_tv_fullseg_exec:s0
get $VEN /lib64/libonesegdmxdriver_ltn.so system/vendor/lib64/libonesegdmxdriver_ltn.so 644 0 u:object_r:vendor_file:s0
for a in lib lib64; do
  get $VEN /$a/vendor.samsung.hardware.dtvtuner@1.0_vendor.so system/vendor/$a/vendor.samsung.hardware.dtvtuner@1.0_vendor.so 644 0 u:object_r:vendor_file:s0
done
get $VEN /etc/init/vendor.samsung.hardware.dtvtuner@1.0-service.rc system/vendor/etc/init/vendor.samsung.hardware.dtvtuner@1.0-service.rc 644 0 u:object_r:vendor_configs_file:s0
mkdir -p $O/system/vendor/etc/vintf/manifest
cat > $O/system/vendor/etc/vintf/manifest/dtvtuner.xml <<'XML'
<manifest version="1.0" type="device">
    <hal format="hidl">
        <name>vendor.samsung.hardware.dtvtuner</name>
        <transport>hwbinder</transport>
        <version>1.0</version>
        <interface>
            <name>IDtvTuner</name>
            <instance>default</instance>
        </interface>
    </hal>
</manifest>
XML
echo "/system/vendor/etc/vintf/manifest/dtvtuner.xml 644 0 0 u:object_r:vendor_configs_file:s0" >> $L
echo "tv38: $(wc -l < $L) files staged"
