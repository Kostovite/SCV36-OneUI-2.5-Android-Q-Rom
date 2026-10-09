#!/usr/bin/env python3
"""Make the Q et5xx power / reset sequence identical to the stock SCV36 fps_* driver (verified by differential
emulation of both kernels, tools/analysis/fpemu.py):
  stock fps_power_control(1): LDO=1, pinctrl idle, usleep 1600, (sleepPin), usleep 12000
  stock fps_power_control(0): LDO=0, pinctrl sleep
  stock fps_reset (no sleepPin): LDO=0, usleep 1100, LDO=1, usleep 12000 (no pinctrl change)
usage: patch_et5xx_stock_timing.py <kernel tree>"""
import sys
p = sys.argv[1] + '/drivers/fingerprint/et5xx-spi.c'
s = open(p).read()

old_reset = """		if (etspi->ldo_pin) {
			etspi_power_control(etspi, 0);
			usleep_range(5000, 5050);
			etspi_power_control(etspi, 1);
			etspi->reset_count++;
		}
		return;"""
new_reset = """		if (etspi->ldo_pin) {
			/* as stock SCV36 fps_reset: LDO toggle only, pins untouched */
			gpio_set_value(etspi->ldo_pin, 0);
			usleep_range(1100, 1150);
			gpio_set_value(etspi->ldo_pin, 1);
			usleep_range(12000, 12050);
			etspi->reset_count++;
		}
		return;"""

old_pc = """		if (etspi->ldo_pin)
			gpio_set_value(etspi->ldo_pin, 1);
		usleep_range(50, 100);
		if (etspi->sleepPin)
			gpio_set_value(etspi->sleepPin, 1);
		etspi_pin_control(etspi, true);
		usleep_range(10000, 10050);
	} else if (status == 0) {
		etspi_pin_control(etspi, false);
		if (etspi->sleepPin)
			gpio_set_value(etspi->sleepPin, 0);
		if (etspi->ldo_pin)
			gpio_set_value(etspi->ldo_pin, 0);"""
new_pc = """		/* as stock SCV36 fps_power_control: LDO, idle pins, 1.6 ms, sleepPin, 12 ms */
		if (etspi->ldo_pin)
			gpio_set_value(etspi->ldo_pin, 1);
		etspi_pin_control(etspi, true);
		usleep_range(1600, 1650);
		if (etspi->sleepPin)
			gpio_set_value(etspi->sleepPin, 1);
		usleep_range(12000, 12050);
	} else if (status == 0) {
		if (etspi->sleepPin)
			gpio_set_value(etspi->sleepPin, 0);
		if (etspi->ldo_pin)
			gpio_set_value(etspi->ldo_pin, 0);
		etspi_pin_control(etspi, false);"""

if new_reset in s and new_pc in s:
    print('already patched'); sys.exit(0)
for o in (old_reset, old_pc):
    if s.count(o) != 1: sys.exit('pattern not found exactly once:\n' + o)
s = s.replace(old_reset, new_reset).replace(old_pc, new_pc)
open(p, 'w').write(s)
print('patched', p)
