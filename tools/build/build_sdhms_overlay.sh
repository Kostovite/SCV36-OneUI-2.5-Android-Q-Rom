#!/usr/bin/env bash
# WSL: static RRO for com.sec.android.sdhms (SSRM) -> config/overlay/out/SdhmsS8Overlay.apk (goes to /vendor/overlay).
# Why: SDHMS always loads raw/siop_starqlte_sdm845 (S9 policy, name hard-coded in sb.m; "ssrm_default" only on eng
# builds) and validates every CPUFreqMax / GPUFreqMax value against the frequencies the kernel reports
# (ssrm.jar CustomFrequencyManagerService: /sys/power/cpufreq_table, /sys/class/kgsl/kgsl-3d0/gpu_available_frequencies).
# Adreno 630 steps (675/520 MHz) do not exist on the S8 Adreno 540 -> "Fails to parse policy XML /
# limiter(GPUFreqMax) has invalid value - 520000000" + SSRM Warning dialog, and no thermal policy at all.
# Fix: same S9 phone policy, every frequency replaced by the highest valid S8 step <= it (never looser).
# Valid sets = stock JPN DT (work/kernel_gap/stock_dtb0.dts): GPU qcom,gpu-freq; CPU = Samsung cpufreq_limit table:
# big cluster (cpufreq-table-4) >= big_min_freq 979200 + LITTLE (cpufreq-table-0) / little_divider 2.
set -e
P=$(cd "$(dirname "$0")/../.." && pwd); W=~/s8rom/work/sdhms_overlay; O=$P/config/overlay/out
APK=~/s8rom/trees/g9600_root/system/priv-app/SamsungDeviceHealthManagerService/SamsungDeviceHealthManagerService.apk
FWRES=~/s8rom/trees/g9600_root/system/framework/framework-res.apk
rm -rf $W && mkdir -p $W/src $W/res/raw $O
unzip -q -o -j $APK res/raw/siop_starqlte_sdm845.xml -d $W/src
python3 - $P/work/kernel_gap/stock_dtb0.dts $W/src/siop_starqlte_sdm845.xml $W/res/raw/siop_starqlte_sdm845.xml <<'PY'
import re, sys
dts, src, out = sys.argv[1:]
d = open(dts).read()
tbl = {m.group(1): [int(x, 16) for x in m.group(2).split()]
       for m in re.finditer(r'qcom,cpufreq-table-(\d+)\s*=\s*<([^>]*)>', d)}
big = [f for f in tbl['4'] if f >= 979200]
little = [f // 2 for f in tbl['0']]
cpu = sorted(set(big + little))
gpu = sorted(set(int(x, 16) for x in re.findall(r'qcom,gpu-freq\s*=\s*<(0x[0-9a-f]+)>', d)) - {27000000})
print('valid GPU', gpu); print('valid CPU', cpu)
def fit(v, valid):
    if v == -1 or v in valid: return v
    lower = [f for f in valid if f <= v]
    return lower[-1] if lower else valid[0]
s = open(src).read(); changes = {}
def fix(m):
    lim, body = m.group(1), m.group(0)
    valid = gpu if lim == 'GPUFreqMax' else cpu
    def val(vm):
        new = [fit(int(x), valid) for x in vm.group(1).replace(' ', '').split(':')]
        for a, b in zip(vm.group(1).replace(' ', '').split(':'), new):
            if int(a) != b: changes[(lim, int(a))] = b
        return 'value="' + ':'.join(str(x) for x in new) + '"'
    return re.sub(r'value="([^"]*)"', val, body)
s = re.sub(r'<[^>]*(?:limiter|name)="(CPUFreqMax|GPUFreqMax)"[^>]*>', fix, s)
open(out, 'w').write(s)
for (lim, a), b in sorted(changes.items()): print(f'  {lim}: {a} -> {b}')
# self-check: every value now valid
for lim, valid in (('CPUFreqMax', cpu), ('GPUFreqMax', gpu)):
    for m in re.finditer(r'(?:limiter|name)="%s"[^>]*?value="([^"]*)"' % lim, s):
        for x in m.group(1).replace(' ', '').split(':'):
            assert int(x) == -1 or int(x) in valid, (lim, x)
print('policy OK:', out)
PY
cat > $W/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.s8port.overlay.sdhms" android:versionCode="1" android:versionName="1.0">
    <overlay android:targetPackage="com.sec.android.sdhms" android:isStatic="true" android:priority="10" />
    <application android:hasCode="false" />
</manifest>
EOF
aapt package -f -M $W/AndroidManifest.xml -S $W/res -I $FWRES -F $W/unsigned.apk
zipalign -f 4 $W/unsigned.apk $W/aligned.apk
KS=$P/config/overlay/s8port_overlay.jks
[ -f $KS ] || keytool -genkeypair -keystore $KS -storepass s8port -keypass s8port -alias s8port -keyalg RSA \
  -keysize 2048 -validity 10000 -dname "CN=S8 port overlay" >/dev/null 2>&1
apksigner sign --ks $KS --ks-pass pass:s8port --key-pass pass:s8port --out $O/SdhmsS8Overlay.apk $W/aligned.apk
apksigner verify $O/SdhmsS8Overlay.apk && aapt dump badging $O/SdhmsS8Overlay.apk | head -2
unzip -l $O/SdhmsS8Overlay.apk
