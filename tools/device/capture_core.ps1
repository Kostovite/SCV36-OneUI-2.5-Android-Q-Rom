# One run for the three open items: Samsung Camera (switch crash / front flip), fingerprint, iris.
# Uses root (Magisk su) when available for the kernel log, tombstones and /data/vendor state; works without it too.
# Usage: powershell -ExecutionPolicy Bypass -File tools\capture_core.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path (Get-Location) ("core_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
function F($n) { Join-Path $Out $n }
function Sh($cmd, $file) { & $Adb shell $cmd 2>&1 | Out-File -Append -Encoding utf8 (F $file) }
function Root($cmd, $file) { if ($script:HasSu) { & $Adb shell "su -c '$cmd'" 2>&1 | Out-File -Append -Encoding utf8 (F $file) } }
function Shot($n) { & $Adb shell "screencap -p /data/local/tmp/cap.png" 2>&1 | Out-Null; & $Adb pull /data/local/tmp/cap.png (F "$n.png") 2>&1 | Out-Null }
function Step($msg) { Write-Host ""; Read-Host ">>> $msg  [Enter when done]" | Out-Null }

Write-Host "saving to $Out"
& $Adb wait-for-device
$id = (& $Adb shell "su -c id" 2>&1) -join " "
$script:HasSu = $id -match "uid=0"
Write-Host ("root: " + $(if ($script:HasSu) { "yes" } else { "no (kernel log / tombstones skipped)" }))
"su: $id" | Out-File -Encoding utf8 (F "info.txt")
Sh "getprop | grep -iE 'ro.build.display|ro.boot.bootloader|persist.camera|vendor.camera|ro.hardware'" "info.txt"
# (no "dmesg -C": the boot part of the kernel log holds the fingerprint/iris bring-up)
Root "dmesg" "dmesg_boot.txt"
& $Adb logcat -G 16M 2>&1 | Out-Null
& $Adb logcat -c 2>&1 | Out-Null
$log = Start-Process -FilePath $Adb -ArgumentList "logcat -b all -v threadtime" -RedirectStandardOutput (F "logcat.txt") -NoNewWindow -PassThru

# ---- 1. Samsung Camera ---------------------------------------------------------------------------------------
Write-Host "`n== 1/3 Samsung Camera"
& $Adb shell "am force-stop com.sec.android.app.camera" 2>&1 | Out-Null
# (no "am start -W": the S8 SamsungCamera never reports "fully drawn" on this ROM -> -W blocks forever)
& $Adb shell "am start -n com.sec.android.app.camera/.Camera" 2>&1 | Out-File -Encoding utf8 (F "camera_start.txt")
Start-Sleep 5; Shot "cam_rear"
Sh "dumpsys media.camera" "camera_rear_media.txt"
Step "Tap SWITCH CAMERA (rear -> front). Wait 3 s whatever happens (crash or front preview)"
Shot "cam_front"
Sh "dumpsys SurfaceFlinger" "camera_front_sf.txt"
Sh "dumpsys media.camera" "camera_front_media.txt"
Step "If the app is still open: switch back to rear, take one photo. (If it crashed: just continue)"
Shot "cam_after"
Root "dmesg" "dmesg_camera.txt"

# ---- 2. Fingerprint ------------------------------------------------------------------------------------------
Write-Host "`n== 2/3 Fingerprint"
& $Adb shell "am force-stop com.sec.android.app.camera" 2>&1 | Out-Null
Sh "ls -l /dev/fps /dev/esfp0 /dev/vfsspi /dev/qseecom; ls -lZ /dev/fps" "fp_state.txt"
Sh "ps -A -Z | grep -iE 'fingerprint|bauth|qseecom'" "fp_state.txt"
Sh "dumpsys fingerprint" "fp_state.txt"
Root "ls -lRZ /data/vendor/biometrics" "fp_state.txt"
Root "cat /sys/class/fingerprint/fingerprint/type_check /sys/class/fingerprint/fingerprint/name /sys/class/fingerprint/fingerprint/vendor /sys/class/fingerprint/fingerprint/adm" "fp_state.txt"
& $Adb shell "am start -a android.settings.SECURITY_SETTINGS" 2>&1 | Out-Null
Step "Settings > Biometrics and security > Fingerprints: start adding a fingerprint, touch the sensor 3-4 times (screenshot if an error shows)"
Shot "fp_screen"
Root "dmesg" "dmesg_fingerprint.txt"

# ---- 3. Iris -------------------------------------------------------------------------------------------------
Write-Host "`n== 3/3 Iris"
Sh "ps -A -Z | grep -iE 'iris|faced'" "iris_state.txt"
Sh "dumpsys iris" "iris_state.txt"
Sh "service list | grep -iE 'iris|biometric'" "iris_state.txt"
Sh "lshal | grep -iE 'iris|biometric'" "iris_state.txt"
Step "Settings > Biometrics and security > Iris scanner: try to register (screenshot if an error shows)"
Shot "iris_screen"
Root "dmesg" "dmesg_iris.txt"

# ---- crashes --------------------------------------------------------------------------------------------------
Start-Sleep 2
Stop-Process -Id $log.Id -Force -ErrorAction SilentlyContinue
& $Adb shell "for t in data_app_crash system_app_crash data_app_anr SYSTEM_TOMBSTONE; do echo == `$t; dumpsys dropbox --print `$t 2>&1 | tail -300; done" 2>&1 | Out-File -Encoding utf8 (F "crashes.txt")
Root "ls -lt /data/tombstones; for f in `$(ls -t /data/tombstones/tombstone_* 2>/dev/null | head -4); do echo == `$f; head -120 `$f; done" "tombstones.txt"
Write-Host "`ndone: $Out  - send me this folder"
