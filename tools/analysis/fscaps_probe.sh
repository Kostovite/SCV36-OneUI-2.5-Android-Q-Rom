#!/usr/bin/env bash
# WSL: file capabilities (fs_config_files) of the T835, S8 and port vendors, and how the tools carry them.
P=$(cd "$(dirname "$0")/../.." && pwd)
for t in ~/s8rom/trees/t835_vendor ~/s8rom/trees/s8_vendor/vendor ~/s8rom/port/vendor; do
  echo "== $t"; python3 $P/tools/build/fscaps.py $t/etc/fs_config_files
done
echo "== xattr caps currently in port tree:"; getfattr -R -d -m security.capability ~/s8rom/port/vendor/bin 2>/dev/null | head
echo "== label/capability handling in tools"; grep -n -i 'capab\|setcap\|fs_config' $P/tools/*/*.sh $P/tools/*/*.py | grep -v fscaps | head
