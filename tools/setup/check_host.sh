#!/usr/bin/env bash
# Report which build tools are available on the WSL build host.
for t in debugfs e2fsck bc bison flex lz4 clang ld.lld dtc simg2img img2simg zip unzip cpio git make gcc python3; do
  printf '%-10s ' "$t"; command -v "$t" || echo MISSING
done
