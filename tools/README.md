# Tools

Every script starts with a header comment saying what it does, where it runs (WSL, build server, phone, TWRP) and how to call it. This index is generated from those headers.

Shared settings: [`lib/env.sh`](lib/env.sh) reads `config/local.env` (repo root `S8PORT`, work dir `S8ROM`, `BUILD_HOST`, `PHONE_PC`) and defines the phone helpers `ph`, `phsh`, `phpush` (local adb, or adb on the PC the phone is plugged into, over ssh).

## setup/

One-time host / build-server setup, source + toolchain fetch, and `remote.sh` (sync + build on the server).

| Script | What it does |
|---|---|
| [`check_host.sh`](setup/check_host.sh) | Report which build tools are available on the WSL build host. |
| [`fetch_kernels.sh`](setup/fetch_kernels.sh) | Clone kernel trees into the WSL ext4 home (kernel sources need a case-sensitive filesystem). |
| [`fetch_toolchain.sh`](setup/fetch_toolchain.sh) | AOSP GCC 4.9 aarch64 toolchain (the compiler Samsung used for the stock S8/Tab S4 kernels). |
| [`remote.sh`](setup/remote.sh) | Run from WSL: push project tools + configs to the build server and execute a command there. |
| [`server_setup.sh`](setup/server_setup.sh) | Runs ON the build server (no sudo needed): python shim, kernel tree, GCC 4.9 toolchain. |
| [`setup_host.sh`](setup/setup_host.sh) | Install build dependencies on the WSL Debian host. usage: SUDO_PW=... bash tools/setup/setup_host.sh |
| [`setup_server_ssh.sh`](setup/setup_server_ssh.sh) | One-time: key-based SSH from WSL to the build server, then print server specs. |
| [`setup_smali.sh`](setup/setup_smali.sh) | smali/baksmali 2.5.2 (vdexExtractor is built separately in ~/s8rom/tools_bin, -Werror removed). |

## build/

The build pipeline: vendor, system image, SELinux, overlays, iris/TV staging, boot images, packaging.

| Script | What it does |
|---|---|
| [`build_deknox_system.sh`](build/build_deknox_system.sh) | Run in WSL (needs sudo for loop mount): stock CZE1 system minus KnoxGuard & the Knox lock/attestation agents, no stock-recovery restore, /data encryption optional. Output: sparse ext4 for Odin (system… |
| [`build_framework_overlay.sh`](build/build_framework_overlay.sh) | static RRO for framework-res ("android") -> config/overlay/out/FrameworkS8Overlay.apk (goes to /vendor/overlay). AOD brightness: G9600 config_aodBrightnessValues = [0, 40, 71, 94] (4 levels) turns on … |
| [`build_iris_overlay.sh`](build/build_iris_overlay.sh) | static RRO "IrisS8Overlay" for com.samsung.android.server.iris -> config/overlay/out/IrisS8Overlay.apk (installed as /vendor/overlay/IrisS8Overlay/IrisS8Overlay.apk). Gives the unmodified, Samsung-sig… |
| [`build_sdhms_overlay.sh`](build/build_sdhms_overlay.sh) | static RRO for com.sec.android.sdhms (SSRM) -> config/overlay/out/SdhmsS8Overlay.apk (goes to /vendor/overlay). Why: SDHMS always loads raw/siop_starqlte_sdm845 (S9 policy, name hard-coded in sb.m; "s… |
| [`build_stubs.sh`](build/build_stubs.sh) | build the small vendor stand-in libraries in config/stubs/ -> config/stubs/out/<arch>/ libsensorlistener.so (armv7): see config/stubs/libsensorlistener.cpp |
| [`build_system.sh`](build/build_system.sh) | build the One UI 2 port system image for the SCV36 from the G9600 Android 10 image. G9600 system (labels preserved) - debloat + T835/S8 vendor in /system/vendor + /vendor & /odm links |
| [`build_vendor.sh`](build/build_vendor.sh) | assemble the One UI 2 port vendor = Tab S4 (T835) Android 10 vendor + S8 phone hardware from the SCV36 Pie vendor. Output tree: ~/s8rom/port/vendor   (goes into /system/vendor of the port system image… |
| [`check_property_contexts.py`](build/check_property_contexts.py) | Find duplicate property prefixes across the property_contexts files Android 10 init loads, in the order it loads |
| [`compile_policy.sh`](build/compile_policy.sh) | compile the full split policy (as init does on boot) to verify the merged vendor policy before flashing. |
| [`contexts_add.sh`](build/contexts_add.sh) | build file_contexts / hwservice_contexts additions for the transplanted S8 HALs and check every type exists in the compiled merged policy (config/sepolicy/precompiled_sepolicy.test). |
| [`cpio_extract.py`](build/cpio_extract.py) | Extract a (gzipped) newc cpio ramdisk. usage: python cpio_extract.py ramdisk.cpio.gz out_dir |
| [`dedup_contexts.py`](build/dedup_contexts.py) | Remove vendor-side entries that the (G9600) platform policy already defines. Android 10 aborts on duplicates: |
| [`dtb_single_mode.sh`](build/dtb_single_mode.sh) | remove the S8 panel's multi-resolution display timings (fhd, hd) from the concatenated JPN DTBs, keeping only the native wqhd timing. Samsung's One UI 2 SurfaceFlinger "MultiResolution" matches the WM… |
| [`fscaps.py`](build/fscaps.py) | Decode Android fs_config_files (binary: struct fs_path_config_from_file) and list entries with capabilities. |
| [`gen_vndk_lite.py`](build/gen_vndk_lite.py) | Fill AOSP Android 10 ld.config.vndk_lite.txt for the S8 (VNDK-lite Pie vendor) on the G9600 Q system. |
| [`label_tree.py`](build/label_tree.py) | Set security.selinux xattrs on a mounted tree from Android file_contexts files (like the build's e2fsdroid would). |
| [`magisk_patch.sh`](build/magisk_patch.sh) | Patch a boot.img with Magisk on the PC (WSL), same steps as the Magisk app's boot_patch.sh. |
| [`make_flashable_zip.sh`](build/make_flashable_zip.sh) | pack out/twrp_push (boot.img, vendor.tar, vendor_labels.sh, apply_vendor.sh, system_add.tar) into a TWRP flashable zip: out/rom/s8port_update_<date>.zip (installer: installer/update-binary). |
| [`make_release_boot.sh`](build/make_release_boot.sh) | release boot.img = a template boot image (e.g. the phone's current Magisk-patched boot, dumped with dd) with the kernel replaced by out/kernel/Image.gz and the debug options removed from the cmdline. … |
| [`make_vendor_push.sh`](build/make_vendor_push.sh) | package the port vendor for a fast TWRP update (no full system reflash): out/twrp_push/vendor.tar        - ~/s8rom/port/vendor (owners/modes kept, no xattrs) |
| [`mkboot.py`](build/mkboot.py) | Repack a Samsung (header v0) boot.img using a stock image as template. |
| [`odin_tar.py`](build/odin_tar.py) | Wrap images into an Odin-flashable .tar.md5 (ustar + trailing md5 line, like Samsung's own packages). |
| [`omc_decode.py`](build/omc_decode.py) | Decode/encode Samsung OMC text files (cscfeature.xml, cscfeature_network.xml, ...). |
| [`patch_dtb_noverity.sh`](build/patch_dtb_noverity.sh) | remove dm-verity (verify/avb) flags from the early-mount fstab inside the stock SCV36 JPN DTBs. Input: the 3 stock DTBs; output: out/kernel/jpn_dtbs_noverity.dtb (concatenated, ready to append to Imag… |
| [`policy_gap.py`](build/policy_gap.py) | SELinux additions for the S8 phone HALs (NFC, fingerprint) on top of the T835 Q vendor policy. |
| [`port10_vndk28.py`](build/port10_vndk28.py) | Runs in WSL (python3 + readelf). Build the vndk-28 library set for the One UI 2 port: |
| [`stage_iris_t835.sh`](build/stage_iris_t835.sh) | stage the Galaxy Tab S4 (SM-T835, MSM8998, Android 10) iris stack for the SCV36 One UI 2 port. |
| [`stage_tv.sh`](build/stage_tv.sh) | stage the SCV36 ISDB-T TV (One-Seg / Full-Seg, FCI FC8300 tuner) into system_add for the One UI 2 port. |
| [`stage_tv_scv38.sh`](build/stage_tv_scv38.sh) | stage the SCV38 (Galaxy S9 au, Android 10) ISDB-T TV stack for the One UI 2 port. |
| [`symcheck.py`](build/symcheck.py) | Static link check for transplanted S8 Pie vendor ELFs inside the port (T835 Q vendor + G9600 Q system). |
| [`transplant_deps.py`](build/transplant_deps.py) | for S8 Pie vendor HAL services, list everything needed to transplant them into the T835 Q vendor: |
| [`twrp_adb_default.sh`](build/twrp_adb_default.sh) | make our SCV36 TWRP always come up with adb (no MTP): every USB mode TWRP asks for (mtp, mtp,adb, adb) builds the adb-only configfs gadget, and sys.usb.config=adb is set at boot -> adb works without t… |
| [`twrp_port.sh`](build/twrp_port.sh) | port TWRP 3.4.0 dreamqlte to SCV36 = TWRP ramdisk + SCV36 kernel/JPN DTBs + fixed fstab. Builds two variants in out/twrp/: _stockkernel (SCV36 CZE1 recovery kernel) and _qkernel (our perf kernel + JPN… |
| [`unpack_odin.py`](build/unpack_odin.py) | Extract and lz4-decompress members of a Samsung Odin .tar.md5. |
| [`vendor_symbol_audit.py`](build/vendor_symbol_audit.py) | Unresolved-import audit of the port vendor tree, the way the Q linker resolves a vendor process. |
| [`vendor_visible_check.py`](build/vendor_visible_check.py) | every NEEDED library of the transplanted vendor ELFs must be loadable from a vendor process on Android 10 |
| [`vintf_kcheck.py`](build/vintf_kcheck.py) | Offline VINTF kernel check: framework compatibility matrix (target-level from the vendor manifest) vs our kernel |

## kernel/

`build_kernel.sh` and the scripts that patched the kernel tree (their result is in `kernel/patches`).

| Script | What it does |
|---|---|
| [`build_kernel.sh`](kernel/build_kernel.sh) | Build the Tab S4 Android 10 msm8998 kernel with the stock SCV36 config, Samsung lock-down features off. Runs on WSL or the build server. Env overrides: |
| [`fix_kgsl_gup.py`](kernel/fix_kgsl_gup.py) | Runs ON the build server (python3): adapt the transplanted Pie kgsl.c to the 4.4.205 get_user_pages() signature |
| [`kernel_branches.sh`](kernel/kernel_branches.sh) | keep both S8 kernel variants as git branches in ~/s8rom/kernel/t830_q. s8-pie-test : APR fix + s8dbg + Pie KGSL transplant (boots the stock S8 Android 9 system) |
| [`make_stock_nodefex_test.sh`](kernel/make_stock_nodefex_test.sh) | DIAGNOSTIC ONLY (user-run): one-shot fingerprint A/B test image = stock SCV36 kernel (4.4.153) with Samsung DEFEX enforcement (task_defex_enforce) and the root restriction (sec_restrict_uid) returning… |
| [`patch_always_permissive.py`](kernel/patch_always_permissive.py) | add CONFIG_ALWAYS_PERMISSIVE (as in hadesKernel Q for the Exynos S8, corsicanu/ |
| [`patch_apr_legacy.py`](kernel/patch_apr_legacy.py) | Runs ON the build server (python3): make the Q-tree APR driver work with the S8 Pie device tree. |
| [`patch_et5xx_fps_common.py`](kernel/patch_et5xx_fps_common.py) | Kernel patch (server tree): let the Q-tree Egis ET5xx driver (drivers/fingerprint/et5xx-spi.c) drive the S8 JPN |
| [`patch_et5xx_ioc_magic.py`](kernel/patch_et5xx_ioc_magic.py) | Kernel patch (server tree), stage 3 after patch_et5xx_ldo_reset.py: accept the S8 Pie bauth ioctl magic. |
| [`patch_et5xx_ldo_reset.py`](kernel/patch_et5xx_ldo_reset.py) | Kernel patch (server tree), stage 2 after patch_et5xx_fps_common.py: reset + power for boards without a reset pin. |
| [`patch_et5xx_spi_pins.py`](kernel/patch_et5xx_spi_pins.py) | Kernel patch (server tree), stage 4 after patch_et5xx_ioc_magic.py: mux the fingerprint SPI pins for TrustZone. |
| [`patch_et5xx_stock_timing.py`](kernel/patch_et5xx_stock_timing.py) | Make the Q et5xx power / reset sequence identical to the stock SCV36 fps_* driver (verified by differential |
| [`patch_et5xx_tz_clock.py`](kernel/patch_et5xx_tz_clock.py) | Kernel patch (server tree), from reverse engineering the stock SCV36 Pie kernel (KDI CZE1, CONFIG_KALLSYMS_ALL, |
| [`patch_s8dbg.py`](kernel/patch_s8dbg.py) | Runs ON the build server (python3): add the 's8dbg.recovery' debug hook to msm-poweroff.c in the Q kernel tree. |
| [`patch_s8dbg_logdump.py`](kernel/patch_s8dbg_logdump.py) | Runs ON the build server (python3): extend the 's8dbg.recovery' debug hook in msm-poweroff.c with a reboot notifier |
| [`patch_s8dbg_watchdog.py`](kernel/patch_s8dbg_watchdog.py) | Runs ON the build server (branch s8-q-port): add a boot watchdog to the s8dbg debug hook in msm-poweroff.c. |
| [`patch_sec_nfc_support.py`](kernel/patch_sec_nfc_support.py) | Kernel patch (server tree): add /sys/class/nfc/nfc_support to the S8 sec_nfc driver. |
| [`patch_spi_qsd_fp_pinctrl.py`](kernel/patch_spi_qsd_fp_pinctrl.py) | Kernel patch (server tree), with patch_et5xx_spi_pins.py: make spi_qsd's fp_spi_request_gpios() usable before the |
| [`patch_vfs8xxx_fps_common.py`](kernel/patch_vfs8xxx_fps_common.py) | Kernel patch (server tree): drive the SCV36 fingerprint sensor with the Q-tree Synaptics driver |
| [`transplant_kgsl.sh`](kernel/transplant_kgsl.sh) | replace the Q-tree Adreno/KGSL driver with the S8 Pie (G9500 PP) one. Reason: Q kgsl makes the CP scratch buffer privileged -> S8 Pie GPU microcode faults ("CP initialization failed to |

## patches/

Binary / APK patches for Samsung userspace, applied by the build scripts.

| Script | What it does |
|---|---|
| [`merge_seciris_s8ui.py`](patches/merge_seciris_s8ui.py) | Overlay the S8 (phone) SecIrisService UI onto the decoded T835 apk: layouts, drawables, anims, raw videos by name, and per-name dimen/color/bool/integer values. T835 code + strings stay. usage: merge_… |
| [`patch_cameraservice_hiddenid.py`](patches/patch_cameraservice_hiddenid.py) | G9600 Q /system/lib/libcameraservice.so: let API1 getCameraInfo() reach Samsung hidden camera ids (iris = 90). |
| [`patch_cameraservice_orientation.py`](patches/patch_cameraservice_orientation.py) | G9600 Q /system/lib/libcameraservice.so: restore the Pie CameraClient display-orientation rule. |
| [`patch_fp_module_version.py`](patches/patch_fp_module_version.py) | Make the S8 Pie fingerprint.default.so (HAL 2.1) acceptable to the G9600 fingerprint@3.0 service. |
| [`patch_fp_s8_media.py`](patches/patch_fp_s8_media.py) | Swap the S9 fingerprint-enroll guide media in the G9600 BiometricSetting.apk for the S8's own (stock S8 Pie SecSettings): res/raw/sec_fingerprint_{v,h}_0{1,2}.mp4 (the S8 shipped only v_*; its h_* are… |
| [`patch_gralloc_nv21.py`](patches/patch_gralloc_nv21.py) | Binary patch for the T835 (Q) msm8998 libgrallocutils.so (lib + lib64): NV21 row stride like the S8 Pie gralloc. |
| [`patch_iristlc_t835_authid.py`](patches/patch_iristlc_t835_authid.py) | T835 (Tab S4, Q) /system/lib64/libIrisTlc.so -> request layout of the S8 sec_iris TA for IrisTlc_GetAuthId. |
| [`patch_knox_securefolder.sh`](patches/patch_knox_securefolder.sh) | patch the One UI 2 (G9600) services.jar so Secure Folder can be created on this Knox-tripped (warranty 0x1) device. Same approach as KnoxPatch (GPL-3.0, salvogiangri) SystemHooks.applyTIMAHooks for On… |
| [`patch_semcamera.sh`](patches/patch_semcamera.sh) | patch the One UI 2 (G9600) framework semcamera.jar for the S8 HAL1 camera stack. The S8 SamsungCamera 9.0 activates its shooting mode (UI, shutter, mode switch) only after |

## device/

Run against the phone (Windows PowerShell + adb, WSL, TWRP or on-device root): captures, live install / rollback, TWRP helpers.

| Script | What it does |
|---|---|
| [`bootloop_diag.ps1`](device/bootloop_diag.ps1) | is a system installed, which boot image is on the phone, and the crash logs. |
| [`capture_boot.ps1`](device/capture_boot.ps1) | Record the full log from the start of boot (needs the debug adb props). Start it while the phone is in TWRP or rebooting; it waits for adb, then logs for -Seconds (default 240) while you test things o… |
| [`capture_bootloop.ps1`](device/capture_bootloop.ps1) | Record logcat + kernel log from every bootloop iteration (needs AP_5 debug-adb boot image on the phone). |
| [`capture_cam_fp.ps1`](device/capture_cam_fp.ps1) | Samsung Camera save/record failures + front preview flip, and a live fingerprint bus check (needs Magisk root). |
| [`capture_camera.ps1`](device/capture_camera.ps1) | Camera + torch test capture: run it with the phone booted and adb connected. It walks you through rear preview, front preview and the torch slider and grabs, at each step, a screenshot, the SurfaceFli… |
| [`capture_core.ps1`](device/capture_core.ps1) | One run for the three open items: Samsung Camera (switch crash / front flip), fingerprint, iris. Uses root (Magisk su) when available for the kernel log, tombstones and /data/vendor state; works witho… |
| [`capture_display.ps1`](device/capture_display.ps1) | Display layer-by-layer state (phone booted, adb on). Saves .\display_<time>\ in the current folder. |
| [`capture_live.ps1`](device/capture_live.ps1) | Port running (adb up): grab logs + display/radio/wifi state over adb into .\live_<time> (current folder). |
| [`capture_power.ps1`](device/capture_power.ps1) | Battery drain capture (needs Magisk root). 1) powershell -ExecutionPolicy Bypass -File tools\capture_power.ps1 -Start -> resets battery stats; then UNPLUG the phone, screen off, leave it 30-60 min (no… |
| [`capture_samsung_camera.ps1`](device/capture_samsung_camera.ps1) | Samsung Camera "preview shows but no touch works" capture: launches the S8 SamsungCamera, waits, taps the screen and the shutter by itself, and saves the logs needed to see why the app never activates… |
| [`capture_stock_fp.ps1`](device/capture_stock_fp.ps1) | Fingerprint reference capture on the STOCK SCV36 Pie ROM (no root needed). |
| [`collect_debug.ps1`](device/collect_debug.ps1) | Collect debug info from the SCV36 over adb. Read-only: nothing on the phone is modified. PowerShell port of collect_debug.sh - needs only adb (platform-tools) + Samsung USB driver. |
| [`collect_debug.sh`](device/collect_debug.sh) | Collect debug info from the SCV36 over adb. Read-only: nothing on the phone is modified. |
| [`fp_clk_test.sh`](device/fp_clk_test.sh) | Experiment: does the S8 fingerprint TA find the ET510 when HLOS keeps the BLSP2 QUP6 (BLSP12) SPI + AHB clocks on (what the S8 Pie G9500 et5xx did on FP_SET_SPI_CLOCK)? |
| [`fp_live.sh`](device/fp_live.sh) | Runs on the phone as root (tools/device/capture_cam_fp.ps1): fingerprint SPI bus state while the fingerprint HAL starts. Output: /data/local/tmp/fp_live/{state,samples,dmesg}.txt |
| [`fp_stocktest_prep.sh`](device/fp_stocktest_prep.sh) | Phone (root, our kernel): prepare a ONE-SHOT boot of the stock SCV36 kernel with our One UI 2 system, to tell whether the fingerprint failure is our kernel or the Q userspace. The test image (stock Im… |
| [`fp_tz_test.sh`](device/fp_tz_test.sh) | Captures the QSEE (TrustZone app) log while the fingerprint HAL re-probes the sensor, so we see what the "dualfp" TA itself reports for its sensor detection (cgst / FP cmd 0x10). |
| [`iris_live.sh`](device/iris_live.sh) | live install / rollback of the T835 iris stack (tools/build/stage_iris_t835.sh output in ~/iris_stage) on the phone. |
| [`knox_sf_live.sh`](device/knox_sf_live.sh) | build + live-install (or roll back) the Secure Folder services.jar patch (tools/patches/patch_knox_securefolder.sh). |
| [`make_debug_boot.sh`](device/make_debug_boot.sh) | make a boot image that starts adb without RSA authorization from early boot, for catching bootloop logs. |
| [`parse_cachehead.py`](device/parse_cachehead.py) | Parse the s8dbg kernel-log dump from a raw copy of the start of the 'cache' partition (cache_head.bin). |
| [`parse_debugpart.py`](device/parse_debugpart.py) | Parse a dump of Samsung's 'debug' partition (msm8998 layout from include/linux/qcom/sec_debug_partition.h). |
| [`power_dump.sh`](device/power_dump.sh) | Runs on the phone as root (tools/device/capture_power.ps1): sleep / wakeup / crash-loop state for battery-drain analysis. Output: /data/local/tmp/power/*.txt |
| [`pull_logs.ps1`](device/pull_logs.ps1) | After a failed boot that landed in TWRP: copy the 'cache' log dump and Samsung's 'debug' partition to the PC. Phone: TWRP main screen (MTP disabled). Every step retries if adb drops. |
| [`read_debugpart.ps1`](device/read_debugpart.ps1) | In TWRP: copy Samsung's 'debug' partition (reset reason + kernel log saved by the bootloader after a crash). Read-only. |
| [`read_logdump.ps1`](device/read_logdump.ps1) | In TWRP after an AP_7 debug boot: read the kernel log the s8dbg hook wrote to the start of the 'cache' partition. |
| [`run_stock_nodefex_test.sh`](device/run_stock_nodefex_test.sh) | one-shot fingerprint A/B test on the stock SCV36 kernel (DEFEX/root restriction set to allow, built by tools/kernel/make_stock_nodefex_test.sh). Puts out/kernel/test_stockkernel_nodefex.img in the REC… |
| [`twrp_backup.ps1`](device/twrp_backup.ps1) | Back up the irreplaceable partitions (IMEI/modem/calibration) + stock boot/recovery while the phone is in TWRP. TWRP's adb shell is already root, so plain dd works. Read-only on the phone except temp … |
| [`twrp_check.ps1`](device/twrp_check.ps1) | Verify TWRP can use the SCV36 storage. Phone must be booted into TWRP with USB connected. |
| [`twrp_check.sh`](device/twrp_check.sh) | Runs ON the phone inside TWRP (pushed by twrp_check.ps1). Checks that TWRP can see and use storage. |
| [`twrp_sysdiag.ps1`](device/twrp_sysdiag.ps1) | Diagnose why /system won't mount in TWRP. Read-only (e2fsck -n never writes). |

## analysis/

Research scripts kept for reference: firmware inspection, ABI / symbol / policy checks, kernel comparisons, reverse-engineering helpers. Not part of the build.

| Script | What it does |
|---|---|
| [`abi_diff.sh`](analysis/abi_diff.sh) | Where do the Tab S4 Q (t830_q) and S8 Pie (g9500_pp) kernels differ in the parts the S8 Pie vendor blobs talk to? 1) userspace ABI headers (include/uapi + msm media headers)  2) ABI-sensitive driver d… |
| [`abi_hdr_diff.sh`](analysis/abi_hdr_diff.sh) | show the exact Pie->Q changes in the UAPI headers the S8 Pie vendor blobs use. |
| [`abi_users.sh`](analysis/abi_users.sh) | do ELFs that stay T835 still find every symbol they import from libraries we replaced with S8 copies? |
| [`apr_probe.sh`](analysis/apr_probe.sh) | APR (audio DSP link) driver in Q (t830_q) vs S8 Pie (g9500_pp) - the crash site. |
| [`check_compat.sh`](analysis/check_compat.sh) | can the G9600 Android 10 system run on the S8 Pie vendor? + G9600 debloat candidates by size. |
| [`check_efs_backup.sh`](analysis/check_efs_backup.sh) | sanity-check an efs.img backup (lists structure only, never prints IMEI/serial contents). |
| [`check_q_reqs.sh`](analysis/check_q_reqs.sh) | Android 10 requirements the S8 port must satisfy (APEX type, kernel features, encryption, selinux). |
| [`check_vndk28.sh`](analysis/check_vndk28.sh) | VNDK-28 pieces in S8 Pie system vs what the G9600 Q system has. |
| [`compare_media.sh`](analysis/compare_media.sh) | boot/charging animation assets in stock S8 (CZE1) vs G9600 (Android 10) system/media. |
| [`compat_check.sh`](analysis/compat_check.sh) | For every 'compatible' string in the stock SCV36 JPN r12 device tree, check whether a driver in each kernel tree claims it (string present in a .c file). Shows which hardware each kernel can actually … |
| [`cp_mbns.sh`](analysis/cp_mbns.sh) | list the carrier modem profiles (MCFG mcfg_sw.mbn) inside a Samsung CP_*.tar.md5 (or a modem.bin). A VoLTE donor must carry a profile covering Vietnamese carriers (e.g. row/viettel, row/common, open m… |
| [`dbgpart_probe.sh`](analysis/dbgpart_probe.sh) | what does Samsung's sec_debug_partition write to the 'debug' partition on panic? |
| [`deodex_services.sh`](analysis/deodex_services.sh) | deodex stock CZE1 services via the oat (services.odex + services.vdex side by side) -> smali, then locate the KnoxGuard service and where SystemServer starts it. Samsung Pie stores CompactDex (cdex001… |
| [`dtb_find.py`](analysis/dtb_find.py) | Find device-tree node paths whose 'compatible' contains a string, in a (possibly concatenated) DTB file. |
| [`dts_compare.sh`](analysis/dts_compare.sh) | Clone the Canadian Snapdragon S8 Pie kernel (same 4.4.153 base), build its dreamq DTBs, and diff its rev12 tree against the stock SCV36 (JPN) rev12 DTB to see what is Japan-specific. |
| [`dts_paths.py`](analysis/dts_paths.py) | Print full node paths in a decompiled .dts whose node name matches a regex. usage: dts_paths.py <file.dts> <regex> |
| [`dump_s8_system_libs.sh`](analysis/dump_s8_system_libs.sh) | dump S8 Pie /system/lib{,64} (HIDL interface libs live there on Pie) for transplant resolution. |
| [`dump_trees.sh`](analysis/dump_trees.sh) | Dump S8 stock vendor and the donor S9 system tree into WSL ext4 (~/s8rom/trees) for size/debloat analysis. |
| [`find_symbol.sh`](analysis/find_symbol.sh) | which S8 Pie library (vendor or system) defines a symbol, and what the G9600 Q system has under that name. |
| [`fp_dts_src.sh`](analysis/fp_dts_src.sh) | where the G9500 PP DTS defines fingerprint nodes, and which dreamq JPN files include them. |
| [`fp_node.sh`](analysis/fp_node.sh) | fingerprint node in G9500-source JPN r12 DTS vs stock (CZE1) JPN r12 DTB. |
| [`fp_probe.sh`](analysis/fp_probe.sh) | locate the fingerprint driver for the JPN 'fps,common' node in both trees. |
| [`fpemu.py`](analysis/fpemu.py) | Differential emulation of the fingerprint kernel driver (stock SCV36 fps_* vs our et5xx etspi_*). |
| [`fscaps_probe.sh`](analysis/fscaps_probe.sh) | file capabilities (fs_config_files) of the T835, S8 and port vendors, and how the tools carry them. |
| [`g9500_probe.sh`](analysis/g9500_probe.sh) | unpack SM-G9500 CHN PP kernel source and check SCV36 (jpn_kdi) support in it. |
| [`g9600_vendor_policy.sh`](analysis/g9600_vendor_policy.sh) | does the G9600 Q vendor run the same Samsung NFC / fingerprint HALs, and what SELinux does it give them? |
| [`hw_data_diff.sh`](analysis/hw_data_diff.sh) | hardware data files that differ between S8 Pie vendor and T835 Q vendor (wifi/bt fw, audio, ueventd, sensors). |
| [`inspect_donor.sh`](analysis/inspect_donor.sh) | Read-only look at the donor (SCV38, Android 10) images with debugfs. Run inside WSL. |
| [`inspect_g9600.sh`](analysis/inspect_g9600.sh) | Run inside WSL: dump the G9600 donor /system (system-as-root) to ~/s8rom/trees/g9600_root and report what matters. |
| [`inspect_g9600_boot.sh`](analysis/inspect_g9600_boot.sh) | how does the G9600 Android 10 boot? (ramdisk content, fstab, SAR/2SI) + size budget for the port. |
| [`inspect_g9600_root.sh`](analysis/inspect_g9600_root.sh) | SAR root of the G9600 system image (entries at /, vendor/odm mountpoints, /system/vendor) + odm omc layout. |
| [`inspect_image.sh`](analysis/inspect_image.sh) | mount the built port system image read-only and run a python check against it. |
| [`inspect_services.sh`](analysis/inspect_services.sh) | pull services.jar (+ odex/vdex) and KnoxGuard permission files from the stock CZE1 system image. |
| [`inspect_system.sh`](analysis/inspect_system.sh) | Read-only inspection of a raw (unsparsed) Samsung system ext4 image with debugfs (run inside WSL). |
| [`inspect_t835.sh`](analysis/inspect_t835.sh) | analyse the Tab S4 (SM-T835) Android 10 vendor as the base vendor for the S8 One UI 2 port. |
| [`inspect_t835_boot.sh`](analysis/inspect_t835_boot.sh) | T835 (msm8998 Android 10) boot image: cmdline, ramdisk type (2SI?), DT fstab. |
| [`inspect_xxv.sh`](analysis/inspect_xxv.sh) | unsparse the G960F OXM odm image and find the XXV (Vietnam) CSC config. |
| [`jp_nodes.sh`](analysis/jp_nodes.sh) | compatible strings of JPN-only DT nodes, and which kernel trees carry their drivers. |
| [`kernel_gap.sh`](analysis/kernel_gap.sh) | Compare the stock SCV36 kernel config (Pie, from IKCONFIG) against the Tab S4 Q tree: which enabled symbols have no Kconfig definition in the Q tree (= missing S8 drivers). |
| [`kernel_probe.sh`](analysis/kernel_probe.sh) | Inspect the cloned Tab S4 Q kernel: build script, toolchain, defconfigs, S8 (dream) board support. |
| [`kgsl_probe.sh`](analysis/kgsl_probe.sh) | Pie -> Q kgsl changes touching read-only / privileged GPU buffers (the CP write fault). |
| [`km_probe.sh`](analysis/km_probe.sh) | why does vendor.keymaster-3-0 exit 1 on the port? compare keystore/keymaster props + files S8 vs port vendor |
| [`km_probe2.sh`](analysis/km_probe2.sh) | keymaster@3.0 on the port vendor - labels, policy, manifest, linkage |
| [`km_probe3.sh`](analysis/km_probe3.sh) | SELinux rules of the keymaster / gatekeeper HAL domains in the port policy (tee_device, qseecom, hwservice). |
| [`km_probe4.sh`](analysis/km_probe4.sh) | hal_keymaster rules and attributes in the port vendor cil. |
| [`km_probe5.sh`](analysis/km_probe5.sh) | where does each NEEDED of the keymaster/gatekeeper stack resolve, and is it visible to the vendor namespace? |
| [`km_probe6.sh`](analysis/km_probe6.sh) | soft-keymaster libs and pd-mapper / per_mgr / pm-service in S8 Pie vs the port vendor. |
| [`list_apps.sh`](analysis/list_apps.sh) | List donor apps with sizes + package names (from AndroidManifest via aapt if present, else dir name). |
| [`list_g9600_apps.sh`](analysis/list_g9600_apps.sh) | all G9600 system apps with sizes (MiB) -> work/donor_G9600/app_sizes.txt |
| [`mbn_ims.sh`](analysis/mbn_ims.sh) | extract MCFG profiles from a modem.bin / CP tar and show the IMS / VoLTE related EFS items each one sets. |
| [`mcfg_dump.sh`](analysis/mcfg_dump.sh) | dump MCFG profiles from a CP tar via mcfg_parse.py. usage: mcfg_dump.sh <CP tar> <profile substr> [grep] |
| [`mcfg_hex.sh`](analysis/mcfg_hex.sh) | hex dump of one MCFG profile (mcfg_sw.mbn) from a CP tar. usage: mcfg_hex.sh <CP tar> <profile path substring> |
| [`mcfg_parse.py`](analysis/mcfg_parse.py) | Parse a Qualcomm MCFG profile (mcfg_sw.mbn) and list the items it sets: NV item ids and EFS file paths (with a |
| [`mdt_check.py`](analysis/mdt_check.py) | Compare modem.mdt program headers with the split blob sizes (modem.bNN). usage: mdt_check.py <dir with modem.mdt + bNN> |
| [`modem_probe.sh`](analysis/modem_probe.sh) | modem firmware paths, fstab mounts and per_mgr / pd_mapper rc entries, port vs S8 Pie. |
| [`modem_probe2.sh`](analysis/modem_probe2.sh) | S8 fstabs, ueventd firmware directories and firmware images on disk. |
| [`modem_probe3.sh`](analysis/modem_probe3.sh) | which SCV36 image holds modem.mdt/b11, and are mdt + blobs consistent? |
| [`modem_probe4.sh`](analysis/modem_probe4.sh) | extract modem.mdt + modem.bNN from modem.bin and check them with mdt_check.py. |
| [`nfc_check.sh`](analysis/nfc_check.sh) | Samsung FeliCa NFC driver (sec-nfc) in both trees vs stock DT node + stock config. |
| [`nfc_data.sh`](analysis/nfc_data.sh) | NFC HAL interfaces + data files on S8 Pie vendor vs T835 Q vendor. |
| [`port10_classify.sh`](analysis/port10_classify.sh) | Runs in WSL after port10_vndk.sh. For each system lib the S8 vendor needs: does the Android-10 donor have it, does the S8 Pie system have it? -> decides vndk-28 contents. |
| [`port10_ldcfg.sh`](analysis/port10_ldcfg.sh) | linker config (ld.config*), vndk-sp-28 / vndk-28 presence: G9600 donor vs S8 Pie. |
| [`port10_plan.sh`](analysis/port10_plan.sh) | Compare what the Android-10 donor system expects (VNDK, SAR/init) against what the S8 Pie vendor provides. |
| [`port10_sepol.sh`](analysis/port10_sepol.sh) | SELinux policy file layout of S8 Pie (monolithic) vs the G9600 donor (split policy, mapping versions). |
| [`port10_vndk.sh`](analysis/port10_vndk.sh) | Work out the vndk-28 set the S8 Pie vendor needs on an Android-10 system: every DT_NEEDED of every vendor ELF that is not provided by the vendor itself and is not an LL-NDK library. |
| [`re_annotate.py`](analysis/re_annotate.py) | Reverse-engineering helper (build server, venv with pyelftools): disassemble a function of a vmlinux-to-elf |
| [`re_thumb.py`](analysis/re_thumb.py) | Reverse-engineering helper for 32-bit ARM (Thumb-2) Android shared libraries (build server, venv with pyelftools + |
| [`restart_probe.sh`](analysis/restart_probe.sh) | rest of the msm restart path (Q tree) + compare the odd panic("recovery") with S8 Pie source. |
| [`reverse_compat.sh`](analysis/reverse_compat.sh) | Q-tree drivers (compiled into our kernel) whose of_match compatibles are ALL absent from the stock S8 Pie DT, but whose Pie-tree counterpart did NOT need a DT node -> same trap as APR (init never runs… |
| [`shim_qemu_test/`](analysis/shim_qemu_test) | Sub-project (see its scripts) |
| [`twrp_inspect.sh`](analysis/twrp_inspect.sh) | unpack TWRP dreamqlte and stock SCV36 recovery with magiskboot; compare kernel, DTB models, fstab. |
| [`tz_hals.sh`](analysis/tz_hals.sh) | TrustZone-backed HALs (must match the S8's own TZ apps) + Samsung hwservice names that need labels. |
| [`usb_probe.sh`](analysis/usb_probe.sh) | USB gadget / conn_gadget init triggers and usb props, port vendor vs S8 Pie vs G9600. |
| [`users_of.sh`](analysis/users_of.sh) | which ELFs in a vendor tree NEED a given library. usage: bash users_of.sh <tree> <lib.so>... |
| [`vndk_lite_values.sh`](analysis/vndk_lite_values.sh) | collect the values needed to fill AOSP Q's ld.config.vndk_lite.txt template. |
| [`warmreset_probe.sh`](analysis/warmreset_probe.sh) | who overrides the warm-reset request in the restart path? |
| [`xref_str.sh`](analysis/xref_str.sh) | find code that references a string in an arm64 .so (adrp+add pairs) and print surrounding disassembly. |

## gearvr/

Firefox Reality rebuilt for the Gear VR runtime (VrApi 1.1.26, current GeckoView).

| Script | What it does |
|---|---|
| [`build_fxr_gearvr.sh`](gearvr/build_fxr_gearvr.sh) | Build server (~/fxr): Firefox Reality for Gear VR on the SCV36 port. ~/fxr/FirefoxReality          MozillaReality/FirefoxReality (final tree, + vrb submodule) |
| [`patch_fxr_gearvr.py`](gearvr/patch_fxr_gearvr.py) | Patch Firefox Reality (MozillaReality/FirefoxReality, final tree bc6f43f6, MPL-2.0) into a Gear VR build. |

## lib/

Shared shell code.

| Script | What it does |
|---|---|
| [`env.sh`](lib/env.sh) | Sourced by the tools: repo root + local settings (config/local.env, not in git - copy config/local.env.example). S8PORT     repo checkout (this folder) |
