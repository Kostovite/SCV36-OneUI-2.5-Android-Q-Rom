"""Runs ON the build server (branch s8-q-port): add a boot watchdog to the s8dbg debug hook in msm-poweroff.c.
msm_poweroff.s8dbg_timeout=<seconds> (cmdline, debug boot image only): if userspace has not cleared it by then
(echo 0 > /sys/module/msm_poweroff/parameters/s8dbg_timeout, done by an init trigger on sys.boot_completed=1),
the kernel restarts -> the s8dbg reboot notifier dumps the kernel log (incl. init's messages) to 'cache' and the
s8dbg restart path warm-resets into recovery. Catches hangs, which leave no panic record."""
import os
F = os.path.expanduser('~/s8rom/kernel/t830_q/drivers/power/reset/msm-poweroff.c')
s = open(F).read()
if 's8dbg_timeout' in s:
    print('already patched'); raise SystemExit
s = s.replace('#include <linux/gfp.h>\n', '#include <linux/gfp.h>\n#include <linux/kthread.h>\n#include <linux/delay.h>\n'
              '#include <linux/moduleparam.h>\n#include <linux/reboot.h>\n', 1)
anchor = 'static int __init s8dbg_logdump_init(void)\n{\n\tif (s8dbg_recovery)\n\t\tregister_reboot_notifier(&s8dbg_reboot_nb);\n'
assert anchor in s, 'anchor not found'
watchdog = '''/* s8dbg boot watchdog: catch boot hangs (no panic, no reboot) in debug images */
static int s8dbg_timeout;
module_param(s8dbg_timeout, int, 0644);

static int s8dbg_watchdog_fn(void *unused)
{
\tint t = 0;

\twhile (!kthread_should_stop()) {
\t\tmsleep(1000);
\t\tif (READ_ONCE(s8dbg_timeout) <= 0) {
\t\t\tpr_info("s8dbg: boot watchdog cancelled after %d s\\n", t);
\t\t\treturn 0;
\t\t}
\t\tif (++t >= READ_ONCE(s8dbg_timeout)) {
\t\t\tpr_emerg("s8dbg: boot watchdog expired after %d s - capturing log and rebooting\\n", t);
\t\t\tkernel_restart("s8dbg-boot-timeout");
\t\t}
\t}
\treturn 0;
}

'''
s = s.replace(anchor, watchdog + anchor + '\tif (s8dbg_recovery && s8dbg_timeout > 0)\n'
              '\t\tkthread_run(s8dbg_watchdog_fn, NULL, "s8dbg_wdog");\n', 1)
open(F, 'w').write(s)
print('s8dbg boot watchdog added')
