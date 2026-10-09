#!/usr/bin/env bash
# Runs ON the build server: who overrides the warm-reset request in the restart path?
cd ~/s8rom/kernel/t830_q
echo "== qpnp_pon_system_pwr_off():"
grep -n 'int qpnp_pon_system_pwr_off' -A45 drivers/input/misc/qpnp-power-on.c | head -60
echo "== other callers forcing reset type:"
grep -rn 'qpnp_pon_system_pwr_off(' --include='*.c' drivers arch kernel | grep -v 'qpnp-power-on.c:.*int qpnp_pon_system_pwr_off' | head -20
echo "== restart/reboot notifiers in sec_debug:"
grep -rnE 'register_reboot_notifier|register_restart_handler|atomic_notifier_chain_register\(&panic' drivers/debug/*.c | head -10
