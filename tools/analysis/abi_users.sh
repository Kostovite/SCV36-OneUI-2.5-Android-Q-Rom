#!/usr/bin/env bash
# WSL: do ELFs that stay T835 still find every symbol they import from libraries we replaced with S8 copies?
# usage: abi_users.sh <vendor tree> <replaced lib (lib64/x.so)> <user ELF>...
V=$1; L=$2; shift 2
readelf -W --dyn-syms $V/$L | awk '$7!="UND" && ($5=="GLOBAL"||$5=="WEAK") {sub(/@.*/,"",$8); print $8}' | sort -u > /tmp/def.txt
for u in "$@"; do
  readelf -W --dyn-syms $V/$u | awk '$7=="UND" && $5=="GLOBAL" {sub(/@.*/,"",$8); print $8}' | sort -u > /tmp/und.txt
  # only symbols that the original T835 library provided (i.e. the ones this user takes from it)
  readelf -W --dyn-syms ~/s8rom/trees/t835_vendor/$L | awk '$7!="UND" {sub(/@.*/,"",$8); print $8}' | sort -u > /tmp/olddef.txt
  miss=$(comm -12 /tmp/und.txt /tmp/olddef.txt | comm -23 - /tmp/def.txt)
  echo "$u -> $(basename $L): ${miss:-OK}"
done
