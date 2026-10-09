#!/usr/bin/env python3
"""Static link check for transplanted S8 Pie vendor ELFs inside the port (T835 Q vendor + G9600 Q system).
For each ELF: follow NEEDED like the vendor linker namespace does (vendor lib dirs first, then system VNDK-29 /
LLNDK / bionic) and report undefined dynamic symbols that no loaded library defines (-> "CANNOT LINK EXECUTABLE",
exit status 1 at start).
usage: python3 symcheck.py [group ...]   (default: all groups in config/transplant/*.txt)"""
import glob, os, re, subprocess, sys
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
from functools import lru_cache

T = os.path.expanduser('~/s8rom')
V = T + '/port/vendor'
SYS = T + '/trees/g9600_root/system'
TR = os.path.join(REPO, 'config/transplant')


def search_dirs(bits):
    d = 'lib64' if bits == 64 else 'lib'
    dirs = [f'{V}/{d}', f'{V}/{d}/hw', f'{V}/{d}/egl', f'{SYS}/{d}/vndk-sp-29', f'{SYS}/{d}/vndk-29', f'{SYS}/{d}']
    for apex in sorted(glob.glob(f'{SYS}/apex/*')):
        dirs += [f'{apex}/{d}', f'{apex}/{d}/bionic']
    return dirs


@lru_cache(None)
def elf_info(path):
    out = subprocess.run(['readelf', '-W', '-d', '--dyn-syms', path], capture_output=True, text=True).stdout
    needed = re.findall(r'\(NEEDED\)\s+Shared library: \[(.+?)\]', out)
    defined, undef = set(), set()
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 8 and p[0].endswith(':') and p[4] in ('GLOBAL', 'WEAK'):
            name = p[7].split('@')[0]
            if p[6] == 'UND':
                if p[4] == 'GLOBAL':
                    undef.add(name)
            else:
                defined.add(name)
    bits = 64 if 'ELF64' in subprocess.run(['readelf', '-h', path], capture_output=True, text=True).stdout else 32
    return tuple(needed), frozenset(defined), frozenset(undef), bits


def find(lib, bits):
    for d in search_dirs(bits):
        if os.path.exists(f'{d}/{lib}'):
            return f'{d}/{lib}'
    return None


def check(path):
    needed, _, undef, bits = elf_info(path)
    provided, missing_libs, seen, todo = set(), [], set(), list(needed)
    while todo:                                  # breadth-first over the dependency tree
        lib = todo.pop(0)
        if lib in seen:
            continue
        seen.add(lib)
        p = find(lib, bits)
        if not p:
            missing_libs.append(lib); continue
        n, d, _, _ = elf_info(p)
        provided |= d
        todo += list(n)
    return missing_libs, sorted(s for s in undef if s not in provided)


groups = sys.argv[1:] or [os.path.basename(g)[:-4] for g in glob.glob(TR + '/*.txt') if not g.endswith('data.txt')]
bad = 0
for g in groups:
    for rel in open(f'{TR}/{g}.txt').read().split():
        rel = rel.replace('SYSTEM:', '')
        path = f'{V}/{rel}'
        if not os.path.exists(path) or not (rel.startswith('bin/') or rel.endswith('.so')):
            continue
        if open(path, 'rb').read(4) != b'\x7fELF':
            continue
        ml, ms = check(path)
        if ml or ms:
            bad += 1
            print(f'[{g}] {rel}')
            if ml: print(f'    missing libs: {ml}')
            if ms: print(f'    unresolved symbols ({len(ms)}): {ms[:12]}{" ..." if len(ms) > 12 else ""}')
print(f'checked groups {groups}: {bad} ELF(s) with link problems')
