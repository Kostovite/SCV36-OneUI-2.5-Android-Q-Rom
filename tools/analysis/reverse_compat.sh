#!/usr/bin/env bash
# Runs ON the build server: Q-tree drivers (compiled into our kernel) whose of_match compatibles are ALL absent from the
# stock S8 Pie DT, but whose Pie-tree counterpart did NOT need a DT node -> same trap as APR (init never runs).
cd ~/s8rom/kernel
DTS=~/s8rom/work/dts/jpn_r12.dts
O=~/s8rom/kernel/out_dream
grep -oE '"[^"]+"' $DTS | tr -d '"' | sort -u > /tmp/dt_strings.txt
for d in drivers/soc/qcom/qdsp6v2 sound/soc/msm sound/soc/codecs drivers/gpu/msm drivers/video/fbdev/msm \
         drivers/media/platform/msm drivers/platform/msm/ipa drivers/soc/qcom drivers/char drivers/net/wireless; do
  for f in $(grep -rl --include='*.c' 'of_device_id' t830_q/$d 2>/dev/null); do
    o=$O/${f#t830_q/}; o=${o%.c}.o
    [ -f "$o" ] || continue                      # only drivers actually built into our kernel
    comps=$(awk '/of_device_id/,/};/' $f | grep -oE 'compatible *= *"[^"]+"' | sed -E 's/.*"([^"]+)"/\1/')
    [ -z "$comps" ] && continue
    hit=0; for c in $comps; do grep -qxF "$c" /tmp/dt_strings.txt && hit=1; done
    if [ $hit = 0 ]; then
      pie=g9500_pp/${f#t830_q/}
      if [ -f $pie ] && ! grep -q 'of_device_id' $pie; then tag="PIE HAD NO DT MATCH (APR-like trap!)"
      elif [ -f $pie ]; then tag="pie also DT-matched"; else tag="new in Q"; fi
      echo "${f#t830_q/}: $(echo $comps | tr '\n' ' ') -> $tag"
    fi
  done
done | sort | grep -v 'pie also DT-matched' | head -40
