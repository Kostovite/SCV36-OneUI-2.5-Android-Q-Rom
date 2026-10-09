#!/usr/bin/env bash
# Install build dependencies on the WSL Debian host. usage: SUDO_PW=... bash tools/setup/setup_host.sh
set -e
S() { echo "$SUDO_PW" | sudo -S -p '' "$@"; }
S apt-get update -qq
S env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  bc bison flex lz4 clang lld libssl-dev cpio zip unzip device-tree-compiler python3-pip \
  android-sdk-libsparse-utils e2fsprogs xxd
bash "$(dirname "$0")/check_host.sh"
