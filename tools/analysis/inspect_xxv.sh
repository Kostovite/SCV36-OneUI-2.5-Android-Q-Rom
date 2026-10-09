#!/usr/bin/env bash
# WSL: unsparse the G960F OXM odm image and find the XXV (Vietnam) CSC config.
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
D=$P/work/donor_G960F
[ -s $D/odm.raw.img ] || simg2img $D/odm.img $D/odm.raw.img
OUT=$D/odm_tree; rm -rf $OUT; mkdir -p $OUT
debugfs -R "rdump / $OUT" $D/odm.raw.img 2>/dev/null
echo "== top dirs (MiB):"; du -sm $OUT/* | sort -rn | head
echo "== paths containing XXV:"; find $OUT -ipath '*XXV*' | sed "s#$OUT##" | head -20
echo "== CSC code dirs (3 uppercase letters):"
find $OUT -maxdepth 4 -type d -regex '.*/[A-Z0-9][A-Z0-9][A-Z0-9]' | sed "s#$OUT##" | head -10
