#!/system/bin/sh
# Battery tuning for the One UI 2 port (run as root on the phone):  battery_tune.sh apply|rollback|status
#   e.g. from the PC:  phsh tools/device/battery_tune.sh   (defaults to apply)
# Based on the 2026-10-10 audit (docs/DEVLOG.md): telemetry/bloat that only wakes the phone is disabled, store/push
# apps that poll in the background are background-restricted, and the "always scanning" radios are switched off.
# Never touches KnoxGuard / Knox attestation or anything the phone needs to work.
# vaultkeeperd (T835 Q daemon vs S8 Pie TA: "Unexpected reqlen" -> exit, init respawns it every ~11 s, each run loads
# the TA) is only stopped after boot by a Magisk service.d script; the vaultkeeper HAL KnoxGuard talks to keeps running
# (user OK 2026-10-10).
MODE=${1:-apply}
VKSTOP=/data/adb/service.d/s8port_vaultkeeper_stop.sh

# Pure telemetry / diagnostics / analytics - nothing user-visible depends on them.
DISABLE="
com.sec.android.diagmonagent
com.samsung.android.dqagent
com.samsung.android.knox.analytics.uploader
com.samsung.android.securitylogagent
com.samsung.android.rubin.app
com.samsung.android.networkdiagnostic
com.samsung.storyservice
com.samsung.android.beaconmanager
com.samsung.android.ipsgeofence
com.google.android.gms.location.history
com.wssyncmldm
com.sec.android.soagent
com.samsung.android.spayfw
com.samsung.android.app.omcagent
"
# Google Play services components that only do telemetry / ads / federated learning in the background
# (push, location, account sync, Advertising ID service and everything apps call stay enabled).
GMS_DISABLE="
.analytics.AnalyticsReceiver
.analytics.AnalyticsTaskService
.analytics.service.AnalyticsService
.clearcut.uploader.QosUploaderService
.learning.training.background.TrainingGcmTaskService
.ads.social.GcmSchedulerWakeupService
.ads.config.FlagsReceiver
.growth.upgradeparty.scheduler.UpgradePartyTaskService
.growth.watchdog.GrowthWatchdogTaskService
.stats.service.DropBoxEntryAddedReceiver
.stats.service.DropBoxEntryAddedService
.usagereporting.service.UsageReportingIntentService
.nearby.discovery.offline.OfflineCachingService
"
# Still usable when opened, but may not run jobs/alarms in the background.
#   samsungapps: PollJobService held a 3m17s wakelock; spp.push: re-provisions every ~15 min and fails
#   (DUPLICATE_DEVICEID_TO_REPROVISION); themestore: SmpJobService 29 s.
RESTRICT="
com.sec.android.app.samsungapps
com.samsung.android.themestore
com.sec.spp.push
com.samsung.android.game.gos
com.google.android.apps.turbo
com.samsung.android.app.galaxyfinder
com.samsung.android.scloud
com.samsung.android.mobileservice
com.samsung.android.mdx.kit
com.samsung.android.mdecservice
com.samsung.android.smartmirroring
com.samsung.android.aware.service
com.samsung.android.allshare.service.mediashare
com.samsung.android.allshare.service.fileshare
com.samsung.cmh
com.samsung.android.service.peoplestripe
com.samsung.android.app.social
com.samsung.android.easysetup
com.samsung.android.app.sharelive
com.samsung.android.forest
com.samsung.android.svcagent
com.samsung.android.themecenter
com.samsung.android.samsungpass
com.sec.android.app.billing
com.google.android.apps.tachyon
com.google.android.youtube
com.google.android.apps.docs
com.google.android.apps.maps
com.google.android.projection.gearhead
com.google.ar.core
com.google.android.feedback
com.google.android.partnersetup
com.google.android.as
"
# global settings: name off-value on-value
SETTINGS="
ble_scan_always_enabled 0 1
wifi_scan_always_enabled 0 1
"

installed() { pm path "$1" >/dev/null 2>&1; }

case $MODE in
apply)
  for p in $DISABLE; do installed $p && pm disable-user --user 0 $p >/dev/null && echo "disabled   $p"; done
  for c in $GMS_DISABLE; do pm disable com.google.android.gms/$c >/dev/null 2>&1 && echo "disabled   gms/$c"; done
  for p in $RESTRICT; do installed $p || continue
    cmd appops set $p RUN_ANY_IN_BACKGROUND ignore
    am set-standby-bucket $p restricted 2>/dev/null || am set-standby-bucket $p rare
    echo "restricted $p"
  done
  echo "$SETTINGS" | while read n off on; do [ -n "$n" ] && settings put global $n $off && echo "global $n=$off"; done
  cat > $VKSTOP <<'EOS'
#!/system/bin/sh
# s8port battery_tune: stop the vaultkeeperd respawn loop (fails on the S8 TA anyway); the HAL stays up.
# init starts it at late-fs, before Magisk's late_start service stage -> stop it right away.
setprop ctl.stop vaultkeeper
EOS
  chmod 755 $VKSTOP; setprop ctl.stop vaultkeeper; echo "vaultkeeperd stopped (+ $VKSTOP)"
  ;;
rollback)
  for p in $DISABLE; do installed $p && pm enable --user 0 $p >/dev/null && echo "enabled    $p"; done
  for c in $GMS_DISABLE; do pm enable com.google.android.gms/$c >/dev/null 2>&1 && echo "enabled    gms/$c"; done
  for p in $RESTRICT; do installed $p || continue
    cmd appops set $p RUN_ANY_IN_BACKGROUND allow; am set-standby-bucket $p active; echo "unrestricted $p"
  done
  echo "$SETTINGS" | while read n off on; do [ -n "$n" ] && settings put global $n $on && echo "global $n=$on"; done
  rm -f $VKSTOP; setprop ctl.start vaultkeeper; echo "vaultkeeperd restarted"
  ;;
status)
  for p in $DISABLE; do installed $p && echo "$p enabled=$(pm list packages -d | grep -qx "package:$p" && echo no || echo yes)"; done
  echo "gms components disabled: $(dumpsys package com.google.android.gms | sed -n '/disabledComponents:/,/enabledComponents:/p' | grep -cE "$(echo $GMS_DISABLE | sed 's/ /|/g; s/\./\\./g')")/$(echo $GMS_DISABLE | wc -w)"
  for p in $RESTRICT; do installed $p && echo "$p $(cmd appops get $p RUN_ANY_IN_BACKGROUND) bucket=$(am get-standby-bucket $p)"; done
  echo "$SETTINGS" | while read n off on; do [ -n "$n" ] && echo "global $n=$(settings get global $n)"; done
  echo "vaultkeeperd: $(getprop init.svc.vaultkeeper)  hal: $(getprop init.svc.vaultkeeper_hal)  boot script: $([ -f $VKSTOP ] && echo yes || echo no)"
  ;;
*) echo "usage: $0 apply|rollback|status"; exit 1;;
esac
exit 0
