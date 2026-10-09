#!/usr/bin/env bash
# WSL: NFC HAL interfaces + data files on S8 Pie vendor vs T835 Q vendor.
S8=~/s8rom/trees/s8_vendor/vendor; TV=~/s8rom/trees/t835_vendor
echo "== S8 manifest NFC/SE entries:"; grep -B1 -A3 -iE '<name>.*(nfc|secure_element)' $S8/etc/vintf/manifest.xml | grep -E '<name>|<version>' | paste - -
echo "== S8 init rc for nfc service:"; cat $S8/etc/init/sec.android.hardware.nfc@1.1-service.rc
echo "== S8 NFC data files:"; (cd $S8 && find . -iname '*nfc*' -o -iname '*sec_s3n*' | grep -v '\.so$' | sort)
echo "== T835 NFC data files:"; (cd $TV && find . -iname '*nfc*' | grep -v '\.so$' | sort)
echo "== T835 sepolicy NFC types present?"; grep -oE '\((type|typeattribute) [a-z_]*nfc[a-z_]*' $TV/etc/selinux/vendor_sepolicy.cil $TV/etc/selinux/plat_pub_versioned.cil | sort -u | head
echo "== T835 fingerprint types present?"; grep -oE '\((type|typeattribute) [a-z_]*(fingerprint|hal_fp)[a-z_]*' $TV/etc/selinux/*.cil | sort -u | head
