#!/usr/bin/env bash
# One-time: key-based SSH from WSL to the build server, then print server specs.
# usage: SSH_PW=... bash tools/setup/setup_server_ssh.sh
set -e
. "$(dirname "$0")/../lib/env.sh"; HOST=${BUILD_HOST:?set BUILD_HOST in config/local.env}
command -v sshpass >/dev/null || { echo "$SUDO_PW" | sudo -S -p '' apt-get install -y -qq sshpass >/dev/null; }
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/id_ed25519
sshpass -p "$SSH_PW" ssh-copy-id -o StrictHostKeyChecking=accept-new -i ~/.ssh/id_ed25519.pub $HOST >/dev/null 2>&1
ssh -o BatchMode=yes $HOST 'echo "key auth OK on $(hostname)"; nproc; free -g | head -2; df -h ~ | tail -1; cat /etc/os-release | head -2;
  for t in git make gcc python3 python bc bison flex lz4 dtc cpio rsync debugfs simg2img; do printf "%s: " $t; command -v $t || echo MISSING; done;
  sudo -n true 2>/dev/null && echo SUDO_NOPASS || echo SUDO_NEEDS_PASSWORD'
