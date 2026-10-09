#!/usr/bin/env bash
# Run inside WSL: dump the G9600 donor /system (system-as-root) to ~/s8rom/trees/g9600_root and report what matters.
P=$(cd "$(dirname "$0")/../.." && pwd)
W=$P/work/donor_G9600
T=~/s8rom/trees/g9600_root; mkdir -p $T
OUT=$W/inspect; mkdir -p $OUT
used() { dumpe2fs -h "$1" 2>/dev/null | awk -F: '/^Block count/{c=$2}/^Free blocks/{f=$2}/^Block size/{b=$2}END{printf "%s: fs %d MiB, used %d MiB\n", n, c*b/1048576, (c-f)*b/1048576}' n="$(basename "$1")"; }
for i in system vendor odm hidden; do used $W/$i.raw.img; done
[ -e $T/system ] || debugfs -R "rdump /system $T" $W/system.raw.img 2>/dev/null
S=$T/system
echo "dumped /system: $(du -sm $S | cut -f1) MiB"
grep -E 'ro.build.(display.id|version.(release|security_patch|oneui|sem))|ro.product.system.(model|device)|ro.csc.sales_code|ro.config.knox' $S/build.prop
du -sm $S/app/* $S/priv-app/* $S/preload/* 2>/dev/null | sort -k2 > $OUT/app_sizes.txt
echo "apps: $(wc -l < $OUT/app_sizes.txt)"
echo "== keyboard / messages / launcher / setup:"
grep -iE 'honeyboard|keyboard|messag|touchwizhome|launcher|setupwizard' $OUT/app_sizes.txt | awk '{printf "%s(%s) ", $2, $1}'; echo
echo "== boot animation:"; ls -la $S/media/*.qmg 2>/dev/null | awk '{print $5, $NF}'
echo "== China-only services (candidates to remove):"
grep -iE 'baidu|tencent|wechat|alipay|weibo|qq|chn|china|cmcc|unionpay|sogou|iflytek|mipush|huawei|meituan|tmall|taobao|jd|ctrip|hk' $OUT/app_sizes.txt | awk '{printf "%s(%s) ", $2, $1}'; echo
echo "== GMS present?"; ls $S/priv-app | grep -iE 'GmsCore|Phonesky|GoogleServicesFramework' | tr '\n' ' '; echo
echo "== odm root:"; debugfs -R "ls -p /" $W/odm.raw.img 2>/dev/null | awk -F/ '$6!=""{print $6}' | tr '\n' ' '; echo
echo "== odm omc CSCs:"; debugfs -R "ls -p /omc" $W/odm.raw.img 2>/dev/null | awk -F/ '$6!=""{print $6}' | tr '\n' ' '; echo
echo "== hidden root:"; debugfs -R "ls -p /" $W/hidden.raw.img 2>/dev/null | awk -F/ '$6!=""{print $6}' | tr '\n' ' '; echo
