#!/usr/bin/env bash
# WSL: hardware data files that differ between S8 Pie vendor and T835 Q vendor (wifi/bt fw, audio, ueventd, sensors).
P=$(cd "$(dirname "$0")/../.." && pwd)
S8=~/s8rom/trees/s8_vendor/vendor; TV=~/s8rom/trees/t835_vendor
R=$P/work/stock_CZE1/boot.img_unpacked/ramdisk
echo "== wifi chip files:"; echo "  S8:   $(ls $S8/etc/wifi | tr '\n' ' ')"; echo "  T835: $(ls $TV/etc/wifi | tr '\n' ' ')"
echo "== bt firmware:"; echo "  S8:   $(ls $S8/firmware | grep -i bcm | tr '\n' ' ')"; echo "  T835: $(ls $TV/firmware | grep -i bcm | tr '\n' ' ')"
echo "== audio xml:"; echo "  S8:   $(ls $S8/etc | grep -iE 'mixer|audio' | tr '\n' ' ')"; echo "  T835: $(ls $TV/etc | grep -iE 'mixer|audio' | tr '\n' ' ')"
echo "== sound card name in mixer_paths:"; head -3 $S8/etc/mixer_paths*.xml 2>/dev/null | grep -i card | head -2
echo "== ueventd lines for S8 phone devices (S8 ramdisk + vendor):"
grep -hE 'sec-nfc|esfp|vfsspi|ttyHS|felica|snfc' $R/ueventd.rc $S8/ueventd.rc 2>/dev/null | sort -u
echo "== T835 vendor ueventd present:"; ls $TV/ueventd.rc 2>&1
echo "== sensors HAL:"; ls $S8/lib64/hw | grep -i sensor; ls $TV/lib64/hw | grep -i sensor
