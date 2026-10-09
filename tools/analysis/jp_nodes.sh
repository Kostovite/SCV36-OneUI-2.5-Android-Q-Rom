#!/usr/bin/env bash
# Runs ON the build server: compatible strings of JPN-only DT nodes, and which kernel trees carry their drivers.
cd ~/s8rom/work/dts
for n in 'fps-spi@0' 'vfsspi-spi@0' 'sec-nfc@27' 'qcom-spi@0' 'isdbt_data' 'sec_thermistor@1' 'pn547@2B'; do
  for f in jpn_r12.dts can_r12.dts; do
    c=$(grep -A6 "$n {" "$f" | grep -m1 compatible)
    [ -n "$c" ] && echo "$f  $n: $(echo $c | tr -d '\t')"
  done
done
cd ~/s8rom/kernel
echo; printf '%-24s %6s %6s\n' "string" "Q-tree" "CAN"
for c in vfs8xxx 'vfsspi,vfs8xxx' 'etspi' 'egis' 'sec-nfc' 'sec_nfc' 'isdbt' 'mmtuner' 'felica' 'sec,thermistor'; do
  printf '%-24s %6s %6s\n' "$c" \
    "$(grep -rIl --include='*.c' -- "$c" t830_q/drivers 2>/dev/null | wc -l)" \
    "$(grep -rIl --include='*.c' -- "$c" dreamqltecan/drivers 2>/dev/null | wc -l)"
done
