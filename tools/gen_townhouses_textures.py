#!/usr/bin/env python3
"""Genereert de texturen voor de Townhouses art-pass. Deterministisch, geen externe assets: alles komt uit
dit script, dus er zit geen licentie aan vast die op Steam een probleem kan zijn (#135).

Schrijft PNG's naar assets/maps/townhouses/:
  brick.png      metselwerk voor de gevels
  cobble.png     keien voor de kade
  rooftile.png   dakpannen voor de surf-daken
  quay.png       flagstones met voegen voor het plein

Gebruik: python3 tools/gen_townhouses_textures.py
"""
import math
import os
import random
import struct
import zlib

SIZE = 512
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "maps", "townhouses")


def write_png(path, pixels):
    """pixels: lijst van (r,g,b) per rij, SIZE breed."""
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


def noise(x, y, seed):
    """Goedkope deterministische ruis in 0..1."""
    r = random.Random((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791))
    return r.random()


def clamp(v):
    return max(0, min(255, int(v)))


def brick():
    """Rijen stenen met verspringende voeg, lichte kleurvariatie per steen."""
    rows, cols = 12, 6
    bh, bw = SIZE / rows, SIZE / cols
    mortar = (86, 78, 70)
    base = (124, 78, 52)
    rows_px = []
    for y in range(SIZE):
        row = []
        ry = int(y // bh)
        offset = 0.5 * bw if ry % 2 else 0.0
        for x in range(SIZE):
            xx = (x + offset) % SIZE
            cx = int(xx // bw)
            fx = xx - cx * bw
            fy = y - ry * bh
            # Voeg: een paar px rond de rand van elke steen.
            edge = min(fx, bw - fx, fy, bh - fy)
            if edge < 2.0:
                n = noise(x // 3, y // 3, 7)
                v = 1.0 - 0.12 * n
                row.append((clamp(mortar[0] * v), clamp(mortar[1] * v), clamp(mortar[2] * v)))
                continue
            # Kleur per steen, met korrel erover.
            s = noise(cx, ry, 31) - 0.5
            g = noise(x // 2, y // 2, 91) - 0.5
            k = 1.0 + 0.16 * s + 0.10 * g
            row.append((clamp(base[0] * k), clamp(base[1] * k * 0.98), clamp(base[2] * k * 0.95)))
        rows_px.append(row)
    return rows_px


def cobble():
    """Keien: een jitterend raster met donkere voegen en lichte toppen."""
    cells = 10
    cs = SIZE / cells
    pts = []
    rnd = random.Random(4242)
    for cy in range(cells + 1):
        line = []
        for cx in range(cells + 1):
            line.append((cx * cs + (rnd.random() - 0.5) * cs * 0.45,
                         cy * cs + (rnd.random() - 0.5) * cs * 0.45))
        pts.append(line)
    base = (108, 106, 100)
    out = []
    for y in range(SIZE):
        row = []
        cy = int(y // cs)
        for x in range(SIZE):
            cx = int(x // cs)
            # Afstand tot het dichtstbijzijnde roosterpunt: klein = steen, groot = voeg.
            best = 1e9
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    gx = min(max(cx + dx, 0), cells)
                    gy = min(max(cy + dy, 0), cells)
                    px, py = pts[gy][gx]
                    d = math.hypot(x - px, y - py)
                    best = min(best, d)
            t = min(1.0, best / (cs * 0.52))
            k = 0.55 + 0.45 * t
            n = noise(x // 2, y // 2, 13) - 0.5
            k *= 1.0 + 0.12 * n
            row.append((clamp(base[0] * k), clamp(base[1] * k), clamp(base[2] * k * 0.97)))
        out.append(row)
    return out


def rooftile():
    """Dakpannen: horizontale rijen met verspringende segmenten en een schaduwrand per rij."""
    rows, cols = 16, 10
    rh, rw = SIZE / rows, SIZE / cols
    base = (138, 62, 44)
    out = []
    for y in range(SIZE):
        row = []
        ry = int(y // rh)
        offset = 0.5 * rw if ry % 2 else 0.0
        for x in range(SIZE):
            xx = (x + offset) % SIZE
            cx = int(xx // rw)
            fx = xx - cx * rw
            fy = y - ry * rh
            s = noise(cx, ry, 77) - 0.5
            k = 1.0 + 0.18 * s
            # Ronde onderkant van de pan en een schaduwlijn aan de bovenkant.
            if fy < 3.0:
                k *= 0.62
            elif math.hypot((fx - rw * 0.5) / (rw * 0.5), (fy - rh) / rh) > 0.92:
                k *= 0.82
            n = noise(x // 2, y // 2, 5) - 0.5
            k *= 1.0 + 0.08 * n
            row.append((clamp(base[0] * k), clamp(base[1] * k), clamp(base[2] * k)))
        out.append(row)
    return out


def quay():
    """Flagstones: grote tegels met smalle voegen, koel grijs met warme vlekken."""
    cells = 4
    cs = SIZE / cells
    base = (96, 98, 102)
    out = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            fx, fy = x % cs, y % cs
            edge = min(fx, cs - fx, fy, cs - fy)
            k = 0.72 if edge < 3.0 else 1.0
            warm = noise(x // 40, y // 40, 3) - 0.5
            n = noise(x // 2, y // 2, 29) - 0.5
            k *= 1.0 + 0.10 * n + 0.12 * warm
            row.append((clamp(base[0] * k * (1.0 + 0.06 * warm)), clamp(base[1] * k), clamp(base[2] * k)))
        out.append(row)
    return out


if __name__ == "__main__":
    for name, fn in (("brick", brick), ("cobble", cobble), ("rooftile", rooftile), ("quay", quay)):
        print("wrote", write_png(os.path.join(OUT, name + ".png"), fn()))
