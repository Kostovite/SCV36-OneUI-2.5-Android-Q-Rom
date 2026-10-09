#!/usr/bin/env bash
# WSL: make our SCV36 TWRP always come up with adb (no MTP): every USB mode TWRP asks for (mtp, mtp,adb, adb) builds
# the adb-only configfs gadget, and sys.usb.config=adb is set at boot -> adb works without touching the screen.
# usage: bash tools/build/twrp_adb_default.sh <in recovery.img> <out recovery.img>
set -e
IN=$(realpath "$1"); OUT=$(realpath -m "$2")
MB=~/s8rom/twrp/magiskboot
W=$(mktemp -d ~/twrpadb_XXXX); cd $W
$MB unpack -h "$IN" >/dev/null 2>&1
$MB cpio ramdisk.cpio "extract init.recovery.usb.rc usb.rc" >/dev/null 2>&1
python3 - usb.rc <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
if 'S8PORT adb-only' in s: print('already patched'); sys.exit(0)
adb_bind = """    write /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration "adb"
    rm /config/usb_gadget/g1/configs/b.1/f1
    rm /config/usb_gadget/g1/configs/b.1/f2
    rm /config/usb_gadget/g1/configs/b.1/f3
    rm /config/usb_gadget/g1/configs/b.1/f4
    rm /config/usb_gadget/g1/configs/b.1/f5
    write /config/usb_gadget/g1/idVendor 0x18d1
    write /config/usb_gadget/g1/idProduct 0x4ee7
    symlink /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f1
    write /config/usb_gadget/g1/UDC ${sys.usb.controller}
    setprop sys.usb.state ${sys.usb.config}
"""
# replace the mtp and mtp,adb blocks (up to the next blank line / EOF) with adb-only equivalents
def repl(trigger, body):
    global s
    m = re.search(r'^on ' + re.escape(trigger) + r'\n(?:    .*\n?)*', s, re.M)
    assert m, trigger
    s = s[:m.start()] + 'on ' + trigger + '\n' + body + s[m.end():]
repl('property:sys.usb.config=mtp', '    start adbd\n')
repl('property:sys.usb.ffs.ready=1 && property:sys.usb.config=mtp,adb', adb_bind)
s += """
# S8PORT adb-only: TWRP's MTP gadget never brought adb up on the SCV36 -> mtp/mtp,adb behave as adb
on property:sys.usb.ffs.ready=1 && property:sys.usb.config=mtp
""" + adb_bind + """
on boot
    setprop sys.usb.config adb
"""
open(p, 'w').write(s); print('patched')
EOF
$MB cpio ramdisk.cpio "add 0750 init.recovery.usb.rc usb.rc" >/dev/null 2>&1
$MB repack "$IN" new.img >/dev/null 2>&1
grep -q SEANDROIDENFORCE new.img || printf 'SEANDROIDENFORCE' >> new.img
cp new.img "$OUT"
$MB cpio ramdisk.cpio "extract init.recovery.usb.rc chk.rc" >/dev/null 2>&1; grep -c 'S8PORT adb-only' chk.rc
echo "-> $OUT ($(stat -c %s "$OUT") bytes)"
cd ~ && rm -rf -- "$W"
