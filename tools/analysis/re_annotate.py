#!/usr/bin/env python3
"""Reverse-engineering helper (build server, venv with pyelftools): disassemble a function of a vmlinux-to-elf
kernel ELF and annotate adrp/add (and adrp/ldr) pairs with the C string or symbol they point at, plus bl targets.
usage: re_annotate.py <kernel.elf> <objdump> <symbol> [<symbol>...]"""
import re, subprocess, sys
from elftools.elf.elffile import ELFFile

elf_path, objdump, syms = sys.argv[1], sys.argv[2], sys.argv[3:]
f = open(elf_path, 'rb'); elf = ELFFile(f)
segs = [(s['p_vaddr'], s['p_filesz'], s['p_offset']) for s in elf.iter_segments() if s['p_type'] == 'PT_LOAD']
symtab = elf.get_section_by_name('.symtab') or elf.get_section_by_name('.dynsym')   # stripped .so: dynamic symbols
by_name, by_addr = {}, []
for s in symtab.iter_symbols():
    if s['st_value']:
        by_name.setdefault(s.name, s['st_value']); by_addr.append((s['st_value'], s.name))
by_addr.sort()
import bisect
addrs = [a for a, _ in by_addr]


def read(va, n):
    for v, sz, off in segs:
        if v <= va < v + sz:
            f.seek(off + va - v); return f.read(min(n, v + sz - va))
    return b''


def cstr(va):
    b = read(va, 200).split(b'\0')[0]
    if b[:1] == b'\x01' and len(b) > 2: b = b'<%c>' % b[1] + b[2:]   # printk KERN_SOH level prefix
    if len(b) >= 2 and all(32 <= c < 127 or c in (9, 10) for c in b):
        return b.decode().replace('\n', '\\n')
    return None


def symof(va):
    i = bisect.bisect_right(addrs, va) - 1
    if i < 0: return None
    a, n = by_addr[i]; return n if va == a else '%s+0x%x' % (n, va - a)


for name in syms:
    start = by_name[name]; i = addrs.index(start)
    sz = next((s['st_size'] for s in symtab.iter_symbols() if s.name == name), 0)
    end = start + sz if sz else next(a for a in addrs[i:] if a > start)
    out = subprocess.run([objdump, '-d', '--no-show-raw-insn', '--start-address=0x%x' % start,
                          '--stop-address=0x%x' % end, elf_path], capture_output=True, text=True).stdout
    print('=' * 20, name, hex(start), '-', hex(end))
    page = {}
    for line in out.splitlines():
        m = re.match(r'\s*([0-9a-f]+):\s+(\S+)\s*(.*)', line)
        if not m: continue
        addr, op, args = int(m.group(1), 16), m.group(2), m.group(3)
        note = ''
        regs = re.findall(r'\b([xw]\d+)\b', args)
        if op == 'adrp':
            mm = re.search(r'(?:0x)?([0-9a-f]{3,16})', args.split(',', 1)[1])   # 64-bit kernel or short .so address
            if mm: page[regs[0].replace('w', 'x')] = int(mm.group(1), 16)
        elif op == 'add' and len(regs) >= 2 and regs[1] in page and '#' in args:
            imm = int(re.search(r'#(0x[0-9a-f]+|\d+)', args).group(1), 0)
            va = page[regs[1]] + imm; page[regs[0]] = va
            s = cstr(va); note = ('"%s"' % s) if s else (symof(va) or '')
        elif op == 'ldr' and '[' in args:
            mm = re.search(r'\[(x\d+),#(0x[0-9a-f]+|\d+)\]', args)
            if mm and mm.group(1) in page:
                note = symof(page[mm.group(1)] + int(mm.group(2), 0)) or ''
        args = re.sub(r'\s*<[^>]*>', lambda x: x.group(0) if op in ('bl', 'b') or op.startswith('b.') or op.startswith('cb') or op.startswith('tb') else '', args)
        print('%x: %-7s %s%s' % (addr & 0xffff, op, args, ('    ; ' + note) if note else ''))
