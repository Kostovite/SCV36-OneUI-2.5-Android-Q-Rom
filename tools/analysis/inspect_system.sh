#!/usr/bin/env bash
# Read-only inspection of a raw (unsparsed) Samsung system ext4 image with debugfs (run inside WSL).
# usage: bash tools/analysis/inspect_system.sh <system.raw.img> <out_dir>
IMG="$1"; OUT="$2"
mkdir -p "$OUT"
D() { debugfs -R "$1" "$IMG" 2>/dev/null; }
names() { D "ls -p $1" | awk -F/ '$6!=""{print $6}'; }

echo "== root:"; names / | tr '\n' ' '; echo
for f in build.prop vendor/build.prop vendor/etc/fstab.qcom etc/fstab.qcom vendor/etc/vintf/manifest.xml \
         vendor/manifest.xml vendor/compatibility_matrix.xml etc/vintf/manifest.xml; do
  dst="$OUT/$(echo "$f" | tr / _)"
  D "dump -p /$f $dst"
  if [ -s "$dst" ]; then echo "dumped $f"; else rm -f -- "$dst"; fi
done
for d in priv-app app vendor/lib64/hw vendor/bin bin etc/init vendor/etc/init vendor/app vendor/firmware; do
  names "/$d" > "$OUT/ls_$(echo "$d" | tr / _).txt"
  echo "ls $d: $(wc -l < "$OUT/ls_$(echo "$d" | tr / _).txt") entries"
done
