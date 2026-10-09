# Collect crash logs after a failed boot (TWRP)

## Quick way (recommended)

With the phone on the TWRP main screen (MTP disabled), on the PC in `C:\Users\minhh\Documents\s8`:

```powershell
powershell -ExecutionPolicy Bypass -File tools\pull_logs.ps1
```

It reads both partitions and copies both files into `debug\run_<date>\`, retrying any step where adb drops.
Send that folder. The manual steps below are only a fallback.

---

Use this when the phone lands in TWRP by itself after a failed boot of the One UI 2 debug build.
Don't power the phone off or force-restart it before step 2: the logs stay in place until the next boot.

## 1. On the phone (TWRP)

1. **Mount → Disable MTP.** MTP knocks adb offline on this phone.
2. **Advanced → Terminal**, then type these two lines exactly, pressing Enter after each:

```sh
dd if=/dev/block/bootdevice/by-name/cache of=/sdcard/cache_head.bin bs=4096 count=520
dd if=/dev/block/bootdevice/by-name/debug of=/sdcard/debugpart.img bs=1048576
```

Each line should finish with `... records in` / `... records out`.

| File | Size | What it holds |
|---|---|---|
| `cache_head.bin` | 2 MiB | Kernel log written by our reboot hook when Android **asked** to reboot |
| `debugpart.img` | 10 MiB | Kernel log saved by the bootloader after a kernel **panic** |

## 2. On the PC (PowerShell, in `C:\Users\minhh\Documents\s8`)

```powershell
adb kill-server
foreach ($f in "cache_head.bin","debugpart.img") { for ($i=0; $i -lt 10; $i++) { adb wait-for-recovery; adb pull /sdcard/$f debug\$f; if ($?) { break }; Start-Sleep 2 } }
```

The loop retries automatically if adb drops. When it's done, both files are in `debug\`.

## 3. Send them

Copy `debug\cache_head.bin` and `debug\debugpart.img` to
`D:\Users\minhh\Documents\s8_scv36_rom\debug\` on the build PC.

## If adb still won't connect

Put a microSD card in the phone, and in step 1 replace `/sdcard/` with `/external_sd/` in both `dd` lines.
Then read the card on the PC and copy the two files from it.
