#!/usr/bin/env python3
"""WSL: every NEEDED library of the transplanted vendor ELFs must be loadable from a vendor process on Android 10
(vendor lib dirs, VNDK-29 / VNDK-SP-29 of the G9600 system, LLNDK, bionic). transplant_deps.present() also counts
plain /system libraries as present, which a vendor process cannot see (libandroid, libstdc++ ...).
usage: python3 vendor_visible_check.py [vendor dir]   (default ~/s8rom/port/vendor); exit 1 on problems"""
import glob, os, re, subprocess, sys
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

V = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/s8rom/port/vendor')
SYS = os.path.expanduser('~/s8rom/trees/g9600_root/system')
TDIR = os.path.join(REPO, 'config/transplant')
llndk = set()
for f in glob.glob(SYS + '/etc/llndk.libraries.*.txt'):
    llndk |= set(open(f).read().split())
BIONIC = {'libc.so', 'libm.so', 'libdl.so'}
files = set()
for t in glob.glob(TDIR + '/*.txt'):
    if t.endswith('data.txt'):
        continue
    for l in open(t):
        l = re.sub(r'^(G9600|SYSTEM):', '', l.strip())
        if l.startswith(('lib/', 'lib64/', 'bin/')):
            files.add(l)
bad = {}
for f in sorted(files):
    p = os.path.join(V, f)
    if not os.path.isfile(p):
        continue
    out = subprocess.run(['readelf', '-d', p], capture_output=True, text=True).stdout
    if 'NEEDED' not in out:
        continue
    d = 'lib64' if 'ELF 64' in subprocess.run(['file', '-L', p], capture_output=True, text=True).stdout else 'lib'
    for n in re.findall(r'\(NEEDED\)\s+Shared library: \[(.+?)\]', out):
        if n in BIONIC or n in llndk:
            continue
        if any(os.path.exists(x) for x in (f'{V}/{d}/{n}', f'{V}/{d}/hw/{n}', f'{V}/{d}/egl/{n}',
                                           f'{SYS}/{d}/vndk-29/{n}', f'{SYS}/{d}/vndk-sp-29/{n}')):
            continue
        bad.setdefault(f'{d}/{n}', []).append(f)
for n, users in sorted(bad.items()):
    print(f'NOT VENDOR-VISIBLE {n}  <- {", ".join(users[:4])}{" ..." if len(users) > 4 else ""}')
print(f'vendor visibility: {len(files)} transplanted files checked, {len(bad)} missing libraries')
sys.exit(1 if bad else 0)
