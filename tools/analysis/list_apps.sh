#!/usr/bin/env bash
# List donor apps with sizes + package names (from AndroidManifest via aapt if present, else dir name).
P=$(cd "$(dirname "$0")/../.." && pwd)
cd ~/s8rom/trees/s9_root/system || exit 1
OUT=$P/work/donor_SCV38/inspect
du -sm app/* priv-app/* preload/* 2>/dev/null | sort -k2 > $OUT/app_sizes.txt
wc -l < $OUT/app_sizes.txt
echo "== media:"; ls media | tr '\n' ' '; echo
echo "== carrier/csc-ish in etc:"; ls etc | grep -iE 'csc|omc|carrier|kdi|jpn|felica|kddi|au_' | tr '\n' ' '; echo
echo "== odm root on donor:"; cat $P/work/donor_SCV38/inspect/ls_odm_root.txt | tr '\n' ' '; echo
