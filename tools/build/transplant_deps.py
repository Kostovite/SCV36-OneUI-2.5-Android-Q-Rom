#!/usr/bin/env python3
"""WSL: for S8 Pie vendor HAL services, list everything needed to transplant them into the T835 Q vendor:
init .rc files, VINTF manifest <hal> entries, and NEEDED shared libraries missing from the T835 vendor + G9600 system
(resolved recursively with readelf). Writes config/transplant/<name>.txt file lists.
usage: python3 tools/build/transplant_deps.py"""
import glob, os, re, subprocess, xml.etree.ElementTree as ET
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

T = os.path.expanduser('~/s8rom/trees')
S8 = T + '/s8_vendor/vendor'          # S8 Pie vendor (from system/vendor)
TV = T + '/t835_vendor'               # T835 Q vendor
SYS = T + '/g9600_root/system'        # G9600 Q system (provides LLNDK/VNDK-29 + system libs)
S8SYS = T + '/s8_system'              # S8 Pie /system (Pie keeps vendor.samsung.* HIDL interface libs here)
G96V = T + '/g9600_vendor'            # S9 (G9600) Q vendor: donor for HALs whose S8 Pie version the Q framework rejects
# group -> (donor vendor tree, prefix written to the file list); default = S8 Pie vendor, no prefix
DONOR = {'nfc': (G96V, 'G9600:'), 'fingerprint': (G96V, 'G9600:')}
BIONIC = {'libc.so', 'libdl.so', 'libm.so'}  # Q: /apex/com.android.runtime/*/bionic
OUT = os.path.join(REPO, 'config/transplant')
os.makedirs(OUT, exist_ok=True)

SERVICES = {
    # One UI 2 FingerprintService only asks for ISehBiometricsFingerprint@3.0 (FEATURE_JDM_HAL false) -> the S8 Pie
    # ISecBiometricsFingerprint@2.1 HAL is never used. G9600 libbauthserver drives the same Egis ET510 on /dev/esfp0
    # (kernel: tools/kernel/patch_et5xx_fps_common.py). Risk: S8 Pie fingerprint TA vs the Q bauth TZ client.
    'fingerprint': ['vendor.samsung.hardware.biometrics.fingerprint@3.0-service'],
    # G9600 Q HAL (sec.android.hardware.nfc@1.2: INfc 1.2 + ISehNfc 2.0): the G9600 NfcNci calls ISehNfc 2.0 ("Hal is
    # nullptr", "fail nfa enable" with the S8 Pie ISecNfc 1.1 HAL). Chip-generic S.LSI HAL; S8 SEN82AB firmware/rfreg
    # come from data.txt and the config is written by build_vendor.sh
    'nfc': ['sec.android.hardware.nfc@1.2-service'],
    # radio configsvc: not transplanted - Samsung Q uses /vendor/bin/secril_config_svc (T835 init.vendor.rilcommon.rc)
    # Broadcom BCM4361 on the S8 vs Qualcomm WCN on the Tab S4: whole wifi/bt stack comes from the S8
    # wifi: keep the T835 Q wifi HAL services/supplicant/hostapd (match the G9600 framework, Q BoringSSL);
    # only the Broadcom legacy HAL library comes from the S8 (EXTRA_ELF below).
    # Wi-Fi HAL service itself = G9600 (config/transplant/wifi.txt): the T835 (Qualcomm) one sets the MAC with iface
    # down/up -> bcmdhd powers the chip off on wlan0 down -> P2P device lost (Wi-Fi Direct / Quick Share broken). The
    # Broadcom G9600 and S8 Pie HALs change the MAC with the interface up.
    'wifi': [],
    'bluetooth': ['android.hardware.bluetooth@1.0-service'],
    # TrustZone-backed HALs must match the S8's own TZ apps (Tab S4 keymaster -> qseecom -22, keystore aborts)
    'tz': ['android.hardware.keymaster@3.0-service', 'android.hardware.gatekeeper@1.0-service'],
    # S8 sensor stack matching the S8 ADSP sensor firmware (T835 HAL lists the sensors but never delivers Samsung
    # SemContext auto-rotation: WindowOrientationListener getProposedRotation -1)
    'sensors': ['android.hardware.sensors@1.0-service'],
    # camera: the T835 Samsung provider (ISehCameraProvider@3.0, what the G9600 cameraserver wants) stays; it loads
    # camera.msm8998.so through the plain camera_module_t interface and runs mm-camera in-process. The T835 mm-camera
    # read the S8 rear module EEPROM and asked for libmmcamera_s5k2l2sa.so (absent) -> 0 cameras. Whole S8 Pie
    # QCamera2 HAL + mm-camera (sensor/chromatix/actuator/eeprom/companion/3A) instead; kernel msm_camera ABI = Pie+16 lines.
    'camera': [],
}
# dlopen'ed implementations (not visible to readelf) resolved like binaries
EXTRA_ELF = {
    # macloader: writes /data/vendor/conn/.cid.info (Murata/Semco module id) that bcmdhd reads to pick the nvram
    'wifi': ['lib64/libwifi-hal.so', 'bin/hw/macloader'],
    # passthrough impl dlopen'ed by the S8 bluetooth service; the T835 one is Qualcomm (ttyHS0 SoC) -> Broadcom needs S8's
    'bluetooth': ['lib64/hw/android.hardware.bluetooth@1.0-impl.so'],
    # G9600 vendor copy of the ISehNfc 2.0 interface lib (the system copy is not visible to vendor processes)
    'nfc': ['lib64/vendor.samsung.hardware.nfc@2.0.so'],
    # boot 17: G9600 libbauthserver + S8 TA -> "read SNSR Type success but file has wrong data", common_prepare fail
    # x6, "FP Sensor is out of order" (also with the LDO-reset kernel). The S8 module/libbauthserver export the same
    # ss_fingerprint_* API (the G9600 one only adds Goodix gf* support) -> G9600 @3.0 service + the S8 Pie bauth stack
    # that was built against the S8 fingerprint TA (S8V: = take from the S8 Pie vendor in a donor group)
    'fingerprint': ['lib64/vendor.samsung.hardware.biometrics.fingerprint@3.0.so', 'S8V:lib64/hw/fingerprint.default.so'],
    'sensors': ['lib64/hw/android.hardware.sensors@1.0-impl.so', 'lib64/sensors.ssc.so', 'lib64/sensors.grip.so',
                'lib64/libsensor1.so', 'lib64/libsensor_reg.so', 'bin/sensors.qti'],
    'tz': ['lib64/hw/android.hardware.keymaster@3.0-impl.so', 'lib64/hw/android.hardware.gatekeeper@1.0-impl.so',
           'lib64/hw/keystore.mdfpp.so', 'lib64/hw/keystore.msm8998.so',
           'lib64/hw/gatekeeper.mdfpp.so', 'lib64/hw/gatekeeper.msm8998.so',
           # Pie VNDK keymaster libs (Q changed Create*Operation signatures); only the keymaster stack uses them
           'SYSTEM:lib64/libkeymaster_portable.so', 'SYSTEM:lib64/libkeymaster_messages.so',
           # boot 6: keymaster@3.0-service exit 1 -> keystore null -> system_server NPE loop; the Pie impl still
           # pulled the Q VNDK-29 soft keymaster pair, so the whole keymaster stack is now Pie
           'SYSTEM:lib64/libsoftkeymasterdevice.so', 'SYSTEM:lib64/libpuresoftkeymasterdevice.so'],
    'camera': ['lib/hw/camera.msm8998.so', 'lib/libmmcamera*.so', 'lib/*chromatix*.so', 'lib/libactuator_*.so',
               'lib/*.camera.samsung.so', 'lib/libqomx_*.so', 'lib/libmmjpeg*.so', 'lib/libmmqjpeg*.so',
               'lib/libjpegdhw.so', 'lib/libjpegehw.so',
               # Samsung 3A per camera module, loaded by name from the EEPROM id (hwinfo_make_3a_name ->
               # F12QS_libTsAe.so ...): "module_sensor_load_external_libs: failed: loading AEC library"
               'lib/*libTs*.so',
               # boot 17: the HAL still ran the T835 copies of its Samsung plugin host (libuniapi/libuniplugin, NEEDED
               # by camera.msm8998.so), PMIC flash/torch lib, remosaic daemon and JPEG DMA -> S8's (Tab S4 has
               # another camera/flash). Plugins the S8 uniplugin dlopens: only these two exist on the S8
               'lib/libuniapi.so', 'lib64/libuniapi.so', 'lib/libuniplugin.so', 'lib64/libuniplugin.so',
               'lib/libflash_pmic.so', 'lib/libremosaic_daemon.so', 'lib/libjpegdmahw.so',
               'lib/libdejagging_interface.so', 'lib/libIDDQD_interface.so',
               # their libstdc++ (bionic new/delete shim) is not vendor-visible on Q (not LLNDK) -> vendor copy
               'SYSTEM:lib/libstdc++.so'],
    # (pd-mapper / pm-service aborts were missing file capabilities, not a version mismatch: the T835 ones stay,
    #  see build_vendor.sh step 7b)
}
# extra VINTF packages a transplanted service also registers (the S8 nfc service serves ISecNfc AND the standard
# INfc; the G9600 NFC app needs INfc -> SIGSEGV loop in NfcAdaptation without the manifest entry)
EXTRA_HAL = {'nfc': ['android.hardware.nfc'], 'fingerprint': ['android.hardware.biometrics.fingerprint']}
# groups whose every vendor library is taken from the S8 when the S8 has it (not only when the T835 lacks it)
PREFER_S8 = {'tz', 'sensors'}
# groups that take only libraries matching a pattern from the S8 (the rest of their deps: T835/Q when present).
# camera: 32-bit GPU/graphics/media libs (libOpenCL, libadreno_utils, libqdMetaData, libc2d30, gralloc...) are shared
# with every 32-bit app and the T835 Q graphics stack -> never replaced
PREFER_S8_RE = {'camera': re.compile(r'(?i)(mmcamera|chromatix|actuator|qomx|mmjpeg|mmqjpeg|jpeg[de]hw|camera|imglib|'
                                     r'eztune|faceproc|companion|eeprom|dualcam|bokeh|qcamera|ubifocus|stillmore|'
                                     r'seemore|optizoom|trueportrait|chromaflash|clearsight|fdconfig|scveCommon|'
                                     r'fastcvopt|libcvface|mmlib|is_|q3a|stats|tintless|libTs|uniapi|uniplugin|'
                                     r'flash_pmic|remosaic|jpegdma|dejagging_interface|IDDQD_interface)')}
# shared vendor libraries used by many other T835 services: never replaced, even in PREFER_S8 groups
SHARED_KEEP_T835 = {'libcrypto.so', 'libssl.so', 'libQSEEComAPI.so', 'libdiag.so', 'libdrmfs.so', 'libdrmutils.so',
                    # Qualcomm QMI / modem plumbing shared with RIL, IMS, data (4G works with the T835 copies)
                    'libmdmdetect.so', 'libdsutils.so', 'libidl.so', 'libsdsprpc.so', 'libadsprpc.so', 'libcdsprpc.so'}
SHARED_KEEP_T835_PREFIX = ('libqmi',)
# same file name exists in the T835 vendor but is built for the Qualcomm radio -> always take (and replace with) the S8 one
FORCE_S8 = {'libwifi-hal.so', 'libbt-vendor.so', 'libwpa_client.so', 'libkeystore-wifi-hidl.so',
            'libkeystore-engine-wifi-hidl.so'}


def needed(path):
    try:
        out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True).stdout
    except FileNotFoundError:
        raise SystemExit('readelf missing: apt install binutils')
    return re.findall(r'\(NEEDED\)\s+Shared library: \[(.+?)\]', out)


SRC = S8   # donor tree of the group being resolved


def present(lib, bits, prefer_s8=False):
    if lib in BIONIC:
        return True
    if lib in FORCE_S8:
        return False
    d0 = 'lib64' if bits == 64 else 'lib'
    if hasattr(prefer_s8, 'search'):
        prefer_s8 = bool(prefer_s8.search(lib))
    if prefer_s8 and lib not in SHARED_KEEP_T835 and not lib.startswith(SHARED_KEEP_T835_PREFIX) and (os.path.exists(f'{SRC}/{d0}/{lib}') or os.path.exists(f'{SRC}/{d0}/hw/{lib}')):
        return False
    d = 'lib64' if bits == 64 else 'lib'
    for root in (f'{TV}/{d}', f'{TV}/{d}/hw', f'{SYS}/{d}', f'{SYS}/{d}/vndk-29', f'{SYS}/{d}/vndk-sp-29'):
        if os.path.exists(f'{root}/{lib}'):
            return True
    # libs in flattened APEX (e.g. libc++ / runtime) count as present
    for apex in os.listdir(f'{SYS}/apex'):
        if os.path.exists(f'{SYS}/apex/{apex}/{d}/{lib}'):
            return True
    return False


def resolve(binary, prefer_s8=False):
    bits = 64 if 'ELF 64' in subprocess.run(['file', '-L', binary], capture_output=True, text=True).stdout else 32
    d = 'lib64' if bits == 64 else 'lib'
    todo, seen, missing, unresolved = needed(binary), set(), [], []
    while todo:
        lib = todo.pop()
        if lib in seen:
            continue
        seen.add(lib)
        if present(lib, bits, prefer_s8):
            continue
        cands = (f'{SRC}/{d}/{lib}', f'{SRC}/{d}/hw/{lib}') + ((f'{S8SYS}/{d}/{lib}',) if SRC == S8 else ())
        for cand in cands:
            if os.path.exists(cand):
                missing.append(cand)
                todo += needed(cand)
                break
        else:
            unresolved.append(lib)
    return missing, unresolved


def manifest_entries(names):
    m = ET.parse(f'{SRC}/etc/vintf/manifest.xml').getroot()
    hits = []
    for hal in m.findall('hal'):
        n = hal.findtext('name') or ''
        if any(k in n for k in names):
            hits.append(ET.tostring(hal, encoding='unicode').strip())
    return hits


for group, bins in SERVICES.items():
    SRC, PFX = DONOR.get(group, (S8, ''))
    files, unres, rcs = [], [], []
    keys = []
    for b in bins:
        path = f'{SRC}/bin/hw/{b}'
        files.append(path)
        miss, un = resolve(path, PREFER_S8_RE.get(group, group in PREFER_S8))
        files += miss
        unres += un
        for dp, _, fs in os.walk(f'{SRC}/etc/init'):
            for rc in fs:
                if b in open(f'{dp}/{rc}', errors='ignore').read():
                    rcs.append(f'{dp}/{rc}')
        keys.append(b.split('@')[0].replace('-service', ''))
        keys.append(b.split('@')[0].replace('sec.android.hardware', 'vendor.samsung.hardware'))
    pref = PREFER_S8_RE.get(group, group in PREFER_S8)
    extra = []
    for e in EXTRA_ELF.get(group, []):
        src = f'{S8SYS}/{e[7:]}' if e.startswith('SYSTEM:') else f'{S8}/{e[4:]}' if e.startswith('S8V:') else f'{SRC}/{e}'
        extra += sorted(glob.glob(src)) if '*' in src else [src]
    s8v = []   # S8 Pie vendor files pulled into a donor group: resolved against the S8 tree, written without prefix
    for src in extra:
        if os.path.exists(src):
            gsrc = SRC
            if src.startswith(S8 + '/') and SRC != S8:
                SRC = S8
            files.append(src)
            miss, un = resolve(src, pref)
            if SRC != gsrc:
                s8v += [src] + miss
            files += miss
            unres += un
            SRC = gsrc
    # a file taken from the S8 replaces the donor's copy of the same path
    s8rel = {p[len(S8) + 1:] for p in s8v}
    files = [p for p in files if not (p.startswith(SRC + '/') and p[len(SRC) + 1:] in s8rel)]
    files += rcs
    hals = manifest_entries(keys + EXTRA_HAL.get(group, []))
    def name(p):
        return p.replace(SRC + '/', PFX).replace(S8SYS + '/', 'SYSTEM:').replace(S8 + '/', '')
    with open(f'{OUT}/{group}.txt', 'w') as f:
        f.write('\n'.join(sorted(set(name(p) for p in files))) + '\n')
    with open(f'{OUT}/{group}.manifest.xml', 'w') as f:
        f.write('\n'.join(hals) + '\n')
    print(f'== {group}: {len(set(files))} files ({len(rcs)} rc), {len(hals)} manifest <hal>, unresolved: {sorted(set(unres))}')
    for p in sorted(set(name(p) for p in files)):
        print('   ', p)
