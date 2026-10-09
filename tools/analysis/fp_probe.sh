#!/usr/bin/env bash
# Runs ON the build server: locate the fingerprint driver for the JPN 'fps,common' node in both trees.
cd ~/s8rom/kernel
for t in t830_q dreamqltecan; do
  echo "== $t"
  grep -rIl --include='*.c' 'fps,common' $t/drivers | head
  grep -rIn --include='Kconfig*' -E 'config (SENSORS_VFS8XXX\w*|SENSORS_FINGERPRINT\w*|SENSORS_ET5\w*|FPS\w*)' $t/drivers | head
  grep -nE 'VFS8XXX|FINGERPRINT|fps' $t/drivers/fingerprint/Makefile 2>/dev/null | head
done
echo "== stock SCV36 config fingerprint symbols"
grep -iE 'FINGERPRINT|VFS|FPS|ET5' ~/s8rom/work/stock_kernel.config
