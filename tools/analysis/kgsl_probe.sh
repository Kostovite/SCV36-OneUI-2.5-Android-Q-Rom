#!/usr/bin/env bash
# Runs ON the build server: Pie -> Q kgsl changes touching read-only / privileged GPU buffers (the CP write fault).
cd ~/s8rom/kernel
diff -ru g9500_pp/drivers/gpu/msm t830_q/drivers/gpu/msm | grep -nE '^[-+].*(READONLY|GPUREADONLY|PRIV|scratch|memstore|rptr|ringbuffer|preempt|PROTECT|secure|zap|_RO\b)' | head -40
echo "== files changed:"
diff -rq g9500_pp/drivers/gpu/msm t830_q/drivers/gpu/msm | sed 's#g9500_pp/##; s# and t830_q.*##' | head -30
