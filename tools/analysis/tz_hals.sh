#!/usr/bin/env bash
# WSL: TrustZone-backed HALs (must match the S8's own TZ apps) + Samsung hwservice names that need labels.
S8=~/s8rom/trees/s8_vendor/vendor; TV=~/s8rom/trees/t835_vendor; PV=~/s8rom/port/vendor
echo "== S8 vs T835 TZ-related HAL binaries:"
for p in keymaster gatekeeper vaultkeeper wvkprov proca tlc tee skpm sem secure_storage drm; do
  echo "  $p: S8[$(ls $S8/bin/hw $S8/bin 2>/dev/null | grep -i $p | tr '\n' ' ')] T835[$(ls $TV/bin/hw $TV/bin 2>/dev/null | grep -i $p | tr '\n' ' ')]"
done
echo "== S8 manifest names (all) - for hwservice labels:"
grep -oE '<fqname>[^<]+</fqname>|<name>[a-z][^<]+</name>' $S8/etc/vintf/manifest.xml | sed -E 's/<[^>]+>//g' | paste -sd' ' | fold -w 220
echo "== port: which manifest interfaces lack a hwservice label:"
python3 - $PV ~/s8rom/trees/g9600_root/system/etc/selinux/plat_hwservice_contexts <<'PY'
import sys, re
pv, plat = sys.argv[1:]
m = open(pv + '/etc/vintf/manifest.xml').read()
labels = set()
for f in (plat, pv + '/etc/selinux/vendor_hwservice_contexts'):
    for l in open(f):
        p = l.split()
        if p and not p[0].startswith('#'): labels.add(p[0])
for hal in re.findall(r'<hal format="hidl">.*?</hal>', m, re.S):
    pkg = re.search(r'<name>([^<]+)</name>', hal).group(1)
    for itf in re.findall(r'<interface>\s*<name>([^<]+)</name>', hal):
        if f'{pkg}::{itf}' not in labels:
            print(f'  UNLABELED {pkg}::{itf}')
PY
