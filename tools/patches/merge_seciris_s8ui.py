#!/usr/bin/env python3
# Overlay the S8 (phone) SecIrisService UI onto the decoded T835 apk: layouts, drawables, anims, raw videos by name,
# and per-name dimen/color/bool/integer values. T835 code + strings stay. usage: merge_seciris_s8ui.py <s8 dir> <t835 dir>
import os, re, shutil, sys, xml.etree.ElementTree as ET
s8, t = sys.argv[1] + '/res', sys.argv[2] + '/res'
norm = lambda d: re.sub(r'-v(4|8|13)$', '', d)
copied = 0
for d in os.listdir(s8):
    if d.startswith('values'): continue
    td = os.path.join(t, norm(d)); os.makedirs(td, exist_ok=True)
    for f in os.listdir(os.path.join(s8, d)):
        base = os.path.splitext(f)[0]
        for old in os.listdir(td):          # drop same-name resource with another extension (webp vs png)
            if os.path.splitext(old)[0] == base and old != f: os.remove(os.path.join(td, old))
        shutil.copy(os.path.join(s8, d, f), os.path.join(td, f)); copied += 1
# tablet-only layout qualifiers the phone app never had: drop the files S8 has so phones use the S8 variants
for d in ('layout-h400dp-land', 'layout-h500dp-land'):
    p = os.path.join(t, d)
    if os.path.isdir(p):
        for f in os.listdir(p):
            if os.path.exists(os.path.join(s8, 'layout', f)): os.remove(os.path.join(p, f))
        if not os.listdir(p): os.rmdir(p)
merged = 0
for d in os.listdir(s8):
    if not d.startswith('values') or re.match(r'values-[a-z]{2}(-|$)', d) and not re.match(r'values-(sw|mdpi|xhdpi|night|land|nodpi)', d): continue
    for f in ('dimens.xml', 'colors.xml', 'bools.xml', 'integers.xml'):
        sp = os.path.join(s8, d, f)
        if not os.path.exists(sp): continue
        tp = os.path.join(t, norm(d), f); os.makedirs(os.path.dirname(tp), exist_ok=True)
        src = {e.get('name'): e for e in ET.parse(sp).getroot()}
        if os.path.exists(tp):
            tree = ET.parse(tp); root = tree.getroot()
        else:
            root = ET.Element('resources'); tree = ET.ElementTree(root)
        have = {e.get('name'): e for e in root}
        for n, e in src.items():
            if n in have:
                have[n].text = e.text; have[n].attrib.update(e.attrib)
            else:
                root.append(e)
            merged += 1
        tree.write(tp, encoding='utf-8', xml_declaration=True)
# phone wording: the T835 strings say "tablet" ("Hold tablet closer"...). Take the S8 string for every name both apps
# have, in every language the S8 app ships (default, en, en-rUS, ja, ko, pt-rBR, vi, zh-rCN); other languages keep
# the T835 text. Whole elements are replaced so <xliff:g> placeholders come along.
import copy
ET.register_namespace('xliff', 'urn:oasis:names:tc:xliff:document:1.2')
strings = 0
for d in os.listdir(s8):
    sp = os.path.join(s8, d, 'strings.xml'); tp = os.path.join(t, norm(d), 'strings.xml')
    if not d.startswith('values') or not os.path.exists(sp) or not os.path.exists(tp):
        continue
    src = {e.get('name'): e for e in ET.parse(sp).getroot() if e.tag == 'string'}
    tree = ET.parse(tp); root = tree.getroot()
    for i, e in enumerate(list(root)):
        if e.tag == 'string' and e.get('name') in src:
            root.remove(e); root.insert(i, copy.deepcopy(src[e.get('name')])); strings += 1
    tree.write(tp, encoding='utf-8', xml_declaration=True)
# T835-only strings (landscape / orientation hints) have no S8 version: swap the device word in English + Vietnamese
WORDS = {'values': [('tablets', 'phones'), ('tablet', 'phone'), ('Tablet', 'Phone')],
         'values-vi': [('máy tính bảng', 'điện thoại'), ('Máy tính bảng', 'Điện thoại')]}
WORDS['values-en'] = WORDS['values-en-rUS'] = WORDS['values-en-rGB'] = WORDS['values']
reworded = 0
for d, pairs in WORDS.items():
    tp = os.path.join(t, d, 'strings.xml')
    if not os.path.exists(tp):
        continue
    s = open(tp, encoding='utf-8').read(); n = s
    for a, b in pairs:
        n = n.replace(a, b)
    if n != s:
        open(tp, 'w', encoding='utf-8').write(n); reworded += 1
print(f'copied {copied} files, merged {merged} values, {strings} S8 strings, reworded {reworded} string files')
