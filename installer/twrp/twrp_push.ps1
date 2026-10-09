# Flash a new boot image + small system files from TWRP over adb (no Odin needed).
# Phone: booted into TWRP, Mount -> Disable MTP. PC: run from this folder:
#   powershell -ExecutionPolicy Bypass -File twrp_push.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

function Retry([scriptblock]$cmd, [string]$what) {
    for ($i = 1; $i -le 10; $i++) {
        & $Adb wait-for-recovery
        & $cmd
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "  retry $i ($what)"; Start-Sleep 2
    }
    throw "failed: $what"
}

& $Adb kill-server
Retry { & $Adb push "$here\boot.img" /tmp/boot.img } "push boot.img"
Retry { & $Adb shell "dd if=/tmp/boot.img of=/dev/block/bootdevice/by-name/boot bs=4096 && sync" } "flash boot"
Write-Host "boot flashed"

# vendor init file that cancels the debug boot watchdog after a successful boot
Retry { & $Adb shell "mount /system_root 2>/dev/null || mount /system 2>/dev/null; true" } "mount system"
$rcdir = (& $Adb shell "if [ -d /system_root/system/vendor/etc/init ]; then echo /system_root/system/vendor/etc/init; else echo /system/system/vendor/etc/init; fi").Trim()
Retry { & $Adb push "$here\s8dbg.rc" "$rcdir/s8dbg.rc" } "push s8dbg.rc"
Retry { & $Adb shell "chmod 0644 $rcdir/s8dbg.rc && chcon u:object_r:vendor_configs_file:s0 $rcdir/s8dbg.rc && ls -lZ $rcdir/s8dbg.rc && sync" } "label s8dbg.rc"
Write-Host "done - in TWRP choose Reboot -> System"
