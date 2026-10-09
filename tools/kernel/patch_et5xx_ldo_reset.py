#!/usr/bin/env python3
"""Kernel patch (server tree), stage 2 after patch_et5xx_fps_common.py: reset + power for boards without a reset pin.
Boot 16 (G9600 fingerprint@3.0 HAL on the S8): the S8 fingerprint TA loads and answers, but the sensor init fails
("controlOp : common_prepare fail" x6 -> "FP Sensor is out of order"). The S9 board (same Egis ET510) has
etspi-sleepPin = the sensor reset line and its HAL resets the sensor through FP_SENSOR_RESET; on S8 Rev11/12 the reset
is tied to the sensor supply (DT has only fps-ldoPin), so with no sleepPin a reset was a no-op.
  - etspi_reset(): no sleepPin -> power-cycle the LDO (that is the S8's reset)
  - probe (secure mode, no sleepPin): power the sensor on, so it answers even if the HAL never asks for power
usage: python3 patch_et5xx_ldo_reset.py <kernel tree>"""
import sys

f = sys.argv[1] + '/drivers/fingerprint/et5xx-spi.c'
s = open(f, newline='').read()
assert 'fps,common' in s, 'run patch_et5xx_fps_common.py first'
if 'S8: no reset pin' in s:
    print('already patched'); sys.exit(0)


def sub1(old, new):
    global s
    assert s.count(old) == 1, 'pattern count %d: %r' % (s.count(old), old[:60])
    s = s.replace(old, new)


# etspi_power_control is defined after etspi_reset -> forward declaration
sub1('''static void etspi_reset(struct etspi_data *etspi)
{
	pr_info("%s\\n", __func__);

	if (!etspi->sleepPin)
		return;''', '''static void etspi_power_control(struct etspi_data *etspi, int status);

static void etspi_reset(struct etspi_data *etspi)
{
	pr_info("%s\\n", __func__);

	if (!etspi->sleepPin) {
		/* S8: no reset pin - the ET510 reset follows its supply, so a reset is a power cycle */
		if (etspi->ldo_pin) {
			etspi_power_control(etspi, 0);
			usleep_range(5000, 5050);
			etspi_power_control(etspi, 1);
			etspi->reset_count++;
		}
		return;
	}''')
sub1('''#ifdef ENABLE_SENSORS_FPRINT_SECURE
	etspi->tz_mode = true;
#endif''', '''#ifdef ENABLE_SENSORS_FPRINT_SECURE
	etspi->tz_mode = true;
	/* S8: no reset pin - keep the sensor powered from probe on (the S9 HAL expects a live sensor) */
	if (!etspi->sleepPin && etspi->ldo_pin)
		etspi_power_control(etspi, 1);
#endif''')
open(f, 'w', newline='').write(s)
print('patched', f)
