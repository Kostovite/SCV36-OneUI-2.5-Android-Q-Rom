#!/usr/bin/env python3
"""Reverse-engineering helper for 32-bit ARM (Thumb-2) Android shared libraries (build server, venv with pyelftools +
capstone): disassemble exported functions and annotate
  - bl/blx to PLT stubs -> imported symbol name (from .rel.plt / .rela.plt)
  - bl/blx to local code -> nearest exported symbol
  - PC-relative literal loads (ldr rX,[pc,#]) and the following "add rX, pc" -> C string / symbol
usage: re_thumb.py <lib.so> <symbol substring> [...]   (demangled names; all matches are dumped)"""
import bisect, re, subprocess, sys
from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB
from elftools.elf.elffile import ELFFile
from elftools.elf.relocation import RelocationSection

path, pats = sys.argv[1], sys.argv[2:]
f = open(path, 'rb'); elf = ELFFile(f); data = open(path, 'rb').read()
segs = [(s['p_vaddr'], s['p_filesz'], s['p_offset']) for s in elf.iter_segments() if s['p_type'] == 'PT_LOAD']


def rd(va, n):
    for v, sz, off in segs:
        if v <= va < v + sz:
            return data[off + va - v: off + va - v + min(n, v + sz - va)]
    return b''


dyn = elf.get_section_by_name('.dynsym')
syms = [(s['st_value'] & ~1, s['st_size'], s.name) for s in dyn.iter_symbols() if s['st_value'] and s['st_info']['type'] in ('STT_FUNC', 'STT_OBJECT')]
names = {}
mangled = [n for _, _, n in syms]
dem = subprocess.run(['c++filt'], input='\n'.join(mangled), capture_output=True, text=True).stdout.splitlines()
symtab = sorted((a, sz, d) for (a, sz, _), d in zip(syms, dem))
addrs = [a for a, _, _ in symtab]


def symat(va):
    i = bisect.bisect_right(addrs, va) - 1
    if i >= 0:
        a, sz, n = symtab[i]
        if va < a + max(sz, 1): return n if va == a else '%s+0x%x' % (n, va - a)
    return None


# PLT: GOT slot -> import name; PLT stub address found by scanning .plt for the GOT reference (ARM ldr pattern)
got2name = {}
for sec in elf.iter_sections():
    if isinstance(sec, RelocationSection) and sec.name in ('.rel.plt', '.rela.plt'):
        st = elf.get_section(sec['sh_link'])
        for r in sec.iter_relocations():
            got2name[r['r_offset']] = st.get_symbol(r['r_info_sym']).name
imp_names = list(got2name.values())
imp_dem = dict(zip(imp_names, subprocess.run(['c++filt'], input='\n'.join(imp_names), capture_output=True, text=True).stdout.splitlines()))
plt = elf.get_section_by_name('.plt'); plt2name = {}
if plt:
    # bionic ARM PLT entry: add ip, pc, #0xNN00000; add ip, ip, #0xNN000; ldr pc, [ip, #0xNNN]!  (12 bytes, after 20-byte header)
    base = plt['sh_addr']; body = plt.data()
    for off in range(20, len(body) - 11, 12):
        w = [int.from_bytes(body[off + 4 * k: off + 4 * k + 4], 'little') for k in range(3)]
        def imm(x):
            v, rot = x & 0xff, ((x >> 8) & 0xf) * 2
            return ((v >> rot) | (v << (32 - rot))) & 0xffffffff
        got = (base + off + 8 + imm(w[0]) + imm(w[1]) + (w[2] & 0xfff)) & 0xffffffff
        if got in got2name: plt2name[base + off] = imp_dem.get(got2name[got], got2name[got])


def cstr(va):
    b = rd(va, 160).split(b'\0')[0]
    if len(b) >= 3 and all(32 <= c < 127 or c in (9, 10) for c in b): return b.decode()
    return None


md = Cs(CS_ARCH_ARM, CS_MODE_THUMB); md.detail = False
for a, sz, n in symtab:
    if not any(p in n for p in pats) or not sz or 'thunk' in n: continue
    print('=' * 10, n, hex(a), sz)
    code = rd(a, sz); lit = {}
    for ins in md.disasm(code, a):
        note = ''
        m = re.match(r'(\w+), \[pc, #(-?0x[0-9a-f]+|-?\d+)\]', ins.op_str)
        if ins.mnemonic.startswith('ldr') and m:
            pa = ((ins.address + 4) & ~3) + int(m.group(2), 0)
            val = int.from_bytes(rd(pa, 4), 'little'); lit[m.group(1)] = (val, ins.address)
            note = '=0x%x' % val
        m = re.match(r'(\w+), pc$', ins.op_str)
        if ins.mnemonic == 'add' and m and m.group(1) in lit:
            va = (lit[m.group(1)][0] + ins.address + 4) & 0xffffffff
            s = cstr(va); note = ('"%s"' % s) if s else (symat(va) or hex(va))
        if ins.mnemonic in ('bl', 'blx') and ins.op_str.startswith('#'):
            t = int(ins.op_str[1:], 0)
            note = plt2name.get(t) or symat(t) or ''
        print('%6x: %-6s %-28s %s' % (ins.address, ins.mnemonic, ins.op_str, ('; ' + note) if note else ''))
