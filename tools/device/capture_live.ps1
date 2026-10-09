# Port running (adb up): grab logs + display/radio/wifi state over adb into .\live_<time> (current folder).
# Usage: powershell -ExecutionPolicy Bypass -File capture_live.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path (Get-Location) ("live_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
Write-Host "saving to $Out"
Write-Host "waiting for the phone (adb device)..."
& $Adb wait-for-device
$jobs = [ordered]@{
    "getprop.txt"          = "getprop"
    "logcat_all.txt"       = "logcat -b all -d -v threadtime"
    "dmesg.txt"            = "dmesg"
    "display.txt"          = "dumpsys display"
    "surfaceflinger.txt"   = "dumpsys SurfaceFlinger"
    "window_displays.txt"  = "dumpsys window displays"
    "window_windows.txt"   = "dumpsys window windows"
    "activity_top.txt"     = "dumpsys activity top"
    "wm_size_density.txt"  = "wm size; wm density; settings get global display_size_forced"
    "wifi.txt"             = "dumpsys wifi; ls -la /vendor/etc/wifi /data/vendor/wifi 2>&1; getprop | grep -i -E 'wlan|wifi|wpa'"
    "telephony.txt"        = "dumpsys telephony.registry; dumpsys isub; getprop | grep -i -E 'ril|radio|gsm|sim|modem'"
    "services.txt"         = "service list; lshal -i 2>&1"
    "tombstones.txt"       = "ls -la /data/tombstones /data/vendor/tombstones 2>&1"
}
foreach ($k in $jobs.Keys) {
    Write-Host "  $k"
    & $Adb shell $jobs[$k] 2>&1 | Out-File -Encoding utf8 (Join-Path $Out $k)
}
Write-Host "  screen.png"
& $Adb shell "screencap -p /data/local/tmp/screen.png" 2>&1 | Out-Null
& $Adb pull /data/local/tmp/screen.png (Join-Path $Out "screen.png") 2>&1 | Out-Null
Get-ChildItem $Out | ForEach-Object { "{0,-24} {1,12:N0} bytes" -f $_.Name, $_.Length }
Write-Host "Saved -> $Out"
