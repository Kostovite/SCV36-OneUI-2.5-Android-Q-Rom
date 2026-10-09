#!/usr/bin/env bash
# WSL (SUDO_PW): mount the built port system image read-only and run a python check against it.
# usage: SUDO_PW=... bash tools/analysis/inspect_image.sh tools/build/check_property_contexts.py [args]
P=$(cd "$(dirname "$0")/../.." && pwd); M=~/s8rom/port/mnt_ro
S() { echo "$SUDO_PW" | sudo -S -p '' "$@"; }
mkdir -p $M; mountpoint -q $M && S umount $M
S mount -o loop,ro ~/s8rom/port/system.img $M
S python3 $P/$1 $M "${@:2}"
S umount $M
