#!/usr/bin/env bash
# WSL: dump MCFG profiles from a CP tar via mcfg_parse.py. usage: mcfg_dump.sh <CP tar> <profile substr> [grep]
set -e
REPO=$(cd "$(dirname "$0")/../.." && pwd)
IN=$1; P=$2; G=${3:-.}; W=$(mktemp -d)
tar -xf "$IN" -C $W modem.bin.lz4; lz4 -dqf $W/modem.bin.lz4 $W/modem.bin
src=$(mdir -/ -b -i $W/modem.bin ::/image/modem_pr | grep "mcfg_sw.mbn$" | grep "$P" | head -1)
mcopy -o -n -i $W/modem.bin "$src" $W/p.mbn
echo "== $src"; python3 $REPO/tools/analysis/mcfg_parse.py $W/p.mbn --grep "$G"
rm -rf $W
