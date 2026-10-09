# Back up the irreplaceable partitions (IMEI/modem/calibration) + stock boot/recovery while the phone is in TWRP.
# TWRP's adb shell is already root, so plain dd works. Read-only on the phone except temp files in /tmp (RAM).
# Usage: powershell -ExecutionPolicy Bypass -File tools\twrp_backup.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")

$Out = Join-Path $PSScriptRoot ("..\..\backup\" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
& $Adb wait-for-recovery
$parts = "efs","sec_efs","persist","persistent","modemst1","modemst2","fsg","fsc","param","steady","keyrefuge","keystore","devinfo","boot","recovery","misc","hidden"
foreach ($p in $parts) {
    $dev = "/dev/block/bootdevice/by-name/$p"
    $exists = (& $Adb shell "test -e $dev && echo yes") -join ""
    if ($exists.Trim() -ne "yes") { continue }
    & $Adb shell "dd if=$dev of=/tmp/$p.img bs=4096" 2>&1 | Out-Null
    & $Adb pull "/tmp/$p.img" (Join-Path $Out "$p.img") 2>&1 | Out-Null
    & $Adb shell "rm /tmp/$p.img" | Out-Null
    $f = Join-Path $Out "$p.img"
    if (Test-Path $f) { "{0,-12} {1,12:N0} bytes" -f $p, (Get-Item $f).Length | Write-Host }
    else { Write-Host "$p FAILED" -ForegroundColor Red }
}
Get-ChildItem $Out -Filter *.img | Get-FileHash -Algorithm SHA256 | ForEach-Object { "{0}  {1}" -f $_.Hash, (Split-Path $_.Path -Leaf) } |
    Out-File -Encoding utf8 (Join-Path $Out "SHA256SUMS.txt")
Write-Host "Done -> $((Resolve-Path $Out).Path)"
Write-Host "Copy this folder somewhere off the PC too (USB stick / cloud). efs/modemst*/fsg/persist hold your IMEI and RF calibration." -ForegroundColor Yellow
