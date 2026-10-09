"""Runs ON the build server (python3): add the 's8dbg.recovery' debug hook to msm-poweroff.c in the Q kernel tree.
With 's8dbg.recovery' on the kernel cmdline, every restart (incl. after a panic) becomes a WARM reset into recovery,
so pstore / last_kmsg survive and can be read from TWRP. Idempotent."""
import os, sys
p = os.path.expanduser('~/s8rom/kernel/t830_q/drivers/power/reset/msm-poweroff.c')
s = open(p).read()
if 's8dbg_recovery' in s:
    print('already patched'); sys.exit(0)

hook_decl = '''
/* s8dbg: debug-only bootloop catcher, enabled by "s8dbg.recovery" on the kernel cmdline */
static bool s8dbg_recovery;
static int __init s8dbg_recovery_setup(char *str)
{
	s8dbg_recovery = true;
	return 1;
}
__setup("s8dbg.recovery", s8dbg_recovery_setup);

static void msm_restart_prepare(const char *cmd)
{'''
anchor = '\nstatic void msm_restart_prepare(const char *cmd)\n{'
assert s.count(anchor) == 1, 'anchor not found exactly once'
s = s.replace(anchor, hook_decl, 1)

body_anchor = '''#ifdef CONFIG_SEC_DEBUG
	unsigned long value;
	int hard_reset_reason = 0xff;
#endif
'''
hook_body = body_anchor + '''
	if (s8dbg_recovery) {
		pr_emerg("s8dbg: restart (cmd=%s) redirected to recovery via warm reset\\n",
			 cmd ? cmd : "");
		qpnp_pon_system_pwr_off(PON_POWER_OFF_WARM_RESET);
		qpnp_pon_set_restart_reason(PON_RESTART_REASON_RECOVERY);
		__raw_writel(0x77665502, restart_reason);
		return;
	}
'''
assert s.count(body_anchor) == 1, 'body anchor not found exactly once'
s = s.replace(body_anchor, hook_body, 1)
open(p, 'w').write(s)
print('patched', p)
