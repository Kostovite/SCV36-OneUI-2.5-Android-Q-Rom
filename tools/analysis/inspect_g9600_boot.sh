#!/usr/bin/env bash
# WSL: how does the G9600 Android 10 boot? (ramdisk content, fstab, SAR/2SI) + size budget for the port.
P=$(cd "$(dirname "$0")/../.." && pwd)
W=~/s8rom/port; mkdir -p $W/g9600_boot && cd $W/g9600_boot
MB=~/s8rom/twrp/magiskboot
$MB unpack -h $P/work/donor_G9600/boot.img >/dev/null 2>&1
grep -E '^(cmdline|os_version|name)=' header
mkdir -p rd && cd rd && $MB cpio ../ramdisk.cpio extract >/dev/null 2>&1
echo "== ramdisk entries:"; find . -maxdepth 2 | sort | head -40
echo "== init type:"; file init 2>/dev/null; ls -la init system/bin/init 2>/dev/null
cd $W
echo "== G9600 system root (SAR?):"; ls ~/s8rom/trees/g9600_root | tr '\n' ' '; echo
ls -la ~/s8rom/trees/g9600_root/init ~/s8rom/trees/g9600_root/vendor ~/s8rom/trees/g9600_root/odm 2>&1 | head
echo "== G9600 vendor fstab:"
debugfs -R "cat /etc/fstab.qcom" $P/work/donor_G9600/vendor.raw.img 2>/dev/null | grep -v '^#' | grep -v '^$'
echo "== S8 DT fstab (first-stage mount) after our no-verity patch:"
dtc -I dtb -O dts $P/out/kernel/jpn_dtbs_noverity.dtb 2>/dev/null | awk '/fstab \{/,/^\t\t\};/' | head -30
echo "== size budget (MiB):"
echo "G9600 /system used: $(du -sm ~/s8rom/trees/g9600_root/system | cut -f1)"
echo "S8 Pie vendor:     483 (from earlier)"
echo "S8 system partition usable: 4399"
