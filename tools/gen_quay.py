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

MATS = {
    "floor": ((0.24, 0.25, 0.26), 0.92),
    "concrete": ((0.40, 0.40, 0.38), 0.88),
    "outer": ((0.32, 0.34, 0.36), 0.86),
    "roof": ((0.30, 0.34, 0.31), 0.90),
    "brick": ((0.52, 0.36, 0.24), 0.85),
    "cover": ((0.48, 0.40, 0.32), 0.82),
    "steel": ((0.32, 0.34, 0.37), 0.62),
    "hazard": ((0.78, 0.62, 0.14), 0.75),
    "surf": ((0.36, 0.42, 0.48), 0.62),
    "team_blue": ((0.27, 0.46, 0.62), 0.82),
    "team_orange": ((0.70, 0.44, 0.18), 0.82),
    "van": ((0.25, 0.32, 0.36), 0.70),
    "trim": ((0.20, 0.21, 0.23), 0.88),
    "bus": ((0.28, 0.38, 0.30), 0.78),
    "c_red": ((0.56, 0.20, 0.15), 0.78),
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
CORNER_WALL = (0.15, -1.0, 1.55, -1.0, 1.55, 6.4, 0.15, 6.4)
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
corner_exits = []  # (prefix, toe, forward xz) for the speed strip at the launch
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
box("WallWest", -HALF_X, -INNER_X, 0, WALL_H, -HALF_Z, HALF_Z, "outer")
box("WallEast", INNER_X, HALF_X, 0, WALL_H, -HALF_Z, HALF_Z, "outer")
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
pair_sub("WestWinW", -34.4, -32.4, 1.0, 2.5, 30.2, 32.4)
pair_sub("WestWinE", -15.6, -13.6, 1.0, 2.5, 35.6, 37.8)
pair_sub("EastWinN1", 18.2, 20.4, 1.0, 2.5, 27.6, 29.6)
pair_sub("EastWinN2", 30.0, 32.2, 1.0, 2.5, 27.6, 29.6)
pair_sub("EastWinE", 32.4, 34.4, 1.0, 2.5, 30.2, 32.4)
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
pair_sub("QuayNotchS", -20.85, -17.5, 0.02, QUAY_Y + 0.35, 15.9, 20.3)
pair_sub("QuayNotchN", -20.85, -17.5, 0.02, QUAY_Y + 0.35, -20.3, -15.9)
# Street-ramp slot through the roof edge. Wider than the tread and open to the
# sky, so the roof does not sit as a ledge on either side of the ramp. The west
# stair shaft ends at z=44.5 and the east one starts at z=33.5, so the slot
# stops short of both. Cut before the ramp unions.
pair_sub("ExtNotchW", -19.3, -13.55, 6.3, ROOF_Y + 0.4, 44.70, 48.55)
pair_sub("ExtNotchE", 13.55, 19.3, 6.3, ROOF_Y + 0.4, 29.50, 33.35)
# Slot for the side link. Wider than the tread, through the north face, so the
# brick does not stand up as a lip where the walk meets the roof.
pair_sub("SideLinkNotch", 30.85, 34.05, 8.5, ROOF_Y + 0.45, 27.5, 30.7)

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
# Rails stop at the ceiling and stay off the landing, so the foot is open.
pair_box("WestRailAO", -32.15, -31.9, 0.0, CEIL_Y, 33.9, 45.3, "trim")
pair_box("WestRailAI", -26.9, -26.65, 0.0, CEIL_Y, 33.9, 45.3, "trim")
pair_box("WestRailBO", -16.1, -15.85, 0.0, CEIL_Y, 32.7, 44.1, "trim")
pair_box("WestRailBI", -20.9, -20.65, 0.0, CEIL_Y, 32.7, 44.1, "trim")
pair_box("EastRailAO", 15.85, 16.1, 0.0, CEIL_Y, 33.9, 45.3, "trim")
pair_box("EastRailAI", 20.9, 21.15, 0.0, CEIL_Y, 33.9, 45.3, "trim")
pair_box("EastRailBO", 31.9, 32.15, 0.0, CEIL_Y, 32.7, 44.1, "trim")
pair_box("EastRailBI", 26.65, 26.9, 0.0, CEIL_Y, 32.7, 44.1, "trim")

# Exterior ramp, the second way up. Climbs in toward the roof, not along it.
# 3.4 m wide. The notch takes the brick out past both edges of the tread.
# The landing is the same height as the roof, and the ramp arrives on its edge.
pair_ramp_x("WestRamp", EXT_W_Z0, EXT_W_Z1, EXT_X_FOOT, EXT_X_TOP, ROOF_Y, "concrete")
pair_ramp_x("EastRamp", EXT_E_Z0, EXT_E_Z1, -EXT_X_FOOT, -EXT_X_TOP, ROOF_Y, "concrete")
pair_box("WestRampLand", EXT_X_TOP - 1.35, EXT_X_TOP, ROOF_Y - 0.45, ROOF_Y, 44.70, 48.55, "concrete")
pair_box("EastRampLand", 18.4, 19.75, ROOF_Y - 0.45, ROOF_Y, 29.50, 33.35, "concrete")
pair_box("WestRampEdge", EXT_X_FOOT - 0.2, EXT_X_FOOT + 0.2, -0.06, 0.0, EXT_W_Z0, EXT_W_Z1, "hazard")
pair_box("EastRampEdge", -EXT_X_FOOT - 0.2, -EXT_X_FOOT + 0.2, -0.06, 0.0, EXT_E_Z0, EXT_E_Z1, "hazard")

# Quay ↔ dock. Foot on the dock floor, top buried in the deck past the notch.
# ~21°, wide enough for two capsules. Kept off the dock surf (high end is z≈14).
pair_ramp_x("QuayRampS", 15.5, 20.7, -10.4, -21.0, QUAY_Y, "concrete")
pair_ramp_x("QuayRampN", -20.7, -15.5, -10.4, -21.0, QUAY_Y, "concrete")
pair_box("QuayRampSEdge", -10.6, -10.25, -0.06, 0.0, 15.5, 20.7, "hazard")
pair_box("QuayRampNEdge", -10.6, -10.25, -0.06, 0.0, -20.7, -15.5, "hazard")

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

# Roof lip out to the west toe, so the 10 m roof meets the high end. Stays on the open
# side of the toe (x greater than the toe) so it does not bury the face.
_toe_hi = toe_world(FLANK_BASIS, flank_o, 0.0)
pair_box("FlankLip", _toe_hi[0] - 0.05, -34.0, ROOF_Y - 0.32, ROOF_Y, 36.0, 44.0, "roof")
# On the lip, in from the toe. Past the toe the bar would hang in the air.
pair_box("FlankLipEdge", _toe_hi[0] + 0.04, _toe_hi[0] + 0.34, ROOF_Y - 0.06, ROOF_Y, 38.2, 41.6, "hazard")

# Low-end deck: from the toe east onto the quay's outer edge (x=-32), then further
# downhill. It stops there so it does not cut the dock surf on the inner face.
_toe_lo = toe_world(FLANK_BASIS, flank_o, FLANK_DEPTH)
pair_box("FlankDeck", _toe_lo[0] - 0.15, -31.6, QUAY_Y - 0.32, QUAY_Y,
         _toe_lo[2] - 12.0, _toe_lo[2] + 0.4, "concrete")
pair_box("FlankPostA", -38.6, -37.4, 0.0, QUAY_Y - 0.32, _toe_lo[2] - 9.4, _toe_lo[2] - 8.2, "concrete")
pair_box("FlankPostB", -35.4, -34.2, 0.0, QUAY_Y - 0.32, _toe_lo[2] - 3.6, _toe_lo[2] - 2.4, "concrete")

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
        "path_rotation_accurate = false",
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
    _add_path_poly(prefix + "Fill", path_name, CORNER_FILL, "concrete")
    # Behind the ridge (local +X is away from the centre on the mirrored profile).
    _add_path_poly(prefix + "Wall", path_name, CORNER_WALL, "concrete")
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
        corner_exits.append((prefix, end, (end_travel[0], end_travel[2])))
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

# Balcony on the open side of the entry toe (west, toward the dock) and back onto the east roof.
# The face itself is east of the toe.
_pad_x1 = c_toes[0][0] + 0.12
_pad_z0 = min(c_toes[0][2], 24.0) - 0.8
pair_box("CornerPad", 18.2, _pad_x1, ROOF_Y - 0.32, ROOF_Y, _pad_z0, 28.6, "roof")
pair_box("CornerPadEdge", c_toes[0][0] - 0.32, c_toes[0][0] - 0.02, ROOF_Y - 0.06, ROOF_Y,
         c_toes[0][2] - 0.28, c_toes[0][2] + 0.28, "hazard")
# No deck on the exit. The run leaves going west, into the dock, and a floor there would stop it.

# Side link. From the east quay up the north-east corner of the loods, ~24°.
# Stays east of the corner wall (its outer face is x≤30.85) so it does not cover the surf.
# Top is exactly roof height; the foot is exactly quay height. About 2.4 m wide.
# The foot is solid with the quay, so the east edge is not a floating shelf.
pair_box("SideLinkPad", 31.2, 33.95, 0.0, QUAY_Y, 13.6, 17.6, "concrete")
pair_ramp_z("SideLink", 31.4, 33.8, 15.6, 29.0, ROOF_Y - QUAY_Y, "steel", y0=QUAY_Y)
pair_box("SideLinkLand", 31.3, 33.9, ROOF_Y - 0.48, ROOF_Y, 29.0, 30.55, "steel")
add_ramp_probes()

# ---------------------------------------------------------------- parapets (gaps are the surf lip, the ramp bridge, the balcony, one drop)
def para(name, x0, x1, z0, z1):
    pair_box(name, x0, x1, ROOF_Y, ROOF_Y + PARAPET, z0, z1, "concrete")


# West roof.
para("WParN1", -34.0, -30.0, 28.0, 28.45)
para("WParN2", -26.0, -14.0, 28.0, 28.45)  # gap -30..-26 is the drop
para("WParS", -34.0, -14.0, 49.55, 50.0)
para("WParW1", -34.0, -33.55, 28.0, 36.0)
para("WParW2", -34.0, -33.55, 44.0, 50.0)  # gap 36..44 is the flank lip
para("WParE1", -14.45, -14.0, 28.0, 44.55)
para("WParE2", -14.45, -14.0, 48.70, 49.5)  # gap is the exterior ramp
# East roof.
para("EParN1", 14.0, 18.0, 28.0, 28.45)
para("EParN2", 30.0, 30.7, 28.0, 28.45)  # gap 18..30 balcony, 30.7..34 is the side link
para("EParS", 14.0, 34.0, 49.55, 50.0)
para("EParE", 33.55, 34.0, 30.7, 50.0)  # north end is the side-link landing
para("EParW1", 14.0, 14.45, 28.0, 29.35)
para("EParW2", 14.0, 14.45, 33.50, 50.0)
# AC on the roof: 1.1 m, the crate row, off the gaps and the shafts.
pair_box("WestAC", -28.5, -26.2, ROOF_Y, ROOF_Y + 1.1, 41.5, 43.8, "steel")
pair_box("EastAC", 26.2, 28.6, ROOF_Y, ROOF_Y + 1.1, 34.2, 36.6, "steel")

# ---------------------------------------------------------------- cover
# Bus across each street, so the spawn door does not see the dock.
pair_box("Bus", -4.6, 4.6, 0.0, 2.4, 37.4, 40.6, "bus")
# Containers across the dock, 2.6 m, breaking the long axis.
pair_box("DockBox", -3.05, 3.05, 0.0, 2.6, 15.2, 17.6, "c_red")
# Van, 1.4 m, off the cross surf (that surf is |x|<9, z about -1.5..1.8).
pair_box("Van", 5.2, 8.6, 0.35, 1.75, -9.4, -6.2, "van")
# Crates in the flank lane, the quay and the dock. 1.10 m.
pair_box("LaneCrateA", -40.4, -38.2, 0.0, 1.1, -16.0, -14.0, "cover")
pair_box("LaneCrateB", -39.6, -37.4, 0.0, 1.1, -4.0, -2.0, "cover")
pair_box("LaneCrateC", -40.2, -38.0, 0.0, 1.1, 8.0, 10.0, "cover")
pair_box("LaneCrateD", -39.4, -37.2, 0.0, 1.1, 20.0, 22.0, "cover")
pair_box("LaneCrateE", -40.0, -37.8, 0.0, 1.1, 32.0, 34.0, "cover")
pair_box("QuayCrateA", -28.4, -26.2, QUAY_Y, QUAY_Y + 1.1, -10.0, -8.0, "cover")
pair_box("QuayCrateB", -27.2, -25.0, QUAY_Y, QUAY_Y + 1.1, 6.0, 8.0, "cover")
pair_box("DockCrateA", -12.4, -10.2, 0.0, 1.1, 6.4, 8.4, "cover")
pair_box("DockCrateB", 8.2, 10.4, 0.0, 1.1, -5.2, -3.2, "cover")
# Off the street-ramp foot (that foot is x -12..-7, z≈23).
pair_box("StreetCrate", -6.2, -4.2, 0.0, 1.1, 12.4, 14.4, "cover")

# ---------------------------------------------------------------- spawns
# Yards behind a 3.2 m wall. Team colour only on that wall. Baffles close the flanks.
# The wall covers the street mouth. The baffles meet the loods, so a spawn does not
# look down the flank. The way out is the strip between this wall and the south doors.
pair_box("SpawnWall", -16.0, 16.0, 0.0, 3.2, 54.6, 55.3, "team_blue", "team_orange")
pair_box("BaffleIn", -45.2, -33.8, 0.0, 3.2, 53.8, 54.5, "concrete")
pair_box("BaffleOut", 33.8, 45.2, 0.0, 3.2, 53.8, 54.5, "concrete")
pair_box("TruckA", 5.2, 8.4, 0.0, 1.9, 56.0, 59.0, "van")
pair_box("TruckB", -8.4, -5.2, 0.0, 1.9, 56.0, 59.0, "van")
pair_box("SpawnCrateA", -28.6, -26.4, 0.0, 1.1, 55.2, 57.2, "cover")
pair_box("SpawnCrateB", 26.4, 28.6, 0.0, 1.1, 55.6, 57.6, "cover")

# ---------------------------------------------------------------- lights (omni, no shadows)
WARM = (1.0, 0.86, 0.70)
COOL = (0.78, 0.86, 1.0)
pair_light("InsideA", (-24.0, 2.4, 39.0), WARM, 0.7, 12.0)
pair_light("InsideB", (24.0, 2.4, 39.0), WARM, 0.7, 12.0)
pair_light("RoofLight", (-24.0, 12.4, 40.0), WARM, 0.35, 10.0)
pair_light("QuayLight", (-26.0, 6.2, 0.0), COOL, 0.4, 14.0)
pair_light("CornerLight", (24.0, 12.2, 26.0), WARM, 0.4, 11.0)
light("DockA", (-6.0, 5.5, 8.0), COOL, 0.45, 16.0)
light("DockB", (6.0, 5.5, -8.0), COOL, 0.45, 16.0)
pair_light("Yard", (0.0, 3.4, 57.0), WARM, 0.35, 10.0)


def _end_strip(name, basis, origin, along, floor_y, sign=1.0, drop=0.0):
    """Catch volume at the toe, as tall as this surf. sign -1 leaves through the origin end."""
    toe_pos = toe_world(basis, origin, along)
    strips.append(speed_strip.make(
        name, toe_pos, speed_strip.forward_xz(basis, sign), floor_y, height=drop))


_end_strip("StripFlankW", FLANK_BASIS, flank_o, FLANK_DEPTH, QUAY_Y, drop=FLANK_DROP)
_end_strip("StripFlankE", FLANK_E_BASIS, flank_e, FLANK_DEPTH, QUAY_Y, drop=FLANK_DROP)
_end_strip("StripDockW", DOCK_BASIS, dock_o, DOCK_DEPTH, 0.0, drop=DOCK_DROP)
_end_strip("StripDockE", DOCK_E_BASIS, dock_e, DOCK_DEPTH, 0.0, drop=DOCK_DROP)
_end_strip("StripCross", CROSS_BASIS, (CROSS_DEPTH / 2.0, 0.1, 1.8), CROSS_DEPTH, 0.0)
for _prefix, _end, _fwd in corner_exits:
    strips.append(speed_strip.make(
        "Strip" + _prefix, _end, _fwd, QUAY_Y, height=ROOF_Y - QUAY_Y))


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
