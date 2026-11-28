#!/usr/bin/env python3
"""Genereert de texturen voor de Skyline art-pass (stijl A-familie, hoge stadsdaken). Deterministisch,
geen externe assets (#135).

Schrijft PNG's naar assets/maps/skyline/:
  concrete.png gepleisterd beton voor de torens en borstweringen
  steel.png    staal voor de brandtrappen, leuningen en units
  brick.png    baksteen voor de oudere panden
  glass.png    glas voor de gevels en de lichte ramen in de diepte

Gebruik: python3 tools/gen_skyline_textures.py
"""
import os
import random
import struct
import zlib

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "maps", "skyline")


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


def concrete(rng):
    base = fbm(rng, 4)
    grit = noise(rng, 160)
    rows = []
    for y in range(SIZE):
        row = []
        # horizontale stortnaden om de 128 px
        seam = (y % 128) < 3
        for x in range(SIZE):
            v = base[y][x]
            g = grit[y][x]
            c = 112 + 36 * v + 16 * (g > 0.87)
            if seam:
                c *= 0.72
            row.append((clamp(c * 1.01), clamp(c), clamp(c * 0.97)))
        rows.append(row)
    return rows


def steel(rng):
    base = fbm(rng, 3)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            rib = 0.1 if (x % 24) < 2 else 0.0
            c = 104 + 26 * v + 22 * rib
            row.append((clamp(c * 0.97), clamp(c), clamp(c * 1.04)))
        rows.append(row)
    return rows


def brick(rng):
    row_h, brick_w = 26, 52
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
                row.append((clamp(92 + 16 * v), clamp(86 + 14 * v), clamp(78 + 12 * v)))
            else:
                shade = 0.86 + 0.24 * ((x * 5 + y * 11) % 9) / 9.0
                row.append((clamp(118 * shade + 18 * v), clamp(72 * shade + 12 * v), clamp(56 * shade + 10 * v)))
        rows.append(row)
    return rows


def glass(rng):
    base = fbm(rng, 2)
    rows = []
    for y in range(SIZE):
        row = []
        band = (y % 96) < 4
        for x in range(SIZE):
            v = base[y][x]
            mullion = (x % 64) < 3
            if band or mullion:
                row.append((38, 42, 48))
            else:
                # koel glas met een warme luchtreflectie bovenin
                warm = 1.0 if (y % 96) < 30 else 0.0
                r = 52 + 30 * v + 40 * warm
                g = 66 + 34 * v + 26 * warm
                b = 84 + 30 * v + 10 * warm
                row.append((clamp(r), clamp(g), clamp(b)))
        rows.append(row)
    return rows


def main():
    rng = random.Random(20261201)
    for name, fn in (("concrete", concrete), ("steel", steel), ("brick", brick), ("glass", glass)):
        print(" wrote", write_png(os.path.join(OUT, name + ".png"), fn(rng)))


if __name__ == "__main__":
    main()
