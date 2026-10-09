#!/usr/bin/env python3
"""Remove vendor-side entries that the (G9600) platform policy already defines. Android 10 aborts on duplicates:
init: "Duplicate prefix match detected" (property_contexts); (hw)servicemanager refuse duplicate service names.
Samsung's sdm845 Q platform policy carries several Qualcomm vendor.* properties that the Tab S4 vendor also defines.
usage: python3 dedup_contexts.py <plat_dir> <vendor_selinux_dir>"""
import os, sys

plat, vend = sys.argv[1:]
# vndservice_contexts is NOT paired with plat_service_contexts: it belongs to vndservicemanager (separate namespace,
# needs its own "*" default entry), so only property and hwservice contexts share a namespace with the platform.
PAIRS = [('plat_property_contexts', 'vendor_property_contexts'),
         ('plat_hwservice_contexts', 'vendor_hwservice_contexts')]


def key(p, kind):
    if kind == 'property':
        return (p[0], 'exact' if len(p) >= 3 and p[2] == 'exact' else 'prefix')
    return (p[0],)


for pf, vf in PAIRS:
    kind = 'property' if 'property' in pf else 'service'
    pp, vp = os.path.join(plat, pf), os.path.join(vend, vf)
    if not (os.path.exists(pp) and os.path.exists(vp)):
        continue
    seen = {key(l.split(), kind) for l in open(pp) if l.split() and not l.startswith('#')}
    out, dropped, own = [], [], set()
    for l in open(vp):
        p = l.split()
        if p and not l.startswith('#'):
            k = key(p, kind)
            if k in seen or k in own:
                dropped.append(p[0]); continue
            own.add(k)
        out.append(l)
    open(vp, 'w').writelines(out)
    print(f'{vf}: removed {len(dropped)} duplicates {dropped}')
