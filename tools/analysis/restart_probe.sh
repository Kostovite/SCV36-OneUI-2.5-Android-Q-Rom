#!/usr/bin/env bash
# Runs ON the build server: rest of the msm restart path (Q tree) + compare the odd panic("recovery") with S8 Pie source.
cd ~/s8rom/kernel/t830_q
sed -n '440,470p' drivers/power/reset/msm-poweroff.c
echo ----
sed -n '540,600p' drivers/power/reset/msm-poweroff.c
echo "---- panic(recovery) in S8 Pie source?"; grep -n 'panic("recovery")' ../g9500_pp/drivers/power/reset/msm-poweroff.c || echo "not in G9500 Pie"
echo "---- pon API"; grep -n 'qpnp_pon_set_restart_reason\|qpnp_pon_system_pwr_off' include/linux/input/qpnp-power-on.h
