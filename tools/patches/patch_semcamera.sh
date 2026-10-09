#!/usr/bin/env bash
# WSL: patch the One UI 2 (G9600) framework semcamera.jar for the S8 HAL1 camera stack.
# The S8 SamsungCamera 9.0 activates its shooting mode (UI, shutter, mode switch) only after
# SemCamera.CommonEventListener.onPreviewStarted(), i.e. the notify message COMMON_SHOT_PREVIEW_STARTED (0xf412) that
# it requests with sendCommand(1473 REQUEST_NOTIFY_PREVIEW_STARTED) right before startPreview(). The S8 Pie QCamera2
# HAL never sends 0xf412 (only 0xf411; on Pie the Samsung cameraserver produced it) -> preview runs, but the app stays
# "Shooting mode is not activated" = frozen UI (boot 22).
# -> setPreviewStartedCallbackEnabled(true) also posts 0xf412 to SemCamera's own event handler after 1 s (the app's
#    base menu is ready ~0.65 s after startPreview on a cold start; the event is a no-op before that).
# usage: patch_semcamera.sh <in semcamera.jar> <out semcamera.jar>
set -e
IN=$1; OUT=$2; TB=~/s8rom/tools_bin; W=$(mktemp -d)
cd $W; cp "$IN" in.jar; unzip -q in.jar classes.dex
java -jar $TB/baksmali.jar d classes.dex -o smali
F=smali/com/samsung/android/camera/core/SemCamera.smali
python3 - $F <<'PY'
import re, sys
f = sys.argv[1]; s = open(f).read()
m = re.search(r'(\.method public setPreviewStartedCallbackEnabled\(Z\)V\n)(.*?)(\.end method)', s, re.S)
assert m, 'setPreviewStartedCallbackEnabled not found'
body = m.group(2)
assert 'S8 port' not in body
loc = re.search(r'\.(locals|registers) (\d+)', body)   # need v0-v3 (+ p0, p1 for .registers)
n = int(loc.group(2))
body = body.replace(loc.group(0), '.locals %d' % max(4, n) if loc.group(1) == 'locals' else '.registers %d' % max(6, n), 1)
rets = body.count('return-void'); assert rets == 1, 'return-void count %d' % rets
inject = '''    # S8 port: the S8 HAL never sends COMMON_SHOT_PREVIEW_STARTED -> post it ourselves
    if-eqz p1, :s8_done
    iget-object v0, p0, Lcom/samsung/android/camera/core/SemCamera;->mEventHandler:Lcom/samsung/android/camera/core/SemCamera$EventHandler;
    if-eqz v0, :s8_done
    const v1, 0xf412
    invoke-virtual {v0, v1}, Landroid/os/Handler;->removeMessages(I)V
    invoke-virtual {v0, v1}, Landroid/os/Handler;->obtainMessage(I)Landroid/os/Message;
    move-result-object v1
    const-wide/16 v2, 0x3e8
    invoke-virtual {v0, v1, v2, v3}, Landroid/os/Handler;->sendMessageDelayed(Landroid/os/Message;J)Z
    :s8_done
    return-void'''
body = body.replace('    return-void', inject)
s = s[:m.start(2)] + body + s[m.end(2):]
open(f, 'w').write(s); print('patched setPreviewStartedCallbackEnabled')
PY
grep -q 'mEventHandler:Lcom/samsung/android/camera/core/SemCamera$EventHandler;' $F
java -jar $TB/smali.jar a smali -o classes.dex --api 29
# dex stored uncompressed (no odex/vdex shipped for it any more: the installer removes the stale G9600 ones)
cp in.jar out.jar; zip -q -0 out.jar classes.dex
zipalign -f 4 out.jar "$OUT" 2>/dev/null || cp out.jar "$OUT"
cd /; rm -rf $W
unzip -lv "$OUT" | grep classes.dex
