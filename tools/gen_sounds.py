#!/usr/bin/env python3
"""Generate placeholder gun / hit WAVs. Deterministic, no extra deps."""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")


def write_wav(path: str, samples: list[float]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767.0)) for s in samples
        )
        w.writeframes(frames)


def env(t: float, attack: float, decay: float) -> float:
    if t < 0:
        return 0.0
    if t < attack:
        return t / attack if attack > 0 else 1.0
    return math.exp(-(t - attack) / decay)


def rifle_fire(rng: random.Random) -> list[float]:
    n = int(0.13 * SR)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        noise = rng.uniform(-1.0, 1.0)
        # crude highpass
        hp = noise if i == 0 else noise - rng.uniform(-0.2, 0.2)
        shot = hp * env(t, 0.001, 0.028) * 0.45
        click = math.sin(2 * math.pi * 2100 * t) * env(t, 0.0004, 0.008) * 0.35
        thump = math.sin(2 * math.pi * 92 * t) * env(t, 0.001, 0.05) * 0.7
        body = math.sin(2 * math.pi * 180 * t) * env(t, 0.001, 0.035) * 0.35
        out[i] = shot + click + thump + body
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * 0.9 for s in out]


def tick(freq: float, decay: float, amp: float) -> list[float]:
    n = int((decay * 6 + 0.02) * SR)
    out = []
    for i in range(n):
        t = i / SR
        s = math.sin(2 * math.pi * freq * t) * math.exp(-t / decay) * amp
        s += (0.15 * amp) * math.sin(2 * math.pi * freq * 2.2 * t) * math.exp(-t / (decay * 0.6))
        out.append(s)
    return out


def kill_sound() -> list[float]:
    n = int(0.22 * SR)
    out = []
    for i in range(n):
        t = i / SR
        a = math.sin(2 * math.pi * 140 * t) * math.exp(-t / 0.06)
        b = math.sin(2 * math.pi * 90 * t) * math.exp(-t / 0.09)
        c = math.sin(2 * math.pi * 420 * t) * math.exp(-t / 0.03) * 0.4
        out.append((a + b + c) * 0.85)
    return out


def hurt_self() -> list[float]:
    """Low thud + flesh, not the high tick used for hitting enemies."""
    n = int(0.18 * SR)
    rng = random.Random(11)
    out = []
    for i in range(n):
        t = i / SR
        noise = rng.uniform(-1.0, 1.0)
        flesh = noise * math.exp(-t / 0.035) * 0.35
        thump = math.sin(2 * math.pi * 72 * t) * math.exp(-t / 0.055) * 0.9
        body = math.sin(2 * math.pi * 165 * t) * math.exp(-t / 0.04) * 0.45
        slap = math.sin(2 * math.pi * 340 * t) * math.exp(-t / 0.018) * 0.25
        out.append(flesh + thump + body + slap)
    peak = max(abs(s) for s in out) or 1.0
    return [s / peak * 0.88 for s in out]


def empty_click() -> list[float]:
    n = int(0.06 * SR)
    out = []
    for i in range(n):
        t = i / SR
        s = math.sin(2 * math.pi * 1600 * t) * math.exp(-t / 0.012)
        s += math.sin(2 * math.pi * 400 * t) * math.exp(-t / 0.02) * 0.4
        out.append(s * 0.5)
    return out


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    write_wav(os.path.join(OUT, "rifle_fire.wav"), rifle_fire(random.Random(7)))
    write_wav(os.path.join(OUT, "hit.wav"), tick(1900, 0.018, 0.55))
    write_wav(os.path.join(OUT, "headshot.wav"), tick(2650, 0.022, 0.65))
    write_wav(os.path.join(OUT, "kill.wav"), kill_sound())
    write_wav(os.path.join(OUT, "empty.wav"), empty_click())
    write_wav(os.path.join(OUT, "hurt.wav"), hurt_self())
    print("wrote sounds to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
