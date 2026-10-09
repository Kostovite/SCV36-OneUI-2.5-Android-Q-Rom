#!/usr/bin/env python3
"""Kernel patch (server tree), stage 4 after patch_et5xx_ioc_magic.py: mux the fingerprint SPI pins for TrustZone.
Boot 19: S8 bauth stack + S8 TA "dualfp" load and talk to the driver (power, wake-up, FP_SET_SPI_CLOCK ok), but every
sensor command in the TA fails (common_prepare fail opcode 8/9 -> "FP Sensor is out of order") - same as with the
G9600 stack. The ET510 sits on BLSP12 SPI (spi@c1ba000, qcom,use-pinctrl): HLOS spi_qsd leaves GPIO81-84 in
"spi_sleep" = function "gpio" because it never transfers itself; only "spi_default" muxes them to blsp_spi12. In
secure mode the TA drives BLSP12 directly, so the REE driver must select the active pin state - spi_qsd exports
fp_spi_request_gpios() for exactly this, but the Q ET5xx driver never calls it.
-> FP_SET_SPI_CLOCK: after the clocks are on, fp_spi_request_gpios() (idempotent; re-run on every clock enable,
   which also covers resume from suspend).
usage: python3 patch_et5xx_spi_pins.py <kernel tree>"""
import sys

f = sys.argv[1] + '/drivers/fingerprint/et5xx-spi.c'
s = open(f, newline='').read()
assert 'EGIS_IOC_MAGIC_S8' in s, 'run patch_et5xx_ioc_magic.py first'
if 'fp_spi_request_gpios(spi)' in s:
    print('already patched'); sys.exit(0)

old = '''			retval = fp_spi_clock_enable(spi);
			if (retval < 0)
				pr_err("%s: Unable to enable spi clk\\n",
					__func__);
		}'''
assert s.count(old) == 1, 'pattern count %d' % s.count(old)
s = s.replace(old, '''			retval = fp_spi_clock_enable(spi);
			if (retval < 0)
				pr_err("%s: Unable to enable spi clk\\n",
					__func__);
			/* S8: TZ drives BLSP12 itself - mux GPIO81-84 to blsp_spi12 (spi_qsd leaves them "gpio") */
			else if (fp_spi_request_gpios(spi) < 0)
				pr_err("%s: Unable to set spi pins active\\n", __func__);
		}''')
open(f, 'w', newline='').write(s)
print('patched', f)
