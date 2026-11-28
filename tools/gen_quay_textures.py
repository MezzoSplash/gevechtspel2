#!/usr/bin/env python3
"""Genereert de texturen voor de Quay art-pass (stijl A-familie, haven). Deterministisch, geen externe
assets: alles komt uit dit script (#135).

Schrijft PNG's naar assets/maps/quay/:
  stone.png    granieten blokken voor de kademuren en trappen
  wood.png     havenplanken voor de steigers, kisten en pallets
  metal.png    verweerd staal voor kranen, bolders en containers
  asphalt.png  kadekasseien voor het dek

Gebruik: python3 tools/gen_quay_textures.py
"""
import os
import random
import struct
import zlib

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "maps", "quay")


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


def stone(rng):
    """Granieten blokken: grote rechthoeken met donkere voegen, grijs met warme korrel."""
    base = fbm(rng, 3)
    rows = []
    bh, bw = 86, 170
    for y in range(SIZE):
        row = []
        band = (y // bh) % 2
        off = bw // 2 if band else 0
        for x in range(SIZE):
            bx = (x + off) % bw
            joint = bx < 4 or (y % bh) < 4
            v = base[y][x]
            if joint:
                c = 52 + 14 * v
            else:
                shade = 0.9 + 0.22 * ((x * 3 + y * 7) % 13) / 13.0
                c = (104 + 40 * v) * shade
            row.append((clamp(c * 1.02), clamp(c), clamp(c * 0.96)))
        rows.append(row)
    return rows


def wood(rng):
    """Havenplanken: lange latten met nerf en kopschroeven."""
    base = fbm(rng, 4)
    rows = []
    plank = 64
    for y in range(SIZE):
        row = []
        seam = (y % plank) < 3
        for x in range(SIZE):
            v = base[y][x]
            grain = 0.5 + 0.5 * ((x * 0.7 + v * 26.0) % 1.0)
            if seam:
                r, g, b = 46, 34, 24
            else:
                shade = 0.82 + 0.3 * grain
                r = (112 + 26 * v) * shade
                g = (78 + 20 * v) * shade
                b = (52 + 14 * v) * shade
            row.append((clamp(r), clamp(g), clamp(b)))
        rows.append(row)
    return rows


def metal(rng):
    """Verweerd staal: koel grijs met roeststrepen onder de bouten."""
    base = fbm(rng, 3)
    streak = noise(rng, 96)
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            v = base[y][x]
            s = streak[y][x]
            c = 96 + 30 * v
            rust = max(0.0, s - 0.82) * 2.6
            r = c + 40 * rust
            g = c + 12 * rust
            b = c * 0.98 - 8 * rust
            row.append((clamp(r), clamp(g), clamp(b)))
        rows.append(row)
    return rows


def asphalt(rng):
    """Kasseien op de kade: kleine blokken, warm grijs, natte glans."""
    base = fbm(rng, 3)
    grit = noise(rng, 192)
    rows = []
    cw, ch = 32, 24
    for y in range(SIZE):
        row = []
        band = (y // ch) % 2
        off = cw // 2 if band else 0
        for x in range(SIZE):
            bx = (x + off) % cw
            joint = bx < 2 or (y % ch) < 2
            v = base[y][x]
            g = grit[y][x]
            if joint:
                c = 44 + 10 * v
            else:
                c = (86 + 34 * v) + 18 * (g > 0.85)
            row.append((clamp(c * 1.03), clamp(c), clamp(c * 0.95)))
        rows.append(row)
    return rows


def main():
    rng = random.Random(20261130)
    for name, fn in (("stone", stone), ("wood", wood), ("metal", metal), ("asphalt", asphalt)):
        print(" wrote", write_png(os.path.join(OUT, name + ".png"), fn(rng)))


if __name__ == "__main__":
    main()
