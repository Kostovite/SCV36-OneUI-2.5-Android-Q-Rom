# Battery drain capture (needs Magisk root).
#   1) powershell -ExecutionPolicy Bypass -File tools\capture_power.ps1 -Start
#      -> resets battery stats; then UNPLUG the phone, screen off, leave it 30-60 min (normal SIM / Wi-Fi state)
#   2) plug back in, run:  powershell -ExecutionPolicy Bypass -File tools\capture_power.ps1
#      -> collects sleep stats, wakeup sources, crash loops, batterystats into power_<date>\
param([switch]$Start, [string]$Adb = "adb")
& $Adb wait-for-device
$id = (& $Adb shell "su -c id" 2>&1) -join " "
if ($id -notmatch "uid=0") { Write-Host "root not available ($id) - approve the Magisk prompt on the phone and run again"; exit 1 }
if ($Start) {
    & $Adb shell "su -c 'dumpsys batterystats --reset; dumpsys batterystats --enable full-wake-history'" | Out-Host
    & $Adb shell "su -c 'mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug; cat /sys/kernel/debug/wakeup_sources > /data/local/tmp/wakeup_sources_start.txt; cat /sys/power/system_sleep/stats /sys/kernel/debug/rpm_stats > /data/local/tmp/sleep_stats_start.txt 2>/dev/null; date > /data/local/tmp/power_start.txt'" | Out-Host
    Write-Host "Battery stats reset. Now UNPLUG the phone, turn the screen off and leave it 30-60 min. Then plug in and run this script again without -Start."
    exit 0
}
$Out = Join-Path (Get-Location) ("power_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
# helper .sh: next to this script, else in the project tools folder (copies of the .ps1 elsewhere lack it)
$Helper = Join-Path $PSScriptRoot "power_dump.sh"
& $Adb push $Helper /data/local/tmp/power_dump.sh 2>&1 | ForEach-Object { "$_" } | Out-Host   # (adb prints progress on stderr)
& $Adb shell "su -c 'sh /data/local/tmp/power_dump.sh'" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "run.txt")
& $Adb pull /data/local/tmp/power $Out 2>&1 | Out-Null
foreach ($f in "wakeup_sources_start.txt", "sleep_stats_start.txt", "power_start.txt") { & $Adb pull "/data/local/tmp/$f" $Out 2>&1 | Out-Null }
Write-Host "done: $Out  - send me this folder"
