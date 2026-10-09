#!/usr/bin/env bash
# WSL: remove the S8 panel's multi-resolution display timings (fhd, hd) from the concatenated JPN DTBs, keeping only
# the native wqhd timing. Samsung's One UI 2 SurfaceFlinger "MultiResolution" matches the WM size (1080x2220) to an
# HWC display mode and then renders into that size expecting the panel DDI to upscale - the T835 composer never sends
# the S8 panel's multires commands, so the image sat unscaled in the top-left. With no matching mode SF logs
# "Unsupported Resolution" and keeps the normal GPU-scaled projection.
# usage: bash dtb_single_mode.sh <in.dtb (concatenated)> <out.dtb>
set -e
IN=$1; OUT=$2; W=~/s8rom/work_dtb; P=$(cd "$(dirname "$0")/../.." && pwd)
rm -rf $W && mkdir -p $W && cd $W
python3 - "$IN" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(); o = 0; n = 0
while True:
    o = d.find(b'\xd0\x0d\xfe\xed', o)
    if o < 0: break
    tot = struct.unpack_from('>I', d, o + 4)[0]
    if 64 < tot < (4 << 20):
        n += 1; open('part%02d.dtb' % n, 'wb').write(d[o:o + tot]); o += tot
    else:
        o += 4
print(n, 'dtbs')
PY
for f in part*.dtb; do
  dtc -q -I dtb -O dts -o ${f%.dtb}.dts $f
  for node in $(python3 $P/tools/analysis/dts_paths.py ${f%.dtb}.dts '^(fhd|hd)$' | grep 'mdss-dsi-display-timings'); do
    fdtput -r $f "$node" && echo "$f: removed $node"
  done
  dtc -q -I dtb -O dts -o ${f%.dtb}.after.dts $f
  left=$(python3 $P/tools/analysis/dts_paths.py ${f%.dtb}.after.dts '^(fhd|hd)$' | grep -c 'mdss-dsi-display-timings' || true)
  echo "$f: $(fdtget $f / model) - multires timings left: $left"
done
cat part*.dtb > "$OUT"
ls -la "$IN" "$OUT"
