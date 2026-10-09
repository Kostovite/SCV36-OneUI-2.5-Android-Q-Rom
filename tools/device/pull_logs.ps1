# After a failed boot that landed in TWRP: copy the 'cache' log dump and Samsung's 'debug' partition to the PC.
# Phone: TWRP main screen (MTP disabled). Every step retries if adb drops.
# Usage: powershell -ExecutionPolicy Bypass -File tools\pull_logs.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path $PSScriptRoot ("..\..\debug\run_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null

function Retry([scriptblock]$cmd, [string]$what) {
    for ($i = 1; $i -le 10; $i++) {
        & $Adb wait-for-recovery
        & $cmd
        if ($LASTEXITCODE -eq 0) { Write-Host "ok: $what"; return }
        Write-Host "  retry $i ($what)"; Start-Sleep 2
    }
    throw "failed after 10 tries: $what"
}

& $Adb kill-server
Retry { & $Adb shell "umount /cache 2>/dev/null; dd if=/dev/block/bootdevice/by-name/cache of=/tmp/cache_head.bin bs=4096 count=520" } "read cache"
Retry { & $Adb shell "dd if=/dev/block/bootdevice/by-name/debug of=/tmp/debugpart.img bs=1048576" } "read debug partition"
# tombstones = native crash reports (why services abort); /data is unencrypted on the port
# + dropbox = Java crash reports with full stack traces (system_server / app crashes, "internal problem" dialog),
#   Samsung /data/log, last boot's property state; adb_check = why adb did not come up on the port
Retry { & $Adb shell "mount /data 2>/dev/null; cd /data && tar -czf /tmp/crash.tgz tombstones vendor/tombstones anr system/dropbox log misc/logd property/persistent_properties 2>/dev/null; ls -la /tmp/crash.tgz" } "pack tombstones + dropbox"
Retry { & $Adb shell "mount /system_root 2>/dev/null || mount /system 2>/dev/null; for f in /system_root/system/etc/prop.default /system_root/system/build.prop /system/etc/prop.default /system/build.prop; do [ -f `$f ] && echo == `$f && grep -E 'adb|usb.config|ro.secure|ro.debuggable' `$f; done; ls -la /data/misc/adb 2>&1; ls /data/system/dropbox | tail -40" > (Join-Path $Out "adb_check.txt") } "adb check"
Retry { & $Adb pull /tmp/crash.tgz (Join-Path $Out "crash.tgz") } "pull tombstones"
Retry { & $Adb pull /tmp/cache_head.bin (Join-Path $Out "cache_head.bin") } "pull cache_head.bin"
Retry { & $Adb pull /tmp/debugpart.img (Join-Path $Out "debugpart.img") } "pull debugpart.img"
Get-ChildItem $Out | ForEach-Object { "{0,-16} {1,12:N0} bytes" -f $_.Name, $_.Length }
Write-Host "Saved -> $((Resolve-Path $Out).Path)"
