# Donor firmware and sources

Nothing here is redistributed. Download the files yourself (samfw.com, Bifrost / SamFirm-style tools,
opensource.samsung.com) and place them as shown; all of these paths are git-ignored.

## Firmware

| Role | Device | Build | Expected path | Used for |
|---|---|---|---|---|
| Target (stock) | Galaxy S8 au **SCV36** (`dreamqlte`, KDI) | `SCV36KDU1CZE1` (Android 9) | `firmware/s8/` → unpacked to `work/stock_CZE1/` | Kernel config (IKCONFIG), JPN DTBs, every S8 hardware blob (camera, audio, sensors, TZ clients, BT, panel), S8 apps (SamsungCamera 9.0, StickerProvider, SecIrisService UI, fingerprint media), trustlets on `apnhlos` |
| System | Galaxy S9 **SM-G9600** (China/HK) | `G9600ZHU9FZC1` (Android 10, One UI 2.0) | `firmware/SAMFW.COM_SM-G9600_IUS_G9600ZHU9FZC1_fac/` → `~/s8rom/trees/g9600_root` | The whole `/system` (SAR), odm, the Broadcom Wi-Fi HAL / supplicant, NFC HAL, fingerprint@3.0 service |
| Vendor base | Galaxy Tab S4 LTE **SM-T835** | `T835DXU5CVG2` (Android 10) | `firmware/SAMFW.COM_SM-T835_XXV_T835DXU5CVG2_fac/` → `work/donor_T835/`, `~/s8rom/trees/t835_vendor` | MSM8998 Q vendor with split SELinux 29.0; iris stack (irisd, libIrisTlc, SecIrisService) from its system |
| CSC | Galaxy S9 **SM-G960F** OXM | `G960FXXUHFVG6` (Android 10) | `firmware/SAMFW.COM_SM-G960F_XXV_G960FXXUHFVG6_fac/` → `work/donor_G960F/` | Vietnamese CSC `XXV` (carrier list, APNs, CscFeature) |
| Optional | Galaxy S9 au **SCV38** | `SCV38KDS1CVK1` (Android 10) | `firmware/s9/`, `~/s9fw/` | First donor candidate (dropped: au carrier bloat); its ISDB-T TV stack (`S8PORT_TV38=1`) |
| Reference | Galaxy S8 China **SM-G9500** | `G9500ZCS6DUD1` | `firmware/SAMFW.COM_SM-G9500_CHC_G9500ZCS6DUD1_fac/` | Modem/MCFG comparison only (VoLTE research) |

Unpack Odin packages with `tools/build/unpack_odin.py`; inspect raw images with `tools/analysis/inspect_system.sh`;
`tools/analysis/dump_trees.sh` extracts the trees into the WSL work area (`~/s8rom/trees`).

## Kernel sources

| Source | Where | Used for |
|---|---|---|
| SM-T830 Android 10 kernel (msm-4.4.205) | [linckandrea/android_kernel_samsung_msm8998](https://github.com/linckandrea/android_kernel_samsung_msm8998) tag `Q-r1` (= T830XXU5CVG2) — `tools/setup/fetch_kernels.sh` | **Base of our kernel** |
| SM-G9500 CHN Pie OSS (4.4.153) | opensource.samsung.com → `SM-G9500_CHN_PP_Opensource.zip` → `firmware/SM-G9500_CHN_PP_Opensource` | SCV36 defconfig (`msm8998_sec_dreamqlte_jpn_kdi_defconfig`), JPN DTS sources, Pie KGSL, camera_v2 reference |
| Canadian S8 Pie kernel | `android-source-codes/dreamqltecan_kernel` (GitHub mirror) | dreamq DTS r00–r12 comparison |
| AOSP GCC 4.9 aarch64 | `tools/setup/fetch_toolchain.sh` | Same compiler Samsung used |

Samsung publishes **no** SCV36 / SC-02J kernel source; the stock SCV36 kernel was symbolised with
[vmlinux-to-elf](https://github.com/marin-m/vmlinux-to-elf) for reverse engineering (`tools/analysis/re_annotate.py`).

## Other downloads (`downloads/`)

| File | Used for |
|---|---|
| `magisk/Magisk-v30.7.apk` | `tools/build/magisk_patch.sh` (root, optional) |
| `twrp/` TWRP 3.4.0-0 `dreamqlte` | Base for the SCV36 TWRP (`tools/build/twrp_port.sh`) |
| `GearVR_SystemApps.zip` | Gear VR service + Oculus system apps (S9 extract) |
| `kernel.zip`, `dream2qltechn.zip`, `katu/` | Katuwu's S8 CHN Q kernels – fingerprint research reference |
