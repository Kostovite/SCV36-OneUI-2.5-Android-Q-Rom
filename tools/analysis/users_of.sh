#!/usr/bin/env bash
# WSL: which ELFs in a vendor tree NEED a given library. usage: bash users_of.sh <tree> <lib.so>...
TREE=$1; shift
for lib in "$@"; do
  echo "== users of $lib in $TREE:"
  find $TREE -type f \( -name '*.so' -o -path '*/bin/*' \) | while read -r f; do
    readelf -d "$f" 2>/dev/null | grep -q "Shared library: \[$lib\]" && echo "   ${f#$TREE/}"
  done
done
