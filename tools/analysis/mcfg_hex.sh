#!/usr/bin/env bash
# WSL: hex dump of one MCFG profile (mcfg_sw.mbn) from a CP tar. usage: mcfg_hex.sh <CP tar> <profile path substring>
set -e
IN=$1; P=$2; W=$(mktemp -d)
tar -xf "$IN" -C $W modem.bin.lz4; lz4 -dqf $W/modem.bin.lz4 $W/modem.bin
src=$(mdir -/ -b -i $W/modem.bin ::/image/modem_pr | grep "mcfg_sw.mbn$" | grep "$P" | head -1)
mcopy -o -n -i $W/modem.bin "$src" $W/p.mbn
python3 - $W/p.mbn <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
for m in [i for i in range(len(d)) if d[i:i+4] == b'MCFG'][:3]:
    print('MCFG at', hex(m))
    for r in range(m - 16, m + 160, 16):
        b = d[r:r+16]; print(f'{r:06x} {b.hex(" ")}  {"".join(chr(c) if 32 <= c < 127 else "." for c in b)}')
PY
rm -rf $W
