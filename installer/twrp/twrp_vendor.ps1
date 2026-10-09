# Update only the port vendor from TWRP (no Odin / no full system flash).
# Phone: TWRP main screen, MTP disabled. PC, from this folder:
#   powershell -ExecutionPolicy Bypass -File twrp_vendor.ps1 [-Adb C:\path\adb.exe]
param([string]$Adb = "adb")
$here = $PSScriptRoot
function Retry([scriptblock]$cmd, [string]$what) {
    for ($i = 1; $i -le 10; $i++) {
        & $Adb wait-for-recovery
        $out = & $cmd 2>&1
        if ($LASTEXITCODE -eq 0) { $out | Write-Host; Write-Host "ok: $what"; return $out }
        Write-Host "  retry $i ($what):"; $out | Select-Object -Last 6 | Write-Host; Start-Sleep 2
    }
    throw "failed after 10 tries: $what"
}
& $Adb kill-server
Retry { & $Adb shell "mkdir -p /data/media/0/s8port" } "prepare"
foreach ($f in "boot.img", "vendor.tar", "vendor_labels.sh", "apply_vendor.sh", "system_add.tar") {
    Retry { & $Adb push "$here\$f" "/data/media/0/s8port/$f" } "push $f" | Out-Null
}
Retry { & $Adb shell "dd if=/data/media/0/s8port/boot.img of=/dev/block/bootdevice/by-name/boot bs=4096 && sync" } "flash boot" | Out-Null
$r = Retry { & $Adb shell "sh /data/media/0/s8port/apply_vendor.sh" } "apply vendor"
if (-not ($r -match "APPLY_OK")) { throw "apply_vendor.sh did not finish" }
Write-Host "done - in TWRP choose Reboot -> System"
