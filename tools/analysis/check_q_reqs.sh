#!/usr/bin/env bash
# WSL: Android 10 requirements the S8 port must satisfy (APEX type, kernel features, encryption, selinux).
P=$(cd "$(dirname "$0")/../.." && pwd)
S=~/s8rom/trees/g9600_root/system
C=$P/out/kernel/dream_q.config
echo "== /system/apex entries:"; ls -la $S/apex | head -12
echo "== ro.apex.updatable:"; grep -h 'apex.updatable' $S/build.prop ~/s8rom/trees/g9600_root/system/etc/prop.default 2>/dev/null
echo "== kernel features (our build):"
for k in BLK_DEV_LOOP DM_VERITY ANDROID_BINDER_IPC SDCARD_FS QUOTA EXT4_FS_ENCRYPTION F2FS_FS DM_CRYPT CGROUP_SCHED PSI \
         BPF_SYSCALL CGROUP_BPF NETFILTER_XT_MATCH_BPF IKCONFIG SECURITY_SELINUX STATIC_USERMODEHELPER; do
  printf '  %-26s %s\n' $k "$(grep -E "^(# )?CONFIG_$k[= ]" $C | head -1)"
done
echo "== G9600 selinux: precompiled policy needs matching vendor; plat_sepolicy_vers.txt on S8 vendor:"
debugfs -R "cat /vendor/etc/selinux/plat_sepolicy_vers.txt" $P/work/stock_CZE1/system.raw.img 2>/dev/null
debugfs -R "ls -p /vendor/etc/selinux" $P/work/stock_CZE1/system.raw.img 2>/dev/null | awk -F/ '$6!=""{print $6}' | tr '\n' ' '; echo
