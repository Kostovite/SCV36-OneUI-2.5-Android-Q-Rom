#!/usr/bin/env python3
"""Patch Firefox Reality (MozillaReality/FirefoxReality, final tree bc6f43f6, MPL-2.0) into a Gear VR build.

Gear VR runs the Oculus Mobile VrApi runtime from com.oculus.systemdriver 9.0 = VrApi 1.1.26 (Apr 2020). Its
DriverLoader rejects any app whose loader/init parms request a newer API (FR 12 asks 1.1.35 -> "incompatible").
third_party/ovr_mobile is assembled by build_fxr_gearvr.sh: VrApi headers from the 1.32 SDK mirror with
VRAPI_MINOR_VERSION pinned to 26, and the genuine 1.1.26 libvrapi.so loader (from FR 7.1's apk).

This adds a 'gearvr' product flavor (VrApi only: no OpenXR, no Oculus Platform SDK, not a store build, 3DoF) and:
  - compiles out the Oculus Platform SDK (platform init / store entitlement / launch-intent messages): those
    services are gone for Gear VR and an open-source build has no store entitlement anyway;
  - calls vrapi_PollEvent (VrApi >= 1.1.29, not exported by the 1.26 loader) only if the runtime has it; without it
    the app keeps hasEventFocus = true (pre-1.29 behaviour);
  - Kryo 280 (Cortex-A73/A53) tuned native flags for the gearvr flavor.
usage: patch_fxr_gearvr.py <FirefoxReality checkout>
"""
import re, sys, os

root = sys.argv[1]
def rd(p): return open(os.path.join(root, p)).read()
def wr(p, s): open(os.path.join(root, p), 'w').write(s)
def once(s, old, new, what):
    n = s.count(old)
    assert n == 1, '%s: expected 1 match, found %d' % (what, n)
    return s.replace(old, new)

MARK = 'GEARVR_NO_OVR_PLATFORM'

# ---- DeviceDelegateOculusVR.cpp -------------------------------------------------------------------------------
p = 'app/src/oculusvr/cpp/DeviceDelegateOculusVR.cpp'
s = rd(p)
if MARK not in s:
    s = once(s, '#include "OVR_Platform.h"\n#include "OVR_Message.h"\n',
             '#ifndef GEARVR_NO_OVR_PLATFORM\n#include "OVR_Platform.h"\n#include "OVR_Message.h"\n#endif\n'
             '#include <dlfcn.h>\n', 'platform includes')
    # platform init + entitlement request
    m = re.search(r'\n(    if \(!ovr_IsPlatformInitialized\(\)\) \{\n.*?\n    \} else if \(!applicationEntitled\) \{\n'
                  r'      ovr_Entitlement_GetIsViewerEntitled\(\);\n    \}\n)', s, re.S)
    assert m, 'platform init block'
    s = s[:m.start(1)] + '#ifndef GEARVR_NO_OVR_PLATFORM\n' + m.group(1) + \
        '#else\n    applicationEntitled = true;  // Gear VR build: no Oculus Platform services\n#endif\n' + s[m.end(1):]
    # message pump
    m = re.search(r'\n(  ovrMessageHandle message;\n  while \(\(message = ovr_PopMessage\(\)\) != nullptr\) \{\n.*?\n  \}\n)\}\n', s, re.S)
    assert m, 'message pump'
    s = s[:m.start(1)] + '#ifndef GEARVR_NO_OVR_PLATFORM\n' + m.group(1) + '#endif\n' + s[m.end(1):]
    # Quest 2 device-type range is newer than the 1.32 headers (and irrelevant on Gear VR)
    s = once(s, '    } else if ((type >= VRAPI_DEVICE_TYPE_OCULUSQUEST2_START) && (type <= VRAPI_DEVICE_TYPE_OCULUSQUEST2_END)) {\n'
                '        VRB_DEBUG("Detected Oculus Quest 2");\n        deviceType = device::OculusQuest;\n',
             '', 'Quest 2 branch')
    # vrapi_PollEvent only when the runtime exports it (VrApi >= 1.1.29)
    s = once(s, '  while (vrapi_PollEvent(eventHeader) == ovrSuccess) {\n',
             '  typedef ovrResult (*PollEventFn)(ovrEventHeader*);\n'
             '  static PollEventFn pollEvent = (PollEventFn) dlsym(RTLD_DEFAULT, "vrapi_PollEvent");\n'
             '  while (pollEvent && pollEvent(eventHeader) == ovrSuccess) {\n', 'PollEvent')
    wr(p, s); print('patched', p)

# ---- OculusVRLayers.cpp: vrapi_GetCenterViewMatrix was dropped from VrApi_Helpers.h after 1.1.2x ----------------
p = 'app/src/oculusvr/cpp/OculusVRLayers.cpp'
s = rd(p)
if 'fxrGetCenterViewMatrix' not in s:
    s = once(s, '#include "OculusVRLayers.h"\n',
             '#include "OculusVRLayers.h"\n\n'
             '// VrApi_Helpers.h (<= 1.1.2x) helper, removed in later SDK headers: left view with the eyes\' mean translation\n'
             'static inline ovrMatrix4f fxrGetCenterViewMatrix(const ovrMatrix4f* aLeft, const ovrMatrix4f* aRight) {\n'
             '  ovrMatrix4f center = *aLeft;\n'
             '  center.M[0][3] = (aLeft->M[0][3] + aRight->M[0][3]) * 0.5f;\n'
             '  center.M[1][3] = (aLeft->M[1][3] + aRight->M[1][3]) * 0.5f;\n'
             '  center.M[2][3] = (aLeft->M[2][3] + aRight->M[2][3]) * 0.5f;\n'
             '  return center;\n'
             '}\n', 'OculusVRLayers include')
    s = once(s, 'vrapi_GetCenterViewMatrix(', 'fxrGetCenterViewMatrix(', 'GetCenterViewMatrix call')
    wr(p, s); print('patched', p)

# ---- CMakeLists.txt: no Oculus Platform SDK for GEARVR ---------------------------------------------------------
p = 'app/CMakeLists.txt'
s = rd(p)
if 'GEARVR' not in s:
    s = once(s, '        ${CMAKE_SOURCE_DIR}/../third_party/OVRPlatformSDK/Include\n', '', 'platform include dir')
    s = once(s, 'elseif(OCULUSVR)\ninclude_directories(\n',
             'elseif(OCULUSVR)\nif(NOT GEARVR)\n  include_directories(${CMAKE_SOURCE_DIR}/../third_party/OVRPlatformSDK/Include)\nendif()\n'
             'include_directories(\n', 'oculusvr include block')
    s = once(s, 'if(OCULUSVR)\nadd_custom_command(TARGET native-lib POST_BUILD\n',
             'if(OCULUSVR AND NOT GEARVR)\nadd_custom_command(TARGET native-lib POST_BUILD\n', 'platform loader copy')
    wr(p, s); print('patched', p)

# ---- app/build.gradle: gearvr flavor ---------------------------------------------------------------------------
p = 'app/build.gradle'
s = rd(p)
if 'gearvr {' not in s:
    # Kryo 280 = Cortex-A73 (big) + Cortex-A53 (LITTLE): tune for A73, stay A53-compatible (armv8-a+crc+crypto)
    opt = ('" -DOCULUSVR -DSTORE_BUILD=0 -DGEARVR_NO_OVR_PLATFORM -O3 -march=armv8-a+crc+crypto -mtune=cortex-a73'
           ' -fomit-frame-pointer -ffunction-sections -fdata-sections -flto=thin"')
    flavor = ('        gearvr {\n'
              '            dimension "platform"\n'
              '            externalNativeBuild {\n'
              '                cmake {\n'
              '                    cppFlags ' + opt + '\n'
              '                    cFlags ' + opt + '\n'
              '                    arguments "-DVR_SDK_LIB=oculusvr-lib", "-DOCULUSVR=ON", "-DGEARVR=ON",\n'
              '                              "-DCMAKE_CXX_FLAGS_RELEASE=-O3 -DNDEBUG", "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG",\n'
              '                              "-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld -flto=thin -Wl,-O2 -Wl,--gc-sections -Wl,--icf=all"\n'
              '                }\n'
              '            }\n'
              '            manifestPlaceholders = [ headtrackingRequired:"false", permissionToRemove:"android.permission.CAMERA" ]\n'
              '        }\n')
    s = once(s, '        oculusvr3dofStore {\n            dimension "platform"\n',
             flavor + '        oculusvr3dofStore {\n            dimension "platform"\n', 'productFlavors')
    s = once(s, "                'oculusvr3dofStoreArm64Debug',\n",
             "                'gearvrArm64Debug',\n                'gearvrArm64Release',\n"
             "                'oculusvr3dofStoreArm64Debug',\n", 'variantFilter')
    ss = ('        gearvr {\n'
          '            java.srcDirs = [\n                    \'src/oculusvr/java\'\n            ]\n'
          '            assets.srcDirs = [\n                    \'src/oculusvr/assets\'\n            ]\n'
          '            res.srcDirs = [\n                    \'src/oculusvr/res\'\n            ]\n'
          '        }\n\n'
          '        gearvrArm64Debug {\n            manifest.srcFile "src/oculusvrArmDebug/AndroidManifest.xml"\n        }\n\n'
          '        gearvrArm64Release {\n            manifest.srcFile "src/oculusvrArmRelease/AndroidManifest.xml"\n        }\n\n')
    s = once(s, '        oculusvr3dofStore {\n            java.srcDirs = [\n', ss + '        oculusvr3dofStore {\n            java.srcDirs = [\n', 'sourceSets')
    wr(p, s); print('patched', p)

# OpenWnn (JP/ZH keyboards) was only on JCenter (shut down): use the AAR Wolvic bundles in libs/openwnn
s = rd(p)
if 'implementation deps.openwnn\n' in s:
    s = once(s, '    implementation deps.openwnn\n',
             '    implementation fileTree(dir: "${project.rootDir}/libs/openwnn/", include: [\'*.aar\'])  // JCenter is gone\n',
             'openwnn')
    wr(p, s); print('patched', p, '(openwnn)')

# Toolchain for newer GeckoView: its AARs (and their AndroidX deps) carry Kotlin 1.8 metadata and minCompileSdk 33.
# Kotlin 1.4.10 -> 1.8.22 (needs Gradle >= 6.8.3: 6.7.1 -> 6.9.4), compileSdk 33 (targetSdk stays 30), and the
# removed 'kotlin-android-extensions' plugin (applied but unused: no synthetic imports, no @Parcelize).
p = 'versions.gradle'
s = rd(p)
if '"1.8.22"' not in s:
    s = re.sub(r'(?m)^(versions\.kotlin = )"[^"]+"', r'\1"1.8.22"', s); wr(p, s); print('patched', p)
p = 'gradle/wrapper/gradle-wrapper.properties'
s = rd(p)
if 'gradle-6.9.4' not in s:
    s = once(s, 'gradle-6.7.1-bin', 'gradle-6.9.4-bin', 'gradle wrapper'); wr(p, s); print('patched', p)
p = 'app/build.gradle'
s = rd(p)
if "apply plugin: 'kotlin-android-extensions'\n" in s:
    s = once(s, "apply plugin: 'kotlin-android-extensions'\n", '', 'android-extensions')
    s = once(s, '    compileSdkVersion build_versions.target_sdk\n', '    compileSdkVersion 33\n', 'compileSdk')
    wr(p, s); print('patched', p, '(toolchain)')

# Kotlin >= 1.7: 'when' statements on sealed types must be exhaustive (no behaviour change: else = no-op)
for p, old, new in (
    ('app/src/common/shared/org/mozilla/vrbrowser/addons/adapters/AddonsListViewAdapter.kt',
     '            is AddonViewHolder -> bindAddon(holder, item as Addon)\n        }\n',
     '            is AddonViewHolder -> bindAddon(holder, item as Addon)\n            else -> {}\n        }\n'),
    ('app/src/common/shared/org/mozilla/vrbrowser/browser/Accounts.kt',
     '            SyncEngine.History -> {\n                GleanMetricsService.FxA.historySyncStatus(value)\n            }\n        }\n',
     '            SyncEngine.History -> {\n                GleanMetricsService.FxA.historySyncStatus(value)\n            }\n            else -> {}\n        }\n')):
    s = rd(p)
    if new not in s:
        s = once(s, old, new, 'exhaustive when ' + os.path.basename(p)); wr(p, s); print('patched', p)

# GeckoView >= ~102 dropped ContentBlockingController's per-site exception list (ContentBlockingException,
# add/remove/check/save/restoreExceptionList). Same as Wolvic today: per-site exceptions become no-ops (listeners
# still notified); the global Enhanced Tracking Protection level keeps working.
p = 'app/src/common/shared/org/mozilla/vrbrowser/browser/content/TrackingProtectionStore.java'
s = rd(p)
if 'ContentBlockingException' in s:
    s = once(s, 'import org.mozilla.geckoview.ContentBlockingController.ContentBlockingException;\n', '', 'CBE import')
    a = s.index('    private Observer<List<SitePermission>> mSitePermissionObserver')
    b = s.index('    private void setTrackingProtectionLevel(')
    stub = '''    private Observer<List<SitePermission>> mSitePermissionObserver = new Observer<List<SitePermission>>() {
        @Override
        public void onChanged(List<SitePermission> sitePermissions) {
            if (sitePermissions != null) {
                mSitePermissions = sitePermissions;
                mIsFirstUpdate = false;
            }
        }
    };

    @Override
    public void onDestroy(@NonNull LifecycleOwner owner) {
        mLifeCycle.removeObserver(this);
        mPrefs.unregisterOnSharedPreferenceChangeListener(this);
    }

    // Gear VR build: GeckoView no longer has per-site content blocking exceptions (see patch_fxr_gearvr.py)
    public void contains(@NonNull Session session, Function<Boolean, Void> onResult) {
        onResult.apply(false);
    }

    public void fetchAll(Function<List<SitePermission>, Void> onResult) {
        onResult.apply(new ArrayList<>());
    }

    public void add(@NonNull Session session) {
        mListeners.forEach(listener -> listener.onExcludedTrackingProtectionChange(
                session.getCurrentUri(), true, session.isPrivateMode()));
    }

    public void remove(@NonNull Session session) {
        mListeners.forEach(listener -> listener.onExcludedTrackingProtectionChange(
                session.getCurrentUri(), false, session.isPrivateMode()));
    }

    public void remove(@NonNull SitePermission permission) {
        mListeners.forEach(listener -> listener.onExcludedTrackingProtectionChange(permission.url, false, false));
    }

    public void removeAll() {
        mSitePermissions.forEach(permission -> mListeners.forEach(listener ->
                listener.onExcludedTrackingProtectionChange(permission.url, false, false)));
    }

'''
    s = s[:a] + stub + s[b:]
    wr(p, s); print('patched', p)

# GeckoView 95 -> 115 API (mirrors Wolvic's adaptations):
#  - NavigationDelegate.onLocationChange(session, url) gained List<ContentPermission> perms
#  - GeckoDisplay.surfaceChanged(surface, [left, top,] w, h) -> surfaceChanged(SurfaceInfo)
#  - SelectionActionDelegate.Selection.clientRect -> screenRect (same client->surface matrix applied, as Wolvic)
#  - GeckoRuntime.EXTRA_CRASH_FATAL -> EXTRA_CRASH_PROCESS_TYPE (fatal == main process)
SH = 'app/src/common/shared/org/mozilla/vrbrowser/'
PERMS = 'java.util.List<org.mozilla.geckoview.GeckoSession.PermissionDelegate.ContentPermission>'
edits = [
    ('browser/engine/Session.java', 'public void onLocationChange(@NonNull GeckoSession aSession, String aUri) {',
     'public void onLocationChange(@NonNull GeckoSession aSession, String aUri, @NonNull %s aPerms) {' % PERMS),
    ('browser/engine/Session.java', 'aListener.onLocationChange(mState.mSession, mState.mUri);',
     'aListener.onLocationChange(mState.mSession, mState.mUri, java.util.Collections.emptyList());'),
    ('browser/engine/Session.java', 'listener.onLocationChange(aSession, aUri);', 'listener.onLocationChange(aSession, aUri, aPerms);'),
    ('browser/engine/Session.java', 'display.surfaceChanged(captureSurface, displayWidth, displayHeight);',
     'display.surfaceChanged(new GeckoDisplay.SurfaceInfo.Builder(captureSurface).size(displayWidth, displayHeight).build());'),
    ('browser/engine/Session.java', 'mState.mDisplay.surfaceChanged(surface, left, top, width, height);',
     'mState.mDisplay.surfaceChanged(new GeckoDisplay.SurfaceInfo.Builder(surface).size(width, height).offset(left, top).build());'),
    ('ui/widgets/NavigationBarWidget.java', 'public void onLocationChange(@NonNull GeckoSession geckoSession, @Nullable String url) {',
     'public void onLocationChange(@NonNull GeckoSession geckoSession, @Nullable String url, @NonNull %s perms) {' % PERMS),
    ('ui/widgets/WindowWidget.java', 'public void onLocationChange(@NonNull GeckoSession session, @Nullable String url) {',
     'public void onLocationChange(@NonNull GeckoSession session, @Nullable String url, @NonNull %s perms) {' % PERMS),
]
for f, old, new in edits:
    s = rd(SH + f)
    if new not in s:
        s = once(s, old, new, 'gv115 ' + f); wr(SH + f, s)
s = rd(SH + 'ui/widgets/WindowWidget.java')
if 'aSelection.clientRect' in s:
    wr(SH + 'ui/widgets/WindowWidget.java', s.replace('aSelection.clientRect', 'aSelection.screenRect'))
for f in ('crashreporting/CrashReporterService.java', 'VRBrowserActivity.java'):
    s = rd(SH + f)
    old = 'intent.getBooleanExtra(GeckoRuntime.EXTRA_CRASH_FATAL, false)'
    if old in s:
        wr(SH + f, s.replace(old, 'GeckoRuntime.CRASHED_PROCESS_TYPE_MAIN.equals('
                                  'intent.getStringExtra(GeckoRuntime.EXTRA_CRASH_PROCESS_TYPE))'))
# GeckoSurfaceTexture.lookup(int) -> lookup(long) (WebXR/immersive frames shared from Gecko into the VR compositor)
p = 'app/src/main/cpp/GeckoSurfaceTexture.cpp'
s = rd(p)
if '"(J)Lorg/mozilla/gecko/gfx/GeckoSurfaceTexture;"' not in s:
    s = once(s, '"(I)Lorg/mozilla/gecko/gfx/GeckoSurfaceTexture;"', '"(J)Lorg/mozilla/gecko/gfx/GeckoSurfaceTexture;"', 'lookup sig')
    s = once(s, 'CallStaticObjectMethod(sGeckoSurfaceTextureClass, sLookup, aHandle);',
             'CallStaticObjectMethod(sGeckoSurfaceTextureClass, sLookup, (jlong) aHandle);', 'lookup call')
    wr(p, s)
print('patched GeckoView 115 API')

# VR activity may be shown on top of the keyguard (standard Activity API, API 27+; the device stays locked) - lets
# dev-mode testing render without unlocking, and keeps the VR session alive when the phone locks in the headset.
p = 'app/src/common/shared/org/mozilla/vrbrowser/VRBrowserActivity.java'
s = rd(p)
if 'setShowWhenLocked' not in s:
    s = once(s, '        mLastGesture = NoGesture;\n        super.onCreate(savedInstanceState);\n',
             '        mLastGesture = NoGesture;\n        super.onCreate(savedInstanceState);\n'
             '        setShowWhenLocked(true);  // Gear VR build: VR view over the keyguard (device stays locked)\n'
             '        setTurnScreenOn(true);\n', 'showWhenLocked')
    wr(p, s); print('patched', p)

# ...and in the manifest: keyguard occlusion is decided at launch from the manifest, before onCreate runs
p = 'app/src/oculusvrArmRelease/AndroidManifest.xml'
s = rd(p)
if 'showWhenLocked' not in s:
    s = once(s, '            android:name=".VRBrowserActivity"\n',
             '            android:name=".VRBrowserActivity"\n            android:showWhenLocked="true"\n'
             '            android:turnScreenOn="true"\n', 'manifest showWhenLocked')
    wr(p, s); print('patched', p)

# GeckoView prefs: GPU compositing (WebRender), WebGL, hardware video decode/encode through Android MediaCodec
# (Snapdragon 835 Venus: H.264/HEVC/VP8/VP9 decode, H.264/VP8 encode for WebRTC)
p = 'app/src/main/res/raw/fxr_config.yaml'
s = rd(p)
HW = '''  # S8 port Gear VR build: hardware acceleration
  gfx.webrender.all: true
  gfx.webrender.enabled: true
  gfx.webrender.force-disabled: false
  webgl.force-enabled: true
  webgl.disabled: false
  media.hardware-video-decoding.enabled: true
  media.hardware-video-decoding.force-enabled: true
  media.android-media-codec.enabled: true
  media.android-media-codec.preferred: true
  media.webrtc.hw.h264.enabled: true
  media.navigator.mediadatadecoder_vpx_enabled: true
  media.av1.enabled: false
'''
if 'S8 port Gear VR build' not in s:
    s = once(s, 'prefs:\n', 'prefs:\n' + HW, 'prefs block')
    wr(p, s); print('patched', p)
print('ok')
