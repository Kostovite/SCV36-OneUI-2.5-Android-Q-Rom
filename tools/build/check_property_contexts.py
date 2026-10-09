#!/usr/bin/env python3
"""Find duplicate property prefixes across the property_contexts files Android 10 init loads, in the order it loads
them (plat, product, vendor, odm). init aborts with "Duplicate prefix match detected" on any repeat (exact-match
entries with the same name are duplicates too).
usage: sudo python3 check_property_contexts.py <mounted system image root> [--fix]
--fix removes the later duplicates from vendor/odm files (system side is left untouched)."""
import os, sys

root = sys.argv[1]
fix = '--fix' in sys.argv
FILES = ['system/etc/selinux/plat_property_contexts',
         'system/product/etc/selinux/product_property_contexts',
         'system/vendor/etc/selinux/vendor_property_contexts',
         'system/vendor/odm/etc/selinux/odm_property_contexts']
seen = {}
for rel in FILES:
    path = os.path.join(root, rel)
    if not os.path.exists(path):
        print(f'(absent) {rel}'); continue
    out, removed = [], []
    for n, line in enumerate(open(path), 1):
        p = line.split()
        if not p or p[0].startswith('#'):
            out.append(line); continue
        # key = name + match type (prefix by default, "exact" if specified)
        key = (p[0], 'exact' if len(p) >= 3 and p[2] == 'exact' else 'prefix')
        if key in seen:
            first = seen[key]
            print(f'DUP {p[0]:45} {key[1]:6} {rel}:{n}  (first in {first[0]}:{first[1]}, ctx {first[2]} vs {p[1]})')
            if fix and 'vendor' in rel:
                removed.append(line); continue
        else:
            seen[key] = (rel, n, p[1])
        out.append(line)
    if fix and removed:
        open(path, 'w').writelines(out)
        print(f'fixed {rel}: removed {len(removed)} duplicate lines')
print(f'{len(seen)} unique property entries checked')
