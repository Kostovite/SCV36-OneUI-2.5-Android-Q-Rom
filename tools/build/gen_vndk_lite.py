"""Fill AOSP Android 10 ld.config.vndk_lite.txt for the S8 (VNDK-lite Pie vendor) on the G9600 Q system.
Placeholder values are recovered by aligning the AOSP ld.config.txt template with Samsung's generated ld.config.29.txt.
usage: python tools/build/gen_vndk_lite.py   -> config/vndk_lite/ld.config.vndk_lite.txt.filled"""
import re
D = 'config/vndk_lite/'
tmpl = open(D + 'aosp_ld.config.template.txt').read().splitlines()
gen = open(D + 'g9600_ld.config.29.txt').read().splitlines()
vals = {}
gi = 0
for t in tmpl:
    m = re.search(r'%([A-Z_]+)%', t)
    if not m:
        continue
    pre = t[:m.start()]
    # find the next generated line with the same prefix
    for j in range(gi, len(gen)):
        if gen[j].startswith(pre) and pre.strip():
            post = t[m.end():]
            v = gen[j][len(pre):len(gen[j]) - len(post) if post else None]
            vals.setdefault(m.group(1), v)
            gi = j + 1
            break
vals['VNDK_VER'] = '-28'                     # vendor VNDK version
vals['VNDK_SAMEPROCESS_LIBRARIES'] = ':'.join(l.strip() for l in open(D + 'vndksp.libraries.28.txt') if l.strip())
# template alignment is unreliable for these (Samsung's ld.config.29.txt differs) -> set from known values
vals['PRODUCT'] = 'product'
vals['PRODUCT_SERVICES'] = 'product_services'
sph = [l for l in gen if l.startswith('namespace.sphal.link.default.shared_libs +=') and 'clang_rt' in l]
vals['SANITIZER_RUNTIME_LIBRARIES'] = sph[0].split('+=', 1)[1].strip()
vals['LLNDK_LIBRARIES'] = ':'.join(l.strip() for l in open(D + 'llndk.libraries.29.txt') if l.strip())
vals.setdefault('PRIVATE_LLNDK_LIBRARIES', '')
for k, v in sorted(vals.items()):
    print(f'{k:28} {len(v.split(":")) if v else 0:3} entries  {v[:90]}')
out = open(D + 'ld.config.vndk_lite.txt').read()
for k, v in vals.items():
    out = out.replace(f'%{k}%', v)
left = set(re.findall(r'%[A-Z_]+%', out))
assert not left, f'unfilled: {left}'
open(D + 'ld.config.vndk_lite.txt.filled', 'w', newline='\n').write(out)
print('written', D + 'ld.config.vndk_lite.txt.filled')
