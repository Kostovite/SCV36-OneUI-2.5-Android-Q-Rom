# qemu test of config/stubs/audio_hal_shim.c against fake_audio.c (run after build.sh, which builds root/ + stubs)
set -e
D=$(cd $(dirname $0); pwd); O=$D/out; P=$(cd "$(dirname "$0")/../../.." && pwd)
T="--target=armv7a-linux-androideabi29 -mthumb -fuse-ld=lld"
clang-19 $T -O2 -fPIC -shared -nostdlib -Wl,-soname,audio.primary.msm8998.so -Wl,-z,now -o $O/root/vendor/lib/hw/audio.primary.msm8998_s8.so $D/fake_audio.c -L$O/stub -lc 2>/dev/null
clang-19 $T -O2 -fPIE -pie -nostdlib -Wl,-z,now -Wl,--dynamic-linker=/system/bin/linker -o $O/root/data/test_audio $D/test_audio.c -L$O/stub -lc -ldl 2>/dev/null
cp $P/config/stubs/out/lib/hw/audio.primary.msm8998.so $O/root/vendor/lib/hw/audio.primary.msm8998.so
cd $O/root && timeout -s KILL 60 unshare -Urpf --mount-proc qemu-arm -L $PWD $PWD/system/bin/linker $PWD/data/test_audio
