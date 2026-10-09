#!/system/bin/sh
# Runs on the phone as root (tools/device/capture_power.ps1): sleep / wakeup / crash-loop state for battery-drain analysis.
# Output: /data/local/tmp/power/*.txt
O=/data/local/tmp/power; rm -rf $O; mkdir -p $O
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
D=/sys/kernel/debug
{
  echo "== cmdline"; cat /proc/cmdline
  echo "== uptime / suspend"; cat /proc/uptime; cat /sys/power/state /sys/power/mem_sleep /sys/power/autosleep 2>&1
  echo "== lpm_levels params"; for f in /sys/module/lpm_levels/parameters/*; do echo "$f = $(cat $f 2>&1)"; done
  echo "== lpm_levels idle_enabled/suspend_enabled"
  find /sys/module/lpm_levels/system -name '*_enabled' 2>/dev/null | while read -r f; do echo "$f = $(cat $f)"; done
  echo "== post_boot ran?"; getprop | grep -iE 'post_boot|sku|vendor.perf|ro.vendor.qti.soc|ro.board.platform|init.svc.qcom-post-boot|sys.boot_completed'
  echo "== cpufreq"; for c in /sys/devices/system/cpu/cpu[0-7]; do echo "$c: online=$(cat $c/online 2>/dev/null) gov=$(cat $c/cpufreq/scaling_governor 2>&1) min=$(cat $c/cpufreq/scaling_min_freq 2>&1) max=$(cat $c/cpufreq/scaling_max_freq 2>&1) cur=$(cat $c/cpufreq/scaling_cur_freq 2>&1)"; done
  echo "== cpuidle"; for c in /sys/devices/system/cpu/cpu[0-7]/cpuidle/state*; do echo "$c $(cat $c/name) usage=$(cat $c/usage) time=$(cat $c/time) disable=$(cat $c/disable 2>/dev/null)"; done
  echo "== kgsl"; for f in governor min_pwrlevel max_pwrlevel default_pwrlevel force_clk_on force_rail_on force_bus_on idle_timer; do echo "$f = $(cat /sys/class/kgsl/kgsl-3d0/$f 2>&1)"; done
} > $O/config.txt 2>&1
{
  echo "== rpm / system sleep stats (deep sleep counters: vmin / vlow)"
  cat /sys/power/system_sleep/stats 2>&1; cat /sys/power/rpmh_stats/master_stats 2>/dev/null
  cat $D/rpm_stats 2>/dev/null; cat $D/rpm_master_stats 2>/dev/null; cat /sys/power/rpm_master_stats 2>/dev/null
  echo "== suspend_stats"; cat $D/suspend_stats 2>&1
  echo "== lpm stats"; cat $D/lpm_stats/stats 2>/dev/null | head -150
} > $O/sleep_stats.txt 2>&1
cat $D/wakeup_sources > $O/wakeup_sources.txt 2>&1
# sort by total wake time (column 7 = total_time) for a quick view
awk 'NR>1{print $7, $1, "active_count="$2, "max="$8, "prevent_suspend="$10}' $O/wakeup_sources.txt | sort -rn | head -40 > $O/wakeup_top.txt
cat /proc/interrupts > $O/interrupts.txt
dmesg > $O/dmesg.txt
grep -E "init: (Service|Untracked pid|starting service)|exited with status|killed by signal|crashed" $O/dmesg.txt | \
  sed -E 's/^\[ *[0-9.]+\] //; s/pid [0-9]+/pid N/; s/\([0-9]+\)/(N)/' | sort | uniq -c | sort -rn | head -60 > $O/init_service_churn.txt
top -b -n 2 -d 3 -m 25 > $O/top.txt 2>&1
dumpsys batterystats > $O/batterystats.txt 2>&1
dumpsys batterystats --checkin > $O/batterystats_checkin.txt 2>&1
dumpsys power > $O/power.txt 2>&1
dumpsys deviceidle > $O/deviceidle.txt 2>&1
dumpsys alarm > $O/alarm.txt 2>&1
dumpsys cpuinfo > $O/cpuinfo.txt 2>&1
dumpsys battery > $O/battery.txt 2>&1
# microphone check (S8 audio wrapper): available input devices + opened inputs
{ dumpsys media.audio_policy; echo "=== audio_flinger"; dumpsys media.audio_flinger; } > $O/audio.txt 2>&1
logcat -b all -d | grep -E 'sec_dev_open_audio_stream|S8AudioShim|Input device list|adev_open_input_stream' > $O/audio_wrapper.txt 2>&1
for t in system_app_crash data_app_crash system_app_native_crash data_app_native_crash SYSTEM_TOMBSTONE system_app_anr data_app_anr system_server_wtf system_app_wtf SYSTEM_RESTART; do
  echo "=== $t"; dumpsys dropbox --print $t 2>&1 | grep -E '^[0-9]{4}-|^Process:|^Package:|^java\.|^Caused by|^pid:|>>>|^signal|^Abort|^Subject' | head -120
done > $O/crashes.txt
ls -l /data/tombstones /data/anr > $O/tombstones_list.txt 2>&1
logcat -b crash -d > $O/logcat_crash.txt 2>&1
logcat -b all -d > $O/logcat_all.txt 2>&1
chmod -R 755 $O
echo POWER_DUMP_DONE
