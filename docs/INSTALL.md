# Installing the One UI 2 port on an SCV36

Only for the **Galaxy S8 au SCV36** (bootloader `SCV36KDU1C*`), with the **bootloader already OEM-unlocked**.
Everything below wipes the phone. Read the whole page first.

## Release files

| File | What it is |
|---|---|
| `AP_OneUI2_SCV36_<date>.tar.md5` | Odin package for a fresh install: boot (release kernel, no root) + recovery (TWRP for SCV36) + system |
| `s8port_update_<date>.zip` | TWRP zip: boot, the S8 vendor, system additions (camera app, iris, patched libs) + installer |
| `twrp_scv36.img` | TWRP 3.4 for SCV36 (our kernel + SCV36 device trees, adb on by default) |
| `boot_release_noroot.img` | The release boot image on its own |
| `SHA256SUMS` | Checksums – verify before flashing |

## Before you start

1. Charge to > 60 %. Have the stock `SCV36KDU1CZE1` firmware (BL/AP/CP/CSC) at hand to go back.
2. **KnoxGuard**: the phone must not be locked by KnoxGuard / RMM (Download Mode shows no `KG STATE: Locked`).
   Never boot an Android that still contains KnoxGuard on a custom kernel – it locks the phone. The port's system
   is fine; the risk is flashing only our boot over the stock system.
3. Back up the irreplaceable partitions once you have TWRP: `tools/device/twrp_backup.ps1`
   (efs, modemst1/2, fsg, persist, param, boot, recovery). EFS holds the IMEI – keep that backup private.

## Fresh install

1. Download Mode (power off; hold **Volume Down + Bixby**, plug in USB; confirm with Volume Up).
2. Odin 3.13+: AP = `AP_OneUI2_SCV36_<date>.tar.md5`, **untick Auto Reboot**, untick Re-Partition, Start.
3. When Odin says PASS, hold **Volume Down + Power** until the screen goes off, then immediately **Volume Up + Bixby
   + Power** → TWRP.
4. Format `/data` with our script – **not** TWRP's Wipe → Format Data (that triggers an ext4 lazy-init kernel panic
   on this kernel): on the PC, `powershell -ExecutionPolicy Bypass -File installer/twrp/twrp_format_data.ps1`.
5. Flash `s8port_update_<date>.zip` in TWRP (Install), or over adb with `installer/twrp/twrp_vendor.ps1`.
   Its log is `/sdcard/s8port_apply.log`.
6. Reboot (from TWRP use **Reboot → System**, or plain `adb reboot` – not `adb reboot system`).
   The first boot takes a few minutes (app optimisation).

## Updating an installed port

Flash the newer `s8port_update_<date>.zip` in TWRP. It replaces boot, `/system/vendor` (except the CSC data in
`odm/`) and the system additions, and keeps your data.

## Root (optional)

Patch `boot_release_noroot.img` with the Magisk app (or `tools/build/magisk_patch.sh` on a PC) and flash the
result to `boot`. Every update zip flashes the non-root boot again.

## After installing

- Language / region: the default CSC is Vietnam (`XXV`); Viettel / MobiFone / Vinaphone APNs are included.
- Set up fingerprint and iris in Settings → Biometrics.
- Known limits: no VoLTE – voice calls need the carrier's 2G/3G (CSFB); a carrier without them (e.g. Viettel has no 3G) has no calls where 2G is gone; no Samsung Pass / Pay, no FeliCa, no FM radio (no chip).
