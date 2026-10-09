# Samsung Camera "preview shows but no touch works" capture: launches the S8 SamsungCamera, waits, taps the screen and
# the shutter by itself, and saves the logs needed to see why the app never activates its shooting mode
# (SemCamera COMMON_SHOT_PREVIEW_STARTED / onStartPreviewCompleted) or whether the UI thread is blocked (ANR).
# Usage: powershell -ExecutionPolicy Bypass -File capture_samsung_camera.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path (Get-Location) ("samsungcam_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
Write-Host "saving to $Out"
& $Adb wait-for-device
& $Adb shell "am force-stop com.sec.android.app.camera" 2>&1 | Out-Null
& $Adb logcat -G 16M 2>&1 | Out-Null
& $Adb logcat -c 2>&1 | Out-Null
$log = Start-Process -FilePath $Adb -ArgumentList "logcat -b all -v threadtime" -RedirectStandardOutput (Join-Path $Out "logcat.txt") -NoNewWindow -PassThru

Write-Host "launching Samsung Camera (keep the phone unlocked, screen on) ..."
& $Adb shell "am start -n com.sec.android.app.camera/.Camera" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "am_start.txt")
Start-Sleep 6
& $Adb shell "screencap -p /data/local/tmp/s8cam1.png" 2>&1 | Out-Null
& $Adb pull /data/local/tmp/s8cam1.png (Join-Path $Out "after_launch.png") 2>&1 | Out-Null

# tap the middle of the preview (touch AF), then the shutter area, then the mode bar
$size = (& $Adb shell "wm size") -replace '.*:\s*', ''
$w, $h = ($size.Trim() -split 'x') | ForEach-Object { [int]$_ }
Write-Host "screen ${w}x${h}: tapping preview, shutter, mode bar ..."
& $Adb shell "input tap $([int]($w/2)) $([int]($h*0.4))" | Out-Null; Start-Sleep 2
& $Adb shell "input tap $([int]($w/2)) $([int]($h*0.88))" | Out-Null; Start-Sleep 3
& $Adb shell "input swipe $([int]($w*0.7)) $([int]($h*0.78)) $([int]($w*0.3)) $([int]($h*0.78)) 200" | Out-Null; Start-Sleep 3
& $Adb shell "screencap -p /data/local/tmp/s8cam2.png" 2>&1 | Out-Null
& $Adb pull /data/local/tmp/s8cam2.png (Join-Path $Out "after_taps.png") 2>&1 | Out-Null

# front camera: flipped preview + crash on switch. SurfaceFlinger shows the camera buffer transform (who flips).
& $Adb shell "am start -n com.sec.android.app.camera/.Camera" 2>&1 | Out-Null
Start-Sleep 3
& $Adb shell "dumpsys SurfaceFlinger" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "sf_rear.txt")
Read-Host "Now tap the SWITCH CAMERA button in Samsung Camera (rear -> front). If it shows the front preview, leave it 3 s. Then press Enter here" | Out-Null
& $Adb shell "screencap -p /data/local/tmp/s8cam3.png" 2>&1 | Out-Null
& $Adb pull /data/local/tmp/s8cam3.png (Join-Path $Out "front.png") 2>&1 | Out-Null
& $Adb shell "dumpsys SurfaceFlinger" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "sf_front.txt")
& $Adb shell "dumpsys media.camera" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "media_camera_front.txt")
& $Adb shell "am start -n com.sec.android.app.camera/.Camera" 2>&1 | Out-Null
Start-Sleep 4

# state of the app, its threads and the framework library it really loaded
$camPid = (& $Adb shell "pidof com.sec.android.app.camera").Trim()
"pid=$camPid" | Out-File -Encoding utf8 (Join-Path $Out "state.txt")
& $Adb shell "dumpsys activity activities | grep -iE 'mResumedActivity|mFocusedApp|camera'" 2>&1 | Out-File -Append -Encoding utf8 (Join-Path $Out "state.txt")
& $Adb shell "dumpsys window | grep -iE 'mCurrentFocus|mFocusedApp|ANR|Not Responding'" 2>&1 | Out-File -Append -Encoding utf8 (Join-Path $Out "state.txt")
if ($camPid) {
    & $Adb shell "grep -iE 'semcamera|SamsungCamera' /proc/$camPid/maps | sort -u -k6" 2>&1 | Out-File -Append -Encoding utf8 (Join-Path $Out "state.txt")
    & $Adb shell "kill -3 $camPid" 2>&1 | Out-Null          # Java stack dump of every thread (shows a blocked UI thread)
    Start-Sleep 3
}
& $Adb shell "ls -l /system/framework/semcamera.jar /system/framework/oat/*/semcamera.* /system/priv-app/SamsungCamera; md5sum /system/framework/semcamera.jar" 2>&1 | Out-File -Append -Encoding utf8 (Join-Path $Out "state.txt")
& $Adb shell "dumpsys media.camera" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "media_camera.txt")
Start-Sleep 2
Stop-Process -Id $log.Id -Force -ErrorAction SilentlyContinue
& $Adb shell "ls -t /data/anr | head -3; for f in `$(ls -t /data/anr/* 2>/dev/null | head -2); do echo == `$f; cat `$f; done" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "anr.txt")
& $Adb shell "for t in data_app_anr data_app_crash system_app_crash SYSTEM_TOMBSTONE; do echo == `$t; dumpsys dropbox --print `$t 2>&1 | tail -200; done" 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "crashes.txt")
Write-Host "done: $Out  - send me this folder"
