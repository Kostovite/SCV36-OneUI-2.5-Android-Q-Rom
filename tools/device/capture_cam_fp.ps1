# Samsung Camera save/record failures + front preview flip, and a live fingerprint bus check (needs Magisk root).
# Usage: powershell -ExecutionPolicy Bypass -File tools\capture_cam_fp.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path (Get-Location) ("camfp_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
function F($n) { Join-Path $Out $n }
function Sh($cmd, $file) { & $Adb shell $cmd 2>&1 | Out-File -Append -Encoding utf8 (F $file) }
function Su($cmd, $file) { & $Adb shell "su -c '$cmd'" 2>&1 | Out-File -Append -Encoding utf8 (F $file) }
function Shot($n) { & $Adb shell "screencap -p /data/local/tmp/cap.png" 2>&1 | Out-Null; & $Adb pull /data/local/tmp/cap.png (F "$n.png") 2>&1 | Out-Null }
function Step($msg) { Write-Host ""; Read-Host ">>> $msg  [Enter when done]" | Out-Null }

Write-Host "saving to $Out"
& $Adb wait-for-device
$id = (& $Adb shell "su -c id" 2>&1) -join " "
if ($id -notmatch "uid=0") { Write-Host "root not available ($id) - approve the Magisk prompt on the phone and run again"; exit 1 }

# ---- camera ----------------------------------------------------------------------------------------------------
Sh "ls -l /sdcard/DCIM/Camera | tail -5" "camera_files_before.txt"
& $Adb logcat -G 16M 2>&1 | Out-Null
& $Adb logcat -c 2>&1 | Out-Null
$log = Start-Process -FilePath $Adb -ArgumentList "logcat -b all -v threadtime" -RedirectStandardOutput (F "logcat.txt") -NoNewWindow -PassThru
& $Adb shell "am force-stop com.sec.android.app.camera" 2>&1 | Out-Null
& $Adb shell "am start -n com.sec.android.app.camera/.Camera" 2>&1 | Out-Null
Step "Samsung Camera is opening (REAR camera, Photo mode): take ONE photo, wait 5 s"
Shot "cam_after_photo"
Step "Switch to VIDEO, record about 5 s, stop, wait 5 s"
Shot "cam_after_video"
Step "Switch to the FRONT camera, wait 3 s (leave it on screen)"
Shot "cam_front"
Sh "dumpsys SurfaceFlinger --list" "camera_front_sf.txt"
Sh "dumpsys SurfaceFlinger" "camera_front_sf.txt"
Sh "dumpsys media.camera" "camera_front_media.txt"
Sh "ls -l /sdcard/DCIM/Camera | tail -8" "camera_files_after.txt"
Sh "df -h /data /sdcard" "camera_files_after.txt"
Su "dmesg | tail -400" "dmesg_camera.txt"
& $Adb shell "am force-stop com.sec.android.app.camera" 2>&1 | Out-Null

# ---- fingerprint: live bus state while the fingerprint service starts ------------------------------------------
Write-Host "`n== fingerprint live check (automatic, ~20 s)"
# helper .sh: next to this script, else in the project tools folder (copies of the .ps1 elsewhere lack it)
$Helper = Join-Path $PSScriptRoot "fp_live.sh"
& $Adb push $Helper /data/local/tmp/fp_live.sh 2>&1 | ForEach-Object { "$_" } | Out-Host   # (adb prints progress on stderr)
& $Adb shell "su -c 'sh /data/local/tmp/fp_live.sh'" 2>&1 | Out-File -Encoding utf8 (F "fp_live_run.txt")
& $Adb pull /data/local/tmp/fp_live (F "fp_live") 2>&1 | Out-Null
Stop-Process -Id $log.Id -Force -ErrorAction SilentlyContinue
& $Adb shell "for t in data_app_crash system_app_crash SYSTEM_TOMBSTONE; do echo == `$t; dumpsys dropbox --print `$t 2>&1 | tail -200; done" 2>&1 | Out-File -Encoding utf8 (F "crashes.txt")
Write-Host "`ndone: $Out  - send me this folder"
