#!/usr/bin/env bash
# Inspect the cloned Tab S4 Q kernel: build script, toolchain, defconfigs, S8 (dream) board support.
K=~/s8rom/kernel/t830_q
cd "$K" || exit 1
echo "== HEAD"; git log --oneline -3
echo "== top-level"; ls | tr '\n' ' '; echo
echo "== build scripts"; ls *.sh build* 2>/dev/null; for f in *.sh; do echo "--- $f"; head -40 "$f"; done
echo "== toolchain dir"; ls toolchain 2>/dev/null; find toolchain -maxdepth 3 -name '*gcc' 2>/dev/null | head
echo "== defconfigs (samsung)"; ls arch/arm64/configs | grep -iE 'gts4|dream|great|msm8998|star|sec' | tr '\n' ' '; echo
echo "== DT dirs"; ls arch/arm64/boot/dts/qcom 2>/dev/null | grep -iE 'dream|gts4|great|8998-sec|samsung' | head -40 | tr '\n' ' '; echo
ls arch/arm64/boot/dts/samsung 2>/dev/null | head -40 | tr '\n' ' '; echo
echo "== Makefile version"; head -5 Makefile
