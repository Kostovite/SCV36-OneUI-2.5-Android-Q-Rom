#!/usr/bin/env python3
"""WSL: SELinux additions for the S8 phone HALs (NFC, fingerprint) on top of the T835 Q vendor policy.
Rules come from Samsung's G9600 Android 10 vendor policy (same HAL family, same Q platform policy).
- type declarations for domain types the T835 lacks
- attribute membership rewritten as small per-type (typeattributeset ATTR (TYPE)) statements
- allow/neverallow-free rules mentioning the domains, dropping any that reference types unknown to the T835 policy
Writes config/sepolicy/s8_phone_hals.cil."""
import os, re
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
T = os.path.expanduser('~/s8rom/trees')
G = open(T + '/g9600_vendor/etc/selinux/vendor_sepolicy.cil').read().splitlines()
TV = open(T + '/t835_vendor/etc/selinux/vendor_sepolicy.cil').read()
PLAT = open(T + '/t835_vendor/etc/selinux/plat_pub_versioned.cil').read()
SYSP = open(T + '/g9600_root/system/etc/selinux/plat_sepolicy.cil').read()
OUT = os.path.join(REPO, 'config/sepolicy')
os.makedirs(OUT, exist_ok=True)

DOMAINS = ['hal_nfc_default', 'hal_fingerprint_default']
# HAL-private types these domains need (exec files, devices, data dirs) - taken from G9600 if T835 lacks them
OWN = DOMAINS + [d + '_exec' for d in DOMAINS] + ['fp_sensor_device', 'nfc_vendor_data_file', 'nfc_efs_file',
                                                  'biometrics_vendor_data_file', 'biometrics_data_file']
known = set(re.findall(r'\((?:type|typeattribute) ([a-zA-Z0-9_]+)\)', TV + PLAT + SYSP))
g_types = set(re.findall(r'\(type ([a-zA-Z0-9_]+)\)', '\n'.join(G)))
add_types = [t for t in OWN if t in g_types and t not in known]
known |= set(add_types)
known |= set(re.findall(r'\(typeattribute ([a-zA-Z0-9_]+)\)', '\n'.join(G))) & set(re.findall(r'\b([a-z0-9_]+)\b', TV + PLAT))
WORD = re.compile(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\b')
KEYWORDS = {'allow', 'allowx', 'auditallow', 'dontaudit', 'typetransition', 'typeattributeset', 'type', 'typeattribute',
            'ioctl', 'and', 'or', 'not', 'all', 'self', 'roletype', 'object_r', 'expandtypeattribute', 'true', 'false'}

out = [f'(type {t})' for t in add_types] + [f'(roletype object_r {t})' for t in add_types]
dropped = 0
for l in G:
    s = l.strip()
    m = re.match(r'\(typeattributeset ([a-zA-Z0-9_]+) \((.*)\)\)$', s)
    if m:  # attribute membership: keep only our types, as small statements
        attr, members = m.group(1), m.group(2).split()
        for t in OWN:
            if t in members and t in known and attr in known and not attr.startswith('base_typeattr'):
                out.append(f'(typeattributeset {attr} ({t}))')
        continue
    if not any(re.search(rf'\b{d}\b', s) for d in DOMAINS + add_types):
        continue
    if s.startswith(('(type ', '(roletype ', '(typeattribute ', '(neverallow')):
        continue
    # every identifier that looks like a type/attribute must exist in the merged policy
    idents = {w for w in WORD.findall(s) if w not in KEYWORDS and '_' in w}
    unknown = {w for w in idents if w not in known and not re.fullmatch(r'[a-z_]+', w) is None and w.endswith(
        ('_file', '_device', '_exec', '_service', '_hwservice', '_prop', '_socket', '_default', '_qti', '_data_file'))
        and w not in known}
    if unknown:
        dropped += 1
        continue
    out.append(s)
out = list(dict.fromkeys(out))
open(OUT + '/s8_phone_hals.cil', 'w').write('\n'.join(out) + '\n')
print(f'added types: {add_types}')
print(f'statements written: {len(out)} (dropped {dropped} referencing types absent from T835)')
