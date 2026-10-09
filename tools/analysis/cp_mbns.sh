#!/usr/bin/env bash
# WSL: list the carrier modem profiles (MCFG mcfg_sw.mbn) inside a Samsung CP_*.tar.md5 (or a modem.bin).
# A VoLTE donor must carry a profile covering Vietnamese carriers (e.g. row/viettel, row/common, open market).
# usage: bash cp_mbns.sh <CP_*.tar.md5 | modem.bin>
set -e
IN=$1; W=$(mktemp -d)
if [[ $IN == *.tar.md5 || $IN == *.tar ]]; then
  tar -xf "$IN" -C $W modem.bin.lz4 2>/dev/null || tar -xf "$IN" -C $W modem.bin
  [ -f $W/modem.bin.lz4 ] && lz4 -dqf $W/modem.bin.lz4 $W/modem.bin
  IMG=$W/modem.bin
else
  IMG=$IN
fi
echo "== $(basename "$IN")"
mdir -/ -b -i $IMG ::/image/modem_pr 2>/dev/null | grep -i 'mcfg_sw\.mbn$' \
  | sed 's#::/image/modem_pr/mcfg/configs/mcfg_sw/##; s#/mcfg_sw.mbn##' | sort
echo "total: $(mdir -/ -b -i $IMG ::/image/modem_pr 2>/dev/null | grep -ci 'mcfg_sw\.mbn$') profiles"
mtype -i $IMG ::/image/modem_pr/mcfg/configs/mcfg_sw/mbn_sw.txt 2>/dev/null | head -5 || true
rm -rf $W
