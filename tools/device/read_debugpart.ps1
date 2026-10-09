# In TWRP: copy Samsung's 'debug' partition (reset reason + kernel log saved by the bootloader after a crash). Read-only.
# Usage: powershell -ExecutionPolicy Bypass -File tools\read_debugpart.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$Out = Join-Path $PSScriptRoot ("..\..\debug\debugpart_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
& $Adb wait-for-recovery
& $Adb shell "dd if=/dev/block/bootdevice/by-name/debug of=/tmp/debugpart.img bs=1048576" 2>&1 | Out-Null
& $Adb pull /tmp/debugpart.img (Join-Path $Out "debugpart.img") | Out-Null
& $Adb shell "rm /tmp/debugpart.img"
$f = Get-Item (Join-Path $Out "debugpart.img")
"{0}: {1:N0} bytes" -f $f.Name, $f.Length | Write-Host
Write-Host "Saved -> $((Resolve-Path $Out).Path)"
