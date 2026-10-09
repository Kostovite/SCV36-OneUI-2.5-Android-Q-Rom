#!/usr/bin/env bash
# Runs ON the build server. Where do the Tab S4 Q (t830_q) and S8 Pie (g9500_pp) kernels differ in the parts the S8 Pie
# vendor blobs talk to? 1) userspace ABI headers (include/uapi + msm media headers)  2) ABI-sensitive driver dirs.
cd ~/s8rom/kernel
A=g9500_pp; B=t830_q
echo "== 1. UAPI headers that differ (ABI seen by vendor blobs)"
for d in include/uapi/linux include/uapi/media include/uapi/sound include/uapi/drm include/media include/linux/qcom; do
  [ -d $A/$d ] || continue
  diff -rq $A/$d $B/$d 2>/dev/null | sed -E "s#$A/##; s#$B/##" | awk '{ if ($1=="Only") print "  only-in "$3" "$4; else print "  DIFF   "$2 }'
done | grep -iE 'kgsl|msm|camera|cam_|mdp|mdss|fb|ion|ipa|rmnet|audio|sound|snd|adsp|apr|wcd|q6|sec_|ssp|sensor|ufs|v4l2|videodev|vidc|media|drm|sde|qseecom|tz|ion|sync' | sort | head -80

echo; echo "== 2. ABI-sensitive driver directories: changed lines (Pie -> Q)"
for d in drivers/gpu/msm drivers/media/platform/msm/camera_v2 drivers/media/platform/msm/vidc drivers/video/fbdev/msm \
         drivers/staging/android/ion drivers/platform/msm/ipa drivers/soc/qcom sound/soc/msm sound/soc/codecs \
         drivers/net/wireless/bcmdhd_100_10 drivers/net/wireless/bcmdhd drivers/sensorhub drivers/misc/qseecom.c \
         drivers/char/adsprpc.c drivers/battery_v2 drivers/input/touchscreen/sec_ts drivers/nfc drivers/fingerprint \
         drivers/media/isdbt drivers/staging/android/sw_sync.c drivers/usb/gadget; do
  if [ -e $A/$d ] && [ -e $B/$d ]; then
    n=$(diff -r $A/$d $B/$d 2>/dev/null | grep -cE '^[<>]')
    printf '  %-48s %7s lines differ\n' "$d" "$n"
  elif [ -e $A/$d ]; then printf '  %-48s  only in S8 Pie tree\n' "$d"
  elif [ -e $B/$d ]; then printf '  %-48s  only in Tab S4 Q tree\n' "$d"; fi
done
