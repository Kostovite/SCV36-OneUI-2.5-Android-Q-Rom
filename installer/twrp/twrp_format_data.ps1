# Phone: TWRP main screen (MTP disabled). Recreates /data cleanly (erases all data / internal storage).
# Usage: powershell -ExecutionPolicy Bypass -File twrp_format_data.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$here = $PSScriptRoot
function Retry([scriptblock]$cmd, [string]$what) {
    for ($i = 1; $i -le 10; $i++) {
        & $Adb wait-for-recovery
        $out = & $cmd 2>&1
        if ($LASTEXITCODE -eq 0) { $out | Write-Host; Write-Host "ok: $what"; return $out }
        Write-Host "  retry $i ($what):"; $out | Select-Object -Last 5 | Write-Host; Start-Sleep 2
    }
    throw "failed after 10 tries: $what"
}
& $Adb kill-server
Retry { & $Adb push "$here\format_data.sh" /tmp/format_data.sh } "push format_data.sh" | Out-Null
$r = Retry { & $Adb shell "sh /tmp/format_data.sh" } "format /data"
if (-not ($r -match "FORMAT_OK")) { throw "format_data.sh did not finish" }
Write-Host "done - in TWRP choose Reboot -> System (first boot takes a few minutes)"
