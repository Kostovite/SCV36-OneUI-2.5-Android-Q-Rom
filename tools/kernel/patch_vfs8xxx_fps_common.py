#!/usr/bin/env python3
"""Kernel patch (server tree): drive the SCV36 fingerprint sensor with the Q-tree Synaptics driver
(drivers/fingerprint/vfs8xxx.c, /dev/vfsspi, VFSSPI 'k' ioctls).
Why: this unit's sensor is a Synaptics NAMSAN, not the Egis ET510 the JPN DT names (fps-chipid = "ET510").
Proven 2026-10-09 by booting One UI 2 once on the stock SCV36 kernel (debug/fp_stockkernel): the stock "fps,common"
driver reports name/vendor NAMSAN/SYNAPTICS, the S8 bauth HAL then probes Synaptics types ("5, 7") through
/dev/vfsspi, the TA's cgst returns 5 and dumpsys shows "FwVersion 08.00.182 ... Module Test : Pass". With our Egis
ET5XX driver (name ET510) the HAL only probes Egis types ("3, 6") -> cgst 0 -> "FP Sensor is out of order".
Changes:
  - match "fps,common" (stock dreamq DT node); every vfsspi-<x> property falls back to fps-<x>
  - sysfs name = "NAMSAN" (stock fps_name_show default; the DT chipid string is wrong for this unit)
usage: python3 patch_vfs8xxx_fps_common.py <kernel tree>"""
import re, sys

f = sys.argv[1] + '/drivers/fingerprint/vfs8xxx.c'
s = open(f, newline='').read()
if 'fps,common' in s:
    print('already patched'); sys.exit(0)


def sub1(old, new):
    global s
    assert s.count(old) == 1, 'pattern count %d: %r' % (s.count(old), old[:60])
    s = s.replace(old, new)


sub1('''	{.compatible = "vfsspi,vfs8xxx",},
	{},''', '''	{.compatible = "vfsspi,vfs8xxx",},
	{.compatible = "fps,common",},	/* S8 dreamq JPN stock DT node */
	{},''')

sub1('static int vfsspi_parse_dt(struct device *dev, struct vfsspi_device_data *data)',
     '''/* S8 (dreamq JPN) DT uses the Samsung "fps,common" binding: fps-<x> instead of vfsspi-<x> property names */
static const char *vfsspi_prop(struct device_node *np, const char *name)
{
	static char buf[64];

	if (strncmp(name, "vfsspi-", 7) || of_find_property(np, name, NULL))
		return name;
	snprintf(buf, sizeof(buf), "fps-%s", name + 7);
	return buf;
}

static int vfsspi_parse_dt(struct device *dev, struct vfsspi_device_data *data)''')
a = s.index('static int vfsspi_parse_dt(struct device *dev, struct vfsspi_device_data *data)')
b = s.index('\n}\n', a)
body, n = re.subn(r'\(np, "(vfsspi-[A-Za-z_]+)"', r'(np, vfsspi_prop(np, "\1")', s[a:b])
assert n >= 9, n
s = s[:a] + body + s[b:]
print('parse_dt: %d property lookups with fps- fallback' % n)

sub1('''	return sprintf(buf, "%s\\n", g_data->chipid);''',
     '''	/* as the stock SCV36 fps,common driver: report the Synaptics part (DT chipid says ET510) */
	return sprintf(buf, "%s\\n", "NAMSAN");''')

open(f, 'w', newline='').write(s)
print('patched', f)
