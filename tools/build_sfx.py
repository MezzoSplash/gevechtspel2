#!/usr/bin/env python3
"""Build game SFX from CC0 sources (see CREDITS.md). Mono 44.1 kHz 16-bit WAV: trimmed, faded, normalized.

Usage: python3 tools/build_sfx.py <src_dir>
<src_dir> holds the unpacked downloads:
  Prepared SFX Library/          The Free Firearm Sound Library (OpenGameArt, CC0)
  kenney_impact/Audio/           Kenney Impact Sounds (CC0)
  kenney_scifi/Audio/            Kenney Sci-fi Sounds (CC0)
Needs ffmpeg and numpy. Writes into assets/sounds/.
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
SRC = sys.argv[1] if len(sys.argv) > 1 else "."
FF = os.path.join(SRC, "Prepared SFX Library") + "/"
K = SRC + "/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds") + "/"

def load(path, hp=40):
    af = f"highpass=f={hp}" if hp else "anull"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-af", af, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)

def onset(x, near=None):
    e = np.convolve(np.abs(x), np.ones(64) / 64, mode="same")
    thr = e.max() * 0.25
    idx = np.argmax(e > thr)
    # walk back to where the transient starts rising
    lo = max(idx - int(0.02 * SR), 0)
    small = np.where(e[lo:idx] < thr * 0.08)[0]
    return lo + (small[-1] if len(small) else 0)

def shape(x, length, hold=0.35, floor_db=-60.0, pre=0.003):
    n = int(length * SR)
    y = x[:n].copy()
    if len(y) < n:
        y = np.pad(y, (0, n - len(y)))
    t = np.arange(n) / n
    fade = np.ones(n)
    k = t > hold
    fade[k] = 10 ** ((floor_db / 20.0) * ((t[k] - hold) / (1 - hold)) ** 1.3)
    a = int(pre * SR)
    fade[:a] *= np.linspace(0, 1, a) if a else 1
    return y * fade

def norm(y, peak_db=-1.0):
    return y / max(np.abs(y).max(), 1e-9) * 10 ** (peak_db / 20.0)

def write(name, y):
    y = np.clip(y, -1, 1)
    with wave.open(OUT + name, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((y * 32767).astype("<i2").tobytes())
    print(f"{name:22s} {len(y)/SR:.2f}s {os.path.getsize(OUT+name)}B")

def gun(src, name, length, hold, drive, peak_db=-1.0):
    x = load(FF + src)
    s = max(onset(x) - int(0.003 * SR), 0)
    y = norm(shape(x[s:], length, hold), 0.0)
    y = np.tanh(drive * y) / np.tanh(drive)  # soft saturation: denser crack, same peak
    write(name, norm(y, peak_db))

gun("AR-15/D_32P.wav", "rifle_fire.wav", 0.55, 0.30, 3.0)
gun("Walther PPQ/X_39P.wav", "pistol_fire.wav", 0.50, 0.30, 2.0)
gun("Nova/O_21P.wav", "shotgun_fire.wav", 0.95, 0.30, 3.5)
gun("Tikka/W_29P.wav", "sniper_fire.wav", 1.40, 0.30, 2.5)

for i in range(5):
    x = load(K + f"kenney_impact/Audio/footstep_concrete_00{i}.ogg", hp=60)
    write("step.wav" if i == 0 else f"step_{i}.wav", norm(shape(x, len(x) / SR, 0.7, pre=0.0), -3.0))

x = load(K + "kenney_impact/Audio/impactPunch_medium_000.ogg")
write("hurt.wav", norm(shape(x, 0.40, 0.5, pre=0.0), -2.0))

crunch = load(K + "kenney_scifi/Audio/explosionCrunch_001.ogg", hp=30)
low = load(K + "kenney_scifi/Audio/lowFrequency_explosion_000.ogg", hp=25)
n = int(2.0 * SR)
mix = np.zeros(n)
mix[:min(n, len(crunch))] += norm(crunch, 0)[:n]
mix[:min(n, len(low))] += norm(low, 0)[:n] * 0.8
write("grenade_boom.wav", norm(shape(mix, 2.0, 0.35, pre=0.0), -1.0))
