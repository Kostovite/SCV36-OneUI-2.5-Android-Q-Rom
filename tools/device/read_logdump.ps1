# In TWRP after an AP_7 debug boot: read the kernel log the s8dbg hook wrote to the start of the 'cache' partition.
# Usage: powershell -ExecutionPolicy Bypass -File tools\read_logdump.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path $PSScriptRoot ("..\..\debug\logdump_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
& $Adb wait-for-recovery
& $Adb shell "umount /cache 2>/dev/null; dd if=/dev/block/bootdevice/by-name/cache of=/tmp/s8dbg.bin bs=4096 count=520" 2>&1 | Out-Null
& $Adb pull /tmp/s8dbg.bin (Join-Path $Out "cache_head.bin") | Out-Null
if (-not (Test-Path (Join-Path $Out "cache_head.bin"))) {
    Write-Host "Could not copy from the phone (adb dropped). Use the TWRP Terminal + MTP method instead." -ForegroundColor Red
    exit 1
}
$bytes = [IO.File]::ReadAllBytes((Join-Path $Out "cache_head.bin"))
$hdr = [Text.Encoding]::ASCII.GetString($bytes, 0, 256).Split("`n")[0]
if ($hdr -notmatch '^S8DBGLOG (\d+) ?(.*)$') {
    Write-Host "No S8DBGLOG header in cache -> the kernel never reached the reboot hook (likely a kernel panic or watchdog)." -ForegroundColor Yellow
} else {
    $len = [int]$Matches[1]; $cmd = $Matches[2]
    $log = [Text.Encoding]::UTF8.GetString($bytes, 4096, [Math]::Min($len, $bytes.Length - 4096))
    $log | Out-File -Encoding utf8 (Join-Path $Out "kernel_log.txt")
    Write-Host "Reboot command: '$cmd'   kernel log: $len bytes"
    Write-Host "---- last 40 lines ----"
    ($log -split "`n" | Select-Object -Last 40) -join "`n" | Write-Host
}
& $Adb shell dmesg | Out-File -Encoding utf8 (Join-Path $Out "dmesg_twrp.txt")
Write-Host "Saved -> $((Resolve-Path $Out).Path)"
Write-Host "(cache now holds raw log data - TWRP: Wipe > Advanced > Cache, or it is reformatted by the ROM install)"
