#!/system/bin/sh
# Runs on the phone as root. Captures the QSEE (TrustZone app) log while the fingerprint HAL re-probes the sensor,
# so we see what the "dualfp" TA itself reports for its sensor detection (cgst / FP cmd 0x10).
# Safe reads only: tzdbg (TZ shared log buffer), regulator sysfs. NO /sys/kernel/debug/gpio or pinctrl reads
# (those reset the phone: TZ-owned BLSP12 pins). Run detached:
#   adb shell "su -c 'nohup sh /data/local/tmp/fp_tz_test.sh >/dev/null 2>&1 &'"
# then ~70 s later check that /data/local/tmp/fp_tz/DONE exists and pull /data/local/tmp/fp_tz.
O=/data/local/tmp/fp_tz; rm -rf $O; mkdir -p $O
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
T=/sys/kernel/debug/tzdbg
ls -l $T > $O/tzdbg_ls.txt 2>&1
# drain what is already in the QSEE log so the capture below starts at the HAL restart
[ -r $T/qsee_log ] && timeout 3 cat $T/qsee_log > $O/qsee_before.txt 2>&1
# background reader: qsee_log returns new data on every read
( i=0; while [ $i -lt 55 ]; do timeout 2 cat $T/qsee_log >> $O/qsee_log.txt 2>&1; sleep 1; i=$((i+1)); done ) &
R=$!
rm -f /data/vendor/biometrics/type/type_check.dat /data/vendor/biometrics/meta/calib.dat
dmesg -c > /dev/null
logcat -c
setprop ctl.restart vendor.fps_hal
sleep 3
setprop ctl.restart zygote
sleep 50
wait $R
timeout 3 cat $T/log > $O/tz_log.txt 2>&1
dmesg > $O/dmesg.txt
logcat -d | grep -E 'bauth|FPLOG|fingerprint|etspi|common_prepare|SNSR|QSEECOM' > $O/hal.txt
for r in /sys/class/regulator/regulator.*; do
  echo "$(cat $r/name 2>/dev/null) state=$(cat $r/state 2>/dev/null) uV=$(cat $r/microvolts 2>/dev/null) users=$(cat $r/num_users 2>/dev/null)"
done > $O/regulators.txt
{
  echo "type_check.dat: $(cat /data/vendor/biometrics/type/type_check.dat 2>&1)"
  echo "model: $(cat /proc/device-tree/model)"
  echo "fps node:"; ls /proc/device-tree/soc/spi@c1ba000/fps-spi@0 2>&1
  echo "cmdline:"; tr ' ' '\n' < /proc/cmdline | grep -iE 'rev|hw_|board'
} > $O/actions.txt
chmod -R 755 $O
touch $O/DONE
