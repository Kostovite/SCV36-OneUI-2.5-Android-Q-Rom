# Run in TWRP right after a bootloop: is a system installed, which boot image is on the phone, and the crash logs.
# Usage: powershell -ExecutionPolicy Bypass -File tools\bootloop_diag.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path $PSScriptRoot ("..\..\debug\bootloop_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
& $Adb wait-for-recovery
$sh = @'
echo "== system installed?"
mount | grep -q ' /system ' || mount -o ro /system 2>/dev/null
if [ -f /system/build.prop ]; then grep -E 'ro.build.display.id|ro.build.version.release' /system/build.prop; ls /system/priv-app | wc -l | sed 's/^/priv-apps: /'
else echo "NO /system/build.prop -> system partition is EMPTY (flash stock CZE1 AP+CP+CSC)"; fi
echo "== boot partition kernel"
dd if=/dev/block/bootdevice/by-name/boot bs=4096 count=4096 2>/dev/null | strings 2>/dev/null | grep -m1 -oE 'SRPP[A-Z0-9]+'
echo "== pstore files"; ls -la /sys/fs/pstore/
echo "== last_kmsg size"; wc -c /proc/last_kmsg 2>/dev/null
'@
$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, $sh.Replace("`r`n", "`n"))
& $Adb push $tmp /tmp/bl.sh | Out-Null
Remove-Item $tmp
& $Adb shell sh /tmp/bl.sh 2>&1 | Tee-Object -FilePath (Join-Path $Out "summary.txt")
& $Adb pull /sys/fs/pstore (Join-Path $Out "pstore") 2>&1 | Out-Null
& $Adb shell cat /proc/last_kmsg 2>$null | Out-File -Encoding utf8 (Join-Path $Out "last_kmsg.txt")
& $Adb shell dmesg | Out-File -Encoding utf8 (Join-Path $Out "dmesg_twrp.txt")
Get-ChildItem -Recurse $Out | Where-Object { -not $_.PSIsContainer } | ForEach-Object { "{0,-40} {1,10:N0} bytes" -f $_.Name, $_.Length }
Write-Host "Saved -> $((Resolve-Path $Out).Path)"
