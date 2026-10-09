# Kernel

Base: Samsung's **SM-T830 (Galaxy Tab S4) Android 10 kernel** — msm-4.4.205, CAF `LA.UM.8.4.r1`, Samsung's shared
MSM8998 tree (git tag `Q-r1`, from [linckandrea/android_kernel_samsung_msm8998](https://github.com/linckandrea/android_kernel_samsung_msm8998)).
Config: the stock SCV36 kernel's own `/proc/config.gz` (Pie, 4.4.153) run through `olddefconfig`, then
[`tools/kernel/build_kernel.sh`](../tools/kernel/build_kernel.sh) switches features on/off.
Device trees: the **stock SCV36 JPN DTBs** (Rev09/11/12) with dm-verity removed from the early-mount fstab and the
panel's FHD/HD timings removed (`tools/build/patch_dtb_noverity.sh`, `tools/build/dtb_single_mode.sh`).

## Branches / patches

The tree lives on the build server (`~/s8rom/kernel/t830_q`); [`tools/setup/remote.sh kernel`](../tools/setup/remote.sh)
writes `git diff Q-r1 HEAD` of the checked-out branch to `patches/<branch>.diff` after every build.

| Diff | Branch | Content |
|---|---|---|
| [`s8-q-release.diff`](patches/s8-q-release.diff) | `s8-q-release` | **What the phone runs.** Everything below minus the s8dbg debug hooks, plus build-hygiene fixes |
| [`s8-q-port.diff`](patches/s8-q-port.diff) | `s8-q-port` | Development branch: same + `s8dbg` (any reboot → TWRP, kernel log dumped to the raw `cache` partition, boot watchdog `msm_poweroff.s8dbg_timeout`) |
| [`s8-pie-test.diff`](patches/s8-pie-test.diff) | `s8-pie-test` | Early experiment: Pie (G9500) KGSL transplant to run the S8's Pie graphics blobs |

To apply on a fresh `Q-r1` checkout: `git apply patches/s8-q-release.diff`.

## S8 changes in `s8-q-release`

| Area | File(s) | Why |
|---|---|---|
| Audio DSP link | `drivers/soc/qcom/qdsp6v2/apr.c` | Q made APR a DT platform driver (`qcom,msm-audio-apr`), the S8 DT has no such node → nothing initialised → `BUG` in timer.c at 6.5 s. Run the init at `device_initcall` when the node is absent (Pie behaviour). `tools/kernel/patch_apr_legacy.py` |
| GPU | `drivers/gpu/msm/*` | Q KGSL restored (the Tab S4 Q graphics blobs need it); the Pie-KGSL transplant is only on `s8-pie-test` |
| NFC | `drivers/nfc/sec_nfc.c` | `/sys/class/nfc/nfc_support`, which the One UI 2 NfcService checks. `tools/kernel/patch_sec_nfc_support.py` |
| Fingerprint | `drivers/fingerprint/vfs8xxx.c` | This SCV36's sensor is a **Synaptics NAMSAN** although the JPN DT says `fps-chipid = "ET510"`. The Synaptics driver binds the `fps,common` node, reads the `fps-*` properties and reports `NAMSAN`, so the HAL probes the right sensor family. `tools/kernel/patch_vfs8xxx_fps_common.py` |
| Fingerprint (unused now) | `drivers/fingerprint/et5xx-spi.c` | Egis path kept working for units with a real ET510: fps,common binding, LDO reset, ioctl magic `j`, TZ-owned SPI clock, stock timing |
| Build | two Samsung `Kconfig`s, `crypto/tcrypt.c` | CRLF line endings (26 Kconfig warnings), unused `drbg_cores` without FIPS |

Build output is warning-free except one upstream Kconfig `select` notice (HDMI audio codec, no HDMI on the S8).

## Config (`build_kernel.sh`, `PROFILE=perf`)

- **Off (Samsung lock-down):** `SEC_RESTRICT_*`, `SECURITY_DEFEX`, `SECURITY_DSMS`, `INTEGRITY`, `UH/RKP/TIMA`, `KNOX_KAP`, `FIVE`, `PROCA`.
- **Off (performance):** KPTI (Kryo 280 is not Meltdown-affected), Spectre-v2 branch-predictor hardening, stack
  protector, SMACK, `AUDITSYSCALL`, AVC stats, `CRYPTO_FIPS`, `SCHED_DEBUG`, `SCHEDSTATS`, `SLUB_DEBUG`, `DEBUG_INFO`, CoreSight.
- **On (Android 10 VINTF):** `MODULES`, `MODULE_UNLOAD`, `MODVERSIONS`, `HARDENED_USERCOPY`, `IKCONFIG_PROC`; `USELIB` off.
- **Kept on purpose:** SELinux, seccomp, audit core, perf events, `SEC_DEBUG` (+ sub-options: Samsung code uses them
  unguarded), `QCOM_RTB` (disabled at runtime with `msm_rtb.enable=0`), `KNOX_NCM`.
- Wi-Fi paths `BCMDHD_FW_PATH=/etc/wifi/bcmdhd_sta.bin`, `PLATFORM_VERSION=10`; fingerprint `SENSORS_VFS8XXX`.
- CPU tuning `-mcpu=cortex-a57.cortex-a53` (GCC 4.9 has no Cortex-A73 model; Kryo 280 = A73/A53 derived, ARMv8.0).
  Do **not** use Snapdragon 845 / Cortex-A75 flags: they emit ARMv8.2 instructions the 835 does not have.
  LTO is not available: the Samsung 4.4 tree has no `LTO_CLANG` support and GCC 4.9 cannot LTO a kernel.

## Building

```sh
bash tools/setup/remote.sh kernel                 # on the server: build_kernel.sh, pulls out/kernel/Image.gz
bash tools/build/make_release_boot.sh <template boot.img> out/kernel/boot_release.img
```

`make_release_boot.sh` swaps the kernel into a template boot image (keeps Magisk, ramdisk, DTB) and cleans the
cmdline. For a non-Magisk image use `tools/build/mkboot.py` with the stock SCV36 boot as template.
