#!/usr/bin/env python3
"""Differential emulation of the fingerprint kernel driver (stock SCV36 fps_* vs our et5xx etspi_*).
Runs probe -> open -> the HAL's ioctl sequence inside Unicorn; every call leaving the driver is stubbed and logged
(gpio, pinctrl, delays, clocks, regulators, irq, printk). Kernel image is rebased to low VA (unicorn has no MMU).
usage: fpemu.py <elf> <prefix fps_|etspi_> > trace.txt"""
import sys, struct, re
from elftools.elf.elffile import ELFFile
from unicorn import *
from unicorn.arm64_const import *

ELF, PFX = sys.argv[1], sys.argv[2]
KBASE = 0xffffff8000000000
def R(a): return a - KBASE if a >= KBASE else a

f = open(ELF, 'rb'); e = ELFFile(f)
syms = {}; addr2name = {}
for s in e.iter_sections():
    if s.header.sh_type != 'SHT_SYMTAB': continue
    for y in s.iter_symbols():
        if y.name and not y.name.startswith('$') and y['st_value'] >= KBASE and y['st_info']['type'] in ('STT_FUNC', 'STT_NOTYPE', 'STT_OBJECT'):
            syms.setdefault(y.name, y['st_value'])
            if y['st_info']['type'] in ('STT_FUNC', 'STT_NOTYPE'):
                addr2name.setdefault(R(y['st_value']), y.name)
segs = [(p['p_vaddr'], p['p_filesz'], p['p_memsz'], p['p_offset']) for p in e.iter_segments() if p['p_type'] == 'PT_LOAD']
if not segs:
    segs = [(s['sh_addr'], s['sh_size'] if s['sh_type'] != 'SHT_NOBITS' else 0, s['sh_size'], s['sh_offset'])
            for s in e.iter_sections() if s['sh_flags'] & 2 and s['sh_addr'] >= KBASE]
lo = min(R(v) for v, _, _, _ in segs) & ~0x1fffff
hi = (max(R(v) + m for v, _, m, _ in segs) + 0x2000000) & ~0xfff   # +32 MiB slack (bss of the raw-Image ELF)
uc = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
uc.mem_map(lo, hi - lo)
img = bytearray(hi - lo)
for v, fs, ms, off in segs:
    f.seek(off); img[R(v) - lo:R(v) - lo + fs] = f.read(fs)
# rebase absolute kernel pointers in data (LIST_HEAD self pointers etc.)
for i in range(0, len(img) - 7, 8):
    q = struct.unpack_from('<Q', img, i)[0]
    if 0xffffff8008000000 <= q < 0xffffff8010000000:
        struct.pack_into('<Q', img, i, q - KBASE)
uc.mem_write(lo, bytes(img))
# page 0: NULL function pointers -> ret
uc.mem_map(0, 0x10000); uc.mem_write(0, b'\xc0\x03\x5f\xd6' * (0x10000 // 4))
HEAP = 0x100000000; HSZ = 0x1000000; uc.mem_map(HEAP, HSZ); hp = [HEAP + 0x1000]
def alloc(n, data=None):
    a = hp[0]; hp[0] += (max(n, 16) + 0xfff) & ~0xfff
    if data: uc.mem_write(a, data)
    return a
STK = 0x200000000; uc.mem_map(STK, 0x40000)
TI = STK + 0x20000                     # thread_info at 16K-aligned stack base
uc.mem_write(TI + 8, struct.pack('<Q', 0x7fffffffff))   # addr_limit = USER_DS
USER = 0x10000000; uc.mem_map(USER, 0x10000)
STOP = 0x300000000; uc.mem_map(STOP, 0x1000); uc.mem_write(STOP, b'\xc0\x03\x5f\xd6' * 1024)

def rs(a, n=200):
    try:
        b = uc.mem_read(a, n); return b.split(b'\0')[0].decode('latin1')
    except Exception: return '<bad %x>' % a
def X(i): return uc.reg_read(UC_ARM64_REG_X0 + i) if i < 29 else uc.reg_read(UC_ARM64_REG_X29)
def s32(v): v &= 0xffffffff; return v - (1 << 32) if v & 0x80000000 else v

GPIO = {'ldoPin': 74, 'drdyPin': 127}       # JPN Rev12 DT: no sleepPin
U32 = {'orient': [0], 'min_cpufreq_limit': [0x20d000], 'spi-max-frequency': [16000000]}
STR = {'chipid': 'ET510'}
pins = {}; gpio_state = {}; log = []
def L(s): log.append(s); print(s)
def key(name):
    return name.split('-', 1)[1] if name.startswith(('fps-', 'etspi-')) else name

def printk(fmt, args):
    out, ai = '', 0
    for m in re.finditer(r'%[-0-9.]*(l{0,2}|z|h{0,2})([sdiuxXpc%])|[^%]+', fmt):
        t = m.group(0)
        if not t.startswith('%'): out += t; continue
        c = m.group(2)
        if c == '%': out += '%'; continue
        v = args[ai] if ai < len(args) else 0; ai += 1
        out += rs(v) if c == 's' else str(s32(v)) if c in 'di' else '%x' % v if c in 'xXp' else str(v & 0xffffffff)
    return out.lstrip('<0123456789>').rstrip('\n')

QUIET = re.compile(r'^(mutex_|_raw_spin|__raw_spin|spin_|__mutex_init|init_waitqueue|__init_waitqueue|wake_lock_init|'
                   r'wakeup_source|__wake_up|init_timer|setup_timer|lockdep|_cond_resched|__might_sleep|'
                   r'list_del|__check_object_size|__stack_chk|preempt|__pm_|pm_)')

def stub(name):
    a = [X(i) for i in range(6)]; ret = 0
    if name in ('printk', 'vprintk', 'vprintk_emit'):
        L('  printk: ' + printk(rs(a[0]), a[1:6] + [0] * 4)); ret = 0
    elif name in ('kmem_cache_alloc_trace',): ret = alloc(a[2])
    elif name in ('__kmalloc', 'kmalloc_order_trace', 'kmalloc_order', 'vmalloc', 'vzalloc'): ret = alloc(a[0])
    elif name in ('devm_kmalloc',): ret = alloc(a[1])
    elif name in ('kmem_cache_alloc',): ret = alloc(0x1000)
    elif name in ('of_find_property',):
        k = key(rs(a[1])); ret = alloc(16) if (k in GPIO or k in U32 or k in STR) else 0
        L('  of_find_property(%s) -> %s' % (rs(a[1]), 'yes' if ret else 'no'))
    elif name == 'of_get_named_gpio_flags':
        k = key(rs(a[1])); ret = GPIO.get(k, -2) & 0xffffffffffffffff
        L('  DT gpio %s -> %d' % (rs(a[1]), s32(ret)))
    elif name in ('of_property_read_u32_array', 'of_property_read_variable_u32_array'):
        k = key(rs(a[1]))
        if k in U32: uc.mem_write(a[2], struct.pack('<%dI' % len(U32[k]), *U32[k])); ret = 0
        else: ret = -22 & 0xffffffffffffffff
        L('  DT u32 %s -> %s' % (rs(a[1]), U32.get(k)))
    elif name in ('of_property_read_string', 'of_property_read_string_helper'):
        k = key(rs(a[1]))
        if k in STR:
            sp = alloc(32, STR[k].encode() + b'\0'); uc.mem_write(a[2], struct.pack('<Q', sp))
            ret = 1 if name.endswith('helper') else 0
        else: ret = -22 & 0xffffffffffffffff
        L('  DT str %s -> %s' % (rs(a[1]), STR.get(k)))
    elif name in ('get_device', 'spi_dev_get', 'kobject_get'): ret = a[0]
    elif name == '__list_add':
        n_, p_, x_ = a[0], a[1], a[2]
        uc.mem_write(x_ + 8, struct.pack('<Q', n_)); uc.mem_write(n_, struct.pack('<QQ', x_, p_)); uc.mem_write(p_, struct.pack('<Q', n_))
    elif name in ('put_device', 'nonseekable_open', 'round_jiffies_up', 'mod_timer', 'del_timer', 'del_timer_sync', 'cancel_work_sync', 'flush_workqueue'): ret = 0
    elif name == 'gpio_to_desc': ret = 0x400000000 + a[0] * 64
    elif name.startswith('gpiod_') or name.startswith('gpio_') or name.startswith('__gpio'):
        g = (a[0] - 0x400000000) // 64 if a[0] >= 0x400000000 else a[0]
        if 'get' in name and 'value' in name:
            ret = gpio_state.get(g, 0); L('  %s(gpio%d) -> %d' % (name, g, ret))
        elif 'set' in name or 'output' in name:
            gpio_state[g] = a[1] & 1; L('  GPIO %d := %d   [%s]' % (g, a[1] & 1, name))
        else: L('  %s(gpio%d)' % (name, g))
    elif name in ('pinctrl_get', 'devm_pinctrl_get'): ret = alloc(64); L('  pinctrl_get')
    elif name == 'pinctrl_lookup_state':
        ret = alloc(64); pins[ret] = rs(a[1]); L('  pinctrl_lookup_state(%s)' % rs(a[1]))
    elif name == 'pinctrl_select_state': L('  PINCTRL -> %s' % pins.get(a[1], '?%x' % a[1]))
    elif name in ('usleep_range',): L('  delay usleep_range(%d,%d)' % (a[0], a[1]))
    elif name in ('msleep', 'msleep_interruptible'): L('  delay msleep(%d)' % a[0])
    elif name in ('__const_udelay', '__udelay', '__delay', 'udelay', 'mdelay'): L('  delay %s(%d)' % (name, a[0]))
    elif name in ('__arch_copy_from_user', '__copy_from_user', '_copy_from_user', 'copy_from_user',
                  '__arch_copy_to_user', '__copy_to_user', '_copy_to_user', 'copy_to_user', '__copy_in_user'):
        uc.mem_write(a[0], bytes(uc.mem_read(a[1], a[2]))); ret = 0
    elif name in ('__class_create', 'class_create', 'device_create', 'kobject_create_and_add', '__alloc_workqueue_key',
                  'alloc_workqueue', 'create_singlethread_workqueue', 'sec_device_create', 'device_create_with_groups',
                  'class_find_device', 'spi_get_drvdata', 'wakeup_source_register', 'wakeup_source_create',
                  'regulator_get', 'devm_regulator_get', 'clk_get', 'devm_clk_get'):
        ret = alloc(0x400); L('  %s -> obj' % name)
    elif QUIET.match(name): ret = 0
    else:
        L('  CALL %s(%x, %x, %x, %x)' % (name, a[0], a[1], a[2], a[3]))
    return ret & 0xffffffffffffffff

def emu_name(n): return n.startswith(PFX) or n in ('fps_spi_clock',)
calls = [0]
def hook(uc, addr, size, _):
    n = addr2name.get(addr)
    if addr == STOP: uc.emu_stop(); return
    if addr < 0x10000: L('  INDIRECT CALL NULL+%x' % addr); uc.reg_write(UC_ARM64_REG_X0, 0); return
    if n is None or emu_name(n): return
    r = stub(n)
    uc.reg_write(UC_ARM64_REG_X0, r)
    uc.reg_write(UC_ARM64_REG_PC, uc.reg_read(UC_ARM64_REG_X30))
uc.hook_add(UC_HOOK_CODE, hook, begin=lo, end=hi)
uc.hook_add(UC_HOOK_CODE, hook, begin=0, end=0x10000)
uc.hook_add(UC_HOOK_CODE, hook, begin=STOP, end=STOP + 4)

def call(fn, *args):
    for i, v in enumerate(args): uc.reg_write(UC_ARM64_REG_X0 + i, v)
    uc.reg_write(UC_ARM64_REG_SP, TI + 0x3f00); uc.reg_write(UC_ARM64_REG_X30, STOP)
    uc.reg_write(UC_ARM64_REG_X17, 0)
    try: uc.reg_write(UC_ARM64_REG_SP_EL0, TI)
    except Exception: pass
    try:
        uc.emu_start(R(syms[fn]), STOP, count=2000000)
    except UcError as ex:
        L('  !! emu error %s at pc=%x (%s)' % (ex, uc.reg_read(UC_ARM64_REG_PC),
                                             addr2name.get(uc.reg_read(UC_ARM64_REG_PC), '?')))
    return uc.reg_read(UC_ARM64_REG_X0)

spi = alloc(0x1000); np_ = alloc(0x400); uc.mem_write(spi + 608, struct.pack('<Q', np_))
L('== probe'); r = call(PFX + 'probe', spi); L('== probe ret %d' % s32(r))
inode = alloc(0x400, struct.pack('<256I', *([152 << 20] * 256))); filp = alloc(0x400)
L('== open'); r = call(PFX + 'open', inode, filp); L('== open ret %d' % s32(r))
CMD = 0x40206a00
def ioc(op, ln=0, speed=0, name=''):
    b = struct.pack('<QQIIHBBB3x', 0, 0, ln & 0xffffffff, speed, 0, 0, 0, op)
    uc.mem_write(USER, b)
    L('== ioctl %s (op 0x%x len %d speed %d)' % (name, op, s32(ln), speed))
    r = call(PFX + 'ioctl', filp, CMD, USER); L('== ret %d' % s32(r))
SEQ = [(0x05, 1, 0, 'POWER_CONTROL 1'), (0x17, 0, 0, 'SET_WAKE_UP_SIGNAL'), (0x06, 0, 12500000, 'SET_SPI_CLOCK'),
       (0x05, 1, 0, 'POWER_CONTROL 1'), (0x05, 0, 0, 'POWER_CONTROL 0'), (0x10, 0, 0, 'DISABLE_SPI_CLOCK'),
       (0x14, -1, 0, 'SET_SENSOR_TYPE -1'), (0x06, 0, 12500000, 'SET_SPI_CLOCK'), (0x05, 1, 0, 'POWER_CONTROL 1'),
       (0x11, 1, 0, 'CPU_SPEEDUP 1'), (0x11, 0, 0, 'CPU_SPEEDUP 0'), (0x05, 0, 0, 'POWER_CONTROL 0'),
       (0x05, 1, 0, 'POWER_CONTROL 1'), (0x04, 0, 0, 'SENSOR_RESET'), (0x04, 0, 0, 'SENSOR_RESET'),
       (0x05, 0, 0, 'POWER_CONTROL 0'), (0x14, -2, 0, 'SET_SENSOR_TYPE -2'), (0x14, 1, 0, 'SET_SENSOR_TYPE 1')]
for op, ln, sp_, nm in SEQ: ioc(op, ln, sp_, nm)
