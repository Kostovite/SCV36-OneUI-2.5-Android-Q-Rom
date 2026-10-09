#!/usr/bin/env bash
# WSL: static RRO for framework-res ("android") -> config/overlay/out/FrameworkS8Overlay.apk (goes to /vendor/overlay).
# AOD brightness: G9600 config_aodBrightnessValues = [0, 40, 71, 94] (4 levels) turns on the S9 AOD brightness control
# (AODService AODRune.SUPPORT_BRIGHTNESS_CONTROL = length > 2): doze mode is always HLPM 0x10002 and the 2/10/30/60 nit
# level goes to the S9 panel by a path the S8 panel driver does not have (dream screenBrightness stays -1), so the
# S8 panel (S6E3HA6 alpm: 1/2 = ALPM/HLPM 2 nit, 3/4 = ALPM/HLPM 60 nit, low byte only) sits at 2 nit forever.
# With 2 values the AOD falls back to the S8 scheme: mode 2 (HLPM 2 nit) / 4 (HLPM 60 nit) chosen by the light
# sensor (auto) = exactly what the S8 kernel driver implements. The 4-step manual slider disappears (as on stock S8).
# Wi-Fi Direct / Quick Share: G9600 config_wifi_connected_mac_randomization_supported = true -> before every connect the
# framework sets a per-network random MAC through the Wi-Fi HAL, which takes wlan0 down. The S8 bcmdhd4361 powers the
# chip off on wlan0 down (wl_android_wifi_off) and back on, which deletes the cfg80211 P2P device the supplicant created
# (wl_cfgp2p_del_p2p_disc_if) -> later P2P private commands fail "p2p_wdev is NULL" -> SET_AP_WPS_P2P_IE fails, Quick
# Share receive "ReceiverConnectionFail". Stock S8 Pie never randomized -> false (factory MAC, as on stock).
set -e
P=$(cd "$(dirname "$0")/../.." && pwd); W=~/s8rom/work/fw_overlay; O=$P/config/overlay/out
FWRES=~/s8rom/trees/g9600_root/system/framework/framework-res.apk
rm -rf $W && mkdir -p $W/res/values $O
# DISABLED by default: with randomization off wlan0 keeps the chip default MAC 00:90:4c:.. (our bcmdhd never loads
# /efs/wifi/.mac.info) and association fails (MLME connect -22). MACRAND_OFF=1 only once the driver MAC load is fixed.
[ "${MACRAND_OFF:-0}" = 1 ] && cat > $W/res/values/bools.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- S8 bcmdhd: a MAC change power-cycles the chip and loses the P2P device -->
    <bool name="config_wifi_connected_mac_randomization_supported">false</bool>
</resources>
EOF
cat > $W/res/values/arrays.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- S8 panel: two AOD levels (2 nit / 60 nit) -->
    <integer-array name="config_aodBrightnessValues">
        <item>0</item>
        <item>94</item>
    </integer-array>
</resources>
EOF
# Iris: the T835 SecIrisService (kept unmodified + Samsung-signed) reads android:string/config_keyguardComponent by
# the T835 numeric id 0x01040252, which aapt inlined. In the G9600 framework-res that id is
# config_headlineFontFeatureSettings (default "") -> IrisService.onCreate NPE crash loop. Give that id the keyguard
# component. Its only other use is the headline text fontFeatureSettings, where an unparseable value is skipped.
cat > $W/res/values/strings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="config_headlineFontFeatureSettings" translatable="false">com.android.systemui/com.android.systemui.keyguard.KeyguardService</string>
</resources>
EOF
cat > $W/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.s8port.overlay.framework" android:versionCode="1" android:versionName="1.0">
    <overlay android:targetPackage="android" android:isStatic="true" android:priority="10" />
    <application android:hasCode="false" />
</manifest>
EOF
aapt package -f -M $W/AndroidManifest.xml -S $W/res -I $FWRES -F $W/unsigned.apk
zipalign -f 4 $W/unsigned.apk $W/aligned.apk
KS=$P/config/overlay/s8port_overlay.jks
apksigner sign --ks $KS --ks-pass pass:s8port --key-pass pass:s8port --out $O/FrameworkS8Overlay.apk $W/aligned.apk
apksigner verify $O/FrameworkS8Overlay.apk
aapt2 dump resources $O/FrameworkS8Overlay.apk | grep -A2 -E "config_aodBrightnessValues|mac_randomization"
