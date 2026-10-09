#!/usr/bin/env python3
"""Kernel patch (server tree), stage 3 after patch_et5xx_ldo_reset.py: accept the S8 Pie bauth ioctl magic.
Boot 17/18: the G9600 libbauthserver reaches the S8 fingerprint TA but its sensor init fails (common_prepare fail,
"FP Sensor is out of order"); the S8 Pie libbauthserver (built against the S8 TA) failed at the first ioctl
("BAuthDeviceOpen sys call failed rv : 209"). Disassembly of both libs: identical egis_ioc_transfer layout, opcodes
and error codes - only the ioctl magic differs: S8 Pie 0x40206a00 = _IOW('j', 0, 32), G9600/Q driver 'k' (0x6b).
-> the Q ET5xx driver accepts both magics (the request is otherwise decoded by _IOC_NR/_IOC_SIZE only).
usage: python3 patch_et5xx_ioc_magic.py <kernel tree>"""
import sys

f = sys.argv[1] + '/drivers/fingerprint/et5xx-spi.c'
s = open(f, newline='').read()
assert 'S8: no reset pin' in s, 'run patch_et5xx_ldo_reset.py first'
if 'EGIS_IOC_MAGIC_S8' in s:
    print('already patched'); sys.exit(0)

old = 'if (_IOC_TYPE(cmd) != EGIS_IOC_MAGIC) {'
assert s.count(old) == 1, 'pattern count %d' % s.count(old)
s = s.replace(old, '''/* S8 Pie libbauthserver uses magic 'j' (same transfer struct / opcodes as the 'k' Q userspace) */
#define EGIS_IOC_MAGIC_S8 'j'
	if (_IOC_TYPE(cmd) != EGIS_IOC_MAGIC && _IOC_TYPE(cmd) != EGIS_IOC_MAGIC_S8) {''')
open(f, 'w', newline='').write(s)
print('patched', f)
