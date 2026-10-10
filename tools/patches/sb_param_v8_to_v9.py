#!/usr/bin/env python3
"""SoundBooster parameters: stock S8 (v8, lib_SoundBooster_ver800) -> v9 layout (lib_SoundBooster_ver900).

usage: sb_param_v8_to_v9.py <S8 v8 SoundBoosterParam.txt> <S9 v9 template SoundBoosterParam.txt> <out>

Why: the S9 (G9600) system's AudioFlinger runs its own SoundBooster (libsamsungSoundbooster_plus_legacy ->
lib_SoundBooster_ver900) and reads /vendor/etc/SoundBoosterParam.txt, which holds the S8 v8 file for the S8 HAL.
v9 parsed the v8 lines -> misread speaker tuning on every output.

Layout (from the S9 and Tab S4 v9 files): a global S line, then four mode blocks A..D (speaker modes; the S8 has one
speaker, so all four get the same tuning). Per block X, the v8 line K becomes XK:
  H, F       + one trailing field (0)            L      + two trailing fields (from the template)
  MA..MP     multiband sections, v9 has one field fewer (the last one is dropped)
  AA.., CA.. biquad coefficient slots (42 values), v8 3 slots -> v9 8 slots (unused slots all 0)
  BA.., DA.. filter designs freq,Q,gain for those slots (unused slots: 700,200,-1 = the v9 files' placeholder)
  AM, CM     per-slot enable masks (padded with 0)       AU, CU unchanged
S line: v8 fields 0-4 -> v9 0-4, v8 5 -> v9 9, v8 6-7 -> v9 14-15, other fields from the template except
v9 field 13 = 0 (single speaker; 1 in the dual/quad speaker S9/Tab S4 files, 0 in the S8 One UI 2.5 port GalaxyOS).
The output has exactly the template's keys and field counts (checked).
"""
import sys


def load(path):
    keys, d = [], {}
    for line in open(path, encoding='latin-1').read().replace('\r', '').split('\n'):
        if line.strip():
            p = line.split(',')
            keys.append(p[0]); d[p[0]] = p[1:]
    return keys, d


v8keys, v8 = load(sys.argv[1])
tkeys, tpl = load(sys.argv[2])
if len(v8['S']) != 8 or 'AH' in v8:
    sys.exit('input is not a v8 file')

out = {}
s = list(tpl['S'])
for i8, i9 in ((0, 0), (1, 1), (2, 2), (3, 3), (4, 4), (5, 9), (6, 14), (7, 15)):
    s[i9] = v8['S'][i8]
s[13] = '0'
out['S'] = s

for blk in 'ABCD':
    def t(k):
        return tpl[blk + k]
    out[blk + 'H'] = v8['H'] + t('H')[len(v8['H']):]
    out[blk + 'H'][-1] = '0'
    out[blk + 'F'] = v8['F'] + ['0']
    out[blk + 'L'] = v8['L'] + t('L')[len(v8['L']):]
    for m in 'ABCDEFGHIJKLMNOP':
        out[blk + 'M' + m] = v8['M' + m][:len(t('M' + m))]
    for coef, design in (('A', 'B'), ('C', 'D')):
        mask = list(v8[coef + 'M'])
        for slot in 'ABCDEFGH':
            ck, dk = coef + slot, design + slot
            out[blk + ck] = v8[ck] if ck in v8 else ['0'] * len(t(ck))
            out[blk + dk] = v8[dk] if dk in v8 else ['700', '200', '-1']
        out[blk + coef + 'M'] = (mask + ['0'] * 8)[:len(t(coef + 'M'))]
        out[blk + coef + 'U'] = v8[coef + 'U']

bad = [k for k in tkeys if k not in out or len(out[k]) != len(tpl[k])] + [k for k in out if k not in tpl]
if bad:
    sys.exit('layout mismatch: ' + ' '.join(bad[:20]))
with open(sys.argv[3], 'w', newline='\r\n' if '\r\n' in open(sys.argv[2], encoding='latin-1', newline='').read() else '\n') as f:
    for k in tkeys:
        f.write(','.join([k] + out[k]) + '\n')
print(f'SoundBooster v8 -> v9: {len(tkeys)} lines, S={",".join(out["S"])}')
