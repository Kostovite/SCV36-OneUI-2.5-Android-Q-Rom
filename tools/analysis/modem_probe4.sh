#!/usr/bin/env bash
# WSL (boot 8): extract modem.mdt + modem.bNN from modem.bin and check them with mdt_check.py.
P=$(cd "$(dirname "$0")/../.." && pwd)
W=~/s8rom/fwcheck; mkdir -p $W/img; cd $W/img
for f in modem.mdt $(seq -f 'modem.b%02g' 0 23); do mcopy -o -n -i $W/modem.bin ::/image/$f . 2>/dev/null; done
python3 $P/tools/analysis/mdt_check.py .
