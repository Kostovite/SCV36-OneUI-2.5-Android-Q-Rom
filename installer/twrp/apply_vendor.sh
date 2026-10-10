#!/sbin/sh
# Runs in TWRP: replace the port's /system/vendor (except odm/ = CSC data) with vendor.tar and relabel it.
set -e
T=${1:-/data/media/0/s8port}   # folder holding vendor.tar, vendor_labels.sh, system_add.tar (zip installer passes its own)
M=/mnt/s8sys
mkdir -p $M
umount $M 2>/dev/null || true
mount -o rw /dev/block/bootdevice/by-name/system $M
V=$M/system/vendor
[ -d $V/etc ] || { echo "vendor dir not found at $V"; exit 1; }
find $V -mindepth 1 -maxdepth 1 ! -name odm -exec rm -rf {} +
tar -xf $T/vendor.tar -C $V
sh $T/vendor_labels.sh $V >/dev/null
chown -R 0:2000 $V/bin; find $V/bin -type f -exec chmod 0755 {} +
ls -lZ $V/bin/hw/android.hardware.keymaster@3.0-service $V/etc/init/s8dbg.rc
# /system additions (S8 camera companion ISP + OIS firmware in /system/etc/firmware, read by the kernel)
if [ -f $T/system_add.tar ]; then
  # S8 SamsungCamera 9.0 replaces the S9 10.5 one: drop the old apk + its oat, and the app data/dex caches of the
  # newer version (the app recreates them; a downgrade over 10.5 databases would crash)
  if tar -tf $T/system_add.tar | grep -q 'priv-app/SamsungCamera/SamsungCamera.apk'; then
    rm -rf $M/system/priv-app/SamsungCamera
    D=/data
    rm -rf $D/data/com.sec.android.app.camera $D/user_de/0/com.sec.android.app.camera $D/misc/profiles/cur/0/com.sec.android.app.camera \
           $D/misc/profiles/ref/com.sec.android.app.camera $D/dalvik-cache/*/system@priv-app@SamsungCamera@* 2>/dev/null || true
    echo "camera: S9 SamsungCamera removed (apk, oat, app data)"
  fi
  # patched semcamera.jar (S8 HAL preview-started event): the G9600 odex/vdex no longer match its dex
  tar -tf $T/system_add.tar | grep -q 'framework/semcamera.jar' && rm -f $M/system/framework/oat/*/semcamera.odex $M/system/framework/oat/*/semcamera.vdex
  # iris stack (T835 SecIrisService replaces the S9 one) + BiometricSetting with the S8 fingerprint media: drop the
  # old oat / dex caches of the replaced apks
  for a in SecIrisService IrisUserTest BiometricSetting; do
    if tar -tf $T/system_add.tar | grep -q "priv-app/$a/$a.apk"; then
      rm -rf $M/system/priv-app/$a/oat /data/dalvik-cache/*/system@priv-app@$a@* 2>/dev/null || true
    fi
  done
  tar -xf $T/system_add.tar -C $M/system
  # a "./" entry in the tar would stamp its own mode onto /system itself (2026-10-09: /system became 0644 ->
  # init "Error getting file context handle" -> execv(/system/bin/init) EACCES -> kernel panic at 2.4 s)
  chown 0:0 $M/system; chmod 0755 $M/system
  for e in $(tar -tf $T/system_add.tar | sed 's#^\./##; s#/$##' | grep -v '^\.\?$'); do
    f=$M/system/$e; chown 0:0 $f
    if [ -d $f ]; then chmod 0755 $f; else chmod 0644 $f; fi
    case "$e" in lib|lib/*|lib64|lib64/*) ctx=system_lib_file ;; *) ctx=system_file ;; esac   # plat_file_contexts
    chcon u:object_r:$ctx:s0 $f 2>/dev/null || echo "note: chcon $e failed"
  done
  # SCV38 TV (tools/build/stage_tv_scv38.sh): exact SCV38 owner/mode/label per file ("<path> <mode|L:target> <uid> <gid>
  # <label>"); the generic pass above made dtvserver/dtvmgr 0644 and followed the app's lib symlinks
  # same format for the iris stack (tools/build/stage_iris_t835.sh: irisd = irisd_exec root:shell 0755, ...)
  for LST in $M/system/etc/s8port_tv38_files.txt $M/system/etc/s8port_iris_files.txt; do
  [ -f $LST ] || continue
    while read p m u g l; do
      case $m in
        L:*) chcon -h $l $M$p 2>/dev/null || echo "note: chcon $p failed" ;;
        *) chown $u:$g $M$p; chmod $m $M$p; chcon $l $M$p 2>/dev/null || echo "note: chcon $p failed" ;;
      esac
    done < $LST
    echo "metadata: $(wc -l < $LST) entries from $(basename $LST)"
  done
  [ -f $M/system/bin/irisd ] && ls -lZ $M/system/bin/irisd
  # ISDB-T TV middleware (tools/build/stage_tv.sh): executable + the Q vendor policy's oneseg_mw entry type
  if [ -f $M/system/bin/SDtvService ]; then
    chown 0:2000 $M/system/bin/SDtvService; chmod 0755 $M/system/bin/SDtvService
    chcon u:object_r:oneseg_mw_exec:s0 $M/system/bin/SDtvService 2>/dev/null || echo "note: chcon SDtvService failed"
    ls -lZ $M/system/bin/SDtvService
  fi
  # The companion-ISP / OIS kernel drivers open /system/etc/firmware/* from inside the camera HAL process
  # (hal_camera_default), which Q policy lets read vendor_file_type but not system_file -> "failed to open
  # /system/etc/firmware/F12QS_Isp0_imx333.bin, err -13", no rear camera. vendor_firmware_file is a vendor_file_type.
  for f in $M/system/etc/firmware/*; do chcon u:object_r:vendor_firmware_file:s0 $f 2>/dev/null || echo "note: chcon $f failed"; done
  ls -Z $M/system/etc/firmware | head -3
  echo "system_add: $(ls $M/system/etc/firmware | wc -l) files in /system/etc/firmware"
fi
# ISDB-T TV (tools/build/stage_tv.sh, zips 1912/0021) postponed: remove it unless this zip carries it again
if ! tar -tf $T/system_add.tar 2>/dev/null | grep -q 'bin/SDtvService'; then
  rm -rf $M/system/priv-app/MobileTV_JPN_HYBRID $M/system/bin/SDtvService $M/system/etc/one-seg \
         $M/system/etc/init/init.isdbttv.rc $M/system/etc/permissions/privapp-permissions-com.samsung.android.app.dtv.isdbt.xml $M/system/fonts/BML.ttf
  for l in libSDtvService libSDtvStack libSDtvPorting libISDBT_tuner libtuneriface libtlcSDtvRmp libbroadcastForOneSeg_jni \
           libOneSegfactorytest_jni_fb libonesegutils libonesegbmlpeer libQSEEComAPI libsdtv_compat libBML libTvsystemInterface; do
    rm -f $M/system/lib64/$l.so
  done
  rm -rf /data/app/com.samsung.android.app.dtv.isdbt-* /data/data/com.samsung.android.app.dtv.isdbt \
         /data/user_de/0/com.samsung.android.app.dtv.isdbt /data/dalvik-cache/*/system@priv-app@MobileTV_JPN_HYBRID@* 2>/dev/null || true
  echo "tv: removed"
fi
# SCV38 TV (tools/build/stage_tv_scv38.sh, default off): remove it unless this zip carries it
if ! tar -tf $T/system_add.tar 2>/dev/null | grep -q 'bin/dtvserver'; then
  rm -rf $M/system/priv-app/FsDtvApp $M/system/bin/dtvserver $M/system/bin/dtvmgr $M/system/media/dtv \
         $M/system/etc/multimedia $M/system/etc/init/init.fsidtv.rc $M/system/etc/s8port_tv38_files.txt \
         $M/system/etc/permissions/privapp-permissions-jp.co.fsi.fs1seg.xml
  rm -f $M/system/lib64/libDtv*.so $M/system/lib64/libdtvsdserver*.so $M/system/lib64/libsdvm*.so \
        $M/system/lib/vendor.samsung.hardware.dtvtuner@1.0.so $M/system/lib64/vendor.samsung.hardware.dtvtuner@1.0.so \
        $V/bin/hw/vendor.samsung.hardware.dtvtuner@1.0-service $V/lib64/libonesegdmxdriver_ltn.so \
        $V/lib/vendor.samsung.hardware.dtvtuner@1.0_vendor.so $V/lib64/vendor.samsung.hardware.dtvtuner@1.0_vendor.so \
        $V/etc/init/vendor.samsung.hardware.dtvtuner@1.0-service.rc $V/etc/vintf/manifest/dtvtuner.xml
  rm -rf /data/data/jp.co.fsi.fs1seg /data/user_de/0/jp.co.fsi.fs1seg /data/dalvik-cache/*/system@priv-app@FsDtvApp@* \
         /data/dtv 2>/dev/null || true
  echo "tv38: removed"
fi
# FM radio app added by the boot 17 build: the SCV36 has no FM chip (ISDB-T tuner on those pins) -> remove it again
rm -rf $M/system/priv-app/HybridRadio
# ss_conn_daemon2 (G9600 /init.rc, DeX on PC / Samsung Flow) exits at once on this port and init restarts it every
# 5 s forever (debugpart klog: 42 starts in ~4 min, CPU wakeups) -> disabled (start ss_conn_daemon2_service by hand)
I=$M/init.rc
if [ -f $I ] && ! grep -A6 '^service ss_conn_daemon2_service' $I | grep -q '^    disabled'; then
  sed -i '/^service ss_conn_daemon2_service /a\    disabled' $I && echo "init.rc: ss_conn_daemon2_service disabled"
fi
# IPService (Gallery AI tagger) aborts in a loop: the T835 SNAP HAL lacks /vendor/saiv image-understanding models
rm -rf $M/system/priv-app/IPService /data/app/com.samsung.ipservice-* /data/data/com.samsung.ipservice 2>/dev/null || true
# CSC: the SCV36 EFS sales code (imei/mps_code.dat) is KDI, which the G9600 odm does not carry -> sales code empty,
# no carrier features (VoLTE off). KDI = alias of the Vietnamese XXV CSC (EFS untouched).
O=$V/odm/etc/omc
if [ -d $O/XXV ]; then
  rm -rf $O/KDI; cp -a $O/XXV $O/KDI
  grep -qx KDI $O/sales_code_list.dat || echo KDI >> $O/sales_code_list.dat
  echo "omc: KDI -> XXV ($(ls $O/KDI | wc -l) entries)"
fi
# odm labels/modes as on a real /odm partition (G9600 odm.img): the first system image labelled it vendor_file
# (as /vendor/odm) and XXV came in as uid 1000 / 0777 -> scs, ePDG and IMS got EACCES on customer.xml. Never fatal.
OD=$V/odm
for c in XXV KDI; do
  [ -d $O/$c ] || continue
  chown -R 0:0 $O/$c; find $O/$c -type d -exec chmod 0755 {} +; find $O/$c -type f -exec chmod 0644 {} +
done
chcon -R u:object_r:vendor_configs_file:s0 $OD/etc 2>/dev/null || echo "note: chcon odm/etc failed"
for d in app priv-app; do [ -d $OD/$d ] && { chcon -R u:object_r:vendor_app_file:s0 $OD/$d 2>/dev/null || echo "note: chcon odm/$d failed"; }; done
ls -lZd $O/KDI $O/KDI/conf/customer.xml 2>/dev/null || true
# Samsung apps pick chip policies (SDHMS/SSRM GPU limits) by ro.hardware.chipname: S9 system says SDM845
sed -i 's/^ro\.hardware\.chipname=.*/ro.hardware.chipname=MSM8998/' $M/system/build.prop
# props the vendor build.prop may not set on Q (loaded with vendor_init SELinux context) -> system build.prop
B=$M/system/build.prop
FP=$(grep -m1 '^ro.system.build.fingerprint=' $B | cut -d= -f2-)
sed -i -e '/^ro\.bt\.bdaddr_path=/d' -e '/^ro\.vendor\.gpu\.available_frequencies=/d' -e '/^ro\.build\.fingerprint=/d' -e '/^# S8 port props/d' \
       -e '/^persist\.camera\.HAL3\.enabled=/d' -e '/^wifi\.direct\.interface=/d' -e '/^audio\.offload\.disable=/d' $B
STEREO=0; grep -qs 's8port stereo earpiece' $M/system/vendor/etc/mixer_paths_tavil.xml $M/vendor/etc/mixer_paths_tavil.xml && STEREO=1
{ echo "# S8 port props"
  echo "ro.bt.bdaddr_path=/efs/bluetooth/bt_addr"
  # S8 SamsungCamera 9.0 speaks HAL1 (Samsung parameters + sendCommand 1000/1508/1807/1821); the Pie cameraserver
  # served it through Samsung's extended Camera2Client, the Q one rejects it ("Unknown command", "preview FPS range
  # 15 - 30 is not supported"). QCamera2Factory: HAL3.enabled=0 -> every camera reported as device 1.0 (the mode the
  # S8 HAL uses on factory builds) -> CameraClient passes everything straight to the HAL; camera2 apps use the
  # framework legacy shim.
  echo "persist.camera.HAL3.enabled=0"
  # (Wi-Fi Direct: no wifi.direct.interface override - p2p-dev-wlan0 broke P2P setup completely in boot 22; the
  #  supplicant is now the G9600 Broadcom build, which handles the bcmdhd p2p0 netdev itself)
  echo "ro.vendor.gpu.available_frequencies=710000000 670000000 596000000 515000000 414000000 342000000 257000000"
  # S8PORT_STEREO builds: compress offload has no DSP channel mixer -> music through deep-buffer (speaker L + earpiece R)
  if [ $STEREO = 1 ]; then echo "audio.offload.disable=true"; fi
  if [ -n "$FP" ]; then echo "ro.build.fingerprint=$FP"; fi; } >> $B
grep -A4 '^# S8 port props' $B
grep '^ro.hardware.chipname=' $M/system/build.prop || echo 'note: no chipname line in build.prop'
# Display: Samsung WM (CoreRune.FW_DYNAMIC_RESOLUTION_CONTROL, compiled into the S9 services.jar) applies a 0.75
# screen ratio (FHD+ 1080x2220 / 480 dpi) at every boot whenever display_size_forced is EMPTY, and `wm size <native>`
# stores an empty value. The T835 composer shows FHD+ unscaled in the top-left. Store the native size explicitly.
setxml() {  # file name value
  f=$1; n=$2; v=$3
  [ -f $f ] || return 0
  sed -i "/<setting [^>]* name=\"$n\" /d" $f
  id=$(( $(grep -o ' id="[0-9]*"' $f | grep -o '[0-9][0-9]*' | sort -n | tail -1) + 1 ))
  line="<setting id=\"$id\" name=\"$n\" value=\"$v\" package=\"android\" defaultValue=\"$v\" defaultSysSet=\"true\" />"
  grep -v '</settings>' $f > $f.new
  { echo "$line"; echo '</settings>'; } >> $f.new
  cat $f.new > $f; rm -f $f.new   # cat keeps owner/mode/SELinux label of the original file
  grep -o "<setting [^>]* name=\"$n\" [^>]*>" $f
}
G=/data/system/users/0/settings_global.xml; SS=/data/system/users/0/settings_secure.xml
setxml $G display_size_forced 1440,2960
setxml $SS display_density_forced 640
setxml $SS default_display_size_forced 1440,2960
setxml $SS default_display_density_forced 640
# AOD charging info: AODService stored charging_info_always=-1 (hidden) while it could see led_pattern; drop it so
# it is re-evaluated with the new sysfs_led_pattern label (-> 1, "Show charging information" switch available)
SY=/data/system/users/0/settings_system.xml
if [ -f $SY ] && grep -q 'name="charging_info_always" value="-1"' $SY; then
  grep -v 'name="charging_info_always"' $SY > $SY.new; cat $SY.new > $SY; rm -f $SY.new; echo "aod: charging_info_always reset"
fi
# fingerprint: the S8 bauth stack reads a sensor-type/metadata cache in /data/vendor/biometrics that the G9600 bauth
# wrote in its own format on earlier boots ("read SNSR Type success but file has wrong data"); nothing is enrolled
# yet -> start clean (the HAL recreates the tree; s8_fingerprint.rc recreates the dirs)
if [ -d /data/vendor/biometrics ]; then rm -rf /data/vendor/biometrics/*; echo "fingerprint: /data/vendor/biometrics cleared"; fi
sync
umount $M
echo APPLY_OK
