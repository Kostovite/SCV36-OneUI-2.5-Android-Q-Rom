# DEBUG ONLY: enable adb (no RSA prompt) from early boot on the port, so logs can be read while the screen is black.
# Phone: TWRP main screen. PC, from this folder:
#   powershell -ExecutionPolicy Bypass -File twrp_debug_adb.ps1          (enable)
#   powershell -ExecutionPolicy Bypass -File twrp_debug_adb.ps1 -Undo    (restore original)
param([string]$Adb = "adb", [switch]$Undo)
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
Retry { & $Adb push "$here\debug_adb.sh" /tmp/debug_adb.sh } "push debug_adb.sh" | Out-Null
$arg = ""; if ($Undo) { $arg = "--undo" }
$r = Retry { & $Adb shell "sh /tmp/debug_adb.sh $arg" } "apply"
if (-not ($r -match "DEBUG_ADB_OK")) { throw "debug_adb.sh did not finish" }
Write-Host "done - in TWRP choose Reboot -> System, wait ~3 min after the screen goes black, then run tools\capture_live.ps1"
