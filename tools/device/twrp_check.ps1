# Verify TWRP can use the SCV36 storage. Phone must be booted into TWRP with USB connected.
# Usage: powershell -ExecutionPolicy Bypass -File tools\twrp_check.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$script = Join-Path $PSScriptRoot "twrp_check.sh"
# push with LF line endings regardless of how the file was copied around
$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, ((Get-Content -Raw $script) -replace "`r`n", "`n"))
& $Adb wait-for-recovery
& $Adb push $tmp /tmp/twrp_check.sh | Out-Null
Remove-Item $tmp
$out = Join-Path $PSScriptRoot ("..\..\debug\twrp_check_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
& $Adb shell sh /tmp/twrp_check.sh 2>&1 | Tee-Object -FilePath $out
Write-Host "Saved -> $((Resolve-Path $out).Path)"
# Samsung keeps the previous boot's kernel log in /proc/last_kmsg (not pstore) - grab the last bootloop if still in RAM
$lk = Join-Path $PSScriptRoot ("..\..\debug\last_kmsg_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")
& $Adb shell "cat /proc/last_kmsg 2>/dev/null || cat /sys/fs/pstore/console-ramoops* 2>/dev/null" | Out-File -Encoding utf8 $lk
Write-Host ("last_kmsg: {0:N0} bytes -> {1}" -f (Get-Item $lk).Length, (Resolve-Path $lk).Path)
