#!/usr/bin/env bash
# Compare the stock SCV36 kernel config (Pie, from IKCONFIG) against the Tab S4 Q tree:
# which enabled symbols have no Kconfig definition in the Q tree (= missing S8 drivers).
P=$(cd "$(dirname "$0")/../.." && pwd)
K=~/s8rom/kernel/t830_q
W=$P/work
CFG=$W/stock_CZE1/boot.img_unpacked/kernel.config
OUT=$W/kernel_gap; mkdir -p $OUT
cd "$K"
# all symbols defined anywhere in the Q tree
grep -rhoE '^\s*(menu)?config\s+[A-Z0-9_]+' --include='Kconfig*' . | awk '{print $NF}' | sort -u > $OUT/q_symbols.txt
grep -E '^CONFIG_[A-Z0-9_]+=(y|m)' "$CFG" | sed -E 's/^CONFIG_([A-Z0-9_]+)=.*/\1/' | sort -u > $OUT/stock_enabled.txt
comm -23 $OUT/stock_enabled.txt $OUT/q_symbols.txt > $OUT/missing_in_q.txt
echo "stock enabled: $(wc -l < $OUT/stock_enabled.txt), defined in Q tree: $(wc -l < $OUT/q_symbols.txt), missing: $(wc -l < $OUT/missing_in_q.txt)"
cat $OUT/missing_in_q.txt | tr '\n' ' '; echo
# decompile stock DTBs for reference (S8 JPN rev09/11/12)
python3 - "$W/stock_CZE1/boot.img_unpacked/kernel" "$OUT" <<'EOF'
import sys, zlib, re
raw = open(sys.argv[1], 'rb').read()
z = zlib.decompressobj(16 + zlib.MAX_WBITS); z.decompress(raw); tail = z.unused_data
offs = [m.start() for m in re.finditer(rb'\xd0\x0d\xfe\xed', tail)]
for i, o in enumerate(offs):
    size = int.from_bytes(tail[o+4:o+8], 'big')
    open(f'{sys.argv[2]}/stock_dtb{i}.dtb', 'wb').write(tail[o:o+size])
print('dtbs', len(offs))
EOF
for d in $OUT/stock_dtb*.dtb; do dtc -q -I dtb -O dts -o "${d%.dtb}.dts" "$d"; grep -m1 'model =' "${d%.dtb}.dts"; done
