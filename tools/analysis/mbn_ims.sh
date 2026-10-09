#!/usr/bin/env bash
# WSL: extract MCFG profiles from a modem.bin / CP tar and show the IMS / VoLTE related EFS items each one sets.
# usage: bash mbn_ims.sh <CP_*.tar.md5|modem.bin> <profile path substring>...
set -e
IN=$1; shift; W=$(mktemp -d)
if [[ $IN == *.tar.md5 ]]; then tar -xf "$IN" -C $W modem.bin.lz4; lz4 -dqf $W/modem.bin.lz4 $W/modem.bin; IMG=$W/modem.bin; else IMG=$IN; fi
for p in "$@"; do
  src=$(mdir -/ -b -i $IMG ::/image/modem_pr 2>/dev/null | grep "mcfg_sw.mbn$" | grep "$p" | head -1)
  mcopy -o -n -i $IMG "$src" $W/p.mbn
  echo "== $p ($(stat -c %s $W/p.mbn) bytes)"
  strings -n 6 $W/p.mbn | grep -i -E "ims|volte|sip|pdn|apn|lte_voice|voice_domain|ipv6|mmtel" | sort -u | head -40
done
rm -rf $W
