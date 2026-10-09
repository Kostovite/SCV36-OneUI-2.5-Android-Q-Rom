#!/usr/bin/env bash
# WSL: release boot.img = a template boot image (e.g. the phone's current Magisk-patched boot, dumped with dd) with
# the kernel replaced by out/kernel/Image.gz and the debug options removed from the cmdline. Ramdisk, DTB, header
# fields and the SEANDROIDENFORCE footer come from the template (magiskboot), so Magisk stays installed.
# usage: make_release_boot.sh <template boot.img> <out boot.img> [Image.gz]
# cmdline: drops "s8dbg.recovery msm_poweroff.s8dbg_timeout=N log_buf_len=N" (debug kernel only) and replaces
# msm_rtb.filter=... with msm_rtb.enable=0 (Qualcomm register trace buffer logs every MMIO access otherwise).
# Magisk's Samsung kernel hexpatches (RKP / DEFEX / PROCA) are re-applied; they are no-ops on our kernel config.
set -e
P=$(cd "$(dirname "$0")/../.." && pwd)
IN=$(realpath "$1"); OUT=$(realpath -m "$2"); IMG=$(realpath "${3:-$P/out/kernel/Image.gz}")
MB=${S8ROM:-$HOME/s8rom}/twrp/magiskboot
WD=$(mktemp -d ${S8ROM:-$HOME/s8rom}/relboot_XXXX); cd "$WD"
cp "$MB" ./magiskboot
./magiskboot unpack -h "$IN" >/dev/null 2>&1
gzip -dc "$IMG" > kernel
./magiskboot hexpatch kernel \
  49010054011440B93FA00F71E9000054010840B93FA00F7189000054001840B91FA00F7188010054 \
  A1020054011440B93FA00F7140020054010840B93FA00F71E0010054001840B91FA00F7181010054 2>/dev/null || true
./magiskboot hexpatch kernel 821B8012 E2FF8F12 2>/dev/null || true
./magiskboot hexpatch kernel 70726F63615F636F6E66696700 70726F63615F6D616769736B00 2>/dev/null || true
sed -i -E -e 's/ s8dbg\.recovery//; s/ msm_poweroff\.s8dbg_timeout=[0-9]+//; s/ log_buf_len=[0-9]+[KMG]?//' \
  -e 's/msm_rtb\.filter=0x[0-9a-fA-F]+/msm_rtb.enable=0/' header
grep '^cmdline=' header
./magiskboot repack "$IN" new.img >/dev/null 2>&1
cp new.img "$OUT"; sha1sum "$OUT"
cd ~ && rm -rf -- "$WD"
