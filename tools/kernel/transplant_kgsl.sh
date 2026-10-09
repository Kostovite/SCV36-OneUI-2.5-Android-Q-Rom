#!/usr/bin/env bash
# Runs ON the build server: replace the Q-tree Adreno/KGSL driver with the S8 Pie (G9500 PP) one.
# Reason: Q kgsl makes the CP scratch buffer privileged -> S8 Pie GPU microcode faults ("CP initialization failed to
# idle" + GPU write permission fault) and surfaceflinger crash-loops. The uapi msm_kgsl.h stays Q (additive superset).
set -e
cd ~/s8rom/kernel
rsync -a --delete g9500_pp/drivers/gpu/msm/ t830_q/drivers/gpu/msm/
find t830_q/drivers/gpu/msm -type f -exec touch {} +   # rsync keeps 2019 mtimes -> make would skip them
cd t830_q
echo "kgsl now from S8 Pie: $(git diff --stat -- drivers/gpu/msm | tail -1)"
# other in-kernel users of kgsl-internal headers that may differ (devfreq adreno governors)
diff -rq ../g9500_pp/drivers/devfreq ../t830_q/drivers/devfreq | grep -iE 'adreno|kgsl|gpubw' || echo "devfreq adreno governors identical"
diff -q ../g9500_pp/include/linux/msm_adreno_devfreq.h include/linux/msm_adreno_devfreq.h && echo "msm_adreno_devfreq.h identical"
