#!/usr/bin/env python3
"""Combo SFX for Gevechtspel, synthesised from scratch (no samples, no ripped audio).

    python3 tools/gen_combo_sfx.py   -> assets/sounds/combo_{ding,special,land,bail}.wav

ding     punchy, crunchy arcade blip + sub thump per combo move (the HUD raises its pitch with the multiplier)
special  dark whoosh into a heavy hit for wallrun / wall jump / wall to wall / dive / roll
land     meaty payout: slam, then a chunky low "ka-CHING", when a kill lands the combo
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


def sat(x, drive):
    """Soft clip: grit and loudness without harsh digital clipping."""
    return np.tanh(x * drive) / np.tanh(drive)


def crush(x, bits=7, hold=2):
    """A little sample-and-hold bit crush for an arcade edge."""
    y = np.repeat(x[::hold], hold)[: len(x)]
    q = 2 ** (bits - 1)
    return np.round(y * q) / q


def thump(f0, f1, sec, decay):
    """Kick-style body: a sine that drops in pitch (punch), with a short click on top."""
    t = t_of(sec)
    f = f1 + (f0 - f1) * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    click = lowpass(rng.standard_normal(len(t)), 2) * np.exp(-t / 0.004)
    return body + 0.35 * click


def hit(f, sec, decay):
    """Chunky arcade tone: square-ish wave with a downward blip, darker than a bell."""
    t = t_of(sec)
    fr = f * (1 + 0.5 * np.exp(-t / 0.015))
    ph = 2 * np.pi * np.cumsum(fr) / SR
    tone = np.sign(np.sin(ph)) * 0.5 + np.sin(ph) * 0.5
    return lowpass(tone, 6) * env(t, 0.001, decay)


def ding():
    # per move: low punchy blip + sub thump, crunchy (the HUD pitches it up with the multiplier)
    x = mix(thump(180, 70, 0.22, 0.07) * 0.9, hit(330, 0.22, 0.06) * 0.6)
    return lowpass(crush(sat(x, 2.5), 7, 1), 3)


def special():
    t = t_of(0.5)
    noise = rng.standard_normal(len(t))
    band = lowpass(noise, 10) - lowpass(noise, 70)  # darker whoosh
    whoosh = band * np.sin(np.pi * np.clip(t / 0.28, 0, 1)) ** 2 * (t < 0.28) * 1.4
    impact = pad(mix(thump(160, 50, 0.4, 0.12) * 1.2, hit(220, 0.35, 0.1) * 0.7, hit(330, 0.3, 0.08) * 0.35), 0.24)
    return lowpass(crush(sat(mix(whoosh, impact), 3.0), 7, 1), 4)


def land():
    # meaty payout: heavy slam, then a chunky two-note "ka-CHING" (low, not sparkly)
    slam = mix(thump(120, 40, 0.5, 0.16) * 1.3,
               lowpass(rng.standard_normal(int(SR * 0.08)), 4) * env(t_of(0.08), 0.001, 0.02) * 0.8)
    ka = pad(hit(196, 0.18, 0.05) * 0.8, 0.03)  # G3
    ching = pad(mix(hit(294, 0.55, 0.22), hit(440, 0.5, 0.18) * 0.5, thump(90, 45, 0.3, 0.1) * 0.6), 0.12)  # D4 + A4
    return lowpass(crush(sat(mix(slam, ka, ching), 2.8), 7, 1), 3)


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
    # combo_bail.wav (the record scratch) is frozen as approved: not rewritten. --bail to regenerate it.
    import sys
    if "--bail" in sys.argv:
        save("combo_bail.wav", bail())
