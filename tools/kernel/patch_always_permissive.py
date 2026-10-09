"""Runs ON the build server: add CONFIG_ALWAYS_PERMISSIVE (as in hadesKernel Q for the Exynos S8, corsicanu/
android_kernel_samsung_universal8895 branch 10). Any write to /sys/fs/selinux/enforce is forced to 0, so the One UI 2
port boots permissive while the S8 Pie vendor has no proper split vendor policy. Off unless enabled in the config."""
import os, re
K = os.path.expanduser('~/s8rom/kernel/t830_q/security/selinux/')

kc = open(K + 'Kconfig').read()
if 'config ALWAYS_PERMISSIVE' not in kc:
    kc = kc.replace('config SECURITY_SELINUX_BOOTPARAM',
                    'config ALWAYS_PERMISSIVE\n\tbool "NSA SELinux Permissive"\n\tdepends on SECURITY_SELINUX\n'
                    '\tdefault n\n\thelp\n\t  This forces the kernel to run in permissive mode.\n\n'
                    'config SECURITY_SELINUX_BOOTPARAM', 1)
    open(K + 'Kconfig', 'w').write(kc)

fs = open(K + 'selinuxfs.c').read()
anchor = ('#else\n\tif (new_value != selinux_enforcing) {\n'
          '\t\tlength = task_has_security(current, SECURITY__SETENFORCE);')
if 'CONFIG_ALWAYS_PERMISSIVE' not in fs:
    assert fs.count(anchor) == 1, 'anchor not found exactly once'
    fs = fs.replace(anchor, '#else\n#ifdef CONFIG_ALWAYS_PERMISSIVE\n\tnew_value = 0;\n#endif\n'
                            '\tif (new_value != selinux_enforcing) {\n'
                            '\t\tlength = task_has_security(current, SECURITY__SETENFORCE);')
    open(K + 'selinuxfs.c', 'w').write(fs)
print('ALWAYS_PERMISSIVE patch present:', 'CONFIG_ALWAYS_PERMISSIVE' in open(K + 'selinuxfs.c').read())
