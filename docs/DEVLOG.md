# SCV36 → One UI 2.x (Android 10) port — research notes & plan

_Research date: 2026-10-05. XDA blocks VN IPs (bunny.net 403) → XDA threads were read via web.archive.org._

## 1. Device facts (correction)

| | |
|---|---|
| Model | Galaxy S8 au/KDDI **SCV36** (twin: docomo SC-02J, both "G950J/G950D") |
| SoC | **Qualcomm Snapdragon 835 / MSM8998 — NOT Exynos** |
| Codename | `dreamqlte`; board-identical to China/HK **SM-G9500 (`dreamqltechn`)** |
| Bootloader | OEM-unlockable (unlike US G950U). Same hardware as G9500 → G9500 kernels/ROMs work with patches |
| Official max | Android 9 / One UI 1.0 |
| FeliCa (Osaifu-Keitai) | Stops working with modified kernel/root (confirmed in XDA t3830039 #8) |

Everything Exynos (G950F/FD/N) — kernels, ROMs, "OneUI 2.5 for S8" ports, RMM bypass zips built for Exynos — **will not boot** on this phone.

## 2. Prior art found

| What | Where | Notes |
|---|---|---|
| Oreo root for SC-02J/SCV36 | XDA t3830039 (archived) | Odin stock → OEM unlock → TWRP dreamqlte → format data → tomatolei's G9500 kernel (`9500.img`) → Magisk + wifi fix + `fstab.qcom` fix |
| G9500/G9550 Oreo fixes | XDA t3819774 (Peter KIKI) | wifi/data-mount fixes for Japanese S8 on G9500 kernels |
| Aurora ROM (极光ROM) G9500/G9550 | aurorarom.cn | Pie/One UI 1.0, worked on SC-02J with "G950J kernel patch" |
| LineageOS 17.1 (Android 10) dreamqlte | github.com/codyalank/lineage-17.1-dreamqlte (Mar 2026) | Uses `dreamqltechn` tree; BT/RIL/WiFi patches are directly relevant (same BCM4361 + Samsung RIL) |
| dreamqltechn device tree / kernel / TWRP | github.com/Samsung-S8-MSM8998-Dev | WIP, 2021 |
| MSM8998 Samsung kernel, **Android 10 (Q) branches** | github.com/linckandrea/android_kernel_samsung_msm8998 (`Qs-r*`, `lineage-17.1`) | Tab S4 (SM-T830, also MSM8998) got official Android 10 / One UI 2.5 → Samsung's own Q-era MSM8998 kernel source |
| Other MSM8998 kernels | icepie/, lyq1996/, ivanmeler/ android_kernel_samsung_msm8998 | S8/S8+/N8 Snapdragon custom kernels |
| SC-02J kernel (Androplus-based) | github.com/myurar1a/dreamqlte | Japanese-variant specific kernel bits |

**No existing One UI 2.x port for any Snapdragon S8** was found — this would be new work.

## 3. Port strategy (One UI 2.x)

Donor ROM = **Galaxy S9 au SCV38** (Snapdragon 845, official Android 10 / One UI 2.0, Japanese CSC + FeliCa framework, same 1440×2960 screen). Fallback donor: SM-G9600 (China S9, One UI 2.5).

```
system   = SCV38 Android 10 system  (framework, One UI apps)
vendor   = SCV36/G9500 Pie blobs (S8 is non-Treble: lives in /system/vendor) + selective Q blobs
kernel   = S8 board support (SCV36/G9500 Pie OSS) forward-ported onto Tab S4 Q kernel (msm-4.4, Samsung Q)
ramdisk  = Q-style init/fstab, system-as-root handling, SELinux policy merged, Knox/vaultkeeper/defex disabled
```

Phases:
1. **Safety**: EFS/modem/persist backup (`tools/device/collect_debug.sh --root`). Stock Odin package kept offline.
2. **Diagnose the current "Knox lockout"** (see §4) so it doesn't recur on every flash.
3. **Kernel**: build a bootable Pie kernel from SCV36 OSS source with defex/RKP/proca/FIVE/dm-verity/vaultkeeper hooks disabled → then forward-port to Q.
4. **Bring-up**: boot LineageOS 17.1 (codyalank) first as an Android 10 sanity check of the kernel + vendor.
5. **One UI 2 port**: SCV38 system + S8 vendor; fix boot (SELinux permissive first), then HALs: RIL, WiFi/BT, camera, fingerprint, display/HWC, audio.
6. Harden: SELinux enforcing, Knox-dependent apps stubbed, flashable zip via TWRP.

Build host: Linux (WSL2 Ubuntu is fine) for kernel + image tools (`simg2img`, `lpunpack` n/a, `magiskboot`, `mkbootimg`, AIK, `sdat2img`).

## 4. The "Knox shuts down / won't boot after a while" problem

Most likely **RMM/KG ("Prenormal") lock**: firmware lets a custom binary boot, then after ~7 days offline or a server check the
bootloader refuses it ("Only official released binaries are allowed"). Other candidates: dm-verity on `/system`, vaultkeeper,
or Knox `defex`/`five` killing init services. Need: a photo of the **Download Mode screen** + the error text shown at boot + logs.

### Confirmed from the phone (debug/20261005_211558, 2026-10-05)

- `ro.board.platform=msm8998`, `ro.hardware=qcom` → Snapdragon confirmed. Board rev 12 (DTB "DREAMQ PROJECT JPN Rev12").
- Running stock `SCV36KDU1CUD4` (Pie, patch 2020-12), **binary 1**, not rooted.
- `flash.locked=0`, `verifiedbootstate=orange`, `warranty_bit=1` (Knox already tripped, permanent).
- **KnoxGuard (`com.samsung.android.kgclient`, /system/priv-app/KnoxGuard) is an active Device Admin** and wakes up periodically;
  **RLC (`/system/priv-app/Rlc`, Remote Lock Control)** is installed. These are the KG/RMM lock components → the
  lockout is almost certainly KG. Every ROM we ship must delete KnoxGuard + Rlc (and the vaultkeeper HAL).

## 4b. Stock firmware analysis (CZE1 = same source CL21482906 as CUD4, re-signed May 2026)

Extracted to `work/stock_CZE1/` (`tools/build/unpack_odin.py`, `tools/build/cpio_extract.py`, `tools/analysis/inspect_system.sh`).

- **boot.img**: header v0, page 4096, `Image.gz-dtb` (3 DTBs: JPN Rev09/11/12), SEANDROIDENFORCE footer.
  Kernel `4.4.153-21482906` has IKCONFIG → exact defconfig saved at `work/stock_CZE1/boot.img_unpacked/kernel.config`.
- Kernel security features to disable in our build: `SEC_RESTRICT_ROOTING/SETUID/FORK`, `SECURITY_DEFEX`, `SECURITY_DSMS`,
  `UH_RKP/TIMA_RKP/RKP_*` (hypervisor kernel protection), `KNOX_KAP`, `KNOX_NCM`, `INTEGRITY`, `DM_VERITY` (system is on dm-0).
- Ramdisk: `ro.factory.model=SM-G950J`; `init.rc` starts `icd` (integrity check daemon) before vold; `verity_key` present.
- `/vendor/etc/fstab.qcom`: `/data` = `forceencrypt=footer` (FDE). System is not system-as-root, `ro.treble.enabled=false`,
  but **vendor is fully HIDL** (vendor/etc/vintf/manifest.xml, VNDK-lite 28) → good for an Android 10 system port.
- Security HALs/services to drop: `vendor.samsung.security.vaultkeeper_server`, `proca`, `wsm`, `sem`, `skpm`;
  apps: KnoxGuard, Rlc, KnoxCore, KnoxAttestationAgent, DsmsAPK, SecurityLogAgent, knoxanalyticsagent.
- `recovery-from-boot.p` present → stock recovery is re-flashed on boot; remove it so TWRP survives.
- Japanese bits present: MobileFeliCa*, FeliCaLock, FeliCaRemoteLockKDI, au* apps, WfdKDDILinkService.

## 5. Downloads needed from you (XDA/samfw block automated access)

| # | File | Source |
|---|---|---|
| 1 | ✅ have `SCV36KDU1CZE1` in `firmware/` | — |
| 2 | SCV38 Android 10 firmware (donor) | samfw.com / Bifrost (SCV38, KDI) |
| 3 | SCV36 kernel source (Pie) | opensource.samsung.com → search `SCV36` (login + accept) |
| 4 | SM-T830 Android 10 kernel source (T830XXU5CVG2 or similar) | opensource.samsung.com → `SM-T830` (or clone linckandrea `Qs-r*`) |
| 5 | Odin 3.13.x (or Odin3 v3.14.4) + Samsung USB driver | samsung developer site / samfw |
| 6 | TWRP 3.4.0-0 dreamqlte (Snapdragon S8) | https://dl.twrp.me/dreamqlte/ |

Put them under `downloads/`.

## 6. Donor analysis — SCV38KDS1CVK1 (Android 10, One UI 2.x, patch 2021-06)

Extracted to `work/donor_SCV38/` (system/vendor/odm raw images, PIT); trees dumped into WSL `~/s8rom/trees/`.
Tab S4 Android 10 kernel (linckandrea `Q-r1` = T830XXU5CVG2 on CAF LA.UM.8.4.r1) cloned to WSL `~/s8rom/kernel/t830_q`.

- Donor is **Treble + system-as-root** (separate `vendor.img` sdm845, `odm.img`); S8 is non-Treble, vendor inside `/system/vendor`.
  → port puts S9 `/system` + S8 `/system/vendor` (Pie, HIDL, VNDK 28) into the S8 system partition; needs SAR-aware ramdisk.
- Space (PIT): S8 `system` = 4480 MiB (4399 usable). S9 system 4326 + S8 vendor 483 + S9 odm 43 = 4852 MiB → too big.
  `config/debloat.txt` (JP/au/FeliCa/Knox-lock/bloat) frees ~759 MiB → ~4093 MiB, fits with ~300 MiB spare.
- Removing JP apps leaves **no keyboard** (HoneyBoardJPN) and **no SMS app** (PlusMessage, there is no Samsung Messages in KDI
  firmware). Boot animation `media/bootsamsung*.qmg` is the au one. Fix: take Samsung Keyboard, Samsung Messages and the
  generic boot animation from a non-carrier S9 Android 10 firmware (SM-G9600 HK/TGY or CHC) — or switch donor to it.

## 7. Kernel status (WSL `~/s8rom/kernel`)

- Host tools installed (`tools/setup/setup_host.sh`); toolchain = AOSP GCC 4.9.x 20150123 (`~/s8rom/toolchains`, same as stock).
- Tab S4 Q tree is Samsung's **shared msm8998 kernel** (`build_msm8998.sh` still lists dreamqlte/greatqlte targets),
  but only gts4lwifi defconfig + DTS were published.
- `tools/analysis/kernel_gap.sh`: of 1759 symbols enabled in stock SCV36 config, only **2 are missing** in the Q tree:
  `SENSORS_VFS8XXX_EGIS` (fingerprint driver → port from SCV36 OSS source) and `SEC_DEBUG_GAF_V3` (debug, drop).
- Stock DTBs (JPN Rev09/11/12) decompiled to `work/kernel_gap/stock_dtb*.dts`. Proper DTS sources still need SCV36 OSS.
- `tools/kernel/build_kernel.sh`: stock config + lock-down features off → `out_dream/arch/arm64/boot/Image.gz` (compile test).
- **Builds run on the LAN server** (BUILD_HOST in config/local.env; 104 cores, Debian 12): `bash tools/setup/remote.sh kernel`
  (from WSL) syncs tools/config, builds in ~36 s, pulls `out/kernel/{Image.gz,dream_q.config,build.log}`.
- **Perf profile** (`PROFILE=perf`, default) on top of the lock-down removal: off = KPTI (Kryo 280 is not Meltdown-affected),
  Spectre-v2 branch-predictor hardening, stack protector, hardened usercopy, SMACK, AUDITSYSCALL, AVC stats, CRYPTO_FIPS,
  SCHED_DEBUG/SCHEDSTATS, SLUB_DEBUG, DEBUG_INFO, CoreSight; `-mcpu=cortex-a57.cortex-a53` (closest GCC 4.9 model).
  Kept (Android/Samsung code needs them unguarded): SELinux, seccomp, audit core, perf events, SEC_DEBUG + sub-logs,
  QCOM_RTB (turn off at runtime via cmdline), KNOX_NCM. Qualcomm `scripts/gcc-wrapper.py` bypassed (`CC=` override).
- Not yet bootable: needs S8 DTBs appended (stock DTBs as first try), an Android 10 system-as-root ramdisk, mkbootimg.

## 8. Download Mode (2026-10-05) + S8 board sources

- Download Mode: `RP SWREV B1(1,1,1,1,1) K0 S0`, FRP OFF, OEM LOCK OFF, Warranty void 0x1, Current binary Samsung Official,
  **no KG/RMM STATE line** → this BL does not enforce the KG boot block; the old lockout was Android-side (KnoxGuard app,
  SEC_RESTRICT_ROOTING/DEFEX, verity). All removed in our builds.
- Samsung OSS has **no SCV36/SC-02J/any JPN S8/S8+/N8 source**. Has `SM-G9500_CHN_PP_Opensource.zip` (China S8, Pie).
- GitHub mirror `android-source-codes/dreamqltecan_kernel` (Canadian SD S8, Pie, 4.4.153 = same base) cloned on server:
  has dreamq r00–r12 DTS, `dreamqlte_can_open_defconfig`, vfs8xxx driver. DTBs build with `HOSTCFLAGS=-fcommon`.
- JPN r12 vs CAN r12 DT diff (`tools/analysis/dts_compare.sh`): JPN-only = `sec-nfc` (FeliCa NFC), ISDB-T 1seg tuner, `fps-spi`
  fingerprint (`fps,common` → `SENSORS_VFS8XXX_EGIS`, in **neither** tree), CF thermistor; CAN-only = pn547 NFC, eSE,
  vfsspi, 2 LDOs. → Use stock JPN DTBs with our kernel; fingerprint driver needs G9500 CHN source (or G960J QQ as fallback).
- `tools/build/mkboot.py`: header-v0 repacker, verified byte-identical vs stock (except Samsung's 256-byte signature).
  Test image `out/test/boot_qkernel_pie.img` = perf Q-kernel + stock JPN DTBs + stock Pie ramdisk (kernel-only HW test).
- `tools/device/twrp_backup.ps1`: dd backup of efs/modemst/fsg/persist/param/... + boot/recovery from TWRP.

## 9. Sources found (2026-10-05)

- `firmware/SM-G9500_CHN_PP_Opensource` (unpacked on server `~/s8rom/kernel/g9500_pp`, 4.4.153): contains
  **`msm8998_sec_dreamqlte_jpn_kdi_defconfig` (= SCV36)** + `jpn_dcm` (SC-02J), **JPN DTS `msm8998-sec-dreamq-jpn-r09/r11/r12`**
  (+ `dream2q-jpn-nfc`, `dream2q-jpn-isdbt` dtsi, S6E3HA6 JPN panel dtsi). This is the board source for our DTBs.
- Fingerprint: stock CZE1 DT says `fps,common`, **`fps-chipid = "ET510"` (Egis ET510)**, drdy = tlmm 127, ldo = tlmm 74,
  no reset pin. Q tree `drivers/fingerprint/et5xx-spi.c` (`etspi,et5xx`) detects ET510C/D but requires `etspi-sleepPin`
  → TODO: patch sleepPin optional + add `etspi` node; enable `SENSORS_ET5XX`. S7 edge JPN source has `et510-spi.c` as reference.
- Donor switched candidate: `firmware/SAMFW.COM_SM-G9600_IUS_G9600ZHU9FZC1_fac` = SM-G9600 HK/CHN (pit STARQLTE_CHN_HK),
  Android 10 (OS10), CSC OMC `OWC`, separate odm (multi-CSC) + hidden (preloads). No Japan/au content.

## 10. Odin-only workflow (TWRP doesn't work on this SCV36)

- `tools/build/magisk_patch.sh` (WSL): runs Magisk v30.7's own boot_patch.sh on the PC (x86_64 magiskboot + arm64 payload),
  KEEPVERITY/KEEPFORCEENCRYPT=true; Samsung kernel hexpatches (RKP/defex/proca) applied to stock kernel.
- `tools/build/odin_tar.py`: ustar + md5 trailer, like Samsung packages. Outputs in `out/odin/`:
  `AP_0_restore_stock_boot`, `AP_1_root_stock-kernel` (stock kernel + Magisk), `AP_2_root_q-kernel-perf` (our kernel + Magisk).
- Final ROM will also ship as Odin AP (boot + sparse system); no data preservation needed → no encryption, wipe in stock recovery.
- G9600 donor checked: system used 4282 MiB, has HoneyBoard (63 MiB), SamsungMessages_11, generic bootsamsung.qmg, GMS,
  no China-only apps; odm 105 MiB used, hidden (IUS/UNE preloads) 107 MiB.

## 11. Root bootloop + TWRP port (2026-10-05)

- `AP_1_root_stock-kernel` (stock kernel + Magisk v30.7) → **bootloop** ("set warranty bit : kernel" is normal). Same as the
  old XDA SC-02J experience: stock JPN kernel + root needed a modified kernel. Diagnose via pstore from TWRP.
- Official TWRP 3.4.0 dreamqlte = kernel 4.4.16 (2017) with no JPN DTBs, and `/modem` pointed at `modem` (SCV36: firmware
  vfat is `apnhlos`) → explains "can't access storage". `tools/build/twrp_port.sh`: TWRP ramdisk + SCV36 kernel + JPN DTBs +
  fixed fstab (+ /preload). Outputs `out/odin/AP_TWRP_scv36_A_stockkernel` and `..._B_qkernel` (recovery.img).
- **TWRP B (our perf Q kernel 4.4.205 + stock JPN DTBs) WORKS** (2026-10-05): all partitions visible, efs/cache/hidden/data
  mount, /data 32 MiB R/W OK, sec_touchscreen + keys + hall probed → first on-device proof the Q kernel drives the hardware.
  `/system` fails to mount (EXT4-fs errors at TWRP start) → diagnosing with `tools/device/twrp_sysdiag.ps1`.
- Backup `backup/20261005_223719` verified: 16 images, SHA256 OK, efs ext4 clean (imei/carrier/sec_efs/... present),
  modemst1/2 + fsg full. pstore empty; /proc/last_kmsg only held the bootloader (XBL/ABL) log of the TWRP boot.
- sysdiag: the EXT4 errors were sda24 (userdata, still FDE-encrypted at TWRP start) - harmless. /system is EMPTY because the
  user's TWRP Advanced Wipe included System (recovery.log: "Formatting System using make_ext4fs"). TWRP format/write works.
  Next: Odin stock CZE1 (AP+CP+CSC) → Odin `AP_3_qkernel-root+TWRP` (boot = Q kernel + Magisk, recovery = TWRP B).
- `tools/analysis/compat_check.sh`: of 309 compatible strings in stock JPN r12 DT, G9500 PP and Tab S4 Q trees leave the SAME set
  unclaimed (none missing only in Q). Real unclaimed: `fps,common` (→ ET5xx plan), `sec-mst` (Samsung Pay, n/a),
  `rtc6213n` (FM radio). `sec-nfc` IS supported in both (`SEC_NFC_DRIVER_NAME` macro, identical drivers/nfc/sec_nfc.c),
  already enabled from stock config (SAMSUNG_NFC/SEC_NFC). Remaining risk = driver revisions vs Pie blobs (KGSL/camera/audio)
  → decided by the AP_3 on-device test; fallback kernel = G9500 PP `msm8998_sec_dreamqlte_jpn_kdi_defconfig`.
- **Hybrid ("half-half") kernel analysis** (`tools/analysis/abi_diff.sh`, `tools/analysis/abi_hdr_diff.sh`): Pie(G9500) → Q(T830) UAPI changes
  are additive only for kgsl, ion, ipa, qseecom, v4l2-controls, compress_params; only `msm_audio_anc.h` changes a struct
  (ANC calibration, likely unused on S8). Driver deltas: camera_v2 16 lines, nfc 43, fingerprint 53, sec_ts 99, isdbt 0,
  fbdev/msm 1090, gpu/msm 816, sound/soc/msm 15801. Decision: keep Q kernel; transplant a Pie driver dir only for a
  subsystem that fails the AP_3 test (audio first candidate, then display).
- AP_3 (Q kernel + Magisk, stock CZE1 system present) → bootloop. last_kmsg: PowerOffReason PS_HOLD (software reboot, not
  kernel panic/upload) → likely Android init rebooting (critical service crash / mount failure). pstore empty because the
  user's key-combo was a HardReset. Next: `AP_5_qkernel_noroot_debugadb` (no Magisk, ro.adb.secure=0, adb from early boot,
  `tools/device/make_debug_boot.sh`) + `tools/device/capture_bootloop.ps1` to record logcat each loop.
- AP_6 (s8dbg.recovery hook): hook fired (no keys, "Recovery Mode, Reset param!", phone entered TWRP by itself) but the reset
  is still HARD (PowerOnReason HardReset, WarmResetReason empty; XBL configures PMIC "DVDD reset") → RAM/pstore always lost
  on this retail phone at debug LOW. → AP_7: s8dbg reboot notifier writes kmsg to the raw start of `cache`
  (header "S8DBGLOG <len> <cmd>"), read with `tools/device/read_logdump.ps1` in TWRP. Kernel changes live as
  `kernel/patches/0001-s8dbg-reboot-to-recovery.patch` (= `git diff` of the server tree, synced by remote.sh kernel).
- **ROOT CAUSE of Q-kernel bootloop (debug partition RESET_KLOG @1MB, `tools/device/parse_debugpart.py`)**: Pie fs_mgr's
  verity table has FEC feature args → Q kernel "verity: Invalid number of feature args" → retry without FEC → Samsung
  dm-verity finds system "corrupt" (TWRP had mounted /system rw → superblock changed) → `Kernel panic: dmv corrupt`.
  Fix: strip `verify` from DT fstab (`tools/build/patch_dtb_noverity.sh` → `out/kernel/jpn_dtbs_noverity.dtb`, magiskboot dtb patch).
  Test image: `AP_8_qkernel_noverity_debug` (Q kernel + no-verity JPN DTBs + no-auth adb + s8dbg).
  Lesson: the Samsung 'debug' partition is THE crash log on this phone (bootloader saves klog there after a panic).
- AP_8 (no verity) got to 6.5 s, then **kernel BUG timer.c:815** in `adsp_load_fw → apr_set_q6_state →
  schedule_delayed_work`: Q-tree APR became a DT platform driver (`qcom,msm-audio-apr`, absent in S8 Pie DT) → all APR
  init (client locks, subsys notifiers, delayed work) lived in a probe that never ran. Fix `tools/kernel/patch_apr_legacy.py`:
  no node → run the same init at device_initcall (Pie behaviour), skip of_platform_populate. `tools/analysis/reverse_compat.sh`
  found no other built-in driver with this trap. All Q-tree kernel changes: `kernel/patches/t830_q-changes.diff`.
  Next test image: `AP_9_qkernel_aprfix_debug`.
- AP_9 (APR fix): Android ran ~175 s (camera imx333 probed!) but **surfaceflinger SIGSEGV loop**: `kgsl: CP initialization
  failed to idle` + GPU write-permission fault → RescueParty → FACTORY_RESET prompt → reboot recovery (caught by the
  s8dbg cache dump, `tools/device/parse_cachehead.py`). Cause: Q kgsl allocates the CP scratch buffer PRIVILEGED; S8 Pie Adreno
  microcode writes it → fault. **Half-half transplant**: `tools/kernel/transplant_kgsl.sh` = whole `drivers/gpu/msm` from
  G9500 PP (+ touch for mtimes) + `tools/kernel/fix_kgsl_gup.py` (get_user_pages gup_flags). uapi msm_kgsl.h kept (superset).
  Next: `AP_10_qkernel_piekgsl_debug`.
- **AP_10 BOOTED ANDROID** (instant, to setup wizard) = Q kernel + Pie kgsl + APR fix + no-verity DTB works.
  Then **KG lock fired** ("Only official released binaries… Security error"; TWRP blocked, Download Mode OK): the stock
  system still had KnoxGuard (kgclient) → detected the custom kernel. This is the user's original lockout.
  Recovery: full stock CZE1 (BL+AP+CP+CSC), online KG check-in, verify Odin accepts TWRP again.
  RULE: never boot Android with KnoxGuard present + custom binary → next package = one-shot Odin AP with de-Knoxed
  stock system + our boot + TWRP (`tools/build/build_deknox_system.sh`).
- `tools/build/build_deknox_system.sh` → `out/rom/system_deknox_CZE1.img.ext4` (sparse): stock CZE1 minus KnoxGuard, Rlc,
  KLMSAgent, SKMSAgent, knoxanalyticsagent, KnoxAttestationAgent, SecurityLogAgent, DsmsAPK, recovery-from-boot.p;
  fstab forceencrypt→encryptable; **global G9600 bootsamsung/bootsamsungloop/shutdown.qmg** (QMG v0x0f; Pie player
  already plays v0x0f). Charging .spi identical across firmwares; Android 10 charging look = Q `lpm` → comes with the
  One UI 2 system. One-shot package: `out/odin/AP_11_deknox_stock_qkernel_twrp.tar.md5` (boot + TWRP + system).
- Odin "Can't open the specified file (Line: 2006)" also happens for packages **>= 4 GiB** (first AP_11 was 4.35 GB).
  Fix: Samsung-style lz4 entries (`name.lz4`, LZ4 frame: independent 1 MiB blocks, content size + checksum = FLG 0x6c
  BD 0x60). `tools/build/odin_tar.py` compresses on the fly (<4 GiB inputs); big images: WSL `lz4 -1 -B6 --content-size`.
  AP_11 repacked: 3.05 GB (system 4.30 GB → 3.00 GB), all entries verified.
- Odin "Set PIT file → Can't open the specified file (Line: 2006)" = **Re-Partition enabled without a readable PIT**
  (sticky after the stock CSC flash). Fix: Options → untick Re-Partition, or load `out/odin/DREAMQLTE_JPN_OPEN.pit`.

## 12. One UI 2 (Android 10) port — architecture (decided 2026-10-06)

Donor = G9600 (SM-G9600 HK/CHN, One UI 2, Android 10, no JP/au). Base = system-as-root + Treble, VNDK 29.
S8 (dreamqlte) = non-Treble, Pie vendor inside /system/vendor, VNDK 28.

**Compatibility model: vndk_lite** (AOSP `ld.config.vndk_lite.txt`). In it the `[vendor]` default namespace is NOT isolated
and searches `/system/${LIB}` directly → the Pie vendor can resolve its deps from Pie system libs we ship in /system.
Vendor dep analysis (`tools/analysis/port10_vndk.sh` + `port10_classify.sh`), S8 Pie vendor ELFs:
- lib64: needs 178 system (non-LLNDK) libs → 119 exist in donor(Q), **48 only in S8 Pie**, 11 nowhere; lib: 160 → 109/40/11.
- "48 only in Pie" = Samsung HAL interface .so (camera/radio/wifi/fingerprint/nfc@1.1/sem/skpm...) + libicuuc/libnl/libyuv.
  → ship these as a **vndk-28 compat set** from S8 Pie /system into the Q system (half-half at the library level).
- "11 nowhere" = Qualcomm CNE/QTEE/slimclient (com.quicinc.cne*, libcne, libQTEEConnector_vendor, libslimclient,
  vendor.qti.latency) → pull from S8 Pie /system/lib*; they are Pie-built, load under vndk_lite.
- LLNDK (20 libs: libc/libm/liblog/libnativewindow/...) stay Q versions (ABI-stable by contract).

**Assembly** (`tools/build_rom10.sh`): donor Q /system  + inject {Pie vndk-sp-28, the 48+11 Pie compat libs, S8
/system/vendor Pie tree, Pie firmware}  + ld.config.vndk_lite.txt (VNDK_VER=28)  + Pie init.*.rc/fstab/ueventd + sepolicy
permissive for bring-up  + remove JP/au/FeliCa apps (config/debloat.txt)  + global boot/charging anim.
Kernel = our Q kernel (Pie kgsl + APR fix + no-verity). NFC = Samsung sec-nfc (global tag/HCE); FeliCa stays dead.
Knox/KnoxGuard left STOCK (not patched). First boot = SELinux permissive, then tighten.

## 12. Vietnamese CSC (XXV) from SM-G960F OXM (G960FXXUHFVG6, Android 10)

- XXV config = `odm/etc/omc/XXV` in the OXM multi-CSC odm image → extracted to `work/donor_G960F/odm_tree/etc/omc/XXV`.
- `tools/build/omc_decode.py` (from OMCDecoder: per-byte rotate + salt XOR, then gzip; encode/decode round-trip verified)
  → decoded `work/xxv_decoded/cscfeature.xml`, `cscfeature_network.xml`.
- Network: `CscFeature_RIL_SupportVolte=TRUE`, LTE module, WB-AMR on, CNAP, IMS CLIR. customer.xml carries the VN carrier
  list + APNs (Viettel, Vinaphone, MobiFone, Vietnamobile, Gmobile, Reddi).
- Plan: install XXV into the port's `/odm/etc/omc` (sales code XXV). Caveat: the Snapdragon modem (NON-HLOS/modem.bin) only
  has Japanese carrier MBN profiles → VoLTE on VN carriers may not register even with the CSC flag; 4G data + CS-fallback
  voice will work.

## 13. One UI 2 port — architecture findings (2026-10-06)

- **Boot model**: G9600 Q uses 2SI — boot ramdisk = only first-stage `init` (+ apex/debug_ramdisk/dev/mnt/proc/sys dirs);
  it mounts the SAR system image from the **DT fstab** and switch_roots. S8 DT fstab already has `system` (verify stripped,
  `out/kernel/jpn_dtbs_noverity.dtb`); `vendor` entry disabled → S8 vendor lives in `/system/vendor`, root `/vendor` symlink.
- **Size**: G9600 /system 4214 MiB + S8 vendor 483 = 4697 > 4399 usable → remove ≥ ~350 MiB from G9600 (target ≥ 450).
- **VNDK**: S8 Pie vendor is VNDK-lite (only vndk-sp-28, 32 libs). G9600 ships only vndk-29. Port adds
  `/system/lib{,64}/vndk-sp-28` (from S8 Pie) + `/system/etc/ld.config.vndk_lite.txt` generated from AOSP android10
  template (`tools/build/gen_vndk_lite.py` → `config/vndk_lite/ld.config.vndk_lite.txt.filled`) + `vndksp.libraries.28.txt`.
- **APEX**: flattened (directories) → no loop/apexd image mounting at boot.
- **SELinux = main blocker**: S8 is NOT split-policy (vendor has no *_sepolicy.cil; monolithic /sepolicy in ramdisk).
  Q init uses split policy if /system/etc/selinux/plat_sepolicy.cil exists → needs a vendor policy half.
  Plan: (a) first boots with a monolithic Q policy is not possible without vendor cil; (b) build vendor cil from the
  G9600 vendor policy (same Samsung/QC HAL family) + S8 vendor_file_contexts, mapping via 28.0.cil, permissive first
  (androidboot.selinux=permissive needs init support on user build → check G9600 init).
- **BPF**: kernel has no BPF_SYSCALL; OK because first_api_level=24 + kernel 4.4 → netd falls back to xt_qtaguid (verify).

### Soft-lock / boot-stopper checklist for the port
1. KnoxGuard stays stock → must be cleared by Samsung check-in; never flash custom binaries while KG is locking.
2. dm-verity → stripped in DT fstab (done). AVB: n/a (S8 has no vbmeta).
3. Encryption: Pie vendor `forceencrypt=footer` → change to `encryptable=footer` (FDE still supported on Q for N-launch).
4. SELinux split-policy (above).
5. RescueParty → repeated system_server/SurfaceFlinger crashes force "factory reset" recovery prompt (seen on AP_9).
6. VNDK-lite linker namespaces (above) → missing → HAL services crash-loop.
7. Pie-vendor HAL vs Q framework: graphics (composer 2.1/allocator 2.0 OK in Q), camera provider 2.4 OK,
   Samsung extensions (vendor.samsung.*) may need framework-side shims (watch logcat).
8. FRP: after a factory reset Android asks for the previous Google account — sign in with your own account.

### How the Exynos S8 One UI 2.5 port did it (hadesRom Q, corsicanu + ananjaser1211, XDA t4208409, via Wayback)
- Donor: Note 9 N960F (Exynos 9810 → 8895, cross-SoC). Aroma installer with selectable bloat: "SELECT LESS BLOATWARE OR
  THE PHONE WILL NOT BOOT" (same system-partition size limit as ours).
- Earlier hadesTreble (t3953332): treble vendor = S9+ G965F vendor + S8 hardware blobs, `treble-convert` zip carved a
  vendor partition → vendor SELinux policy came from the donor vendor, not the S8.
- hadesKernel Q (github corsicanu/android_kernel_samsung_universal8895 branch 10, exynos8895-dreamlte_defconfig):
  RKP/UH/KAP/DEFEX/DM_VERITY/SEC_RESTRICT_ROOTING off, no BPF_SYSCALL, and `CONFIG_ALWAYS_PERMISSIVE=y`
  ("Permissive kernel - needed for hw mismatch"). Encryption listed as broken/disabled.
- For our port: `tools/kernel/patch_always_permissive.py` written (same change in selinuxfs.c) but NOT applied - applying it was
  blocked by the tool permission policy; pending the user's decision. Alternative without it: build a proper vendor
  split policy (G9600 vendor cil + S8 file_contexts) and boot enforcing.

### GalaxyOS H2.0 (One UI 2.5 for Exynos S8, `custom_roms/`) - inspected 2026-10-06
- System = Note 9 N960FXXU9FUK2 (SAR). Vendor = **Note 9's own Q vendor** (selinux plat_sepolicy_vers 29.0, full split
  policy: vendor_sepolicy.cil, plat_pub_versioned.cil, precompiled_sepolicy, vendor_file_contexts) installed into
  `/system/system/vendor`, root symlink `/vendor -> /system/vendor`. S8 hardware overlays from `GalaxyOS/device/*`
  (wifi/bt fw, mixer_paths/gains, NFC s3nrn82 rfreg, camera setfiles). fstab: no encryption. Boot = hadesKernel + ramdisk.
- Not copied: `ro.frp.pst=` (disables Factory Reset Protection), vaultkeeper/tima security props.
- **Revised vendor plan (option 2, enforcing)**: base vendor = **Tab S4 SM-T835 Android 10 vendor** (msm8998, Samsung Q,
  complete split SELinux policy) + S8 phone-specific blobs from SCV36 Pie vendor (RIL/modem, camera tuning, panel, audio
  mixer, NFC, fingerprint). Needs: SM-T835 last Android 10 firmware (U5C*).

## 14. Base vendor = Tab S4 SM-T835 T835DXU5CVG2 (Android 10) - analysed 2026-10-06
- `work/donor_T835/` (vendor/system/boot raw images + PIT); trees in WSL `~/s8rom/trees/t835_vendor`, `s8_vendor`.
- msm8998, ro.vndk.version=29, first_api 27, **split SELinux 29.0 complete** (vendor_sepolicy.cil, plat_pub_versioned.cil,
  precompiled_sepolicy, vendor_*_contexts) → enforcing boot possible; VNDK-lite workaround (§13) no longer needed.
- RIL/QMI present (LTE tablet). Size 443 MiB → budget 4214 + 443 = 4657 MiB vs 4399 usable → remove ≥ 260 MiB (+margin).
- Transplant from S8 Pie vendor (+ SELinux rules for each): fingerprint HAL (Egis, vendor.samsung.hardware.biometrics.
  fingerprint@2.1), NFC HAL (sec.android.hardware.nfc@1.1, S3NRN82 + rfreg), radio.configsvc, camera tuning/sensor
  setfiles, panel/display, audio mixer_paths/gains, sensors (S8 37 vs T835 27 files).
- fstab: drop forceencrypt (encryptable or none), keep apnhlos/modem/dsp/persist/efs mounts (same partition names on S8).

### Vendor SELinux for the S8 phone HALs (enforcing) - done 2026-10-06
- `tools/build/transplant_deps.py` → `config/transplant/{fingerprint,nfc,radio_configsvc}.txt` + `.manifest.xml`: each HAL is
  self-contained (binary + .rc + HIDL iface lib from S8 Pie **/system**/lib64, NFC also `lib64/nfc_nci_fn.so`).
  NFC data: `etc/libnfc-sec-vendor.conf`, `etc/permissions/android.hardware.nfc{,.hce,.hcef}.xml`, `com.android.nfc_extras.xml`.
  S8 NFC service also serves `android.hardware.nfc@1.1::INfc` + secure_element 1.0 (manifest).
- Rules: Samsung G9600 Q vendor policy labels `sec.android.hardware.nfc@1.1-service` as hal_nfc_default and has
  hal_nfc_default (25) / hal_fingerprint_default (59) rules. `tools/build/policy_gap.py` → `config/sepolicy/s8_phone_hals.cil`
  (64 statements, per-type typeattributeset, 20 dropped that need S9-only types).
- `tools/build/compile_policy.sh`: secilc of G9600 plat_sepolicy + mapping 29.0 + T835 plat_pub_versioned + merged vendor
  → **compiles OK** (`config/sepolicy/precompiled_sepolicy.test`, 1.1 MB).
- `tools/build/contexts_add.sh` → `config/sepolicy/vendor_{file,hwservice}_contexts.add` (S8 iface names ISecNfc,
  ISecBiometricsFingerprint; /dev/sec-nfc, /dev/esfp*); all referenced types verified present.
- Next: `tools/build/build_vendor.sh` (assemble tree: T835 vendor + transplants + merged cil + regenerated precompiled policy
  & sha256 + merged manifest + fstab without forceencrypt), then G9600 debloat ≥ 260 MiB, ramdisk, image, Odin package.

## 15. One UI 2 port - first flashable build (2026-10-06)
- Vendor (`tools/build/build_vendor.sh`, 449 MiB): T835 Q vendor; tablet QCA wifi/bt services removed; S8 transplants:
  wifi (bcmdhd: wifi@1.0 HAL, wpa_supplicant, hostapd, libwifi-hal, fw/nvram), bluetooth (BCM4361 HAL, libbt-vendor,
  hcd), NFC (sec nfc@1.1 + INfc 1.1 + SE 1.0, libnfc-sec-vendor.conf, permissions), fingerprint HAL, radio configsvc,
  S8 audio routing; manifest -7/+9; merged SELinux (precompiled regenerated, secilc OK); fstab no forceencrypt; ueventd.
- System (`tools/build/build_system.sh`): G9600 Q image resized to 1146880 blocks; 53 apps removed (`config/debloat_g9600.txt`,
  ~839 MiB); vendor in /system/vendor, `/vendor -> /system/vendor`, `/odm -> /vendor/odm` (G9600 odm + XXV, default
  sales_code XXV); labels via `tools/build/label_tree.py` (runtime path /vendor/..., fc_sort precedence) → 0 unlabeled.
  Free space 442 MiB. `out/rom/system_oneui2_s8.img{,.ext4,.ext4.lz4}`.
- Kernel: server branches `s8-pie-test` (Pie KGSL) / `s8-q-port` (Q KGSL, for T835 Q graphics). Diffs in
  `kernel/patches/`. Port kernel `out/kernel/port_Image.gz`.
- Boot (`tools/build/mkboot.py --cmdline --osver-from`): port kernel + `jpn_dtbs_noverity.dtb` + T835 2SI ramdisk + T835 cmdline
  (firmware_class.path=/vendor/firmware_mnt/image), os 10.0.0/2022-06. `boot_oneui2_{debug,release}.img`.
- Odin: `out/odin/AP_OneUI2_S8_debug.tar.md5` (2.78 GB: boot debug + TWRP + system), `AP_OneUI2_boot_release.tar.md5`.
- Known gaps (expected on first boot): fingerprint needs ET5xx kernel driver patch (§9); camera = T835 HAL with S8 sensors
  (likely broken until S8 camera libs transplanted); RIL = T835 Samsung RIL with S8 modem (verify calls/data);
  sensors/panel tuning; KnoxGuard is stock in the G9600 system (see flash prerequisites).
- **Boot 1 (AP_OneUI2_S8_debug)**: kernel OK, 2SI first stage mounted SAR system, **SELinux enforcing policy loaded**
  from /vendor/etc/selinux/precompiled_sepolicy, second stage started, then init abort: "Duplicate prefix match detected
  for 'vendor.mls.'" (G9600 plat_property_contexts already carries 9 Qualcomm vendor.* props the T835 vendor defines).
  Fix: `tools/build/dedup_contexts.py` in build_vendor.sh (property + hwservice contexts only; vndservice is a separate
  namespace). Check tool: `tools/analysis/inspect_image.sh tools/build/check_property_contexts.py`. Rebuilt → `AP_OneUI2_S8_debug_v2`.
- Boot 2 (v2): no panic, no reboot → **hang on first (bootloader) logo > 10 min** (debugpart identical to boot 1; no
  S8DBGLOG). Added **s8dbg boot watchdog** (`tools/kernel/patch_s8dbg_watchdog.py`, server branch s8-q-port commit 8beb2f790):
  `msm_poweroff.s8dbg_timeout=150` → after 150 s kernel_restart → log dumped to cache → TWRP. Cancelled by
  `installer/debug/s8dbg.rc` (on sys.boot_completed=1 write 0 to /sys/module/msm_poweroff/parameters/s8dbg_timeout).
  Iteration now via TWRP: `installer/twrp/twrp_push.ps1` (dd boot + push rc, chcon vendor_configs_file).
- Boot 3 (watchdog debug boot): watchdog fired at 150 s ('s8dbg-boot-timeout'). Not a hang: **crash loop** (28x) of
  keymaster-3-0 (exit 1) → keystore SIGABRT → surfaceflinger/zygote/... restart; QSEECOM send_cmd -22, VaultKeeper
  "Unexpected reqlen(44536), should be(44216)": T835 TZ-client HALs vs S8 TZ apps. Also hwservice add denials for
  vendor.samsung.hardware.wifi::IWifiExt and radio.configsvc::IConfigSvc (unlabeled → default_android_hwservice).
  Fixes: transplant group `tz` (S8 keymaster@3.0 + gatekeeper@1.0 services, impls, keystore/gatekeeper.{mdfpp,msm8998},
  libskeymaster3device/libkeymaster*; PREFER_S8 except shared libcrypto/libssl/libQSEEComAPI/...); 4 hwservice labels;
  T835 rc files for replaced binaries removed; manifest drops derived from transplant manifests + duplicate check.
  Vaultkeeper (Knox) left as-is (non-critical). Iteration via TWRP: `installer/twrp/twrp_vendor.ps1` (vendor.tar +
  vendor_labels.sh + apply_vendor.sh, keeps vendor/odm). pull_logs.ps1 now also collects tombstones (crash.tgz).
- Boot 4 (tz vendor): **boot animation shows** (keymaster/TZ fix works) but rotated -90°: Tab S4 vendor = landscape
  (configstore primary orientation, ro.sf.lcd_density=360, ro.minui.default_rotation=ROTATION_LEFT). build_vendor step
  5b: ro.surface_flinger.primary_display_orientation=ORIENTATION_0, ro.sf.lcd_density=480, ro.sf.init.lcd_density=640
  (S8 values), minui rotation removed. Fallback if still rotated: S8 configstore@1.1 service instead of the T835 one.
- Boot 5 (display fix): watchdog fired at 150 s again, but system_server was up ("Start dexopt ... firstBoot: true")
  → first-boot dexopt needs minutes: watchdog now 1200 s. Remaining loops: keymaster exit 1 within 30 ms →
  **`tools/build/symcheck.py`** (static NEEDED + undefined-symbol check of transplants against port vendor + Q VNDK/LLNDK):
  libkeymaster3device needs Pie `keymaster::*OperationFactory::Create*Operation` (Q changed signatures) → ship S8 Pie
  libkeymaster_portable/libkeymaster_messages in vendor (only keymaster stack uses them, `tools/analysis/users_of.sh`);
  S8 wpa_supplicant needs SSL_set_session_* (gone from Q BoringSSL) → **wifi reworked**: keep T835 Q wifi HAL /
  supplicant / hostapd (match G9600 framework), transplant only Broadcom libwifi-hal.so (+ fw/nvram data).
  radio configsvc transplant dropped: Samsung Q uses `secril_config_svc` (T835 init.vendor.rilcommon.rc); its
  hwservice label pointed at a nonexistent type. TZ rc files: T835 versions kept (Q `interface` lines).
  symcheck: 0 problems. twrp_vendor.ps1 now also flashes boot.img.
- Boot 6 (keymaster/wifi fix): boot animation correct for a few s, then **shrinks to the left**, then black screen,
  blue LED on, no watchdog return yet, no adb (user build). Hypothesis: One UI applies its default resolution
  (WQHD+ → FHD+ multi-resolution) when system_server starts; T835 display stack mis-scales the S8 panel.
  Debug-only adb at boot: `installer/debug/twrp_debug_adb.ps1` (prop.default: ro.adb.secure=0,
  persist.sys.usb.config=mtp,adb; backup prop.default.orig, -Undo). Live capture: `tools/device/capture_live.ps1`
  (logcat, dumpsys display/SurfaceFlinger/window, wm size/density, lshal, screencap, tombstones).

### Boot 7 analysis (run_20261006_135210, 2026-10-06)
- Android 10 userspace runs: zygote + system_server start, boot animation shown; black screen = system_server crash loop
  (6x `FATAL EXCEPTION IN SYSTEM PROCESS: NullPointerException IKeystoreService.exist` on null), RescueParty
  -> reboot,recovery after ~1116 s (s8dbg kernel log intact).
- Root cause 1: vendor.keymaster-3-0 exits status 1 ~15 ms after start (before any qseecom app load) -> keystore
  never registers. SELinux for hal_keymaster_default complete; Pie impl still pulled Q VNDK-29
  libsoftkeymasterdevice/libpuresoftkeymasterdevice. Fix: take both from S8 Pie /system (tz group, 18 files).
- Root cause 2: T835 vendor.pd_mapper + vendor.per_mgr abort every 5 s -> audioserver aborts. Fix: new transplant
  group 'periph' (S8 Pie bin/pd-mapper, pm-service, pm-proxy; T835 init.target.rc entries kept). symcheck 0.
- Next boot: flash vendor.tar + debug adb (prop.default) so logcat is reachable if it still loops.

### Boot 8 analysis (run_20261006_142552) - reached setup wizard, then hard reset
- Keymaster fix worked: sys.boot_completed at 116 s, boot watchdog cancelled, setup wizard shown ("internal problem" popup).
- Reset ~120 s: debug partition OEM reset reason TZBSP_ERR_FATAL_XPU_VIOLATION. Chain: pm-service / pd-mapper /
  sensors.qti `IPC_RTR: msm_ipc_router_bind: Do not have permissions` (t830_q kernel check_permissions() needs
  CAP_NET_RAW or CAP_NET_BIND_SERVICE) -> modem PIL load fails at modem.b11 (rc -11) -> MBA region unlock timeout -> XPU.
  SCV36 modem.bin verified consistent (mdt phdrs == blob sizes, span 0x8ac00000..0x91900000 = DT region).
- Root cause: Qualcomm grants NET_BIND_SERVICE via file capabilities (vendor/etc/fs_config_files); the TWRP tar push
  restores only SELinux labels. Fix = build_vendor.sh step 7b: init `capabilities` for every non-root init service
  whose binary has caps in fs_config_files (per_mgr, pd_mapper, sensors.qti, ims*, loc_launcher). periph S8 swap reverted.
- Note: the final Odin/system image should carry real security.capability xattrs (e2fsdroid + fs_config) instead.

### Boot 9 (2026-10-06) - One UI 2 runs: display/touch/USB charge/speaker OK
- Broken: tablet layout, volume panel + AOD crash, no Wi-Fi, no SIM, no USB mode dialog / adb.
- USB: One UI phone framework uses sys.usb.config=mtp,conn_gadget[,adb]; T835 rc has no trigger -> gadget unbound.
  Fix build_vendor.sh 7c (S8 conn_gadget blocks). debug_adb.sh: G9600 build.prop persist.sys.usb.config=none overrode
  prop.default -> now patches build.prop too + clears /data/property/persistent_properties.
- Layout: ro.sf.lcd_density 480 -> 640 (stock S8/S9 at 1440x2960; 480 = 480 dp wide = tablet-like).

### Boot 10 (2026-10-06) - bugreport: UI up, fixes for crashes / wifi / identity
- NFC SIGSEGV loop (NfcAdaptation::InitializeHalDeviceContext): S8 nfc service also serves android.hardware.nfc@1.1::INfc,
  manifest only declared ISecNfc -> transplant_deps EXTRA_HAL nfc.
- audioserver abort "devicePort included BT SCO ALL" (Samsung Q audiopolicy) -> build_vendor 5e splits "Bt Sco All"
  into BT SCO / Headset / Car Kit like the G9600 vendor. (Volume panel crash suspected to follow from this.)
- Identity: Q derives ro.product.* from product,odm,vendor,system -> Tab S4 values won (SM-T835, gts4lltexx fingerprint).
  5d: vendor+odm = SM-G9500 / dreamqltezh / dreamqltechn, ro.build.fingerprint pinned = G9600 system fingerprint.
- floating_feature.xml lives in /vendor/etc on Q -> One UI read the Tab S4 list (name "Galaxy Tab S4", no
  SupportForceTouch, no AOD config). 5f: G9600 list, BRAND_NAME=Galaxy S8, DUAL_SPEAKER FALSE, no spk_stereo.
  Touch IC reports PRESSURE events fine (sec_ts), so the pressure home key should follow.
- Wi-Fi: bcmdhd looked for /etc/wifi/bcmdhd_sta.bin_b0 + nvram_net.txt (t830_q Kconfig defaults) and /data/misc/conn
  (no ANDROID_PLATFORM_VERSION). build_kernel.sh: BCMDHD_FW/NVRAM_PATH=/vendor/etc/wifi/{bcmdhd_sta.bin,nvram.txt},
  PLATFORM_VERSION=10 (-> /data/vendor/conn, P+ behaviour). S8 macloader replaces the T835 one (T835 wifi.rc kept).
  New kernel in out/twrp_push/boot.img (previous: out/kernel/boot_boot9.img).
- SIM: modem + RIL OK, SIM LOADED (MobiFone 45201, SMSC read) but PS attach rejected, rejectCause=8, CS searching.
  Not a ROM crash; needs on-device checks (IMEI via *#06#, SIM in another phone). ro.csc.sales_code empty (CSC inactive).
- Camera app: "no capability for 0" (T835 camera HAL vs S8 sensors) - pending. CMAS crash = harmless app bug.

### Boot 11 (2026-10-06) - layout + TWRP wipe panic
- Layout root cause (bugreport): WM config sw640dp 270dpi land, logical 2220x1080 letterboxed in physical 1440x2960
  (physicalFrame 0,1129-1440,1830). One UI's resolution/density override persisted in /data from the first (Tab S4
  vendor, density 360) boot: 360*0.75 = 270. Cleared by the data reset; recomputed from S8 panel + S9 feature list.
- After a TWRP "Wipe Data": Kernel panic in ext4lazyinit on sda24 ("Something is wrong with group 0 ... itable unused
  count") -> /data errors=panic -> s8dbg redirects to recovery. Fix: installer/twrp/format_data.sh (mke2fs,
  lazy_itable_init=0) via twrp_format_data.ps1. Avoid TWRP's Wipe Data on this port.

### Boot 12 (2026-10-06) - bugreport2: AOD / pressure key / volume panel OK
- "Internal problem" dialog = Build.isBuildConsistent() -> VintfObject.verifyWithoutAvb() on Treble (not fingerprints).
  tools/build/vintf_kcheck.py vs compatibility_matrix.3.xml: kernel lacked HARDENED_USERCOPY, MODULES, MODULE_UNLOAD,
  MODVERSIONS and had USELIB=y -> build_kernel.sh fixed (+IKCONFIG_PROC). Offline kernel check now clean.
- Display: One UI default FHD+ via display_size_forced (logical 1080x2220, physicalFrame full panel). T835 composer shows
  it unscaled in the top-left; touch maps the full panel. Fix: drop SEC_FLOATING_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL
  (stay WQHD+ 640 dpi) + `wm size reset; wm density reset` on the device.
- Wi-Fi: with ANDROID_PLATFORM_VERSION>=9 bcmdhd prefixes /vendor itself -> /vendor/vendor/etc/wifi. Config back to
  /etc/wifi/bcmdhd_sta.bin + /etc/wifi/nvram.txt (resolves to /vendor/etc/wifi/...nvram.txt_murata_r033_b0).
- Bluetooth: S8 service loaded the T835 Qualcomm passthrough impl (ttyHS0, "SOC init failed during patch downloading").
  bluetooth EXTRA_ELF += lib64/hw/android.hardware.bluetooth@1.0-impl.so (Broadcom, libbt-vendor + bcm4361B0_*.hcd).
- Sensors all present (LSM6DSL/AK09916C/TMD4906/LPS22HB, Samsung Screen Orientation Sensor) -> auto-rotate expected
  to work once the display is native. NFC HAL up but fw 0.0.0 "need bringup" - needs capture after toggling NFC.
- Pending: fingerprint (ET5xx kernel driver), iris + camera (T835 camera HAL vs S8 sensors: "Unknown camera ID 0"),
  cellular (MobiFone rejectCause 8; SIM works in a S21 FE).

### Boot 13 (2026-10-06) - bugreport3: 4G + Wi-Fi WORK
- Display still 1080x2220 in the top-left: display_size_forced=1080,2220 / density 480 are Samsung *system defaults*
  (defaultSystemSet:true) -> `wm size reset` returns to them. Workaround: `wm size 1440x2960; wm density 640`.
  Root: T835 SDM shows the forced size unscaled (SDM props seen: vendor.display.mixer_resolution, disable_scaler ...).
- SSRM/SDHMS "Fails to parse policy XML": limiter(GPUFreqMax)=520000000 invalid -> ro.hardware.chipname=SDM845 (S9
  system) + ro.vendor.gpu.available_frequencies unset. apply_vendor.sh sets chipname=MSM8998 in system build.prop;
  vendor build.prop gets Adreno 540 frequency list.
- VoLTE: IMS registers "VIETTEL VOLTE" profile but "no VoLTE feature" / "disallow Call Service": ro.csc.sales_code empty
  because EFS imei/mps_code.dat = KDI (backup checked read-only) and the G9600 odm has no KDI CSC. apply_vendor.sh
  creates odm/etc/omc/KDI = copy of XXV + adds KDI to sales_code_list.dat (EFS untouched).
- Bluetooth now Broadcom path; fails at rfkill0/state EACCES: T835 rc never chowns it -> etc/init/s8_bluetooth.rc
  (S8 Pie "on boot" block: rfkill, /efs/bluetooth/bt_addr + ro.bt.bdaddr_path, bluesleep proc, btlock).
- NFC: "Nfc need bringup" (fw 0.0.0, init failed at boot - boot log rotated out). Rotation: listener registered via
  SemContext, not conclusive. New tools/device/capture_boot.ps1 records logcat from boot for NFC/BT/camera/rotation.
- Next big item: camera + iris (S8 mm-camera stack transplant), fingerprint (ET5xx kernel driver).

### Boot 14 (2026-10-06) - boot log capture (tools/device/capture_boot.ps1)
- CSC alias works: ro.csc.sales_code=KDI (XXV content), chipname MSM8998, Viettel LTE data OK.
- VoLTE: IMS PDN "ims" (VIETTEL IMS APN) rejected by modem: SETUP_DATA_CALL cause -8, RIL-QMI "Data call end reason
  (2/211)" -> PDN_THROTTLED. SCV36 modem.bin carries only 2 MCFG MBNs: generic/apac/dcm and generic/apac/kddi -> no
  VoLTE profile for VN carriers in the au modem firmware. Only fix = different CP (e.g. SM-G9500) = RF/NV risk,
  needs the user's decision. Incoming calls must use CSFB (3G); not exercised during the capture.
- NFC: NfcService "NFC Kernel Driver doesn't exist!!" -> G9600 NfcNci checks /sys/class/nfc/nfc_support (newer
  Samsung kernels). Kernel patch tools/kernel/patch_sec_nfc_support.py (server commit cda440322).
- Bluetooth: rfkill0/state still EACCES and ro.bt.bdaddr_path unset -> s8_bluetooth.rc not effective; moved to
  ueventd sysfs rules (/sys/devices/*rfkill/rfkill* state/type) + ro.bt.bdaddr_path in vendor build.prop.
- Rotation: WindowOrientationListener uses SemContext "Auto Rotation", getProposedRotation always -1 (T835 sensor HAL
  never delivers SContext). New transplant group 'sensors' (S8 HAL impl/service, sensors.ssc/grip, libsensor1/_reg,
  sensors.qti; QMI/dsutils/mdmdetect/sdsprpc kept T835 via SHARED_KEEP_T835[_PREFIX]); abi_users.sh: T835 users OK.
  build_vendor never deletes etc/init/hw/*.rc any more.
- Camera: provider legacy/0 with 0 devices; T835 mm-camera probes tablet sensors. Next: S8 mm-camera stack (32-bit
  daemon + sensor/chromatix/actuator libs + camera HAL) vs Q kernel msm_camera ABI.

### Boot 15 (2026-10-06) - rotation works; NFC/BT/VoLTE/display deep-dive
- Q loads /vendor/build.prop with the vendor_init SELinux context: ro.vendor.gpu.*, ro.bt.*, ro.build.fingerprint were
  silently dropped -> now written to system build.prop by apply_vendor.sh ("# S8 port props").
- BT rfkill: Q ueventd wildcards match per path segment (FNM_PATHNAME); BT node is DT /soc/bt_driver ->
  /sys/devices/soc/soc:bt_driver/rfkill/rfkill* (tools/analysis/dtb_find.py). NFC node /soc/i2c@c179000/sec-nfc@27.
- NFC: kernel nfc_support fix worked (no "Kernel Driver doesn't exist"); now "Hal is nullptr"/"fail nfa enable":
  G9600 NfcNci needs ISehNfc 2.0. nfc group now from the G9600 Q vendor (DONOR in transplant_deps: sec.android.hardware.
  nfc@1.2-service, nfc_nci_sec.so, vendor.samsung.hardware.nfc@2.0.so) + config in G9600 format with S8 SEN82AB clock/
  firmware/rfreg (build_vendor 7e). Note: present()/symcheck treat /system/lib64 as visible to vendor - not true.
- Display: base=1080x2220 480dpi persisted as settings *defaults* -> apply_vendor.sh deletes display_size_forced /
  display_density_forced / screen_resolution_state from /data/system/users/0/settings_*.xml.
- VoLTE / modem: tools/analysis/mcfg_parse.py (MCFG: 16 B header + 8 B version, items [len u32][type][attr][u16]):
  SCV36 kddi/dcm and G9500 d_world profiles contain ONLY /policyman/carrier_policy.xml (RAT policy) - no IMS items.
  G9500 CP (G9500ZCS6DUD1): cmcc volte_op/volte_su, ct, cu, d_world. -> CP swap is unlikely to change VoLTE; on hold.
  IMS PDN fails locally (2/211 = IPv6 call throttled) on the first attempt of every boot, also on the first Viettel
  boot. Viettel does not whitelist devices (pixel-volte-patch #185: ims + xcap APNs suffice; Viettel has no 3G ->
  VoLTE mandatory for calls). Next test: new IMS APN IPv4-only + xcap APN (bypasses per-APN/IPv6 throttle).

### Display shrink root cause (2026-10-06, decompiled G9600 services.jar with jadx)
- WindowManagerService (line ~4562): if CoreRune.FW_DYNAMIC_RESOLUTION_CONTROL (compile-time true on S9) and Global
  display_size_forced is EMPTY -> WindowManagerServiceExtension.applyScreenRatioToSizeDensity(): base = 0.75 x initial
  (1440x2960@640 -> 1080x2220@480), saved incl. Secure default_display_size_forced/default_display_density_forced.
  Skipped only if FW_HIGH_PERFORMANCE_MODE, a non-empty forced size, or /sys/class/lcd/panel/window_type == "ff ff ff".
- wm size 1440x2960 = native -> DisplayContent.setForcedSize stores "" -> FHD again next boot. config_maxUiWidth=0.
- Fix: store non-empty native values: Global display_size_forced=1440,2960, Secure display_density_forced=640 and the
  default_* twins (apply_vendor.sh setxml, or settings put over adb). T835 SDM never scales a smaller logical size.
- Display, final root cause (libsurfaceflinger.so disassembly): Samsung SF MultiResolution matches the WM size to an
  HWC display mode; on a match (1080x2220 = S8 DT timing "fhd") it sets mScaledDisplay and renders into that size,
  expecting the panel DDI multires scaler (S8 kernel ss_dsi multires cmds) - the T835 composer never drives it.
  No match -> "[MultiResolution] Unsupported Resolution" -> return, normal GPU projection. WM stays 1080x2220 even with
  the settings at 1440,2960 (runtime caller not found; irrelevant after the fix).
  Fix: tools/build/dtb_single_mode.sh removes .../ss_dsi_panel_S6E3HA6_AMB577MQ01_WQHD/qcom,mdss-dsi-display-timings/{fhd,hd}
  from all 3 JPN DTBs -> out/kernel/jpn_dtbs_noverity_wqhd.dtb; kernel counts timings dynamically (mdss_dsi_panel.c).
  Previous boot.img kept as out/kernel/boot_before_wqhd.img.

### Research pass after the display fix (2026-10-06) - fixes built, not yet flashed
- **CSC/VoLTE (real bug)**: the first system image labelled the whole odm as `vendor_file` (label_tree used the runtime
  path /vendor/odm, where the vendor catch-all rule wins) and XXV came from the Windows mount as uid 1000 / 0777.
  Boot 15 log: scs "Device doesn't have cscfeature.xml corresponding to KDI", ePDG/IMS CscParser EACCES on
  /odm/etc/omc/KDI/conf/customer.xml -> the Vietnamese CSC features (CscFeature_RIL_SupportVolte, IMS settings) were
  never loaded. G9600 odm.img: etc = vendor_configs_file, app/priv-app = vendor_app_file, root 0644/0755.
  Fix: apply_vendor.sh relabels odm + root-owns XXV/KDI; build_system.sh labels odm as /odm.
- **VoLTE PDN**: IMS SETUP_DATA_CALL (profile 2, APN ims, IPV4V6) refused in ~20 ms with QMI 2/211
  (= INTERNAL PDN_IPV6_CALL_THROTTLED, libqmi enum) and retry=INT_MAX, on the first AP request of each boot; network
  advertises VoPS=SUPPORTED. au's own IMS APN is also "ims" (IPv6) -> likely the KDDI modem config/profile throttles
  that APN by itself. Test: IMS APN protocol IPv4 (+ xcap APN) after the CSC fix.
- **Bluetooth (real bug)**: T835 vendor labels /sys/devices/platform/soc/soc:bt_driver/rfkill/... but on this 4.4 kernel
  the node is /sys/devices/soc/soc:bt_driver/... -> rfkill state stays `sysfs`, hal_bluetooth_default may only write
  sysfs_bluetooth_writable -> EACCES regardless of chown. Added the 4.4 path to vendor_file_contexts.add.
  (LineageOS 17.1 dreamqlte: BCM4361B0 reports as BCM4347B0; they disabled LPM for an AOSP libbt-vendor bluesleep
  crash - we use Samsung's own libbt-vendor; bluesleep.c Pie vs Q differs only in a proc read fix.)
- **Fingerprint**: G9600 FingerprintService only uses ISehBiometricsFingerprint@3.0 (BiometricFeature.FEATURE_JDM_HAL
  false) -> the S8 Pie @2.1 HAL could never work. G9600 libbauthserver supports Egis ET510 on /dev/esfp0 ->
  fingerprint group now from the G9600 vendor (3.0 service + fingerprint.default.so + bauth libs) + s8_fingerprint.rc.
  Kernel: stock binds DT "fps,common" with an unpublished driver; tools/kernel/patch_et5xx_fps_common.py teaches the Q-tree
  et5xx-spi.c that node (fps-* props, optional sleepPin), SENSORS_ET5XX=y (server commit 6eb95c9b4).
  Risk: Q bauth TZ client vs the S8 Pie fingerprint TA.
- **Camera**: T835 mm-camera read the S8 rear EEPROM and wanted libmmcamera_s5k2l2sa.so (absent) -> 0 cameras.
  S8 sensors: rear S5K2L2 (F12QL) / IMX333 (F12QS), front S5K3H1 (V08QL) / IMX320 (V08QS), iris S5K5E6.
  Both stacks run mm-camera in-process in the provider; T835 Samsung provider@3.0 loads the HAL via plain
  camera_module_t -> keep it, transplant the whole S8 Pie HAL + mm-camera (transplant group 'camera', 319 files,
  PREFER_S8_RE so shared 32-bit GPU/graphics libs stay Q). Sensor list msm8998_camera_dream.xml (name compiled into
  libmmcamera2_sensor_modules.so) + chromatix xmls via data.txt. Kernel camera_v2/companion/OIS = G9500 Pie source.
  Companion ISP + OIS firmware are opened by the kernel at /system/etc/firmware (absent in G9600) ->
  out/twrp_push/system_add.tar + build_system.sh 3b. libandroid.so (not vendor-visible on Q): stats_modules NEEDED was
  stale (patchelf --remove-needed); libsensorlistener -> vendor stub (config/stubs, tools/build/build_stubs.sh).
  One UI 2 camera app keeps the S9 /system/cameradata/camera-feature.xml (newer format than S8's).
- **NFC**: G9600 HAL knows S3NRN82/SEN4 family; compares chip CSC vs sales code (KDI = SCV36 chip) - test pending.
- **Iris**: T835 vendor already starts /system/bin/irisd (S9 Q IrisService/IrisTlc via QSEECom) - needs the camera
  first (S5K5E6 via the S8 HAL), then TA compatibility.
- vendor.tar is now root-owned (was uid 1000 = system); bin/ root:shell 0755 like the image build.

### Error triage + GalaxyOS comparison (2026-10-06)
- GalaxyOS H2.0 (Exynos S8, Note9 N960F system) telephony/IMS app set == ours (imsservice, EpdgService, ImsSettings,
  UnifiedWFC, SamsungDialer, TelephonyUI, ModemServiceMode, serviceModeApp_FB, charon, imsd, init.ril*.rc). Only
  Exynos extras (ikev2-client, init.rilcarrier.rc) + RcsSettings / EweMBMSServer_TEL. Its scripts only pick the EFS
  sales code's CSC and tweak cscfeature.xml -> its VoLTE works because the CSC is readable and the Exynos modem has
  global carrier configs. Nothing app-level to copy. (lists: work/galaxyos/lists/)
- Boot 15 log, error sources by volume: Bluetooth app death x24 (rfkill label, fixed), PROCA (pa_daemon_qsee respawn
  every 5 s + hwservicemanager ctl.interface_start ISehProca x380 -> not started + removed from manifest),
  VaultKeeper TA mismatch (T835 Q vaultkeeperd vs S8 TA; KnoxGuard reads its state through it -> deliberately left
  alone), izat xtwifi-inet-agent (binary absent -> disabled), macloader dhd fw/nvram path EACCES (S8 wifi_brcm.rc +
  nvram_path chown + restorecon), audio platform_info: Pie-only snd device names + mic-info section skipped
  (metadata only), Knox VPN iptables cleanup / CMAS / DeX settings provider / timerslack from apps = benign.
- No ipsec/eris/charon crash in the captured boots; labels of /system/bin/{eris,charon,imsd} are correct. ePDG
  (com.sec.epdg) CscParser failed on the unreadable KDI customer.xml - fixed by the odm relabel; needs a new capture.
- Kernel log in bugreports starts at ~78 s (ring buffer overrun) -> debug boot cmdline log_buf_len=4M;
  tools/device/capture_boot.ps1 now also saves a bugreport (full dmesg) + fingerprint/CSC/camera-fw checks.

### Boot 16 (boot_20261006_193214) -> camera/torch, FM, iris, fingerprint, LED, SSRM (2026-10-06)
- **Camera + torch**: S8 mm-camera probes all sensors (IMX333 rear, IMX320 front + _cc, S5K5E6 iris), but the rear
  session needs Samsung 3A per module (hwinfo_make_3a_name -> F12QS_libTsAe.so, libTsAf/Awb/Accm[Front]) - not in
  the transplant -> session abort -> companion thread used a destroyed mutex -> FORTIFY abort of the whole provider
  (83 restarts) -> no camera, no torch. Fix: camera group += lib/*libTs*.so (+ vendor libstdc++ from S8 /system).
  tools/build/vendor_visible_check.py (runs in build_vendor) now fails the build on any non-vendor-visible NEEDED lib.
- **SSRM "Fails to parse policy XML"**: SDHMS hard-codes raw/siop_starqlte_sdm845 and validates CPUFreqMax/GPUFreqMax
  against ssrm.jar CustomFrequencyManagerService tables (/sys/power/cpufreq_table, kgsl gpu_available_frequencies);
  Adreno 630 520/675 MHz invalid on Adreno 540. tools/build/build_sdhms_overlay.sh -> static RRO SdhmsS8Overlay.apk with
  the same policy remapped to the next lower valid S8 step (CPU from DT cpufreq tables + Samsung cpufreq_limit).
- **Device rc lost**: init.target.rc imports init.${ro.product.device}.rc; since the identity is dreamqltechn the T835
  init.gts4llte.rc was never imported -> no irisd, faced, sswap, /dev/radio0 perms, /efs/carrier. -> etc/init/s8_device.rc.
- **FM radio**: kernel RADIO_RTC6213N (DT richwave,rtc6213n @0x64, same chip as the S9 CHN), HybridRadio back
  (system_add.tar), /dev/radio0 system:audio 0660.
- **Fingerprint**: G9600 fingerprint@3.0 HAL loads the S8 TA fine, then common_prepare fails -> "FP Sensor is out of
  order". S9 board has the ET510 reset on etspi-sleepPin; S8 Rev11/12 has none -> tools/kernel/patch_et5xx_ldo_reset.py:
  reset = LDO power cycle, sensor powered at probe (server commit c582a7822).
- **LED indicator**: Settings shows it only if /sys/class/sec/led/led_blink can be stat'ed; Q policy leaves it plain
  sysfs (no getattr for system_app) -> genfscon /devices/virtual/sec/led -> sysfs_led_writable; floating feature
  SETTINGS_SUPPORT_LED_INDICATOR added.
- *#06#: SamsungDialer -> SECRET_CODE "06" -> com.sec.android.app.servicemodeapp ShowIMEI (present, needs only
  TelephonyManager.getImei) - needs a log taken while dialing.

### Boot 17 (boot_20261006_212201) -> flashable zip s8port_update_20261006_2139.zip (2026-10-06)
- Camera provider crash loop gone (libTs fix): cameraserver lists rear 0 / front 1 / front-cc 90, no error traces.
  Iris + face services opened the front cameras; Samsung Camera never connected. Logcat stream died at +1 min
  (adb reconnect) -> tests not logged. capture_boot.ps1 now restarts logcat, logcat -G 16M, end dump of all buffers,
  dropbox crashes (crashes.txt), wifi_p2p.txt, iris.txt.
- Camera: HAL still linked the T835 libuniapi/libuniplugin (NEEDED by camera.msm8998.so), libflash_pmic (PMIC
  flash = torch), libremosaic_daemon, libjpegdmahw -> S8 copies; T835-only uniplugin plugins removed (S8 shipped only
  dejagging + IDDQD).
- Fingerprint: same "common_prepare fail" x6 / "FP Sensor is out of order" with the LDO-reset kernel, plus
  "read SNSR Type success but file has wrong data" (G9600 libbauthserver). S8 and G9600 fingerprint.default.so call
  the identical ss_fingerprint_* API (G9600 lib only adds Goodix gf*) -> G9600 @3.0 service + S8 Pie
  fingerprint.default.so/libbauthserver/libbauthtzcommon (matching the S8 TA). transplant_deps.py: S8V: prefix.
- FM radio: impossible on SCV36 hardware. JPN DT i2c@20 (FM bus) status="disabled"; GPIO 99/100/129 = ISDB-T tuner
  lna-en/rst/irq. Samsung's SCV36 app list (docs.samsungknox.com/CCMode/SCV36_P.pdf) has "ANT Radio Service"
  (ANT+, not FM) and "MobileTV" (com.samsung.android.app.dtv.isdbt). HybridRadio removed again (debloat + installer).
- IPsec: no crash in boots 15-17 logs; com.sec.epdg (unlabelled persistent system app = the "IPsec" popup candidate)
  logs only "RILRECEIVER not initialized" (ePDG<->RIL IIL link). IOF "Verification FAILED" for charon etc. = Samsung
  file-integrity check failing for every binary (harmless). Needs crashes.txt from the next capture.
- Quick Share: wpa_supplicant p2p0 "Could not configure driver mode" -> falls back to a dedicated P2P device (normal
  for bcmdhd); configs identical to S8 stock. Needs a capture of a receive attempt.
- Other ROMs checked: LineageOS 17.1 dreamqlte (codyalank) - fingerprint not working, camera basic; Samsung-S8-MSM8998-Dev
  dreamqltechn proprietary-files (used to spot the T835 camera support libs above).
- tools/build/make_flashable_zip.sh + installer/update-binary: TWRP zip = boot.img + vendor.tar + system_add.tar +
  apply_vendor.sh (checks bootloader SCV36*, extracts to /sdcard/s8port_zip, log -> /sdcard/s8port_apply.log).

### Boot 18 (boot_20261006_214804) -> s8port_update_20261006_2206.zip (2026-10-06)
- Torch works (S8 libflash_pmic). Camera HAL3 opens camera 0 fine, but SamsungCamera 10.5 (S9) needs 9 samsung.android.*
  vendor tags (availablePreviewStreamConfigurations, availableFeatures, afAvailableModes, digital zoom lists...) the S8
  QCamera HAL never publishes -> "There is no capability" / NPE Size.toString in changePreviewSurfaceSize.
  -> S8 SamsungCamera 9.0.01.78 (SemCamera/API1 + Samsung params = what the S8 HAL serves; SemCamera + secimaging +
  semextendedformat + libsemcamera_jni present in Q framework; same platform cert 34df0e7a...; privapp whitelist
  covers all its privileged perms) + S8 /system/cameradata, via system_add.tar; installer removes the S9 apk/oat/data.
- Fingerprint with the S8 bauth stack: (1) "Wrong fp version. Expected 768, got 513": service checks
  hw_device_t.version == 0x300 -> tools/patches/patch_fp_module_version.py (S8 module device constant 'HWDT'/0x201 @0xce0 and
  HMI module_api -> 0x300; device struct slots 112..208 identical, checked by disassembly). (2) "BAuthDeviceOpen sys call
  failed rv 209": S8 lib ioctl magic 'j' (0x40206a00) vs Q driver 'k' (0x40206b00), opcodes/struct identical ->
  tools/kernel/patch_et5xx_ioc_magic.py (server commit 8a0b55d26), new boot.img.
- Iris: S9 irisd/libIrisTlc (TZ secure preview API: IrisTlc_secure_preview_with_fd/mem, IB, createInputSurface) vs the
  S8 sec_iris TA in /vendor/firmware_mnt/image (S8 NON-HLOS): IrisTlc_SendHatHmacKey -> TA -13, then -10. S8
  irisd lacks com.samsung.android.biometrics.IIrisDaemon + the new module calls -> no drop-in; needs a protocol shim
  (not started). TsAf_load_lib_front libptr NULL = fixed-focus front, benign.
- Quick Share: accept -> MdxKit semListen loop, every p2pListen fails with SupplicantStatus 6 FAILURE_IFACE_DISABLED.
  Boot: "p2p0: Failed to initialize driver interface" (nl80211 set mode on bcmdhd p2p0 = WL_ENABLE_P2P_IF netdev),
  fallback dedicated P2P device; kernel: wl_cfgp2p_del_p2p_disc_if at the Wi-Fi restart (~39 s), p2p0 stays DOWN.
  T835 supplicant is a Qualcomm build; S8 one is Broadcom but only supplicant 1.1 / ISehSupplicant 1.0 (framework
  wants 1.2 / 2.0). Next: bcmdhd change_virtual_iface on p2p0 ("netinfo not found" -> -ENODEV?) / driver P2P model.
- IPsec popup did not trigger (dropbox has no ipsec/epdg crash). Other dropbox crashes: cmas background-start (benign),
  com.samsung.ipservice / ipsgeofence (to check).
- "IPsec crash" = most likely com.samsung.ipservice (label "IPService", Gallery AI tagger, cmhservice uid): native
  SIGABRT "Failed HIDL return status not checked: DEAD_OBJECT" in libsnap_hidl SnapSessionImpl::Open ->
  vendor.samsung.hardware.snap@1.1 (T835 SNAP HAL; the S8 had IPService but no SNAP) died. SNAP service tombstone
  not captured yet. com.samsung.android.ipsgeofence: Zygote selinux_android_setcontext(5022, platform:privapp) failed.

### Boot 19 (boot_20261006_222242) -> s8port_update_20261006_2246.zip (2026-10-06)
- Rear camera, real root cause (kernel log): msm_companion_fw_write "failed to open
  /system/etc/firmware/F12QS_Isp0_imx333.bin, err -13" (and OIS "No OIS FW ... in the system"): the drivers open the
  files from the camera HAL process; Q policy: hal_camera_default may read vendor_file_type/firmware_file, not
  system_file (sesearch). -> /system/etc/firmware/* labelled vendor_firmware_file (apply_vendor.sh, build_system.sh).
- S8 SamsungCamera 9.0 installed and opens, but cameraserver serves it via Camera2Client (API1 over HAL3):
  "Unknown command 1807/1508/1821/1000", "Requested preview FPS range 15 - 30 is not supported" -> setParameters
  failed. Pie cameraserver had Samsung extensions for it (string com.sec.android.app.camera; gone in G9600's).
  QCamera2Factory (disassembled): persist.camera.HAL3.enabled default "1" ("0" on factory builds, ro.build.PDA FA*),
  0 -> every camera device version 0x100 -> CameraClient (HAL1) passes Samsung params/commands to the HAL.
  -> persist.camera.HAL3.enabled=0 in the S8 port props (persist.camera. = vendor_camera_prop, readable by the HAL).
- Fingerprint: S8 stack now opens the device, TA "dualfp" loads, still common_prepare fail. Kernel: SPI clocks on, but
  BLSP12 SPI pins GPIO81-84 stay in spi_sleep = function "gpio" (spi_qsd never transfers in secure mode); spi_qsd
  exports fp_spi_request_gpios() for this, the Q ET5xx never called it -> tools/kernel/patch_et5xx_spi_pins.py
  (server commit b1c7d9a1c): select the active blsp_spi12 state on every FP_SET_SPI_CLOCK.
- ipsgeofence Zygote abort: uid 5022 had no name (T835 vendor passwd/group lack vendor_ipsgeofence/advmodem/
  felicalock) -> build_vendor 7f adds them from the G9600 vendor (seapp_contexts already match).
- IPService: no crash this boot; SNAP sessions create/destroy fine.
- Iris: S9 iris service also needs the S9 HAL tag samsung.android.control.shootingMode (IllegalArgumentException)
  -> on top of the TA protocol mismatch; iris not portable this way.
- Quick Share: P2P device iface is created at 23.3 s (wl_cfg80211_add_if p2p0 iftype 7), then the Wi-Fi HAL powers
  the chip off/on during the Q scan-only -> client-mode start (wl_cfgp2p_del_p2p_disc_if, wl_android_wifi_off) and
  the supplicant's re-add fails ("p2p0: Failed to initialize driver interface") -> listen = IFACE_DISABLED.
  Next: test Wi-Fi off/on after boot; bcmdhd p2p0 netdev (WL_ENABLE_P2P_IF) vs P2P_DEVICE re-creation.

### Boot 20 (bootloop_20261006_225714 / run_20261006_225759) - kernel panic, fixed (2026-10-06)
- debug partition klog: fingerprint@3.0 ioctl FP_SET_SPI_CLOCK -> fp_spi_request_gpios -> pinctrl_select_state(NULL)
  -> "Kernel panic - not syncing: Fatal exception" at 16.7 s -> s8dbg redirected the reset to recovery (TWRP).
  spi_qsd gets its pinctrl handle in init_resources() = first runtime resume of the master, never reached in TZ mode.
  -> tools/kernel/patch_spi_qsd_fp_pinctrl.py (server commit 803fb4422): pinctrl on demand, error instead of NULL deref.
  -> s8port_update_20261006_2301.zip (boot.img only changed vs 2246). Previous boot.img: out/kernel/boot_spipins_panic.img.
- bootloop_diag "system partition is EMPTY" line is a false alarm (it checks /system/build.prop; SAR layout).

### Boot 21 (run_20261006_235830) - SError panic, reverted; error triage (2026-10-07)
- With the pinctrl fix, fp_spi_request_gpios succeeded and 1 ms later: "Bad mode in Error handler detected, code
  0xbf000002 -- SError" -> panic. TZ owns/locks the BLSP12 pin config (TLMM XPU) -> HLOS must not touch GPIO81-84.
  The pin theory was wrong: both pin commits reverted (server b29f0315c / 9b53331cd). Kernel = boot-19 kernel + ioctl
  magic 'j' fix. Kernel-side secure SPI is like stock (alias spi12 = c1ba000, "disable bam for BLSP tzspi, spi num(12)").
- Stock driver = CONFIG_SENSORS_VFS8XXX_EGIS (Egis variant of the Synaptics vfsspi driver, magic 'j'): not in any public
  tree (jesec cm-14.1 / icepie msm8998 have only Synaptics vfs8xxx + et5xx 'k').
- Installer: rm /data/vendor/biometrics/* (G9600 bauth cache "file has wrong data"); wifi.direct.interface=p2p-dev-wlan0
  (HAL default p2p0 collides with the bcmdhd p2p0 netdev; dedicated P2P device re-created by the supplicant).
- Kernel log: "audit: rate limit exceeded" x48 in boot 19 -> SELinux denials are being dropped (the camera-firmware
  denial never showed) -> consider audit rate limit off for debug boots.

### Boot 22 (boot_20261007_001057) -> s8port_update_20261007_0045.zip (2026-10-07)
- Camera (HAL1 mode works: device@1.0, imx333 streams, preview buffers NV21 1440x1080 stride 1440): app UI frozen =
  SamsungCamera 9.0 activates its shooting mode only after SemCamera onPreviewStarted (notify 0xf412
  COMMON_SHOT_PREVIEW_STARTED, requested via sendCommand 1473 before startPreview). S8 Pie HAL never sends 0xf412
  (only 0xf411) -> tools/patches/patch_semcamera.sh: Q semcamera.jar posts 0xf412 itself 1 s after the request (in
  system_add.tar; installer removes the stale semcamera odex/vdex). Front-camera switch was blocked by the same gate.
  Vertical-line preview: not explained by the buffer geometry; re-check once the UI is active.
- Torch level crash: SystemUI -> setTorchModeStrength -> Samsung cameraserver "Camera 0 has no flashlight" for HAL1
  devices (ERROR_ILLEGAL_ARGUMENT, uncaught) -> SEC_FLOATING_FEATURE_CAMERA_SUPPORT_TORCH_BRIGHTNESS_LEVEL FALSE.
- Quick Share: wifi.direct.interface=p2p-dev-wlan0 made it worse (T835 Qualcomm supplicant: "Could not read interface
  p2p-dev-wlan0 flags: No such device", P2P never set up) -> prop dropped; supplicant stack replaced by the G9600
  Broadcom Q build (wpa_supplicant + vendor.samsung.hardware.wifi.supplicant@2.0, libkeystore-engine-wifi-hidl,
  libwpa_client; supplicant HIDL 1.2 / ISehSupplicant 2.0, BRCM hang/FT handling) - matches the S8 bcmdhd driver.
- IPService (Gallery AI tagger): crash loop = T835 SNAP HAL armnn FileNotFoundException for
  /vendor/saiv/image_understanding/db/aig_classifier/aig_classifier_cnn_light.caffemodel -> debloated.
- Fingerprint: unchanged (TA loads, common_prepare fails, TA sets FP_SET_SENSOR_TYPE -1 = it identifies no sensor).
  Stock S8 design is a "common" driver: /dev/fps with /dev/esfp0 + /dev/vfsspi symlinks, HAL handles ET510 and
  Synaptics NAMSAN. Katuwu S8 CHN Q kernels (downloads/kernel.zip, dream2qltechn.zip, built from
  github.com/Katuwu-commits/s8-chinese-custom-kernel) use the public Synaptics vfsspi driver only; CHN Rev09 DT lists
  both NAMSAN and ET510 on the same pins (LDO 74, DRDY 127, BLSP12), CHN Rev12 only NAMSAN, JPN Rev12 says ET510.
  BLSP12 SPI node + "disable bam for BLSP tzspi" identical to ours.

### Fingerprint reverse engineering (2026-10-07) -> s8port_update_20261007_0353.zip
- Stock SCV36 kernel (work/stock_CZE1, CONFIG_KALLSYMS_ALL=y, CONFIG_SENSORS_VFS8XXX_EGIS) symbolised on the build
  server: ~/re/stock.elf (github.com/marin-m/vmlinux-to-elf, venv ~/re/venv), annotated disassembly with
  tools/analysis/re_annotate.py (adrp/add -> strings/symbols): ~/re/fps_all.txt, ~/re/stock_text.dis.
- Stock driver = one "fps,common" driver (/dev/fps; init symlinks esfp0 + vfsspi) serving two ioctl dialects:
  magic 'j' Egis messages (opcode @msg+28) and magic 'k' Synaptics/namsan VFSSPI_IOCTL_* ("it is not egis/namsan
  ioctl" otherwise). fps_power_control(1): LDO (or fps-regulator) on, select fps pinctrl state, 1.6 ms, sleepPin, 12 ms.
  Egis HLOS register ops (0x01-03, 0x1a stores spi_value, 0x20-25, 0x30/31, 0x40-43) = no-ops; 0xa4/a5/a8 interrupt
  init/free/abort.
- KEY DIFFERENCE: stock FP_SET_SPI_CLOCK / FP_DISABLE_SPI_CLOCK never touch the BLSP12 clocks (max_speed_hz + wakelock
  only); no fp_spi_clock_set_rate/enable/disable/request_gpios caller anywhere in the stock kernel (only msm_spi_probe
  -> fp_spi_clock_get). The S9 Q et5xx re-rated the core clock to 12.5 MHz and gated it on DISABLE (boot 22 @17.96 s,
  mid TA bring-up). -> tools/kernel/patch_et5xx_tz_clock.py (server commit 2579dd369), kernel #21.
  Previous boot.img: out/kernel/boot_before_tzclock.img.

### Torch level + camera (2026-10-07) -> s8port_update_20261007_0443.zip
- Torch slider crash, reverse engineered (tools/analysis/re_thumb.py: capstone Thumb disassembler with PLT/string resolution):
  CameraService::setTorchModeStrength -> CameraFlashlight -> ProviderFlashControl -> CameraProviderManager::
  setTorchMode(id,on,strength) -> DeviceInfo1 -> cast to SEC device 1.0 -> vendor.samsung.camera.device@1.0
  secSetTorchModeStrength -> CameraModule::sehSetTorchModeStrength -> camera_module_t +0xa8
  set_torch_mode_strength(const char*, bool, int); S8 Pie HAL slot NULL -> -ENOSYS(-38) -> "has no flashlight".
  Kernel S2MPB02 rear_flash sysfs already takes torch levels 1001..1010 (One UI levels 1..5 = 1001/1002/1004/1006/1009).
  -> config/stubs/camera_torch_shim.c = new camera.msm8998.so (copies the real HMI, fills +0xa8: real set_torch_mode
  on, then the level via sysfs); real HAL renamed lib/hw/camera.msm8998_s8.so; TORCH_BRIGHTNESS_LEVEL back to TRUE.
- Rear camera: companion ISP firmware now loads (CRC companion 0xF8B1FC4B == AP), so the stripes are not a missing
  companion FW. Next data: tools/device/capture_camera.ps1 (screencap + SurfaceFlinger buffer dump per step).

### Camera preview stripes (2026-10-07) -> s8port_update_20261007_1150.zip
- User: both cameras capture fine in every app, preview striped in ALL apps; only SamsungCamera freezes.
- Root cause (reverse engineered gralloc1::GetAlignedWidthAndHeight, S8 Pie vs T835 Q libgrallocutils): NV21
  (HAL_PIXEL_FORMAT_YCrCb_420_SP) row stride S8 = ALIGN(w,16); T835 = ALIGN(w, Adreno GetGpuPixelAlignment) except
  w in {176,352,720}. S8 HAL1 preview buffers (usage 0x40020000 = CAMERA_HEAP|HW_CAMERA_WRITE, NV21 1440x1080) are
  written with HAL padding stride 1440 -> display reads 1472 -> sheared stripes. Snapshots use HAL ION buffers -> fine.
  (UBWC ruled out: both IsUBwcEnabled need ALLOC_UBWC and exclude NV21; bit 30 is CAMERA_HEAP in this gralloc1 gen.)
  -> tools/patches/patch_gralloc_nv21.py: lib64 jump-table byte 0x16d8 0x50->0x00, lib Thumb 0x38b8 blx -> b.n 0x38fc; nop.
- SamsungCamera freeze: still open, needs tools/device/capture_camera.ps1 run.

### Notification LED + torch slider (2026-10-07) -> s8port_update_20261007_1202.zip
- LED lit by the bootloader, dead in Android: lights HAL boot log "/sys/class/sec/led/led_pattern ... Open error! : [13]".
  Kernel SM5720 RGB driver is in (same LED config as stock). Stock SCV36 ramdisk init.rc chowns /sys/class/sec/led/*
  to system; the Q system init.rc does not, and the policy only let system_server/system_app write sysfs_led_writable,
  but on Q the writer is hal_light_default. -> s8_device.rc chown/chmod lines + hal_light_default/vendor_init rules
  in config/sepolicy/s8_phone_hals.extra.cil.
- Torch slider: SystemUI Rune.QPANEL_ENABLE_TORCH_INTENSITY = SemFloatingFeature
  SEC_FLOATING_FEATURE_CAMERA_SUPPORT_TORCH_BRIGHTNESS_LEVEL (/vendor/etc/floating_feature.xml); the 0353 zip still
  carried the 0045 vendor (FALSE). TRUE since 0443; slider = long-press the flashlight tile.

### Camera "in use by another app" regression (2026-10-07) -> s8port_update_20261007_1303.zip
- 1150/1202 (first zips flashed with the torch wrapper): every app failed to open either camera right after boot.
  Cause: QCamera2Factory::camera_device_open / open_legacy in the S8 Pie HAL check
  `module == &HAL_MODULE_INFO_SYM.common` ("Invalid module. Trying to open %p, expect %p") and the wrapper handed
  them its copied HMI. The real HMI lives in the HAL's .bss (filled by its constructor).
- Fix (config/stubs/camera_torch_shim.c): the copied HMI gets its own hw_module_methods_t + open_legacy that call
  the real functions with the real module pointer. Everything else in 1202 unchanged.
- 1303 was still broken: OFF_METHODS was 0x18 (= hw_module_t.dso, NULL for a dlopen'ed HAL) instead of 0x14 ->
  NULL deref in the wrapper constructor -> camera provider crash. Fixed -> s8port_update_20261007_1402.zip.
- Verified under qemu-arm with the G9600 Q bionic linker (tools/shim_qemu_test): fake HAL = full PASS
  (open/open_legacy/torch/strength); real S8 HAL: HMI copy ok (id camera, api 2.4), real open/open_legacy with
  the wrapper's module -> -38 (= the 1202 bug reproduced), through the wrapper they pass the module check and
  reach QCamera2Factory (stops there: no camera hardware in qemu). Real HMI: .bss, filled by init_array 0x64db9
  (template 0x14a9e0 'HWMT' api 2.4, methods @+0x14, 0x80..0x94 functions, 0x98..0xaf zero).

### Samsung Camera buttons do nothing (2026-10-07) -> s8port_update_20261007_1437.zip
- 1402: preview/open camera/front+back/torch slider OK; S8 SamsungCamera 9.0 buttons animate but nothing happens =
  "Shooting mode is not activated" (Camera.onStartPreviewCompleted never runs).
- Why the semcamera.jar patch (0443..1402) never worked: the G9600 framework.jar (BOOTCLASSPATH, boot image) carries
  its own com.samsung.android.camera.core.SemCamera and the app has no <uses-library semcamera> -> the boot copy runs.
- Fix in the HAL wrapper (config/stubs/camera_torch_shim.c): HAL1 devices get a copied camera_device_ops_t (23 ops);
  after each successful start_preview a thread sends notify(0xf412 COMMON_SHOT_PREVIEW_STARTED) 0.5 s later
  (set_callbacks recorded; stop_preview/release/close bump a generation under a lock so it never fires late).
  Chain verified by RE: vendor.samsung.camera.device@1.0-impl sNotifyCb forwards msg_type unchanged;
  G9600 CameraClient::lockIfMessageWanted passes (msg & 0xfffff805) != 0 as "samsung defined callback msg" (no lock,
  no msg-enabled check) -> handleGenericNotify -> app SemCamera EventHandler 0xf412 -> onPreviewStarted.
  qemu fake-HAL test (tools/shim_qemu_test): notify 0xf412 + cookie after start, none after stop/release/close, PASS.

### Samsung Camera: crash on camera switch + vertically flipped front preview (2026-10-07, research)
- Stock S8 Pie (work/stock_CZE1/system.raw.img): libcameraservice.so links libseccameracore.so
  (SecCameraCoreManager + Shot* classes: Single, Beauty, Burst, HDR, Panorama, SlowMotion, OutFocus, WideMotionSelfie,
  Interactive...) between CameraClient and the HAL1 device. It produced COMMON_SHOT_PREVIEW_STARTED (1473 handled in the
  core, msg 0x20 enabled, event on first preview frame), swallowed sendCommand 1000..1091 (setShootingMode = 1000+mode,
  cameraInitVersion 1000), 1473, 1645, 1710, 1730 and forwarded everything else (beauty 0x49d.., flip 0x5e6/0x5e7,
  effects 0x510/0x512) to the HAL. G9600 Q cameraserver has no SecCameraCoreManager; ~20 of its deps are missing.
- S8 HAL QCamera2HardwareInterface::sendCommand returns 0 for unknown commands (default -> r6 = 0), so the forwarded
  1000-range commands are harmless no-ops; not the crash.
- getOrientation identical Pie/Q; all 3 devices are HAL1 (0 back 90, 1 front 270, 90 front 270); HAL has
  preview-flip/flip-mode params (off). App renders preview itself with GL (com.samsung.android.glview GLTexture.setFlip).
- Pie framework is odexed with compact dex: vdexExtractor (server ~/vdexExtractor, built w/o -Werror) + baksmali on the
  .odex next to its .vdex works (dexlib2 reads cdex through the oat); bare .cdex does not.
- GalaxyOS (custom_roms, One UI 2.5 S8 *Exynos* only: dreamx/great) runs the One UI 2.5 camera2 app on the Exynos HAL3
  (ExynosCamera3 + SecCameraVendorTags) -> no HAL1/SecCameraCore problem there. S8 Snapdragon HAL3 (QCamera3) only has
  samsung.android.control/lens/lens.info vendor sections. No public One UI 2 port for Snapdragon S8/Note8 found.
- Next: device log of the switch crash + SurfaceFlinger transform of the front preview (tools/device/capture_samsung_camera.ps1).

### Audio quality: S8 Pie audio HAL stack (2026-10-07) -> s8port_update_20261007_1831.zip
- Before: only S8 mixer_paths/platform_info/policy were transplanted; HAL, ACDB loader + ACDB files, SoundBooster
  (+ params), sound trigger HAL were the Tab S4's (quad NXP TFA9896 speakers, TDM SoundBooster, tablet ACDB).
- The S8 speaker is a Maxim MAX98506 whose protection/loudness runs in the S8 HAL: sec_dsm_spkr_prot_processing,
  sec_dsm_spkr_prot_control_tx_topology, VI feedback on TERT_MI2S_TX (S8 mixer has no QC "vi-feedback" path, so the
  T835 HAL dsm_feedback flag cannot replace it). ACDB files are format-compatible (QCMSNDDB/AVDB, same loader API)
  but must match the S8 ADSP + S8 platform_info acdb ids. SoundBooster v8 (S8) vs v9 (Q) param formats differ.
- Now: config/transplant/audio.txt (33 files: S8 HAL renamed audio.primary.msm8998_s8.so, ST HAL, ACDB loader/GCS/
  SVA libs, offload effect libs, SoundBooster plus + lib_SoundBooster_ver800, 8 *_cal.acdb, SoundBoosterParam,
  audio_output_policy.conf) under the T835 Q audio@5.0/effect@5.0/ISehDevicesFactory services; S8 audio props
  (vendor.audio.safx.pbe.enabled=true ...); T835 TFA/TDM/WSA plugin libs removed.
- Wrapper config/stubs/audio_hal_shim.c: audio.sec_primary.default.so (Samsung Q extension, G9600 libaudiohal
  SecDevicesFactoryHal) dlsym()s sec_get_audio_device_instance / sec_get_audio_stream_instance (Q-only) and only
  calls standard ops on the results (adev +0x60/+0x64, stream +0x28/+0x2c) -> wrapper tracks adev + streams by io
  handle (open/close_output +0x6c/+0x70 verified against the HAL's exported adev_*_output_stream, input +0x74/+0x78).
  qemu test tools/shim_qemu_test/audio_test.sh PASS. Precedent: GalaxyOS (S8 Exynos) runs the S8 Pie vendor audio
  HAL under One UI 2.5 and only overrides mixer_paths / SoundBoosterParam / dsm.bin.
- Dolby: Q DAX (T835 libswdap + dax-default.xml) kept; S8 Pie had libswdap with no dax xml.

### ISDB-T TV (SCV36 One-Seg/Full-Seg) port (2026-10-07) -> s8port_update_20261007_1912.zip (+ audio stack)
- Hardware: FCI FC8300 on BLSP1 SPI (spi@c175000 "isdbt_spi_comp") + isdbt_pdata (pwr-en, rst gpio100, lna-en gpio99,
  irq gpio129, BBCLK3, 19.2 MHz xtal). Kernel: the T830 Q tree already has the SCV36-flavour driver
  (drivers/media/isdbt/fc8300_spi: lna-en, isdbt_gpio_active/suspend, SEC_ISDBT_FORCE_OFF, shutdown) and the stock
  config enables it; boot logs show isdbt_thread + isdbt_force_power_off kthreads (= probe completed, /dev/isdbt).
  ioctl ABI ('t', 0..29, struct ioctl_info 516 bytes) identical to the stock driver (stock.elf RE).
- SELinux: the T835 Q vendor policy already carries Samsung's Q TV policy (oneseg_mw, oneseg_mw_exec,
  oneseg_mw_service, oneseg_data_file, mmb_device, oneseg_apk, platform_app rules, file contexts for
  /system/bin/SDtvService, /dev/isdbt, /data/one-seg); G9600 plat_service_contexts maps ISDtvService.* etc.
- Userspace (tools/build/stage_tv.sh -> system_add): stock priv-app MobileTV_JPN_HYBRID (platform cert, privapp xml),
  /system/bin/SDtvService (+ service def from the S8 init.carrier.rc in init.isdbttv.rc, /dev/isdbt chown),
  /system/etc/one-seg, middleware libs S8 vendor/lib64 -> /system/lib64 (platform libs, system namespace),
  libQSEEComAPI copy (Full-Seg RMP TA via QSEECom), libsdtv_compat.so (GraphicBuffer::lock(uint32_t,void**) ->
  Q 4-arg lock; get_malloc_leak_info stub; NEEDED-added to libSDtvPorting/libonesegutils), libSDtvService
  /system/vendor/lib64 dlopen paths -> /system////////lib64 (equal length). Installer: SDtvService 0755 oneseg_mw_exec.
- Caveat: ISDB-T is the Japanese standard; Vietnam broadcasts DVB-T2 -> no channels in VN even when working.

### 0021 freeze = audio HAL crash loop (2026-10-08) -> s8port_update_20261008_0048.zip
- debug/freeze.txt: audio@2.0-service SIGSEGV every 5 s (strcmp NULL in libhardware hw_get_module_by_class).
  S8AudioShim: "cannot locate symbol set_sched_policy" - Pie libcutils export, on Q in libprocessgroup (VNDK-SP).
  Fix: patchelf --add-needed libprocessgroup.so on audio.primary.msm8998_s8.so (build_vendor.sh 2c, checked);
  all other imports of the audio transplant resolve against Q libs (static check). Wrapper fallback: valid HMI with
  open() = -ENODEV instead of an all-zero HMI. qemu: real HAL + wrapper dlopen OK (HMI "QCOM Audio HAL").
- TV port disabled (make_vendor_push.sh, S8PORT_TV=1 to re-enable); apply_vendor.sh removes the 1912/0021 TV files.

### Camera save / video / mic (camfp_20261008_014344) -> s8port_update_20261008_0154.zip (2026-10-08)
- Samsung Camera crash = SecurityException registerContentObserver(com.samsung.android.provider.stickerprovider):
  stock S8 priv-app StickerProvider (no privileged perms) added (make_vendor_push.sh). Fixed in 0121.
- Photo never saved: auto LLS -> reprocess count 2, LLS plugin missing ("libhifills_interface.so not found") -> 2nd
  pass never runs, no JPEG. S8 Pie kept the uni plugins (hifills, blurdetection, focuspeaking, hypermotion,
  smartfocus, vdis: interface + core) in /system/lib -> now SYSTEM:lib/... in config/transplant/camera.txt (S8 cores
  replace the T835 ones; build_vendor's T835-plugin cleanup skips listed files). Symbols checked vs Q VNDK.
- Video "write error" = AudioRecord -22: APM "Input device list is empty!" at boot. Audio wrapper bug:
  sec_get_audio_stream_instance type 0 = output, 1 = input (was swapped) -> sec_dev_open_audio_stream failed for
  every stream; for the input that fails openInput -> no mic for any app. Fixed (qemu test updated, PASS).
- Front preview upside down (180 deg) only in SamsungCamera (GL SurfaceTexture preview, HAL orientation front 270):
  open - compare Pie vs Q CameraClient display-orientation / buffer transform (~/re/pie_cs.so).
- Fingerprint: TA "cgst" (FP cmd 0x10) finds no sensor -> FP_SET_SENSOR_TYPE unknown -> common_prepare fail x6.
  Kernel power/reset sequence normal. Next: tools/device/fp_live.sh (live BLSP2 clocks + SPI pinmux during HAL start).

### Vendor symbol audit (2026-10-08) -> s8port_update_20261008_0224.zip
- tools/build/vendor_symbol_audit.py: every vendor ELF resolved through its own NEEDED closure in the Q vendor namespace
  (vendor lib*/vndk-ext, VNDK-SP/VNDK-29, LL-NDK). Found: libhifills set_sched_policy (-> +libprocessgroup; this was
  why the 0154 low-light capture still never finished), libOpenCv/libxcv.camera.samsung __aeabi_idiv0 (->
  config/stubs/aeabi_compat.c libaeabi_compat.so). Remaining: T835's own lib64/lib_SoundAlive_AlbumArt_ver105.so
  _Unwind_Resume (stock T835 file, left). Run it after every vendor change.
- Mic: still "could not find device for source 5" on 0154 although the wrapper type fix is in vendor.tar -> need
  dumpsys media.audio_policy (added to tools/device/power_dump.sh).
- Battery: tools/device/capture_power.ps1 (+power_dump.sh): RPM/system sleep stats, wakeup sources, lpm/cpuidle, crash
  loops, batterystats. post_boot (re-enables lpm sleep) runs at boot_completed (boot dmesg). Capture pending.

### Front preview flip (camfp_20261008_023304) -> s8port_update_20261008_0239.zip (2026-10-08)
- Photos (rear + front) now saved (0224 plugin fixes). Video: still no mic ("could not find device for source 5").
- Front flip root cause (disassembly, ~/re_cs): Pie CameraClient::sendCommand(3=SET_DISPLAY_ORIENTATION) =
  getOrientation(deg, facing==FRONT), arg2 ignored. G9600 Q: arg2==1 -> unmirrored transform for any facing.
  S8 SamsungCamera 9.0 passes arg2=1 and also sends HAL cmd 1510 (VT flip mode -> QCamera flipHorizontal) -> FLIP_H
  before ROT_90 = upside-down preview. tools/patches/patch_cameraservice_orientation.py: a3440 cmp.w r11,#1 ->
  cmp.w r11,#0x80000000 (system_add/lib/libcameraservice.so); apply_vendor labels system_add lib* as system_lib_file.
- Scripts: user runs copies on another PC (C:\Users\minhh\Documents\s8\tools, old versions) -> they need the current
  capture_cam_fp.ps1 / capture_power.ps1 / fp_live.sh / power_dump.sh copied over. fp_live.sh now also dumps the
  boot audio lines + media.audio_policy (mic).

### Reset during fp_live + restart loops (2026-10-08) -> s8port_update_20261008_0300.zip
- debugpart: OEM_RESET_REASON 0x9 TZBSP_ERR_FATAL_XPU_VIOLATION = fp_live.sh reading /sys/kernel/debug/gpio +
  pinctrl pinconf/pinmux (all TLMM regs incl. TZ-owned BLSP12 GPIO81-84; stock DT has no reserved-gpios either).
  Script fixed (no pin/gpio dumps). Never read those debugfs files on this device.
- Same klog: init restart loops every ~5 s = CPU wakeups: argos-daemon (T835 argosd, needs CONFIG_ARGOS /
  /dev/network_throughput, absent on S8) -> argos.rc removed (build_vendor); ss_conn_daemon2_service (G9600 /init.rc,
  DeX on PC / Samsung Flow, exits at once) -> "disabled" added by apply_vendor; vaultkeeper ("There is no VK ID",
  ~10 s) left alone (KnoxGuard reads its state through it - KG rule).
- Mic: dumpsys media.audio_policy on 0239 (2nd boot) lists Built-In Mic + Built-In Back Mic -> wrapper type fix works;
  the failed video was on the 1st boot after flashing (no boot log). Re-test video.
- Fingerprint: type_check.dat = "Fail" (HAL cache), BLSP2 QUP6 SPI clk 19.2 MHz; this kernel's clk debugfs has no
  enable_count. After ctl.restart the HAL does not reopen /dev/esfp0 (cached Fail). Still: TA cgst finds no sensor.

### Fingerprint clock test (debug/fp_clk_run2, 2026-10-08)
- BLSP2 AHB + QUP6 SPI clocks forced on via clk debugfs, HAL + zygote restarted: HAL reopens /dev/esfp0, TA dualfp
  (/vendor/firmware_mnt/image = device's own) runs cgst (FP cmd 0x10) -> still no sensor, type_check.dat "Fail",
  common_prepare fail x6, recovery fail 38, SetSPIStatus (FP cmd 0xc 65) qsapp ret 21. -> HLOS clock theory ruled out.
- Our et5xx power path = stock fps_* (LDO gpio74, pinctrl default/idle/sleep on gpio127/74, 10 ms settle; JPN Rev11/12
  have no sleepPin, only Rev09 has fps-sleepPin on pcal6524 expander pin 20). "sfst" = HAL reads
  /sys/class/fingerprint/fingerprint/type_check (stock = last FP_SET_SENSOR_TYPE value). Minor: our driver rejects
  FP_SET_SENSOR_TYPE -2 with -EFAULT (stock stores it).
- Next: tools/device/fp_tz_test.sh -> QSEE log (tzdbg/qsee_log) of the dualfp TA during the probe + regulator states.
- fp_tz (debug/fp_tz): board = "DREAMQ JPN Rev12", androidboot.revision=12 -> no sleepPin, DT node as expected.
  tzdbg qsee_log/log empty (production TZ, no TA logging). Same result (sfst not supported -> cgst -> out of order).
  Regulators: every disabled rail maps to a non-FP consumer in the stock DT (wil6210, sdhc2, hrm lvs1/l19, cam, BT,
  display) or to none (s2abb01-ldo, s2dos03-ldo2: no phandle = no consumer in stock either) -> no missing FP rail found.
- Remaining discriminators: (a) did FP ever work on this unit on stock SCV36 firmware (hardware check);
  (b) boot stock SCV36 Pie kernel (Samsung-signed, KG-safe) + stock DTB with our Q ramdisk -> if the TA finds the
  sensor there, it is our kernel; if not, userspace/TA or hardware.
- Differential emulation (tools/analysis/fpemu.py, Unicorn on the build server, ~/re/emu_*.txt): stock fps_* vs our etspi_*
  driven through probe/open + the HAL ioctl sequence, external calls stubbed + logged. Same GPIO/pinctrl actions;
  differences only in timing/order: stock power-on LDO -> idle pins -> 1.6 ms -> 12 ms (ours 0.05 + 10 ms), stock reset
  = LDO toggle 1.1 ms + 12 ms without pin changes (ours full power cycle 5 ms + 10 ms). -> tools/kernel/patch_et5xx_stock_timing.py
  (server commit 71e52ef8b), re-emulated = identical to stock. -> s8port_update_20261008_1054.zip (boot.img only
  changed; previous out/kernel/boot_before_stocktiming.img). If FP still fails, the HLOS driver is ruled out.
- New report: AOD auto + manual brightness do nothing (to investigate; needs live adb or a capture).
- Kernel #22 (stock timing) flashed live (Magisk-patched out/kernel/boot_stocktiming_magisk.img, previous boot backed up
  to /sdcard/boot_backup_k21.img): fingerprint unchanged (need to cgst -> common_prepare fail -> out of order).
  => HLOS fingerprint driver ruled out. Left: rest of our kernel vs stock (TZ/qseecom/clock/bus side) or Q userspace.

### Live device access (2026-10-08)
- Phone is on the user's other PC: PHONE_PC in config/local.env; WSL helpers ~/ph (adb cmd) and ~/phsh (push +
  run a script as root). TWRP made adb-by-default: tools/build/twrp_adb_default.sh (all USB modes = adb-only gadget,
  sys.usb.config=adb on boot) -> out/twrp/twrp_scv36_adbdefault.img flashed (original: out/twrp/
  recovery_before_adbdefault.img). Verified: root adb in recovery ~25 s after `adb reboot recovery`.

### AOD brightness (2026-10-08) - fixed live, in build_vendor
- G9600 framework-res config_aodBrightnessValues = [0,40,71,94] -> AODService_v50 SUPPORT_BRIGHTNESS_CONTROL: doze mode
  always 0x10002 (HLPM) + 4-level nit value by an S9-only path (dream screenBrightness -1). S8 panel driver
  (S6E3HA6 mdss_samsung_panel_lpm_store: mode+3 as u8 -> 1/2 = ALPM/HLPM 2 nit, 3/4 = 60 nit) -> stuck at 2 nit.
- Fix: static RRO tools/build/build_framework_overlay.sh -> /vendor/overlay/FrameworkS8Overlay (2 values) -> AOD uses the S8
  scheme: mode 4 (60 nit) / 2 (2 nit) by light sensor. Verified live: "LPM_MODE : HLPM ... bl_level : 2NIT" in a dark
  room. Manual 4-step slider no longer offered (as stock S8). Installed live by remounting / rw (vendor is /system/vendor).
- Note: on our debug kernel `adb reboot` from Android can be redirected into TWRP (s8dbg, cmd=adb); `adb reboot` from
  TWRP boots Android.

### Wi-Fi Direct / Quick Share (live, 2026-10-08) - in progress
- Supplicant = G9600 Broadcom build; service args + p2p/wpa overlays identical to stock S8 Pie.
- After Wi-Fi on: HAL creates p2p0, supplicant "nl80211: Could not configure driver mode / p2p0: Failed to initialize
  driver interface" then "P2P: rsdb mode is set" (dedicated P2P device fallback), framework "P2P interface setup
  completed"; p2p0 link up 16:03:30.65, link DOWN 16:03:33.5 -> later SupplicantP2pIfaceHal stopFind() status 6
  IFACE_DISABLED, p2pSet(discovery_icon) status 1. Hypothesis: p2p0 netdev taken down -> supplicant marks the P2P
  iface disabled. Next: find who downs p2p0 (bcmdhd wl_cfgp2p / netd), compare with S8 Pie; functional test needs
  the user to unlock (secure keyguard blocks the Wi-Fi Direct screen over adb).
- ROOT CAUSE (2026-10-09): on CMD_START_CONNECT the framework sets the per-network random MAC through the Wi-Fi HAL.
  Our HAL was the T835 (Qualcomm tablet) build: SetUpState(false) -> SetMacAddress -> SetUpState(true). bcmdhd4361
  powers the chip off on wlan0 down (wl_android_wifi_off) -> wl_cfgp2p_del_p2p_disc_if -> p2p_wdev NULL forever ->
  SET_AP_WPS_P2P_IE 2 "init discovery error -19 / Enable discovery failed", p2p0 left DOWN -> IFACE_DISABLED ->
  Quick Share ReceiverConnectionFail. Stock S8 kernel driver = same version/symbols (no missing feature); the S8 Pie
  and G9600 (Broadcom) HALs set the MAC with the iface UP (no SetUpState strings) -> G9600 HAL now in
  config/transplant/wifi.txt. Live: MAC set without chip reset, P2P device kept, p2p0 UP, connect 0.35 s.
  Confirmed by the user 2026-10-09: Quick Share works.

### ISDB-T TV re-enabled (2026-10-09)
- Live: SDtvService runs as u:r:oneseg_mw, registers ISDtvService.SDtvStackService; MobileTV_JPN_HYBRID 1.3.57 is a
  privileged app. Full TV-stack symbol audit vs Q bionic/system: only free_malloc_leak_info was missing (stub added).
- Self-inflicted bootloop on the way: extracting a tar with a "./" entry into /system made /system 0644 -> init
  "Error getting file context handle" -> execv(/system/bin/init) EACCES -> panic 2.4 s (debug partition klog). Fixed
  (chmod 0755 in TWRP); system_add.tar now has no "./" entry and apply_vendor.sh re-sets /system 0755.
- Newer "Mobile TV 3.3.11" (APKMirror, Android 10+) = com.samsung.android.app.dtv.sbtvd = Brazil SBTVD/ISDB-Tb app:
  needs the Brazil platform framework com.samsung.android.dtv.sbtvd.* (16 classes not in the APK, not in the
  G9600/S9/SCV36 systems) + Ginga middleware; different broadcast profile than Japan's ISDB-T. Not usable here.
  The SCV36 Japanese app (1.3.57) is the newest that matches this phone's SDtvService stack.
- SCV36 app crashes fixed: live player UnsatisfiedLinkError for libBML.so (One-Seg BML) and libTvsystemInterface.so
  (Full-Seg bml_aprofile) - both stock vendor/lib64, now in stage_tv.sh (+ /system/fonts/BML.ttf). The SIGSEGV
  tombstones (art_quick_generic_jni_trampoline, sp=0) were the player thread returning into a VM already shutting
  down after that Java crash - not a separate bug.
- DVB-T2 (Vietnam) is impossible on this tuner: FC8300 demod is ISDB-T only in silicon, outputs only TS over SPI.

### Iris plan (2026-10-09 research, offline) - T835 Q iris stack + T835 sec_iris TA, ready to test
- Why the earlier S9 (G9600) attempt failed: its SecIrisService uses IRController type 1 = HAL_V3 (camera2 +
  samsung.android.control.shootingMode, S9-only tag) and its irisd/libIrisTlc speak the SDM845 TA protocol.
- Tab S4 SM-T835 = same SoC + same iris sensor S5K5E6 (identical chromatix libs). Its Q SecIrisService uses type 0 =
  HAL_V1 (SemCamera id 90, shot-mode 39, no-display-mode, setIrisDataCallback) - functionally identical to stock S8
  Pie's IRV1Controller; the S8 HAL implements exactly that (setIrisCamera, secure IRIS buffers, FD callbacks, IR LED
  CAM_INTF_PARM_IRIS_LED_*). G9600 semcamera.jar has the iris callback API; G9600 vs T835 libcameraservice CameraClient
  (HAL1) identical. IIrisDaemon(22)/IIrisService(23)/IIrisServiceReceiver(7) AIDL identical G9600 vs T835 framework.
  T835 irisd/libIris*/iris.default.so link on the G9600 system (IKeystoreService::asInterface = dead import, no reloc).
  SecIrisService: same platform cert, android.uid.system, uses-library semcamera.
- TA: NON-HLOS.bin from each BL: S8 and T835 sec_iris both HW_ID 3002000000200000 (MSM8998, Samsung OEM, model 0),
  SW_ID 0x..0C v1, APP_ID 0x165 -> T835 TA should be accepted. T835 TA 14 MB vs S8 3 MB (new engine). authhat: same
  code segments on S8/T835. S9 TA = HW_ID 6000.. (SDM845), useless.
- Loading: irisd has no read on firmware_file; the TA comes in via the kernel (request_firmware,
  firmware_class.path=/vendor/firmware_mnt/image) and the kernel secure-CCI (CONFIG_MSM_SEC_CCI_TA_NAME="sec_iris")
  loads it by name too -> must be visible IN /vendor/firmware_mnt/image (apnhlos, read-only, never written).
  init may mounton firmware_file dirs (not files) -> s8_iris.rc bind-mounts a merged copy (stock CZE1 image dir +
  T835 sec_iris.*, 57 MB, system has 457 MB free) over it on post-fs, gated on ro.boot.bootloader=SCV36KDU1CZE1.
- Kernel: nothing missing vs stock (all stock iris/secure-camera/tz_i2c symbols present; T830 tree adds IR LED exports).
- Tools: tools/build/stage_iris_t835.sh (-> ~/iris_stage, files.txt with labels), tools/device/iris_live.sh install|rollback
  (backup /sdcard/iris_g9600_backup, list /sdcard/s8port_iris_files.txt). Not yet run on the phone.
- Test: iris_live.sh install -> reboot (single TWRP bounce) -> check mount (/vendor/firmware_mnt/image/sec_iris.b02
  size 5007294), irisd log (TA load / SendHatHmacKey), Settings > Biometrics > Iris enroll; logcat IrisService,
  IRIS_DBG, mm-camera, dmesg qseecom/tz_i2c/s2mpb02. Watch-outs: kernel loading the S8 TA before the bind (would show
  b02 size 1535150), HAT/keymaster with the S8 keymaster TA, IR LED eye-safety timeouts.

### 2026-10-09 afternoon: iris live, Secure Folder gate open, Gear VR apps
- User ran knox_sf_live.sh + iris_live.sh. Bind mount works (/vendor/firmware_mnt/image/sec_iris.b02 = 5007294 = T835).
  T835 SecIrisService crash-looped: IrisService.onCreate getString(0x01040252) = T835 framework-res id of
  config_keyguardComponent; G9600 has it at 0x0104025b -> unflattenFromString null -> NPE. tools/patches/patch_seciris_t835.sh
  remaps it (only differing framework id; layout XML uses public ids), apk keeps its v1 platform META-INF (Q does not
  verify /system app contents). stage_iris_t835.sh applies it. Live: IrisService up, "IRController HAL_V1", no crash.
  irisd loads sec_iris lazily (session start) -> next: user enrolls (PIN + eyes), then capture irisd/TA/camera logs.
- Secure Folder: after the services.jar patch PersonaManagerService logs isSecureFolderSupported true; creation needs
  the user (Samsung account + lock screen).
- Gear VR: system side already complete on the port (panel hmt_on/hmt_bright, GearVrManagerService "vr",
  com.samsung.feature.hmt(.tethered), kernel USB_HID/HIDRAW/UHID/USB_HMT_SAMSUNG_INPUT, oculus.crt, libgearvr).
  Installed the 14 apps from downloads/GearVR_SystemApps.zip (S9 SM-G960F extract, no splits) as user apps:
  vrsvc 3.2.04.10 (android.uid.system, same platform cert -> uid 1000), vrsystem, vrsetupwizard, vr.gallery2,
  com.oculus.{systemdriver,ocms,horizon,home,systemutilities,systemactivities,vrshell,vrshell.home,mediaplayer,
  browser} 9.0. The Oculus ones failed INSTALL_FAILED_VERIFICATION_FAILURE (Play Protect on adb installs) ->
  verifier_verify_adb_installs=0 only for the install, then restored (deleted, was unset).
  Store/login are dead upstream (store shut May 2024); use Gear VR Service developer mode / SideloadVR to launch
  installed apps. Not done (declined): emulating Meta's login/entitlement backend.
- Gear VR Service dev mode = Settings.Global vrmode_developer_mode (set 1 live; also sys.hmt.developer,
  disable_launch_vr_home, setupwizard_skip_update_check in its provider). VR apps have no LAUNCHER category
  (monkey: "No activities") - launched via VR shell / dev mode.
- VR browsers: Oculus Browser 8.1.5 = Chromium 79 compiled into one 50 MB libchrome.so with Oculus's VR UI;
  Samsung Internet for Gear VR (not in the zip) ended at 5.6 (Aug 2018). Neither engine can be swapped (closed,
  monolithic). Open-source route: Firefox Reality (MPL-2.0, GeckoView, separately updatable engine) - last Go (VrApi
  3DoF, same runtime as Gear VR) build 12 rc6 oculusvr3dofStore arm64 (2020-08) declares
  com.samsung.android.vr.application.mode=vr_only -> installed live (org.mozilla.vrbrowser). Next: test in headset;
  if it runs, rebuild FirefoxReality/Wolvic oculusvr3dof flavor with a current GeckoView (needs Oculus Mobile SDK).
- Offline VR without headset (dev mode), gates found + opened (all local settings):
  1. Settings.Global vrmode_developer_mode=1 (Gear VR Service dev toggle).
  2. Settings.Global vr_setupwizard_completed=1 (value the wizard writes on success; GearVrManagerService:
     "setupwizard completed, developer mode enabled! start launch!"). 0 = "start pending launch" -> online wizard.
  3. vrsvc provider content://com.samsung.android.hmt.vrsvc.vr/secure key=allow_vr_api_permission value=1 (its
     developer-screen toggle) + restart vrsvc -> no more "Thread priority security exception" (VrApi init -2).
     (That provider also stores deviceId = IMEI: never dump it unfiltered.)
- VrApi: last Gear VR system driver (com.oculus.systemdriver 9.0) = VrApi 1.1.26 (Apr 2020). DriverLoader
  nativeCheckVersion rejects newer loaders: FR 12 = 1.1.35, 10.1 = 1.1.31, 9.1/8 = 1.1.29, 7.1 = 1.1.26 (fits).
  FR 7.1 (org.mozilla.vrbrowser, Jan 2020, Gecko ~72) installed: vrapi_Initialize [end] OK, then it self-kills
  ~1 s later because the activity is paused behind the PIN keyguard -> next test needs the screen unlocked.
  ovr_GetDeviceType 'SM-G9500' NOT FOUND (table only S6/S7/Note) is logged but not fatal.
- Engine upgrade path: FR/Wolvic are open source (MPL-2.0) -> rebuild the oculusvr3dof flavor against Mobile SDK
  VrApi 1.1.26 with a current GeckoView. Oculus Browser / Samsung Internet VR engines cannot be swapped.

### Firefox Reality Gear VR build (2026-10-09) - tools/gearvr/{build_fxr_gearvr.sh,patch_fxr_gearvr.py}
- Build server ~/fxr: FR final tree (bc6f43f6, + vrb submodule), toolchain JDK11 / SDK 30+33 / build-tools 30.0.3 /
  NDK 21.4.7075529 / CMake 3.10 in ~/fxr/toolchain. Output ~/fxr/out + out/gearvr/ (signed with ~/fxr/gearvr.keystore,
  own key -> installs as org.mozilla.vrbrowser, replaces Mozilla-signed FR).
- third_party/ovr_mobile = VrApi headers of lovr-org/ovr_sdk_mobile f88e937 (1.32) with VRAPI_MINOR_VERSION pinned to
  26 + the genuine 1.1.26 libvrapi.so loader from FR 7.1 (Gear VR driver = 1.1.26; newer requests are rejected).
- patch: 'gearvr' flavor (VrApi only, no OpenXR, no Oculus Platform SDK/entitlement, STORE_BUILD=0, 3DoF), dlsym'd
  vrapi_PollEvent (>=1.1.29), local GetCenterViewMatrix, Quest2 branch dropped, OpenWnn AAR from Wolvic (JCenter
  gone), manifest + code showWhenLocked/turnScreenOn (VR over keyguard, device stays locked), native -O3
  -march=armv8-a+crc+crypto -mtune=cortex-a73 ThinLTO + lld --gc-sections --icf=all, R8 full mode.
  GeckoView prefs: WebRender all, WebGL, MediaCodec HW decode (+forced), WebRTC HW H.264/VP8, AV1 off (no HW AV1 on
  835 -> sites fall back to HW VP9/H.264).
- GeckoView 95 -> 115 port: Kotlin 1.4.10 -> 1.8.22, Gradle 6.7.1 -> 6.9.4, compileSdk 33 (target 30), drop unused
  kotlin-android-extensions, exhaustive whens, onLocationChange(+perms), GeckoDisplay.SurfaceInfo, Selection
  clientRect -> screenRect, EXTRA_CRASH_FATAL -> EXTRA_CRASH_PROCESS_TYPE==MAIN, per-site tracking exceptions
  stubbed (as Wolvic; global ETP level works), GeckoSurfaceTexture.lookup(int) -> (long).
- Live (dev mode, phone locked, no headset): GV 115 build enters VR mode, VrApi FPS=60 Tear=0 Stale=0, processes
  main + :tab + :gpu (WebRender GPU process). Screenshot = lens-distorted side-by-side environment.
- Ceiling: GeckoView >= 128 AARs are Java 17 bytecode -> Jetifier/AGP 4.2 fail. Next level needs AGP 7/8 + Gradle 7/8
  + JDK 17 migration of the FR build (Wolvic did this).

### 2026-10-09 day: battery result, TV removed, Secure Folder patch
- Overnight (9 h 46 m screen off, Wi-Fi + LTE): 168 mAh = ~17 mAh/h (~0.6 %/h), awake 10 %, vmin 57868x. Cell standby
  71 mAh, idle 63, uid 1000 CPU 36 (system_server 188 s, vaultkeeperd 49 s + qseecomd 46 s), GMS only 3-9 mAh (no
  restriction needed). Top kernel wakers wlan_pm_wake / wlan_rx / wlan_txfl; 15x suspend abort by c171000.uart.
  (pwlog.sh missed it: a 3 s usb-online blip at start ended it - use kernel cumulative counters instead.)
- TV: both ISDB-T stacks removed live (user: unusable in VN, crashing); make_vendor_push.sh S8PORT_TV / S8PORT_TV38
  default 0; apply_vendor.sh removes both stacks when the zip lacks them.
- Secure Folder: tools/patches/patch_knox_securefolder.sh (services.jar: PersonaServiceHelper.isTimaAvailable +
  SdpManagerService$LocalService.isKnoxKeyInstallable -> true; UKS already TRUE; KnoxGuard/ASKS untouched) and
  tools/device/knox_sf_live.sh install|rollback. Samsung Pass: not fixable (TZ attestation of the fuse, server-checked).
  Build + install and iris_live.sh install are blocked for Claude by the auto-mode classifier -> user runs them.

### Battery audit (2026-10-09, in progress)
- Plugged: usb_notify/ssusb wakeup sources block suspend -> measure unplugged only. LPM healthy (cpu/l2/system pc).
- vaultkeeperd respawn loop every ~11 s (exit 255, "There is no VK ID", QSEECOM errors) - user rule: leave vaultkeeper
  alone -> asked user (leave vs. stop respawn). KGRlcManager spam = KnoxGuard, report only.
- Viettel app ANR on BOOT_COMPLETED -> Samsung dumpstate_app_error bugreports. Memory tight (190M free, 900M swap).
- dhd lpas/bcn_to_dly UNSUPPORTED (-23) = firmware lacks the iovars, harmless.
- Overnight unplugged test: /data/local/tmp/pwlog.sh (root, waits unplug -> start.txt, resume.txt, replug -> end.txt
  in /data/local/tmp/pwlog/), batterystats reset at 03:55. Read it + dumpsys batterystats after replug.

### SCV38 (S9 au, Q) TV stack added (2026-10-09) - tools/build/stage_tv_scv38.sh
- firmware/s9 = SCV38KDS1CVK1 (Q). Its tuner is the FC8350 (same FCI FC83xx family); the vendor HAL
  vendor.samsung.hardware.dtvtuner@1.0-service (src TUNNER_FC83XX/oneseg_tunner_hal_FC83XX.c) opens /dev/isdbt with
  the same 't' ioctls 0..29 our FC8300 driver has. Middleware = Fujisoft FS1SEG: app jp.co.fsi.fs1seg ("TV",
  sdk 28/29), dtvserver (-> dtvmgr), libDtv*/libdtvsdserver*/libsdvm*. Full-Seg TRMP = software (OpenSSL, /data/dtv).
- Everything links against the G9600 system; T835 vendor policy + G9600 plat_service_contexts already have the
  identical dtvserver / digital_tv_fullseg / dtv.mgr policy -> only a VINTF fragment (vintf/manifest/dtvtuner.xml).
- Live: HAL (u:r:digital_tv_fullseg), dtvserver (u:r:dtvserver), dtv.mgr registered, app starts, no denials.
  Coexists with the SCV36 stack (both only open /dev/isdbt while in use). Build: make_vendor_push.sh S8PORT_TV38=1
  (needs ~/s9fw/{system,vendor}.raw.img); apply_vendor.sh re-applies etc/s8port_tv38_files.txt metadata.
  Live install list: /sdcard/s8port_tv38_files.txt. Storage restriction fixed live (runtime-permissions 4300->3300).

### Video recording (2026-10-09) - FIXED
- Every app: MediaRecorder start failed <- AudioRecord createRecord -22 <- APM "getInputForAttr() could not find device
  for source 5" (CAMCORDER). Samsung Q policy engine wants AUDIO_DEVICE_IN_2MIC ("Built-In 2 Mic", attached in the
  G9600 _sec policy); the S8 Pie _sec policy lacks it. build_vendor.sh 5f adds the port/attached item/primary-in route.
  Live: audioserver restart -> recording saves .mp4, user confirmed. (Super slow-mo worked before: no audio track.)
- Wi-Fi notes continued:
  (Tried first: config_wifi_connected_mac_randomization_supported=false -> wlan0 keeps the OTP default MAC
  00:90:4c:.. and association fails "MLME connect -22" -> reverted; kept as MACRAND_OFF=1 in build_framework_overlay.sh.)

### Fingerprint: stock-kernel A/B test prepared (2026-10-08)
- Emulated sysfs (tools/analysis/fpemu.py + show functions): stock name/vendor = NAMSAN/SYNAPTICS until the HAL's
  FP_SET_SENSOR_TYPE sets field 792 (egis flag), ours always ET510/EGISTEC; stock also has bfs_values
  ("FP_SPICLK":"9600000"). Same regulator drivers/cleanup (s2abb01, s2dos03) in both kernels.
- One-shot stock-kernel boot: out/kernel/test_stockkernel_in_recovery.img (md5 07cb031f17547e2c2eeab20efa432d55) =
  stock CZE1 Image (4.4.153) + our jpn_dtbs_noverity_wqhd.dtb + our boot ramdisk/cmdline. Written to the RECOVERY
  partition by tools/device/fp_stocktest_prep.sh (also: /dev/fps label + ueventd perms + symlink /dev/esfp0 for the stock
  "fps,common" driver, no-ops on our kernel; clears type_check.dat). `adb reboot recovery` = stock kernel once; next
  reboot = boot partition (our kernel). No root on that boot (no Magisk) -> read bauth lines with plain logcat.
  Afterwards restore TWRP: dd out/twrp/twrp_scv36_adbdefault.img to recovery.
- Stock-kernel test run (2026-10-08): stock 4.4.153 boots, mounts system, loads Q sepolicy, then init's vendor_init
  subcontext gets SIGKILL ("Subcontext received signal 9") at 2.70 s -> "Apex Not Ready... reboot" -> next boot = our
  kernel (one-shot scheme works). Likely Samsung DEFEX/root restriction (CONFIG_SECURITY_DEFEX, sec_restrict_uid; both
  disabled in our build). A diagnostic stock Image with those two hooks returning "allow" was NOT built (blocked as a
  security-weakening patch; needs the user's explicit OK). TWRP restored to recovery (WRITE_OK).

### FINGERPRINT FIXED (2026-10-09) -> s8port_update_20261009_0034.zip (kernel #23)
- One-shot stock-kernel boot (tools/kernel/make_stock_nodefex_test.sh + tools/device/run_stock_nodefex_test.sh, recovery slot,
  DEFEX/sec_restrict_uid returning allow - diagnostic only; also needed the stock /dev/fps -> /dev/vfsspi symlink):
  stock fps,common driver reports NAMSAN/SYNAPTICS -> HAL probes Synaptics ("5, 7") via /dev/vfsspi -> TA cgst = 5,
  ptav 2.0.4.1, dumpsys "FwVersion 08.00.182, ConfigId1 161122, ConfigId2 040130, Module Test : Pass".
- ROOT CAUSE: this SCV36's sensor is a Synaptics NAMSAN; the JPN DT (fps-chipid "ET510") is misleading. Our Egis ET5XX
  driver announced ET510 -> HAL probed only Egis types ("3, 6") -> cgst 0 -> "FP Sensor is out of order".
- Fix: kernel SENSORS_VFS8XXX instead of ET5XX (tools/kernel/build_kernel.sh) + tools/kernel/patch_vfs8xxx_fps_common.py (match
  fps,common, fps-* property fallback, sysfs name NAMSAN; server commit e6f2d813b). Vendor: /dev/vfsspi ueventd perms +
  rc chown. Verified live on #23: name NAMSAN, type_check 5, type_check.dat NAMSAN, sensor info Module Test : Pass.
  Previous kernels: out/kernel/boot_before_vfs8xxx.img, /sdcard/boot_backup_k22.img.
- Caveat: SCV36 units with a real Egis ET510 would need ET5XX (stock driver served both); not seen here.

### 2026-10-09 evening: iris trustlet root-key wall, S8 TA + S8 UI for iris and fingerprint
- Black iris enroll screen, cause 1: TZ rejects the T835 sec_iris (QSEECom_start_app errno 22, ~30 retries ->
  IrisTlc_InitLib fail). Cert chains: S8 TAs (sec_iris, authhat, vaultkee...) root pubkey sha256 faaa8ed1913ecb85,
  T835 5790b001e0cc21af, S9 6823760c... -> Samsung uses a per-product OEM root (fused); same HW_ID/SW_ID/APP_ID is
  not enough. No T835/S9 TA can ever load on this SoC. Bind mount + apnhlos_iris copy dropped (rc deleted live).
- T835 Q irisd + stock S8 sec_iris: TA loads, InitLib 0 (product dreamqltechn), preEnroll ok, AuthHat_Decap_Key ok.
  GetAuthId returns -40 (secure-id file from an earlier stack?) - enrollment itself not yet tried past the helper.
- Cause 2: T835 SecIrisService is the tablet build; at sw411dp-xxxhdpi the default dimens give
  iris_helper_image_width / imageview_width = 0dp -> help-video and eye-preview TextureViews 0 wide, never get a
  surface (no onSurfaceTextureAvailable) -> black. tools/patches/merge_seciris_s8ui.py overlays the stock S8 Pie SecIrisService
  layouts/drawables/anims/raw + phone dimens/colors by name onto the decoded patched T835 apk (apktool 2.9.3 b -c,
  dex/manifest/META-INF kept; smali identical). Every code-used view id still present.
- Fingerprint: G9600 BiometricSetting plays the S9 guide videos -> tools/patches/patch_fp_s8_media.py puts the S8 Pie SecSettings
  sec_fingerprint_v_01/v_02.mp4 (also as h_*) + sec_fingerprint_enroll_animation_expand.json in (zip entry swap).
- Both live on the phone (backups /sdcard/SecIrisService_t835ui_backup.apk, /sdcard/BiometricSetting_g9600_backup.apk,
  also in /sdcard/iris_g9600_backup; rollback list rebuilt). stage_iris_t835.sh now: <T835 system img> <out>, stages
  both apks (13 MB instead of 61 MB). The ~/iris_stage of the afternoon held the UNPATCHED T835 apk (stale stage).
- GetAuthId -40: irisd's secure-id is /data/system/users/0/bio/ir/sid.dat (mStorePath 27), written 2026-10-06 by the
  S9 stack's TA -> renamed sid.dat.s9stack.bak (no iris enrolled) so the S8 TA makes a new one. NOT
  /data/vendor/biometrics/info/User_0/sec_auth_id.dat - that is the fingerprint's (enrolled), leave it.
- Next blocker (enroll, TZ side all 0): IRV1Controller "Camera failed to open: Fail to get camera info" for id 90.
  T835 SehCameraProvider probes a hidden-id table (.bss, filled by its init: ..., 90, 91, 92) via HAL get_camera_info;
  the S8 HAL answers "mapping system camera id 90 -> 3" -> provider registers device@1.0/legacy/90 (dumpsys shows it).
  G9600 CameraService::getCameraInfo(int) = AOSP bounds check (id >= mNumberOfCameras(2) -> ILLEGAL_ARGUMENT, id from
  mNormalDeviceIds[]); the T835 build rejects only id < 0 and uses std::to_string(id).
  tools/patches/patch_cameraservice_hiddenid.py (on top of the orientation patch, md5 4de7755d -> a97a5fff): bge 86c04 + nops;
  else-branch -> add r0,sp,#16; mov r1,r7; blx to_string(int)@plt 0x10fde0; b 86c56. make_vendor_push.sh applies it.
  Live: written to /system/lib (bind-of-/) + Magisk's stale per-file bind replaced (stop cameraserver; umount -l;
  mount --bind; start). Backup /sdcard/libcameraservice_orient_backup.so.
- Retest: getCameraInfo(90) OK, then connect failed "cameraIdIntToStrLocked: input id 90 invalid: valid range (0, 2)"
  (same AOSP check; identical in T835 - its connect route differs). patch_cameraservice_hiddenid.py extended:
  cameraIdIntToStrLocked id >= size -> std::to_string(id), id < 0 -> "" -> md5 9e1ce910..., live (stop cameraserver;
  umount -l; replace; bind; start). SendHatHmacKey -13 then authhat fallback (cmd 0xe) 0 + enroll init 0 = not fatal.
- 3rd try: same "cameraIdIntToStrLocked: input id 90 invalid" log although Locked was patched: API1 connect calls
  cameraIdIntToStr(int) (String8), which has the Locked logic INLINED (string xrefs: only these two functions).
  Patched the same way (86ed4 -> b empty; 86ed8 -> to_string into sp+8, b 86ec6) -> md5 d51a6546..., live.
  Kernel side OK: /sys/class/camera/secure/iris_camfw "S5K5E6 N", iris_checkfw_user OK, kernel secure-CCI loads
  sec_iris (TZ If version 1.2, set_mode rc=0), s2mpb02 LDO rails switch cleanly.
- 2026-10-09 ~20:22: IRIS WORKS - user enrolled (/data/system/users/0/bio/ir/ now has the template + a fresh sid.dat
  from the S8 TA). Stack: T835 irisd/libs + S8-UI T835 SecIrisService + stock S8 sec_iris TA + 3-site
  libcameraservice hidden-id patch.
- Unlock failed ("iris sensor not responding" after the IR LED flash): IR camera fine, but every new TA session
  "IrisTlc_GetAuthId fail(-40)". Cause: request layout of cmd 13 changed between the S8 and T835 libIrisTlc
  (S8: sid at +4, len +1028; T835: type at +4, sid at +8, len +1032) - all other IrisTlc layouts match (compared
  with a request-buffer diff script). tools/patches/patch_iristlc_t835_authid.py (3 insns, md5 a20ce3a8 -> aa3de5f8), staged
  by stage_iris_t835.sh, live (Magisk per-file bind replaced). Fresh-session GetAuthId now = 1767339332 (the enroll
  id). SendHatHmacKey -13 (GetKFromKM differs: 16400-byte KM blob on T835) stays, authhat fallback covers it.

### 2026-10-09 night: release kernel, iris via overlays, repo cleanup, first release build
- **Release kernel** (server branch `s8-q-release` = s8-q-port without the s8dbg hooks: msm-poweroff.c restored to
  Q-r1; + LF line endings in two Samsung Kconfigs and `drbg_cores __maybe_unused`) -> clean build: 1 upstream Kconfig
  notice left (HDMI codec select). Release cmdline drops `s8dbg.recovery msm_poweroff.s8dbg_timeout log_buf_len=4M`
  and turns the Qualcomm register trace buffer off (`msm_rtb.enable=0`). `tools/build/make_release_boot.sh`
  (template boot + Image.gz, byte-identical to what was flashed). Debug adb props in /system/etc/prop.default
  restored (ro.adb.secure=1), s8dbg.rc removed. LTO: not supported by this tree (dropped, user OK). SD845 flags
  would emit ARMv8.2 code -> not used; GCC 4.9 tuning stays cortex-a57.cortex-a53 (-O2).
- `adb reboot system` from TWRP passes the reason "system" -> Samsung restart code sets an UNKNOWN reason and the
  bootloader keeps PARAM_BOOT_RECOVERY_ENTER (booted TWRP again). Plain `adb reboot` = NORMALBOOT.
- **Iris lost after reboot**: the apktool-rebuilt SecIrisService (S8 UI) failed the package manager's certificate
  check at the next boot scan ("Failed to collect certificates"), the package was dropped and its data wiped; the
  keyguard then retried the missing service ~1/s (sluggish UI). It had only ever been installed live.
  Fix without touching the app: stock Samsung-signed T835 SecIrisService +
  (a) FrameworkS8Overlay: the app reads config_keyguardComponent by the T835 id 0x01040252 = G9600
      config_headlineFontFeatureSettings ("") -> that string now holds the keyguard component;
  (b) IrisS8Overlay (tools/build/build_iris_overlay.sh): S8 Pie layouts/videos/dimens + S8 strings (657, all S8
      languages; English/Vietnamese "tablet" words in the 2 T835-only strings swapped) merged onto the decoded T835
      resources and compiled with every T835 resource ID pinned (apktool public.xml; Android 10 does not remap
      references inside overlays) - build fails unless all 729 names/IDs match;
  (c) SELinux: mediaserver / mediaextractor read vendor_overlay_file (the guide video fd points into the overlay
      apk; without it "Prepare failed" = white video box).
  User confirmed iris enroll + unlock (S8 text overlay installed afterwards). Template survived the wipe (/data/system/users/0/bio/ir).
- Battery notes: vaultkeeperd restarts every few minutes (left alone, KG rule); sensors HAL 37 min CPU in 6.7 h was
  screen-on app use (Spotify OrientationEventListener holds the accelerometer); fingerprint HAL 1 Hz status log
  costs ~0 (24 s CPU / 6.7 h). wlan_wake counts only matter unplugged - standby test still pending.
- **Repo prepared for GitHub**: tools sorted into setup/build/kernel/patches/device/analysis/gearvr, all cross
  references rewritten, hardcoded paths -> repo-relative, credentials -> config/local.env (git-ignored, see
  local.env.example) + tools/lib/env.sh (ph/phsh/phpush), installer sources moved out of out/ (installer/),
  kernel diffs in kernel/patches, docs/{FINDINGS,DONORS}.md, README.md, tools/README.md (generated index).
- **Release build** (out/release/): vendor rebuilt and compared file-by-file with the phone (identical except the
  leftover /dev/fps symlinks of the stock-kernel fingerprint test); iris + fingerprint media now in the update zip
  (system_add + etc/s8port_iris_files.txt metadata, applied by apply_vendor.sh like the TV38 list).
