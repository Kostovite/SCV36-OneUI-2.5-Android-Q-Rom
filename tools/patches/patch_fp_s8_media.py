#!/usr/bin/env python3
# Swap the S9 fingerprint-enroll guide media in the G9600 BiometricSetting.apk for the S8's own (stock S8 Pie
# SecSettings): res/raw/sec_fingerprint_{v,h}_0{1,2}.mp4 (the S8 shipped only v_*; its h_* are 119-byte stubs, so
# h_* get the S8 v_* too) and assets/sec_fingerprint_enroll_animation_expand.json. Same entry names -> no
# resources.arsc change; entries keep their compression (raw mp4s stay stored), original META-INF is kept
# (Q does not verify content of /system apps). zipalign -p 4 afterwards.
# usage: patch_fp_s8_media.py <G9600 BiometricSetting.apk> <S8 Pie SecSettings.apk> <out apk>
import sys, zipfile
src, s8, out = sys.argv[1:4]
z8 = zipfile.ZipFile(s8)
v1 = z8.read('res/raw/sec_fingerprint_v_01.mp4'); v2 = z8.read('res/raw/sec_fingerprint_v_02.mp4')
repl = {'res/raw/sec_fingerprint_v_01.mp4': v1, 'res/raw/sec_fingerprint_h_01.mp4': v1,
        'res/raw/sec_fingerprint_v_02.mp4': v2, 'res/raw/sec_fingerprint_h_02.mp4': v2,
        'assets/sec_fingerprint_enroll_animation_expand.json': z8.read('assets/sec_fingerprint_enroll_animation_expand.json')}
zi = zipfile.ZipFile(src)
with zipfile.ZipFile(out, 'w') as zo:
    for e in zi.infolist():
        data = repl.pop(e.filename, None)
        if data is None: data = zi.read(e.filename)
        else: print('fp-media: replaced', e.filename, len(data))
        n = zipfile.ZipInfo(e.filename, e.date_time); n.compress_type = e.compress_type; n.external_attr = e.external_attr
        zo.writestr(n, data)
if repl: sys.exit('fp-media: entries not found: %s' % ', '.join(repl))
