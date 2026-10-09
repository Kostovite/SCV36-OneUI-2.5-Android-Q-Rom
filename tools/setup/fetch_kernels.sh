#!/usr/bin/env bash
# Clone kernel trees into the WSL ext4 home (kernel sources need a case-sensitive filesystem).
set -e
mkdir -p ~/s8rom/kernel && cd ~/s8rom/kernel
clone() { [ -d "$2/.git" ] && echo "have $2" || git clone --depth 30 --single-branch -b "$3" "$1" "$2"; }
# Samsung Tab S4 (SM-T830, MSM8998) Android 10 drop T830XXU5CVG2 on top of CAF LA.UM.8.4.r1
clone https://github.com/linckandrea/android_kernel_samsung_msm8998.git t830_q Q-r1
du -sh ~/s8rom/kernel/*
