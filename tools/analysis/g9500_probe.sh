#!/usr/bin/env bash
# Runs ON the build server: unpack SM-G9500 CHN PP kernel source and check SCV36 (jpn_kdi) support in it.
set -e
cd ~/s8rom/kernel
if [ ! -d g9500_pp/drivers ]; then
  mkdir -p g9500_pp && tar -xzf ~/s8rom/work/G9500_Kernel.tar.gz -C g9500_pp
fi
cd g9500_pp
head -4 Makefile | tr '\n' ' '; echo
echo "== fingerprint Kconfig symbols:"; grep -nE '^\s*config ' drivers/fingerprint/Kconfig
echo "== 'fps,common' users:"; grep -rIln 'fps,common' drivers arch | head
echo "== VFS8XXX_EGIS users:"; grep -rIn 'VFS8XXX_EGIS' --include='Makefile' --include='Kconfig' --include='*.c' --include='*.h' drivers | head
echo "== JPN dreamq DTS:"; find arch -path '*dts*' \( -iname '*dreamq*jpn*' -o -iname '*jpn*dreamq*' \) | sort | head -30
find arch -path '*dts*' -iname '*dreamq*' | sed 's#.*/##' | sort | tr '\n' ' ' | head -c 1500; echo
echo "== jpn_kdi defconfig vs stock SCV36 running config (enabled symbols)"
D=arch/arm64/configs/msm8998_sec_dreamqlte_jpn_kdi_defconfig
grep -E '^CONFIG_\w+=(y|m)' $D | sort -u > /tmp/kdi_def.txt
grep -E '^CONFIG_\w+=(y|m)' ~/s8rom/work/stock_kernel.config | sort -u > /tmp/stock_run.txt
echo "in defconfig but not stock: $(comm -23 /tmp/kdi_def.txt /tmp/stock_run.txt | wc -l)"; comm -23 /tmp/kdi_def.txt /tmp/stock_run.txt | head -15
echo "defconfig fingerprint/isdbt/nfc lines:"; grep -iE 'FINGERPRINT|VFS|ISDB|MMTUNER|NFC|FELICA' $D
