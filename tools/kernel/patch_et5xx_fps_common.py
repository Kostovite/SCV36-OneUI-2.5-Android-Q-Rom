#!/usr/bin/env python3
"""Kernel patch (server tree): let the Q-tree Egis ET5xx driver (drivers/fingerprint/et5xx-spi.c) drive the S8 JPN
ET510 sensor described by the stock dreamq DT node:
    fps-spi@0 { compatible = "fps,common"; fps-ldoPin; fps-drdyPin; fps-orient; fps-min_cpufreq_limit;
                fps-chipid = "ET510"; pinctrl default/sleep/idle }   (Rev11/Rev12: no fps-sleepPin)
The stock SCV36 kernel bound it with an unpublished SENSORS_VFS8XXX_EGIS "common" driver. The Q driver only knows
"etspi,et5xx" + etspi-* property names and requires a sleep (reset) pin. Changes:
  - match "fps,common"; every etspi-<x> DT property falls back to fps-<x>
  - sleepPin optional (0 = absent): never requested/toggled when the board has none
The device node stays /dev/esfp0 (what libbauthserver opens; ueventd + SELinux fp_sensor_device already set up).
usage: python3 patch_et5xx_fps_common.py <kernel tree>"""
import re, sys

f = sys.argv[1] + '/drivers/fingerprint/et5xx-spi.c'
s = open(f, newline='').read()
if 'fps,common' in s:
    print('already patched'); sys.exit(0)


def sub1(old, new):
    global s
    assert s.count(old) == 1, 'pattern count %d: %r' % (s.count(old), old[:60])
    s = s.replace(old, new)


# 1) property-name fallback helper + use it everywhere inside etspi_parse_dt()
sub1('static int etspi_parse_dt(struct device *dev,', '''/* S8 (dreamq JPN) DT uses the Samsung "fps,common" binding: fps-<x> instead of etspi-<x> property names */
static const char *etspi_prop(struct device_node *np, const char *name)
{
	static char buf[64];

	if (strncmp(name, "etspi-", 6) || of_find_property(np, name, NULL))
		return name;
	snprintf(buf, sizeof(buf), "fps-%s", name + 6);
	return buf;
}

static int etspi_parse_dt(struct device *dev,''')
a = s.index('static int etspi_parse_dt(struct device *dev,')
b = s.index('\n}\n', a)
body = s[a:b]
body, n = re.subn(r'\(np, "(etspi-[A-Za-z_]+)"', r'(np, etspi_prop(np, "\1")', body)
assert n >= 6, n
# 2) sleepPin optional (first gpio lookup in parse_dt)
old_sleep = '''	if (gpio < 0) {
		errorno = gpio;
		goto dt_exit;
	} else {
		data->sleepPin = gpio;'''
assert body.count(old_sleep) == 1
body = body.replace(old_sleep, '''	if (gpio < 0) {
		data->sleepPin = 0;
		pr_info("%s: no sleepPin (S8 fps,common)\\n", __func__);
	} else {
		data->sleepPin = gpio;''')
s = s[:a] + body + s[b:]
print('parse_dt: %d property lookups with fps- fallback' % n)

# 3) every sleepPin use guarded
sub1('''	gpio_set_value(etspi->sleepPin, 0);
	usleep_range(1050, 1100);
	gpio_set_value(etspi->sleepPin, 1);''', '''	if (!etspi->sleepPin)
		return;
	gpio_set_value(etspi->sleepPin, 0);
	usleep_range(1050, 1100);
	gpio_set_value(etspi->sleepPin, 1);''')
sub1('''		status = gpio_request(etspi->sleepPin, "etspi_sleep");
		if (status < 0) {
			pr_err("%s gpio_requset etspi_sleep failed\\n",
				__func__);
			goto etspi_platformInit_sleep_failed;
		}

		status = gpio_direction_output(etspi->sleepPin, 0);
		if (status < 0) {
			pr_err("%s gpio_direction_output SLEEP failed\\n", __func__);
			status = -EBUSY;
			goto etspi_platformInit_sleep_failed;
		}
''', '''		if (etspi->sleepPin) {
			status = gpio_request(etspi->sleepPin, "etspi_sleep");
			if (status < 0) {
				pr_err("%s gpio_requset etspi_sleep failed\\n",
					__func__);
				goto etspi_platformInit_sleep_failed;
			}

			status = gpio_direction_output(etspi->sleepPin, 0);
			if (status < 0) {
				pr_err("%s gpio_direction_output SLEEP failed\\n", __func__);
				status = -EBUSY;
				goto etspi_platformInit_sleep_failed;
			}
		}
''')
sub1('''etspi_platformInit_drdy_failed:
	gpio_free(etspi->sleepPin);''', '''etspi_platformInit_drdy_failed:
	if (etspi->sleepPin)
		gpio_free(etspi->sleepPin);''')
sub1('''			gpio_free(etspi->ldo_pin);
		gpio_free(etspi->sleepPin);
		gpio_free(etspi->drdyPin);''', '''			gpio_free(etspi->ldo_pin);
		if (etspi->sleepPin)
			gpio_free(etspi->sleepPin);
		gpio_free(etspi->drdyPin);''')
left = [m.start() for m in re.finditer(r'gpio_(set_value|free|request|direction_output)\(etspi->sleepPin', s)]
print('sleepPin call sites:', len(left))

# 4) DT match
sub1('	{ .compatible = "etspi,et5xx",},', '	{ .compatible = "etspi,et5xx",},\n	{ .compatible = "fps,common",},')
open(f, 'w', newline='').write(s)
print('patched', f)
