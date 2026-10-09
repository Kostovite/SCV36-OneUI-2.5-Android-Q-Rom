#!/usr/bin/env bash
# WSL, user-run: one-shot fingerprint A/B test on the stock SCV36 kernel (DEFEX/root restriction set to allow, built by
# tools/kernel/make_stock_nodefex_test.sh). Puts out/kernel/test_stockkernel_nodefex.img in the RECOVERY partition (checksum
# verified), clears the cached fingerprint "Fail", boots it once with `adb reboot recovery`, waits for Android and
# saves the fingerprint lines (plain logcat - no root on the stock kernel) to debug/fp_stockkernel/.
# Any later reboot boots the boot partition = our kernel. Afterwards restore TWRP to recovery.
# Needs the phone (adb, or PHONE_PC in config/local.env) running our kernel with Magisk root.
set -e
. "$(dirname "$0")/../lib/env.sh"; P=$S8PORT
O=$P/debug/fp_stockkernel; mkdir -p $O
echo "== current kernel: $(ph 'shell uname -v' | tr -d '\r')"
phpush $P/out/kernel/test_stockkernel_nodefex.img /data/local/tmp/test_nodefex.img
cat > /tmp/recw.sh <<'EOF'
R=/dev/block/bootdevice/by-name/recovery; N=/data/local/tmp/test_nodefex.img
rm -f /data/vendor/biometrics/type/type_check.dat /data/vendor/biometrics/meta/calib.dat
dd if=$N of=$R bs=4M 2>/dev/null; sync
SZ=$(stat -c %s $N); H1=$(sha1sum $N | cut -d' ' -f1); H2=$(head -c $SZ $R | sha1sum | cut -d' ' -f1)
[ "$H1" = "$H2" ] && echo RECOVERY_SLOT_TEST_OK || echo WRITE_MISMATCH
EOF
phpush /tmp/recw.sh /data/local/tmp/recw.sh
R=$(ph 'shell su -c "sh /data/local/tmp/recw.sh"' | tr -d '\r'); echo "== $R"
[ "$R" = RECOVERY_SLOT_TEST_OK ] || { echo "write failed - not rebooting"; exit 1; }
echo "== booting the stock kernel once"; ph 'reboot recovery'; sleep 30
for i in $(seq 1 40); do
  bc=$(ph 'shell getprop sys.boot_completed' 2>/dev/null | tr -d '\r')
  [ "$bc" = 1 ] && { echo "boot_completed after ~$((30+i*10))s"; break; }; sleep 10
done
K=$(ph 'shell uname -a' | tr -d '\r'); echo "== running: $K" | tee $O/kernel.txt
sleep 30   # let the fingerprint HAL probe
ph 'shell logcat -d -b all' | grep -aE 'bauth|FPLOG|fingerprint@|out of order|cgst|common_prepare|SNSR|sensor' > $O/fp_logcat.txt || true
ph 'shell "cat /data/vendor/biometrics/type/type_check.dat; ls -l /dev/fps /dev/esfp0"' > $O/state.txt 2>&1 || true
echo "== result lines:"; grep -aE 'out of order|common_prepare Fail|need to cgst|SNSR|success' $O/fp_logcat.txt | tail -8
echo "saved to $O - tell Claude it is done"
