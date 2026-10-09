#!/usr/bin/env bash
# which SCV36 image holds modem.mdt/b11, and are mdt + blobs consistent?
P=$(cd "$(dirname "$0")/../.." && pwd)
F=$P/firmware/s8; W=~/s8rom/fwcheck; mkdir -p $W; cd $W
for t in $F/CP_SCV36*.tar.md5 $F/BL_SCV36*.tar.md5; do echo "== $(basename $t)"; tar -tvf $t; done
ls $F | grep -i '^AP_' && tar -tf $F/AP_SCV36*.tar.md5 | grep -iE 'hlos|modem|apnhlos'
tar -xf $F/CP_SCV36*.tar.md5 -C $W 2>/dev/null
for f in $W/*.lz4; do [ -e "$f" ] && lz4 -dqf "$f" "${f%.lz4}"; done
ls -la $W
which mdir >/dev/null || echo "need mtools"
for img in $W/modem.bin $W/NON-HLOS.bin; do [ -f $img ] || continue; echo "== $img"; mdir -i $img ::/image 2>/dev/null | grep -iE 'modem|mba' ; done
