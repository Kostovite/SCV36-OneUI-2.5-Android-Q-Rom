# Collect debug info from the SCV36 over adb. Read-only: nothing on the phone is modified.
# PowerShell port of collect_debug.sh - needs only adb (platform-tools) + Samsung USB driver.
# Usage:  powershell -ExecutionPolicy Bypass -File tools\collect_debug.ps1          -> basic info, no root needed
#         powershell -ExecutionPolicy Bypass -File tools\collect_debug.ps1 -Root    -> also last_kmsg/pstore/dmesg + EFS/modem backup (needs Magisk su)
#         add -Adb C:\path\to\adb.exe if adb is not on PATH
param([switch]$Root, [string]$Adb = "adb")

if (-not (Get-Command $Adb -ErrorAction SilentlyContinue)) {
    Write-Host "adb not found. Download platform-tools, unzip, then pass -Adb <folder>\adb.exe or add it to PATH." -ForegroundColor Red
    exit 1
}

$Out = Join-Path $PSScriptRoot ("..\..\debug\" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null

# Run adb and save output as UTF-8 (PowerShell 5.1 '>' would write UTF-16)
function Save([string]$File, [string[]]$AdbArgs) {
    & $Adb @AdbArgs 2>&1 | Out-File -Encoding utf8 (Join-Path $Out $File)
}
function Su([string]$Cmd) { & $Adb shell "su -c '$Cmd'" 2>&1 }

Write-Host "Waiting for device (enable USB debugging, accept the RSA prompt)..."
& $Adb wait-for-device

Save "getprop.txt" @("shell", "getprop")

$props = "ro.product.model ro.product.device ro.product.board ro.hardware ro.board.platform " +
         "ro.boot.bootloader ro.build.PDA ro.build.version.release ro.build.version.security_patch " +
         "ro.csc.sales_code ro.boot.warranty_bit ro.warranty_bit ro.boot.flash.locked " +
         "ro.boot.verifiedbootstate ro.boot.veritymode ro.boot.em.status ro.boot.ddrinfo " +
         "sys.oem_unlock_allowed ro.oem_unlock_supported ro.frp.pst ro.security.vaultkeeper.feature " +
         "ro.config.knox ro.config.tima ro.config.rkp ro.boot.selinux ro.crypto.state ro.crypto.type " +
         "ro.treble.enabled ro.boot.hardware.revision"
$summary = @("== Key properties ==")
foreach ($p in $props.Split(" ", [StringSplitOptions]::RemoveEmptyEntries)) {
    $v = (& $Adb shell getprop $p) -join ""
    $summary += "{0,-40} {1}" -f $p, $v.Trim()
}
$summary += ""
$summary += "Binary (bit) revision = 5th char from end of ro.boot.bootloader, e.g. SCV36KDU[1]CSF1"
$summary | ForEach-Object { Write-Host $_ }
$summary | Out-File -Encoding utf8 (Join-Path $Out "summary.txt")

Save "cmdline.txt"            @("shell", "cat /proc/cmdline")
Save "kernel_version.txt"     @("shell", "cat /proc/version")
Save "partitions.txt"         @("shell", "ls -l /dev/block/bootdevice/by-name/")
Save "proc_partitions.txt"    @("shell", "cat /proc/partitions")
Save "mounts.txt"             @("shell", "mount")
Save "packages.txt"           @("shell", "pm list packages -f")
Save "packages_knox_carrier.txt" @("shell", "pm list packages | grep -iE 'knox|security|vaultkeeper|rlc|felica|kddi|au\.|docomo'")
Save "logcat_all.txt"         @("logcat", "-b", "all", "-d")
Save "logcat_crash.txt"       @("logcat", "-b", "crash", "-d")
Save "dumpsys_device_policy.txt" @("shell", "dumpsys device_policy")
Save "dumpsys_kgclient.txt"   @("shell", "dumpsys package com.samsung.android.kgclient")

if ($Root) {
    Write-Host "Root mode: pulling kernel logs and backing up EFS/modem partitions (read-only dd)."
    Su "cat /proc/last_kmsg"              | Out-File -Encoding utf8 (Join-Path $Out "last_kmsg.txt")
    Su "cat /sys/fs/pstore/* 2>/dev/null" | Out-File -Encoding utf8 (Join-Path $Out "pstore.txt")
    Su "dmesg"                            | Out-File -Encoding utf8 (Join-Path $Out "dmesg.txt")
    # filter on the PC side: nested quotes inside su -c '...' do not survive PowerShell -> adb
    Select-String -Path (Join-Path $Out "dmesg.txt") -Pattern 'defex|knox|rkp|tima|verity|avb|rmm|vaultkeeper|proca|five|selinux' |
        ForEach-Object { $_.Line } | Out-File -Encoding utf8 (Join-Path $Out "dmesg_security.txt")
    Su "ls -la /data/log /data/system/dropbox; cat /data/log/* 2>/dev/null | tail -n 3000" |
        Out-File -Encoding utf8 (Join-Path $Out "data_log.txt")

    $Bk = Join-Path $Out "partition_backup"
    New-Item -ItemType Directory -Force $Bk | Out-Null
    foreach ($part in "efs","sec_efs","persist","modemst1","modemst2","fsg","fsc","steady","param","keydata","keyrefuge") {
        $exists = (& $Adb shell "su -c 'test -e /dev/block/bootdevice/by-name/$part && echo yes'") -join ""
        if ($exists.Trim() -eq "yes") {
            & $Adb shell "su -c 'dd if=/dev/block/bootdevice/by-name/$part of=/sdcard/_bk_$part.img bs=4096'" 2>&1 | Out-Null
            & $Adb pull "/sdcard/_bk_$part.img" (Join-Path $Bk "$part.img") 2>&1 | Out-Null
            & $Adb shell "su -c 'rm /sdcard/_bk_$part.img'" 2>&1 | Out-Null
            if (Test-Path (Join-Path $Bk "$part.img")) { Write-Host "  backed up $part" }
        }
    }
    Write-Host "KEEP $Bk SAFE - it holds your IMEI/baseband data and cannot be regenerated." -ForegroundColor Yellow
}
Write-Host "Done -> $((Resolve-Path $Out).Path)"
