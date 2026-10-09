#!/usr/bin/env bash
# Build server (~/fxr): Firefox Reality for Gear VR on the SCV36 port.
#   ~/fxr/FirefoxReality          MozillaReality/FirefoxReality (final tree, + vrb submodule)
#   ~/fxr/ovr_sdk_mobile          lovr-org/ovr_sdk_mobile mirror (VrApi headers, 1.32 = commit f88e937)
#   ~/fxr/libvrapi_1.1.26_arm64.so  VrApi 1.1.26 loader taken from FirefoxReality 7.1's apk
#   ~/fxr/toolchain/{jdk11,sdk}   JDK 11 (AGP 4.2 / Gradle 6.7.1), SDK 30, build-tools 30.0.3, NDK 21.4.7075529
# usage: build_fxr_gearvr.sh [geckoview version | major, default 115]  -> ~/fxr/out/FirefoxReality-gearvr-<gv>.apk
#   GeckoView 95 needs the patch without its GV115 API block; the toolchain bump (Kotlin 1.8.22) is needed >= ~105
set -eo pipefail
GV=${1:-115}
# a bare major version -> newest release build of that major on maven.mozilla.org
if [[ $GV =~ ^[0-9]+$ ]]; then
  GV=$(curl -s https://maven.mozilla.org/maven2/org/mozilla/geckoview/geckoview-arm64-v8a/maven-metadata.xml \
       | grep -oE "<version>$GV\.[^<]+" | sed 's/<version>//' | tail -1)
  [ -n "$GV" ] || { echo "geckoview $1 not found"; exit 1; }
fi
echo "GeckoView $GV"
F=~/fxr; R=$F/FirefoxReality; T=$F/toolchain
export JAVA_HOME=$T/jdk11 ANDROID_HOME=$T/sdk ANDROID_SDK_ROOT=$T/sdk PATH=$T/jdk11/bin:$PATH

# third_party/ovr_mobile: 1.32 headers with the requested version pinned to 1.1.26 + the 1.1.26 loader
O=$R/third_party/ovr_mobile; rm -rf $O; mkdir -p $O/VrApi/Libs/Android/arm64-v8a/Release
git -C $F/ovr_sdk_mobile archive f88e937 VrApi/Include | tar -x -C $O
sed -i -E 's/(#define VRAPI_MINOR_VERSION )[0-9]+/\126/' $O/VrApi/Include/VrApi_Version.h
cp $F/libvrapi_1.1.26_arm64.so $O/VrApi/Libs/Android/arm64-v8a/Release/libvrapi.so

mkdir -p $R/libs/openwnn && cp $F/wolvic/libs/openwnn/*.aar $R/libs/openwnn/
python3 $F/patch_fxr_gearvr.py $R
cd $R
# GeckoView: release channel, pinned version (the nightly the tree names is gone from maven)
sed -i -E "s/^(versions.gecko_view_release = )\".*\"/\1\"$GV\"/" versions.gradle
sed -i -E 's/(def branch = )"[a-z]+"/\1"release"/' app/build.gradle
printf 'sdk.dir=%s\nndk.dir=%s/ndk/21.4.7075529\n' $ANDROID_HOME $ANDROID_HOME > local.properties
grep -q 'org.gradle.workers.max' gradle.properties || cat >> gradle.properties <<'P'
org.gradle.jvmargs=-Xmx24g -XX:+UseParallelGC
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.workers.max=96
android.enableR8.fullMode=true
P
./gradlew --no-daemon -q assembleGearvrArm64Release 2>&1 | tail -40
APK=$(ls app/build/outputs/apk/gearvrArm64/release/*.apk | head -1); echo "built: $APK"

# sign with our own key (zipalign + apksigner v1+v2)
K=$F/gearvr.keystore
[ -f $K ] || keytool -genkeypair -keystore $K -alias gearvr -keyalg RSA -keysize 4096 -validity 36500 \
  -storepass gearvr123 -keypass gearvr123 -dname "CN=S8 port Gear VR build" >/dev/null 2>&1
BT=$ANDROID_HOME/build-tools/30.0.3; mkdir -p $F/out; OUT=$F/out/FirefoxReality-gearvr-$GV.apk
$BT/zipalign -f -p 4 $APK $OUT.aligned
$BT/apksigner sign --ks $K --ks-pass pass:gearvr123 --out $OUT $OUT.aligned; rm -f $OUT.aligned
$BT/apksigner verify $OUT && ls -la $OUT
unzip -p $OUT lib/arm64-v8a/libvrapi.so | strings -a | grep -m1 -oE '1\.1\.[0-9]+\.[0-9]+'
