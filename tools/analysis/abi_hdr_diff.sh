#!/usr/bin/env bash
# Runs ON the build server: show the exact Pie->Q changes in the UAPI headers the S8 Pie vendor blobs use.
cd ~/s8rom/kernel
for h in include/uapi/linux/msm_kgsl.h include/uapi/linux/ion.h include/uapi/linux/msm_ipa.h include/uapi/linux/qseecom.h \
         include/uapi/linux/v4l2-controls.h include/uapi/sound/compress_params.h include/uapi/linux/msm_audio_anc.h; do
  echo "################ $h  (< Pie S8   > Q Tab S4)"
  diff -u -U1 g9500_pp/$h t830_q/$h | grep -vE '^(\+\+\+|---)' | head -60
done
