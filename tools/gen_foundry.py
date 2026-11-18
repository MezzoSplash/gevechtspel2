#!/usr/bin/env python3
"""Generates scenes/maps/foundry.tscn: "Foundry", an industrial yard built for flow (v2).

CSG under one Arena combiner (collision layer 1), so main.gd bakes the bot navmesh from it.
Re-run after editing:  python3 tools/gen_foundry.py

v2 (map pass after #302; Rooftops was dropped in #304 for being a maze of blocks, see AGENTS.md).
The old Foundry was a 52 x 69 m yard full of crates around a dark hall. v2 keeps what makes it
Foundry (the rust hall with its roof, containers, a water tank, loading docks) and opens it up:

  - 64 x 90 m. Few, big pieces: the hall, container stacks (2.60 / 5.20), the tank, the bunkers.
    Lanes are broken by those and by height, not by a box every few metres.
  - The hall (24 x 28, roof 7.3 m) is the centre: a door on every side, an open floor, a skylight
    with a bridge, and its long walls are wallruns. Each team has a ramp up to the roof on its side.
  - Flow line per team: an ore bunker (10 m) beside its dock, and off its top a surf down the
    outer wall into the other team's back lane, with a strip halfway and one at the foot (LINE x2).
    Blue rides the west wall toward -Z, Orange (the half-turn) the east wall toward +Z.
  - Two crane runways span the yard at 11 m: grapple anchors that block nothing on the ground.

Half-turn, not a mirror (Blue at +Z, Orange at -Z): a mirrored basis drops CSG collision.
"""
import math
import os

import speed_strip

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "foundry.tscn")

MATS = {
    "floor": ((0.25, 0.25, 0.24), 0.92),
    "concrete": ((0.36, 0.36, 0.35), 0.88),
    "outer": ((0.30, 0.31, 0.33), 0.86),
    "hall": ((0.46, 0.30, 0.20), 0.84),
    "hall_trim": ((0.20, 0.21, 0.22), 0.88),
    "roof": ((0.26, 0.27, 0.28), 0.90),
    "steel": ((0.30, 0.32, 0.35), 0.6),
    "hazard": ((0.78, 0.62, 0.14), 0.75),
    "surf": ((0.36, 0.42, 0.48), 0.62),
    "c_red": ((0.56, 0.20, 0.15), 0.78),
    "c_blue": ((0.19, 0.32, 0.52), 0.78),
    "c_green": ((0.20, 0.40, 0.27), 0.78),
    "c_yellow": ((0.70, 0.55, 0.16), 0.78),
    "team_blue": ((0.27, 0.46, 0.62), 0.82),
    "team_orange": ((0.70, 0.44, 0.18), 0.82),
    "tank": ((0.55, 0.57, 0.58), 0.5),
    "furnace": ((0.42, 0.24, 0.17), 0.86),   # refractory brick, darker than the hall
    "ladle": ((0.22, 0.22, 0.23), 0.55),
    "sand": ((0.55, 0.46, 0.32), 0.95),      # moulding sand, warm and matte
    "mould": ((0.38, 0.33, 0.27), 0.85),
    "ingot": ((0.27, 0.25, 0.24), 0.6),
    "truck": ((0.22, 0.30, 0.36), 0.7),
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


# ---------------------------------------------------------------- shell
HX = 32.0
HZ = 45.0
WALL_T = 0.8
WALL_H = 16.0  # the flank surf's ridge at the 10 m end sits near 15.2 m
box("Floor", -HX - WALL_T, HX + WALL_T, -1.0, 0.0, -HZ - WALL_T, HZ + WALL_T, "floor")
box("WallWest", -HX - WALL_T, -HX, 0, WALL_H, -HZ - WALL_T, HZ + WALL_T, "outer")
box("WallEast", HX, HX + WALL_T, 0, WALL_H, -HZ - WALL_T, HZ + WALL_T, "outer")
box("WallSouth", -HX - WALL_T, HX + WALL_T, 0, WALL_H, HZ, HZ + WALL_T, "team_blue")
box("WallNorth", -HX - WALL_T, HX + WALL_T, 0, WALL_H, -HZ - WALL_T, -HZ, "team_orange")

# ---------------------------------------------------------------- the hall
HALL_X, HALL_Z = 12.0, 14.0
HALL_Y = 7.3
HW = 0.4  # wall thickness
box("HallShell", -HALL_X, HALL_X, 0, HALL_Y, -HALL_Z, HALL_Z, "hall")
sub("HallVoid", -HALL_X + HW, HALL_X - HW, 0.0, HALL_Y - 0.4, -HALL_Z + HW, HALL_Z - HW)
# A big door on each end (5.2 x 4.5) and one on each long side (4 x 3.2), offset so no door looks
# straight through to another.
sub_h("HallDoorEnd", 2.8, 8.0, 0.0, 4.5, HALL_Z - 0.6, HALL_Z + 0.6)  # off-centre: the two end doors never line up
sub_h("HallDoorSide", HALL_X - 0.6, HALL_X + 0.6, 0.0, 3.2, 3.0, 7.0)
# Skylight down the middle; the furnace stack rises through it.
sub("Skylight", -3.6, 3.6, HALL_Y - 0.6, HALL_Y + 0.2, -10.0, 10.0)
# The cupola furnace: the landmark. A refractory-brick shaft in the middle of the hall, a steel
# stack through the skylight to 18 m. It is the anchor everyone can see, and on the roof it is the
# cover that splits the roof in two, so the roof is not one platform that sees the whole yard.
cylinder("Furnace", 0.0, 0.0, 2.6, 0.0, 6.2, "furnace", 24)
cylinder("FurnaceBand", 0.0, 0.0, 2.75, 1.0, 1.4, "steel", 24)
cylinder("FurnaceStack", 0.0, 0.0, 1.5, 6.2, 18.0, "steel", 20)
box("FurnaceTap", -0.6, 0.6, 0.9, 1.3, 2.4, 3.8, "hazard")  # the tap spout, yellow edge
# Roof rim, low: the roof is a place to stand, not a box.
box_h("RoofRimEnd", -HALL_X, HALL_X, HALL_Y, HALL_Y + 0.5, HALL_Z - 0.4, HALL_Z, "hall_trim")
box_h("RoofRimSide", HALL_X - 0.4, HALL_X, HALL_Y, HALL_Y + 0.5, -HALL_Z, 10.0, "hall_trim")
# Inside, per half (box_h turns each piece into the other half): a hall to fight in, not a box.
#  - a mezzanine at 3 m along the long wall, with a stair, and cover under it;
#  - a press (2.60) inside the end door, a machine (1.90) inside the side door;
#  - a conveyor (1.10) down the middle of the half, and two roof columns.
MEZZ_Y = 3.0
box_h("Mezz", -HALL_X + HW, -7.6, MEZZ_Y - 0.3, MEZZ_Y, -2.0, HALL_Z - HW, "steel")
box_h("MezzRail", -7.85, -7.6, MEZZ_Y, MEZZ_Y + 1.1, -2.0, 0.8, "hall_trim")
box_h("MezzRailB", -7.85, -7.6, MEZZ_Y, MEZZ_Y + 1.1, 8.2, HALL_Z - HW, "hall_trim")
ramp_z_h("MezzStair", -7.6, -5.6, 1.0, 8.2, MEZZ_Y, "concrete")
box_h("MezzStairEdge", -7.6, -5.6, -0.06, 0.0, 0.85, 1.15, "hazard")
# Under the mezzanine: sand moulds waiting to be poured.
box_h("UnderMezz", -11.4, -9.4, 0, 1.1, 4.0, 7.0, "mould")
box_h("Press", 0.5, 4.0, 0, 2.6, 7.0, 10.5, "steel")  # the moulding press
# The pouring line: moulding flasks (1.10) on a roller track from the furnace's tap toward the side
# door. Three flasks, gaps between them, so it is cover you move along, not a wall.
box_h("RollerTrack", 3.0, 11.0, 0, 0.35, 1.0, 2.6, "hall_trim")
for i, x in enumerate((4.0, 6.6, 9.2)):
    box_h("Flask%d" % i, x, x + 1.6, 0.35, 1.1, 1.1, 2.5, "mould")
box_h("Conveyor", -3.5, -2.3, 0, 1.1, 3.4, 12.0, "hall_trim")
box_h("ColumnA", 4.7, 5.3, 0, HALL_Y - 0.4, 6.7, 7.3, "hall_trim")
box_h("ColumnB", -5.3, -4.7, 0, HALL_Y - 0.4, 10.2, 10.8, "hall_trim")
# Roof ramp per team, along the long wall on its side, landing at the roof's end corner.
RAMP_X0, RAMP_X1 = HALL_X + 0.1, HALL_X + 3.5
ramp_z_h("RoofRamp", RAMP_X0, RAMP_X1, 30.0, HALL_Z - 0.2, HALL_Y, "concrete")
box_h("RoofRampEdge", RAMP_X0, RAMP_X1, -0.06, 0.0, 29.85, 30.15, "hazard")
# The ramp ends beside the roof: a landing carries you across onto it (the rim is cut there).
box_h("RoofLanding", HALL_X - 0.4, RAMP_X1, HALL_Y - 0.3, HALL_Y, 9.6, HALL_Z, "roof")
sub_h("RoofRampMouth", HALL_X - 0.5, HALL_X + 0.1, HALL_Y, HALL_Y + 0.6, 9.6, HALL_Z)

# ---------------------------------------------------------------- bunker and flank surf
# Blue's ore bunker sits in the west corner by its dock; the surf runs off its north face down the
# west wall. Two ways up: the ramp on its east side, and the grapple (its rim is an anchor).
BUNK_X0, BUNK_X1 = -HX, -22.0
BUNK_Z0, BUNK_Z1 = 26.0, 36.0
BUNK_Y = 10.0
box_h("Bunker", BUNK_X0, BUNK_X1, 0, BUNK_Y, BUNK_Z0, BUNK_Z1, "concrete")
ramp_z_h("BunkerRamp", BUNK_X1, BUNK_X1 + 3.6, 16.0, BUNK_Z0 + 2.0, BUNK_Y, "concrete")
# The ramp tops out onto a landing beside the bunker, the full depth of its top: a 1 m gap between a
# rim and the ramp's end was too narrow for the nav agent, and only Blue's side made it by rounding.
box_h("BunkerLanding", BUNK_X1 - 0.2, BUNK_X1 + 3.6, BUNK_Y - 0.3, BUNK_Y, BUNK_Z0 + 2.0, BUNK_Z1, "concrete")
box_h("BunkerLandingEdge", BUNK_X1 + 3.3, BUNK_X1 + 3.6, BUNK_Y, BUNK_Y + 0.6, BUNK_Z0 + 3.0, BUNK_Z1, "hazard")
box_h("BunkerRampEdge", BUNK_X1, BUNK_X1 + 3.6, -0.06, 0.0, 15.85, 16.15, "hazard")

FLANK_TOE_X = -HX + 0.05 + SURF_TOE
FLANK_HIGH_Z = BUNK_Z0
FLANK_LOW_Z = -24.0
fb, fo, fdep = surf_line("SurfFlank_B", (FLANK_TOE_X, BUNK_Y, FLANK_HIGH_Z),
                         (FLANK_TOE_X, 0.0, FLANK_LOW_Z), (1.0, 0.0))
surf_line("SurfFlank_O", (-FLANK_TOE_X, BUNK_Y, -FLANK_HIGH_Z),
          (-FLANK_TOE_X, 0.0, -FLANK_LOW_Z), (-1.0, 0.0))
fill_climb("FillFlank_B", -HX + 0.05, FLANK_TOE_X - 0.15, FLANK_LOW_Z, FLANK_HIGH_Z, BUNK_Y)
fill_climb("FillFlank_O", HX - 0.05, -FLANK_TOE_X + 0.15, -FLANK_LOW_Z, -FLANK_HIGH_Z, BUNK_Y)
mid = fdep * 0.5
ob = tuple((-c[0], c[1], -c[2]) for c in fb)
oo = (-fo[0], fo[1], -fo[2])
for tag, b, o in (("B", fb, fo), ("O", ob, oo)):
    strip_at("StripFlankMid_" + tag, b, o, mid, BUNK_Y * 0.5, BUNK_Y * 0.5)
    strip_at("StripFlankFoot_" + tag, b, o, fdep, 0.0, BUNK_Y)

# ---------------------------------------------------------------- crane runways (grapple)
CRANE_Y = 11.0
for tag, z in (("A", 20.0), ("B", -20.0)):
    box("Crane" + tag, -25.5, 25.5, CRANE_Y, CRANE_Y + 0.8, z - 0.5, z + 0.5, "steel")
    box("Crane%sEdge" % tag, -25.5, 25.5, CRANE_Y - 0.06, CRANE_Y, z - 0.5, z + 0.5, "hazard")
    for sx in (-1.0, 1.0):
        box("Crane%sPost%s" % (tag, "E" if sx > 0 else "W"), sx * 25.5 - 0.4, sx * 25.5 + 0.4, 0,
            CRANE_Y + 0.8, z - 0.4, z + 0.4, "steel")

# A ladle hangs from each runway on its hook: a grapple anchor in the middle of the air.
for tag, (lx, lz) in (("A", (8.0, 20.0)), ("B", (-8.0, -20.0))):
    box("LadleHook" + tag, lx - 0.15, lx + 0.15, 8.7, CRANE_Y, lz - 0.15, lz + 0.15, "steel")
    cylinder("LadleHung" + tag, lx, lz, 1.5, 6.5, 8.7, "ladle")
# Two smokestacks outside the walls: the skyline that says foundry from anywhere in the map.
for tag, (sx, sz) in (("B", (38.0, 30.0)), ("O", (-38.0, -30.0))):
    cylinder("Smokestack" + tag, sx, sz, 1.8, 0.0, 30.0, "furnace")
    cylinder("SmokestackBand" + tag, sx, sz, 1.95, 26.0, 26.6, "steel")

# ---------------------------------------------------------------- yard: a few structures, not scattered cover
# The flanks are long; they are broken by three structures per flank, each also a movement piece:
# box_h/cylinder_h put each one on both flanks, turned, so read the list as "one flank".
#  - a container island across the lane (2.6 low end at the toe side, 5.2 high end at the hall side),
#    with a 1.6 m passage by the surf toe and a 2.5 m one by the hall: a gate, a wallrun, an anchor;
#  - a shed in the other half's back lane (3.4 m, doors on three sides): a small room to fight in;
#  - the water tank near the hall, with its foot.
box_h("IslandLow", -27.0, -21.0, 0, 2.6, 8.0, 12.0, "c_green")
box_h("IslandHigh", -21.0, -14.5, 0, 5.2, 8.0, 12.0, "c_red")
SHED = (-28.0, -20.0, -33.0, -26.0)
box_h("Shed", SHED[0], SHED[1], 0, 3.4, SHED[2], SHED[3], "c_blue")
sub_h("ShedVoid", SHED[0] + 0.3, SHED[1] - 0.3, 0.0, 3.1, SHED[2] + 0.3, SHED[3] - 0.3)
sub_h("ShedDoorN", -25.5, -23.0, 0.0, 2.4, SHED[3] - 0.5, SHED[3] + 0.1)
sub_h("ShedDoorS", -25.5, -23.0, 0.0, 2.4, SHED[2] - 0.1, SHED[2] + 0.5)
sub_h("ShedDoorE", SHED[1] - 0.5, SHED[1] + 0.1, 0.0, 2.4, -30.6, -28.4)
cylinder_h("Tank", -18.0, -12.0, 2.2, 5.0, "tank")
box_h("TankFoot", -20.6, -15.4, 0, 0.4, -14.6, -9.4, "concrete")
# A ladle car in front of each of the hall's end doors, off-centre: a transfer cart (1.0) with a
# casting ladle on it (to 3.0). It hides a body; the ladle's rim is a head-glitch at 3 m.
box_h("LadleCart", 3.8, 9.2, 0, 1.0, 18.2, 21.0, "steel")
cylinder_h("LadleOnCart", 6.5, 19.6, 1.4, 2.0, "ladle", 1.0)
# More to fight around in the yard (playtest: v2 was too open), still only heights from the table:
# a container beside the hall's side door, a barrier at chest height near it, and one by the crane post.
# Moulding sand in a ridge beside the hall's side door (33°: you run up it for height and a look).
heap_h("SandHeap", 18.0, 27.0, 0.6, 6.4, 2.9, "sand")
# Pig iron: stacked ingots, chest and hip height, where the old barriers stood.
box_h("IngotsA", 14.0, 17.0, 0, 1.1, 1.6, 3.0, "ingot")
box_h("IngotsB", 14.4, 16.6, 1.1, 1.4, 1.8, 2.8, "ingot")
box_h("IngotsCrane", -28.0, -24.0, 0, 1.4, 21.0, 22.4, "ingot")
box_h("Moulds", -16.0, -13.0, 0, 1.1, 29.0, 32.0, "mould")

# ---------------------------------------------------------------- docks and spawn yards
SPAWN_WALL_Z = 37.5
box_h("SpawnWall", -10.0, 10.0, 0, 3.2, SPAWN_WALL_Z, SPAWN_WALL_Z + 0.7, "team_blue", "team_orange")
box_h("Dock", -10.0, 10.0, 0, 1.2, 43.0, HZ, "concrete")
ramp_z_h("DockRampW", -13.0, -10.0, 39.5, 44.0, 1.2, "concrete")
box_h("Truck", 13.0, 16.0, 0, 1.9, 39.0, 44.0, "truck")

# ---------------------------------------------------------------- lights
WARM = (1.0, 0.82, 0.62)
COOL = (0.75, 0.86, 1.0)
light("HallA", (0.0, 5.6, 6.0), WARM, 1.5, 15.0)
light("HallB", (0.0, 5.6, -6.0), WARM, 1.5, 15.0)
light("HallMezzB", (-9.0, 2.6, 8.0), WARM, 0.9, 9.0)
light("HallMezzO", (9.0, 2.6, -8.0), WARM, 0.9, 9.0)
light("YardB", (0.0, 5.0, 30.0), WARM, 0.6, 14.0)
light("YardO", (0.0, 5.0, -30.0), WARM, 0.6, 14.0)


def main():
    mats = []
    for n in nodes:
        if n[4] not in mats:
            mats.append(n[4])
    out = ["[gd_scene load_steps=%d format=3]" % (len(mats) + 1 + speed_strip.LOAD_STEPS), ""]
    out += [
        '[sub_resource type="Environment" id="Env_foundry"]',
        "background_mode = 1",
        "background_color = Color(0.19, 0.17, 0.17, 1)",
        "ambient_light_source = 2",
        "ambient_light_color = Color(0.6, 0.54, 0.5, 1)",
        "ambient_light_energy = 0.7",
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
    out += ['[node name="Foundry" type="Node3D"]', ""]
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env_foundry")', ""]
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
