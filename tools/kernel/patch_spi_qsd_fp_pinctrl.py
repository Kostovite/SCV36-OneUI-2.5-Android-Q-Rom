#!/usr/bin/env python3
"""Kernel patch (server tree), with patch_et5xx_spi_pins.py: make spi_qsd's fp_spi_request_gpios() usable before the
controller was ever resumed.
Boot 20 panicked (debug partition klog): etspi_ioctl -> fp_spi_request_gpios -> pinctrl_select_state(NULL)
"Unable to handle kernel NULL pointer". spi_qsd fetches its pinctrl handle in init_resources(), which only runs on the
first runtime resume of the master - never, when TrustZone owns the bus (HLOS does no transfers). -> initialise the
pinctrl handle on demand there, and return an error instead of dereferencing NULL.
usage: python3 patch_spi_qsd_fp_pinctrl.py <kernel tree>"""
import sys

f = sys.argv[1] + '/drivers/spi/spi_qsd.c'
s = open(f, newline='').read()
if 'S8 fp: pinctrl on demand' in s:
    print('already patched'); sys.exit(0)

start = s.index('int fp_spi_request_gpios(struct spi_device *spidev)')
old = '''	} else {
		result = pinctrl_select_state(dd->pinctrl, dd->pins_active);'''
i = s.index(old, start)
assert i < s.index('EXPORT_SYMBOL_GPL(fp_spi_request_gpios);'), 'pattern outside fp_spi_request_gpios'
s = s[:i] + '''	} else {
		/* S8 fp: pinctrl on demand - init_resources() only runs on the master's first runtime resume, which never
		 * happens while TrustZone owns the bus */
		if (IS_ERR_OR_NULL(dd->pinctrl) || IS_ERR_OR_NULL(dd->pins_active)) {
			result = msm_spi_pinctrl_init(dd);
			if (result || IS_ERR_OR_NULL(dd->pins_active)) {
				dev_err(dd->dev, "%s: pinctrl init failed %d\\n", __func__, result);
				return result ? result : -ENODEV;
			}
		}
		result = pinctrl_select_state(dd->pinctrl, dd->pins_active);''' + s[i + len(old):]
open(f, 'w', newline='').write(s)
print('patched', f)
