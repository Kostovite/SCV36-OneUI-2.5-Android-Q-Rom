#!/usr/bin/env bash
# AOSP GCC 4.9 aarch64 toolchain (the compiler Samsung used for the stock S8/Tab S4 kernels).
set -e
mkdir -p ~/s8rom/toolchains && cd ~/s8rom/toolchains
[ -d aarch64-linux-android-4.9/.git ] || git clone --depth 1 -b lineage-17.1 \
  https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git aarch64-linux-android-4.9
aarch64-linux-android-4.9/bin/aarch64-linux-android-gcc --version | head -1
