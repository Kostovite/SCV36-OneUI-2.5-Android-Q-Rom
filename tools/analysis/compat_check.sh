#!/usr/bin/env bash
# Runs ON the build server. For every 'compatible' string in the stock SCV36 JPN r12 device tree, check whether a driver
# in each kernel tree claims it (string present in a .c file). Shows which hardware each kernel can actually drive.
cd ~/s8rom/kernel
DTS=~/s8rom/work/dts/jpn_r12.dts
grep -oE 'compatible = [^;]+' $DTS | sed -E 's/compatible = //; s/"//g' | tr '\0' '\n' | sed 's/\\0/\n/g' | tr ',' '\n' \
  | sed 's/^ *//' | grep -E '^[a-z0-9_-]+,[a-z0-9_.,-]+$|^[a-z0-9_.-]+$' >/dev/null
# full compatible strings (first entry of each node is the specific one)
grep -oE 'compatible = "[^"]+"' $DTS | sed -E 's/compatible = "//; s/"$//' | sort -u > /tmp/compat_all.txt
echo "distinct compatible strings in stock JPN r12: $(wc -l < /tmp/compat_all.txt)"
for t in g9500_pp t830_q; do
  grep -rhoE --include='*.c' '"[a-zA-Z0-9_,.+-]{3,}"' $t/drivers $t/sound $t/arch/arm64 $t/kernel $t/net 2>/dev/null \
    | tr -d '"' | sort -u > /tmp/strings_$t.txt
  comm -23 /tmp/compat_all.txt /tmp/strings_$t.txt > /tmp/missing_$t.txt
  echo "== $t: no driver for $(wc -l < /tmp/missing_$t.txt) compatibles"
done
echo "== missing in BOTH (DT-only / handled outside kernel - not a concern):"
comm -12 /tmp/missing_g9500_pp.txt /tmp/missing_t830_q.txt | tr '\n' ' '; echo
echo "== missing ONLY in Tab S4 Q tree (S8 hardware the Q kernel cannot drive):"
comm -13 /tmp/missing_g9500_pp.txt /tmp/missing_t830_q.txt
echo "== missing ONLY in G9500 PP tree:"
comm -23 /tmp/missing_g9500_pp.txt /tmp/missing_t830_q.txt
