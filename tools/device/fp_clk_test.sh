#!/system/bin/sh
# Runs on the phone as root. Experiment: does the S8 fingerprint TA find the ET510 when HLOS keeps the BLSP2 QUP6
# (BLSP12) SPI + AHB clocks on (what the S8 Pie G9500 et5xx did on FP_SET_SPI_CLOCK)?
# Only clock enable votes through debugfs - NO gpio/pinctrl debugfs reads (those reset the phone: TZ-owned pins).
# The fingerprint HAL only opens the sensor when system_server attaches (setNotify), so after restarting the HAL the
# framework is soft-restarted (zygote; kernel and the clock votes stay). Run detached:
#   adb shell "su -c 'nohup sh /data/local/tmp/fp_clk_test.sh >/dev/null 2>&1 &'"
# then ~60 s later pull /data/local/tmp/fp_clk (DONE file marks completion). A reboot undoes everything.
O=/data/local/tmp/fp_clk; rm -rf $O; mkdir -p $O
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
C=/sys/kernel/debug/clk
for c in gcc_blsp2_ahb_clk gcc_blsp2_qup6_spi_apps_clk; do
  echo "$c before: enable=$(cat $C/$c/enable) rate=$(cat $C/$c/rate)" >> $O/actions.txt
  echo 1 > $C/$c/enable
  echo "$c after:  enable=$(cat $C/$c/enable) rate=$(cat $C/$c/rate)" >> $O/actions.txt
done
# forget the cached "Fail" sensor type / calibration, restart the HAL, then the framework so it re-attaches
rm -f /data/vendor/biometrics/type/type_check.dat /data/vendor/biometrics/meta/calib.dat
dmesg -c > /dev/null
logcat -c
setprop ctl.restart vendor.fps_hal
sleep 3
setprop ctl.restart zygote
sleep 45
dmesg > $O/dmesg.txt
logcat -d | grep -E 'bauth|FPLOG|fingerprint|etspi|common_prepare|SNSR' > $O/hal.txt
{ echo "type_check.dat: $(cat /data/vendor/biometrics/type/type_check.dat 2>&1)"; dumpsys fingerprint; } >> $O/actions.txt 2>&1
for c in gcc_blsp2_ahb_clk gcc_blsp2_qup6_spi_apps_clk; do echo "$c end: enable=$(cat $C/$c/enable)" >> $O/actions.txt; done
chmod -R 755 $O
touch $O/DONE
