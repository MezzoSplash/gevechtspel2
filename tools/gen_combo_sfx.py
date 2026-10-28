#!/usr/bin/env python3
"""Combo SFX for Gevechtspel, synthesised from scratch (no samples, no ripped audio).

    python3 tools/gen_combo_sfx.py   -> assets/sounds/combo_{ding,special,land,bail}.wav

ding     turntable "wicka" scratch per combo move (the HUD raises its pitch with the multiplier)
special  vinyl rewind into a crunchy kick + snare hit (wallrun / wall jump / wall to wall / dive / roll)
land     scratch, snare fill onto a kick, then a register "ka-chunk", when a kill lands the combo
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


def save(name, x, peak=0.85, fade_s=0.01):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * fade_s)
    x[-fade:] *= np.linspace(1, 0, fade)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print("wrote", name, "%.2fs" % (len(x) / SR))


# --- THUG2-style set (ding / special / land): turntable scratches + crunchy drums, like the bail scratch.
# Everything synthesised: a fake "record" (buzzy formant stab + noise) read at a hand-drawn speed curve.
_rng = np.random.default_rng(2)


def lp(x, k):
    k = max(int(k), 1)
    return np.convolve(x, np.ones(k) / k, mode="same")


def sat(x, d):
    return np.tanh(x * d) / np.tanh(d)


def at(x, sec):
    return pad(x, sec)


# --- the "record": a vocal-ish 'ahh' stab (formant buzz) and a noisy hit, like a scratch sample
def record(f0=180, sec=2.0):
    t = t_of(sec); ph = 2 * np.pi * f0 * t
    buzz = sum(np.sin(ph * h) / h for h in range(1, 18))
    form = lp(buzz, 3) - lp(buzz, 25) * 0.6          # crude formant
    return form * 0.7 + lp(_rng.standard_normal(len(t)), 3) * 0.25

def scratch(src, speeds, sec):
    """speeds: list of (duration, from, to). Hand on the platter: read src at that speed."""
    curve = np.concatenate([np.linspace(a, b, int(SR * d)) for d, a, b in speeds])[: int(SR * sec)]
    pos = np.cumsum(curve) + SR * 0.5
    y = np.interp(pos, np.arange(len(src)), src)
    y *= np.clip(np.abs(curve) / 1.0, 0, 1) ** 0.6     # stops are silent
    return lp(y, 2)

# --- drums
def kick(sec=0.35, f0=150, f1=45, dec=0.12):
    t = t_of(sec); f = f1 + (f0 - f1) * np.exp(-t / 0.035)
    return sat(np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / dec), 1.8) + lp(_rng.standard_normal(len(t)), 2) * np.exp(-t / 0.003) * 0.4
def snare(sec=0.3, crunch=3.0):
    t = t_of(sec); n = _rng.standard_normal(len(t))
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04)
    rattle = (n - lp(n, 6)) * np.exp(-t / 0.09)
    return sat(body * 0.8 + rattle, crunch)
def hat(sec=0.08):
    t = t_of(sec); n = _rng.standard_normal(len(t)); return (n - lp(n, 3)) * np.exp(-t / 0.02) * 0.5
def crush(x, bits=8): q = 2 ** (bits - 1); return np.round(x * q) / q


def fill():
    y = np.zeros(int(SR * 0.6))
    for i, d in enumerate([0, 0.07, 0.14, 0.21]):
        s = snare(0.15, 3.0) * (0.6 + 0.12 * i); y[int(SR * d):int(SR * d) + len(s)] += s
    y += at(kick(0.4), 0.28)[:len(y)] * 1.2 if len(at(kick(0.4), 0.28)) <= len(y) else at(kick(0.4), 0.28)[:len(y)] * 1.2
    return y
def bell_clunk():
    t = t_of(0.35)
    clunk = lp(_rng.standard_normal(int(SR * 0.04)), 4) * np.exp(-t_of(0.04) / 0.01)
    ding = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / 0.12) for f in (880, 1320)) * 0.4  # one short register bell
    return mix(clunk * 1.4, at(ding, 0.03))


def thug2_set():
    """The approved preview set (Gianni, 28 Oct). The B variants are computed but not saved: they draw
    from the same noise stream, so skipping them would change the A sounds."""
    rec = record()
    rec_hi = record(260)
    ding = scratch(rec, [(0.05, 0.2, 2.2), (0.04, 2.2, -1.8), (0.06, -1.8, 2.6), (0.05, 2.6, 0)], 0.2)  # "wicka"
    mix(scratch(rec_hi, [(0.03, 0, 2.8), (0.07, 2.8, 0.3)], 0.1), hat() * 0.5)  # B: chirp (unused)
    rewind = scratch(rec, [(0.28, 1.0, -4.0), (0.06, -4.0, 0)], 0.34)
    special = sat(mix(rewind * 0.9, at(kick() * 1.1, 0.30), at(snare() * 0.9, 0.30)), 1.6)  # rewind + hit
    zip_ = scratch(rec_hi, [(0.12, 0.3, 4.5), (0.03, 4.5, 0)], 0.15)  # B: zip + snare (unused)
    mix(zip_, at(snare(0.35, 4.0), 0.13), at(kick(0.3), 0.13), at(snare(0.2), 0.26))
    sc = scratch(rec, [(0.06, 0, 2.5), (0.06, 2.5, -2.5), (0.06, -2.5, 2.5), (0.04, 2.5, 0)], 0.22)
    land = sat(mix(sc * 0.8, at(fill(), 0.2), at(bell_clunk(), 0.5)), 1.5)  # scratch + fill + ka-chunk
    return ding, special, land


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
    d, sp, ld = thug2_set()
    save("combo_ding.wav", d, 0.9, 0.008)
    save("combo_special.wav", sp, 0.9, 0.008)
    save("combo_land.wav", ld, 0.9, 0.008)
    # combo_bail.wav (the record scratch) is frozen as approved: not rewritten. --bail to regenerate it
    # (it would not be byte-identical: it shares the old noise stream).
    import sys
    if "--bail" in sys.argv:
        save("combo_bail.wav", bail())
