#!/usr/bin/env bash
# WSL: patch the One UI 2 (G9600) services.jar so Secure Folder can be created on this Knox-tripped (warranty 0x1)
# device. Same approach as KnoxPatch (GPL-3.0, salvogiangri) SystemHooks.applyTIMAHooks for One UI 1.x/2.x, as a
# static patch - ONLY the Secure Folder part. KnoxPatch's KnoxGuard and ASKS hooks are deliberately NOT applied.
#
# The e-fuse is enforced in TrustZone: after the trip the TIMA trustlet reports "unavailable" and the keymaster TA
# refuses Samsung's Knox-protected keys. PersonaManagerService / SdpManagerService gate container (Secure Folder)
# creation on exactly those two probes:
#   com.android.server.pm.PersonaServiceHelper.isTimaAvailable(Context)          -> TimaHelper.isTimaAvailable()
#   com.android.server.SdpManagerService$LocalService.isKnoxKeyInstallable()      -> installKnoxKey("KnoxTestKey")
# Both are forced to true. (SyntheticPasswordManager.isUnifiedKeyStoreSupported, KnoxPatch's third hook, already
# returns true here: the port's floating_feature has SEC_FLOATING_FEATURE_KNOX_SUPPORT_UKS=TRUE.)
# Nothing reads ro.boot.warranty_bit in framework.jar/services.jar on this build.
# The installer must drop the stale services odex/vdex/art (system/framework/oat/*/services.*).
# usage: patch_knox_securefolder.sh <in services.jar> <out services.jar>
set -e
IN=$1; OUT=$2; TB=~/s8rom/tools_bin; W=$(mktemp -d)
cd $W; cp "$IN" in.jar; unzip -q in.jar 'classes*.dex'
python3 - $W <<'PY'
import os, re, subprocess, sys
W = sys.argv[1]; TB = os.path.expanduser('~/s8rom/tools_bin')
targets = {
    'com/android/server/pm/PersonaServiceHelper.smali': 'isTimaAvailable(Landroid/content/Context;)Z',
    'com/android/server/SdpManagerService$LocalService.smali': 'isKnoxKeyInstallable()Z',
}
done = {}
for dex in sorted(f for f in os.listdir(W) if re.fullmatch(r'classes\d*\.dex', f)):
    out = os.path.join(W, 'sm_' + dex[:-4])
    subprocess.run(['java', '-jar', TB + '/baksmali.jar', 'd', '--api', '29', os.path.join(W, dex), '-o', out], check=True)
    hit = False
    for rel, sig in targets.items():
        p = os.path.join(out, rel)
        if not os.path.exists(p):
            continue
        s = open(p).read()
        m = re.search(r'(\.method [^\n]*' + re.escape(sig) + r'\n)(.*?)(\.end method)', s, re.S)
        assert m, 'method %s not found in %s' % (sig, rel)
        assert 'S8 port' not in m.group(2), 'already patched'
        body = '    .registers %d\n    # S8 port (Knox 0x1): Secure Folder probe forced true, see tools/patches/patch_knox_securefolder.sh\n    const/4 v0, 0x1\n    return v0\n' \
               % (2 if 'Context' in sig else 2)
        s = s[:m.start(2)] + body + s[m.end(2):]
        open(p, 'w').write(s)
        done[rel] = dex; hit = True
        print('patched', sig, 'in', dex)
    if hit:
        subprocess.run(['java', '-jar', TB + '/smali.jar', 'a', '--api', '29', out, '-o', os.path.join(W, dex)], check=True)
missing = set(targets) - set(done)
assert not missing, 'not found: %s' % missing
PY
cp in.jar out.jar
zip -q -0 out.jar classes*.dex          # (stored, like the original; zipalign below)
if command -v zipalign >/dev/null; then zipalign -f -p 4 out.jar "$OUT"; else cp out.jar "$OUT"; fi
cd /; rm -rf $W
echo "knox: $OUT"
