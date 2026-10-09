# Fingerprint reference capture on the STOCK SCV36 Pie ROM (no root needed).
# Usage (phone on stock Pie, USB debugging on, fingerprint NOT yet registered):
#   1. Reboot the phone, unlock, wait ~1 min, then run:  .\capture_stock_fp.ps1
#   2. When the script says so, register one fingerprint in Settings (touch until it finishes), then press Enter.
# Output: .stockfp_<date> - send the whole folder. Does not read IMEI/EFS: only fingerprint-related lines are kept;
# the full logcats and the bugreport zip (both can contain the IMEI) are deleted after filtering.
$ErrorActionPreference = 'Continue'
$out = "stockfp_" + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Force $out | Out-Null

function Sh($cmd, $file) { adb shell $cmd 2>&1 | Out-File -Encoding utf8 (Join-Path $out $file) }

Sh 'getprop ro.build.fingerprint; getprop ro.boot.revision; getprop ro.boot.bootloader' 'props.txt'
Sh 'ls -l /dev/fps /dev/esfp0 /dev/vfsspi /sys/class/fingerprint/fingerprint/ 2>&1' 'devnodes.txt'
Sh 'for f in type_check name vendor adm position intcnt resetcnt; do echo "$f: $(cat /sys/class/fingerprint/fingerprint/$f 2>&1)"; done' 'sysfs_before.txt'
# boot-time HAL bring-up (sensor detection happens at boot)
adb logcat -b all -d 2>&1 | Out-File -Encoding utf8 (Join-Path $out 'logcat_boot.txt')
adb logcat -b all -c 2>&1 | Out-Null

Write-Host ""
Write-Host "Now register ONE fingerprint in Settings > Biometrics and security > Fingerprints."
Write-Host "Finish (or cancel after ~10 touches), then come back here and press Enter." -ForegroundColor Yellow
Read-Host | Out-Null

adb logcat -b all -d 2>&1 | Out-File -Encoding utf8 (Join-Path $out 'logcat_enroll.txt')
Sh 'for f in type_check name vendor adm position intcnt resetcnt; do echo "$f: $(cat /sys/class/fingerprint/fingerprint/$f 2>&1)"; done' 'sysfs_after.txt'
Sh 'dumpsys fingerprint' 'dumpsys_fingerprint.txt'

Write-Host "Taking bugreport (2-4 min, includes the kernel log)..."
adb bugreport (Join-Path $out 'bugreport.zip') 2>&1 | Out-Null
$zip = Join-Path $out 'bugreport.zip'
if (Test-Path $zip) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $zip))
  $e = $z.Entries | Where-Object { $_.Name -like 'bugreport-*.txt' } | Select-Object -First 1
  if ($e) {
    $r = New-Object System.IO.StreamReader($e.Open())
    $lines = New-Object System.Collections.Generic.List[string]
    while (($l = $r.ReadLine()) -ne $null) {
      if ($l -match 'fps|etspi|esfp|vfsspi|spi12|c1ba000|qseecom|QSEECOM|dualfp|bauth|FPLOG|fingerprint|blsp') { $lines.Add($l) }
    }
    $r.Close()
    $lines | Out-File -Encoding utf8 (Join-Path $out 'bugreport_fp_lines.txt')
  }
  $z.Dispose()
  Remove-Item -Force $zip
}
# keep only fingerprint-related logcat lines in a small file too
Get-Content (Join-Path $out 'logcat_boot.txt'), (Join-Path $out 'logcat_enroll.txt') |
  Select-String -Pattern 'bauth|FPLOG|fingerprint|etspi|fps_|common_prepare|SNSR|cgst|sfst|QSEECOM' |
  ForEach-Object { $_.Line } | Out-File -Encoding utf8 (Join-Path $out 'fp_logcat.txt')
Remove-Item -Force (Join-Path $out 'logcat_boot.txt'), (Join-Path $out 'logcat_enroll.txt')
Write-Host "Done: $out  (send the folder)" -ForegroundColor Green
