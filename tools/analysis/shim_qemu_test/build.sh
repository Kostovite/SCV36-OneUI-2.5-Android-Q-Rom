# qemu-arm test of the camera torch wrapper (config/stubs/camera_torch_shim.c) with the real G9600 Q bionic linker.
# WSL (needs qemu-user, clang-19): cp -r tools/shim_qemu_test ~/shimtest; bash ~/shimtest/build.sh   (fake HAL: full PASS/FAIL)
#   bash ~/shimtest/build_real.sh; bash ~/shimtest/pty.sh   (real S8 HAL: module-check controls, stops at the hardware)
set -e
D=$(dirname $0); cd $D; O=$D/out; rm -rf $O; mkdir -p $O/stub $O/root/vendor/lib/hw $O/root/system/lib $O/root/system/bin $O/root/data
P=$(cd "$(dirname "$0")/../../.." && pwd); CLANG=$(command -v clang-19 || command -v clang); T="--target=armv7a-linux-androideabi29 -mthumb -fuse-ld=lld"
for n in c dl log; do echo "void __libc_init(void){} void printf(void){} void memcpy(void){} void strcmp(void){} void exit(void){} void dlopen(void){} void dlsym(void){} void dlerror(void){} void open(void){} void write(void){} void close(void){} void __android_log_print(void){} void usleep(void){} void pthread_create(void){} void pthread_detach(void){} void pthread_mutex_lock(void){} void pthread_mutex_unlock(void){}" > $O/stub/s.c
  $CLANG $T -fPIC -shared -nostdlib -Wl,-soname,lib$n.so -o $O/stub/lib$n.so $O/stub/s.c; done
$CLANG $T -O2 -fPIC -shared -nostdlib -Wl,-soname,camera.msm8998.so -Wl,-z,now -o $O/root/vendor/lib/hw/camera.msm8998_s8.so fakehal.c -L$O/stub -lc
$CLANG $T -O2 -fPIE -pie -nostdlib -Wl,-z,now -Wl,--dynamic-linker=/system/bin/linker -o $O/root/data/test test.c -L$O/stub -lc -ldl
cp $P/config/stubs/out/lib/hw/camera.msm8998.so $O/root/vendor/lib/hw/camera.msm8998.so
R=~/s8rom/trees/g9600_root/system; A=$R/apex/com.android.runtime.release
cp $A/bin/linker $O/root/system/bin/linker
for l in libc libdl libm; do cp $A/lib/bionic/$l.so $O/root/system/lib/; done; cp -L $A/lib/ld-android.so $O/root/system/lib/ 2>/dev/null || cp $R/lib/ld-android.so $O/root/system/lib/
for l in liblog libc++; do cp -L $R/lib/$l.so $O/root/system/lib/ 2>/dev/null || true; done
for f in $O/root/system/lib/*.so; do readelf -d $f | grep NEEDED | sed "s/^/  $(basename $f): /"; done
tar -C $O -czf $D/root.tgz root
cd $O/root && timeout -s KILL 60 unshare -Urpf --mount-proc qemu-arm -L $PWD $PWD/system/bin/linker $PWD/data/test
