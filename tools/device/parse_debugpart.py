"""Parse a dump of Samsung's 'debug' partition (msm8998 layout from include/linux/qcom/sec_debug_partition.h).
usage: python tools/device/parse_debugpart.py <debugpart.img> [out_dir]
Writes klog.txt (kernel log saved at reset), summary.txt, tzlog.txt and prints the crash-relevant tail."""
import os, re, sys

KLOG_OFF, KLOG_SIZE = 0x100000, 0x200000 - 0xC
SUMMARY_OFF, SUMMARY_SIZE = KLOG_OFF + 0x200000, 0x200000
TZLOG_OFF, TZLOG_SIZE = SUMMARY_OFF + SUMMARY_SIZE, 0x40000

img = open(sys.argv[1], 'rb').read()
out = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(sys.argv[1]))

def text(off, size):
    raw = img[off:off + size]
    return re.sub(rb'[^\x09\x0a\x20-\x7e]', b'', raw.replace(b'\x00', b'')).decode('ascii', 'replace')

print('reset header (first 64 bytes):', img[:64].hex())
parts = {'klog': (KLOG_OFF, KLOG_SIZE), 'summary': (SUMMARY_OFF, SUMMARY_SIZE), 'tzlog': (TZLOG_OFF, TZLOG_SIZE)}
for name, (off, size) in parts.items():
    t = text(off, size)
    open(os.path.join(out, f'{name}.txt'), 'w', encoding='utf-8').write(t)
    print(f'{name}: {len(t):,} chars of text')

klog = open(os.path.join(out, 'klog.txt'), encoding='utf-8').read().splitlines()
keys = re.compile(r'Kernel panic|Attempted to kill init|Unable to handle|Internal error|BUG:|Call trace|PC is at|LR is at|'
                  r'init: |FATAL|Aborting|SELinux:  *(Could not|Failed)|avc:  *denied|watchdog|bark|bite|s8dbg|'
                  r'reboot|panic', re.I)
hits = [l for l in klog if keys.search(l)]
print(f'\n==== {len(hits)} crash-relevant klog lines (last 60) ====')
print('\n'.join(hits[-60:]))
print('\n==== klog tail (last 40 lines) ====')
print('\n'.join(klog[-40:]))
