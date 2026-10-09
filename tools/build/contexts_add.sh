#!/usr/bin/env bash
# WSL: build file_contexts / hwservice_contexts additions for the transplanted S8 HALs and check every type exists
# in the compiled merged policy (config/sepolicy/precompiled_sepolicy.test).
P=$(cd "$(dirname "$0")/../.." && pwd); C=$P/config/sepolicy
S8=~/s8rom/trees/s8_vendor/vendor; TV=~/s8rom/trees/t835_vendor/etc/selinux
echo "== S8 interface names (manifest):"
grep -A6 -E '<name>vendor.samsung.hardware.(nfc|biometrics.fingerprint|radio.configsvc)</name>' $S8/etc/vintf/manifest.xml | grep -E '<name>' | paste - -
cat > $C/vendor_file_contexts.add <<'EOF'
/(vendor|system/vendor)/bin/hw/sec\.android\.hardware\.nfc@1\.1-service	u:object_r:hal_nfc_default_exec:s0
/(vendor|system/vendor)/bin/hw/vendor\.samsung\.hardware\.biometrics\.fingerprint@2\.1-service	u:object_r:hal_fingerprint_default_exec:s0
/dev/sec-nfc	u:object_r:nfc_device:s0
/dev/sec-nfc-fn	u:object_r:nfc_device:s0
/dev/esfp[0-9]	u:object_r:fp_sensor_device:s0
/data/vendor/nfc(/.*)?	u:object_r:nfc_vendor_data_file:s0
/data/vendor/biometrics(/.*)?	u:object_r:biometrics_vendor_data_file:s0
EOF
cat > $C/vendor_hwservice_contexts.add <<'EOF'
vendor.samsung.hardware.nfc::ISecNfc	u:object_r:hal_nfc_hwservice:s0
vendor.samsung.hardware.biometrics.fingerprint::ISecBiometricsFingerprint	u:object_r:hal_fingerprint_hwservice:s0
EOF
echo "== types used by the additions vs compiled policy:"
for t in $(cat $C/vendor_file_contexts.add $C/vendor_hwservice_contexts.add | grep -oE 'u:object_r:[a-z0-9_]+' | cut -d: -f3 | sort -u); do
  if seinfo -t $t $C/precompiled_sepolicy.test >/dev/null 2>&1 || grep -qE "\(type $t\)" $TV/vendor_sepolicy.cil $TV/plat_pub_versioned.cil ~/s8rom/trees/g9600_root/system/etc/selinux/plat_sepolicy.cil $C/s8_phone_hals.cil; then
    echo "  ok      $t"; else echo "  MISSING $t"; fi
done
echo "== already labelled by T835?"; grep -iE 'nfc|esfp|biometric' $TV/vendor_file_contexts | head
