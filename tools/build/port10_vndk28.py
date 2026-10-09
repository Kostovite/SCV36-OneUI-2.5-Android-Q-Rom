"""Runs in WSL (python3 + readelf). Build the vndk-28 library set for the One UI 2 port:
the transitive closure of every system library the S8 Pie vendor needs, taken from the S8 Pie system,
stopping at LL-NDK / bionic (those stay the Android 10 versions, ABI-stable by design).
Also renders Android 10's ld.config.vndk_lite.txt for VNDK 28 with vendor searching vndk-28 before /system.
Outputs in ~/s8rom/port10: vndk28_lib.txt, vndk28_lib64.txt, ld.config.vndk_lite.rendered.txt"""
import os, re, subprocess

W = os.path.expanduser('~/s8rom/port10')
PIE = os.path.join(W, 's8sys')                        # S8 Pie /system dump (vendor under PIE/vendor)
DONOR = os.path.expanduser('~/s8rom/trees/g9600_root/system')
LLNDK = set(open(f'{W}/llndk.txt').read().split())
BIONIC = {'libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libsync.so', 'libvndksupport.so',
          'libnativewindow.so', 'libandroid_net.so', 'libmediandk.so', 'libvulkan.so', 'libEGL.so',
          'libGLESv1_CM.so', 'libGLESv2.so', 'libGLESv3.so', 'ld-android.so', 'libclang_rt.ubsan_standalone-aarch64-android.so'}
STOP = LLNDK | BIONIC


def needed(path):
    out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True).stdout
    return re.findall(r'Shared library: \[(.+?)\]', out)


for abi in ('lib', 'lib64'):
    vendor_dirs = [f'{PIE}/vendor/{abi}', f'{PIE}/vendor/{abi}