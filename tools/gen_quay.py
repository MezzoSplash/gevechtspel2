#!/usr/bin/env python3
"""Generates scenes/maps/quay.tscn: "Quay", a dry dock bigger than Rooftops.

Same pipeline as Rooftops: CSG under one Arena combiner (collision layer 1), so main.gd
bakes the bot navmesh from it. Re-run after editing:  python3 tools/gen_quay.py

Half-turn, not a mirror (Blue at +Z, Orange at -Z). A mirrored basis drops CSG collision.
Flat colours, no PBR. Surf faces are the Rooftops triangle (~57°). Anything steeper than
45° is surf; walk ramps stay near 30° so bots (nav slope 46°) can climb them.

Layout (metres, Y up). Playable inside the walls is about 90 x 123.
  - Dock floor at 0 m through the middle. Quay decks at 4 m on the west and east.
    Loods roofs at 10 m behind each spawn. Outer walls are 16.5 m, above the surf ridge.
  - West flank surf: 10 m roof down to the 4 m quay, along the west wall through mid-map.
    The east flank is the half-turn (high end on the orange roof).
  - Inner quay surfs: 4 m down to the dock floor, on the dock side of each quay.
  - A flat surf across the dock, so a run can cross the middle.
  - Radial corner: a concave quarter-circle, radius 14 m at the toe. Off the east roof
    the run turns west into the dock, toward the middle of the map. The orange corner
    is the half-turn, so it turns east into the dock. One path of short rectangles.
  - Every roof has an interior stair and an exterior ramp. The foot of each one sits on
    open floor, clear of the wall. Bots walk those, not the surf.
  - A steel walk climbs the north-east corner of the east loods, from the quay to the
    roof, so a side run can reach the corner surf. Orange is the half-turn.
"""
import json
import math
import os
import sys

import speed_strip

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "quay.tscn")

# Ten materials. Concrete is everything poured (decks, walls, ramps, the outer walls), brick is
# the two loods and the two harbour offices, steel is everything bolted on (stair rails, steel
# walk, gantry), containers are the only loose cover. Yellow only marks surf edges and ramp feet.
MATS = {
    "floor": ((0.24, 0.25, 0.26), 0.92),
    "concrete": ((0.40, 0.40, 0.38), 0.88),
    "roof": ((0.30, 0.34, 0.31), 0.90),
    "brick": ((0.52, 0.36, 0.24), 0.85),
    "steel": ((0.30, 0.33, 0.37), 0.62),
    "hazard": ((0.78, 0.62, 0.14), 0.75),
    "surf": ((0.36, 0.42, 0.48), 0.62),
    "team_blue": ((0.27, 0.46, 0.62), 0.82),
    "team_orange": ((0.70, 0.44, 0.18), 0.82),
    "container": ((0.56, 0.22, 0.16), 0.78),
}

# ~57° face. Buried 0.1 m into the wall and the floor. Same triangle as Rooftops.
SURF_POLY = (-0.1, -0.1, 3.30, -0.1, -0.1, 5.15)
SURF_TOE = 3.30
# Unit normal of that hypotenuse, pointing to the open side (+X) and up.
_FACE_H = math.hypot(3.40, 5.25)
FACE_N = (5.25 / _FACE_H, 3.40 / _FACE_H, 0.0)  # ny ≈ 0.543

ROOF_Y = 10.0
QUAY_Y = 4.0
CEIL_Y = 3.2
# Street ramp onto each loods. 3.4 m wide, ~34°, foot in the open street.
# The west street stair breaks the roof until z=44.5, so that ramp is at the south end.
# The east street stair breaks it from z=33.5, so that ramp is at the north end.
EXT_W_Z0, EXT_W_Z1 = 45.05, 48.35
EXT_E_Z0, EXT_E_Z1 = 29.75, 33.15
EXT_X_FOOT = -3.5
EXT_X_TOP = -18.4
WALL_H = 16.5  # surf ridge at the 10 m end sits near 15.2; the wall stays above it
PARAPET = 1.15
HALF_X = 46.0
HALF_Z = 62.0
WALL_T = 0.8
INNER_X = HALF_X - WALL_T  # 45.2
INNER_Z = HALF_Z - WALL_T

# Flank surf: 6 m of drop over 43 m of extrusion → about 8° along the run.
FLANK_DEPTH = 43.0
FLANK_DROP = 6.0
FLANK_PITCH = math.asin(FLANK_DROP / FLANK_DEPTH)
FLANK_Z = 40.0  # high-end origin, on the blue roof lip
FLANK_X = -(INNER_X - 0.05)  # buried 5 cm into the west inner face

# Dock-edge surf: 4 m down to the floor.
DOCK_DEPTH = 26.0
DOCK_DROP = 4.0
DOCK_PITCH = math.asin(DOCK_DROP / DOCK_DEPTH)
DOCK_X = -18.0
DOCK_Z = 14.0

# Radial corner. Toe radius 14 m, 90°. The profile is mirrored (toe at local -X) and the
# arc is clockwise, so the open side stays on the inside while the run turns toward the
# middle of the map. Centre sits west of the east-roof entry: travel leaves the roof
# going north, then the bend carries it west into the dock. Orange uses the same call
# with the half-turn (centre and angles +180°), which sends that side east into the dock.
# The straight run-in stops short of the east roof (that roof starts at z=28).
CORNER_C = (12.0, 24.0)
CORNER_A0 = 0.0
CORNER_A1 = -math.pi * 0.5
CORNER_R = 14.0
R_ORIGIN = CORNER_R + SURF_TOE
CORNER_LEAD_IN = 3.2
CORNER_LEAD_OUT = 6.0
# Mirrored Rooftops triangle. Toe on -X, so the face opens toward the arc centre.
CORNER_POLY = (0.1, -0.1, -SURF_TOE, -0.1, 0.1, 5.15)
CORNER_TOE = -SURF_TOE
CORNER_FACE = (-FACE_N[0], FACE_N[1], 0.0)
CORNER_FILL = (0.15, -0.05, -3.10, -0.05, -3.10, -14.0, 0.15, -14.0)
CORNER_SPACING = 0.8  # control points; the mesh steps finer than this
CORNER_PITCH = 0.0  # filled in by add_corner once the path length is known
CORNER_LEN = 0.0

nodes = []  # (name, type, transform, extra_lines, mat, parent)
curves = []  # (id, [Vector3, ...]) path samples, profile origin
paths = []  # (node name, curve id) Path3D under Arena
lights = []
checks = []  # (label, basis, origin, along, y_expect)
corner_problems = []
corner_log = []  # (label, det, ny, toe, y_expect, ok) for the mirrored corner profile
probe = []  # dicts written for the headless ray test
corner_exits = []  # (prefix, toe, forward xz, open xz) for the speed strip at the launch
strips = []


def fmt(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def xform(basis_cols, origin):
    (X, Y, Z) = basis_cols
    vals = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2]] + list(origin)
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in vals)


IDENT = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


def add(name, typ, xf, extras, mat, parent="Arena"):
    nodes.append((name, typ, xf, extras, mat, parent))


def box(name, x0, x1, y0, y1, z0, z1, mat, op=None):
    c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    s = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
    extra = ["size = Vector3(%s, %s, %s)" % tuple(fmt(v) for v in s)]
    if op is not None:
        extra.append("operation = %d" % op)
    add(name, "CSGBox3D", xform(IDENT, c), extra, mat)


def sub(name, x0, x1, y0, y1, z0, z1):
    """Cuts whatever was unioned earlier in the file. Later unions stay whole."""
    box(name, x0, x1, y0, y1, z0, z1, "concrete", op=2)


def pair_box(name, x0, x1, y0, y1, z0, z1, mat, mat_o=None):
    """Blue piece plus the half-turn. x and z both flip, so det of a later surf stays +1."""
    box(name + "B", x0, x1, y0, y1, z0, z1, mat)
    box(name + "O", -x1, -x0, y0, y1, -z1, -z0, mat_o or mat)


def pair_sub(name, x0, x1, y0, y1, z0, z1):
    sub(name + "B", x0, x1, y0, y1, z0, z1)
    sub(name + "O", -x1, -x0, y0, y1, -z1, -z0)


def ramp_z(name, x0, x1, z_low, z_high, h, mat, t=0.35, y0=0.0):
    """Top meets y0 at z_low and y0+h at z_high. Basis det is +1."""
    dz = z_high - z_low
    length = math.hypot(dz, h)
    Z = (0.0, h / length, dz / length)
    Y = (0.0, abs(dz) / length, -h / length * (1 if dz > 0 else -1))
    X = (Y[1] * Z[2] - Y[2] * Z[1], Y[2] * Z[0] - Y[0] * Z[2], Y[0] * Z[1] - Y[1] * Z[0])
    mid = ((x0 + x1) / 2, y0 + h / 2, (z_low + z_high) / 2)
    c = tuple(mid[i] - Y[i] * t / 2 for i in range(3))
    add(name, "CSGBox3D", xform((X, Y, Z), c),
        ["size = Vector3(%s, %s, %s)" % (fmt(abs(x1 - x0)), fmt(t), fmt(length))], mat)


def pair_ramp_z(name, x0, x1, z_low, z_high, h, mat, y0=0.0):
    ramp_z(name + "B", x0, x1, z_low, z_high, h, mat, y0=y0)
    ramp_z(name + "O", -x1, -x0, -z_low, -z_high, h, mat, y0=y0)


def ramp_x(name, z0, z1, x_low, x_high, h, mat, t=0.35, y0=0.0):
    """Top meets y0 at x_low and y0+h at x_high."""
    dx = x_high - x_low
    length = math.hypot(dx, h)
    X = (dx / length, h / length, 0.0)
    Y = (-h / length * (1 if dx > 0 else -1), abs(dx) / length, 0.0)
    Z = (X[1] * Y[2] - X[2] * Y[1], X[2] * Y[0] - X[0] * Y[2], X[0] * Y[1] - X[1] * Y[0])
    mid = ((x_low + x_high) / 2, y0 + h / 2, (z0 + z1) / 2)
    c = tuple(mid[i] - Y[i] * t / 2 for i in range(3))
    add(name, "CSGBox3D", xform((X, Y, Z), c),
        ["size = Vector3(%s, %s, %s)" % (fmt(length), fmt(t), fmt(abs(z1 - z0)))], mat)


def pair_ramp_x(name, z0, z1, x_low, x_high, h, mat, y0=0.0):
    ramp_x(name + "B", z0, z1, x_low, x_high, h, mat, y0=y0)
    ramp_x(name + "O", -z1, -z0, -x_low, -x_high, h, mat, y0=y0)


def wedge_x(name, z0, z1, x_low, x_high, h, mat, y0=0.0, top_drop=0.0, bury=0.1, lip=0.05):
    """Solid ramp: top runs from y0 at x_low to y0+h at x_high, solid down to y0-bury.

    A slab ramp hangs in the air: the capsule bumps its head under the low end, and the
    top edge sat a few cm under the deck it climbs to. A wedge has neither. `lip` runs the
    top flat for a few cm past x_high, under the deck it meets. `top_drop` lowers the whole
    top (a skirt that stays inside an existing slab, so the two tops never z-fight).
    """
    sgn = 1.0 if x_high > x_low else -1.0
    top_hi = y0 + h - top_drop
    pts = [
        (x_low, y0 - top_drop),
        (x_high, top_hi),
        (x_high + sgn * lip, top_hi),
        (x_high + sgn * lip, y0 - bury),
        (x_low, y0 - bury),
    ]
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
               for i in range(len(pts)))
    if area < 0.0:
        pts.reverse()  # CCW in local XY, like the surf triangle
    flat = []
    for x, y in pts:
        flat += [x, y]
    # Extrudes along local -Z, so the node sits on the far (z1) side.
    add(name, "CSGPolygon3D", xform(IDENT, (0.0, 0.0, max(z0, z1))),
        ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in flat),
         "depth = %s" % fmt(abs(z1 - z0))], mat)


def pair_wedge_x(name, z0, z1, x_low, x_high, h, mat, y0=0.0, top_drop=0.0, lip=0.05):
    """Blue wedge plus the half-turn. The polygon is in world X/Y, so the half-turn just negates x."""
    wedge_x(name + "B", z0, z1, x_low, x_high, h, mat, y0=y0, top_drop=top_drop, lip=lip)
    wedge_x(name + "O", -z1, -z0, -x_low, -x_high, h, mat, y0=y0, top_drop=top_drop, lip=lip)


def wedge_z(name, x0, x1, z_low, z_high, h, mat, y0=0.0, top_drop=0.0, base_y=None):
    """wedge_x along z: top from y0 at z_low to y0+h at z_high, solid down to base_y."""
    base = (y0 - 0.1) if base_y is None else base_y
    top_hi = y0 + h - top_drop
    pts = [(z_low, y0 - top_drop), (z_high, top_hi), (z_high, base), (z_low, base)]
    area = sum(pts[i][0] * pts[(i + 1) % 4][1] - pts[(i + 1) % 4][0] * pts[i][1] for i in range(4))
    if area < 0.0:
        pts.reverse()
    flat = []
    for a, b in pts:
        flat += [a, b]
    # local X = world +Z, local Y = up, local Z = world -X: extrudes from x0 toward +X.
    add(name, "CSGPolygon3D", xform(((0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0)), (min(x0, x1), 0.0, 0.0)),
        ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in flat),
         "depth = %s" % fmt(abs(x1 - x0))], mat)


def pair_wedge_z(name, x0, x1, z_low, z_high, h, mat, y0=0.0, top_drop=0.0, base_y=None):
    """Blue wedge_z plus the half-turn (x and z both flip)."""
    wedge_z(name + "B", x0, x1, z_low, z_high, h, mat, y0=y0, top_drop=top_drop, base_y=base_y)
    wedge_z(name + "O", -x1, -x0, -z_low, -z_high, h, mat, y0=y0, top_drop=top_drop, base_y=base_y)


def light(name, pos, col, energy, rng):
    lights.append((name, pos, col, energy, rng))


def pair_light(name, pos, col, energy, rng):
    light(name + "B", pos, col, energy, rng)
    light(name + "O", (-pos[0], pos[1], -pos[2]), col, energy, rng)


def _kick_basis(deg, sign):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a) * sign
    return ((1, 0, 0), (0, c, s), (0, -s, c))


def face_stripe(surf_name, stripe_name):
    """Yellow edge on the surf face. A flat bar at the toe hangs off the overhang."""
    tangent = (-FACE_N[1], FACE_N[0], 0.0)  # up the face, toward the ridge
    normal = FACE_N
    inset = 0.72
    center = (
        SURF_TOE + tangent[0] * inset + normal[0] * -0.005,
        -0.1 + tangent[1] * inset + normal[1] * -0.005,
        -1.7,
    )
    # Columns tangent, normal, -Z. Their determinant is +1.
    basis = (tangent, normal, (0.0, 0.0, -1.0))
    add(stripe_name, "CSGBox3D", xform(basis, center),
        ["size = Vector3(0.55, 0.05, 1.6)"], "hazard", parent="Arena/" + surf_name)


def surf(name, origin, basis, depth, kicks, mat="surf", kick_start=40.0, kick_end=40.0):
    """57° wall-surf. Extrusion runs along local -Z. Basis must be det +1."""
    poly = "polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in SURF_POLY)
    add(name, "CSGPolygon3D", xform(basis, origin), [poly, "depth = %s" % fmt(depth)], mat)
    if kicks in ("both", "start"):
        a = math.radians(kick_start)
        half = 10.0
        add(name + "KickA", "CSGBox3D",
            xform(_kick_basis(kick_start, 1), (1.3, half * math.cos(a), half * math.sin(a))),
            ["operation = 2", "size = Vector3(8, 20, 30)"], mat, parent="Arena/" + name)
    if kicks in ("both", "end"):
        a = math.radians(kick_end)
        half = 10.0
        add(name + "KickB", "CSGBox3D",
            xform(_kick_basis(kick_end, -1), (1.3, half * math.cos(a), -depth - half * math.sin(a))),
            ["operation = 2", "size = Vector3(8, 20, 30)"], mat, parent="Arena/" + name)


def rx(beta):
    """Pitch around local X. Positive beta lowers the far end (local -Z)."""
    c, s = math.cos(beta), math.sin(beta)
    return ((1.0, 0.0, 0.0), (0.0, c, -s), (0.0, s, c))


def mul_basis(a, b):
    """Columns of a*b (apply b first)."""
    out = []
    for col in range(3):
        v = (b[col][0], b[col][1], b[col][2])
        out.append(tuple(a[0][i] * v[0] + a[1][i] * v[1] + a[2][i] * v[2] for i in range(3)))
    return tuple(out)


def basis_det(b):
    (X, Y, Z) = b
    return (X[0] * (Y[1] * Z[2] - Y[2] * Z[1])
            - X[1] * (Y[0] * Z[2] - Y[2] * Z[0])
            + X[2] * (Y[0] * Z[1] - Y[1] * Z[0]))


def yaw_into(ix, iz):
    """Y-up rotation whose local +X is (ix, iz). det +1.
    Local -Z, the downhill, is then (iz, -ix) in the xz plane.
    """
    X = (ix, 0.0, iz)
    Y = (0.0, 1.0, 0.0)
    Z = (X[1] * Y[2] - X[2] * Y[1], X[2] * Y[0] - X[0] * Y[2], X[0] * Y[1] - X[1] * Y[0])
    return (X, Y, Z)


def apply_basis(basis, origin, local):
    return tuple(origin[i] + basis[0][i] * local[0] + basis[1][i] * local[1] + basis[2][i] * local[2]
                 for i in range(3))


def toe_world(basis, origin, along):
    """Toe point `along` metres down local -Z (the downhill)."""
    return apply_basis(basis, origin, (SURF_TOE, -0.1, -along))


def face_ny(basis):
    n = apply_basis(basis, (0, 0, 0), FACE_N)
    return n[1]


def origin_for_toe_y(basis, ox, oz, toe_y):
    """Shift the node up so the toe at local z=0 sits on toe_y."""
    y0 = toe_world(basis, (ox, 0.0, oz), 0.0)[1]
    return (ox, toe_y - y0, oz)


# Yaw 180, det +1. Used to turn the west flank basis onto the east wall.
YAW180 = ((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))


def fill_under(name, basis, origin, depth, bury):
    """Solid under the wedge, down to below y=0, stopping short of the toe.
    Same basis as the surf, so the fill pitches with it and does not cover the face.
    """
    poly = [-0.15, -0.05, 3.10, -0.05, 3.10, -bury, -0.15, -bury]
    add(name, "CSGPolygon3D", xform(basis, origin),
        ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in poly),
         "depth = %s" % fmt(depth)], "concrete")


def watch(label, basis, origin, along, y_expect):
    checks.append((label, basis, origin, along, y_expect))


# ---------------------------------------------------------------- shell
box("Floor", -HALF_X, HALF_X, -1.0, 0.0, -HALF_Z, HALF_Z, "floor")
box("WallWest", -HALF_X, -INNER_X, 0, WALL_H, -HALF_Z, HALF_Z, "concrete")
box("WallEast", INNER_X, HALF_X, 0, WALL_H, -HALF_Z, HALF_Z, "concrete")
box("WallSouth", -HALF_X, HALF_X, 0, WALL_H, INNER_Z, HALF_Z, "team_blue")
box("WallNorth", -HALF_X, HALF_X, 0, WALL_H, -HALF_Z, -INNER_Z, "team_orange")

# Quay decks. Inner face is the dock surf. The flank lane (x < -32) stays at y=0.
pair_box("Quay", -32.0, -18.0, 0.0, QUAY_Y, -22.0, 22.0, "concrete")

# ---------------------------------------------------------------- buildings
# West loods feeds the flank surf. East loods feeds the radial corner.
# Street face is the side toward x=0. WT is the wall; the void stops inside it.
WT = 1.4


def building_shell(name, x0, x1):
    z0, z1 = 28.0, 50.0
    pair_box(name + "Shell", x0, x1, 0.0, ROOF_Y, z0, z1, "brick")
    pair_sub(name + "Void", x0 + WT, x1 - WT, 0.0, CEIL_Y, z0 + WT, z1 - WT)


building_shell("West", -34.0, -14.0)
building_shell("East", 14.0, 34.0)

# Doors. West block street face is x=-14; east block street face is x=14.
# North and south doors sit between the two stairs.
pair_sub("WestDoorN", -25.6, -23.0, 0.0, 2.6, 27.6, 29.6)
pair_sub("WestDoorS", -25.6, -23.0, 0.0, 2.6, 48.4, 50.4)
# Street doors stay off the exterior ramp. West ramp owns the south end of this face.
pair_sub("WestDoorE", -15.6, -13.6, 0.0, 2.6, 39.2, 41.8)
pair_sub("EastDoorN", 23.0, 25.6, 0.0, 2.6, 27.6, 29.6)
pair_sub("EastDoorS", 23.0, 25.6, 0.0, 2.6, 48.4, 50.4)
pair_sub("EastDoorW", 13.6, 15.6, 0.0, 2.6, 46.0, 48.6)
# Windows are holes. Not on the spawn face (south): that looks into the yard.
pair_sub("WestWinN1", -32.2, -30.0, 1.0, 2.5, 27.6, 29.6)
pair_sub("WestWinN2", -20.4, -18.2, 1.0, 2.5, 27.6, 29.6)
# Flank shoot-hole, on the open west wall just south of the lip. The low slot
# sat on shadowed brick and read as part of the wall. This one is tall and
# cuts through to the stair shaft, so the lane sees sky and the stair, not a
# black niche. Clear of the lip (ends z≈42.7) and of WestRailAO.
_W2_Z0, _W2_Z1 = 43.05, 46.20
pair_sub("WestWinW2", -34.4, -31.50, 1.15, 6.40, _W2_Z0, _W2_Z1)
pair_sub("WestWinE", -15.6, -13.6, 1.0, 2.5, 35.6, 37.8)
pair_sub("EastWinN1", 18.2, 20.4, 1.0, 2.5, 27.6, 29.6)
pair_sub("EastWinN2", 30.0, 32.2, 1.0, 2.5, 27.6, 29.6)
pair_sub("EastWinW", 13.6, 15.6, 1.0, 2.5, 35.6, 37.8)
# Jog between the two stairs. Clear of both treads (≥1.2 m) and of both landings.
# Doors sit on the end walls; the jog is mid-room, so it does not close a door.
pair_box("WestJog", -25.5, -23.3, 0.0, CEIL_Y, 36.8, 42.8, "brick")
pair_box("EastJog", 23.3, 25.5, 0.0, CEIL_Y, 36.8, 42.8, "brick")

# Stair shafts. The slot is narrower than the ramp, and it runs the whole climb, so a
# 1.8 m capsule has headroom once the tread leaves the floor. Landings themselves keep
# their ceiling: the slot starts just after the foot.
pair_sub("WestStairASlot", -31.55, -27.25, CEIL_Y - 0.15, ROOF_Y + 0.25, 33.5, 46.35)
pair_sub("WestStairBSlot", -20.55, -16.45, CEIL_Y - 0.15, ROOF_Y + 0.25, 31.7, 44.5)
pair_sub("EastStairASlot", 16.45, 20.55, CEIL_Y - 0.15, ROOF_Y + 0.25, 33.5, 46.35)
pair_sub("EastStairBSlot", 27.25, 31.55, CEIL_Y - 0.15, ROOF_Y + 0.25, 31.7, 44.5)
# Quay edge, cut before the ramp is unioned. The ramp then meets the deck at y=4
# instead of dead-ending into the vertical face.
# The notch is the ramp's own footprint: a narrower one left a deck strip standing on
# both edges of the ramp top, and its end sat 6 cm proud of the tread (the capsule stopped).
QUAY_RAMP_TOP_X = -21.0
pair_sub("QuayNotchS", QUAY_RAMP_TOP_X, -17.5, 0.02, QUAY_Y + 0.35, 15.5, 20.7)
pair_sub("QuayNotchN", QUAY_RAMP_TOP_X, -17.5, 0.02, QUAY_Y + 0.35, -20.7, -15.5)
# Street-ramp slot through the roof edge. Wider than the tread and open to the
# sky, so the roof does not sit as a ledge on either side of the ramp. The west
# stair shaft ends at z=44.5 and the east one starts at z=33.5, so the slot
# stops short of both. Cut before the ramp unions.
pair_sub("ExtNotchW", -19.3, -13.55, 6.3, ROOF_Y + 0.4, 44.70, 48.55)
pair_sub("ExtNotchE", 13.55, 19.3, 6.3, ROOF_Y + 0.4, 29.50, 33.35)
# Slot for the side link. Just wider than the tread, through the north face, so
# the brick does not stand up as a lip. The bottom stays under the ramp; a deep
# cut left a hole in the corner with the landing floating over it.
pair_sub("SideLinkNotch", 31.25, 33.95, 9.05, ROOF_Y + 0.45, 27.55, 30.7)

# ---------------------------------------------------------------- harbour office
# Two floors on the middle of each quay deck. Pass-through on the ground floor (west, north and
# south doors), a solid stair along the east wall to the top floor, shoot windows up there and a
# wide opening on the dock side to drop back onto the deck. With the gantry beam on top it
# breaks the long quay and roof-to-roof lines. Orange is the half-turn on the east quay.
OFF_X0, OFF_X1 = -31.0, -20.0
OFF_Z0, OFF_Z1 = -5.0, 5.0
OFF_WT = 0.5
OFF_F1 = QUAY_Y            # ground floor = deck
OFF_SLAB0, OFF_F2 = 7.4, 7.8
OFF_CEIL2 = 11.4
OFF_TOP = 12.0
OFF_STAIR_X0, OFF_STAIR_X1 = -22.6, OFF_X1 + OFF_WT   # against the east wall
# Foot in the south half (open floor in front of it and beside it), crest on the north wall.
OFF_STAIR_Z0, OFF_STAIR_Z1 = 2.4, -3.6                # 3.8 m over 6 m, 32° (loods stairs are 38°)
OFF_DOOR_H = OFF_F1 + 2.7
GANTRY_Y0, GANTRY_Y1 = 11.2, 13.6   # beam over the dock, see "crane gantry"
pair_box("Office", OFF_X0, OFF_X1, OFF_F1, OFF_TOP, OFF_Z0, OFF_Z1, "brick")
pair_sub("OfficeVoid1", OFF_X0 + OFF_WT, OFF_X1 - OFF_WT, OFF_F1, OFF_SLAB0, OFF_Z0 + OFF_WT, OFF_Z1 - OFF_WT)
pair_sub("OfficeVoid2", OFF_X0 + OFF_WT, OFF_X1 - OFF_WT, OFF_F2, OFF_CEIL2, OFF_Z0 + OFF_WT, OFF_Z1 - OFF_WT)
# Ground floor doors, 2.6 m wide.
pair_sub("OfficeDoorW", OFF_X0 - 0.1, OFF_X0 + OFF_WT + 0.1, OFF_F1, OFF_DOOR_H, -1.3, 1.3)
pair_sub("OfficeDoorN", -27.3, -24.7, OFF_F1, OFF_DOOR_H, OFF_Z0 - 0.1, OFF_Z0 + OFF_WT + 0.1)
pair_sub("OfficeDoorS", -27.3, -24.7, OFF_F1, OFF_DOOR_H, OFF_Z1 - OFF_WT - 0.1, OFF_Z1 + 0.1)
pair_sub("OfficeWinN1", -30.0, -28.6, OFF_F1 + 1.0, OFF_F1 + 2.2, OFF_Z0 - 0.1, OFF_Z0 + OFF_WT + 0.1)
pair_sub("OfficeWinS1", -30.0, -28.6, OFF_F1 + 1.0, OFF_F1 + 2.2, OFF_Z1 - OFF_WT - 0.1, OFF_Z1 + 0.1)
# Top floor: shoot windows (sill 1.1 m, eye 1.6 m) on three sides, open on the dock side.
_W2Y0, _W2Y1 = OFF_F2 + 1.1, OFF_F2 + 2.1
for _i, (_a, _b) in enumerate(((-29.6, -27.6), (-25.4, -23.4))):
    pair_sub("OfficeHiN%d" % _i, _a, _b, _W2Y0, _W2Y1, OFF_Z0 - 0.1, OFF_Z0 + OFF_WT + 0.1)
    pair_sub("OfficeHiS%d" % _i, _a, _b, _W2Y0, _W2Y1, OFF_Z1 - OFF_WT - 0.1, OFF_Z1 + 0.1)
for _i, (_a, _b) in enumerate(((-2.8, -1.2), (1.2, 2.8))):
    pair_sub("OfficeHiW%d" % _i, OFF_X0 - 0.1, OFF_X0 + OFF_WT + 0.1, _W2Y0, _W2Y1, _a, _b)
pair_sub("OfficeDrop", OFF_X1 - OFF_WT - 0.1, OFF_X1 + 0.1, OFF_F2, OFF_F2 + 2.6, 1.0, 3.4)
# Slot in the top-floor slab over the stair. Starts where a capsule on the tread would reach
# the slab (tread 5.4 m at z=0.3, head room 2 m), ends on the crest so the tread meets the slab.
pair_sub("OfficeStairSlot", OFF_STAIR_X0, OFF_STAIR_X1, OFF_SLAB0 - 0.1, OFF_F2 + 0.1, OFF_STAIR_Z1, 0.3)

# Subtracts end here. Ramps, surfs and pads are unions and must stay below this line
# in the file, or a later subtract slices them.

# ---------------------------------------------------------------- ramps and pads
# Interior stairs. The foot is a few metres inside the room, so a capsule can stand
# on the floor and walk on. A climbs toward the spawn, B toward the dock.
# 10 m over 12.8 m is 38°, under the 46° nav limit.
pair_ramp_z("WestStairA", -31.9, -26.9, 33.2, 46.0, ROOF_Y, "concrete")
pair_ramp_z("WestStairB", -20.9, -16.1, 44.8, 32.0, ROOF_Y, "concrete")
pair_ramp_z("EastStairA", 16.1, 20.9, 33.2, 46.0, ROOF_Y, "concrete")
pair_ramp_z("EastStairB", 26.9, 31.9, 44.8, 32.0, ROOF_Y, "concrete")
# Yellow edge, flush with the floor. A proud curb stops the capsule.
pair_box("WestStairAEdge", -31.9, -26.9, -0.06, 0.0, 32.95, 33.25, "hazard")
pair_box("WestStairBEdge", -20.9, -16.1, -0.06, 0.0, 44.55, 44.9, "hazard")
pair_box("EastStairAEdge", 16.1, 20.9, -0.06, 0.0, 32.95, 33.25, "hazard")
pair_box("EastStairBEdge", 26.9, 31.9, -0.06, 0.0, 44.55, 44.9, "hazard")
# The shaft runs a little past the crest, so the tread stopped short of the roof
# and left a hole. This plate fills only that gap. It starts on the crest:
# a plate that begins on the slope stands up as a step and the capsule stops.
pair_box("WestStairALand", -31.55, -27.25, ROOF_Y - 0.45, ROOF_Y, 46.0, 46.40, "concrete")
pair_box("WestStairBLand", -20.55, -16.45, ROOF_Y - 0.45, ROOF_Y, 31.65, 32.0, "concrete")
pair_box("EastStairALand", 16.45, 20.55, ROOF_Y - 0.45, ROOF_Y, 46.0, 46.40, "concrete")
pair_box("EastStairBLand", 27.25, 31.55, ROOF_Y - 0.45, ROOF_Y, 31.65, 32.0, "concrete")
# Rails stop at the ceiling and stay off the landing, so the foot is open.
# The street-side bars used to run through the door and the street window.
# They are unions, so they put the cut back: the hole still looked open and
# the capsule (radius 0.4) stopped on a 0.25 m bar just inside the wall.
pair_box("WestRailAO", -32.15, -31.9, 0.0, CEIL_Y, 33.9, 42.80, "steel")
pair_box("WestRailAI", -26.9, -26.65, 0.0, CEIL_Y, 33.9, 45.3, "steel")
pair_box("WestRailBN", -16.1, -15.85, 0.0, CEIL_Y, 32.7, 35.35, "steel")
pair_box("WestRailBS", -16.1, -15.85, 0.0, CEIL_Y, 42.05, 44.1, "steel")
pair_box("WestRailBI", -20.9, -20.65, 0.0, CEIL_Y, 32.7, 44.1, "steel")
pair_box("EastRailAN", 15.85, 16.1, 0.0, CEIL_Y, 33.9, 35.35, "steel")
pair_box("EastRailAS", 15.85, 16.1, 0.0, CEIL_Y, 38.05, 45.3, "steel")
pair_box("EastRailAI", 20.9, 21.15, 0.0, CEIL_Y, 33.9, 45.3, "steel")
pair_box("EastRailBO", 31.9, 32.15, 0.0, CEIL_Y, 32.7, 44.1, "steel")
pair_box("EastRailBI", 26.65, 26.9, 0.0, CEIL_Y, 32.7, 44.1, "steel")
# Same test as the balcony pier: a later union must not land in an opening.
_rail_holes = (
    ("WestWinW2", (-34.35, -31.55, 1.20, 6.30, _W2_Z0 + 0.05, _W2_Z1 - 0.05)),
    ("WestDoorE", (-15.55, -13.65, 0.05, 2.55, 39.25, 41.75)),
    ("WestWinE", (-15.55, -13.65, 1.05, 2.45, 35.65, 37.75)),
    ("EastWinW", (13.65, 15.55, 1.05, 2.45, 35.65, 37.75)),
)
_rail_bars = (
    ("WestRailAO", (-32.15, -31.9, 0.0, CEIL_Y, 33.9, 42.80)),
    ("WestRailBN", (-16.1, -15.85, 0.0, CEIL_Y, 32.7, 35.35)),
    ("WestRailBS", (-16.1, -15.85, 0.0, CEIL_Y, 42.05, 44.1)),
    ("EastRailAN", (15.85, 16.1, 0.0, CEIL_Y, 33.9, 35.35)),
    ("EastRailAS", (15.85, 16.1, 0.0, CEIL_Y, 38.05, 45.3)),
)
for _bar_name, _bar in _rail_bars:
    for _hole_name, _hole in _rail_holes:
        if (_bar[0] < _hole[1] and _hole[0] < _bar[1] and _bar[2] < _hole[3]
                and _hole[2] < _bar[3] and _bar[4] < _hole[5] and _hole[4] < _bar[5]):
            corner_problems.append("%s overlaps %s" % (_bar_name, _hole_name))

# Exterior ramp, the second way up. Climbs in toward the roof, not along it.
# 3.4 m wide. The notch takes the brick out past both edges of the tread.
# The landing is the same height as the roof, and the ramp arrives on its edge.
pair_ramp_x("WestRamp", EXT_W_Z0, EXT_W_Z1, EXT_X_FOOT, EXT_X_TOP, ROOF_Y, "concrete")
pair_ramp_x("EastRamp", EXT_E_Z0, EXT_E_Z1, -EXT_X_FOOT, -EXT_X_TOP, ROOF_Y, "concrete")
# Solid foot under the low end of each street ramp. Under the bare slab the underside was
# head height for the first few metres: players walked in and stuck on their head.
# Top 3 cm under the slab's top, so it stays inside the slab (no z-fight). Past 2.6 m
# the street under the ramp is open as before.
_SKIRT_H = 2.6
_skirt_x = EXT_X_FOOT + (EXT_X_TOP - EXT_X_FOOT) * (_SKIRT_H / ROOF_Y)
pair_wedge_x("WestRampFoot", EXT_W_Z0 + 0.03, EXT_W_Z1 - 0.03, EXT_X_FOOT, _skirt_x, _SKIRT_H, "concrete",
             top_drop=0.03, lip=0.0)
pair_wedge_x("EastRampFoot", EXT_E_Z0 + 0.03, EXT_E_Z1 - 0.03, -EXT_X_FOOT, -_skirt_x, _SKIRT_H, "concrete",
             top_drop=0.03, lip=0.0)
pair_box("WestRampLand", EXT_X_TOP - 1.35, EXT_X_TOP, ROOF_Y - 0.45, ROOF_Y, 44.70, 48.55, "concrete")
pair_box("EastRampLand", 18.4, 19.75, ROOF_Y - 0.45, ROOF_Y, 29.50, 33.35, "concrete")
pair_box("WestRampEdge", EXT_X_FOOT - 0.2, EXT_X_FOOT + 0.2, -0.06, 0.0, EXT_W_Z0, EXT_W_Z1, "hazard")
pair_box("EastRampEdge", -EXT_X_FOOT - 0.2, -EXT_X_FOOT + 0.2, -0.06, 0.0, EXT_E_Z0, EXT_E_Z1, "hazard")

# Quay ↔ dock. Foot on the dock floor, top flush with the deck at the end of the notch.
# ~21°, wide enough for two capsules. Kept off the dock surf (high end is z≈14).
# Solid wedge, 2 cm wider than the notch on each side (that part hides in the deck).
pair_wedge_x("QuayRampS", 15.48, 20.72, -10.4, QUAY_RAMP_TOP_X, QUAY_Y, "concrete")
pair_wedge_x("QuayRampN", -20.72, -15.48, -10.4, QUAY_RAMP_TOP_X, QUAY_Y, "concrete")
pair_box("QuayRampSEdge", -10.6, -10.25, -0.06, 0.0, 15.5, 20.7, "hazard")
pair_box("QuayRampNEdge", -10.6, -10.25, -0.06, 0.0, -20.7, -15.5, "hazard")

# Office stair: solid wedge (nothing to walk under), crest flush with the top floor at z=3.0.
pair_wedge_z("OfficeStair", OFF_STAIR_X0, OFF_STAIR_X1, OFF_STAIR_Z0, OFF_STAIR_Z1, OFF_F2 - OFF_F1, "concrete", y0=OFF_F1)
pair_box("OfficeStairEdge", OFF_STAIR_X0, OFF_STAIR_X1, OFF_F1 - 0.06, OFF_F1, OFF_STAIR_Z0, OFF_STAIR_Z0 + 0.3, "hazard")
# Behind the crest the ground floor would be a 2 x 0.9 m nook under the slab. Solid instead.
pair_box("OfficeNook", OFF_STAIR_X0, OFF_STAIR_X1, OFF_F1, OFF_SLAB0, OFF_Z0 + OFF_WT, OFF_STAIR_Z1, "concrete")

# ---------------------------------------------------------------- flank surf, 10 m → 4 m, mid-wall
# Opens +X (into the map). Downhill is -Z. High end on the roof lip, low end on the quay.
FLANK_BASIS = mul_basis(yaw_into(1.0, 0.0), rx(FLANK_PITCH))
flank_o = origin_for_toe_y(FLANK_BASIS, FLANK_X, FLANK_Z, ROOF_Y)
surf("FlankW", flank_o, FLANK_BASIS, FLANK_DEPTH, "both", kick_start=48.0, kick_end=32.0)
fill_under("FillFlankW", FLANK_BASIS, flank_o, FLANK_DEPTH, ROOF_Y + 1.0)
watch("flankW high", FLANK_BASIS, flank_o, 0.0, ROOF_Y)
watch("flankW low", FLANK_BASIS, flank_o, FLANK_DEPTH, QUAY_Y)

# East flank is the half-turn of the west one: yaw 180, origin flipped.
FLANK_E_BASIS = mul_basis(YAW180, FLANK_BASIS)
flank_e = (-flank_o[0], flank_o[1], -flank_o[2])
surf("FlankE", flank_e, FLANK_E_BASIS, FLANK_DEPTH, "both", kick_start=48.0, kick_end=32.0)
fill_under("FillFlankE", FLANK_E_BASIS, flank_e, FLANK_DEPTH, ROOF_Y + 1.0)
watch("flankE high", FLANK_E_BASIS, flank_e, 0.0, ROOF_Y)
watch("flankE low", FLANK_E_BASIS, flank_e, FLANK_DEPTH, QUAY_Y)

# Walk from the west roof to the high toe. Full height, and only as wide as the
# entry, so it reads as part of the building. A thin plate here hung in the lane.
# The west face stops on the toe: past it the box would sit on the surf.
_toe_hi = toe_world(FLANK_BASIS, flank_o, 0.0)
_LIP_Z0 = _toe_hi[2] - 0.12
_LIP_Z1 = _toe_hi[2] + 2.7
# 6 cm past the toe, under the face, so the walk and the surf share an edge.
# The lip is an arch: the side lane runs under it (3.4 m clear), so the pocket behind the
# loods is no longer cut off from the quay. Both ends sit in solid (the surf fill, the loods).
LIP_ARCH_Y = 3.4
pair_box("FlankLip", _toe_hi[0] - 0.06, -32.2, LIP_ARCH_Y, ROOF_Y, _LIP_Z0, _LIP_Z1, "concrete")
# The lip is a later union and reaches through the west wall. It must stop
# short of the flank shoot-hole or it fills that cut back in.
if _LIP_Z1 > _W2_Z0 and _toe_hi[0] - 0.06 < -31.50:
    corner_problems.append("FlankLip overlaps WestWinW2")
# On the lip, in from the toe. Past the toe the bar would hang in the air.
pair_box("FlankLipEdge", _toe_hi[0] + 0.04, _toe_hi[0] + 0.34, ROOF_Y - 0.06, ROOF_Y,
         _LIP_Z0 + 0.25, _LIP_Z1 - 0.35, "hazard")

# Low end of the flank. Solid from the floor up to the quay, buried into the deck
# so the join is not a lip on two posts. Stays west of the dock surf.
_toe_lo = toe_world(FLANK_BASIS, flank_o, FLANK_DEPTH)
pair_box("FlankDeck", _toe_lo[0] - 0.15, -29.0, 0.0, QUAY_Y,
         _toe_lo[2] - 12.0, _toe_lo[2] + 0.4, "concrete")

# ---------------------------------------------------------------- side lanes
# The ground lane between each loods and the outer wall used to dead-end on the 4 m quay.
# Now the quay deck runs out to the wall and each end of every side lane has a 12° walk ramp:
# yard strip -> lane -> ramp -> quay deck -> ramp -> lane -> the other yard strip.
#
# Under the flank surf the deck starts inside the fill (x=-42.2) and stays below the face:
# the toe is at y>=4 wherever the deck is, and 0.35 m in from the toe the face is 0.54 m higher.
# Past the low end of the surf the deck goes all the way to the wall.
SURF_DECK_X = -42.2
# Runs 0.8 m on under the surf's low end: the fill's end leans, and a shorter deck left a sealed sliver.
pair_box("DeckWallN", -INNER_X, -32.0, 0.0, QUAY_Y, -22.0, _toe_lo[2] + 0.8, "concrete")
pair_box("DeckWallS", SURF_DECK_X, -32.0, 0.0, QUAY_Y, _toe_lo[2], 22.0, "concrete")
# The fill stops 0.2 m short of the toe, so the toe overhung a slot down to the floor. Now that
# you walk beside it, close the slot: a skirt straight down from just under the toe. It never
# reaches the face (2 cm under the toe line), so the surf is the same surface as before.
for _nm, _bs, _org in (("FlankSkirtW", FLANK_BASIS, flank_o), ("FlankSkirtE", FLANK_E_BASIS, flank_e)):
    add(_nm, "CSGPolygon3D", xform(_bs, _org),
        ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in (3.05, -0.12, SURF_TOE - 0.01, -0.12,
                                                                         SURF_TOE - 0.01, -(ROOF_Y + 1.0), 3.05, -(ROOF_Y + 1.0))),
         "depth = %s" % fmt(FLANK_DEPTH)], "concrete")
# Ramps, 4 m over 18 m (12.5°). Solid wedges, tops flush with the deck at the high end.
SIDE_RAMP_FOOT = 40.0
SIDE_RAMP_TOP = 22.0
# Blue pocket (west, under the flank surf) and its half-turn on the orange east side.
pair_wedge_z("PocketRamp", SURF_DECK_X, -33.9, SIDE_RAMP_FOOT, SIDE_RAMP_TOP, QUAY_Y, "concrete")
# Orange-end west lane and its half-turn on the blue east side. Wall to loods.
pair_wedge_z("LaneRamp", -INNER_X, -33.9, -SIDE_RAMP_FOOT, -SIDE_RAMP_TOP, QUAY_Y, "concrete")
pair_box("PocketRampEdge", SURF_DECK_X + 0.3, -33.9, -0.06, 0.0, SIDE_RAMP_FOOT, SIDE_RAMP_FOOT + 0.35, "hazard")
pair_box("LaneRampEdge", -INNER_X, -33.9, -0.06, 0.0, -SIDE_RAMP_FOOT - 0.35, -SIDE_RAMP_FOOT, "hazard")
# Under the arch the fill's slanted end left a 3 x 3 m niche against the wall. Fill it up to the
# arch, past the skirt, so the passage is one clean box.
pair_box("LipNiche", -INNER_X, -41.80, 0.0, LIP_ARCH_Y, _LIP_Z0, _LIP_Z1, "concrete")

# ---------------------------------------------------------------- dock surf, 4 m → 0, inner quay face
DOCK_BASIS = mul_basis(yaw_into(1.0, 0.0), rx(DOCK_PITCH))
dock_o = origin_for_toe_y(DOCK_BASIS, DOCK_X, DOCK_Z, QUAY_Y)
surf("DockW", dock_o, DOCK_BASIS, DOCK_DEPTH, "both", kick_start=48.0, kick_end=32.0)
fill_under("FillDockW", DOCK_BASIS, dock_o, DOCK_DEPTH, QUAY_Y + 1.0)
watch("dockW high", DOCK_BASIS, dock_o, 0.0, QUAY_Y)
watch("dockW low", DOCK_BASIS, dock_o, DOCK_DEPTH, 0.0)
DOCK_E_BASIS = mul_basis(YAW180, DOCK_BASIS)
dock_e = (-dock_o[0], dock_o[1], -dock_o[2])
surf("DockE", dock_e, DOCK_E_BASIS, DOCK_DEPTH, "both", kick_start=48.0, kick_end=32.0)
fill_under("FillDockE", DOCK_E_BASIS, dock_e, DOCK_DEPTH, QUAY_Y + 1.0)
watch("dockE high", DOCK_E_BASIS, dock_e, 0.0, QUAY_Y)
watch("dockE low", DOCK_E_BASIS, dock_e, DOCK_DEPTH, 0.0)
_dock_hi = toe_world(DOCK_BASIS, dock_o, 0.0)


def trim_round(target, basis, origin, centre, radius):
    """Cut everything of one surf/fill inside a vertical cylinder (world centre xz).

    The dock surfs run under the radial corner and their last metre came out on the
    inner side of the corner fill: a small wedge standing on the floor. The fill's inner
    wall sits at radius ~14.2, so the cut ends just inside the fill and nothing shows.
    Child of the target, so it cuts only that piece. Local frame = inverse of the basis.
    """
    (X, Y, Z) = basis
    w = (centre[0], 0.0, centre[1])
    d = [w[i] - origin[i] for i in range(3)]
    local = tuple(sum(c[i] * d[i] for i in range(3)) for c in (X, Y, Z))
    inv = ((X[0], Y[0], Z[0]), (X[1], Y[1], Z[1]), (X[2], Y[2], Z[2]))
    add(target + "Trim", "CSGCylinder3D", xform(inv, local),
        ["operation = 2", "radius = %s" % fmt(radius), "height = 40", "sides = 128"],
        "concrete", parent="Arena/" + target)


_TRIM_R = CORNER_R + SURF_TOE - 3.10 + 0.15  # inner fill wall + 15 cm
trim_round("DockE", DOCK_E_BASIS, dock_e, CORNER_C, _TRIM_R)
trim_round("FillDockE", DOCK_E_BASIS, dock_e, CORNER_C, _TRIM_R)
trim_round("DockW", DOCK_BASIS, dock_o, (-CORNER_C[0], -CORNER_C[1]), _TRIM_R)
trim_round("FillDockW", DOCK_BASIS, dock_o, (-CORNER_C[0], -CORNER_C[1]), _TRIM_R)
face_stripe("DockW", "DockLipEdgeB")
face_stripe("DockE", "DockLipEdgeO")

# ---------------------------------------------------------------- cross surf, flat, through the dock
# Same turn as Rooftops: local +X → world -Z (face opens north), extrusion toward -X.
CROSS_BASIS = ((0.0, 0.0, -1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0))
CROSS_DEPTH = 18.0
surf("Cross", (CROSS_DEPTH / 2.0, 0.1, 1.8), CROSS_BASIS, CROSS_DEPTH, "both")
pair_box("CrossEdge", 8.7, 9.15, -0.06, 0.0, 0.4, 3.2, "hazard")
watch("cross", CROSS_BASIS, (CROSS_DEPTH / 2.0, 0.1, 1.8), 0.0, 0.0)

# ---------------------------------------------------------------- radial corner
def _vadd(a, b, s=1.0):
    return (a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s)


def _vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _vcross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _vunit(a):
    length = math.sqrt(_vdot(a, a))
    if length < 1e-8:
        return None
    return (a[0] / length, a[1] / length, a[2] / length)


def looking_at_up(direction):
    """Same frame Godot uses for CSGPolygon path rotation "Path": -Z along travel, Y near world up."""
    forward = _vunit(direction)
    if forward is None:
        return None
    z_axis = (-forward[0], -forward[1], -forward[2])
    x_axis = _vunit(_vcross((0.0, 1.0, 0.0), z_axis))
    if x_axis is None:
        return None
    y_axis = _vcross(z_axis, x_axis)
    return (x_axis, y_axis, z_axis)


def _arc_travel(ang, sweep):
    """Unit tangent of the arc. Negative sweep is clockwise: the turn into the dock."""
    if sweep >= 0.0:
        return (-math.sin(ang), math.cos(ang))
    return (math.sin(ang), -math.cos(ang))


def corner_xz_samples(cx, cz, a0, a1, lead_in, lead_out, spacing):
    """Profile-origin samples. Straight, then the quarter arc, then straight. s is metres along."""
    radius = R_ORIGIN
    sweep = a1 - a0
    arc_len = radius * abs(sweep)
    total = lead_in + arc_len + lead_out
    count = max(2, int(math.ceil(total / spacing)))
    entry_x = cx + math.cos(a0) * radius
    entry_z = cz + math.sin(a0) * radius
    tin = _arc_travel(a0, sweep)
    tout = _arc_travel(a1, sweep)
    exit_x = cx + math.cos(a1) * radius
    exit_z = cz + math.sin(a1) * radius
    pts = []
    for i in range(count + 1):
        dist = total * i / float(count)
        if dist <= lead_in + 1e-8:
            x = entry_x - tin[0] * (lead_in - dist)
            z = entry_z - tin[1] * (lead_in - dist)
        elif dist <= lead_in + arc_len + 1e-8:
            ang = a0 + sweep * ((dist - lead_in) / arc_len)
            x = cx + math.cos(ang) * radius
            z = cz + math.sin(ang) * radius
        else:
            along = dist - (lead_in + arc_len)
            x = exit_x + tout[0] * along
            z = exit_z + tout[1] * along
        pts.append((x, z, dist, total))
    return pts


def _corner_frames(pts, heights):
    origins = [(pts[i][0], heights[i], pts[i][1]) for i in range(len(pts))]
    frames = []
    for i, origin in enumerate(origins):
        if i == 0:
            tangent = _vsub(origins[1], origins[0])
        elif i == len(origins) - 1:
            tangent = _vsub(origins[-1], origins[-2])
        else:
            tangent = _vsub(origins[i + 1], origins[i - 1])
        frames.append((origin, looking_at_up(tangent), tangent))
    return frames


def _toe_point(basis, origin, toe_x):
    return apply_basis(basis, origin, (toe_x, -0.1, 0.0))


def _solve_corner_heights(pts, y_start, y_end):
    """Path Y so the mirrored toe drops linearly. The frame tilts with the slope, so iterate."""
    heights = []
    for pt in pts:
        want = y_start + (y_end - y_start) * (pt[2] / pt[3])
        heights.append(want + 0.1)
    frames = None
    for _ in range(8):
        frames = _corner_frames(pts, heights)
        for i, (origin, basis, _tangent) in enumerate(frames):
            want = y_start + (y_end - y_start) * (pts[i][2] / pts[i][3])
            heights[i] += want - _toe_point(basis, origin, CORNER_TOE)[1]
    return _corner_frames(pts, heights)


# Face point used by the ray probe: part way from the mirrored toe up the hypotenuse.
_FACE_LOCAL = (
    CORNER_TOE + (0.1 - CORNER_TOE) * 0.35,
    -0.1 + (5.15 - -0.1) * 0.35,
)


def _add_path_poly(name, path_name, poly, mat):
    add(name, "CSGPolygon3D", xform(IDENT, (0.0, 0.0, 0.0)), [
        "polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in poly),
        "mode = 2",
        'path_node = NodePath("../%s")' % path_name,
        # Short rectangles. simplify 0 keeps every one, so the bend has no kink.
        "path_interval = 0.5",
        "path_rotation = 1",
        # Accurate follows the curve. The fast path twists each slice, so the
        # bend reads as a row of separate planks.
        "path_rotation_accurate = true",
        "path_simplify_angle = 0",
        "path_joined = false",
    ], mat)


def _add_path_kick(surf_name, kick_name, basis, origin, deg, at_end):
    """Chamfer only this surf's end cap. A sibling subtract would carve the whole map.

    The corner profile is mirrored, so the box sits on -X, across the toe. +1.3 is the
    wall side and would leave the lip the capsule hits.
    """
    angle = math.radians(deg)
    half = 10.0
    sign = -1.0 if at_end else 1.0
    local_z = -half * math.sin(angle) if at_end else half * math.sin(angle)
    local = (-1.6, half * math.cos(angle), local_z)
    add(kick_name, "CSGBox3D",
        xform(mul_basis(basis, _kick_basis(deg, sign)), apply_basis(basis, origin, local)),
        ["operation = 2", "size = Vector3(8, 20, 30)"], "surf", parent="Arena/" + surf_name)


def add_corner(prefix, cx, cz, a0, a1, y_start, y_end):
    """One surf mesh along straight + quarter arc + straight.

    Separate wedges each had an end cap the capsule hit. A path extrusion is a strip of
    rectangles with caps only at the two ends, and those are chamfered.
    """
    global CORNER_PITCH, CORNER_LEN
    pts = corner_xz_samples(cx, cz, a0, a1, CORNER_LEAD_IN, CORNER_LEAD_OUT, CORNER_SPACING)
    frames = _solve_corner_heights(pts, y_start, y_end)
    CORNER_LEN = pts[0][3]
    CORNER_PITCH = math.atan(abs(y_end - y_start) / CORNER_LEN)
    origins = [frame[0] for frame in frames]
    path_name = prefix + "Path"
    curves.append(("Curve_%s" % prefix, origins))
    paths.append((path_name, "Curve_%s" % prefix))
    _add_path_poly(prefix + "Surf", path_name, CORNER_POLY, "surf")
    # The fill is the solid under the face, down through the floor. A second wall
    # behind the ridge sat above the ground and showed up as a floating ribbon.
    _add_path_poly(prefix + "Fill", path_name, CORNER_FILL, "concrete")
    # Start cap only. An end kicker this size tilts the last metres under 45° and the surf stops.
    _add_path_kick(prefix + "Surf", prefix + "KickA", frames[0][1], frames[0][0], 48.0, False)
    _add_path_kick(prefix + "Fill", prefix + "FillKickA", frames[0][1], frames[0][0], 48.0, False)

    nys = []
    toes = []
    next_probe = 1.2
    count = len(frames)
    for i, (origin, basis, tangent) in enumerate(frames):
        dist, total = pts[i][2], pts[i][3]
        want = y_start + (y_end - y_start) * (dist / total)
        if basis is None:
            corner_problems.append("%s sample %d has no frame" % (prefix, i))
            continue
        toe = _toe_point(basis, origin, CORNER_TOE)
        normal = apply_basis(basis, (0.0, 0.0, 0.0), CORNER_FACE)
        ny = normal[1]
        nys.append(ny)
        toes.append(toe)
        to_centre = _vunit((cx - toe[0], 0.0, cz - toe[2]))
        flat = _vunit((normal[0], 0.0, normal[2]))
        inward = flat is not None and to_centre is not None and _vdot(flat, to_centre) > 0.45
        ok = basis_det(basis) > 0.5 and 0.15 <= ny <= 0.62 and abs(toe[1] - want) < 0.08 and inward
        # The roof starts at z=28. The run-in has to stay north of it.
        on_roof = 14.0 < toe[0] < 34.0 and toe[2] > 27.85 and toe[1] < ROOF_Y + 0.4
        if on_roof:
            ok = False
        if not ok:
            corner_problems.append(
                "%s s=%.1f ny=%.3f toe=(%.1f, %.2f, %.1f) want y=%.2f inward=%s roof=%s" % (
                    prefix, dist, ny, toe[0], toe[1], toe[2], want, inward, on_roof))
        label = None
        if i == 0:
            label = prefix + " high"
        elif i == count // 2:
            label = prefix + " mid"
        elif i == count - 1:
            label = prefix + " low"
        elif not ok:
            label = "%s FAIL %d" % (prefix, i)
        if label is not None:
            corner_log.append((label, basis_det(basis), ny, toe, want, ok))
        if dist + 1e-6 >= next_probe and dist < total - 1.0:
            next_probe = dist + 2.0
            face_pt = apply_basis(basis, origin, (_FACE_LOCAL[0], _FACE_LOCAL[1], 0.0))
            unit_n = _vunit(normal)
            unit_t = _vunit(tangent)
            if unit_n is not None and unit_t is not None:
                above = _vadd(face_pt, unit_n, 0.55)
                probe.append({
                    "name": "%s_surf_%d" % (prefix, int(dist)),
                    "from": above,
                    "to": _vadd(above, unit_n, -1.3),
                    "want": "surf",
                })
                glide = _vadd(face_pt, unit_n, 0.22)
                probe.append({
                    "name": "%s_glide_%d" % (prefix, int(dist)),
                    "from": glide,
                    "to": _vadd(glide, unit_t, 2.2),
                    "want": "clear",
                })
    end_travel = _vunit(frames[-1][2])
    end = toes[-1] if toes else None
    if end_travel is None or end is None:
        corner_problems.append("%s has no exit" % prefix)
    else:
        # Horizontal exit must point at the map centre, not the outer wall.
        aim = _vunit((-end[0], 0.0, -end[2]))
        if aim is None or _vdot((end_travel[0], 0.0, end_travel[2]), aim) < 0.35:
            corner_problems.append(
                "%s exit travel (%.2f, %.2f) from (%.1f, %.1f) does not face the centre" % (
                    prefix, end_travel[0], end_travel[2], end[0], end[2]))
        # Mirrored profile: the flat side of the toe is local -X.
        _exit_basis = frames[-1][1]
        _open = (-_exit_basis[0][0], -_exit_basis[0][2])
        corner_exits.append((prefix, end, (end_travel[0], end_travel[2]), _open))
    return nys, toes


def _ray(name, start, end, want):
    probe.append({"name": name, "from": start, "to": end, "want": want})


def add_ramp_probes():
    """Feet must be open floor. A metre in front of the tread, nothing may block a capsule."""
    _ray("stairA_floor", (-29.4, 1.6, 31.2), (-29.4, -0.5, 31.2), "floor")
    _ray("stairA_open", (-29.4, 0.5, 30.6), (-29.4, 0.5, 32.7), "clear")
    _ray("stairA_tread", (-29.4, 3.5, 36.5), (-29.4, 0.5, 36.5), "slope")
    _ray("stairB_floor", (-18.5, 1.6, 46.8), (-18.5, -0.5, 46.8), "floor")
    _ray("stairB_open", (-18.5, 0.5, 47.4), (-18.5, 0.5, 45.3), "clear")
    _ray("stairB_tread", (-18.5, 3.5, 41.0), (-18.5, 0.5, 41.0), "slope")
    _ray("eastA_floor", (18.5, 1.6, 31.2), (18.5, -0.5, 31.2), "floor")
    _ray("eastA_open", (18.5, 0.5, 30.6), (18.5, 0.5, 32.7), "clear")
    _ray("eastB_floor", (29.4, 1.6, 46.8), (29.4, -0.5, 46.8), "floor")
    _ray("eastB_open", (29.4, 0.5, 47.4), (29.4, 0.5, 45.3), "clear")
    _wz = (EXT_W_Z0 + EXT_W_Z1) * 0.5
    _ez = (EXT_E_Z0 + EXT_E_Z1) * 0.5
    _ray("ext_floor", (-2.4, 1.6, _wz), (-2.4, -0.5, _wz), "floor")
    _ray("ext_open", (-2.0, 0.5, _wz), (-4.2, 0.5, _wz), "clear")
    _ray("ext_tread", (-11.0, 6.8, _wz), (-11.0, 2.2, _wz), "slope")
    # The slot is open above the tread, and the roof past the high end is flat.
    _ray("ext_slot", (-12.6, 8.4, _wz), (-15.4, 8.4, _wz), "clear")
    _ray("ext_join", (-17.2, 10.2, _wz), (-20.4, 10.2, _wz), "clear")
    _ray("ext_roof", (-24.0, 12.0, _wz), (-24.0, 8.0, _wz), "roof")
    # Both edges of the tread are the ramp, not the brick roof beside it.
    _ray("ext_side0", (-16.5, 11.5, 45.2), (-16.5, 7.2, 45.2), "slope")
    _ray("ext_side1", (-16.5, 11.5, 48.2), (-16.5, 7.2, 48.2), "slope")
    _ray("ext_east_side0", (16.5, 11.5, 29.9), (16.5, 7.2, 29.9), "slope")
    _ray("ext_east_side1", (16.5, 11.5, 33.0), (16.5, 7.2, 33.0), "slope")
    _ray("ext_east_roof", (24.0, 12.0, _ez), (24.0, 8.0, _ez), "roof")
    _ray("ext_east_open", (2.0, 0.5, _ez), (4.2, 0.5, _ez), "clear")
    _ray("quay_floor", (-8.6, 1.4, 18.1), (-8.6, -0.5, 18.1), "floor")
    _ray("quay_open", (-8.8, 0.5, 18.1), (-9.9, 0.5, 18.1), "clear")
    _ray("quay_tread", (-15.5, 3.2, 18.1), (-15.5, 0.2, 18.1), "slope")
    _ray("quay_top", (-20.2, 5.2, 18.1), (-20.2, 2.4, 18.1), "slope")
    _ray("quay_deck", (-23.0, 6.0, 18.1), (-23.0, 2.5, 18.1), "deck")
    # Side link. Foot flush with the quay, top flush with the roof, no curb either end.
    _ray("link_foot", (32.4, 5.4, 14.4), (32.4, 2.6, 14.4), "deck")
    _ray("link_open", (32.4, 4.4, 13.8), (32.4, 4.4, 15.3), "clear")
    _ray("link_tread", (32.4, 8.4, 22.4), (32.4, 5.2, 22.4), "slope")
    _ray("link_near", (32.4, 10.5, 28.2), (32.4, 8.2, 28.2), "slope")
    _ray("link_lip", (32.4, 9.9, 27.2), (32.4, 9.9, 28.5), "clear")
    _ray("link_join", (32.4, 10.2, 28.4), (32.4, 10.2, 30.4), "clear")
    _ray("link_roof", (32.4, 12.0, 29.6), (32.4, 8.4, 29.6), "roof")
    _ray("link_orange_roof", (-32.4, 12.0, -29.6), (-32.4, 8.4, -29.6), "roof")
    # Orange end is the half-turn of the west pieces.
    _ray("orangeA_floor", (29.4, 1.6, -31.2), (29.4, -0.5, -31.2), "floor")
    _ray("orangeA_open", (29.4, 0.5, -30.6), (29.4, 0.5, -32.7), "clear")
    _ray("orange_ext_open", (2.0, 0.5, -_wz), (4.2, 0.5, -_wz), "clear")
    _ray("orange_ext_roof", (24.0, 12.0, -_wz), (24.0, 8.0, -_wz), "roof")
    _ray("orange_ext_slot", (12.6, 8.4, -_wz), (15.4, 8.4, -_wz), "clear")
    _ray("orange_quay_tread", (15.5, 3.2, -18.1), (15.5, 0.2, -18.1), "slope")


# Clockwise quarter off the east roof. Orange is the half-turn: centre and angles +180°.
c_ny, c_toes = add_corner("CornerB", CORNER_C[0], CORNER_C[1], CORNER_A0, CORNER_A1, ROOF_Y, QUAY_Y)
add_corner("CornerO", -CORNER_C[0], -CORNER_C[1], CORNER_A0 + math.pi, CORNER_A1 + math.pi, ROOF_Y, QUAY_Y)

# Balcony on the open side of the entry toe (west, toward the dock) and back into
# the north wall. The face itself is east of the toe, so the floor stops short of it.
# The pier holds the floor up. A 0.3 m plate here stuck out of the roof with nothing under it.
_pad_x1 = c_toes[0][0] - 0.08
_pad_z0 = min(c_toes[0][2], 24.0) - 0.8
pair_box("CornerPad", 18.2, _pad_x1, ROOF_Y - 0.8, ROOF_Y, _pad_z0, 28.45, "roof")
# Holds the balcony. Stops short of the toe, so the solid is not a wall on the face.
# The north door is x 23.0–25.6 and the window beside it is x 18.2–20.4. A pier
# across both, from the ground, filled the holes: the cut still looked open and
# the capsule stopped on the concrete. The column stands in the solid bay between
# them. The breast stays above the 2.6 m door, so the walk under it is clear.
_pier_z0 = _pad_z0 + 0.45
_pier_x1 = _pad_x1 - 0.55
pair_box("CornerPierCol", 20.60, 22.50, 0.0, ROOF_Y - 0.8, _pier_z0, 28.45, "concrete")
pair_box("CornerPierTop", 18.2, _pier_x1, 2.70, ROOF_Y - 0.8, _pier_z0, 28.45, "concrete")
pair_box("CornerPadEdge", c_toes[0][0] - 0.32, c_toes[0][0] - 0.15, ROOF_Y - 0.06, ROOF_Y,
         c_toes[0][2] - 0.28, c_toes[0][2] + 0.28, "hazard")
# High end of the corner sits just off the roof, so the cap read as a block in the air.
# Brick laps the balcony and the back of the cap, only at the roof. From the ground
# the same boxes stood in the north windows and beside the door.
# Along the toe it only just passes the crest: further north the toe has already dropped.
pair_box("CornerSeal", 25.80, 27.15, ROOF_Y - 0.85, ROOF_Y, 27.12, 28.80, "brick")
pair_box("CornerSealBack", 27.15, 31.0, ROOF_Y - 0.85, ROOF_Y, 26.40, 28.80, "brick")
# These unions are after the door cuts, so a box in an opening puts the wall back.
_door_clear = (
    ("EastDoorN", (23.05, 25.55, 0.0, 2.55, 22.5, 29.6)),
    ("EastWinN1", (18.25, 20.35, 1.05, 2.45, 27.55, 29.6)),
    ("EastWinN2", (30.05, 32.15, 1.05, 2.45, 27.55, 29.6)),
)
_door_fills = (
    ("CornerPierCol", (20.60, 22.50, 0.0, ROOF_Y - 0.8, _pier_z0, 28.45)),
    ("CornerPierTop", (18.2, _pier_x1, 2.70, ROOF_Y - 0.8, _pier_z0, 28.45)),
    ("CornerSeal", (25.80, 27.15, ROOF_Y - 0.85, ROOF_Y, 27.12, 28.80)),
    ("CornerSealBack", (27.15, 31.0, ROOF_Y - 0.85, ROOF_Y, 26.40, 28.80)),
)
for _fill_name, _fill in _door_fills:
    for _hole_name, _hole in _door_clear:
        if (_fill[0] < _hole[1] and _hole[0] < _fill[1] and _fill[2] < _hole[3]
                and _hole[2] < _fill[3] and _fill[4] < _hole[5] and _hole[4] < _fill[5]):
            corner_problems.append("%s overlaps %s" % (_fill_name, _hole_name))
# No deck on the exit. The run leaves going west, into the dock, and a floor there would stop it.

# Side link. From the east quay up the north-east corner of the loods, ~24°.
# Stays east of the corner wall (its outer face is x≤30.85) so it does not cover the surf.
# Top is exactly roof height; the foot is exactly quay height. About 2.4 m wide.
# The foot is solid with the quay, so the east edge is not a floating shelf.
pair_box("SideLinkPad", 31.2, 33.95, 0.0, QUAY_Y, 13.6, 17.6, "concrete")
pair_ramp_z("SideLink", 31.4, 33.8, 15.6, 29.0, ROOF_Y - QUAY_Y, "steel", y0=QUAY_Y)
# Solid under the low end (down to the lane), like the street ramps: under the bare slab
# the deck edge was a head-height trap. Open again from 2.6 m clearance.
_sl_h = 2.6
wedge_z("SideLinkFootB", 31.43, 33.77, 15.6, 15.6 + (29.0 - 15.6) * _sl_h / (ROOF_Y - QUAY_Y), _sl_h,
        "steel", y0=QUAY_Y, top_drop=0.03, base_y=-0.1)
wedge_z("SideLinkFootO", -33.77, -31.43, -15.6, -(15.6 + (29.0 - 15.6) * _sl_h / (ROOF_Y - QUAY_Y)), _sl_h,
        "steel", y0=QUAY_Y, top_drop=0.03, base_y=-0.1)
# Fills the whole slot behind the ramp, so the roof corner is closed.
pair_box("SideLinkLand", 31.25, 33.95, 9.15, ROOF_Y, 29.0, 30.7, "steel")
add_ramp_probes()


def add_rework_probes():
    """New pieces of the rework. Half-turn copies are the same rays negated in x and z."""
    rays = [
        # Arch: open at chest height, 3 m clear above the floor.
        ("arch_open", (-38.0, 1.0, 43.5), (-38.0, 1.0, 38.6), "clear"),
        ("arch_head", (-38.0, 0.3, 41.2), (-38.0, 3.2, 41.2), "clear"),
        # Side ramps: floor at the foot, a tread, no lip where they meet the deck.
        ("pocket_foot", (-38.0, 1.6, 40.6), (-38.0, -0.5, 40.6), "floor"),
        ("pocket_tread", (-38.0, 4.0, 31.0), (-38.0, -0.5, 31.0), "slope"),
        ("pocket_join", (-38.0, QUAY_Y + 0.12, 23.6), (-38.0, QUAY_Y + 0.12, 20.4), "clear"),
        ("pocket_deck", (-38.0, 6.0, 20.0), (-38.0, 2.0, 20.0), "deck"),
        ("lane_foot", (-40.0, 1.6, -40.6), (-40.0, -0.5, -40.6), "floor"),
        ("lane_tread", (-40.0, 4.0, -31.0), (-40.0, -0.5, -31.0), "slope"),
        ("lane_join", (-40.0, QUAY_Y + 0.12, -23.6), (-40.0, QUAY_Y + 0.12, -20.4), "clear"),
        # Deck beside the surf foot: flat deck, nothing at shin height.
        ("surf_foot_deck", (-41.4, 6.0, 8.0), (-41.4, 2.0, 8.0), "deck"),
        ("surf_foot_shin", (-41.3, QUAY_Y + 0.3, 20.0), (-41.3, QUAY_Y + 0.3, -1.0), "clear"),
        # Deck stack stays out of the flank surf's riding space.
        ("stack_vs_surf", (-41.5, 6.5, 13.2), (-39.7, 6.5, 13.2), "clear"),
        # Office: doors open, stair is a tread, crest flush with the top floor, drop opening open.
        ("office_door_w", (-33.0, 5.0, 0.0), (-26.0, 5.0, 0.0), "clear"),
        ("office_door_n", (-26.0, 5.0, -7.0), (-26.0, 5.0, -1.0), "clear"),
        ("office_door_s", (-26.0, 5.0, 7.0), (-26.0, 5.0, 1.0), "clear"),
        ("office_foot", (-21.5, 5.0, 3.6), (-21.5, 3.0, 3.6), "deck"),
        ("office_tread", (-21.5, 9.5, -1.0), (-21.5, 3.0, -1.0), "slope"),
        ("office_crest", (-21.5, OFF_F2 + 0.12, -2.8), (-21.5, OFF_F2 + 0.12, -4.4), "clear"),
        ("office_top", (-21.5, 9.5, -4.1), (-21.5, 6.0, -4.1), "flat@%.2f" % OFF_F2),
        ("office_floor2", (-26.0, 9.5, 0.0), (-26.0, 6.0, 0.0), "flat@%.2f" % OFF_F2),
        ("office_drop", (-23.0, 8.8, 2.2), (-18.6, 8.8, 2.2), "clear"),
        ("office_stair_head", (-21.5, 5.3, 0.6), (-21.5, 7.2, 0.6), "clear"),
        # Gantry and hanging box: clear over everything you ride.
        ("cross_over", (0.0, 5.7, 1.6), (0.0, 8.5, 1.6), "clear"),
        ("cross_glide", (-9.5, 6.6, 0.4), (9.5, 6.6, 0.4), "clear"),
        ("dock_surf_over", (-16.5, 6.2, 0.0), (-16.5, 11.0, 0.0), "clear"),
        ("gantry_hit", (0.0, 15.0, 0.0), (0.0, 12.0, 0.0), "flat@%.2f" % GANTRY_Y1),
        # Screen slit: open at eye height, closed under and over it.
        ("slit_open", (-32.0, ROOF_Y + 1.6, 30.0), (-32.0, ROOF_Y + 1.6, 26.0), "clear"),
        ("slit_low", (-32.0, ROOF_Y + 0.8, 30.0), (-32.0, ROOF_Y + 0.8, 26.0), "wall"),
        ("screen_shut", (-28.6 + 6.0, ROOF_Y + 1.6, 30.0), (-28.6 + 6.0, ROOF_Y + 1.6, 26.0), "wall"),
    ]
    for name, a, b, want in rays:
        _ray("%s_b" % name, a, b, want)
        _ray("%s_o" % name, (-a[0], a[1], -a[2]), (-b[0], b[1], -b[2]), want)


add_rework_probes()

# ---------------------------------------------------------------- parapets (gaps are the surf lip, the ramp bridge, the balcony, one drop)
def para(name, x0, x1, z0, z1):
    pair_box(name, x0, x1, ROOF_Y, ROOF_Y + PARAPET, z0, z1, "concrete")


# West roof.
# Roof screens, 2.4 m, on the edge of each west-type roof that faces the far team. The far
# roof (the east type) keeps its open north edge for the balcony and the corner surf, so every
# roof-to-roof line along a side passes one screen. Two slits per roof, 1.2 m wide at standing
# eye height (11.6 m): the sniper keeps two fixed lanes instead of the whole map.
SCREEN_H = 2.4
SLIT_Y0, SLIT_Y1 = ROOF_Y + 1.15, ROOF_Y + 1.95


def screen(name, x0, x1, z0, z1, slits=()):
    pair_box(name + "Lo", x0, x1, ROOF_Y, ROOF_Y + SLIT_Y0 - ROOF_Y, z0, z1, "concrete")
    pair_box(name + "Hi", x0, x1, SLIT_Y1, ROOF_Y + SCREEN_H, z0, z1, "concrete")
    edges = [x0] + [v for sl in slits for v in sl] + [x1]
    for i in range(0, len(edges), 2):
        pair_box(name + "Mid%d" % (i // 2), edges[i], edges[i + 1], SLIT_Y0, SLIT_Y1, z0, z1, "concrete")


SLITS_W = ((-32.6, -31.4), (-19.4, -18.2))
screen("WScrN1", -34.0, -30.0, 28.0, 28.45, (SLITS_W[0],))
screen("WScrN2", -26.0, -14.0, 28.0, 28.45, (SLITS_W[1],))  # gap -30..-26 is still the drop
para("WParS", -34.0, -14.0, 49.55, 50.0)
para("WParW1", -34.0, -33.55, 28.0, _LIP_Z0)
para("WParW2", -34.0, -33.55, _LIP_Z1, 50.0)  # gap is the solid walk to the flank toe
para("WParE1", -14.45, -14.0, 28.0, 44.55)
# No stub past the exterior ramp. The south parapet closes that corner.
# East roof. The north edge stays open from the balcony across to the side link.
# A 0.7 m tooth between those two gaps was a block on the corner.
screen("EScrN1", 14.0, 18.0, 28.0, 28.45)
para("EParS", 14.0, 34.0, 49.55, 50.0)
para("EParE", 33.55, 34.0, 30.7, 50.0)  # north end is the side-link landing
para("EParW2", 14.0, 14.45, 33.50, 50.0)

# ---------------------------------------------------------------- cover
# Containers are the only loose cover (2.44 m deep, 2.6 m per box). The old crates, van, AC
# units and dock box were scattered singles that made the lanes read as clutter.
# One container across each street, so the spawn strip does not see the dock (was the bus).
pair_box("StreetBox", -4.5, 4.5, 0.0, 2.6, 37.6, 40.04, "container")
# Dock: offset boxes so the dock is two routes around cover, not one open floor. They stay out
# of the surf flight lines: the corner exits fly west/east at z≈±(5..13), the cross surf
# launches along x at |z|<2, the dock surfs land on the quay ramps.
pair_box("DockBoxA", -6.5, -0.5, 0.0, 2.6, 15.6, 18.04, "container")  # 3.9 m off the quay-ramp foot
pair_box("DockStack", 3.0, 5.44, 0.0, 5.2, 14.5, 20.6, "container")   # two high
pair_box("MouthBox", -6.0, 0.0, 0.0, 2.6, 23.0, 25.44, "container")
# Quay deck: two high, so the wall lane has to step around it. 1.65 m clear of the flank toe,
# outside the riding envelope of the surf (capsule on the face reaches x≈-41.2).
pair_box("DeckStack", -39.5, -31.0, QUAY_Y, QUAY_Y + 5.2, 12.0, 14.44, "container")

# ---------------------------------------------------------------- crane gantry
# One beam across the dock at z=0, resting on the two office walls (it is its own half-turn).
# 11.2 m underside: the cross surf ridge is 5.25 m and the dock surf ridges about 5.5 m here,
# so nothing you ride comes near it. The container hangs right under the beam, 8.6 m up:
# 3.35 m over the cross surf ridge. It cuts the roof-to-roof diagonals through the middle.
box("Gantry", OFF_X1 + OFF_WT, -(OFF_X1 + OFF_WT), GANTRY_Y0, GANTRY_Y1, -1.0, 1.0, "steel")
box("GantryBox", -3.05, 3.05, 8.6, GANTRY_Y0, -1.22, 1.22, "container")

# ---------------------------------------------------------------- spawns
# Yards behind a 3.2 m wall. Team colour only on that wall. Baffles close the flanks.
# The wall covers the street mouth. The baffles meet the loods, so a spawn does not
# look down the flank. The way out is the strip between this wall and the south doors.
pair_box("SpawnWall", -16.0, 16.0, 0.0, 3.2, 54.6, 55.3, "team_blue", "team_orange")
# The corners behind the baffles were dead space (and spawns). They are solid now: the
# baffle grew into a 3.2 m block, and the yard is the part between them.
pair_box("YardFillW", -INNER_X, -33.8, 0.0, 3.2, 53.8, INNER_Z, "concrete")
pair_box("YardFillE", 33.8, INNER_X, 0.0, 3.2, 53.8, INNER_Z, "concrete")

# ---------------------------------------------------------------- lights (omni, no shadows)
WARM = (1.0, 0.86, 0.70)
COOL = (0.78, 0.86, 1.0)
pair_light("InsideA", (-24.0, 2.4, 39.0), WARM, 0.7, 12.0)
pair_light("InsideB", (24.0, 2.4, 39.0), WARM, 0.7, 12.0)
pair_light("RoofLight", (-24.0, 12.4, 40.0), WARM, 0.35, 10.0)
pair_light("QuayLight", (-37.0, 7.5, 0.0), COOL, 0.4, 14.0)
pair_light("OfficeLow", (-25.5, 6.6, 0.0), WARM, 0.55, 8.0)
pair_light("OfficeHigh", (-25.5, 10.6, 0.0), WARM, 0.45, 8.0)
pair_light("CornerLight", (24.0, 12.2, 26.0), WARM, 0.4, 11.0)
light("DockA", (-6.0, 5.5, 8.0), COOL, 0.45, 16.0)
light("DockB", (6.0, 5.5, -8.0), COOL, 0.45, 16.0)
pair_light("Yard", (0.0, 3.4, 57.0), WARM, 0.35, 10.0)


def _end_strip(name, basis, origin, along, floor_y, sign=1.0, drop=0.0):
    """Catch volume at the toe, as tall as this surf. sign -1 leaves through the origin end.

    The yellow mark stays on the flat side of the toe (local +X). Across the toe it
    would sit in the face.
    """
    toe_pos = toe_world(basis, origin, along)
    strips.append(speed_strip.make(
        name, toe_pos, speed_strip.forward_xz(basis, sign), floor_y, height=drop,
        open_xz=(basis[0][0], basis[0][2])))


_end_strip("StripFlankW", FLANK_BASIS, flank_o, FLANK_DEPTH, QUAY_Y, drop=FLANK_DROP)
_end_strip("StripFlankE", FLANK_E_BASIS, flank_e, FLANK_DEPTH, QUAY_Y, drop=FLANK_DROP)
_end_strip("StripDockW", DOCK_BASIS, dock_o, DOCK_DEPTH, 0.0, drop=DOCK_DROP)
_end_strip("StripDockE", DOCK_E_BASIS, dock_e, DOCK_DEPTH, 0.0, drop=DOCK_DROP)
_end_strip("StripCross", CROSS_BASIS, (CROSS_DEPTH / 2.0, 0.1, 1.8), CROSS_DEPTH, 0.0)
for _prefix, _end, _fwd, _open in corner_exits:
    strips.append(speed_strip.make(
        "Strip" + _prefix, _end, _fwd, QUAY_Y, height=ROOF_Y - QUAY_Y, open_xz=_open))


def main():
    failed = False
    print("flank pitch %.2f deg, corner pitch %.2f deg, corner path %.1f m" % (
        math.degrees(FLANK_PITCH), math.degrees(CORNER_PITCH), CORNER_LEN))
    nys = []
    for label, basis, origin, along, y_expect in checks:
        det = basis_det(basis)
        ny = face_ny(basis)
        toe = toe_world(basis, origin, along)
        nys.append(ny)
        ok = det > 0.5 and 0.15 <= ny <= 0.62 and abs(toe[1] - y_expect) < 0.2
        if not ok or any(label.endswith(suffix) for suffix in ("high", "low", "end", "00", "mid")) or "FAIL" in label:
            print("  %-14s det=%+.3f ny=%.3f toe=(%.1f, %.2f, %.1f) expect y=%.1f%s" % (
                label, det, ny, toe[0], toe[1], toe[2], y_expect, "" if ok else "  FAIL"))
        if not ok:
            failed = True
    for label, det, ny, toe, y_expect, ok in corner_log:
        print("  %-14s det=%+.3f ny=%.3f toe=(%.1f, %.2f, %.1f) expect y=%.1f%s" % (
            label, det, ny, toe[0], toe[1], toe[2], y_expect, "" if ok else "  FAIL"))
        if not ok:
            failed = True
    for problem in corner_problems:
        print("  CORNER", problem)
        failed = True
    print("  corner toes %d, first (%.1f, %.1f, %.1f) last (%.1f, %.1f, %.1f), ny %.3f..%.3f" % (
        len(c_toes), c_toes[0][0], c_toes[0][1], c_toes[0][2],
        c_toes[-1][0], c_toes[-1][1], c_toes[-1][2], min(c_ny), max(c_ny)))
    if failed:
        print("surf check failed", file=sys.stderr)
        sys.exit(1)
    mats = []
    for n in nodes:
        if n[4] not in mats:
            mats.append(n[4])
    # FFA spawn on the east roof must stay on the balcony, off the surf face.
    # FFA spawn stays on the balcony, west of the toe, off the surf face.
    if not (18.4 < 24.0 < _pad_x1 - 0.6 and _pad_z0 + 0.3 < 26.0 < 28.2):
        print("corner balcony missed the FFA spawn", file=sys.stderr)
        sys.exit(1)
    out = ["[gd_scene load_steps=%d format=3]" % (len(mats) + 1 + len(curves) + speed_strip.LOAD_STEPS), ""]
    out += [
        '[sub_resource type="Environment" id="Env_quay"]',
        "background_mode = 1",
        "background_color = Color(0.16, 0.18, 0.2, 1)",
        "ambient_light_source = 2",
        "ambient_light_color = Color(0.55, 0.58, 0.62, 1)",
        "ambient_light_energy = 0.62",
        "tonemap_mode = 2",
        "ssao_enabled = false",
        "glow_enabled = false",
        "",
    ]
    for m in mats:
        (r, g, b), rough = MATS[m]
        out += ['[sub_resource type="StandardMaterial3D" id="Mat_%s"]' % m,
                "albedo_color = Color(%s, %s, %s, 1)" % (fmt(r), fmt(g), fmt(b)),
                "roughness = %s" % fmt(rough), ""]
    for cid, pts in curves:
        floats = []
        for p in pts:
            floats.extend((0.0, 0.0, 0.0, 0.0, 0.0, 0.0, p[0], p[1], p[2]))
        out += [
            '[sub_resource type="Curve3D" id="%s"]' % cid,
            "_data = {",
            '"points": PackedVector3Array(%s),' % ", ".join(fmt(v) for v in floats),
            '"tilts": PackedFloat32Array(%s)' % ", ".join(["0"] * len(pts)),
            "}",
            "point_count = %d" % len(pts),
            "",
        ]
    out += speed_strip.resources()
    out += ['[node name="Quay" type="Node3D"]', ""]
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env_quay")', ""]
    out += ['[node name="Sun" type="DirectionalLight3D" parent="."]',
            "transform = Transform3D(0.766, -0.4545, 0.4545, 0, 0.7071, 0.7071, -0.6428, -0.5417, 0.5417, 8, 22, 10)",
            "light_energy = 1.12",
            "light_color = Color(1, 0.95, 0.88, 1)",
            "shadow_enabled = true", ""]
    out += ['[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]', ""]
    out += ['[node name="Arena" type="CSGCombiner3D" parent="."]',
            "use_collision = true", "collision_layer = 1", "collision_mask = 0", ""]
    for name, cid in paths:
        out += ['[node name="%s" type="Path3D" parent="Arena"]' % name,
                'curve = SubResource("%s")' % cid, ""]
    for name, typ, xf, extras, mat, parent in nodes:
        out += ['[node name="%s" type="%s" parent="%s"]' % (name, typ, parent),
                "transform = %s" % xf]
        out += extras
        out += ['material = SubResource("Mat_%s")' % mat, ""]
    out += speed_strip.nodes(strips)
    for name, pos, col, energy, rng in lights:
        out += ['[node name="%s" type="OmniLight3D" parent="."]' % name,
                "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % tuple(fmt(v) for v in pos),
                "light_color = Color(%s, %s, %s, 1)" % tuple(fmt(v) for v in col),
                "light_energy = %s" % fmt(energy),
                "omni_range = %s" % fmt(rng),
                "shadow_enabled = false", ""]
    text = "\n".join(out).rstrip("\n") + "\n"
    with open(OUT, "w") as f:
        f.write(text)
    probe_path = "/tmp/quay_probe.json"
    with open(probe_path, "w") as f:
        json.dump(probe, f)
    print("wrote %s (%d csg nodes, %d probe rays, %d strips)" % (
        os.path.normpath(OUT), len(nodes), len(probe), len(strips)))
    for s in strips:
        c = s["center"]
        print("  strip %-16s center=(%.1f, %.1f, %.1f) floor=%.1f ramp=%.2f" % (
            s["name"], c[0], c[1], c[2], s["floor"], s["ramp_h"]))


if __name__ == "__main__":
    main()
