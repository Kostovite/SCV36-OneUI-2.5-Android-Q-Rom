#!/usr/bin/env bash
# Runs ON the build server: APR (audio DSP link) driver in Q (t830_q) vs S8 Pie (g9500_pp) - the crash site.
cd ~/s8rom/kernel
f=$(cd t830_q && git ls-files | grep -E '(^|/)apr\.c$' | head -3); echo "apr.c files in Q tree: $f"
for t in t830_q g9500_pp; do
  for x in $f; do [ -f $t/$x ] || continue
    echo "################ $t/$x : apr_set_q6_state + delayed work"
    grep -n 'apr_set_q6_state' -A16 $t/$x | head -22
    grep -nE 'DELAYED_WORK|delayed_work|INIT_DELAYED_WORK|queue_delayed_work|add_chld_dev|apr_adsp_up|modem_up|of_platform_populate' $t/$x | head -20
  done
done
echo "################ diff (Pie -> Q) of apr.c"
for x in $f; do diff -u g9500_pp/$x t830_q/$x | head -120; done
