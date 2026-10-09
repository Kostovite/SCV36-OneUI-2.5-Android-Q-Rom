#!/usr/bin/env python3
"""Offline VINTF kernel check: framework compatibility matrix (target-level from the vendor manifest) vs our kernel
.config + version. usage: vintf_kcheck.py <system/etc/vintf dir> <vendor manifest.xml> <kernel .config> <kver e.g. 4.4.153>"""
import glob, re, sys, xml.etree.ElementTree as ET
vdir, man, cfgf, kver = sys.argv[1:5]
level = ET.parse(man).getroot().get('target-level')
print('vendor manifest target-level:', level)
cfg = {}
for l in open(cfgf):
    m = re.match(r'(CONFIG_\w+)=(.*)', l.strip())
    if m: cfg[m.group(1)] = m.group(2).strip('"')
    m = re.match(r'# (CONFIG_\w+) is not set', l.strip())
    if m: cfg[m.group(1)] = 'n'
for f in sorted(glob.glob(vdir + '/compatibility_matrix.*.xml')):
    r = ET.parse(f).getroot()
    if r.get('level') != level: continue
    print('matrix', f.split('/')[-1])
    kv = tuple(int(x) for x in kver.split('.'))
    for k in r.findall('kernel'):
        v = tuple(int(x) for x in k.get('version').split('.'))
        if v[:2] != kv[:2]: continue
        cond = k.find('conditions')
        if cond is not None:
            ok = all(cfg.get(c.findtext('key'), 'n') == c.findtext('value') for c in cond.findall('config'))
            if not ok: continue
        print('  kernel req', k.get('version'), '(ours', kver + ')', 'OK' if kv >= v else 'TOO OLD',
              '| conditional' if cond is not None else '')
        for c in k.findall('config'):
            key, val = c.findtext('key'), c.findtext('value')
            have = cfg.get(key, 'n')
            if val in ('y', 'n', 'm'):
                bad = (have != val) if val != 'n' else have not in ('n',)
            else:
                bad = have.lower() != val.lower().strip('"')
            if bad: print(f'    MISMATCH {key}: need {val}, have {have}')
