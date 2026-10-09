#!/usr/bin/env bash
# Run from WSL: push project tools + configs to the build server and execute a command there.
# usage: bash tools/setup/remote.sh setup            -> one-time server setup
#        bash tools/setup/remote.sh kernel           -> build kernel on the server, pull Image.gz back
#        bash tools/setup/remote.sh run '<cmd>'      -> arbitrary command in ~/s8rom
set -e
. "$(dirname "$0")/../lib/env.sh"; HOST=${BUILD_HOST:?set BUILD_HOST in config/local.env}
P=$S8PORT
ssh $HOST 'mkdir -p ~/s8rom/tools ~/s8rom/work ~/s8rom/config'
rsync -a $P/tools/ $HOST:s8rom/tools/
rsync -a --exclude local.env $P/config/ $HOST:s8rom/config/
case "$1" in
  setup)  ssh $HOST 'bash ~/s8rom/tools/setup/server_setup.sh' ;;
  kernel)
    rsync -a $P/work/stock_CZE1/boot.img_unpacked/kernel.config $HOST:s8rom/work/stock_kernel.config
    ssh $HOST 'CFG=~/s8rom/work/stock_kernel.config OUTCFG=~/s8rom/work/dream_q.config bash ~/s8rom/tools/kernel/build_kernel.sh'
    mkdir -p $P/out/kernel
    rsync -a $HOST:s8rom/kernel/out_dream/arch/arm64/boot/Image.gz $HOST:s8rom/work/dream_q.config $P/out/kernel/
    rsync -a $HOST:s8rom/kernel/out_dream/build.log $P/out/kernel/
    # keep the local copy of our kernel changes in sync with the server tree (kernel/patches/<branch>.diff)
    ssh $HOST 'cd ~/s8rom/kernel/t830_q && git diff Q-r1 HEAD' > $P/kernel/patches/$(ssh $HOST 'cd ~/s8rom/kernel/t830_q && git rev-parse --abbrev-ref HEAD').diff ;;
  run)    shift; ssh $HOST "cd ~/s8rom && $*" ;;
esac
