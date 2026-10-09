#!/usr/bin/env bash
# WSL: build the small vendor stand-in libraries in config/stubs/ -> config/stubs/out/<arch>/
#   libsensorlistener.so (armv7): see config/stubs/libsensorlistener.cpp
set -e
P=$(cd "$(dirname "$0")/../.." && pwd); S=$P/config/stubs; O=$S/out
CLANG=$(command -v clang-19 || command -v clang)
mkdir -p $O/lib
$CLANG --target=armv7a-linux-androideabi29 -mthumb -O2 -fPIC -shared -nostdlib -fno-exceptions -fno-rtti \
  -fuse-ld=lld -Wl,-soname,libsensorlistener.so -Wl,--hash-style=both -Wl,-z,noexecstack \
  -o $O/lib/libsensorlistener.so $S/libsensorlistener.cpp
readelf -W --dyn-syms $O/lib/libsensorlistener.so | awk '$7 != "UND" && $5 == "GLOBAL" {print "  export:", $8}'
readelf -d $O/lib/libsensorlistener.so | grep -E 'SONAME|NEEDED|TEXTREL' || true
file $O/lib/libsensorlistener.so

# camera.msm8998.so (armv7): torch-strength wrapper around the S8 Pie camera HAL (config/stubs/camera_torch_shim.c).
# Link-time stand-ins for bionic libc/libdl and liblog (only the sonames + symbol names matter; the device's real
# libraries resolve them at runtime).
L=$O/linkstub; mkdir -p $L
printf 'void*dlopen(){return 0;}void*dlsym(){return 0;}char*dlerror(){return 0;}\n' > $L/dl.c
printf 'void*memcpy(){return 0;}int strcmp(){return 0;}int open(){return 0;}long write(){return 0;}int close(){return 0;}int pthread_create(){return 0;}int pthread_detach(){return 0;}int pthread_mutex_lock(){return 0;}int pthread_mutex_unlock(){return 0;}int usleep(){return 0;}\n' > $L/c.c
printf 'int __android_log_print(){return 0;}\n' > $L/log.c
for n in c dl log; do
  $CLANG --target=armv7a-linux-androideabi29 -mthumb -fPIC -shared -nostdlib -fuse-ld=lld -Wl,-soname,lib$n.so \
    -o $L/lib$n.so $L/$n.c
done
mkdir -p $O/lib/hw
$CLANG --target=armv7a-linux-androideabi29 -mthumb -O2 -fPIC -shared -nostdlib -ffreestanding -fno-builtin \
  -fuse-ld=lld -Wl,-soname,camera.msm8998.so -Wl,--hash-style=both -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now \
  -o $O/lib/hw/camera.msm8998.so $S/camera_torch_shim.c -L$L -lc -ldl -llog
readelf -d $O/lib/hw/camera.msm8998.so | grep -E 'SONAME|NEEDED|TEXTREL|INIT_ARRAY' || true
readelf -W --dyn-syms $O/lib/hw/camera.msm8998.so | awk '$7 != "UND" && $5 == "GLOBAL" {print "  export:", $8, $3}'
# audio.primary.msm8998.so (armv7): Samsung Q audio extension entry points in front of the S8 Pie audio HAL
# (config/stubs/audio_hal_shim.c)
$CLANG --target=armv7a-linux-androideabi29 -mthumb -O2 -fPIC -shared -nostdlib -ffreestanding -fno-builtin \
  -fuse-ld=lld -Wl,-soname,audio.primary.msm8998.so -Wl,--hash-style=both -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now \
  -o $O/lib/hw/audio.primary.msm8998.so $S/audio_hal_shim.c -L$L -lc -ldl -llog
readelf -W --dyn-syms $O/lib/hw/audio.primary.msm8998.so | awk '$7 != "UND" && $5 == "GLOBAL" {print "  export:", $8, $3}'
# libaeabi_compat.so (armv7): __aeabi_idiv0/__aeabi_ldiv0 for S8 Pie camera libs (config/stubs/aeabi_compat.c)
$CLANG --target=armv7a-linux-androideabi29 -mthumb -O2 -fPIC -shared -nostdlib -ffreestanding -fno-builtin \
  -fuse-ld=lld -Wl,-soname,libaeabi_compat.so -Wl,--hash-style=both -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now \
  -o $O/lib/libaeabi_compat.so $S/aeabi_compat.c
readelf -W --dyn-syms $O/lib/libaeabi_compat.so | awk '$7 != "UND" && $5 == "GLOBAL" {print "  export:", $8}'
# libsdtv_compat.so (arm64): Pie -> Q ABI bridge for the SCV36 ISDB-T TV middleware (config/stubs/sdtv_compat.c)
L64=$O/linkstub64; mkdir -p $L64 $O/lib64
printf 'int _ZN7android13GraphicBuffer4lockEjPPvPiS3_(){return 0;}\n' > $L64/ui.c
$CLANG --target=aarch64-linux-android29 -fPIC -shared -nostdlib -fuse-ld=lld -Wl,-soname,libui.so -o $L64/libui.so $L64/ui.c
$CLANG --target=aarch64-linux-android29 -O2 -fPIC -shared -nostdlib -ffreestanding -fno-builtin \
  -fuse-ld=lld -Wl,-soname,libsdtv_compat.so -Wl,--hash-style=both -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now \
  -o $O/lib64/libsdtv_compat.so $S/sdtv_compat.c -L$L64 -lui
readelf -W --dyn-syms $O/lib64/libsdtv_compat.so | awk '$7 != "UND" && $5 == "GLOBAL" {print "  export:", $8}'
