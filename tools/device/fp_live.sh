#!/system/bin/sh
# Runs on the phone as root (tools/device/capture_cam_fp.ps1): fingerprint SPI bus state while the fingerprint HAL starts.
# Output: /data/local/tmp/fp_live/{state,samples,dmesg}.txt
O=/data/local/tmp/fp_live; rm -rf $O; mkdir -p $O
# microphone (run soon after boot, before the log rotates): audio HAL / Samsung audio extension / policy input setup
logcat -b all -d | grep -E 'audio_hw_primary|sec_audio_hw|audio_hw_sec|S8AudioShim|APM_AudioPolicyManager: (initialize|.*[Ii]nput)|AudioFlinger.*[Ii]nput|MultiRecordManager|msm8974_platform.*(in_snd|input|fail|error)' > $O/audio_boot.txt 2>&1
dumpsys media.audio_policy > $O/audio_policy.txt 2>&1
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
# NEVER read /sys/kernel/debug/gpio or pinctrl pinmux-pins/pinconf-pins here: they read every TLMM register, and the
# TZ-owned ones (BLSP12 fingerprint SPI GPIO81-84 in secure mode) raise a secure access fault -> instant hard reset
# (camfp_20261008_024921). Clock enable counts / rates are plain kernel bookkeeping and safe.
{
  for c in /sys/kernel/debug/clk/*blsp2*; do echo "$c: $(cat $c/enable_count 2>/dev/null) $(cat $c/rate 2>/dev/null)"; done
  echo "gpio74 (fps LDO) value: $(cat /sys/class/gpio/gpio74/value 2>/dev/null || echo n/a)"
  for f in type_check name vendor adm; do echo "$f: $(cat /sys/class/fingerprint/fingerprint/$f 2>&1)"; done
  echo "type_check.dat: $(od -An -tx1 /data/vendor/biometrics/type/type_check.dat 2>&1)"
  ls -l /dev/fps* /dev/esfp0 /dev/vfsspi /dev/etspi* 2>&1
} > $O/state.txt 2>&1
dmesg -C
setprop ctl.restart vendor.fps_hal
i=0
while [ $i -lt 40 ]; do
  {
    echo "== $(cat /proc/uptime | cut -d' ' -f1)"
    for c in /sys/kernel/debug/clk/*blsp2_qup6* /sys/kernel/debug/clk/*blsp2_ahb*; do echo "$c $(cat $c/enable_count 2>/dev/null)"; done
  } >> $O/samples.txt 2>&1
  sleep 0.25
  i=$((i + 1))
done
sleep 3
dmesg > $O/dmesg.txt
chmod -R 755 $O
echo FP_LIVE_DONE
