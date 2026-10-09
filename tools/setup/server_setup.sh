#!/usr/bin/env bash
# Runs ON the build server (no sudo needed): python shim, kernel tree, GCC 4.9 toolchain.
set -e
R=~/s8rom
mkdir -p $R/bin $R/kernel $R/toolchains $R/work
command -v python >/dev/null || ln -sf "$(command -v python3)" $R/bin/python
cd $R/kernel
[ -d t830_q/.git ] || git clone -q --depth 30 --single-branch -b Q-r1 \
  https://github.com/linckandrea/android_kernel_samsung_msm8998.git t830_q
cd $R/toolchains
[ -d aarch64-linux-android-4.9/.git ] || git clone -q --depth 1 -b lineage-17.1 \
  https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git aarch64-linux-android-4.9
# AOSP gcc wrappers are '#!/usr/bin/python' scripts; host has no /usr/bin/python and no sudo
for f in aarch64-linux-android-4.9/bin/*; do
  head -c 20 "$f" 2>/dev/null | grep -q '^#!/usr/bin/python' && sed -i '1s|.*|#!/usr/bin/env python3|' "$f"
done
aarch64-linux-android-4.9/bin/aarch64-linux-android-gcc --version | head -1
du -sh $R/kernel/t830_q
