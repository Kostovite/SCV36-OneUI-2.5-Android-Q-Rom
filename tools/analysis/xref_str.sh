#!/usr/bin/env bash
# WSL: find code that references a string in an arm64 .so (adrp+add pairs) and print surrounding disassembly.
# usage: xref_str.sh <lib.so> <string> [context lines]
L=$1; S=$2; C=${3:-14}
OD=~/s8rom/toolchains/aarch64-linux-android-4.9/bin/aarch64-linux-android-objdump
OFF=$(python3 -c "import sys;d=open('$L','rb').read();print(d.find(b'$S'))")
# file offset -> vaddr via section table
VA=$($OD -h $L | python3 -c "
import sys
o=$OFF
for l in sys.stdin:
    p=l.split()
    if len(p)>=7 and p[0].isdigit():
        sz,va,fo=int(p[2],16),int(p[3],16),int(p[5],16)
        if fo<=o<fo+sz: print('%x'%(va+o-fo)); break
")
echo "string @ file 0x$(printf %x $OFF) vaddr 0x$VA"
PAGE=$(printf "%x" $(( 0x$VA & ~0xfff ))); LO=$(printf "%x" $(( 0x$VA & 0xfff )))
$OD -d --no-show-raw-insn $L > /tmp/dis.txt
grep -n -E "adrp\s+x[0-9]+, $PAGE " /tmp/dis.txt | while IFS=: read n rest; do
  if sed -n "$n,$((n+6))p" /tmp/dis.txt | grep -q -E "add\s+x[0-9]+, x[0-9]+, #0x$LO\b"; then
    echo "---- xref at line $n"; sed -n "$((n-C)),$((n+C))p" /tmp/dis.txt
  fi
done
