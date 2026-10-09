#!/usr/bin/env python3
"""Print full node paths in a decompiled .dts whose node name matches a regex. usage: dts_paths.py <file.dts> <regex>"""
import re, sys
pat = re.compile(sys.argv[2]); stack = []
for line in open(sys.argv[1]):
    s = line.strip()
    m = re.match(r'^(?:[\w,.-]+:\s*)?([\w,.@+-]+|/)\s*\{$', s)
    if m:
        stack.append(m.group(1))
        if pat.search(m.group(1)):
            print('/' + '/'.join(stack[1:]))
    elif s.startswith('};'):
        stack.pop()
