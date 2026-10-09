#!/usr/bin/env bash
# WSL: stage the SCV36 ISDB-T TV (One-Seg / Full-Seg, FCI FC8300 tuner) into system_add for the One UI 2 port.
# usage: stage_tv.sh <stock SCV36 Pie system.raw.img> <S8 Pie vendor dir> <system_add dir>
#
# Stock layout (SCV36 Pie): app priv-app/MobileTV_JPN_HYBRID (com.samsung.android.app.dtv.isdbt, platform cert),
# /system/bin/SDtvService (started by the S8 vendor init.carrier.rc), init.isdbttv.rc (/data/one-seg), /etc/one-seg
# data, middleware libs in /system/vendor/lib64. Those libs are platform libs (libstagefright, libgui, libmedia,
# libbinder, libandroid_runtime ...) loaded by a system binary and a priv-app JNI -> on the Q port they go to
# /system/lib64 (system namespace); libSDtvService dlopen()s two of them by their Pie /system/vendor path -> patched to
# an equal-length /system/lib64 path. Imports checked against the G9600 Q system: only GraphicBuffer::lock(uint32_t,
# void**) and get_malloc_leak_info are gone -> libsdtv_compat.so (config/stubs/sdtv_compat.c). libtlcSDtvRmp (Full-Seg
# RMP, QSEE TA in /vendor/firmware_mnt) needs libQSEEComAPI -> S8 copy in /system/lib64 (deps libion etc. are system).
# Kernel: the T830 Q tree carries the SCV36 FC8300 driver (isdbt_pdata: lna-en, isdbt_gpio_active/suspend, force_off)
# built from the stock config; SELinux: the T835 Q vendor policy already has Samsung's Q oneseg_mw / mmb_device /
# oneseg_data_file / oneseg_apk policy and file contexts (/system/bin/SDtvService, /dev/isdbt, /data/one-seg).
set -e
IMG=$1; S8=$2; SA=$3
P=$(cd "$(dirname "$0")/../.." && pwd); C=$P/config
mkdir -p $SA/priv-app $SA/bin $SA/lib64 $SA/etc/init $SA/etc/permissions   # (no etc/one-seg: debugfs rdump refuses an existing dir)
debugfs -R "rdump /priv-app/MobileTV_JPN_HYBRID $SA/priv-app" $IMG >/dev/null 2>&1
debugfs -R "dump /bin/SDtvService $SA/bin/SDtvService" $IMG >/dev/null 2>&1
debugfs -R "dump /etc/permissions/privapp-permissions-com.samsung.android.app.dtv.isdbt.xml $SA/etc/permissions/privapp-permissions-com.samsung.android.app.dtv.isdbt.xml" $IMG >/dev/null 2>&1
debugfs -R "rdump /etc/one-seg $SA/etc" $IMG >/dev/null 2>&1
# data broadcast (BML) engine: the app System.loadLibrary("BML") (One-Seg) and "TvsystemInterface" (Full-Seg
# bml_aprofile) + its font; each missing one crashed the live player (UnsatisfiedLinkError in onResume)
mkdir -p $SA/fonts; debugfs -R "dump /fonts/BML.ttf $SA/fonts/BML.ttf" $IMG >/dev/null 2>&1
debugfs -R "dump /etc/init/init.isdbttv.rc $SA/etc/init/init.isdbttv.rc" $IMG >/dev/null 2>&1
[ -s $SA/priv-app/MobileTV_JPN_HYBRID/MobileTV_JPN_HYBRID.apk ] && [ -s $SA/bin/SDtvService ] && [ -s $SA/etc/one-seg/njccp932.ctb ] && [ -s $SA/fonts/BML.ttf ] || { echo "tv: stock files missing"; exit 1; }
# the service itself was in the S8 vendor init.carrier.rc (not used on the port) -> system rc, same definition
cat >> $SA/etc/init/init.isdbttv.rc <<'RC'

# S8 port: SCV36 vendor init.carrier.rc "service SDtvService" (JPN MobileTV), unchanged
service SDtvService /system/bin/SDtvService
    class main
    user system
    group system audio sdcard_rw shell media media_rw oem_5432

on boot
    chown system system /dev/isdbt
    chmod 0660 /dev/isdbt
RC
for l in libSDtvService libSDtvStack libSDtvPorting libISDBT_tuner libtuneriface libtlcSDtvRmp \
         libbroadcastForOneSeg_jni libOneSegfactorytest_jni_fb libonesegutils libonesegbmlpeer libBML libTvsystemInterface libQSEEComAPI; do
  cp $S8/lib64/$l.so $SA/lib64/$l.so
done
cp $C/stubs/out/lib64/libsdtv_compat.so $SA/lib64/libsdtv_compat.so
patchelf --add-needed libsdtv_compat.so $SA/lib64/libSDtvPorting.so
patchelf --add-needed libsdtv_compat.so $SA/lib64/libonesegutils.so
python3 - $SA/lib64/libSDtvService.so <<'PY'
import sys
p = sys.argv[1]; d = open(p, 'rb').read()
n = 0
for lib in (b'libISDBT_tuner.so', b'libSDtvStack.so'):
    old = b'/system/vendor/lib64/' + lib
    new = b'/system////////lib64/' + lib          # same length; realpath = /system/lib64/<lib>
    assert len(old) == len(new)
    n += d.count(old + b'\0'); d = d.replace(old + b'\0', new + b'\0')
assert n == 2, 'expected 2 hardcoded paths, found %d' % n
open(p, 'wb').write(d); print('tv: libSDtvService dlopen paths -> /system/lib64')
PY
echo "tv: $(find $SA/priv-app/MobileTV_JPN_HYBRID $SA/bin/SDtvService $SA/etc/one-seg $SA/lib64 -type f | wc -l) files staged"
