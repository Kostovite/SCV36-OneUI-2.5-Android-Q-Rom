# Findings, by subsystem

The short version of [DEVLOG.md](DEVLOG.md): for each part of the phone, what broke when One UI 2 met the S8
hardware, the root cause, and the fix (with the tool that applies it). Read this first; go to the DEVLOG for the
evidence and the dead ends.

Legend: **S8** = stock SCV36 Pie, **T835** = Tab S4 Q vendor, **G9600** = Galaxy S9 Q system.

---

## Boot chain

| Symptom | Root cause | Fix |
|---|---|---|
| Rooted stock kernel bootloops | Samsung DEFEX / root restriction in the stock kernel | Own kernel with the lock-down features off (`tools/kernel/build_kernel.sh`) |
| Q kernel panics "dmv corrupt" | Pie fs_mgr verity table has FEC args the Q kernel rejects → falls back, finds /system modified | Strip `verify` from the DT fstab (`tools/build/patch_dtb_noverity.sh`) |
| `BUG` timer.c at 6.5 s | Q APR is a DT platform driver; S8 DT has no node → never initialised | Legacy init when the node is absent (`tools/kernel/patch_apr_legacy.py`) |
| "Only official released binaries" lock | **KnoxGuard** in the stock system saw the custom kernel | Never boot a custom binary with KnoxGuard present; de-Knoxed stock system for the transition (`tools/build/build_deknox_system.sh`) |
| init abort "Duplicate prefix match vendor.mls." | G9600 plat property_contexts already define 9 vendor props | `tools/build/dedup_contexts.py` |
| keymaster exits → keystore → system_server NPE loop | T835 TZ-client HALs vs the S8 trustlets; Pie keymaster vs Q libkeymaster ABI | Transplant the whole S8 TZ group (keymaster 3.0, gatekeeper, soft-keymaster libs from S8 /system); `tools/build/symcheck.py` |
| Modem load fails → XPU reset at 120 s | `fs_config` file capabilities are lost in a tar install → IPC router denies bind | `capabilities` lines on the init services (build_vendor 7b); image build should carry xattrs |
| "There's an internal problem with your device" | VINTF kernel requirements (MODULES, MODVERSIONS, HARDENED_USERCOPY, no USELIB) | Kernel config (`tools/build/vintf_kcheck.py` checks offline) |
| TWRP *Wipe Data* → kernel panic in ext4lazyinit | /data `errors=panic` + lazy itable init | Format with `installer/twrp/format_data.sh` instead |

## Display

| Symptom | Root cause | Fix |
|---|---|---|
| Boot animation rotated −90° | Tab S4 vendor is landscape | `primary_display_orientation=ORIENTATION_0`, S8 densities (build_vendor 5b) |
| UI shrinks to the top-left (1080×2220 inside 1440×2960) | One UI forces FHD+ when the WM size is empty; Samsung SurfaceFlinger matches that to the panel's DT "fhd" timing and expects the panel's DDI scaler, which the T835 composer never drives | Remove the FHD/HD timings from the JPN DTBs (`tools/build/dtb_single_mode.sh`) → native WQHD+ 640 dpi |
| AOD stuck at 2 nit | G9600 `config_aodBrightnessValues` uses an S9-only path | Static RRO `FrameworkS8Overlay` (`tools/build/build_framework_overlay.sh`) → S8 HLPM 2 nit / 60 nit by light sensor |
| SSRM / thermal policy rejected | S9 GPU/CPU frequency limits are invalid on Adreno 540 | `SdhmsS8Overlay` RRO with S8 frequency steps (`tools/build/build_sdhms_overlay.sh`); `ro.hardware.chipname=MSM8998` |

## Radio, CSC, VoLTE

- SIM, 4G data, SMS, CSFB calls work. The **Vietnamese CSC (XXV)** comes from an SM-G960F OXM odm; the EFS sales code is
  `KDI`, so the installer creates `odm/etc/omc/KDI` as a copy of XXV (EFS is never written).
- The odm must be labelled as `/odm` (not `/vendor/odm`) or the IMS/ePDG CSC parsers get EACCES.
- **VoLTE does not work**: the SCV36 modem firmware carries only KDDI/docomo MCFG profiles (RAT policy only, no IMS items);
  the modem throttles the IMS PDN (QMI 2/211). Swapping the CP was judged not worth the RF/NV risk.

## Wi-Fi / Bluetooth / NFC

| Symptom | Root cause | Fix |
|---|---|---|
| No Wi-Fi | bcmdhd firmware/nvram paths (kernel prefixes `/vendor` itself on P+) | `BCMDHD_FW_PATH=/etc/wifi/...`, `PLATFORM_VERSION=10` |
| S8 wpa_supplicant crashes | Needs BoringSSL symbols gone in Q | Keep a Q supplicant: the **G9600 Broadcom** build (matches the S8 bcmdhd driver) |
| Quick Share fails (`IFACE_DISABLED`) | T835 (Qualcomm) Wi-Fi HAL sets the random MAC with the interface down → bcmdhd powers the chip off → P2P discovery interface deleted | G9600 Broadcom Wi-Fi HAL (sets MAC with the interface up) |
| BT `rfkill` EACCES | sysfs path on 4.4 is `/sys/devices/soc/soc:bt_driver/...`, T835 policy labels the 4.x path | `vendor_file_contexts.add` + ueventd rules |
| NFC "Kernel driver doesn't exist", then "Hal is nullptr" | One UI 2 checks `/sys/class/nfc/nfc_support`; needs `ISehNfc 2.0` | Kernel patch; NFC HAL from the G9600 vendor with S8 SEN82AB config |

## Audio

- S8 speaker is a **Maxim MAX98506** whose protection runs inside the S8 audio HAL (VI feedback on TERT_MI2S_TX);
  the T835 HAL (quad TFA9896) cannot drive it → S8 Pie audio HAL + ACDB + SoundBooster transplanted
  (`config/transplant/audio.txt`) under the Q audio 5.0 service.
- `config/stubs/audio_hal_shim.c` exposes the Samsung Q `sec_get_audio_*_instance` extension the G9600 framework
  expects (stream type 0 = output, 1 = input – getting it backwards killed the mic).
- Video recording needs `AUDIO_DEVICE_IN_2MIC` in the Samsung policy (build_vendor 5f).
- The Pie HAL imports `set_sched_policy` (moved to libprocessgroup on Q) → `patchelf --add-needed`.

## Camera

The S8 Snapdragon camera HAL is HAL1-style with Samsung parameters; One UI 2's camera app needs S9 HAL3 vendor tags.
Solution: S8 Pie mm-camera HAL (319 files) + the **S8 SamsungCamera 9.0** app, with these fixes:

| Symptom | Root cause | Fix |
|---|---|---|
| 0 cameras | T835 mm-camera can't find the S8 sensor modules | Whole S8 camera stack (`config/transplant/camera.txt`) |
| Provider crash loop | Missing Samsung 3A libs (`libTs*`) per module | Added to the transplant |
| Rear camera dead | Companion ISP / OIS firmware in `/system/etc/firmware` not readable by the HAL domain | Label `vendor_firmware_file` |
| Samsung params rejected | cameraserver used HAL3 (Camera2Client) | `persist.camera.HAL3.enabled=0` |
| Striped preview in every app | T835 gralloc NV21 stride = GPU alignment, S8 HAL writes stride = width | `tools/patches/patch_gralloc_nv21.py` |
| SamsungCamera UI frozen | Pie cameraserver's SecCameraCoreManager emitted `COMMON_SHOT_PREVIEW_STARTED`; Q has none | HAL wrapper `config/stubs/camera_torch_shim.c` sends it after `start_preview` |
| Torch slider crash | S8 HAL lacks `set_torch_mode_strength` | Same wrapper implements it via the S2MPB02 sysfs levels |
| Front preview upside down | Q CameraClient skips the mirror when `SET_DISPLAY_ORIENTATION` arg2 == 1 | `tools/patches/patch_cameraservice_orientation.py` |
| Photos never saved | Low-light plugin libs missing / unresolved symbols | S8 uni plugins + `libaeabi_compat`; `tools/build/vendor_symbol_audit.py` |

## Fingerprint

- The JPN DT says Egis **ET510**, but this unit's sensor is a **Synaptics NAMSAN**. Proven by a one-shot boot of the
  stock kernel: its `fps,common` driver reports NAMSAN and the trustlet finds the sensor.
- Fix: Synaptics `vfs8xxx` driver taught the `fps,common` node (`tools/kernel/patch_vfs8xxx_fps_common.py`),
  G9600 fingerprint@3.0 service + S8 Pie `fingerprint.default.so` / bauth libs (match the S8 trustlet),
  `tools/patches/patch_fp_module_version.py` (HAL version 0x201 → 0x300).
- Weeks of SPI pin / clock theories were wrong; the TZ owns BLSP12 (touching its pins = SError / XPU reset).
- Enroll animation: S8 videos swapped into the G9600 BiometricSetting (`tools/patches/patch_fp_s8_media.py`).

## Iris

| Symptom | Root cause | Fix |
|---|---|---|
| S9 iris stack fails | S9 app drives the IR camera through HAL3 + an S9-only tag; S9 irisd speaks the SDM845 trustlet protocol | Use the **Tab S4 Q** iris stack (same SoC + S5K5E6 sensor, HAL1 path like the S8) |
| T835 trustlet rejected (errno 22) | Samsung fuses a **per-product OEM root key**; T835 TA cert chain ends in another root | Use the S8's own `sec_iris` trustlet (already on the phone) |
| SecIrisService crash loop | Reads `config_keyguardComponent` by its T835 framework id (0x01040252 = `config_headlineFontFeatureSettings` on G9600) | `FrameworkS8Overlay` gives that id the keyguard component (`tools/build/build_framework_overlay.sh`) |
| Black enroll screen, Tab S4 look | Tablet layouts give 0 dp TextureViews on a phone | `IrisS8Overlay`: S8 Pie layouts/videos/dimens merged onto the T835 resources (`tools/patches/merge_seciris_s8ui.py`), compiled with every T835 resource ID pinned (`tools/build/build_iris_overlay.sh`) |
| "Fail to get camera info" for id 90 | AOSP bounds check in `getCameraInfo` / `cameraIdIntToStr*` rejects hidden camera ids | `tools/patches/patch_cameraservice_hiddenid.py` (3 sites) |
| Enroll OK, unlock fails (`GetAuthId -40`) | T835 libIrisTlc inserts a `type` field in cmd 13; S8 TA reads the sealed id 4 bytes off | `tools/patches/patch_iristlc_t835_authid.py` |
| Iris gone after a reboot | The first approach modified SecIrisService.apk itself; that invalidates its signature. A live install works until the next boot, then the package manager rejects it ("Failed to collect certificates") and wipes its app data (the template in `/data/system/users/0/bio/ir` survives) | Keep the apk stock; both fixes above are overlays. On Android 10, references inside overlay files are not remapped, so the overlay must reuse the target's resource IDs (checked by the build) |

## Other

- **Secure Folder**: two Knox gates in services.jar return false on a tripped device → `tools/patches/patch_knox_securefolder.sh`
  (KnoxGuard and attestation untouched). Samsung Pass / Pay stay broken (fuse-based attestation).
- **Gear VR**: system side works; Oculus store is shut down. Firefox Reality rebuilt for VrApi 1.1.26 with GeckoView 115
  (`tools/gearvr`).
- **ISDB-T TV** (FC8300) works with the stock SCV36 or SCV38 stack but is useless in Vietnam (DVB-T2, which the tuner
  cannot demodulate) → removed by default.
- **FM radio**: no FM chip on the SCV36 board (its I2C bus is disabled; the pins belong to the TV tuner).

## Battery / background load (2026-10-09)

- Overnight standby: ~17 mAh/h (~0.6 %/h), awake 10 %.
- **vaultkeeperd** restarts every ~3 min ("There is no VK ID": T835 Q daemon vs the S8 trustlet). KnoxGuard reads its
  state through it, so it is deliberately left alone.
- Removed restart loops: `argosd` (needs a kernel feature the S8 lacks), `ss_conn_daemon2`.
- The fingerprint HAL logs a 1 Hz status line while awake; measured cost is negligible (24 s CPU in 6.7 h).
- Release kernel turns off the Qualcomm register trace buffer (`msm_rtb.enable=0`) and the 4 MB debug log buffer.

## Hard-won rules

- The Samsung **`debug` partition** keeps the kernel log of a panic: read it from TWRP (`tools/device/read_debugpart.ps1`).
- Never read `/sys/kernel/debug/gpio` or pinctrl debugfs: TZ-owned pins → XPU reset.
- A tar with a `./` entry extracted over `/` changes `/system`'s mode → init cannot exec → bootloop.
- Q loads `/vendor/build.prop` in the vendor_init context: `ro.*` props outside the vendor namespace are dropped silently.
- `adb reboot system` from TWRP passes an unknown reason → Samsung's bootloader keeps its recovery flag; use plain `adb reboot`.
