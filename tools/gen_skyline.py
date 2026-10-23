#!/usr/bin/env python3
"""Generates scenes/maps/skyline.tscn: "Skyline", city rooftops with a lot of height.

Same pipeline as Rooftops / Quay: CSG under one Arena combiner (collision layer 1), so main.gd
bakes the bot navmesh from it. World paint materials, procedural sky, skyline backdrop.
Re-run after editing:  python3 tools/gen_skyline.py

Half-turn symmetric (x, z) -> (-x, -z). Blue spawns at +Z, Orange at -Z.
Every building is a CSGPolygon3D body (not drawn on the minimap) plus a thin CSGBox3D roof
slab (drawn as floor). Gaps between buildings drop into the street far below; the map root
carries metadata kill_y, and a pawn under it dies (Game / player.gd).

Roof heights (top of slab), Blue half. Orange is the half-turn.
  Spawn roof          y 12   x -16..16, z 36..46
  Centre tower        y 12   x -7..7,  z 20..31  hollow: room y 6..11, stairwell up to a roof hatch
  Mid bridge          y 6    x -3..3,  z 10..20  tower door -> Mid
  Mid (shared)        y 6    x -10..10, z -10..10
  West: WA y 9 (ramp from spawn), WB y 6 (plank ramp or jump), WM y 4 (ramp), plank up to Mid
  East: fire escape up the face of EA (y 15, the perch), ramp down to EB (y 9), plank to Mid,
        or a 5 m drop to EM (y 4, the half-turn of WM)
Lanes: west (low, stepped), centre (tower CQB), east (high, fire escape). Ramps stay <= 37 deg
(walk limit 45, nav 46), planks are >= 2 m wide so the nav agent (r 0.5) fits.
"""
import math
import os
import random

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "skyline.tscn")

BASE = -30.0       # street level, far below every roof
KILL_Y = -3.0      # under the lowest roof (4) and its planks

# (pattern, wear, line_dark, grain): 0 plain, 1 brick, 2 slabs, 3 ribs, 4 roof sheets, 5 asphalt
PAINT = {
    "roof": (4, 0.08, 0.25, 0.04),
    "tar": (5, 0.10, 0.0, 0.05),
    "brick": (1, 0.08, 0.38, 0.03),
    "brick_dark": (1, 0.08, 0.38, 0.03),
    "concrete": (2, 0.09, 0.30, 0.035),
    "plaster": (2, 0.07, 0.18, 0.03),
    "steel": (0, 0.07, 0.0, 0.025),
    "plank": (3, 0.10, 0.30, 0.04),
    "hazard": (0, 0.06, 0.0, 0.02),
    "team_blue": (2, 0.06, 0.22, 0.02),
    "team_orange": (2, 0.06, 0.22, 0.02),
    "ac": (3, 0.06, 0.25, 0.02),
    "street": (5, 0.10, 0.0, 0.05),
    "sky_a": (2, 0.06, 0.25, 0.02),
    "sky_b": (1, 0.06, 0.30, 0.02),
    "sky_c": (2, 0.05, 0.20, 0.02),
}
MATS = {
    "roof": ((0.33, 0.35, 0.34), 0.90),
    "tar": ((0.20, 0.21, 0.22), 0.94),
    "brick": ((0.55, 0.33, 0.24), 0.85),
    "brick_dark": ((0.38, 0.26, 0.22), 0.86),
    "concrete": ((0.44, 0.44, 0.42), 0.88),
    "plaster": ((0.62, 0.58, 0.50), 0.86),
    "steel": ((0.28, 0.31, 0.35), 0.55),
    "plank": ((0.46, 0.34, 0.22), 0.85),
    "hazard": ((0.80, 0.63, 0.14), 0.75),
    "team_blue": ((0.27, 0.46, 0.66), 0.82),
    "team_orange": ((0.74, 0.44, 0.18), 0.82),
    "ac": ((0.62, 0.64, 0.66), 0.62),
    "street": ((0.17, 0.18, 0.19), 0.95),
    "sky_a": ((0.36, 0.40, 0.46), 0.85),
    "sky_b": ((0.44, 0.36, 0.32), 0.85),
    "sky_c": ((0.52, 0.54, 0.56), 0.80),
}

nodes = []      # (name, type, transform, extras, mat, parent)
backdrop = []   # (name, center, size, mat)
lights = []
glows = []      # lit window strips on the backdrop: (name, center, size)


def fmt(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def xform(cols, o):
    (X, Y, Z) = cols
    vals = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2]] + list(o)
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in vals)


IDENT = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
# Extrude straight down: local X = world X, local Y = world -Z, local Z = world +Y (det +1).
DOWN = ((1, 0, 0), (0, 0, -1), (0, 1, 0))


def add(name, typ, xf, extras, mat, parent="Arena"):
    nodes.append((name, typ, xf, extras, mat, parent))


def box(name, x0, x1, y0, y1, z0, z1, mat, op=None):
    c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    s = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
    extra = ["size = Vector3(%s, %s, %s)" % tuple(fmt(v) for v in s)]
    if op is not None:
        extra.append("operation = %d" % op)
    add(name, "CSGBox3D", xform(IDENT, c), extra, mat)


def ht(x0, x1, z0, z1):
    """Half-turn of an XZ rectangle."""
    return -x1, -x0, -z1, -z0


def box_h(name, x0, x1, y0, y1, z0, z1, mat, mat_o=None):
    box(name + "_B", x0, x1, y0, y1, z0, z1, mat)
    a, b, c, d = ht(x0, x1, z0, z1)
    box(name + "_O", a, b, y0, y1, c, d, mat_o or mat)


def sub_h(name, x0, x1, y0, y1, z0, z1):
    box_h(name, x0, x1, y0, y1, z0, z1, "concrete")
    nodes[-1] = nodes[-1][:3] + (nodes[-1][3] + ["operation = 2"],) + nodes[-1][4:]
    nodes[-2] = nodes[-2][:3] + (nodes[-2][3] + ["operation = 2"],) + nodes[-2][4:]


def body(name, x0, x1, z0, z1, top, mat):
    """Building: solid from the street to `top`. Polygon so the minimap ignores it."""
    poly = [x0, -z0, x1, -z0, x1, -z1, x0, -z1]
    add(name, "CSGPolygon3D", xform(DOWN, (0, top, 0)),
        ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in poly),
         "depth = %s" % fmt(top - BASE)], mat)


def building_h(name, x0, x1, z0, z1, top, mat, roof="roof"):
    """Body + roof slab, Blue copy and the Orange half-turn."""
    for suf, (a, b, c, d) in (("_B", (x0, x1, z0, z1)), ("_O", ht(x0, x1, z0, z1))):
        body(name + suf, a, b, c, d, top - 0.02, mat)
        box(name + "Roof" + suf, a, b, top - 0.3, top, c, d, roof)


def _ramp_basis(dh, dl, axis):
    length = math.hypot(dl, dh)
    if axis == "z":
        Z = (0.0, dh / length, dl / length)
        Y = (0.0, abs(dl) / length, -dh / length * (1 if dl > 0 else -1))
    else:
        Z = (dl / length, dh / length, 0.0)
        Y = (-dh / length * (1 if dl > 0 else -1), abs(dl) / length, 0.0)
    X = (Y[1] * Z[2] - Y[2] * Z[1], Y[2] * Z[0] - Y[0] * Z[2], Y[0] * Z[1] - Y[1] * Z[0])
    return (X, Y, Z), length


def ramp(name, axis, a0, a1, lo, hi, y_lo, y_hi, mat, t=0.3):
    """Thin ramp. axis "z": spans x a0..a1, top meets y_lo at z=lo and y_hi at z=hi.
    axis "x": spans z a0..a1, from x=lo to x=hi."""
    dh = y_hi - y_lo
    dl = hi - lo
    basis, length = _ramp_basis(dh, dl, axis)
    Y = basis[1]
    if axis == "z":
        mid = ((a0 + a1) / 2, (y_lo + y_hi) / 2, (lo + hi) / 2)
        size = (abs(a1 - a0), t, length)
    else:
        mid = ((lo + hi) / 2, (y_lo + y_hi) / 2, (a0 + a1) / 2)
        size = (length, t, abs(a1 - a0))
        # local Z runs along X here; the box's long side must be local Z.
        size = (abs(a1 - a0), t, length)
    c = tuple(mid[i] - Y[i] * t / 2 for i in range(3))
    add(name, "CSGBox3D", xform(basis, c),
        ["size = Vector3(%s, %s, %s)" % tuple(fmt(v) for v in size)], mat)
    return math.degrees(math.atan2(abs(dh), abs(dl)))


def ramp_h(name, axis, a0, a1, lo, hi, y_lo, y_hi, mat):
    deg = ramp(name + "_B", axis, a0, a1, lo, hi, y_lo, y_hi, mat)
    ramp(name + "_O", axis, -a1, -a0, -lo, -hi, y_lo, y_hi, mat)
    slopes.append((name, deg))


slopes = []


def light_h(name, pos, col, energy, rng):
    lights.append((name + "_B", pos, col, energy, rng))
    lights.append((name + "_O", (-pos[0], pos[1], -pos[2]), col, energy, rng))


# ================================================================ buildings
building_h("Spawn", -16, 16, 36, 46, 12.0, "brick")
building_h("Tower", -7, 7, 20, 31, 12.0, "plaster", roof="tar")
building_h("WA", -28, -21, 26, 42, 9.0, "brick_dark")
building_h("WB", -28, -19, 9.5, 22, 6.0, "concrete", roof="tar")
building_h("WM", -28, -18, -5, 5, 4.0, "brick")
building_h("EA", 18, 28, 24, 36, 15.0, "concrete")
building_h("EB", 17, 28, 8, 14, 9.0, "plaster", roof="tar")
# Mid is its own half-turn: one copy.
body("Mid", -10, 10, -10, 10, 5.98, "brick_dark")
box("MidRoof", -10, 10, 5.7, 6.0, -10, 10, "roof")
# Bridge from the tower door to Mid: a deck on steel, not a building.
box_h("MidBridge", -3, 3, 5.6, 6.0, 10, 20, "plank")
box_h("MidBridgeBeamW", -3, -2.7, 4.6, 5.6, 10, 20, "steel")
box_h("MidBridgeBeamE", 2.7, 3, 4.6, 5.6, 10, 20, "steel")

# ================================================================ centre tower: room + stairwell (CQB)
# Room y 6..11 inside the tower; the roof slab above is 1 m. Door north to the Mid bridge, a
# second door east onto a ledge that drops to the bridge, the stair runs up the west side.
sub_h("TowerRoom", -6, 6, 6.0, 11.0, 21, 29)
sub_h("TowerDoorN", -1.5, 1.5, 6.0, 8.6, 19.7, 21.3)
sub_h("TowerDoorE", 5.7, 7.3, 6.0, 8.6, 22.5, 25.5)
# Hatch: opens where the head would meet the 11 m ceiling, runs to the stair's top end.
sub_h("TowerHatch", -6.0, -3.0, 10.7, 12.3, 24.6, 29.0)
ramp_h("TowerStair", "z", -6.0, -3.0, 21.5, 29.0, 6.0, 12.0, "concrete")
box_h("TowerStairFoot", -6.0, -3.0, 5.94, 6.0, 21.2, 21.6, "hazard")
# Crates in the room, hip height, clear of the stair and both doors.
box_h("TowerCrateA", 1.5, 3.3, 6.0, 7.1, 25.6, 27.6, "plank")
box_h("TowerCrateB", -2.2, -0.6, 6.0, 7.1, 23.0, 24.6, "plank")
# Ledge outside the east door, low step down onto the bridge level is a drop to the street side.
box_h("TowerLedgeE", 7, 9, 5.7, 6.0, 21.5, 26.5, "steel")
# Roof: a sign block on the centre line breaks the spawn-to-spawn sight over both towers.
box_h("TowerSign", -1.6, 1.6, 12.0, 14.6, 22.0, 23.2, "steel")
box_h("TowerTank", 2.5, 5.5, 12.0, 14.4, 24.5, 27.5, "plank")
box_h("TowerHatchRailN", -6.0, -3.0, 12.0, 12.9, 24.3, 24.6, "steel")

# ================================================================ spawn roof
box_h("SpawnBack", -16, 16, 12.0, 13.2, 45.4, 46.0, "team_blue", "team_orange")
box_h("SpawnSideW", -16, -15.6, 12.0, 13.0, 41.0, 46.0, "brick")
box_h("SpawnSideE", 15.6, 16, 12.0, 13.0, 39.0, 46.0, "brick")
# Front baffles with a jog behind the bridge gap, so the bridge line does not hit a spawn point.
box_h("SpawnBaffleW", -10, -2.2, 12.0, 14.2, 35.6, 36.2, "team_blue", "team_orange")
box_h("SpawnBaffleE", 2.2, 10, 12.0, 14.2, 35.6, 36.2, "team_blue", "team_orange")
box_h("SpawnJog", -3.0, 3.0, 12.0, 14.2, 37.6, 38.2, "concrete")
box_h("SpawnAC_W", -13.5, -11.5, 12.0, 13.2, 37.0, 38.6, "ac")
box_h("SpawnAC_E", 11.5, 13.5, 12.0, 13.2, 37.0, 38.6, "ac")

# Spawn -> Tower: plank bridge across the 5 m gap (a sprint jump also makes it).
box_h("SpawnBridge", -1.25, 1.25, 11.7, 12.0, 31, 36, "plank")
box_h("SpawnBridgeEdgeN", -1.25, 1.25, 11.94, 12.0, 31, 31.25, "hazard")

# ================================================================ west lane (low, stepped)
# Spawn (12) -> WA (9): stair across the 5 m gap.
ramp_h("WestStair", "x", 37.2, 40.0, -21.0, -16.0, 9.0, 12.0, "concrete")
# WA (9) -> WB (6): plank down across the 4 m gap, or jump it.
ramp_h("WestPlank", "z", -26.2, -24.0, 22.0, 26.0, 6.0, 9.0, "plank")
# WB (6) -> WM (4)
ramp_h("WestRamp", "z", -27.4, -25.2, 5.0, 9.5, 4.0, 6.0, "concrete")
# WM (4) -> Mid (6): long plank, the half-turn is the east cross plank.
ramp_h("CrossPlank", "x", -1.1, 1.1, -18.0, -10.0, 4.0, 6.0, "plank")
box_h("WA_Tank", -27.0, -24.0, 9.0, 11.6, 33.0, 36.0, "plank")
box_h("WA_Vent", -23.5, -22.0, 9.0, 10.1, 28.0, 30.0, "ac")
box_h("WB_AC1", -23.0, -21.0, 6.0, 7.2, 14.0, 15.8, "ac")
box_h("WB_AC2", -27.5, -25.5, 6.0, 7.2, 17.5, 19.0, "ac")
box_h("WM_Wall", -24.0, -22.0, 4.0, 5.2, -2.5, 2.5, "brick")
box_h("WM_Edge", -28.0, -27.6, 4.0, 4.9, -5.0, 5.0, "brick")

# ================================================================ east lane (high)
# Fire escape up the west face of EA: landing at spawn height, a flight up the face, top landing.
box_h("FireLanding", 15.8, 18.0, 11.7, 12.0, 34.0, 37.0, "steel")
ramp_h("FireEscape", "z", 15.8, 18.0, 34.0, 27.0, 12.0, 15.0, "steel")
box_h("FireTop", 15.8, 18.0, 14.7, 15.0, 25.2, 27.0, "steel")
box_h("FireRail", 15.6, 15.8, 12.0, 13.0, 27.0, 35.8, "steel")
for i, z in enumerate((27.5, 31.0, 34.5)):
    box_h("FireStrut%d" % i, 15.9, 16.2, BASE, 11.7, z, z + 0.3, "steel")
# EA (15) -> EB (9)
ramp_h("EastStair", "z", 19.0, 21.4, 14.0, 24.0, 9.0, 15.0, "concrete")
# EA cover: knee wall on the north edge, gap where the stair lands.
box_h("EA_LipW", 21.4, 28.0, 15.0, 16.0, 24.0, 24.4, "concrete")
box_h("EA_Vent", 23.5, 26.0, 15.0, 16.3, 29.0, 31.0, "ac")
box_h("EA_Antenna", 26.5, 27.0, 15.0, 19.0, 34.5, 35.0, "steel")
# EB (9) -> Mid (6)
ramp_h("EastPlank", "x", 8.0, 10.0, 10.0, 17.0, 6.0, 9.0, "plank")
box_h("EB_AC", 23.0, 25.0, 9.0, 10.2, 10.0, 12.0, "ac")

# ================================================================ mid
box("Kiosk", -2.0, 2.0, 6.0, 8.6, -2.0, 2.0, "brick")
box("KioskRoof", -2.4, 2.4, 8.6, 8.8, -2.4, 2.4, "steel")
box_h("MidAC1", 4.0, 6.0, 6.0, 7.2, 4.0, 5.6, "ac")
box_h("MidAC2", -7.4, -5.4, 6.0, 7.2, 2.6, 4.2, "ac")
box_h("MidWall", 5.0, 8.5, 6.0, 7.1, -3.2, -2.6, "concrete")

# ================================================================ backdrop (no collision, not on the minimap)
rng = random.Random(7)
box_bd = []
for i in range(46):
    ang = (i / 46.0) * math.tau + rng.uniform(-0.05, 0.05)
    dist = rng.uniform(85, 150)
    cx, cz = math.sin(ang) * dist * 0.85, math.cos(ang) * dist * 1.1
    w = rng.uniform(10, 22)
    d = rng.uniform(10, 22)
    h = rng.uniform(30, 110)
    mat = rng.choice(["sky_a", "sky_b", "sky_c"])
    backdrop.append(("Tower%02d" % i, (cx, BASE + h / 2, cz), (w, h, d), mat))
    # A few lit window bands facing the map.
    if rng.random() < 0.55:
        for k in range(rng.randint(1, 3)):
            y = BASE + rng.uniform(0.35, 0.9) * h
            glows.append(("Glow%02d_%d" % (i, k), (cx, y, cz), (w + 0.1, 0.5, d + 0.1)))
backdrop.append(("Street", (0, BASE - 0.5, 0), (420, 1, 420), "street"))

# ================================================================ lights
WARM = (1.0, 0.84, 0.66)
COOL = (0.75, 0.85, 1.0)
light_h("TowerRoom", (0.0, 9.6, 25.0), WARM, 0.9, 11.0)
light_h("StairLight", (-4.5, 11.0, 23.0), WARM, 0.5, 7.0)
light_h("SpawnLamp", (0.0, 15.0, 41.0), COOL, 0.35, 14.0)
light_h("FireLamp", (17.0, 16.6, 30.0), WARM, 0.5, 8.0)
lights.append(("MidLamp", (0.0, 9.6, 0.0), WARM, 0.45, 13.0))


def team_spawns():
    blue = []
    for z in (40.0, 43.4):
        for x in (-13.0, -8.0, -3.4, 3.4, 8.0, 13.0):
            blue.append((x, 12.0, z))
    return blue


FFA = [(-13, 12, 41), (-24.5, 9, 39), (-22, 6, 12), (-25, 4, -1), (22, 15, 33), (24, 9, 11),
       (4, 6, 8), (-3, 12, 27.5), (2, 6, 27)]


def main():
    mats = []
    for n in nodes:
        if n[4] not in mats:
            mats.append(n[4])
    for b in backdrop:
        if b[3] not in mats:
            mats.append(b[3])
    out = ["[gd_scene format=3]", ""]
    out += ['[ext_resource type="Shader" path="res://shaders/world_paint.gdshader" id="1_paint"]', ""]
    out += [
        # Late afternoon over the city: warm sun, blue-grey haze that swallows the far towers.
        '[sub_resource type="ProceduralSkyMaterial" id="Sky_mat"]',
        "sky_top_color = Color(0.30, 0.42, 0.62, 1)",
        "sky_horizon_color = Color(0.82, 0.72, 0.62, 1)",
        "sky_curve = 0.1",
        "ground_bottom_color = Color(0.22, 0.24, 0.27, 1)",
        "ground_horizon_color = Color(0.7, 0.64, 0.58, 1)",
        "sun_angle_max = 20.0",
        "sun_curve = 0.2",
        "",
        '[sub_resource type="Sky" id="Sky"]',
        'sky_material = SubResource("Sky_mat")',
        "radiance_size = 1",
        "",
        '[sub_resource type="Environment" id="Env"]',
        "background_mode = 2",
        'sky = SubResource("Sky")',
        "ambient_light_source = 3",
        "ambient_light_color = Color(0.58, 0.6, 0.66, 1)",
        "ambient_light_sky_contribution = 0.8",
        "ambient_light_energy = 0.8",
        "reflected_light_source = 2",
        "tonemap_mode = 4",
        "tonemap_exposure = 1.05",
        "tonemap_white = 6.0",
        "ssao_enabled = true",
        "ssao_radius = 1.2",
        "ssao_intensity = 1.6",
        "ssao_power = 1.4",
        "ssao_detail = 0.4",
        "ssao_light_affect = 0.15",
        "glow_enabled = true",
        "glow_intensity = 0.5",
        "glow_strength = 0.9",
        "glow_bloom = 0.0",
        "glow_blend_mode = 1",
        "glow_hdr_threshold = 1.2",
        "fog_enabled = true",
        "fog_mode = 1",
        "fog_light_color = Color(0.7, 0.68, 0.66, 1)",
        "fog_density = 0.45",
        "fog_sky_affect = 0.0",
        "fog_depth_begin = 40.0",
        "fog_depth_end = 200.0",
        "fog_depth_curve = 1.4",
        "adjustment_enabled = true",
        "adjustment_contrast = 1.06",
        "adjustment_saturation = 1.08",
        "",
    ]
    for m in mats:
        (r, g, b), rough = MATS[m]
        pat, wear, line_dark, grain = PAINT[m]
        out += ['[sub_resource type="ShaderMaterial" id="Mat_%s"]' % m,
                'shader = ExtResource("1_paint")',
                "shader_parameter/albedo = Color(%s, %s, %s, 1)" % (fmt(r), fmt(g), fmt(b)),
                "shader_parameter/roughness = %s" % fmt(rough),
                "shader_parameter/pattern = %d" % pat,
                "shader_parameter/wear = %s" % fmt(wear),
                "shader_parameter/line_dark = %s" % fmt(line_dark),
                "shader_parameter/grain = %s" % fmt(grain), ""]
    out += ['[sub_resource type="StandardMaterial3D" id="Mat_glow"]',
            "albedo_color = Color(1, 0.82, 0.55, 1)",
            "emission_enabled = true",
            "emission = Color(1, 0.78, 0.5, 1)",
            "emission_energy_multiplier = 1.6", ""]
    for i, (name, c, s, m) in enumerate(backdrop):
        out += ['[sub_resource type="BoxMesh" id="BM_%d"]' % i,
                "size = Vector3(%s, %s, %s)" % tuple(fmt(v) for v in s), ""]
    for i, (name, c, s) in enumerate(glows):
        out += ['[sub_resource type="BoxMesh" id="GM_%d"]' % i,
                "size = Vector3(%s, %s, %s)" % tuple(fmt(v) for v in s), ""]
    out += ['[node name="Skyline" type="Node3D"]', "metadata/kill_y = %s" % fmt(KILL_Y), ""]
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env")', ""]
    out += ['[node name="Sun" type="DirectionalLight3D" parent="."]',
            "transform = Transform3D(0.766, -0.4545, 0.4545, 0, 0.7071, 0.7071, -0.6428, -0.5417, 0.5417, 8, 30, 10)",
            "light_energy = 1.2",
            "light_color = Color(1, 0.9, 0.78, 1)",
            "shadow_enabled = true",
            "shadow_bias = 0.04",
            "shadow_normal_bias = 1.2",
            "shadow_blur = 1.4",
            "directional_shadow_split_1 = 0.08",
            "directional_shadow_split_2 = 0.22",
            "directional_shadow_split_3 = 0.5",
            "directional_shadow_blend_splits = true",
            "directional_shadow_max_distance = 120.0", ""]
    out += ['[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]', ""]
    out += ['[node name="Arena" type="CSGCombiner3D" parent="."]',
            "use_collision = true", "collision_layer = 1", "collision_mask = 0", ""]
    for name, typ, xf, extras, mat, parent in nodes:
        out += ['[node name="%s" type="%s" parent="%s"]' % (name, typ, parent), "transform = %s" % xf]
        out += extras
        out += ['material = SubResource("Mat_%s")' % mat, ""]
    out += ['[node name="Backdrop" type="Node3D" parent="."]', ""]
    for i, (name, c, s, m) in enumerate(backdrop):
        out += ['[node name="%s" type="MeshInstance3D" parent="Backdrop"]' % name,
                "transform = %s" % xform(IDENT, c),
                "cast_shadow = 0",
                'mesh = SubResource("BM_%d")' % i,
                'surface_material_override/0 = SubResource("Mat_%s")' % m, ""]
    for i, (name, c, s) in enumerate(glows):
        out += ['[node name="%s" type="MeshInstance3D" parent="Backdrop"]' % name,
                "transform = %s" % xform(IDENT, c),
                "cast_shadow = 0",
                'mesh = SubResource("GM_%d")' % i,
                'surface_material_override/0 = SubResource("Mat_glow")', ""]
    for name, pos, col, energy, rng_ in lights:
        out += ['[node name="%s" type="OmniLight3D" parent="."]' % name,
                "transform = %s" % xform(IDENT, pos),
                "light_color = Color(%s, %s, %s, 1)" % tuple(fmt(v) for v in col),
                "light_energy = %s" % fmt(energy),
                "omni_range = %s" % fmt(rng_),
                "shadow_enabled = false", ""]
    with open(OUT, "w") as f:
        f.write("\n".join(out).rstrip("\n") + "\n")
    print("wrote %s (%d csg nodes, %d backdrop, %d lights)" % (
        os.path.normpath(OUT), len(nodes), len(backdrop) + len(glows), len(lights)))
    for n, d in slopes:
        print("  slope %-12s %.1f deg" % (n, d))
    print("  team spawns:", team_spawns())


if __name__ == "__main__":
    main()
