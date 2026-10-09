#!/usr/bin/env bash
# WSL: keymaster@3.0 on the port vendor - labels, policy, manifest, linkage
P=~/s8rom/port10/vendor; [ -d $P ] || P=~/s8rom/port/vendor
echo "port vendor: $P"; ls ~/s8rom/port10 | head
grep -n -E 'keymaster|gatekeeper|keystore' $P/etc/selinux/vendor_file_contexts
echo "== manifest"; grep -n -B2 -A3 -E 'keymaster|gatekeeper' $P/etc/vintf/manifest.xml | head -40
ls $P/etc/vintf/manifest/ 2>/dev/null
echo "== rc"; ls $P/etc/init | grep -iE 'keym|gatek|keyst'
echo "== cil domain of keymaster exec"
grep -E 'hal_keymaster|tee_exec|hal_gatekeeper' $P/etc/selinux/vendor_sepolicy.cil | head -30
echo "== libs"; ls -la $P/lib64/hw | grep -iE 'keym|keyst|gatek'; ls -la $P/lib64 | grep -iE 'keymaster|skeymaster'
