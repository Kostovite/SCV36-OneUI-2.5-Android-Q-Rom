#!/usr/bin/env bash
# Runs ON the build server: Samsung FeliCa NFC driver (sec-nfc) in both trees vs stock DT node + stock config.
cd ~/s8rom/kernel
for t in g9500_pp t830_q; do
  echo "== $t"
  grep -rIln 'sec-nfc\|sec_nfc' --include='*.[ch]' $t/drivers | head -6
  grep -rIn 'compatible' $t/drivers/nfc/sec_nfc* $t/drivers/nfc/samsung/*.c 2>/dev/null | head -4
  grep -rIn 'SEC_NFC_DRIVER_NAME\|#define.*"sec-nfc"' --include='*.h' $t/drivers $t/include 2>/dev/null | head -3
  grep -nE 'config (SEC_NFC|SAMSUNG_NFC|NFC_FELICA|SEC_NFC_\w+)' -r --include='Kconfig*' $t/drivers/nfc | head -8
done
echo "== stock DT sec-nfc node:"; grep -n -A14 'sec-nfc@27 {' ~/s8rom/work/dts/jpn_r12.dts | head -18
echo "== stock config NFC/FeliCa:"; grep -iE 'NFC|FELICA' ~/s8rom/work/stock_kernel.config
