#!/usr/bin/env bash
# WSL: static RRO "IrisS8Overlay" for com.samsung.android.server.iris -> config/overlay/out/IrisS8Overlay.apk
# (installed as /vendor/overlay/IrisS8Overlay/IrisS8Overlay.apk). Gives the unmodified, Samsung-signed T835
# SecIrisService the S8 phone UI: layouts, drawables, animations, help videos and phone dimens/colors of the stock S8
# Pie app (tools/patches/merge_seciris_s8ui.py merges them into the decoded T835 resources).
# Why an overlay: rebuilding the app itself breaks its signature -> the package manager drops it at the next boot.
# Why the IDs are pinned: on Android 10 references inside overlay files (layout -> @id/@dimen/@drawable...) are NOT
# remapped to the target, so every resource is compiled with the T835 app's own ID (apktool's public.xml); the build
# fails if any T835 name/ID differs in the overlay.
# The framework-res ID crash of the same app is handled in FrameworkS8Overlay (build_framework_overlay.sh).
# usage: build_iris_overlay.sh <T835 system.raw.img>
set -e
P=$(cd "$(dirname "$0")/../.." && pwd); W=~/s8rom/work/iris_overlay; O=$P/config/overlay/out
SYS=$1; FWRES=~/s8rom/trees/g9600_root/system/framework/framework-res.apk
S8APK=~/s8rom/port10/s8sys/priv-app/SecIrisService/SecIrisService.apk
AT="java -jar $HOME/s8rom/tools_bin/apktool.jar"
rm -rf $W && mkdir -p $W $O
debugfs -R "dump /system/priv-app/SecIrisService/SecIrisService.apk $W/t835.apk" $SYS >/dev/null 2>&1
[ -s $W/t835.apk ] || { echo "iris overlay: T835 SecIrisService not found in $SYS"; exit 1; }
$AT if -p $W/fw -t g9600 $FWRES >/dev/null
$AT d -s -p $W/fw -o $W/merged $W/t835.apk >/dev/null      # keeps res/values/public.xml = T835 IDs
$AT d -s -p $W/fw -o $W/s8 $S8APK >/dev/null
python3 $P/tools/patches/merge_seciris_s8ui.py $W/s8 $W/merged
cat > $W/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.s8port.overlay.iris" android:versionCode="2" android:versionName="2.0">
    <overlay android:targetPackage="com.samsung.android.server.iris" android:isStatic="true" android:priority="10" />
    <application android:hasCode="false" />
</manifest>
EOF
aapt2 compile --dir $W/merged/res -o $W/res.zip
aapt2 link -o $W/unsigned.apk -I $FWRES --manifest $W/AndroidManifest.xml $W/res.zip
ids() { aapt2 dump resources "$1" | sed -nE 's/^\s+resource (0x[0-9a-f]+) ([a-z-]+\/[A-Za-z0-9_.]+).*/\2 \1/p' | sort; }
bad=$(join -a1 -e NONE -o 0,1.2,2.2 <(ids $W/t835.apk) <(ids $W/unsigned.apk) | awk '$2!=$3' | wc -l)
[ "$bad" = 0 ] || { echo "iris overlay: $bad T835 resources missing or with another ID"; exit 1; }
zipalign -f 4 $W/unsigned.apk $W/aligned.apk
KS=$P/config/overlay/s8port_overlay.jks
apksigner sign --ks $KS --ks-pass pass:s8port --key-pass pass:s8port --out $O/IrisS8Overlay.apk $W/aligned.apk
apksigner verify $O/IrisS8Overlay.apk
echo "iris overlay: $(ids $W/unsigned.apk | wc -l) resources, all T835 IDs kept -> $O/IrisS8Overlay.apk"
