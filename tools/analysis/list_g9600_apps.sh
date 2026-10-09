#!/usr/bin/env bash
# WSL: all G9600 system apps with sizes (MiB) -> work/donor_G9600/app_sizes.txt
P=$(cd "$(dirname "$0")/../.." && pwd)
cd ~/s8rom/trees/g9600_root/system
du -sm app/* priv-app/* 2>/dev/null | sort -k2 > $P/work/donor_G9600/app_sizes.txt
wc -l < $P/work/donor_G9600/app_sizes.txt
