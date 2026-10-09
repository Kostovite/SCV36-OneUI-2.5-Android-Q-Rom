# Record logcat + kernel log from every bootloop iteration (needs AP_5 debug-adb boot image on the phone).
# Usage: powershell -ExecutionPolicy Bypass -File tools\capture_bootloop.ps1 [-Loops 3] [-Adb C:\path\adb.exe]
# Leave the phone looping on its own with USB plugged in; stop with Ctrl+C after a few loops.
param([int]$Loops = 3, [string]$Adb = "adb")
$Out = Join-Path $PSScriptRoot ("..\..\debug\loopcap_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
for ($i = 1; $i -le $Loops; $i++) {
    Write-Host "[$i/$Loops] waiting for adb (phone booting)..."
    & $Adb wait-for-device
    $t = Get-Date -Format "HHmmss"
    Write-Host "[$i/$Loops] connected at $t - recording until the phone reboots"
    # kernel log first (best effort: shell may not be allowed to read it on a user build)
    & $Adb shell "dmesg 2>&1 || cat /proc/kmsg" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "loop${i}_dmesg_$t.txt")
    & $Adb shell "getprop" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "loop${i}_getprop_$t.txt")
    # logcat streams until adb drops (phone rebooting)
    & $Adb logcat -b all -v threadtime 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "loop${i}_logcat_$t.txt")
    Write-Host "[$i/$Loops] disconnected"
}
Get-ChildItem $Out | ForEach-Object { "{0,-40} {1,12:N0} bytes" -f $_.Name, $_.Length }
Write-Host "Saved -> $((Resolve-Path $Out).Path)"
