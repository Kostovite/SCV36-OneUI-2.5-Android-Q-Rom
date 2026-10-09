#!/usr/bin/env bash
# Run in WSL: sanity-check an efs.img backup (lists structure only, never prints IMEI/serial contents).
P=$(cd "$(dirname "$0")/../.." && pwd)
IMG=${1:-$P/backup/20261005_223719/efs.img}
D() { debugfs -R "$1" "$IMG" 2>/dev/null; }
echo "== efs root:"; D "ls -p /" | awk -F/ '$6!=""{print $6}' | tr '\n' ' '; echo
D stats | grep -E 'Filesystem state|Inode count|Free inodes'
echo "== files (count by top dir):"
D "ls -p /" | awk -F/ '$6!="" && $6!="." && $6!=".."{print $6}' | while read -r d; do
  printf '%-24s %s entries\n' "$d" "$(D "ls -p /$d" | awk -F/ '$6!=""' | wc -l)"
done
