#!/usr/bin/env bash
# Runs ON the build server: where the G9500 PP DTS defines fingerprint nodes, and which dreamq JPN files include them.
cd ~/s8rom/kernel/g9500_pp/arch/arm64/boot/dts || exit 1
echo "files with fingerprint nodes:"; grep -rlE 'etspi|vfsspi|fps,common|fps-spi' . | head -20
for f in $(grep -rlE 'etspi,et5xx|vfsspi,vfs8xxx|fps,common' . | head -6); do
  echo "## $f"; grep -n -B2 -A16 -E 'etspi,et5xx|vfsspi,vfs8xxx|fps,common' "$f" | head -22
done
echo "== include chain of jpn-r12:"
grep -n '#include' samsung/msm8998-sec-dreamq-jpn-r12.dts
