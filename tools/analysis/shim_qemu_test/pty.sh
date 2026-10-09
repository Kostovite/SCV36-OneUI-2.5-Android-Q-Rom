R=~/shimtest/real/root; cd $R
timeout -s KILL 40 script -qfc "setarch $(uname -m) -R unshare -Urpf --mount-proc qemu-arm -L $R $R/system/bin/linker $R/data/test real" /dev/null > ~/p.txt 2>&1
tr -d '\r' < ~/p.txt | head -20
