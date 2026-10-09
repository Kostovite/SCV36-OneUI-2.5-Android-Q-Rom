# Display layer-by-layer state (phone booted, adb on). Saves .\display_<time>\ in the current folder.
# Usage: powershell -ExecutionPolicy Bypass -File capture_display.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path (Get-Location) ("display_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
& $Adb wait-for-device
$jobs = [ordered]@{
    "settings.txt"   = "wm size; wm density; settings get global display_size_forced; settings get secure display_density_forced; settings get secure default_display_size_forced; settings get secure default_display_density_forced"
    "wm.txt"         = "dumpsys window displays"
    "display.txt"    = "dumpsys display"
    "sf.txt"         = "dumpsys SurfaceFlinger"
    "sf_ids.txt"     = "dumpsys SurfaceFlinger --display-id; dumpsys SurfaceFlinger --list"
    "hwc_props.txt"  = "getprop | grep -i -E 'display|sdm|sf\.|surface|hwc|lcd|panel|mdss|composer'"
    "sysfs.txt"      = "for f in /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/mode /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/msm_fb_panel_info /sys/class/graphics/fb0/msm_fb_type /sys/class/lcd/panel/lcd_type /sys/class/lcd/panel/window_type /sys/class/lcd/panel/multires /sys/class/lcd/panel/resolution; do echo == `$f; cat `$f 2>&1; done; ls /sys/class/lcd/panel/ 2>&1"
    "logcat.txt"     = "logcat -d -v threadtime -b main -b system | grep -i -E 'SDM|HWC|hwcomposer|DisplayDevice|SurfaceFlinger|applyScreenRatio|ForcedDisplay|DisplaySize|mixer|resolution' | tail -400"
}
foreach ($k in $jobs.Keys) { Write-Host "  $k"; & $Adb shell $jobs[$k] 2>&1 | Out-File -Encoding utf8 (Join-Path $Out $k) }
Write-Host "  screen.png (what Android renders)"
& $Adb shell "screencap -p /data/local/tmp/screen.png" 2>&1 | Out-Null
& $Adb pull /data/local/tmp/screen.png (Join-Path $Out "screen.png") 2>&1 | Out-Null
Get-ChildItem $Out | ForEach-Object { "{0,-16} {1,12:N0} bytes" -f $_.Name, $_.Length }
Write-Host "Saved -> $Out"
