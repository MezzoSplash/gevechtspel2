#!/usr/bin/env python3
"""Generates scenes/maps/townhouses.tscn: "Townhouses", a Dutch canal street built for flow (v2).

CSG under one Arena combiner (collision layer 1), so main.gd bakes the bot navmesh from it.
Re-run after editing:  python3 tools/gen_townhouses.py

v2 (map pass; Foundry v2 set the pattern: blockout first, played in rounds, pieces that belong to
the place). The old Townhouses was four boxes on a flat floor. v2 is a canal street:

  - A canal down the middle, its floor 3 m under the quays: the quay walls are wallruns, the bridges
    are the crossings, boats are cover down there.
  - A row of canal houses along each quay. Their steep tiled roofs (57°) are surfs: the ridge line
    falls from 9 m at a team's end to 3 m past the middle, so each team's row is a flow line into
    the other half, with a strip halfway and one at the foot.
  - A drawbridge in the middle under a tall steel portal: the landmark and the grapple anchor.
    A church tower outside the wall is the skyline.
  - Street things for cover: market stalls, parked cars, bike racks, planters, a tram stop.

Half-turn, not a mirror (Blue at +Z, Orange at -Z): a mirrored basis drops CSG collision.
"""
import math
import os

import speed_strip

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "townhouses.tscn")

MATS = {
    "floor": ((0.22, 0.24, 0.27), 0.90),      # asphalt
    "cobble": ((0.34, 0.33, 0.32), 0.92),     # quay paving
    "quay": ((0.40, 0.39, 0.36), 0.88),       # quay wall stone
    "water": ((0.16, 0.24, 0.28), 0.35),      # canal floor, read as water
    "outer": ((0.34, 0.37, 0.42), 0.85),
    "brick_w": ((0.55, 0.36, 0.22), 0.85),    # warm brick
    "brick_c": ((0.22, 0.42, 0.48), 0.85),    # cool brick
    "house_b": ((0.27, 0.46, 0.62), 0.82),    # dusty blue (team-cousin, on the rows only)
    "house_o": ((0.70, 0.44, 0.18), 0.82),    # ochre
    "roof": ((0.36, 0.22, 0.18), 0.80),       # roof tiles: the surf faces
    "trim": ((0.20, 0.21, 0.23), 0.88),
    "concrete": ((0.36, 0.36, 0.35), 0.88),  # sub() material (fill cuts, never visible)
    "steel": ((0.30, 0.33, 0.37), 0.62),
    "hazard": ((0.78, 0.62, 0.14), 0.75),
    "wood": ((0.48, 0.40, 0.32), 0.80),
    "awning": ((0.55, 0.20, 0.17), 0.80),
    "car": ((0.24, 0.30, 0.36), 0.70),
    "boat": ((0.30, 0.36, 0.30), 0.75),
    "green": ((0.16, 0.36, 0.22), 0.85),
    "team_blue": ((0.27, 0.46, 0.62), 0.82),
    "team_orange": ((0.70, 0.44, 0.18), 0.82),
}

# ~57° face. Buried 0.1 m into the wall and the floor. Same triangle as Quay.
SURF_POLY = (-0.1, -0.1, 3.30, -0.1, -0.1, 5.15)
SURF_TOE = 3.30  # local X of the toe
# The court gutter's smaller section, same 57° face: a full-size wedge stood 11 m tall in the court.
GUTTER_TOE = 2.2
GUTTER_POLY = (-0.1, -0.1, GUTTER_TOE, -0.1, -0.1, (GUTTER_TOE + 0.1) * 5.25 / 3.40 - 0.1)

nodes = []  # (name, type, transform, extra_lines, mat, parent)
lights = []
strips = []
report = []  # lines printed after writing, for a human to check the numbers


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


def box_h(name, x0, x1, y0, y1, z0, z1, mat, mat_o=None):
    """Blue-side box plus its half-turn (x, z) -> (-x, -z) for Orange."""
    box(name + "_B", x0, x1, y0, y1, z0, z1, mat)
    box(name + "_O", -x1, -x0, y0, y1, -z1, -z0, mat_o or mat)


def sub(name, x0, x1, y0, y1, z0, z1):
    """Subtract from whatever was unioned before this node. Order in the file matters."""
    box(name, x0, x1, y0, y1, z0, z1, "concrete", op=2)


def sub_h(name, x0, x1, y0, y1, z0, z1):
    sub(name + "_B", x0, x1, y0, y1, z0, z1)
    sub(name + "_O", -x1, -x0, y0, y1, -z1, -z0)


def ramp_z(name, x0, x1, z_low, z_high, h, mat, t=0.35, y0=0.0):
    """Thin ramp along Z. The top meets y0 at z_low and y0 + h at z_high. Basis det is +1."""
    dz = z_high - z_low
    length = math.hypot(dz, h)
    Z = (0.0, h / length, dz / length)
    Y = (0.0, abs(dz) / length, -h / length * (1 if dz > 0 else -1))
    X = (Y[1] * Z[2] - Y[2] * Z[1], Y[2] * Z[0] - Y[0] * Z[2], Y[0] * Z[1] - Y[1] * Z[0])
    mid = ((x0 + x1) / 2, y0 + h / 2, (z_low + z_high) / 2)
    c = tuple(mid[i] - Y[i] * t / 2 for i in range(3))
    add(name, "CSGBox3D", xform((X, Y, Z), c),
        ["size = Vector3(%s, %s, %s)" % (fmt(abs(x1 - x0)), fmt(t), fmt(length))], mat)


def ramp_z_h(name, x0, x1, z_low, z_high, h, mat, y0=0.0):
    ramp_z(name + "_B", x0, x1, z_low, z_high, h, mat, y0=y0)
    ramp_z(name + "_O", -x1, -x0, -z_low, -z_high, h, mat, y0=y0)


def light(name, pos, col, energy, rng):
    lights.append((name, pos, col, energy, rng))


def _v(a, b, s=1.0):
    return tuple(a[i] + b[i] * s for i in range(3))


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _unit(a):
    n = math.sqrt(sum(c * c for c in a))
    return tuple(c / n for c in a)


def basis_det(b):
    (X, Y, Z) = b
    return (X[0] * (Y[1] * Z[2] - Y[2] * Z[1])
            - X[1] * (Y[0] * Z[2] - Y[2] * Z[0])
            + X[2] * (Y[0] * Z[1] - Y[1] * Z[0]))


def surf_line(name, toe_start, toe_end, open_xz, mat="surf", poly=SURF_POLY, toe=SURF_TOE):
    """A straight ~57° surf whose toe runs from `toe_start` to `toe_end` (world, the toe is the
    lowest edge of the face, where it meets the floor or the air) and whose face opens toward the
    horizontal direction `open_xz`. Returns (basis, origin, depth).

    The basis is built, not picked: local -Z is the travel along the toe, local +X is the open side
    made square to it, local Y completes a right-handed frame, so det is +1 by construction (a
    mirrored basis makes CSG drop the collision, which is why the old file had YAW180 tables).
    """
    d = _v(toe_end, toe_start, -1.0)
    depth = math.sqrt(sum(c * c for c in d))
    Z = _unit(tuple(-c for c in d))
    o = (open_xz[0], 0.0, open_xz[1])
    X = _unit(_v(o, Z, -sum(o[i] * Z[i] for i in range(3))))
    Y = _cross(Z, X)
    if Y[1] < 0.0:
        # With this open side the frame comes out upside down (Y = Z x X points at the floor).
        # Extrude from the other end instead: Z flips, Y comes up, and det stays +1.
        return surf_line(name, toe_end, toe_start, open_xz, mat, poly, toe)
    basis = (X, Y, Z)
    # The toe is local (SURF_TOE, -0.1, 0): put that point on toe_start.
    origin = _v(_v(toe_start, X, -toe), Y, 0.1)
    line = "polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in poly)
    add(name, "CSGPolygon3D", xform(basis, origin), [line, "depth = %s" % fmt(depth)], mat)
    report.append("  surf %-12s det=%.3f len=%.1f drop=%.2f pitch=%.1f deg face ny=%.2f" % (
        name, basis_det(basis), depth, toe_start[1] - toe_end[1],
        math.degrees(math.asin((toe_start[1] - toe_end[1]) / depth)), face_ny(basis)))
    return basis, origin, depth


def face_ny(basis):
    """Y of the face normal: the hypotenuse runs from the toe up to the wall side."""
    (X, Y, _Z) = basis
    # In profile space the face normal is (5.25, 3.40) normalised (toe side and up).
    h = math.hypot(3.40, 5.25)
    return (X[1] * 5.25 + Y[1] * 3.40) / h


def toe_at(basis, origin, along, toe=SURF_TOE):
    local = (toe, -0.1, -along)
    return tuple(origin[i] + basis[0][i] * local[0] + basis[1][i] * local[1] + basis[2][i] * local[2]
                 for i in range(3))


def strip_at(name, basis, origin, along, floor_y, drop=0.0, toe=SURF_TOE):
    """Speed strip on the toe, `along` metres down the surf. `floor_y` is the toe's own height:
    a strip mid-surf catches the rider on the face, one at the foot catches the exit."""
    strips.append(speed_strip.make(
        name, toe_at(basis, origin, along, toe), speed_strip.forward_xz(basis, 1.0), floor_y, height=drop))


# Fill under a toe that descends along Z, from the wall out to the toe, so there is no crawlspace
# under the face. The fill's top is the toe line (a few centimetres under it), never the face.
def fill_climb(name, x_wall, x_toe, z_low, z_high, h):
    length = abs(z_high - z_low)
    if z_high > z_low:
        basis = ((0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0))
        origin = (x_wall, 0.0, z_low)
    else:
        basis = ((0.0, 0.0, -1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0))
        origin = (x_wall, 0.0, z_low)
    poly = [0.0, -0.4, length + 0.8, -0.4, length + 0.8, h - 0.05]
    width = abs(x_toe - x_wall)
    add(name, "CSGPolygon3D", xform(basis, origin),
        ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in poly),
         "depth = %s" % fmt(width)], "concrete")



def cylinder(name, x, z, r, y0, y1, mat, sides=20):
    add(name, "CSGCylinder3D", xform(IDENT, (x, (y0 + y1) / 2, z)),
        ["radius = %s" % fmt(r), "height = %s" % fmt(y1 - y0), "sides = %d" % sides], mat)


def cylinder_h(name, x, z, r, h, mat, y0=0.0):
    """Upright cylinder at (x, z) plus its half-turn."""
    for tag, s in (("B", 1.0), ("O", -1.0)):
        cylinder(name + "_" + tag, s * x, s * z, r, y0, y0 + h, mat)


def heap_h(name, x0, x1, z0, z1, h, mat):
    """A ridge of sand: triangle across x (both slopes walkable when h is under half the width),
    extruded along z, plus its half-turn."""
    poly = [x0, 0.0, x1, 0.0, (x0 + x1) / 2, h]
    for tag, s in (("B", 1.0), ("O", -1.0)):
        pts = [v * (s if i % 2 == 0 else 1.0) for i, v in enumerate(poly)]
        # Local -Z is the extrusion: start at the far end so the prism covers z0..z1. The half-turn's
        # basis is yaw 180 (det +1), which flips local X too, so the points are given unflipped there.
        basis = IDENT if s > 0 else ((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))
        origin = (0.0, 0.0, z1) if s > 0 else (0.0, 0.0, -z1)
        pp = poly if s < 0 else pts
        add(name + "_" + tag, "CSGPolygon3D", xform(basis, origin),
            ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in pp),
             "depth = %s" % fmt(z1 - z0)], mat)



def cylinder(name, x, z, r, y0, y1, mat, sides=20):
    add(name, "CSGCylinder3D", xform(IDENT, (x, (y0 + y1) / 2, z)),
        ["radius = %s" % fmt(r), "height = %s" % fmt(y1 - y0), "sides = %d" % sides], mat)


# ---------------------------------------------------------------- shell
HX = 32.0
HZ = 48.0
WALL_T = 0.8
WALL_H = 15.0  # above the roof ridge at the 9 m end (9 + 5.15)
CANAL_X = 5.0  # the canal runs |x| < CANAL_X
CANAL_Y = -3.0
CANAL_Z = 38.0  # it runs |z| < CANAL_Z: the yards are solid ground
# Ground: everything but the canal is at 0; the canal is cut 3 m into a thick slab.
box("Ground", -HX - WALL_T, HX + WALL_T, CANAL_Y - 1.0, 0.0, -HZ - WALL_T, HZ + WALL_T, "floor")
sub("CanalCut", -CANAL_X, CANAL_X, CANAL_Y, 0.2, -CANAL_Z, CANAL_Z)
box("CanalWater", -CANAL_X, CANAL_X, CANAL_Y - 0.1, CANAL_Y, -CANAL_Z, CANAL_Z, "water")
box("WallWest", -HX - WALL_T, -HX, CANAL_Y - 1.0, WALL_H, -HZ - WALL_T, HZ + WALL_T, "outer")
box("WallEast", HX, HX + WALL_T, CANAL_Y - 1.0, WALL_H, -HZ - WALL_T, HZ + WALL_T, "outer")
box("WallSouth", -HX - WALL_T, HX + WALL_T, CANAL_Y - 1.0, WALL_H, HZ, HZ + WALL_T, "team_blue")
box("WallNorth", -HX - WALL_T, HX + WALL_T, CANAL_Y - 1.0, WALL_H, -HZ - WALL_T, -HZ, "team_orange")
# Quay paving strips on both quays (visual only: flush, the same height as the ground).
box_h("QuayPave", CANAL_X, CANAL_X + 6.0, -0.02, 0.0, -CANAL_Z, CANAL_Z, "cobble")
# Steps down into the canal at both ends of each quay (half-turn pairs), 3 m over 6 m.
ramp_z_h("CanalSteps", CANAL_X - 2.4, CANAL_X - 0.2, 30.0, 36.0, 3.0, "quay", y0=CANAL_Y)
ramp_z_h("CanalStepsB", -CANAL_X + 0.2, -CANAL_X + 2.4, 30.0, 36.0, 3.0, "quay", y0=CANAL_Y)

# ---------------------------------------------------------------- bridges
BRIDGE_Z = 22.0
box_h("Bridge", -CANAL_X - 0.5, CANAL_X + 0.5, -0.4, 0.0, BRIDGE_Z - 3.0, BRIDGE_Z + 3.0, "quay")
box_h("BridgeRailN", -CANAL_X, CANAL_X, 0.0, 1.0, BRIDGE_Z + 2.7, BRIDGE_Z + 3.0, "steel")
box_h("BridgeRailS", -CANAL_X, CANAL_X, 0.0, 1.0, BRIDGE_Z - 3.0, BRIDGE_Z - 2.7, "steel")
# The drawbridge in the middle: deck at 0, and a steel portal 11 m high over it - the landmark,
# and the anchor everyone grapples to.
box("DrawDeck", -CANAL_X - 0.5, CANAL_X + 0.5, -0.4, 0.0, -3.0, 3.0, "wood")
PORTAL_Y = 11.0
for sx in (-1.0, 1.0):
    for sz in (-1.0, 1.0):
        box("PortalPost%s%s" % ("E" if sx > 0 else "W", "S" if sz > 0 else "N"),
            sx * (CANAL_X + 0.6) - 0.35, sx * (CANAL_X + 0.6) + 0.35, 0.0, PORTAL_Y, sz * 2.6 - 0.35, sz * 2.6 + 0.35, "steel")
box("PortalBeamS", -CANAL_X - 1.0, CANAL_X + 1.0, PORTAL_Y - 0.8, PORTAL_Y, 2.25, 2.95, "steel")
box("PortalBeamN", -CANAL_X - 1.0, CANAL_X + 1.0, PORTAL_Y - 0.8, PORTAL_Y, -2.95, -2.25, "steel")
box("PortalCap", -CANAL_X - 1.0, CANAL_X + 1.0, PORTAL_Y, PORTAL_Y + 0.4, -2.95, 2.95, "steel")
box("PortalEdge", -CANAL_X - 1.0, CANAL_X + 1.0, PORTAL_Y - 0.86, PORTAL_Y - 0.8, -2.95, 2.95, "hazard")

# ---------------------------------------------------------------- canal houses and the roof surfs
# West row: houses x ROW_X0..ROW_X1 along the west quay. Blue's part (z ROOF_LOW_Z..ROOF_HIGH_Z) has
# the long falling roof; the rest of the row (Orange's end) is plain houses with flat roofs. The east
# row is the half-turn, so Orange's roof falls toward +Z on the east side.
ROW_X0, ROW_X1 = -24.0, -11.0
ROOF_HIGH_Z, ROOF_LOW_Z = 34.0, -12.0
ROOF_HIGH_Y, ROOF_LOW_Y = 9.0, 3.0
# The house mass under the roof: a prism whose top follows the roof's toe line (trapezoid in z-y),
# extruded across x from the back of the row to the face's toe.
def row_mass(name, x0, x1, z_low, z_high, y_low, y_high, mat):
    length = z_high - z_low
    poly = [0.0, 0.0, length, 0.0, length, y_high, 0.0, y_low]
    for tag, s in (("B", 1.0), ("O", -1.0)):
        # Local X runs along +z (Blue) / -z (Orange); local -Z extrudes across x toward the quay.
        if s > 0:
            basis = ((0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0))
            origin = (x0, 0.0, z_low)
        else:
            basis = ((0.0, 0.0, -1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0))
            origin = (-x0, 0.0, -z_low)
        add(name + "_" + tag, "CSGPolygon3D", xform(basis, origin),
            ["polygon = PackedVector2Array(%s)" % ", ".join(fmt(v) for v in poly),
             "depth = %s" % fmt(x1 - x0)], mat)


ROOF_TOE_X = ROW_X1  # the face's toe sits on the front of the houses, over the quay
row_mass("RowFall", ROW_X0, ROOF_TOE_X, ROOF_LOW_Z, ROOF_HIGH_Z, ROOF_LOW_Y - 0.05, ROOF_HIGH_Y - 0.05, "brick_w")
rb, ro, rdep = surf_line("RoofSurf_B", (ROOF_TOE_X, ROOF_HIGH_Y, ROOF_HIGH_Z),
                         (ROOF_TOE_X, ROOF_LOW_Y, ROOF_LOW_Z), (1.0, 0.0), mat="roof")
surf_line("RoofSurf_O", (-ROOF_TOE_X, ROOF_HIGH_Y, -ROOF_HIGH_Z),
          (-ROOF_TOE_X, ROOF_LOW_Y, -ROOF_LOW_Z), (-1.0, 0.0), mat="roof")
ob = tuple((-c[0], c[1], -c[2]) for c in rb)
oo = (-ro[0], ro[1], -ro[2])
for tag, b, o in (("B", rb, ro), ("O", ob, oo)):
    strip_at("StripRoofMid_" + tag, b, o, rdep * 0.5, (ROOF_HIGH_Y + ROOF_LOW_Y) * 0.5, 4.0)
    strip_at("StripRoofFoot_" + tag, b, o, rdep, ROOF_LOW_Y, ROOF_LOW_Y)
# The roof's back, behind the face, at the toe line: a flat strip of roof you can stand on.
# Gables: a step every 6 m along the row, so the facade reads as separate canal houses.
for i, z in enumerate(range(-6, 34, 6)):
    box_h("Gable%d" % i, ROOF_TOE_X - 0.05, ROOF_TOE_X + 0.25, 0.0, 2.6, z + 2.0, z + 2.4, "trim")
# The other end of the row: plain houses, flat roof at 6 m, an alley between them at z -14..-12.
box_h("RowPlain", ROW_X0, ROW_X1, 0.0, 6.0, -34.0, -14.0, "brick_c")
box_h("RowPlainCap", ROW_X0, ROW_X1, 6.0, 6.3, -34.0, -14.0, "trim")

# Way up to the roof's high end: a long ramp up the back alley (9 m over 24 m, about 21°) onto a
# roof deck behind the row's high end, where you step onto the surf. The plain houses' flat roof on
# the other end has a ramp from the quay up to a landing beside it. Each ramp ends exactly on the
# edge it climbs to: overlapped 1.5 m into the deck, it came out from under the deck's edge 0.6 m
# low, more than the nav agent's 0.5 m climb.
DECK = (-31.6, ROW_X1 + 0.6, ROOF_HIGH_Z, 40.0)
box_h("RoofDeck", DECK[0], DECK[1], ROOF_HIGH_Y - 0.3, ROOF_HIGH_Y, DECK[2], DECK[3], "trim")
box_h("RoofDeckPosts", -31.6, -29.6, 0.0, ROOF_HIGH_Y - 0.3, 38.0, 40.0, "brick_c")
box_h("RoofDeckPostsB", -13.0, -11.0, 0.0, ROOF_HIGH_Y - 0.3, 38.0, 40.0, "brick_c")
ramp_z_h("AlleyRamp", -31.6, -27.6, 12.0, DECK[2], ROOF_HIGH_Y, "wood")
box_h("AlleyRampEdge", -31.6, -27.6, -0.06, 0.0, 11.85, 12.15, "hazard")
ramp_z_h("PlainRoofRamp", -10.9, -8.4, -28.0, -17.0, 6.0, "wood")
box_h("PlainRoofLanding", -11.3, -8.4, 5.7, 6.0, -17.0, -14.0, "wood")
box_h("PlainRoofRampEdge", -10.9, -8.4, -0.06, 0.0, -28.15, -27.85, "hazard")

# ---------------------------------------------------------------- back alleys (the flanks)
# Behind each row: a lane with garden walls (1.9) and sheds, broken every so often.
box_h("GardenWallA", -31.0, -26.0, 0, 1.9, 8.0, 8.4, "brick_w")
box_h("GardenWallB", -29.0, -24.0, 0, 1.9, -4.0, -3.6, "brick_w")
box_h("Shed", -26.0, -24.2, 0, 2.6, 18.0, 22.0, "wood")
box_h("GardenWallC", -31.0, -26.0, 0, 1.9, -22.0, -21.6, "brick_w")

# ---------------------------------------------------------------- street cover on the quays
box_h("StallA", 7.0, 9.5, 0, 1.9, 8.0, 11.0, "wood")
box_h("StallAwnA", 6.8, 9.7, 2.4, 2.6, 7.8, 11.2, "awning")
box_h("CarA", 6.4, 8.4, 0.2, 1.4, -8.0, -3.4, "car")
box_h("BikesA", 9.6, 10.6, 0, 1.1, 14.0, 18.0, "steel")
box_h("PlanterA", 6.6, 8.2, 0, 1.1, 28.0, 30.0, "green")
box_h("TramStop", 7.0, 10.6, 0, 2.4, -20.0, -19.6, "steel")
box_h("TramStopRoof", 6.6, 11.0, 2.4, 2.6, -21.2, -19.4, "steel")
# Boats in the canal: cover down there.
box_h("BoatA", -3.6, -0.6, CANAL_Y, CANAL_Y + 1.4, 8.0, 15.0, "boat")
box_h("BoatB", 0.8, 3.8, CANAL_Y, CANAL_Y + 1.4, -16.0, -10.0, "boat")

# ---------------------------------------------------------------- spawn yards
SPAWN_WALL_Z = 41.0
box_h("SpawnWall", -10.0, 10.0, 0, 3.2, SPAWN_WALL_Z, SPAWN_WALL_Z + 0.7, "team_blue", "team_orange")
box_h("YardCar", 13.0, 17.0, 0.2, 1.4, 43.0, 45.0, "car")
# The church tower, outside the wall: the skyline.
for tag, (cx, cz) in (("B", (40.0, 20.0)), ("O", (-40.0, -20.0))):
    box("Church" + tag, cx - 3.0, cx + 3.0, 0.0, 22.0, cz - 3.0, cz + 3.0, "brick_w")
    box("ChurchSpireBase" + tag, cx - 2.2, cx + 2.2, 22.0, 26.0, cz - 2.2, cz + 2.2, "trim")
    box("ChurchSpire" + tag, cx - 1.0, cx + 1.0, 26.0, 34.0, cz - 1.0, cz + 1.0, "trim")

# ---------------------------------------------------------------- lights
WARM = (1.0, 0.85, 0.66)
COOL = (0.78, 0.86, 1.0)
light("QuayB", (8.0, 4.0, 18.0), WARM, 0.6, 14.0)
light("QuayO", (-8.0, 4.0, -18.0), WARM, 0.6, 14.0)
light("Bridge", (0.0, 8.0, 0.0), COOL, 0.5, 14.0)
light("DeckB", (-20.0, 7.5, 37.0), WARM, 0.6, 10.0)
light("DeckO", (20.0, 7.5, -37.0), WARM, 0.6, 10.0)


def main():
    mats = []
    for n in nodes:
        if n[4] not in mats:
            mats.append(n[4])
    out = ["[gd_scene load_steps=%d format=3]" % (len(mats) + 1 + speed_strip.LOAD_STEPS), ""]
    out += [
        '[sub_resource type="Environment" id="Env_townhouses"]',
        "background_mode = 1",
        "background_color = Color(0.13, 0.15, 0.18, 1)",
        "ambient_light_source = 2",
        "ambient_light_color = Color(0.52, 0.56, 0.62, 1)",
        "ambient_light_energy = 0.58",
        "tonemap_mode = 2",
        "ssao_enabled = false",
        "glow_enabled = false",
        "",
    ]
    out += speed_strip.resources()
    for m in mats:
        (r, g, b), rough = MATS[m]
        out += ['[sub_resource type="StandardMaterial3D" id="Mat_%s"]' % m,
                "albedo_color = Color(%s, %s, %s, 1)" % (fmt(r), fmt(g), fmt(b)),
                "roughness = %s" % fmt(rough), ""]
    out += ['[node name="Townhouses" type="Node3D"]', ""]
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env_townhouses")', ""]
    out += ['[node name="Sun" type="DirectionalLight3D" parent="."]',
            "transform = Transform3D(0.766, -0.4545, 0.4545, 0, 0.7071, 0.7071, -0.6428, -0.5417, 0.5417, 6, 18, 8)",
            "light_energy = 1.12",
            "light_color = Color(1, 0.95, 0.88, 1)",
            "shadow_enabled = true", ""]
    out += ['[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]', ""]
    out += ['[node name="Arena" type="CSGCombiner3D" parent="."]',
            "use_collision = true", "collision_layer = 1", "collision_mask = 0", ""]
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
    print("wrote %s (%d csg nodes, %d strips)" % (os.path.normpath(OUT), len(nodes), len(strips)))
    for line in report:
        print(line)
    for s in strips:
        c = s["center"]
        print("  strip %-18s center=(%.1f, %.1f, %.1f) ramp=%.2f" % (s["name"], c[0], c[1], c[2], s["ramp_h"]))


if __name__ == "__main__":
    main()
