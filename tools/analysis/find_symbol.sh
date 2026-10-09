#!/usr/bin/env bash
# WSL: which S8 Pie library (vendor or system) defines a symbol, and what the G9600 Q system has under that name.
# usage: bash find_symbol.sh <symbol> [<symbol>...]
for sym in "$@"; do
  echo "== $sym"
  for d in ~/s8rom/trees/s8_vendor/vendor/lib64 ~/s8rom/trees/s8_system/lib64; do
    for f in $d/*.so; do
      readelf -W --dyn-syms "$f" 2>/dev/null | awk -v s="$sym" '$7!="UND" && $8==s {found=1} END{exit !found}' && echo "  S8: ${f#$HOME/s8rom/trees/}"
    done
  done
done
echo "== Q (G9600 system) copies of those libs:"
ls ~/s8rom/trees/g9600_root/system/lib64/vndk-29 | grep -i keymaster
