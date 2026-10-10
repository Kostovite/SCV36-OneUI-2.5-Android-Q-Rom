# One UI 2 (Android 10) for the Galaxy S8 au SCV36

A port of Samsung **One UI 2.0 / Android 10** to the Japanese **Galaxy S8 au SCV36** (Snapdragon 835, `dreamqlte`),
a phone Samsung left on Android 9 / One UI 1.0. It is assembled from three Samsung firmwares plus the S8's own
hardware blobs, a forward-ported kernel, and a set of small binary patches, and installs as a TWRP flashable zip.

This repository holds **only the tooling, patches, configuration and research notes** – no firmware, no Samsung
binaries, no built images. Everything is rebuilt from firmware you download yourself.

> Daily-driven on one SCV36 in Vietnam (Viettel / MobiFone). It is a hobby port: read [Safety](#safety-rules) before flashing anything.

---

## Status

| Area | State | Notes |
|---|---|---|
| Boot, display (WQHD+ 640 dpi), touch, pressure home key | ✅ | Multi-resolution timings removed from the DT so One UI cannot fall into a mis-scaled FHD+ mode |
| SELinux | ✅ enforcing | Tab S4 Q split policy + S8 HAL rules ([config/sepolicy](config/sepolicy)) |
| 4G data, SMS, calls (VoLTE, CSFB fallback) | ✅ | Vietnamese CSC (XXV) aliased to the EFS sales code KDI |
| VoLTE (+ video calls, SMS over IMS) | ✅ | Tested on Viettel: IMS registers on LTE with the stock au modem firmware; needs the readable XXV CSC (KDI alias + `/odm` labels) |
| Wi-Fi, Wi-Fi Direct / Quick Share | ✅ | Broadcom BCM4361 with the G9600 Broadcom HAL + supplicant |
| Bluetooth | ✅ | S8 Broadcom stack |
| NFC (Samsung sec-nfc, global tag/HCE) | ✅ | FeliCa / Osaifu-Keitai: ❌ (needs the stock Japanese stack) |
| Audio, speaker protection, mic, video recording | ✅ | S8 Pie audio HAL behind a Q shim; S8 speaker tuning converted for the One UI 2 SoundBooster, S9 Dolby tuning |
| Stereo speakers (bottom = L, earpiece = R) | ✅ | DSP per-stream channel mixer; `S8PORT_STEREO=1` (release builds include it) |
| Camera (rear, front, torch levels, photo + video) | ✅ | S8 Pie HAL1 stack + S8 SamsungCamera 9.0 |
| Fingerprint | ✅ | Synaptics NAMSAN (the DT wrongly says Egis ET510) |
| Face recognition | ✅ enroll + unlock | S8 Pie face engine (S8 trustlet layout) + camera2 vendor keys on the HAL1 legacy shim |
| Iris | ✅ enroll + unlock | Tab S4 Q iris stack + the S8's own trustlet; stock Samsung-signed app with the S8 UI supplied by overlays |
| Sensors, auto-rotate, AOD (auto brightness), notification LED | ✅ | |
| Secure Folder | ✅ | services.jar gate patch (KnoxGuard untouched) |
| Gear VR | ✅ system side | Store/login are dead upstream; see [tools/gearvr](tools/gearvr) |
| Samsung Pass / Samsung Pay / Knox attestation | ❌ | Fuse-backed, server-checked: not fixable |
| ISDB-T TV | ⏸ removed | Works, but useless in Vietnam (DVB-T2); `S8PORT_TV=1` to include |

Full history, every root cause and every dead end: **[docs/DEVLOG.md](docs/DEVLOG.md)**.
The short, per-subsystem version: **[docs/FINDINGS.md](docs/FINDINGS.md)**.

---

## How the port is put together

```
 ┌──────────────── /system  (SAR, ext4, one partition) ─────────────────┐
 │  Galaxy S9 SM-G9600 Android 10 system  (One UI 2.0, framework, apps) │
 │   − 53 apps debloated            + S8 camera app / cameradata        │
 │   + 3 binary-patched framework libs (cameraservice, semcamera, ...)  │
 │                                                                      │
 │  /system/vendor  =  Tab S4 SM-T835 Android 10 vendor (MSM8998, Q,    │
 │                     split SELinux, VNDK 29)                          │
 │                  +  S8 hardware transplants from SCV36 Pie:          │
 │                     camera, audio, sensors, keymaster/TZ, BT, NFC,   │
 │                     fingerprint, Wi-Fi HAL, modem/RIL glue, panel    │
 └──────────────────────────────────────────────────────────────────────┘
 boot.img = Tab S4 Android 10 kernel (msm-4.4.205) + S8 board fixes
            + stock SCV36 JPN device trees (verity off, WQHD only) + 2SI ramdisk
```

| Piece | Source firmware | Why this one |
|---|---|---|
| System (One UI 2) | SM-G9600 (Galaxy S9 China/HK) `G9600ZHU9FZC1` | Global One UI 2 build, no carrier apps, Snapdragon |
| Vendor base | SM-T835 (Galaxy Tab S4 LTE) `T835DXU5CVG2` | Same SoC (MSM8998) with an official Android 10 vendor and split SELinux |
| Hardware blobs, DTBs, TZ apps | SCV36 stock `SCV36KDU1CZE1` (Android 9) | The phone's own camera/audio/sensor stacks and trustlets |
| Kernel | SM-T830 Android 10 source (msm-4.4) | Samsung's last MSM8998 kernel; S8 board support ported in |
| Vietnamese CSC | SM-G960F OXM `G960FXXUHFVG6` | XXV carrier config and APNs |

Details and download hints: [docs/DONORS.md](docs/DONORS.md).

---

## Repository layout

| Path | What is in it |
|---|---|
| [docs/](docs) | `FINDINGS.md` (per-subsystem summary), `DONORS.md`, `DEVLOG.md` (full journal), `DEBUG_LOGS.md` |
| [kernel/](kernel) | Kernel changes as diffs against Samsung's Tab S4 Q source, one per branch; how to build |
| [tools/setup/](tools/setup) | Host / build-server setup, toolchain + kernel source fetch, `remote.sh` |
| [tools/build/](tools/build) | The build pipeline: system, vendor, SELinux, overlays, iris/TV staging, packaging |
| [tools/kernel/](tools/kernel) | `build_kernel.sh` and the scripts that patch the kernel tree |
| [tools/patches/](tools/patches) | Binary / APK patches for Samsung userspace (cameraservice, iris, fingerprint, Secure Folder…) |
| [tools/device/](tools/device) | Run against the phone: log capture, TWRP helpers, live install/rollback |
| [tools/analysis/](tools/analysis) | Research scripts: firmware inspection, ABI/symbol checks, reverse-engineering helpers |
| [tools/gearvr/](tools/gearvr) | Firefox Reality rebuilt for the Gear VR runtime |
| [tools/lib/env.sh](tools/lib/env.sh) | Shared settings + phone helpers (`ph`, `phsh`, `phpush`) |
| [config/](config) | Inputs to the build: debloat lists, SELinux additions, transplant lists, shim sources, VNDK config |
| [installer/](installer) | TWRP zip installer (`update-binary`, `apply_vendor.sh`) and PC-side TWRP scripts |

Every script starts with a comment saying what it does, where it runs (WSL, build server, phone, TWRP) and its usage.
An index is in [tools/README.md](tools/README.md).

---

## Building

### Requirements

- **Windows + WSL2 (Debian)** for image work (`tools/setup/setup_host.sh` installs the packages: debugfs, e2fsprogs,
  simg2img, lz4, python3, apktool deps, …). Kernel sources need a case-sensitive filesystem → they live in the WSL
  home, `~/s8rom` (override with `S8ROM`).
- **A Linux build server** (optional but used throughout) for the kernel: `tools/setup/server_setup.sh`
  fetches the AOSP GCC 4.9 toolchain and the kernel tree.
- The donor firmwares from [docs/DONORS.md](docs/DONORS.md) under `firmware/` and `downloads/` (git-ignored).
- An SCV36 with an **unlocked bootloader**, TWRP for SCV36 (`tools/build/twrp_port.sh`) and a full TWRP backup
  (`tools/device/twrp_backup.ps1`).

### Local settings

```sh
cp config/local.env.example config/local.env   # git-ignored
# BUILD_HOST=user@build-server     (kernel builds)
# PHONE_PC=                         (empty = phone is on this machine's adb; else user@pc where it is plugged in)
```

### Pipeline

```sh
# 0. one-time
bash tools/setup/setup_host.sh                  # WSL packages
bash tools/setup/remote.sh setup                # build server: toolchain + kernel tree
bash tools/analysis/dump_trees.sh               # unpack donor images into ~/s8rom/trees

# 1. kernel  (server; pulls out/kernel/Image.gz, writes kernel/patches/<branch>.diff)
bash tools/setup/remote.sh kernel

# 2. vendor + system
bash tools/build/build_vendor.sh                # T835 vendor + S8 transplants + SELinux -> ~/s8rom/port/vendor
SUDO_PW=... bash tools/build/build_system.sh    # full system image (first install / Odin)

# 3. TWRP update zip  (boot.img + vendor.tar + system_add.tar + installer)
bash tools/build/make_vendor_push.sh
bash tools/build/make_flashable_zip.sh          # -> out/rom/s8port_update_<date>.zip
```

Flags: `S8PORT_DEBUG=1` adds the boot-watchdog trigger for the debug kernel branch; `S8PORT_TV=1` / `S8PORT_TV38=1`
include the ISDB-T TV stacks.

### Kernel

Branch `s8-q-release` (default) is Samsung's SM-T830 Q kernel plus the S8 board fixes; `s8-q-port` is the same with
the `s8dbg` debug hooks (reboot-to-TWRP on any crash, kernel log dumped to `cache`, boot watchdog). See
[kernel/README.md](kernel/README.md). Release boot cmdline drops the debug options and turns the Qualcomm register
trace buffer off (`msm_rtb.enable=0`).

---

## Installing

Step by step: **[docs/INSTALL.md](docs/INSTALL.md)**. In short:

1. Fresh install: Odin AP package (boot + TWRP + system), then format `/data` with
   `installer/twrp/twrp_format_data.ps1` (TWRP's own *Wipe Data* triggers an ext4 lazy-init panic on this kernel),
   then flash the update zip.
2. Updates: flash `s8port_update_<date>.zip` in TWRP, or over adb with `installer/twrp/twrp_vendor.ps1`.
   The installer checks for an SCV36 bootloader and logs to `/sdcard/s8port_apply.log`.
3. Root is optional (patch the release boot with Magisk).

Release packages are built with `tools/build/make_release.sh` into `out/release/` (not in git: they contain Samsung
binaries).

---

## Safety rules

These are hard rules for working on this phone; most were learned the hard way.

- **KnoxGuard**: never boot Android with KnoxGuard present *and* a custom binary – it locks the device
  ("Only official released binaries are allowed"). The port's system has KnoxGuard handled before first boot.
- **EFS is read-only.** Never write to it; never print or commit the IMEI / serials (capture scripts filter them).
- **Never read `/sys/kernel/debug/gpio` or pinctrl debugfs** – touching TrustZone-owned pins causes an XPU reset.
- Don't flash a different modem (CP) without a backup and a reason; RF calibration lives with it.
- Keep a TWRP backup of `efs`, `modemst1/2`, `fsg`, `persist`, `param`, `boot`, `recovery` (`twrp_backup.ps1`).

---

## Credits and licences

- Samsung Open Source (SM-T830 / SM-G9500 kernel sources, GPL-2.0); kernel diffs in `kernel/patches` are GPL-2.0.
- Prior art that pointed the way: codyalank's LineageOS 17.1 dreamqlte, hadesRom / hadesKernel (corsicanu,
  ananjaser1211), GalaxyOS, Katuwu's S8 CHN kernels, the XDA SC-02J/SCV36 root threads.
- Tools used: TWRP, Magisk / magiskboot, apktool, smali, vmlinux-to-elf, capstone, Unicorn, OMCDecoder's algorithm.
- Samsung firmware, apps and trademarks belong to Samsung and are **not** distributed here.

The scripts and documentation in this repository are provided as-is, without warranty; flashing can brick or
lock your device.
