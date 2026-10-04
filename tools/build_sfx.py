#!/usr/bin/env python3
"""Build game SFX from CC0 sources (see CREDITS.md). Mono 44.1 kHz 16-bit WAV: trimmed, faded, normalized.

Usage: python3 tools/build_sfx.py <src_dir>
<src_dir> holds the unpacked downloads:
  Prepared SFX Library/          The Free Firearm Sound Library (OpenGameArt, CC0)
  kenney_impact/Audio/           Kenney Impact Sounds (CC0)
  kenney_scifi/Audio/            Kenney Sci-fi Sounds (CC0)
  kenney_ui/Audio/               Kenney Interface Sounds (CC0)
  tts/                           raw Piper TTS takes, voice en_US-ljspeech-high (LJ Speech, public domain):
                                   echo "Friendly radar online." | piper -m en_US-ljspeech-high.onnx -f tts/friendly_radar_online.wav
                                   echo "Enemy radar online." | piper -m en_US-ljspeech-high.onnx -f tts/enemy_radar_online.wav
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

def load(path, hp=40, extra=""):
    af = f"highpass=f={hp}" if hp else "anull"
    if extra:
        af += "," + extra
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

def filt(y, af):
    """Run a float signal through an ffmpeg filter chain."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-af", af,
                          "-f", "f32le", "-"], input=y.astype(np.float32).tobytes(), capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)[:len(y)]

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

def shotgun():
    # Nova blast with a bass shelf, plus a synthesized sub thump, a short noise crack on the transient and a bit of
    # Kenney low-frequency rumble for the tail, then saturated together.
    length = 1.0
    x = load(FF + "Nova/O_21P.wav", hp=30, extra="bass=g=6:f=120:w=0.8")
    s = max(onset(x) - int(0.003 * SR), 0)
    body = norm(shape(x[s:], length, 0.30), 0.0)
    n = len(body)
    t = np.arange(n) / SR
    freq = 55.0 + 45.0 * np.exp(-t / 0.05)
    sub = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / 0.08) * np.minimum(t / 0.002, 1.0)
    rng = np.random.default_rng(7)
    crack = filt(rng.standard_normal(n) * np.exp(-t / 0.0025), "highpass=f=1800")
    rumble = load(K + "kenney_scifi/Audio/lowFrequency_explosion_000.ogg", hp=25)
    rumble = norm(shape(rumble, length, 0.15, pre=0.0), 0.0)[:n]
    y = body + 0.30 * sub + 0.50 * norm(crack, 0.0) + 0.15 * rumble
    y = norm(y, 0.0)
    y = np.tanh(3.0 * y) / np.tanh(3.0)
    write("shotgun_fire.wav", norm(y, -1.0))

shotgun()
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

# Melee swing: own synthesis (CC0), band-passed noise sweeping up then down.
rng = np.random.default_rng(11)
n = int(0.26 * SR)
t = np.arange(n) / n
noise = rng.standard_normal(n)
swing = np.zeros(n)
for lo, hi, w in ((300, 900, 0.6), (900, 2400, 1.0), (2400, 5000, 0.35)):
    band = filt(noise, f"highpass=f={lo},lowpass=f={hi}")
    swing += band * w * np.sin(np.pi * np.clip((t - 0.05 * (lo / 900)) / 0.9, 0, 1)) ** 2
write("melee_swing.wav", norm(swing * (0.25 + 0.75 * t ** 0.5) * (1 - t) ** 0.6, -4.0))

punch = load(K + "kenney_impact/Audio/impactPunch_heavy_001.ogg")
clank = load(K + "kenney_impact/Audio/impactPlate_light_002.ogg", hp=200)
n = int(0.40 * SR)
hit = np.zeros(n)
hit[:min(n, len(punch))] += norm(punch, 0)[:n]
hit[:min(n, len(clank))] += norm(clank, 0)[:n] * 0.35
hit = np.tanh(2.0 * norm(hit, 0)) / np.tanh(2.0)
write("melee_hit.wav", norm(shape(hit, 0.40, 0.4, pre=0.0), -1.0))

def radio(src, name):
    # Radio announcer: band-limited voice, saturation, a squelch burst before and a short tail after.
    v = load(K + "tts/" + src, hp=0, extra="highpass=f=320,lowpass=f=3300,highpass=f=320,lowpass=f=3300")
    v = norm(v, 0.0)
    v = np.tanh(3.0 * v) / np.tanh(3.0)
    pre, post = int(0.10 * SR), int(0.12 * SR)
    total = pre + len(v) + post
    y = np.zeros(total)
    y[pre:pre + len(v)] += v
    rng = np.random.default_rng(3)
    hiss = filt(rng.standard_normal(total), "highpass=f=900,lowpass=f=4500")
    hiss = norm(hiss, 0.0)
    env = np.full(total, 0.035)
    sq = int(0.06 * SR)
    env[:sq] = 0.30 * np.linspace(1, 0.4, sq)
    env[total - post:total - post + sq] = 0.22 * np.linspace(1, 0.2, sq)
    env[total - post + sq:] = 0.0
    y += hiss * env
    write(name, norm(shape(y, total / SR, 0.92, pre=0.002), -1.5))

radio("friendly_radar_online.wav", "radar_friendly.wav")
radio("enemy_radar_online.wav", "radar_enemy.wav")

def trickshot():
    # Trickshot sting: Kenney Interface rising sweep, then the two-tone chime plus an octave-up copy for sparkle.
    sweep = load(K + "kenney_ui/Audio/maximize_005.ogg", hp=120)
    chime = load(K + "kenney_ui/Audio/confirmation_002.ogg", hp=120)
    sparkle = load(K + "kenney_ui/Audio/confirmation_002.ogg", hp=400, extra=f"asetrate={SR*2},aresample={SR}")
    total = int(0.68 * SR)
    y = np.zeros(total)
    def put(x, at, gain):
        a = int(at * SR)
        n = min(len(x), total - a)
        y[a:a + n] += x[:n] * gain
    put(norm(sweep, 0.0), 0.0, 0.55)
    put(norm(chime, 0.0), 0.07, 1.0)
    put(norm(sparkle, 0.0), 0.07, 0.35)
    y = np.tanh(1.6 * y) / np.tanh(1.6)
    write("trickshot.wav", norm(shape(y, total / SR, 0.7, pre=0.002), -2.0))

if os.path.isdir(K + "kenney_ui/Audio"):
    trickshot()
