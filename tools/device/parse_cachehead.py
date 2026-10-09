"""Parse the s8dbg kernel-log dump from a raw copy of the start of the 'cache' partition (cache_head.bin).
usage: python tools/device/parse_cachehead.py <cache_head.bin> [out_dir]"""
import os, re, sys

d = open(sys.argv[1], 'rb').read()
out = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.abspath(sys.argv[1]))
first = d[:256].split(b'\n')[0]
m = re.match(rb'S8DBGLOG (\d+) ?(.*)', first)
if not m:
    print('No S8DBGLOG header -> the reboot hook did not run (kernel panic / watchdog: check debugpart.img).')
    print('ext4 superblock intact:', d[0x438:0x43a] == b'\x53\xef')
    sys.exit(0)
n, cmd = int(m.group(1)), m.group(2).decode(errors='replace')
log = d[4096:4096 + n].decode('utf-8', 'replace')
open(os.path.join(out, 'kernel_log.txt'), 'w', encoding='utf-8').write(log)
print(f'reboot cmd: {cmd!r}   kernel log: {n:,} bytes -> kernel_log.txt')
keys = re.compile(r'init: .*(fail|error|crash|reboot|abort)|vold|cryptfs|encrypt|watchdog|Kernel panic|Unable to handle|'
                  r'BUG:|Oops|s8dbg|reboot|surfaceflinger|zygote|system_server|died|FATAL', re.I)
lines = log.splitlines()
hits = [l for l in lines if keys.search(l)]
print(f'\n==== {len(hits)} relevant lines (last 50) ====')
print('\n'.join(hits[-50:]))
print('\n==== last 30 lines ====')
print('\n'.join(lines[-30:]))
