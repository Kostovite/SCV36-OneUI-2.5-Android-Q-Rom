# full sysroot: G9600 /system/lib (apex symlinks resolved) + port vendor/lib, real S8 HAL behind the shim
set -e
O=$HOME/shimtest/real; rm -rf $O; mkdir -p $O/root/system $O/root/data
P=$(cd "$(dirname "$0")/../../.." && pwd)
R=~/s8rom/trees/g9600_root/system; A=$R/apex/com.android.runtime.release
cp -a $R/lib $O/root/system/lib; mkdir -p $O/root/system/bin; cp $A/bin/linker $O/root/system/bin/linker
cd $O/root/system/lib
for f in $(find . -type l); do t=$(readlink $f); case $t in /apex/com.android.runtime/*) rm $f; cp ${A}/${t#/apex/com.android.runtime/} $f ;; /apex/*) ap=${t#/apex/}; n=${ap%%/*}; rm $f; cp $R/apex/$n*/${ap#*/} $f 2>/dev/null || true ;; esac; done
for d in $(ls -d $R/lib/vndk-sp-29 $R/lib/vndk-29 $R/apex/com.android.vndk.v29*/lib 2>/dev/null); do echo "vndk: $d"; cp -n $d/*.so $O/root/system/lib/ 2>/dev/null || true; done
cp -a ~/s8rom/port/vendor $O/root/vendor
# the port tree may hold an older wrapper build: always test the fresh one
cp $P/config/stubs/out/lib/hw/camera.msm8998.so $O/root/vendor/lib/hw/camera.msm8998.so
cp $HOME/shimtest/out/root/data/test $O/root/data/test
cd $O && tar czf $HOME/shimtest/real.tgz root && ls -la $HOME/shimtest/real.tgz
