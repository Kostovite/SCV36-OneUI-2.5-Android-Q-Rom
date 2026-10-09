#!/usr/bin/env bash
# WSL (boot 9): USB gadget / conn_gadget init triggers and usb props, port vendor vs S8 Pie vs G9600.
V=~/s8rom/port/vendor; S8=~/s8rom/trees/s8_vendor/vendor; S8S=~/s8rom/trees/s8_system; G=~/s8rom/trees/g9600_root
echo "== kernel usb gadget config"; grep -E 'CONFIG_USB_(CONFIGFS|G_ANDROID|ANDROID|DWC3|GADGET)=|CONFIG_USB_CONFIGFS_|CONFIG_USB_F_' ~/s8rom/kernel/out_dream/.config | head -40
echo "== usb rc files: port vendor"; ls $V/etc/init/hw | grep -i usb; grep -rln 'sys.usb' $V/etc/init | head
echo "== usb rc: g9600 system root"; ls $G | grep -i usb; ls $G/system/etc/init | grep -i usb
echo "== S8 pie usb rc"; find $S8 $S8S -name '*usb*rc' | head; ls ~/s8rom/trees/s9_root 2>/dev/null | grep -i usb
echo "== sys.usb.controller / configfs props"; grep -rh -E 'sys.usb.controller|sys.usb.configfs|usb.udc' $V/etc/init $V/build.prop $V/default.prop $G/system/build.prop 2>/dev/null | sort | uniq | head -20
