#!/usr/bin/env python3
"""Unresolved-import audit of the port vendor tree, the way the Q linker resolves a vendor process.

Each ELF's undefined GLOBAL symbols must be exported by something in its own NEEDED closure (breadth-first,
searched in the vendor namespace order: vendor/lib*, VNDK-SP, VNDK, LL-NDK). Libraries that are dlopen()ed
(HALs, plugins) usually also see the symbols of the host process, so for them the common host libs (libc, libm,
libdl, liblog, libc++, libutils, libcutils, libhardware, libhidlbase ...) are added as a baseline; a symbol only
some other unrelated vendor lib exports is still reported. Pie-only exports (libcutils set_sched_policy, libc
__aeabi_idiv0, old libui/libgui ABI) show up here instead of as silent dlopen failures at runtime.

usage: vendor_symbol_audit.py [vendor dir] [g9600 system dir]   (WSL, uses readelf)
"""
import os, re, subprocess, sys
from collections import deque

V = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/s8rom/port/vendor')
G = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~/s8rom/trees/g9600_root/system')
RT = next(os.path.join(G, 'apex', d) for d in os.listdir(os.path.join(G, 'apex')) if d.startswith('com.android.runtime'))
LLNDK = ['libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libandroid_net.so', 'libnativewindow.so', 'libsync.so',
         'libvndksupport.so', 'libEGL.so', 'libGLESv1_CM.so', 'libGLESv2.so', 'libGLESv3.so', 'libneuralnetworks.so',
         'libmediandk.so', 'libbinder_ndk.so', 'libvulkan.so', 'libft2.so']
HOST = ['libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libc++.so']  # host process baseline (only LL-NDK + libc++:

def search_dirs(bits):
    l = 'lib64' if bits == 64 else 'lib'
    d = [os.path.join(V, l, s) for s in ('', 'hw', 'egl', 'soundfx', 'mediadrm', 'camera', 'sensors', 'vndk', 'vndk-sp')]  # vendor VNDK-ext first
    d += [os.path.join(G, l, 'vndk-sp-29'), os.path.join(G, l, 'vndk-29'), os.path.join(RT, l, 'bionic'),
          os.path.join(RT, l)]
    return [x for x in d if os.path.isdir(x)]

_cache = {}
def elf(path):
    if path in _cache:
        return _cache[path]
    out = subprocess.run(['readelf', '-W', '-d', '--dyn-syms', path], capture_output=True, text=True).stdout
    needed = re.findall(r'\(NEEDED\)\s+Shared library: \[(.+?)\]', out)
    exports, imports = set(), set()
    for line in out.splitlines():
        if ' GLOBAL ' not in line and ' WEAK ' not in line:
            continue
        f = line.split()
        name, ndx = f[-1], f[-2]
        if name.endswith(':'):
            continue
        name = name.split('@')[0]
        if ndx == 'UND':
            if ' GLOBAL ' in line:
                imports.add(name)
        else:
            exports.add(name)
    _cache[path] = (needed, exports, imports)
    return _cache[path]

def find(name, bits):
    if name in LLNDK:   # LL-NDK always comes from the system/runtime, never from vendor
        for d in (os.path.join(RT, 'lib64' if bits == 64 else 'lib', 'bionic'), os.path.join(G, 'lib64' if bits == 64 else 'lib')):
            p = os.path.join(d, name)
            if os.path.isfile(p):
                return p
    for d in search_dirs(bits):
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p
    return None

def closure(path, bits, extra=()):
    seen, missing, q = {}, [], deque([path] + [p for p in (find(n, bits) for n in extra) if p])
    while q:
        p = q.popleft()
        if p in seen:
            continue
        seen[p] = True
        for n in elf(p)[0]:
            fp = find(n, bits)
            if fp is None:
                if p == path:
                    missing.append(n)
            elif fp not in seen:
                q.append(fp)
    return list(seen), missing

def ident(path):
    with open(path, 'rb') as f:
        h = f.read(5)
    if h[:4] != b'\x7fELF':
        return None
    return 64 if h[4] == 2 else 32

report = []
for root in ('lib', 'lib64', 'bin'):
    for dp, dn, fn in os.walk(os.path.join(V, root)):
        if '/rfsa/' in dp + '/':
            continue          # aDSP/cDSP shared objects (loaded by the DSP, not by Linux)
        for n in fn:
            p = os.path.join(dp, n)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            bits = ident(p)
            if bits is None:
                continue
            is_exe = root == 'bin'
            libs, miss = closure(p, bits, () if is_exe else HOST)
            have = set()
            for l in libs:
                have |= elf(l)[1]
            unres = sorted(s for s in elf(p)[2] if s not in have)
            if miss or unres:
                report.append('%s: %s%s' % (os.path.relpath(p, V), 'NEEDED%s ' % miss if miss else '',
                                            'SYMS%s' % unres if unres else ''))
print('\n'.join(sorted(report)))
print('# %d files with problems' % len(report), file=sys.stderr)
