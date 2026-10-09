#!/usr/bin/env bash
# WSL: does the G9600 Q vendor run the same Samsung NFC / fingerprint HALs, and what SELinux does it give them?
P=$(cd "$(dirname "$0")/../.." && pwd)
GV=~/s8rom/trees/g9600_vendor
[ -d $GV/etc ] || { mkdir -p $GV && debugfs -R "rdump / $GV" $P/work/donor_G9600/vendor.raw.img 2>/dev/null; }
echo "== G9600 HAL binaries for nfc / fingerprint:"; ls $GV/bin/hw | grep -iE 'nfc|finger|biometric'
echo "== G9600 file_contexts for them:"; grep -iE 'nfc|finger|biometric|sec-nfc|esfp|vfsspi|etspi' $GV/etc/selinux/vendor_file_contexts
echo "== G9600 hwservice_contexts:"; grep -iE 'nfc|finger|biometric' $GV/etc/selinux/vendor_hwservice_contexts
echo "== G9600 domain types:"; grep -oE '\(type (hal_nfc|hal_fingerprint|hal_secure_element)[a-z_]*\)' $GV/etc/selinux/vendor_sepolicy.cil | sort -u
echo "== rule count per domain:"; for d in hal_nfc_default hal_fingerprint_default; do echo "  $d: $(grep -c "$d" $GV/etc/selinux/vendor_sepolicy.cil)"; done
