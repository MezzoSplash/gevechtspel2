#!/usr/bin/env python3
"""Genereert de texturen voor de Rooftops art-pass (stijl A-familie). Deterministisch, geen externe
assets: alles komt uit dit script (#135).

Schrijft PNG's naar assets/maps/rooftops/:
  tar.png       bitumen dakbedekking met grind voor de daken
  brick.png     baksteen voor de optrekken en schoorstenen
  cladding.png  gegalvaniseerde plaat voor de units, watertanks en leidingen
  concrete.png  beton voor de randen, trappenhuizen en bordessen

Gebruik: python3 tools/gen_rooftops_textures.py
"""
import os
import random
import struct
import zlib

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "maps", "rooftops")


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


def noise(rng, cells, size=SIZE):
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
        n = noise(rng, 4 << o)
        for y in range(SIZE):
            ra = acc[y]
            rn = n[y]
            for x in range(SIZE):
                ra[x] += rn[x] * amp
        amp *= 0.5
    return acc


def tar(rng):
    base = fbm(rng, 3)
    gravel = noise(rng, 160)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            g = gravel[y][x]
            c = 44 + 22 * v + 40 * (g > 0.78) + 18 * (0.2 < g < 0.28)
            # grind heeft warme korrels
            row.append((clamp(c * 1.06), clamp(c), clamp(c * 0.94)))
        rows.append(row)
    return rows


def brick(rng):
    row_h, brick_w = 30, 60
    rows = []
    for y in range(SIZE):
        row = []
        band = (y // row_h) % 2
        off = brick_w // 2 if band else 0
        for x in range(SIZE):
            bx = (x + off) % brick_w
            mortar = bx < 3 or (y % row_h) < 3
            v = rng.random() * 0.1
            if mortar:
                row.append((clamp(96 + 18 * v), clamp(90 + 16 * v), clamp(82 + 14 * v)))
            else:
                shade = 0.85 + 0.25 * ((x * 5 + y * 11) % 9) / 9.0
                row.append((clamp(128 * shade + 20 * v), clamp(78 * shade + 12 * v), clamp(58 * shade + 10 * v)))
        rows.append(row)
    return rows


def cladding(rng):
    base = fbm(rng, 3)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            # verticale ribbels
            rib = 0.08 if (x % 16) < 2 else 0.0
            c = 120 + 34 * v + 26 * rib
            row.append((clamp(c * 0.97), clamp(c), clamp(c * 1.05)))
        rows.append(row)
    return rows


def concrete(rng):
    base = fbm(rng, 4)
    grit = noise(rng, 128)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            g = grit[y][x]
            c = 104 + 42 * v + 16 * (g > 0.88) - 12 * (g < 0.14)
            row.append((clamp(c * 1.01), clamp(c), clamp(c * 0.98)))
        rows.append(row)
    return rows


def main():
    rng = random.Random(20261129)
    for name, fn in (("tar", tar), ("brick", brick), ("cladding", cladding), ("concrete", concrete)):
        print(" wrote", write_png(os.path.join(OUT, name + ".png"), fn(rng)))


if __name__ == "__main__":
    main()
