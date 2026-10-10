#!/usr/bin/env python3
"""Stereo media playback on the S8: bottom speaker = LEFT, earpiece = RIGHT (S9/S21-style "dual speaker"), mixer side.

usage: stereo_earpiece_mixer.py <mixer_paths_tavil.xml in> <out>

Hardware (S8 SCV36, msm8998-tavil-snd-card), established by listening tests on the phone (2026-10-10):
  bottom speaker = one MAX98506 on TERT_MI2S_RX, "One Stop Mode" Mono Left -> plays the LEFT channel. "Mono Right"
                   would address a second amp (sub_regmap) the S8 does not have.
  earpiece       = WCD9340 EAR PA via SLIMBUS_0_RX. Only the 1-channel layout of the S8's own call path works
                   (SLIM RX0 -> RX INT0, SLIM_0_RX Channels One); every 2-channel layout stayed silent.
  right channel  = DSP per-stream/per-device channel mixer (msm-pcm-q6-v2 "AudStr N ChMixer *"): stream 2 ch in,
                   1 ch out, only for back-end SLIM_0_RX (port_idx 3), weights FL 0 / FR 16384 (Q14 unity).
                   Verified: right-only weights -> right tone, left-only -> left tone, at the earpiece.
Kernel detail: the Input/Output Map and Weight controls only store values; "Cfg" copies them to the routing cache
(applied at adm_open). audio_route writes controls in index order (Cfg first), so the maps/weights go into the
defaults section (written once at HAL init) and the media paths only switch Cfg on (reset to 0 when the path ends).
Streams: deep-buffer = MultiMedia1 = PCM 0, low-latency = MultiMedia5 = PCM 13. Compress offload (MultiMedia4) has no
channel mixer -> left speaker-only; tools/build/build_vendor.sh sets audio.offload.disable=true with S8PORT_STEREO=1.
Only plain speaker playback changes: combined devices (speaker-and-headphones/-bt/-usb ...) keep a copy of the
original path ("<usecase> speaker-only"); device paths (speaker, handset, voice) are untouched, so calls and
speakerphone stay as they were. Earpiece level = the S8 call setting (EAR PA G_6_DB, RX0 Digital Volume 81).
Needs One UI dual-speaker mode (floating feature AUDIO_SUPPORT_DUAL_SPEAKER TRUE + spk_stereo), otherwise SoundBooster
downmixes to mono first.
"""
import re
import sys

MARK = '<!-- s8port stereo earpiece -->'
STREAMS = {'deep-buffer-playback': ('MultiMedia1', 0), 'low-latency-playback': ('MultiMedia5', 13)}
SLIM_0_RX_PORT_IDX = 3       # be_name[] index of SLIM_0_RX in msm-pcm-routing-v2.c
FL, FR, FC = 1, 2, 3         # PCM_CHANNEL_* ids
Q14_UNITY = 16384


def ctl(name, value, idx=None, ind='        '):
    i = f' id="{idx}"' if idx is not None else ''
    return f'{ind}<ctl name="{name}"{i} value="{value}" />\n'


EAR_CHAIN = (ctl('SLIM RX0 MUX', 'AIF1_PB') + ctl('SLIM_0_RX Channels', 'One') +
             ctl('RX INT0_1 MIX1 INP0', 'RX0') + ctl('RX INT0 DEM MUX', 'CLSH_DSM_OUT') +
             ctl('EAR PA Gain', 'G_6_DB') + ctl('RX0 Digital Volume', '81'))

s = open(sys.argv[1], encoding='utf-8').read()
if MARK in s:
    sys.exit('already patched')

# defaults (applied once at HAL init): earpiece output = right input channel
defaults = f'    {MARK}\n'
for usecase, (fe, pcm) in STREAMS.items():
    a = f'AudStr {pcm} ChMixer'
    defaults += (ctl(f'{a} Input Map', FL, 0, '    ') + ctl(f'{a} Input Map', FR, 1, '    ') +
                 ctl(f'{a} Output Map', FC, 0, '    ') +
                 ctl(f'{a} Weight Ch 1', 0, 0, '    ') + ctl(f'{a} Weight Ch 1', Q14_UNITY, 1, '    '))
m = re.search(r'<mixer>\n', s)
if not m:
    sys.exit('no <mixer> root')
s = s[:m.end()] + defaults + s[m.end():]

done = []
for usecase, (fe, pcm) in STREAMS.items():
    m = re.search(r'( *)<path name="%s speaker">\n( *)<ctl name="TERT_MI2S_RX Audio Mixer %s" value="1" />\n'
                  r'\1</path>\n' % (re.escape(usecase), fe), s)
    if not m:
        sys.exit(f'{usecase} speaker: unexpected layout')
    ind = m.group(2)
    # combined devices include "<usecase> speaker": keep them on a copy of the original (speaker only)
    s = s[:m.start()] + m.group(0).replace(f'"{usecase} speaker"', f'"{usecase} speaker-only"') + s[m.start():]

    def keep_parent(pm, usecase=usecase):
        if pm.group(1) == f'{usecase} speaker-protected':
            return pm.group(0)
        return pm.group(0).replace(f'<path name="{usecase} speaker" />', f'<path name="{usecase} speaker-only" />')
    s = re.sub(r'<path name="([^"]+)">\n(?:(?!</path>).)*?</path>', keep_parent, s, flags=re.S)

    m = re.search(r'( *)<path name="%s speaker">\n( *)<ctl name="TERT_MI2S_RX Audio Mixer %s" value="1" />\n'
                  % (re.escape(usecase), fe), s)
    cfg = ''.join(ctl(f'AudStr {pcm} ChMixer Cfg', v, i, ind)
                  for i, v in enumerate((1, 0, 2, 1, SLIM_0_RX_PORT_IDX)))
    add = f'{ind}{MARK}\n' + ctl(f'SLIMBUS_0_RX Audio Mixer {fe}', 1, None, ind) + \
        EAR_CHAIN.replace('        ', ind) + cfg
    s = s[:m.end()] + add + s[m.end():]
    done.append(f'{usecase}({fe}, PCM {pcm})')
open(sys.argv[2], 'w', encoding='utf-8').write(s)
print('stereo earpiece: ' + ' '.join(done))
