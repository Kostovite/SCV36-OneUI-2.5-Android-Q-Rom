# Camera + torch test capture: run it with the phone booted and adb connected. It walks you through rear preview,
# front preview and the torch slider and grabs, at each step, a screenshot, the SurfaceFlinger layer/buffer dump
# (preview buffer format + stride: explains striped previews) and the camera service state; logcat for the whole run.
# Usage: powershell -ExecutionPolicy Bypass -File capture_camera.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path (Get-Location) ("camera_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
Write-Host "saving to $Out"
& $Adb wait-for-device
& $Adb logcat -G 16M 2>&1 | Out-Null
& $Adb logcat -c 2>&1 | Out-Null
$log = Start-Process -FilePath $Adb -ArgumentList "logcat -b all -v threadtime" -RedirectStandardOutput (Join-Path $Out "logcat.txt") -NoNewWindow -PassThru

function Snap($name) {
    Write-Host "  capturing $name ..."
    & $Adb shell "screencap -p /data/local/tmp/s8cap.png" 2>&1 | Out-Null
    & $Adb pull /data/local/tmp/s8cap.png (Join-Path $Out "$name.png") 2>&1 | Out-Null
    & $Adb shell "dumpsys SurfaceFlinger" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "$name`_surfaceflinger.txt")
    & $Adb shell "dumpsys media.camera" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "$name`_camera.txt")
    & $Adb shell "cat /sys/class/camera/flash/rear_flash" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "$name`_torch.txt")
}

$steps = [ordered]@{
    "rear"  = "Open the Camera app on the REAR camera, wait 3 s with the preview showing, then press Enter"
    "photo" = "Take a photo (shutter), wait until it is saved, then press Enter"
    "front" = "Switch to the FRONT camera, wait 3 s, then press Enter"
    "video" = "Switch to Video, record ~5 s, stop, then press Enter"
    "torch" = "Close the camera. Turn the torch on in quick settings, long-press it and move the brightness slider to max, then press Enter"
    "torch_low" = "Move the torch slider to the lowest level, then press Enter (then turn the torch off)"
}
foreach ($k in $steps.Keys) {
    Read-Host $steps[$k] | Out-Null
    Snap $k
}
Start-Sleep 2
Stop-Process -Id $log.Id -Force -ErrorAction SilentlyContinue
& $Adb shell "for t in system_app_crash data_app_crash system_app_native_crash SYSTEM_TOMBSTONE; do echo == `$t; dumpsys dropbox --print `$t 2>&1 | tail -300; done" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "crashes.txt")
& $Adb shell "ls -lt /sdcard/DCIM/Camera | head" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "dcim.txt")
Write-Host "done: $Out  - send me this folder (the last photo in DCIM/Camera too, if one was taken)"
