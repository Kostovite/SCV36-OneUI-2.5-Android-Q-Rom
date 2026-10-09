# Diagnose why /system won't mount in TWRP. Read-only (e2fsck -n never writes).
# Usage: powershell -ExecutionPolicy Bypass -File tools\twrp_sysdiag.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path $PSScriptRoot ("..\..\debug\sysdiag_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
& $Adb wait-for-recovery
& $Adb pull /tmp/recovery.log (Join-Path $Out "recovery.log") | Out-Null
& $Adb shell dmesg | Out-File -Encoding utf8 (Join-Path $Out "dmesg.txt")
$sh = @'
B=/dev/block/bootdevice/by-name/system
echo "== mounts"; grep -E 'system|sda19|dm-' /proc/mounts
echo "== superblock"; dumpe2fs -h $B 2>&1 | grep -E 'volume name|features|state|Block count|Free blocks|Last mount|errors|Filesystem created'
echo "== mount attempt"; mkdir -p /s_chk; mount -t ext4 -o ro $B /s_chk; echo "rc=$?"; ls /s_chk | head; umount /s_chk 2>/dev/null
echo "== e2fsck -n (read-only check)"; e2fsck -n $B 2>&1 | head -40
echo "== first 64KB non-zero?"; dd if=$B bs=65536 count=1 2>/dev/null | od -An -tx1 | grep -cv ' 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00'
'@
$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, $sh.Replace("`r`n", "`n"))
& $Adb push $tmp /tmp/sysdiag.sh | Out-Null
Remove-Item $tmp
& $Adb shell sh /tmp/sysdiag.sh 2>&1 | Tee-Object -FilePath (Join-Path $Out "system_check.txt")
Write-Host "Saved -> $((Resolve-Path $Out).Path)"
