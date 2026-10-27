#!/usr/bin/env python3
"""Combo SFX for Gevechtspel, synthesised from scratch (no samples, no ripped audio).

    python3 tools/gen_combo_sfx.py   -> assets/sounds/combo_{ding,special,land,bail}.wav

ding     short bell per combo move (the HUD raises its pitch as the multiplier grows)
special  air whoosh + bright ching for wallrun / wall jump / wall to wall / dive / roll
land     "kaching": register clunk + coin chimes, when a kill lands the combo
bail     record scratch, when the combo is lost (death or the timer)
Mono 16-bit 44.1 kHz. Deterministic (fixed seed).
"""
import os, wave
import numpy as np

SR = 44100
rng = np.random.default_rng(84)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")


def t_of(sec):
    return np.arange(int(SR * sec)) / SR


def env(t, attack, decay):
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay)


def bell(f, sec, decay, partials=((1, 1.0), (2.76, 0.35), (5.4, 0.18), (8.9, 0.07))):
    t = t_of(sec)
    s = sum(a * np.sin(2 * np.pi * f * m * t) * np.exp(-t / (decay / m ** 0.5)) for m, a in partials)
    return s * env(t, 0.002, 10)


def lowpass(x, k):
    k = max(int(k), 1)
    return np.convolve(x, np.ones(k) / k, mode="same")


def pad(x, sec):
    return np.concatenate([np.zeros(int(SR * sec)), x])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def save(name, x, peak=0.85):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * 0.01)
    x[-fade:] *= np.linspace(1, 0, fade)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print("wrote", name, "%.2fs" % (len(x) / SR))


def ding():
    return bell(1318.5, 0.35, 0.12)  # E6


def special():
    t = t_of(0.55)
    noise = rng.standard_normal(len(t))
    # whoosh: band of noise sweeping up then fading (two smoothing widths = crude band-pass)
    sweep = lowpass(noise, 6) - lowpass(noise, 40)
    whoosh = sweep * np.sin(np.pi * np.clip(t / 0.32, 0, 1)) ** 2 * (t < 0.32)
    ching = pad(bell(1760, 0.45, 0.18) + 0.6 * bell(2637, 0.45, 0.14), 0.24)
    return mix(whoosh * 0.9, ching)


def land():
    t = t_of(0.08)
    clunk = (np.sin(2 * np.pi * 140 * t) + 0.5 * lowpass(rng.standard_normal(len(t)), 3)) * env(t, 0.001, 0.025)
    coins = [pad(bell(f, 0.5, 0.2), d) for f, d in ((2093, 0.06), (2637, 0.12), (3136, 0.18), (4186, 0.24))]
    return mix(clunk * 1.2, *[c * 0.7 for c in coins])


def bail():
    # record scratch: filtered noise read at a speed that goes back and forth (a hand on the platter)
    dur = 0.6
    t = t_of(dur)
    speed = np.concatenate([
        np.linspace(1.0, -1.6, int(SR * 0.16)),
        np.linspace(-1.6, 1.8, int(SR * 0.18)),
        np.linspace(1.8, 0.0, len(t) - int(SR * 0.16) - int(SR * 0.18)),
    ])
    src = lowpass(rng.standard_normal(SR * 2), 4)
    tone = np.sin(2 * np.pi * 220 * np.arange(SR * 2) / SR) * 0.6  # the "music" under the needle
    src = src * 0.5 + tone
    pos = np.cumsum(speed) + SR
    s = np.interp(pos, np.arange(len(src)), src)
    s *= np.clip(np.abs(speed) / 1.2, 0, 1) ** 0.7  # quieter as the platter stops
    s = lowpass(s, 2) * env(t, 0.004, 0.5)
    return s


if __name__ == "__main__":
    save("combo_ding.wav", ding(), 0.7)
    save("combo_special.wav", special())
    save("combo_land.wav", land())
    save("combo_bail.wav", bail())
