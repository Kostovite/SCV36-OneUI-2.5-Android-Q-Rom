# Record the full log from the start of boot (needs the debug adb props). Start it while the phone is in TWRP or
# rebooting; it waits for adb, then logs for -Seconds (default 240) while you test things on the phone.
# Usage: powershell -ExecutionPolicy Bypass -File capture_boot.ps1 [-Seconds 240] [-Adb C:\path\adb.exe]
param([int]$Seconds = 240, [string]$Adb = "adb")
$Out = Join-Path (Get-Location) ("boot_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
Write-Host "saving to $Out"
Write-Host "waiting for Android (adb device) - choose Reboot -> System in TWRP now..."
& $Adb wait-for-device
& $Adb logcat -G 16M 2>&1 | Out-Null   # bigger ring buffers: the end-of-run dump below must still hold the boot
Write-Host "adb up - logging for $Seconds s. Meanwhile: open Camera (rear, front, video), torch tile, add a fingerprint,"
Write-Host "  register iris, Quick Share receive, connect Wi-Fi + wait for the IPsec popup, dial *#06#."
# boot 17: the live stream died after ~1 min (adb reconnect) while the test ran later -> restart it whenever it
# drops (one file per stream), and dump every buffer again at the end
$deadline = (Get-Date).AddSeconds($Seconds); $n = 0
while ((Get-Date) -lt $deadline) {
    $log = Join-Path $Out ("logcat_boot" + $(if ($n) { "_$n" } else { "" }) + ".txt")
    $p = Start-Process -FilePath $Adb -ArgumentList "logcat -b all -v threadtime" -RedirectStandardOutput $log -NoNewWindow -PassThru
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep 2 }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    elseif ((Get-Date) -lt $deadline) { Write-Host "  logcat stream dropped - reconnecting"; & $Adb wait-for-device; $n++ }
}
Write-Host "  logcat_end.txt (all buffers)"
& $Adb logcat -d -b all -v threadtime 2>&1 | Out-File -Encoding utf8 (Join-Path $Out "logcat_end.txt")
$jobs = [ordered]@{
    "dmesg.txt"       = "dmesg"
    "sensors.txt"     = "dumpsys sensorservice"
    "window.txt"      = "dumpsys window displays; dumpsys window | grep -i -E 'rotation|orientation'"
    "camera.txt"      = "dumpsys media.camera; lshal -i 2>&1 | grep -i camera"
    "getprop.txt"     = "getprop"
    # every "X keeps stopping" (Java + native, with stacks) and tombstone summaries since boot
    "crashes.txt"     = "for t in system_app_crash data_app_crash system_app_native_crash data_app_native_crash SYSTEM_TOMBSTONE system_server_crash; do echo == `$t; dumpsys dropbox --print `$t 2>&1 | head -400; done"
    "wifi_p2p.txt"    = "dumpsys wifip2p 2>&1 | head -150; ip addr show p2p0 2>&1; ip link 2>&1 | grep -E 'p2p|wlan'"
    "iris.txt"        = "lshal -i 2>&1 | grep -i -E 'iris|bauth|fingerprint'; ps -A | grep -i -E 'iris|faced|fingerprint|camera'; dumpsys iris 2>&1 | head -60"
    "checks.txt"      = "echo == kernel; cat /proc/version; echo == wm; wm size; wm density; settings get global display_size_forced; echo == nfc; ls -la /sys/class/nfc/ 2>&1; cat /sys/class/nfc/nfc_support 2>&1; ls -lZ /dev/sec-nfc 2>&1; echo == bt; ls -lZL /sys/class/rfkill/*/state /sys/class/rfkill/*/type 2>&1; cat /sys/class/rfkill/*/name 2>&1; ls -lZ /dev/ttyHS* 2>&1; getprop ro.bt.bdaddr_path; echo == files; ls -la /vendor/etc/init/ | grep -E 's8|bluetooth|sensors'; grep -E 'rfkill|ttyHS0' /vendor/ueventd.rc; echo == calls; dumpsys telephony.registry | grep -i -E 'mCallState|mServiceState|VoiceRegState|mVoLte' | head; getprop | grep -i -E 'ims|volte' | head -20; echo == csc; getprop ro.csc.sales_code; ls -lZ /odm/etc/omc/KDI/conf/ 2>&1; echo == fingerprint; ls -lZ /dev/esfp0 2>&1; ls /sys/class/fingerprint/fingerprint/ 2>&1; cat /sys/class/fingerprint/fingerprint/name /sys/class/fingerprint/fingerprint/vendor 2>&1; lshal -i 2>&1 | grep -i -E 'fingerprint|proca'; echo == camera fw; ls -l /system/etc/firmware 2>&1"
}
foreach ($k in $jobs.Keys) { Write-Host "  $k"; & $Adb shell $jobs[$k] 2>&1 | Out-File -Encoding utf8 (Join-Path $Out $k) }
# full kernel log (user build: shell may not read dmesg; dumpstate can) - boot cmdline has log_buf_len=4M
Write-Host "  bugreport.zip (takes 1-3 min)"
& $Adb bugreport (Join-Path $Out "bugreport.zip") 2>&1 | Select-Object -Last 2 | Write-Host
Get-ChildItem $Out | ForEach-Object { "{0,-20} {1,12:N0} bytes" -f $_.Name, $_.Length }
Write-Host "Saved -> $Out"
