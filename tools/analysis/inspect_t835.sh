#!/usr/bin/env bash
# WSL: analyse the Tab S4 (SM-T835) Android 10 vendor as the base vendor for the S8 One UI 2 port.
P=$(cd "$(dirname "$0")/../.." && pwd)
V=$P/work/donor_T835/vendor.raw.img
S8=$P/work/stock_CZE1/system.raw.img
T=~/s8rom/trees; mkdir -p $T
rm -rf $T/t835_vendor && mkdir -p $T/t835_vendor && debugfs -R "rdump / $T/t835_vendor" $V 2>/dev/null
rm -rf $T/s8_vendor && mkdir -p $T/s8_vendor && debugfs -R "rdump /vendor $T/s8_vendor" $S8 2>/dev/null
TV=$T/t835_vendor; SV=$T/s8_vendor/vendor
echo "== sizes: T835 vendor $(du -sm $TV | cut -f1) MiB, S8 Pie vendor $(du -sm $SV | cut -f1) MiB"
echo "== T835 vendor props:"; grep -hE 'vndk|first_api|board.platform|product.vendor.device|ro.vendor.build.fingerprint|treble' $TV/build.prop $TV/default.prop 2>/dev/null
echo "== T835 selinux:"; ls $TV/etc/selinux; cat $TV/etc/selinux/plat_sepolicy_vers.txt
echo "== T835 fstab:"; ls $TV/etc | grep -i fstab; grep -v '^#' $TV/etc/fstab.qcom 2>/dev/null | grep -v '^$' | awk '{print $1, $2, $3, $5}'
echo "== RIL / radio on T835 (LTE tablet):"; ls $TV/lib64 | grep -iE 'ril|qmi' | head -10 | tr '\n' ' '; echo
echo "== HAL binaries only in S8 Pie vendor (phone-specific):"
comm -23 <(ls $SV/bin/hw 2>/dev/null | sort) <(ls $TV/bin/hw | sort) | tr '\n' ' '; echo
echo "== HAL binaries only in T835 vendor:"
comm -13 <(ls $SV/bin/hw 2>/dev/null | sort) <(ls $TV/bin/hw | sort) | tr '\n' ' '; echo
echo "== camera / fingerprint / nfc / sensor libs - S8 vs T835 counts:"
for k in camera fingerprint nfc sensor; do echo "  $k: S8 $(find $SV -iname "*$k*" | wc -l)  T835 $(find $TV -iname "*$k*" | wc -l)"; done
