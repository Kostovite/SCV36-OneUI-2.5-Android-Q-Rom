#!/usr/bin/env bash
# Build the Tab S4 Android 10 msm8998 kernel with the stock SCV36 config, Samsung lock-down features off.
# Runs on WSL or the build server. Env overrides:
#   ROOT   (default ~/s8rom)            kernel tree at $ROOT/kernel/t830_q, toolchain at $ROOT/toolchains
#   CFG    (default stock kernel.config) starting config
#   OUTCFG (optional)                    copy the final .config here
# Output: $ROOT/kernel/out_dream/arch/arm64/boot/Image.gz
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
ROOT=${ROOT:-~/s8rom}
K=$ROOT/kernel/t830_q
O=$ROOT/kernel/out_dream
CFG=${CFG:-$P/work/stock_CZE1/boot.img_unpacked/kernel.config}
TC=$ROOT/toolchains/aarch64-linux-android-4.9/bin
export PATH=$ROOT/bin:$PATH   # provides 'python' for the AOSP gcc wrapper when the host lacks it
export ARCH=arm64 SUBARCH=arm64 CROSS_COMPILE=$TC/aarch64-linux-android-
mkdir -p $O
cp "$CFG" $O/.config

cfg() { $K/scripts/config --file $O/.config "$@"; }
# Samsung lock-down / root-killing / hypervisor protection
for s in SEC_RESTRICT_ROOTING SEC_RESTRICT_SETUID SEC_RESTRICT_FORK SEC_RESTRICT_ROOTING_LOG \
         SECURITY_DEFEX SECURITY_DSMS INTEGRITY INTEGRITY_AUDIT \
         UH UH_RKP TIMA_RKP RKP_KDP RKP_CFP RKP_CFP_JOPP RKP_CFP_ROPP RKP_CFP_ROPP_SYSREGKEY RKP_NS_PROT RKP_DMAP_PROT \
         KNOX_KAP SEC_DEBUG_GAF_V3 FIVE PROCA; do   # KNOX_NCM stays: net code calls it unconditionally
  cfg --disable $s
done
# Broadcom BCM4361 wifi: S8 firmware/nvram live in /vendor/etc/wifi. With ANDROID_PLATFORM_VERSION >= 9 the driver
# prefixes "/vendor" itself, so the config keeps /etc/wifi/... (setting /vendor/etc/... gave /vendor/vendor/etc/...)
cfg --set-str BCMDHD_FW_PATH "/etc/wifi/bcmdhd_sta.bin"
cfg --set-str BCMDHD_NVRAM_PATH "/etc/wifi/nvram.txt"
# Samsung's build passes the Android version: bcmdhd then uses /data/vendor/conn/ (.cid.info from macloader) + P+ paths
export PLATFORM_VERSION=10 ANDROID_MAJOR_VERSION=q
# Android 10 VINTF kernel requirements (compatibility_matrix.3.xml, kernel 4.4): a mismatch makes
# Build.isBuildConsistent() fail -> "There's an internal problem with your device" at every boot
cfg --enable MODULES; cfg --enable MODULE_UNLOAD; cfg --enable MODVERSIONS; cfg --disable USELIB
cfg --enable IKCONFIG; cfg --enable IKCONFIG_PROC   # VINTF reads /proc/config.gz
# Fingerprint: the stock "fps,common" driver (SENSORS_VFS8XXX_EGIS, unpublished) serves Egis + Synaptics. This SCV36's
# sensor is a Synaptics NAMSAN (proven on the stock kernel, debug/fp_stockkernel), although the DT says ET510 ->
# Q-tree Synaptics vfs8xxx driver taught the fps,common node (tools/kernel/patch_vfs8xxx_fps_common.py), /dev/vfsspi.
# TZ owns the SPI bus (ENABLE_SENSORS_FPRINT_SECURE, from CONFIG_SENSORS_FINGERPRINT).
cfg --disable SENSORS_VFS8XXX_EGIS; cfg --disable SENSORS_ET5XX; cfg --enable SENSORS_VFS8XXX
# FM radio: NOT on the SCV36. The JPN DT carries the generic rtcfmradio@64 node, but its i2c@20 bus is
# status="disabled" and GPIO 99/100/129 are the ISDB-T tuner's lna-en/rst/irq (isdbt node) -> no FM chip on the board.
# (driver left enabled: inert, the bus never probes)
cfg --enable MEDIA_RADIO_SUPPORT; cfg --enable RADIO_ADAPTERS; cfg --enable RADIO_RTC6213N; cfg --enable I2C_RTC6213N
cfg --set-str LOCALVERSION "-scv36-q"
cfg --disable LOCALVERSION_AUTO

# (HARDENED_USERCOPY stays on: required by the Q VINTF kernel matrix)
# PROFILE=perf (default): strip hardening + debug overhead. Kept on purpose because Android needs them:
# SELinux, seccomp, audit core (SELinux denial logs), perf events/ftrace core (atrace/simpleperf), SEC_DEBUG (upload mode,
# reset reasons) and all its SEC_DEBUG_*/SEC_PM_DEBUG sub-options (printk.c, sec_debug.c, lpm-levels.c,
# qpnp-power-on.c use their structs unguarded - patch later if worth it), KNOX_NCM (net code calls it unconditionally).
PROFILE=${PROFILE:-perf}
if [ "$PROFILE" = perf ]; then
  # Spectre/Meltdown mitigations. Kryo 280 (A73/A53-derived) is not Meltdown-affected, so KPTI is pure overhead;
  # branch-predictor hardening is a real Spectre-v2 mitigation traded for speed at the user's request.
  for s in UNMAP_KERNEL_AT_EL0 HARDEN_BRANCH_PREDICTOR \
           CC_STACKPROTECTOR_STRONG SECURITY_SMACK AUDITSYSCALL SECURITY_SELINUX_AVC_STATS \
           CRYPTO_FIPS \
           SCHED_DEBUG SCHEDSTATS SLUB_DEBUG DEBUG_INFO \
           CORESIGHT; do   # QCOM_RTB stays: sec_debug/tzic call it unconditionally (disable at runtime via cmdline)
    cfg --disable $s
  done
  cfg --enable CC_STACKPROTECTOR_NONE
  # GCC 4.9 has no cortex-a73 model; a57.a53 big.LITTLE tuning is the closest to Kryo 280 gold/silver
  CPUFLAGS="-mcpu=cortex-a57.cortex-a53"
fi

cd $K
make O=$O olddefconfig >/dev/null
echo "== lock-down symbols still enabled (should be empty):"
grep -E '^CONFIG_(SEC_RESTRICT|SECURITY_DEFEX|SECURITY_DSMS|UH_RKP|TIMA_RKP|RKP_|KNOX_KAP|FIVE|PROCA)' $O/.config || true
[ -n "$OUTCFG" ] && cp $O/.config "$OUTCFG"
start=$(date +%s)
# CC set explicitly: bypasses Qualcomm scripts/gcc-wrapper.py (py2-only, turns new warnings into errors)
if make O=$O -j"$(nproc)" CC="${CROSS_COMPILE}gcc" KCFLAGS="-mno-android ${CPUFLAGS:-}" Image.gz > $O/build.log 2>&1; then
  echo "BUILD OK in $(( $(date +%s) - start ))s"; ls -la $O/arch/arm64/boot/Image.gz
  echo "warnings: $(grep -c "warning:" $O/build.log)"; grep "warning:" $O/build.log | sed -E "s#.*t830_q/##" | sort -u | head -15
else
  echo "BUILD FAILED in $(( $(date +%s) - start ))s"; grep -nE 'error:|Error [0-9]' $O/build.log | head -40
  exit 1
fi
echo "== profile: $PROFILE  cpuflags: ${CPUFLAGS:-none}"
grep -E '^CONFIG_(UNMAP_KERNEL_AT_EL0|HARDEN_BRANCH_PREDICTOR|CC_STACKPROTECTOR_\w+|HARDENED_USERCOPY|SCHED_DEBUG|SCHEDSTATS|SLUB_DEBUG|QCOM_RTB|CORESIGHT|CRYPTO_FIPS|SEC_DEBUG_SCHED_LOG)=' $O/.config || echo "(all perf-profile options off)"
