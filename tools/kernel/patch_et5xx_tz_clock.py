#!/usr/bin/env python3
"""Kernel patch (server tree), from reverse engineering the stock SCV36 Pie kernel (KDI CZE1, CONFIG_KALLSYMS_ALL,
symbolised with vmlinux-to-elf; unpublished CONFIG_SENSORS_VFS8XXX_EGIS "fps,common" driver, fps_ioctl @ffffff8009051bd4):
  Egis 'j' FP_SET_SPI_CLOCK (0x06): stores spi->max_speed_hz and holds the wakelock - NO fp_spi_clock_set_rate /
      fp_spi_clock_enable ("already enabled same clock" / "already enabled. DISABLE_SPI_CLOCK" only relax+re-take
      the wakelock);
  Egis 'j' FP_DISABLE_SPI_CLOCK (0x10): wakelock release only.
  Nothing in the stock kernel calls fp_spi_clock_set_rate/enable/disable or fp_spi_request_gpios (only msm_spi_probe
  calls fp_spi_clock_get): the S8 TrustZone fingerprint TA programs BLSP12 (clocks + pins) itself.
The S9 Q et5xx driver re-rates the BLSP12 core clock to 12.5 MHz and gates it again on FP_DISABLE_SPI_CLOCK (boot 22:
gated at 17.96 s, during the TA's sensor bring-up) -> every TA sensor transaction fails (common_prepare, sensor type
unknown). -> make both ioctls behave like stock.
usage: python3 patch_et5xx_tz_clock.py <kernel tree>"""
import sys

f = sys.argv[1] + '/drivers/fingerprint/et5xx-spi.c'
s = open(f, newline='').read()
if 'S8 stock: TZ owns the BLSP12 clocks' in s:
    print('already patched'); sys.exit(0)


def cut(start_marker, end_marker):
    a = s.index(start_marker); b = s.index(end_marker, a)
    return a, b


# FP_SET_SPI_CLOCK: secure branch
a, b = cut('#ifdef ENABLE_SENSORS_FPRINT_SECURE\n\t\tif (etspi->enabled_clk) {\n\t\t\tif (spi->max_speed_hz == ioc->speed_hz)',
           '#else\n\t\tspi->max_speed_hz = ioc->speed_hz;\n#endif')
assert s[a:b].count('fp_spi_clock_enable') == 1
s = s[:a] + '''#ifdef ENABLE_SENSORS_FPRINT_SECURE
		/* S8 stock: TZ owns the BLSP12 clocks - only the speed and the wakelock here (stock fps_ioctl) */
		if (etspi->enabled_clk) {
			if (spi->max_speed_hz == ioc->speed_hz) {
				pr_info("%s already enabled same clock.\\n", __func__);
				break;
			}
			pr_info("%s already enabled. DISABLE_SPI_CLOCK\\n", __func__);
			wake_unlock(&etspi->fp_spi_lock);
			etspi->enabled_clk = false;
		}
		spi->max_speed_hz = ioc->speed_hz;
		wake_lock(&etspi->fp_spi_lock);
		etspi->enabled_clk = true;
''' + s[b:]

# FP_DIABLE_SPI_CLOCK: wakelock only
a, b = cut('\tcase FP_DIABLE_SPI_CLOCK:', '\t\tbreak;')
blk = s[a:b]
assert 'fp_spi_clock_disable' in blk, blk
s = s[:a] + '''	case FP_DIABLE_SPI_CLOCK:
		pr_info("%s FP_DISABLE_SPI_CLOCK\\n", __func__);
		if (etspi->enabled_clk) {	/* S8 stock: no clock gating from HLOS */
			pr_info("%s DISABLE_SPI_CLOCK\\n", __func__);
			wake_unlock(&etspi->fp_spi_lock);
			etspi->enabled_clk = false;
		}
''' + s[b:]
assert s.count('fp_spi_clock_enable(') == 0 or 'fp_spi_clock_enable(' not in s.split('etspi_ioctl')[1].split('\n}\n')[0], \
    'clock enable still in ioctl'
open(f, 'w', newline='').write(s)
print('patched', f)
