#!/usr/bin/env bash
# Runs ON the build server: fingerprint node in G9500-source JPN r12 DTS vs stock (CZE1) JPN r12 DTB.
cd ~/s8rom/kernel/g9500_pp
echo "== G9500 source JPN r12 fingerprint node:"
grep -rn -A12 -E 'vfsspi|fps-spi|fps,common|etspi' arch/arm64/boot/dts/samsung/msm8998-sec-dreamq-jpn-r12.dts \
  $(grep -oE '#include "[^"]+"' arch/arm64/boot/dts/samsung/msm8998-sec-dreamq-jpn-r12.dts | tr -d '"' | awk '{print "arch/arm64/boot/dts/samsung/"$2}') 2>/dev/null | head -30
echo "== stock CZE1 JPN r12 fingerprint node:"
grep -n -A16 'fps-spi@0 {' ~/s8rom/work/dts/jpn_r12.dts | head -24
