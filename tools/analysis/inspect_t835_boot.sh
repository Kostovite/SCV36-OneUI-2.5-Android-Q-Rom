#!/usr/bin/env bash
# WSL: T835 (msm8998 Android 10) boot image: cmdline, ramdisk type (2SI?), DT fstab.
P=$(cd "$(dirname "$0")/../.." && pwd); MB=~/s8rom/twrp/magiskboot
W=~/s8rom/port/t835_boot; rm -rf $W; mkdir -p $W/rd && cd $W
$MB unpack -h $P/work/donor_T835/boot.img >/dev/null 2>&1
grep -E '^(cmdline|os_version|name)=' header
cd rd && $MB cpio ../ramdisk.cpio extract >/dev/null 2>&1; echo "== ramdisk:"; ls -A | tr '\n' ' '; echo
cd ..; echo "== T835 DT fstab:"
for d in kernel_dtb dtb; do [ -f $d ] && { dtc -I dtb -O dts $d 2>/dev/null | awk '/fstab \{/,/^\t\t\};/' | grep -E 'dev =|mnt_point|fsmgr_flags|status' | head -8; break; }; done
echo "== G9600 ramdisk:"; ls -A ~/s8rom/port/g9600_boot/rd | tr '\n' ' '; echo
