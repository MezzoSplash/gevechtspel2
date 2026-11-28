#!/usr/bin/env python3
"""Genereert de texturen voor de Foundry art-pass (stijl A-familie). Deterministisch, geen externe
assets: alles komt uit dit script, dus er zit geen licentie aan die op Steam een probleem kan zijn (#135).

Schrijft PNG's naar assets/maps/foundry/:
  rust.png      roestig plaatstaal voor de buitenmuren en tanks
  iron.png      gietijzer met putjes voor de ovens, lepels en persen
  firebrick.png vuurvaste steen voor de ovenbanden en de hall-schil
  concrete.png  beton voor de vloer en de bunkers

Gebruik: python3 tools/gen_foundry_textures.py
"""
import os
import random
import struct
import zlib

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "maps", "foundry")


def write_png(path, pixels):
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in pixels)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    return path


def clamp(v):
    return 0 if v < 0 else (255 if v > 255 else int(v))


def value_noise(rng, cells, size=SIZE):
    """Ruwe bilineaire ruis op een grid van cells x cells, terug als size x size floats 0..1."""
    grid = [[rng.random() for _ in range(cells + 1)] for _ in range(cells + 1)]
    step = size / float(cells)
    out = []
    for y in range(size):
        gy = y / step
        y0 = int(gy)
        fy = gy - y0
        row = []
        for x in range(size):
            gx = x / step
            x0 = int(gx)
            fx = gx - x0
            a = grid[y0][x0] * (1 - fx) + grid[y0][x0 + 1] * fx
            b = grid[y0 + 1][x0] * (1 - fx) + grid[y0 + 1][x0 + 1] * fx
            row.append(a * (1 - fy) + b * fy)
        out.append(row)
    return out


def fbm(rng, octaves=4):
    acc = [[0.0] * SIZE for _ in range(SIZE)]
    amp = 0.5
    for o in range(octaves):
        n = value_noise(rng, 4 << o)
        for y in range(SIZE):
            row_a = acc[y]
            row_n = n[y]
            for x in range(SIZE):
                row_a[x] += row_n[x] * amp
        amp *= 0.5
    return acc


def rust(rng):
    base = fbm(rng)
    pits = value_noise(rng, 64)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            p = pits[y][x]
            # diep roodbruin met oranje plekken en donkere putjes
            r = 92 + 120 * v - 30 * (p > 0.82)
            g = 46 + 62 * v - 20 * (p > 0.82)
            b = 30 + 34 * v - 12 * (p > 0.82)
            if v > 0.62:
                r += 26
                g += 16
            row.append((clamp(r), clamp(g), clamp(b)))
        rows.append(row)
    return rows


def iron(rng):
    base = fbm(rng, 3)
    spec = value_noise(rng, 96)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            s = spec[y][x]
            g = 52 + 40 * v + 18 * (s > 0.8)
            row.append((clamp(g * 0.96), clamp(g), clamp(g * 1.06)))
        rows.append(row)
    return rows


def firebrick(rng):
    row_h = 32
    brick_w = 64
    rows = []
    for y in range(SIZE):
        row = []
        band = (y // row_h) % 2
        offset = brick_w // 2 if band else 0
        for x in range(SIZE):
            bx = (x + offset) % brick_w
            by = y % row_h
            mortar = bx < 3 or by < 3
            v = rng.random() * 0.12
            if mortar:
                row.append((clamp(74 + 20 * v), clamp(66 + 18 * v), clamp(58 + 16 * v)))
            else:
                shade = 0.82 + 0.3 * ((x * 7 + y * 13) % 11) / 11.0
                row.append((clamp(126 * shade + 24 * v), clamp(66 * shade + 12 * v), clamp(48 * shade + 10 * v)))
        rows.append(row)
    return rows


def concrete(rng):
    base = fbm(rng, 4)
    grit = value_noise(rng, 128)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            g = grit[y][x]
            c = 96 + 44 * v + 20 * (g > 0.86) - 14 * (g < 0.12)
            row.append((clamp(c * 1.02), clamp(c), clamp(c * 0.97)))
        rows.append(row)
    return rows


def main():
    rng = random.Random(20261128)
    for name, fn in (("rust", rust), ("iron", iron), ("firebrick", firebrick), ("concrete", concrete)):
        path = write_png(os.path.join(OUT, name + ".png"), fn(rng))
        print(" wrote", path)


if __name__ == "__main__":
    main()
