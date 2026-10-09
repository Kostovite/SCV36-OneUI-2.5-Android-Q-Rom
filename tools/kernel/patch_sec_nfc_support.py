#!/usr/bin/env python3
"""Kernel patch (server tree): add /sys/class/nfc/nfc_support to the S8 sec_nfc driver.
The One UI 2 (G9600) NfcService checks that file and otherwise logs "NFC Kernel Driver doesn't exist!!" and never
brings the chip up ("Nfc need bringup!!"). Later Samsung kernels create it; the S8-era driver does not.
usage: python3 patch_sec_nfc_support.py <kernel tree>"""
import sys

f = sys.argv[1] + '/drivers/nfc/sec_nfc.c'
s = open(f).read()
if 'nfc_support' in s:
    print('already patched'); sys.exit(0)
old = '''static int __init sec_nfc_init(void)
{
	return SEC_NFC_INIT(&sec_nfc_driver);
}'''
new = '''/* One UI 2 NfcService requires /sys/class/nfc/nfc_support (newer Samsung kernels) */
static struct class *sec_nfc_support_class;

static ssize_t nfc_support_show(struct class *class, struct class_attribute *attr, char *buf)
{
	return snprintf(buf, PAGE_SIZE, "1\\n");
}
static CLASS_ATTR(nfc_support, 0444, nfc_support_show, NULL);

static int __init sec_nfc_init(void)
{
	sec_nfc_support_class = class_create(THIS_MODULE, "nfc");
	if (IS_ERR(sec_nfc_support_class))
		pr_err("nfc class create failed: %ld\\n", PTR_ERR(sec_nfc_support_class));
	else if (class_create_file(sec_nfc_support_class, &class_attr_nfc_support))
		pr_err("nfc_support attribute create failed\\n");
	return SEC_NFC_INIT(&sec_nfc_driver);
}'''
assert old in s, 'sec_nfc_init not found'
s = s.replace(old, new)
open(f, 'w').write(s)
print('patched', f)
