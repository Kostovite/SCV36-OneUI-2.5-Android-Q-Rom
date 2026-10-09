#!/usr/bin/env bash
# Runs ON the build server: keep both S8 kernel variants as git branches in ~/s8rom/kernel/t830_q.
#   s8-pie-test : APR fix + s8dbg + Pie KGSL transplant (boots the stock S8 Android 9 system)
#   s8-q-port   : APR fix + s8dbg, original Q KGSL (matches the Tab S4 Android 10 graphics blobs in the port vendor)
set -e
cd ~/s8rom/kernel/t830_q
git config user.email >/dev/null || git config user.email "s8rom@localhost"
git config user.name  >/dev/null || git config user.name  "s8rom"
if ! git rev-parse --verify -q s8-pie-test >/dev/null; then
  git checkout -q -b s8-pie-test
  git add -A && git commit -q -m "S8 test kernel: APR legacy init, s8dbg reboot hook, Pie KGSL transplant"
fi
if ! git rev-parse --verify -q s8-q-port >/dev/null; then
  git checkout -q -b s8-q-port s8-pie-test
  git checkout -q HEAD~1 -- drivers/gpu/msm      # Q KGSL as shipped (before the transplant commit)
  git commit -q -m "One UI 2 port kernel: restore Q KGSL for the Tab S4 Q graphics blobs" || true
fi
git checkout -q ${1:-s8-q-port}
find drivers/gpu/msm -type f -exec touch {} +
echo "on branch $(git rev-parse --abbrev-ref HEAD): $(git log --oneline -3 | tr '\n' ';')"
git diff --stat s8-pie-test s8-q-port | tail -1
