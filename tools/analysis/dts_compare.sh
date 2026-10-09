#!/usr/bin/env bash
# Runs ON the build server. Clone the Canadian Snapdragon S8 Pie kernel (same 4.4.153 base), build its dreamq DTBs,
# and diff its rev12 tree against the stock SCV36 (JPN) rev12 DTB to see what is Japan-specific.
set -e
R=~/s8rom
cd $R/kernel
[ -d dreamqltecan/.git ] || git clone -q --depth 1 https://github.com/android-source-codes/dreamqltecan_kernel.git dreamqltecan
export PATH=$R/bin:$PATH ARCH=arm64 CROSS_COMPILE=$R/toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-
O=$R/kernel/out_can
cd dreamqltecan
make -s O=$O dreamqlte_can_open_defconfig >/dev/null 2>&1
make -s O=$O CC="${CROSS_COMPILE}gcc" HOSTCFLAGS=-fcommon -j"$(nproc)" dtbs 2>&1 | grep -E 'rror' | head -5 || true
ls $O/arch/arm64/boot/dts/samsung/ | grep dreamq | tr '\n' ' '; echo
D=$R/work/dts; mkdir -p $D
dtc -q -I dtb -O dts -s -o $D/can_r12.dts $O/arch/arm64/boot/dts/samsung/msm8998-sec-dreamq-r12.dtb
dtc -q -I dtb -O dts -s -o $D/jpn_r12.dts $R/work/stock_dtb0.dtb
grep -m1 'model =' $D/can_r12.dts $D/jpn_r12.dts
# compare node paths only (phandle numbers differ between builds)
nodes() { awk '/{$/{gsub(/^[ \t]+/,""); sub(/ {$/,""); depth++; path[depth]=$0; p=""; for(i=1;i<=depth;i++) p=p"/"path[i]; print p} /};$/{depth--}' "$1" | sort -u; }
nodes $D/can_r12.dts > $D/can_nodes.txt; nodes $D/jpn_r12.dts > $D/jpn_nodes.txt
echo "== nodes only in JPN (stock SCV36): $(comm -13 $D/can_nodes.txt $D/jpn_nodes.txt | wc -l)"
comm -13 $D/can_nodes.txt $D/jpn_nodes.txt | sed 's#^//##' | head -40
echo "== nodes only in CAN: $(comm -23 $D/can_nodes.txt $D/jpn_nodes.txt | wc -l)"
comm -23 $D/can_nodes.txt $D/jpn_nodes.txt | sed 's#^//##' | head -25
