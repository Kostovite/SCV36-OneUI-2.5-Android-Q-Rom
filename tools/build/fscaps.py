#!/usr/bin/env python3
"""Decode Android fs_config_files (binary: struct fs_path_config_from_file) and list entries with capabilities.
usage: fscaps.py <fs_config_files> [--all]"""
import struct, sys
d = open(sys.argv[1], 'rb').read()
CAPS = {0:'CHOWN',1:'DAC_OVERRIDE',2:'DAC_READ_SEARCH',3:'FOWNER',4:'FSETID',5:'KILL',6:'SETGID',7:'SETUID',8:'SETPCAP',
        10:'NET_BIND_SERVICE',11:'NET_BROADCAST',12:'NET_ADMIN',13:'NET_RAW',14:'IPC_LOCK',21:'SYS_ADMIN',23:'SYS_NICE',
        24:'SYS_RESOURCE',25:'SYS_TIME',27:'MKNOD',33:'AUDIT_CONTROL',35:'WAKE_ALARM',36:'BLOCK_SUSPEND',34:'MAC_ADMIN',30:'AUDIT_WRITE'}
o = 0
while o + 16 <= len(d):
    ln, mode, uid, gid, caps = struct.unpack_from('<HHHHQ', d, o)
    if ln < 16: break
    path = d[o+16:o+ln].split(b'\0')[0].decode()
    o += ln
    if caps or '--all' in sys.argv:
        names = [CAPS.get(i, str(i)) for i in range(64) if caps >> i & 1]
        print(f'{path:60s} uid={uid} gid={gid} mode={mode:o} caps={caps:#x} {"|".join(names)}')
