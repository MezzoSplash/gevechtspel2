#!/usr/bin/env python3
"""Synthesize the two tension music cues. Own work (no samples), released as CC0.

  music_round_start.wav  ~13 s build-up that plays when a round goes live
  music_round_final.wav  16 s seamless loop for the last 30 s / someone close to the kill limit
  music_menu.wav         48 s calm seamless loop for the main menu

Deterministic (fixed seed). Needs numpy. Run: python3 tools/gen_music.py
"""
from __future__ import annotations

import os
import wave

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")
RNG = np.random.default_rng(7)


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def saw(f: float, n: int, partials: int = 12) -> np.ndarray:
    t = np.arange(n) / SR
    y = np.zeros(n)
    for k in range(1, partials + 1):
        if f * k > SR / 2.2:
            break
        y += np.sin(2 * np.pi * f * k * t) / k
    return y


def env(n: int, a: float, d: float) -> np.ndarray:
    t = np.arange(n) / SR
    e = np.exp(-np.maximum(t - a, 0) / d)
    if a > 0:
        e = np.where(t < a, t / a, e)
    return e


def lowpass(y: np.ndarray, cut: float) -> np.ndarray:
    a = np.exp(-2 * np.pi * cut / SR)
    out = np.empty_like(y)
    s = 0.0
    for i, v in enumerate(y):
        s = (1 - a) * v + a * s
        out[i] = s
    return out


def put(buf: np.ndarray, at: float, x: np.ndarray, gain: float = 1.0) -> None:
    i = int(at * SR) % len(buf)
    end = min(len(buf), i + len(x))
    buf[i:end] += x[: end - i] * gain
    rest = len(x) - (end - i)
    if rest > 0 and LOOP:
        buf[:rest] += x[end - i:] * gain  # wrap so the loop point is seamless


def drum(n_s: float = 0.6) -> np.ndarray:
    n = int(n_s * SR)
    t = np.arange(n) / SR
    f = 52 + 90 * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.22)
    slap = lowpass(RNG.uniform(-1, 1, n), 1800) * env(n, 0.001, 0.03)
    return body + 0.6 * slap


def tick(n_s: float = 0.05) -> np.ndarray:
    n = int(n_s * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 3100 * t) + 0.5 * np.sin(2 * np.pi * 4700 * t)) * env(n, 0.0005, 0.008)


def bass_note(m: int, n_s: float) -> np.ndarray:
    n = int(n_s * SR)
    return lowpass(saw(hz(m), n, 10), 700) * env(n, 0.004, n_s * 0.45)


def pad(ms: list[int], n_s: float, swell: bool) -> np.ndarray:
    n = int(n_s * SR)
    y = np.zeros(n)
    t = np.arange(n) / SR
    for m in ms:
        for det in (-0.08, 0.0, 0.07):
            y += saw(hz(m + det), n, 8)
    y = lowpass(y, 1400) / (len(ms) * 3)
    vib = 1 + 0.15 * np.sin(2 * np.pi * 5.0 * t)
    shape = (t / n_s) ** 1.6 if swell else np.minimum(1, t / 0.3) * np.minimum(1, (n_s - t) / 0.3)
    return y * shape * vib


def write(name: str, y: np.ndarray, fade_out: float = 0.0) -> None:
    if fade_out > 0:
        k = int(fade_out * SR)
        y[-k:] *= np.linspace(1, 0, k) ** 2
    y = np.tanh(y / (np.max(np.abs(y)) or 1) * 1.6)
    y = y / np.max(np.abs(y)) * 0.84
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767).astype("<i2").tobytes())
    print(path, f"{len(y) / SR:.2f}s")


# D minor ostinato: D D F D | D D Eb(b2) D, sixteenths.
RIFF = [38, 38, 41, 38, 38, 38, 39, 38]


def round_start() -> np.ndarray:
    global LOOP
    LOOP = False
    bpm, bars = 132, 7
    beat = 60 / bpm
    six = beat / 4
    total = bars * 4 * beat + 1.5
    buf = np.zeros(int(total * SR))
    steps = bars * 16
    for s in range(steps):
        at = s * six
        bar = s // 16
        m = RIFF[s % 8] + (5 if bar in (4, 5) else 0)
        put(buf, at, bass_note(m, six * 0.95), 0.55 + 0.05 * bar)
        if s % 4 == 0:
            put(buf, at, drum(), 0.9 if s % 16 == 0 else 0.5)
        if bar >= 2 and s % 2 == 1:
            put(buf, at, tick(), 0.18)
        if bar >= 5 and s % 4 == 2:
            put(buf, at, drum(0.3), 0.35)
    put(buf, 0.0, pad([62, 65, 69], 4 * 4 * beat, True), 0.5)
    put(buf, 4 * 4 * beat, pad([63, 67, 70], 3 * 4 * beat, True), 0.6)
    # final hit
    put(buf, bars * 4 * beat, drum(1.4), 1.4)
    put(buf, bars * 4 * beat, bass_note(26, 1.4), 0.9)
    return buf


def round_final() -> np.ndarray:
    global LOOP
    LOOP = True
    bpm, bars = 150, 10  # 16.0 s exactly
    beat = 60 / bpm
    six = beat / 4
    total = bars * 4 * beat
    buf = np.zeros(int(round(total * SR)))
    for s in range(bars * 16):
        at = s * six
        bar = s // 16
        m = RIFF[s % 8] + (3 if bar % 4 == 2 else 0) + (-2 if bar % 4 == 3 else 0)
        put(buf, at, bass_note(m, six * 0.9), 0.65)
        if s % 4 == 0:
            put(buf, at, drum(), 1.0)
        if s % 8 == 6:
            put(buf, at, drum(0.25), 0.45)
        put(buf, at, tick(), 0.22 if s % 2 == 0 else 0.1)
    for b in range(0, bars, 2):
        put(buf, b * 4 * beat, pad([62 + (b % 4), 65 + (b % 4), 69], 2 * 4 * beat, False), 0.55)
    return buf


def soft_pad(ms: list[int], n_s: float) -> np.ndarray:
    n = int(n_s * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for m in ms:
        for det in (-0.05, 0.05):
            y += np.sin(2 * np.pi * hz(m + det) * t) + 0.25 * np.sin(2 * np.pi * hz(m + 12 + det) * t)
    y /= len(ms) * 2
    fade = np.minimum(1, t / 1.5) * np.minimum(1, (n_s - t) / 1.5)  # crossfades into the next chord
    return y * fade


def pluck(m: int, n_s: float = 1.6) -> np.ndarray:
    n = int(n_s * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * hz(m) * t) + 0.3 * np.sin(2 * np.pi * hz(m) * 2 * t)
    return y * env(n, 0.01, 0.5)


def menu_calm() -> np.ndarray:
    global LOOP
    LOOP = True
    bpm = 80  # 4 chords x 4 bars x 3 s = 48 s
    beat = 60 / bpm
    bar = 4 * beat
    total = 16 * bar
    buf = np.zeros(int(round(total * SR)))
    # Fmaj7 - Am7 - Dm9 - Cmaj7, two bars each, twice.
    chords = [[53, 57, 60, 64], [57, 60, 64, 67], [50, 53, 57, 64], [48, 52, 55, 59]]
    for i in range(8):
        ch = chords[i % 4]
        at = i * 2 * bar
        put(buf, at - 1.0, soft_pad(ch, 2 * bar + 2.0), 0.55)
        put(buf, at, lowpass(saw(hz(ch[0] - 12), int(2 * bar * SR), 4), 300) * env(int(2 * bar * SR), 0.4, 3.0), 0.35)
        notes = ch[1:] + [ch[0] + 12]
        for k in range(8):
            if (k + i) % 3 == 2:
                continue  # leave gaps so it breathes
            put(buf, at + k * beat, pluck(notes[(k * 3 + i) % 4] + 12), 0.18)
    return buf


LOOP = False

if __name__ == "__main__":
    write("music_round_start.wav", round_start(), fade_out=1.0)
    write("music_round_final.wav", round_final())
    write("music_menu.wav", menu_calm())
