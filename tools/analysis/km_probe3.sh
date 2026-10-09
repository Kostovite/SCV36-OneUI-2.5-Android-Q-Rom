#!/usr/bin/env bash
# WSL (boot 5): SELinux rules of the keymaster / gatekeeper HAL domains in the port policy (tee_device, qseecom, hwservice).
P=~/s8rom/port/vendor; SP=$P/etc/selinux/precompiled_sepolicy
which sesearch || echo "no sesearch"
for d in hal_keymaster_default hal_gatekeeper_default; do
  echo "== $d allow on devices / hwservice"
  sesearch -A -s $d $SP 2>/dev/null | grep -E 'tee_device|qseecom|hwservice|ion_device|chr_file' | head -20
done
echo "== who has tee_device"; sesearch -A -t tee_device -c chr_file $SP 2>/dev/null | head -20
echo "== S8 pie vendor policy for hal_keymaster_default"
grep -h -E '\(allow hal_keymaster_default' ~/s8rom/trees/s8_vendor/vendor/etc/selinux/*.cil | head -30
echo "== attrs of hal_keymaster_default in port"; seinfo -t hal_keymaster_default -x $SP 2>/dev/null | head -20
echo "== /dev/qseecom label"; grep -E 'qseecom' $P/etc/selinux/vendor_file_contexts ~/s8rom/trees/s8_vendor/vendor/etc/selinux/vendor_file_contexts
echo "== ldd-ish"; ls -la $P/lib64/hw | grep -iE 'keym|keyst|gatek'; ls -la $P/lib64 | grep -iE 'keymaster'
