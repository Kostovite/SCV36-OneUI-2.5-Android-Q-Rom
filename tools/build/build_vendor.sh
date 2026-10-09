#!/usr/bin/env bash
# WSL: assemble the One UI 2 port vendor = Tab S4 (T835) Android 10 vendor + S8 phone hardware from the SCV36 Pie vendor.
# Output tree: ~/s8rom/port/vendor   (goes into /system/vendor of the port system image)
set -e
T=~/s8rom/trees; P=$(cd "$(dirname "$0")/../.." && pwd); C=$P/config
S8=$T/s8_vendor/vendor; S8SYS=$T/s8_system; TV=$T/t835_vendor
W=~/s8rom/port; V=$W/vendor
mkdir -p $W
rsync -a --delete $TV/ $V/
echo "base: T835 vendor $(du -sm $V | cut -f1) MiB"

# 1) remove the tablet's Qualcomm-radio wifi/bt services (replaced by the S8 Broadcom ones)
for f in bin/hw/android.hardware.bluetooth@1.0-service-qti; do   # T835 Q wifi services are kept (see transplant_deps.py)
  rm -f $V/$f
  grep -rl "$(basename $f)" $V/etc/init 2>/dev/null | xargs -r rm -f
done

# 2) transplant HAL file sets (SYSTEM: = from S8 Pie /system, Pie keeps vendor.samsung.* iface libs there)
for g in fingerprint nfc wifi bluetooth tz sensors camera audio; do
  # drop T835 init files that start the same binaries (avoids duplicate/competing services);
  # wifi: the T835 wifi.rc (data dirs, wpa_supplicant, macloader service) stays and runs the S8 macloader binary
  [ $g = wifi ] || sed 's/^G9600://' $C/transplant/$g.txt | grep -E '^bin/' | while read -r b; do
    grep -rlF "/vendor/$b" $V/etc/init 2>/dev/null | while read -r rc; do
      case "$rc" in */etc/init/hw/*) echo "  kept core ${rc#$V/} (starts $b)"; continue ;; esac   # init.qcom.rc etc.
      sed 's/^G9600://' $C/transplant/$g.txt | grep -qxF "${rc#$V/}" || { rm -f "$rc"; echo "  removed T835 ${rc#$V/} (starts $b)"; }
    done
  done
  while read -r f; do
    [ -z "$f" ] && continue
    if [[ $f == SYSTEM:* ]]; then src=$S8SYS/${f#SYSTEM:}; dst=$V/${f#SYSTEM:}
    elif [[ $f == G9600:* ]]; then src=$T/g9600_vendor/${f#G9600:}; dst=$V/${f#G9600:}
    else src=$S8/$f; dst=$V/$f; fi
    mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"
  done < $C/transplant/$g.txt
  if [ $g = tz ]; then for rc in $(grep '^etc/init/' $C/transplant/$g.txt); do [ -f $TV/$rc ] && cp -a $TV/$rc $V/$rc && echo "  kept T835 $rc"; done; fi
  echo "transplanted $g: $(grep -c . $C/transplant/$g.txt) files"
done
# 2b) camera: S8 Pie libs that reach for libandroid.so (not loadable from a vendor process on Q).
#     libmmcamera2_stats_modules: stale NEEDED (no libandroid symbol used) -> dropped.
#     libsensorlistener (camera HAL sensor hints via ASensorManager) -> vendor stub (config/stubs, tools/build/build_stubs.sh).
bash $P/tools/build/build_stubs.sh >/dev/null
cp $C/stubs/out/lib/libsensorlistener.so $V/lib/libsensorlistener.so
# Pie-only imports found by tools/build/vendor_symbol_audit.py (each was a silent dlopen failure of a camera plugin):
#   set_sched_policy (Pie libcutils, Q libprocessgroup)  -> libhifills (low-light shot: no photo was ever saved)
#   __aeabi_idiv0 (Pie libc)                             -> libOpenCv / libxcv (blur detection) -> libaeabi_compat
for b in lib lib64; do [ -f $V/$b/libhifills.so ] && patchelf --add-needed libprocessgroup.so $V/$b/libhifills.so; done
cp $C/stubs/out/lib/libaeabi_compat.so $V/lib/libaeabi_compat.so
for l in libOpenCv.camera.samsung.so libxcv.camera.samsung.so; do patchelf --add-needed libaeabi_compat.so $V/lib/$l; done
patchelf --remove-needed libandroid.so $V/lib/libmmcamera2_stats_modules.so
for f in $V/lib/*.so $V/lib/hw/*.so; do readelf -d "$f" 2>/dev/null | grep -q 'NEEDED.*\[libandroid\.so\]' && echo "  WARN still needs libandroid: ${f#$V/}"; done
echo "camera: libsensorlistener stub + stats_modules NEEDED fixed"
# torch level slider: the S8 Pie HAL module has no set_torch_mode_strength (camera_module_t +0xa8, Samsung Q) ->
# wrapper module (config/stubs/camera_torch_shim.c) in front of the real HAL, renamed camera.msm8998_s8.so
mv $V/lib/hw/camera.msm8998.so $V/lib/hw/camera.msm8998_s8.so
cp $C/stubs/out/lib/hw/camera.msm8998.so $V/lib/hw/camera.msm8998.so
[ ! -e $V/lib64/hw/camera.msm8998.so ] || echo "  WARN 64-bit camera HAL present - torch wrapper is 32-bit only"
echo "camera: torch-strength wrapper installed (real HAL = lib/hw/camera.msm8998_s8.so)"
# camera preview stripes in every app: T835 gralloc aligns NV21 rows to the Adreno pixel alignment (1440 -> 1472), the
# S8 HAL1 writes 1440-byte rows (S8 Pie gralloc: ALIGN 16) -> NV21 back to ALIGN(w, 16) (tools/patches/patch_gralloc_nv21.py)
python3 $P/tools/patches/patch_gralloc_nv21.py $V
# S8 libuniplugin dlopens Samsung camera plugins by name. The S8 Pie kept most of them (hifills = low-light shot,
# blurdetection, focuspeaking, hypermotion, smartfocus, vdis = video stabilisation; interface + core) in /system/lib,
# which a vendor process cannot load on Q -> without them the auto low-light capture never finished (no photo saved,
# camfp_20261008_014344). They come from the S8 system via config/transplant/camera.txt (SYSTEM:lib/...); any other
# T835 plugin of the same name belongs to the tablet HAL -> removed.
for p in $(strings $V/lib/libuniplugin.so | grep -E '^lib.*_interface\.so$' | sort -u); do
  for b in lib lib64; do
    grep -qxF "SYSTEM:$b/$p" $C/transplant/camera.txt && continue
    [ -f $V/$b/$p ] && [ ! -f $T/s8_vendor/vendor/$b/$p ] && { rm -f $V/$b/$p; echo "  camera: removed T835 plugin $b/$p"; }
  done
done
# argosd (T835 network-throughput booster) needs CONFIG_ARGOS (/dev/network_throughput, DT soc/argos) - not in the S8
# kernel (stock SCV36 neither): it exits at once and init restarted it every 5 s forever -> no service
rm -f $V/etc/init/argos.rc
# 2c) audio: S8 Pie audio HAL stack (config/transplant/audio.txt) under the T835 Q audio@5.0 / effect@5.0 / Samsung
#     ISehDevicesFactory services. The S8 speaker (Maxim MAX98506) needs the S8 HAL's Samsung DSM speaker protection
#     (VI feedback on TERT_MI2S_TX) + S8 ACDB (DSP EQ/limiter/DSM tuning) + S8 SoundBooster v8 (Pie lib +
#     lib_SoundBooster_ver800 + its own param format); the T835 HAL/ACDB/SoundBooster are tuned for the tablet's quad
#     TFA9896 speakers. Wrapper (config/stubs/audio_hal_shim.c) supplies the Q-only sec_get_audio_device_instance /
#     sec_get_audio_stream_instance that audio.sec_primary.default.so dlsym()s from the primary module.
mv $V/lib/hw/audio.primary.msm8998.so $V/lib/hw/audio.primary.msm8998_s8.so
# The Pie HAL imports set_sched_policy (libcutils on Pie); on Q it lives in libprocessgroup (VNDK-SP, same signature).
# Without it dlopen fails ("cannot locate symbol set_sched_policy") -> audio service crash loop (0021 freeze).
patchelf --add-needed libprocessgroup.so $V/lib/hw/audio.primary.msm8998_s8.so
cp $C/stubs/out/lib/hw/audio.primary.msm8998.so $V/lib/hw/audio.primary.msm8998.so
# tablet-only pieces the S8 HAL never loads (T835 HAL plugins, quad-speaker TDM SoundBooster, TFA amp firmware)
for f in lib/libspkrprot.so lib/libcirrusspkrprot.so lib/soundfx/libsamsungSoundbooster_tdm.so \
         lib64/soundfx/libsamsungSoundbooster_tdm.so lib/lib_SoundBooster_TDM_ver100.so lib64/lib_SoundBooster_TDM_ver100.so \
         firmware/Tfa9896.cnt; do
  [ -e $V/$f ] && rm -f $V/$f && echo "  audio: removed T835 $f"
done
# S8 Pie audio props (S8 kept them in /system/build.prop): psychoacoustic bass enhancement for the small speaker,
# ADM buffering; the T835 feature flags (vendor.audio.feature.*) only steer the T835 HAL plugin loader
sed -i -E '/^vendor\.audio\.safx\.pbe\.enabled=/d; /^vendor\.audio\.adm\.buffering\.ms=/d; /^vendor\.audio\.noisy\.broadcast\.delay=/d' $V/build.prop
cat >> $V/build.prop <<'PROPS'
# S8 port: S8 Pie audio HAL props
vendor.audio.safx.pbe.enabled=true
vendor.audio.adm.buffering.ms=6
vendor.audio.noisy.broadcast.delay=600
vendor.audio.offload.pstimeout.secs=3
PROPS
readelf -W --dyn-syms $V/lib/hw/audio.primary.msm8998.so | grep -q sec_get_audio_stream_instance || { echo "audio wrapper missing"; exit 1; }
readelf -d $V/lib/hw/audio.primary.msm8998_s8.so | grep -q libprocessgroup.so || { echo "audio: libprocessgroup not linked"; exit 1; }
echo "audio: S8 Pie HAL stack + wrapper installed (real HAL = lib/hw/audio.primary.msm8998_s8.so)"
# fingerprint: S8 Pie bauth stack under the G9600 @3.0 service -> module/device version 2.1 -> 3.0 (the kernel driver
# accepts the S8 ioctl magic: tools/kernel/patch_et5xx_ioc_magic.py)
python3 $P/tools/patches/patch_fp_module_version.py $V/lib64/hw/fingerprint.default.so
python3 $P/tools/build/vendor_visible_check.py $V   # fails the build if a transplant needs a non-vendor-visible library

# 3) data files
grep -vE '^\s*(#|$)' $C/transplant/data.txt | while read -r f; do
  if [ -d "$S8/$f" ]; then mkdir -p $V/$f && cp -a $S8/$f/. $V/$f/; elif [ -e "$S8/$f" ]; then mkdir -p "$(dirname $V/$f)"; cp -a $S8/$f $V/$f; else echo "  (absent on S8: $f)"; fi
done

# 4) VINTF manifest: drop tablet entries replaced above, add S8 entries
python3 - "$V/etc/vintf/manifest.xml" $C/transplant <<'PY'
import sys, re, glob
path, tdir = sys.argv[1], sys.argv[2]
m = open(path).read()
add = ''.join(open(f).read() for f in sorted(glob.glob(tdir + '/*.manifest.xml')))
# every package the S8 transplants declare replaces the tablet's entry (duplicate instances break VINTF)
drop = sorted(set(re.findall(r'<name>([a-z][^<]+)</name>', add)) - {'default'})
drop += ['android.hardware.bluetooth']   # tablet QCA bt variant
def keep(block):
    n = re.search(r'<name>([^<]+)</name>', block).group(1)
    return not any(n == d or n.startswith(d + '.') for d in drop)
blocks = re.findall(r'\s*<hal format="hidl".*?</hal>', m, re.S)
for b in blocks:
    if not keep(b):
        m = m.replace(b, '')
m = m.replace('</manifest>', add + '</manifest>')
open(path, 'w').write(m)
# sanity: no package@version::interface/instance may be declared twice
import collections
inst = collections.Counter()
for hal in re.findall(r'<hal format="hidl".*?</hal>', m, re.S):
    pkg = re.search(r'<name>([^<]+)</name>', hal).group(1)
    for fq in re.findall(r'<fqname>([^<]+)</fqname>', hal):
        inst[pkg + fq] += 1
    for itf, body in re.findall(r'<interface>\s*<name>([^<]+)</name>(.*?)</interface>', hal, re.S):
        for i in re.findall(r'<instance>([^<]+)</instance>', body):
            inst[f'{pkg}::{itf}/{i}'] += 1
dups = [k for k, v in inst.items() if v > 1]
print('manifest duplicate instances:', dups or 'none')
print('manifest: removed', sum(not keep(b) for b in blocks), 'tablet entries, added', add.count('<hal '), 'S8 entries')
PY

# 5) SELinux: merged vendor cil + contexts, regenerated precompiled policy matching the G9600 system
SE=$V/etc/selinux; SYSSE=$T/g9600_root/system/etc/selinux
cat $C/sepolicy/s8_phone_hals.cil $C/sepolicy/s8_phone_hals.extra.cil >> $SE/vendor_sepolicy.cil
cat $C/sepolicy/vendor_file_contexts.add >> $SE/vendor_file_contexts
cat $C/sepolicy/vendor_hwservice_contexts.add >> $SE/vendor_hwservice_contexts
# Samsung's Q platform policy (G9600) already defines some Qualcomm vendor.* entries -> duplicates are fatal on boot
python3 $P/tools/build/dedup_contexts.py $SYSSE $SE
PROD=$T/g9600_root/system/product/etc/selinux/product_sepolicy.cil; [ -f $PROD ] || PROD=
secilc -m -M true -G -N -c 30 -o $SE/precompiled_sepolicy -f /dev/null \
  $SYSSE/plat_sepolicy.cil $SYSSE/mapping/29.0.cil $SE/plat_pub_versioned.cil $SE/vendor_sepolicy.cil $PROD
# init only uses the precompiled policy if these hashes match the system's; otherwise it compiles at boot (also fine)
cp $SYSSE/plat_sepolicy_and_mapping.sha256 $SE/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256
[ -f $T/g9600_root/system/product/etc/selinux/product_sepolicy_and_mapping.sha256 ] && \
  cp $T/g9600_root/system/product/etc/selinux/product_sepolicy_and_mapping.sha256 $SE/precompiled_sepolicy.product_sepolicy_and_mapping.sha256
echo "sepolicy: precompiled $(stat -c %s $SE/precompiled_sepolicy) bytes"

# 5b) display: the Tab S4 vendor describes a landscape tablet (configstore primary orientation 90, density 360).
#     Android 10 surfaceflinger lets ro.surface_flinger.* override configstore -> S8 portrait panel values.
#     density 640 = stock S8/S9 at 1440x2960 (360 dp wide = phone layout; 480 gave 480 dp = tablet-like layout).
sed -i -E '/^ro\.sf\.lcd_density=/d; /^ro\.sf\.init\.lcd_density=/d; /^ro\.surface_flinger\.primary_display_orientation=/d' $V/build.prop
sed -i -E '/^ro\.minui\.default_rotation=/d' $V/default.prop
cat >> $V/build.prop <<'PROPS'

# S8 (SCV36) display, replacing the Tab S4 landscape values
ro.surface_flinger.primary_display_orientation=ORIENTATION_0
ro.sf.lcd_density=640
ro.sf.init.lcd_density=640
# (ro.vendor.gpu.available_frequencies, ro.bt.bdaddr_path, ro.build.fingerprint: Q loads /vendor/build.prop with the
#  vendor_init SELinux context, which may not set freq_prop/bluetooth_prop/build_prop -> set in system build.prop by
#  installer/twrp/apply_vendor.sh instead)
PROPS
echo "display: $(grep -E 'primary_display_orientation|lcd_density' $V/build.prop | tr '\n' ' ')"
# 5c) Build.isBuildConsistent(): vendor fingerprint (Tab S4) != system fingerprint (S9) -> "There's an internal problem
#     with your device" dialog at every boot. Report the system's fingerprint from the vendor too.
SYSFP=$(grep -m1 '^ro.system.build.fingerprint=' $T/g9600_root/system/build.prop | cut -d= -f2-)
[ -n "$SYSFP" ] || SYSFP=$(grep -m1 '^ro.build.fingerprint=' $T/g9600_root/system/build.prop | cut -d= -f2-)
sed -i -E "s#^ro\.vendor\.build\.fingerprint=.*#ro.vendor.build.fingerprint=$SYSFP#" $V/build.prop
echo "fingerprint: $(grep '^ro.vendor.build.fingerprint=' $V/build.prop)"
# 5d) identity: Q derives ro.product.* (and ro.build.fingerprint) from ro.product.{product,odm,vendor,system}.* in that
#     order -> the Tab S4 vendor/odm values won (model SM-T835 = tablet UI in Samsung apps, mixed fingerprint).
#     Present the hardware's global twin SM-G9500 (dreamqltechn) and pin one fingerprint everywhere.
ODMP=$V/odm/etc/build.prop
for f in $V/build.prop $ODMP; do
  p=vendor; [ $f = $ODMP ] && p=odm
  sed -i -E "s#^ro\.product\.$p\.model=.*#ro.product.$p.model=SM-G9500#; s#^ro\.product\.$p\.name=.*#ro.product.$p.name=dreamqltezh#; s#^ro\.product\.$p\.device=.*#ro.product.$p.device=dreamqltechn#; s#^ro\.$p\.build\.fingerprint=.*#ro.$p.build.fingerprint=$SYSFP#" $f
done
sed -i -E '/^ro\.build\.fingerprint=/d' $V/build.prop   # (build_prop: set from system build.prop, see above)
echo "identity: $(grep -hE '^ro\.product\.(vendor|odm)\.(model|device)=' $V/build.prop $ODMP | tr '\n' ' ')"

# 5f) Samsung feature list: on Q it lives in /vendor/etc -> One UI was reading the Tab S4 tablet list (device name
#     "Galaxy Tab S4", no SupportForceTouch = no pressure home key, no AOD config). Use the S9 (G9600) list that
#     matches the system, adjusted for S8 hardware (single speaker, name).
FF=$V/etc/floating_feature.xml
cp $T/g9600_vendor/etc/floating_feature.xml $FF
sed -i -E 's#(<SEC_FLOATING_FEATURE_SETTINGS_CONFIG_BRAND_NAME>)[^<]*#\1Galaxy S8#;
           s#(<SEC_FLOATING_FEATURE_AUDIO_SUPPORT_DUAL_SPEAKER>)[^<]*#\1FALSE#;
           s#,spk_stereo##;
           /SEC_FLOATING_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL/d' $FF
# (torch level slider stays on: SEC_FLOATING_FEATURE_CAMERA_SUPPORT_TORCH_BRIGHTNESS_LEVEL TRUE from the G9600 list;
#  the strength call is served by the camera.msm8998.so torch wrapper, see step 2b)
# S8 notification LED (stock SCV36 TRUE; the G9600 list lacks it -> no "LED indicator" setting)
grep -q SETTINGS_SUPPORT_LED_INDICATOR $FF || sed -i 's#</SecFloatingFeatureSet>#    <SEC_FLOATING_FEATURE_SETTINGS_SUPPORT_LED_INDICATOR>TRUE</SEC_FLOATING_FEATURE_SETTINGS_SUPPORT_LED_INDICATOR>\n</SecFloatingFeatureSet>#' $FF
# (no DYN_RESOLUTION_CONTROL: One UI would default to FHD+ via display_size_forced, which the T835 composer shows
#  unscaled in the top-left 75% of the WQHD+ panel while touch maps the full panel -> stay at native 1440x2960)
echo "features: $(grep -oE 'BRAND_NAME>[^<]*|SupportForceTouch|AOD_ITEM>[^<]*|DUAL_SPEAKER>[^<]*' $FF | tr '\n' ' ')"

# 5e) audio: the S8/T835 _sec policy has one "Bt Sco All" port (AUDIO_DEVICE_OUT_ALL_SCO); Samsung's Q audiopolicy
#     aborts on it ("devicePort included BT SCO ALL") -> split into the three SCO sinks like the S9 Q vendor.
python3 - $V/etc/audio_policy_configuration_sec.xml <<'PY'
import re, sys
f = sys.argv[1]; s = open(f).read()
port = re.search(r'( *)<devicePort tagName="Bt Sco All" role="sink" type="AUDIO_DEVICE_OUT_ALL_SCO">\n(.*?)</devicePort>\n', s, re.S)
if port:
    ind, body = port.group(1), port.group(2)
    new = ''.join(f'{ind}<devicePort tagName="{n}" type="{t}" role="sink">\n{body}{ind}</devicePort>\n'
                  for n, t in (('BT SCO', 'AUDIO_DEVICE_OUT_BLUETOOTH_SCO'), ('BT SCO Headset', 'AUDIO_DEVICE_OUT_BLUETOOTH_SCO_HEADSET'),
                               ('BT SCO Car Kit', 'AUDIO_DEVICE_OUT_BLUETOOTH_SCO_CARKIT')))
    s = s.replace(port.group(0), new)
    route = re.search(r'( *)<route type="mix" sink="Bt Sco All"\s*\n\s*sources="([^"]*)"/>\n', s)
    ri, src = route.group(1), route.group(2)
    s = s.replace(route.group(0), ''.join(f'{ri}<route type="mix" sink="{n}"\n{ri}       sources="{src}"/>\n'
                                          for n in ('BT SCO', 'BT SCO Headset', 'BT SCO Car Kit')))
    open(f, 'w').write(s)
print('audio: Bt Sco All split' if port else 'audio: no Bt Sco All port', '| remaining refs:', s.count('Bt Sco All'))
PY
# 5f) video recording: Samsung's Q audio policy engine routes AUDIO_SOURCE_CAMCORDER to AUDIO_DEVICE_IN_2MIC
#     ("Built-In 2 Mic", attached in the S9 Q vendor). The S8 Pie policy has no such port -> "getInputForAttr() could
#     not find device for source 5" -> MediaRecorder start failed in every app. Add it like the G9600 config (same
#     profile as the back mic; the S8 HAL has camcorder-stereo/main/sub-mic paths).
python3 - $V/etc/audio_policy_configuration_sec.xml <<'PY'
import re, sys
f = sys.argv[1]; s = open(f).read()
if 'AUDIO_DEVICE_IN_2MIC' not in s:
    s, n1 = re.subn(r'(\n( *)<item>Built-In Back Mic</item>\n)', r'\1\2<item>Built-In 2 Mic</item>\n', s, count=1)
    m = re.search(r'( *)<devicePort tagName="Built-In Back Mic" type="AUDIO_DEVICE_IN_BACK_MIC" role="source">(.*?)</devicePort>\n', s, re.S)
    s = s.replace(m.group(0), m.group(0) + f'{m.group(1)}<devicePort tagName="Built-In 2 Mic" type="AUDIO_DEVICE_IN_2MIC" role="source">{m.group(2)}</devicePort>\n', 1)
    s, n2 = re.subn(r'(<route type="mix" sink="primary-in"\s*sources="Built-In Mic,Built-In Back Mic,)', r'\1Built-In 2 Mic,', s, count=1)
    assert n1 == 1 and n2 == 1, (n1, n2)
    open(f, 'w').write(s)
print('audio: Built-In 2 Mic (camcorder) present')
PY

# 6) fstab: no forced encryption (spare phone; FDE on this hybrid is untested)
sed -i -E 's/,?forceencrypt=footer//' $V/etc/fstab.qcom
grep -q forceencrypt $V/etc/fstab.qcom && { echo "forceencrypt still present"; exit 1; } || echo "fstab: encryption off"

# 7) ueventd: S8 phone device nodes
cat >> $V/ueventd.rc <<'EOF'

# S8 (SCV36) phone hardware added for the One UI 2 port
/dev/sec-nfc              0660   nfc        nfc
/dev/sec-nfc-fn           0660   nfc        nfc
/dev/esfp0                0660   system     system
/dev/vfsspi               0660   system     system
/dev/wlan                 0660   wifi       wifi
/dev/ttyHS0               0660   bluetooth  bluetooth
/dev/btlock               0600   bluetooth  bluetooth
# Broadcom BT power switch (DT /soc/bt_driver; bt_upio writes rfkill0/state as the bluetooth user).
# Q ueventd matches wildcards per path segment (FNM_PATHNAME) -> exact depth
/sys/devices/soc/soc:bt_driver/rfkill/rfkill*   state   0660   bluetooth  bluetooth
/sys/devices/soc/soc:bt_driver/rfkill/rfkill*   type    0440   bluetooth  bluetooth
EOF

# 7b) file capabilities: a real build sets security.capability on vendor binaries from etc/fs_config_files
#     (e.g. NET_BIND_SERVICE for pd-mapper/pm-service/sensors.qti - the msm IPC router refuses bind() without it,
#     modem PIL then fails -> TZ XPU violation reset). The TWRP push only restores SELinux labels, so grant the same
#     capabilities through init instead (ambient caps for non-root services).
python3 - $V <<'PY'
import os, re, struct, sys
V = sys.argv[1]
CAPS = {0:'CHOWN',1:'DAC_OVERRIDE',2:'DAC_READ_SEARCH',3:'FOWNER',4:'FSETID',5:'KILL',6:'SETGID',7:'SETUID',8:'SETPCAP',
        10:'NET_BIND_SERVICE',11:'NET_BROADCAST',12:'NET_ADMIN',13:'NET_RAW',14:'IPC_LOCK',21:'SYS_ADMIN',23:'SYS_NICE',
        24:'SYS_RESOURCE',25:'SYS_TIME',27:'MKNOD',30:'AUDIT_WRITE',33:'AUDIT_CONTROL',34:'MAC_ADMIN',35:'WAKE_ALARM',
        36:'BLOCK_SUSPEND'}
d = open(f'{V}/etc/fs_config_files', 'rb').read()
want, o = {}, 0
while o + 16 <= len(d):
    ln, mode, uid, gid, caps = struct.unpack_from('<HHHHQ', d, o)
    if ln < 16: break
    path = d[o+16:o+ln].split(b'\0')[0].decode(); o += ln
    if caps and path.startswith(('vendor/bin/', 'system/vendor/bin/')):
        want['/vendor/' + path.split('vendor/', 1)[1]] = ' '.join(CAPS[i] for i in range(64) if caps >> i & 1)
added = []
for root, _, files in os.walk(f'{V}/etc/init'):
    for fn in files:
        if not fn.endswith('.rc'): continue
        rc = os.path.join(root, fn); lines = open(rc, errors='replace').read().split('\n'); out = []; i = 0
        while i < len(lines):
            m = re.match(r'\s*service\s+(\S+)\s+(\S+)', lines[i])
            if not m:
                out.append(lines[i]); i += 1; continue
            j = i + 1
            while j < len(lines) and not re.match(r'\s*(service|on|import)\s', lines[j]): j += 1
            block = lines[i:j]; exe = re.sub(r'^/system/vendor/', '/vendor/', m.group(2))
            user = next((l.split()[1] for l in block if l.strip().startswith('user ')), 'root')
            if exe in want and user != 'root' and not any(l.strip().startswith('capabilities') for l in block):
                block.insert(1, '    capabilities ' + want[exe]); added.append(f'{m.group(1)}({want[exe]})')
            out += block; i = j
        open(rc, 'w').write('\n'.join(out))
print('capabilities added:', ', '.join(added) or 'none')
for exe in want:
    if not any(exe.split('/')[-1] in a for a in added): print('  (not init-started as non-root / already set:', exe, ')')
PY

# 7c) USB: the One UI phone framework uses sys.usb.config=mtp,conn_gadget[,adb] (Samsung phones); the tablet rc has no
#     trigger for it -> gadget never bound (no USB mode dialog, no adb). Take the S8 Pie blocks for those configs.
python3 - $S8/etc/init/hw/init.msm.usb.configfs.rc $V/etc/init/hw/init.msm.usb.configfs.rc <<'PY'
import re, sys
src, dst = sys.argv[1:]
s = open(src).read(); d = open(dst).read()
blocks = re.findall(r'^on property:[^\n]*sys\.usb\.config=mtp,conn_gadget[^\n]*\n(?:(?!on )[^\n]*\n)*', s, re.M)
new = [b for b in blocks if b.split('\n')[0] not in d]
if new:
    open(dst, 'a').write('\n# S8 (Samsung phone) USB configs, added for the One UI 2 port\n' + '\n'.join(b.rstrip() + '\n' for b in new))
print('usb: added', len(new), 'conn_gadget trigger blocks')
PY

# 7d) S8 Broadcom bluetooth setup (S8 Pie init.qcom.rc "on boot"): the T835 rc chmods rfkill0/state but never gives
#     it to the bluetooth user -> bt_upio "open(/sys/class/rfkill/rfkill0/state) for write failed: Permission denied"
cat > $V/etc/init/s8_bluetooth.rc <<'EOF'
# S8 (SCV36) Broadcom BCM4361 bluetooth (One UI 2 port)
on boot
    mkdir /efs/bluetooth 0770 system bluetooth
    chown system bluetooth /efs/bluetooth
    chown system bluetooth /efs/bluetooth/bt_addr
    chmod 0770 /efs/bluetooth
    chmod 0640 /efs/bluetooth/bt_addr
    setprop ro.bt.bdaddr_path "/efs/bluetooth/bt_addr"
    chown bluetooth bluetooth /dev/ttyHS0
    chmod 0660 /dev/ttyHS0
    chown bluetooth bluetooth /sys/class/rfkill/rfkill0/state
    chown bluetooth bluetooth /sys/class/rfkill/rfkill0/type
    chmod 0660 /sys/class/rfkill/rfkill0/state
    chown bluetooth bluetooth /proc/bluetooth/sleep/proto
    chown bluetooth bluetooth /proc/bluetooth/sleep/lpm
    chown bluetooth bluetooth /proc/bluetooth/sleep/btwrite
    chmod 0660 /proc/bluetooth/sleep/lpm
    chmod 0220 /proc/bluetooth/sleep/btwrite
    chmod 0660 /proc/bluetooth/sleep/proto
    chown bluetooth bluetooth /dev/btlock
    chmod 0600 /dev/btlock
EOF

# 7c2) restart loops seen in the boot logs:
#   - PROCA (Samsung process authenticator, vendor.samsung.hardware.security.proca@2.0): its TA session fails because
#     FIVE/PROCA are off in our kernel -> "PA daemon has not sent the config", respawn every 5 s (318 QSEECom errors
#     per 4 min). Not started, and not declared, so clients get "not present" at once instead of waiting.
#   - izat.conf (T835) launches xtwifi-inet-agent, which the vendor does not ship -> execvp EACCES + restart loop.
sed -i -E 's/^(\s*)start proca$/\1# start proca   (S8 port: PROCA\/FIVE off in the kernel)/' $V/etc/init/pa_daemon_qsee.rc
python3 - $V/etc/vintf/manifest.xml <<'PY'
import re, sys
p = sys.argv[1]; m = open(p).read()
blocks = [b for b in re.findall(r'\s*<hal format="hidl">.*?</hal>', m, re.S) if '<name>vendor.samsung.hardware.security.proca</name>' in b]
for b in blocks: m = m.replace(b, '')
open(p, 'w').write(m); print('proca: removed', len(blocks), 'manifest entr' + ('y' if len(blocks) == 1 else 'ies'))
PY
python3 - $V/etc/izat.conf <<'PY'
import sys
p = sys.argv[1]; lines = open(p).read().split('\n'); cur = None; n = 0
for i, l in enumerate(lines):
    if l.startswith('PROCESS_NAME='): cur = l.split('=', 1)[1]
    if l.startswith('PROCESS_STATE=') and cur in ('xtwifi-inet-agent', 'xtwifi-client') and l != 'PROCESS_STATE=DISABLED':
        lines[i] = 'PROCESS_STATE=DISABLED'; n += 1
open(p, 'w').write('\n'.join(lines)); print('izat: disabled', n, 'missing xtwifi process(es)')
PY
grep -n 'proca' $V/etc/init/pa_daemon_qsee.rc | tail -1

# 7c3) Broadcom wifi: S8 wifi_brcm.rc (data.txt) only chowns firmware_path; macloader also writes nvram_path, and the
#      dhd module params are not uevent-relabelled -> restorecon to sysfs_ss_writable (vendor_file_contexts)
cat >> $V/etc/init/wifi_brcm.rc <<'EOF'

# S8 port: macloader (user wifi) writes both dhd path params
on boot
    restorecon_recursive /sys/module/dhd/parameters
    chown wifi root /sys/module/dhd/parameters/nvram_path
    chmod 0664 /sys/module/dhd/parameters/firmware_path
    chmod 0664 /sys/module/dhd/parameters/nvram_path
EOF

# 7c4) SSRM "Fails to parse policy XML": static RRO replacing SDHMS raw/siop_starqlte_sdm845 with the same S9 phone
#      policy remapped to S8 CPU/GPU steps (tools/build/build_sdhms_overlay.sh)
bash $P/tools/build/build_sdhms_overlay.sh >/dev/null
mkdir -p $V/overlay/SdhmsS8Overlay
cp $C/overlay/out/SdhmsS8Overlay.apk $V/overlay/SdhmsS8Overlay/SdhmsS8Overlay.apk
echo "ssrm: SdhmsS8Overlay.apk in vendor/overlay"
# AOD brightness: framework config_aodBrightnessValues -> 2 levels = S8 AOD scheme (HLPM 2/60 nit via alpm 2/4,
# light-sensor auto) that the S8 panel driver implements (tools/build/build_framework_overlay.sh)
bash $P/tools/build/build_framework_overlay.sh >/dev/null
mkdir -p $V/overlay/FrameworkS8Overlay
cp $C/overlay/out/FrameworkS8Overlay.apk $V/overlay/FrameworkS8Overlay/FrameworkS8Overlay.apk
echo "aod: FrameworkS8Overlay.apk in vendor/overlay"
# Iris: S8 phone UI for the stock T835 SecIrisService (tools/build/build_iris_overlay.sh, run by stage_iris_t835.sh)
if [ -f $C/overlay/out/IrisS8Overlay.apk ]; then
  mkdir -p $V/overlay/IrisS8Overlay
  cp $C/overlay/out/IrisS8Overlay.apk $V/overlay/IrisS8Overlay/IrisS8Overlay.apk
  echo "iris: IrisS8Overlay.apk in vendor/overlay"
fi

# 7c5) device rc: init.target.rc imports init.${ro.product.device}.rc - since 5d made the device "dreamqltechn" the
#      Tab S4 init.gts4llte.rc is never imported -> no irisd (iris), faced (face unlock), sswap (zram), /dev/radio0
#      perms (FM), /efs/carrier, freezer. Always-loaded S8 version (S9 init.starqlte.rc + T835, S8 hardware only).
cat > $V/etc/init/s8_device.rc <<'EOF'
# S8 (SCV36) device init for the One UI 2 port (replaces init.gts4llte.rc / init.starqlte.rc)
on boot
    write /proc/sys/vm/swappiness 160
    # notification/charging LED (SM5720 RGB): stock SCV36 ramdisk init.rc lines - the Q system init.rc lacks them ->
    # root-owned nodes, lights HAL (user system) got EACCES on led_pattern
    chown system system /sys/class/sec/led/led_r
    chown system system /sys/class/sec/led/led_g
    chown system system /sys/class/sec/led/led_b
    chown system system /sys/class/sec/led/led_pattern
    chown system system /sys/class/sec/led/led_blink
    chown system system /sys/class/sec/led/led_lowpower
    chown system system /sys/class/sec/led/led_brightness
    chown system system /sys/class/sec/led/delay_on
    chown system system /sys/class/sec/led/delay_off
    chown system system /sys/class/sec/led/blink
    chmod 0660 /sys/class/sec/led/led_pattern
    chmod 0660 /sys/class/sec/led/led_blink
    chmod 0660 /sys/class/sec/led/led_lowpower

on fs
    mkdir /efs/mb_po 0700 system system

# iris (S9 Q irisd + IrisTlc; S8 iris camera S5K5E6 + iris TA) and face unlock
service irisd /system/bin/irisd
    class late_start
    user system
    group system

service faced /system/bin/faced
    class late_start
    user system
    group system

service swapon /sbin/sswap -s -f 2048
    class core
    user root
    group root
    seclabel u:r:sswap:s0
    oneshot

on post-fs
    mkdir /efs/carrier 0755 system system

on post-fs-data
    # FM radio (Richwave RTC6213N, kernel RADIO_RTC6213N)
    chown system audio /dev/radio0
    chmod 0660 /dev/radio0
    # earjack / Maxim speaker amp calibration (same blocks as the S9)
    chown system radio /sys/class/audio/earjack/key_state
    chown system radio /sys/class/audio/earjack/mic_adc
    chown system radio /sys/class/audio/earjack/select_jack
    chown system radio /sys/class/audio/earjack/state
    mkdir /efs/maxim 0770 audioserver audio
    chown audioserver audio /efs/maxim/temp_cal
    chown audioserver audio /efs/maxim/rdc_cal
    chmod 0660 /efs/maxim/temp_cal
    chmod 0660 /efs/maxim/rdc_cal
    mkdir /data/firmware 0770 audioserver system
    # olaf dex2oat freezer
    mkdir /dev/freezer
    mount cgroup none /dev/freezer freezer
    mkdir /dev/freezer/olaf
    write /dev/freezer/olaf/freezer.state THAWED
    chown system system /dev/freezer/olaf
    chown system system /dev/freezer/olaf/tasks
    chown system system /dev/freezer/olaf/cgroup.procs
    chown system system /dev/freezer/olaf/freezer.state
    chmod 0644 /dev/freezer/olaf/tasks
    chmod 0644 /dev/freezer/olaf/cgroup.procs
    chmod 0644 /dev/freezer/olaf/freezer.state
EOF

# 7d2) fingerprint (G9600 fingerprint@3.0 HAL + S8 Pie bauth on the S8 sensor): data dirs + device/sysfs owners from
#      the S8/S9 init.qcom.rc (the T835 tablet has no fingerprint sensor, so its rc never sets them up).
#      This SCV36 has a Synaptics NAMSAN (kernel vfs8xxx -> /dev/vfsspi); /dev/esfp0 kept for Egis-sensor units.
cat > $V/etc/init/s8_fingerprint.rc <<'EOF'
# S8 (SCV36) fingerprint (Synaptics NAMSAN /dev/vfsspi or Egis /dev/esfp0) for the G9600 fingerprint@3.0 HAL
on post-fs-data
    mkdir /data/vendor/biometrics 0770 system system
    mkdir /data/vendor/fpSnrTest 0770 system system

on boot
    chmod 0660 /dev/vfsspi
    chown system system /dev/vfsspi
    chmod 0660 /dev/esfp0
    chown system system /dev/esfp0
    chown system radio /sys/class/fingerprint/fingerprint/type_check
    chown system radio /sys/class/fingerprint/fingerprint/name
    chown system radio /sys/class/fingerprint/fingerprint/vendor
    chown system radio /sys/class/fingerprint/fingerprint/adm
    chown system radio /sys/class/fingerprint/fingerprint/bfs_values
EOF

# 7e) NFC: G9600 Q S.LSI HAL (nfc group) driving the S8 SEN82AB chip: G9600 config format, S8 clock/firmware/rfreg
G96C=$T/g9600_vendor/etc/libnfc-sec-vendor.conf
python3 - $G96C $S8/etc/libnfc-sec-vendor.conf $V/etc/libnfc-sec-vendor.conf <<'PY'
import re, sys
g, s8, out = sys.argv[1:]
txt = open(g).read(); s8txt = open(s8).read()
def s8val(k):
    m = re.search(r'^' + k + r'=(.*)$', s8txt, re.M); return m.group(1) if m else None
NL = chr(10)
clk = NL.join(f'{k}={s8val(k)}' for k in ('FW_CFG_CLK_TYPE', 'FW_CFG_CLK_SPEED', 'FW_CFG_CLK_REQ') if s8val(k))
txt = re.sub(r'^FW_CFG_CLK_SPEED=.*$', lambda m: clk, txt, flags=re.M)
for k, v in (('FW_DIR_PATH', '"/vendor/firmware/"'), ('FW_FILE_NAME', '"sec_senn82ab_firmware.bin"'),
             ('RF_DIR_PATH', '"/vendor/etc/"'), ('RF_FILE_NAME', '"sec_senn82ab_rfreg.bin"')):
    txt = re.sub(r'^' + k + r'=.*$', f'{k}={v}', txt, flags=re.M)
if s8val('WAKEUP_DELAY') and 'WAKEUP_DELAY' not in txt:
    txt += NL + f'WAKEUP_DELAY={s8val("WAKEUP_DELAY")}' + NL
open(out, 'w').write(txt)
print('nfc conf:', ' '.join(l for l in txt.splitlines() if re.match(r'(FW_|RF_|WAKEUP)', l)))
PY
ls -la $V/firmware/sec_senn82ab_firmware.bin $V/etc/sec_senn82ab_rfreg.bin $V/bin/hw/sec.android.hardware.nfc@1.2-service

# 7f) OEM AIDs the G9600 system apps run as (sharedUserId -> vendor passwd/group name -> vendor_seapp_contexts):
#     missing on the T835 -> uid 5022 has no name -> "selinux_android_setcontext(5022, ...ipsgeofence) failed",
#     Zygote abort of com.samsung.android.ipsgeofence (+ advmodem 5017, felicalock 5504 - FeliCa lock on the JPN S8)
for f in passwd group; do
  grep -E '^vendor_(ipsgeofence|advmodem|felicalock):' $T/g9600_vendor/etc/$f | while IFS= read -r l; do
    grep -qF "${l%%:*}:" $V/etc/$f || { echo "$l" >> $V/etc/$f; echo "  $f += ${l%%:*}"; }
  done
done

# 8) verify every transplanted binary gets a non-default SELinux label
python3 - $V $SE/vendor_file_contexts $C/transplant <<'PY'
import sys, re, glob, os
V, fc, tdir = sys.argv[1:]
rules = []
for l in open(fc):
    p = l.split()
    if len(p) >= 2 and p[0].startswith('/'):
        rules.append((re.compile('^' + p[0] + '$'), p[-1]))
bad = 0
for g in glob.glob(tdir + '/*.txt'):
    if g.endswith('data.txt'): continue
    for f in open(g).read().split():
        if not f.startswith('bin/'): continue
        path = '/vendor/' + f
        lab = [l for r, l in rules if r.match(path)]
        label = lab[-1] if lab else 'NONE'
        if label == 'NONE' or 'vendor_file:' in label:
            bad += 1
        print(f'  {label:45} {path}')
print('unlabeled service binaries:', bad)
PY
echo "vendor ready: $(du -sm $V | cut -f1) MiB at $V"
