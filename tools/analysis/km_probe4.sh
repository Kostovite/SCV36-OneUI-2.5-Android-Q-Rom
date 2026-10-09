#!/usr/bin/env bash
# WSL (boot 5): hal_keymaster rules and attributes in the port vendor cil.
P=~/s8rom/port/vendor
echo "== port vendor cil: hal_keymaster_default / hal_keymaster rules"
grep -h -E 'hal_keymaster_default|\(allow hal_keymaster ' $P/etc/selinux/vendor_sepolicy.cil | grep -v typeattributeset | head -40
echo "== typeattributeset containing hal_keymaster_default"
grep -h -oE '\(typeattributeset [a-z_0-9]+ \([^)]*\bhal_keymaster_default\b' $P/etc/selinux/vendor_sepolicy.cil | awk '{print $2}'
echo "== hal_keymaster_server membership"; grep -h -E '\(typeattributeset hal_keymaster_server' $P/etc/selinux/vendor_sepolicy.cil
echo "== S8 pie policy files"; find ~/s8rom/trees/s8_vendor ~/s8rom/trees/s8_system -name '*.cil' | head
