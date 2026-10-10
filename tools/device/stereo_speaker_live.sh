#!/bin/bash
# Stereo speaker (bottom speaker = left, earpiece = right) on/off on the running phone, for listening tests.
#   on : mixer_paths_tavil.xml + earpiece/right-channel mixer in the media speaker paths
#        (tools/patches/stereo_earpiece_mixer.py); floating_feature.xml AUDIO_SUPPORT_DUAL_SPEAKER TRUE + spk_stereo
#        (One UI dual-speaker mode: no mono downmix, Dolby Atmos offered for the speaker); /system/build.prop
#        audio.offload.disable=true (compress offload has no DSP channel mixer); reboots
#   off: restores the backups (/sdcard/s8port_stereo_backup) and reboots
# Always patches the pre-stereo originals (backup) so it can be re-run after a script change.
# Same change at build time: S8PORT_STEREO=1 tools/build/build_vendor.sh
P=$(cd "$(dirname "$0")/../.." && pwd); . $P/tools/lib/env.sh
MODE=${1:?usage: stereo_speaker_live.sh on|off}
W=$(mktemp -d); trap 'rm -rf $W' EXIT
B=/sdcard/s8port_stereo_backup
# phone path -> backup name
FILES="system/vendor/etc/mixer_paths_tavil.xml:mixer_paths_tavil.xml system/vendor/etc/floating_feature.xml:floating_feature.xml system/build.prop:build.prop"
if [ "$MODE" = on ]; then
  for e in $FILES; do f=${e#*:}
    echo "cat $B/$f 2>/dev/null || cat /${e%%:*}" > $W/get.sh
    phsh $W/get.sh | tr -d '\r' > $W/$f.orig
    [ -s $W/$f.orig ] || { echo "could not read $f"; exit 1; }
  done
  python3 $P/tools/patches/stereo_earpiece_mixer.py $W/mixer_paths_tavil.xml.orig $W/mixer_paths_tavil.xml || exit 1
  python3 -c "import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])" $W/mixer_paths_tavil.xml || { echo "bad XML"; exit 1; }
  sed -E 's#(<SEC_FLOATING_FEATURE_AUDIO_SUPPORT_DUAL_SPEAKER>)[^<]*#\1TRUE#;
          /SOUNDALIVE_VERSION>/{/spk_stereo/!s#(uhq_level,adapt)#\1,spk_stereo#}' $W/floating_feature.xml.orig > $W/floating_feature.xml
  grep -q 'DUAL_SPEAKER>TRUE' $W/floating_feature.xml && grep -q spk_stereo $W/floating_feature.xml || { echo "floating feature edit failed"; exit 1; }
  { grep -v '^audio.offload.disable=' $W/build.prop.orig; echo 'audio.offload.disable=true'; } > $W/build.prop
  for e in $FILES; do f=${e#*:}; phpush $W/$f /data/local/tmp/s8st_$f || exit 1; done
  SRC=/data/local/tmp/s8st_
else
  SRC=$B/
fi
{
  echo "[ \"$MODE\" = on ] || [ -d $B ] || { echo 'no backup in $B'; exit 1; }"
  echo "mount -o rw,remount /"
  echo "mkdir -p /data/local/tmp/sysrw $B; mountpoint -q /data/local/tmp/sysrw || mount --bind / /data/local/tmp/sysrw"
  for e in $FILES; do f=${e#*:}; T=/data/local/tmp/sysrw/${e%%:*}
    echo "L=\$(ls -Z $T | cut -d' ' -f1); [ -f $B/$f ] || cp -p $T $B/$f"
    echo "cat $SRC$f > $T; chmod 644 $T; chown root:root $T; chcon \$L $T"
  done
  echo "sync; echo 'stereo $MODE'; reboot"
} > $W/apply.sh
phsh $W/apply.sh
