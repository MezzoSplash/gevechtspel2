#!/usr/bin/env python3
"""Generates scenes/maps/rooftops.tscn: "Rooftops", a flat-roof housing court built for flow.

Same pipeline as Quay: CSG under one Arena combiner (collision layer 1), so main.gd bakes the
bot navmesh from it. Re-run after editing:  python3 tools/gen_rooftops.py

v2 (the map pass after #302): the old Rooftops was a layout from before surf chains, the carry,
the combo and the grapple, with movement bolted on. v2 keeps what it is (two brick blocks with
6 m roofs around a court, skybridges at roof height) and is laid out around three flow lines:

  1. Flank line. Each team owns one flank: off its own roof along a launch deck at 6 m, onto a
     surf on the outer wall that runs 6 m -> 0 m over 48 m into the other team's back lane.
     A strip mid-way and one at the foot: one clean ride is LINE x2. Blue rides the west wall
     toward -Z, Orange (the half-turn) the east wall toward +Z. The lane beside it stays a lane.
  2. Court line. A court surf drops from each roof edge to the middle of the court, a strip at the
     bottom, and the exit runs straight up the other team's court ramp onto their roof. The surf's
     back is a vertical face in the court: wallrun it.
  3. Grapple. A steel gantry spans the court at 11 m: the anchor that turns a court exit into a
     roof, a bridge or the far flank. Roof parapets are anchors too.

Rules from docs/art (Maps): no clean lane over 35 m, spawns never see each other, every floor has
two ways up, a walk route beside every surf, bots walk (stairs, ramps, flanks), not surf. Cover
comes from the height table (1.10 / 1.40 / 1.90 / 2.60 m), big pieces, no crate clutter in the
fast lanes: a carry dies on a 1 m crate.

Half-turn, not a mirror (Blue at +Z, Orange at -Z): a mirrored basis drops CSG collision.
Playable inside the walls is 70 x 100.
"""
import math
import os

import speed_strip

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "rooftops.tscn")

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
    "ac": ((0.45, 0.47, 0.48), 0.72),
    "van": ((0.25, 0.32, 0.36), 0.70),
    "trim": ((0.20, 0.21, 0.23), 0.88),
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


# ---------------------------------------------------------------- shell
HX = 35.0  # inner half-width
HZ = 50.0  # inner half-length
WALL_T = 0.8
WALL_H = 12.5  # the flank surf's ridge at the 6 m end sits near 11.2 m
box("Floor", -HX - WALL_T, HX + WALL_T, -1.0, 0.0, -HZ - WALL_T, HZ + WALL_T, "floor")
box("WallWest", -HX - WALL_T, -HX, 0, WALL_H, -HZ - WALL_T, HZ + WALL_T, "outer")
box("WallEast", HX, HX + WALL_T, 0, WALL_H, -HZ - WALL_T, HZ + WALL_T, "outer")
box("WallSouth", -HX - WALL_T, HX + WALL_T, 0, WALL_H, HZ, HZ + WALL_T, "team_blue")
box("WallNorth", -HX - WALL_T, HX + WALL_T, 0, WALL_H, -HZ - WALL_T, -HZ, "team_orange")

# ---------------------------------------------------------------- blocks
# Blue block x -16..16, z 16..34; Orange is the half-turn. Roof 6 m, ground floor ceiling 3.2 m.
ROOF_Y = 6.0
CEIL_Y = 3.2
PARAPET = 1.15
BX = 16.0
BZ0, BZ1 = 16.0, 34.0
box_h("Shell", -BX, BX, 0, ROOF_Y, BZ0, BZ1, "brick")
sub_h("Void", -BX + 1.6, BX - 1.6, 0.0, CEIL_Y, BZ0 + 1.6, BZ1 - 1.6)
# Doors 3.0 x 2.6 (nav agent radius 0.5, height 1.75). Court door off the gutter and the ramp.
sub_h("DoorCourt", 8.6, 11.6, 0.0, 2.6, BZ0 - 0.3, BZ0 + 1.9)
sub_h("DoorSpawn", -1.5, 1.5, 0.0, 2.6, BZ1 - 1.9, BZ1 + 0.3)
sub_h("DoorWest", -BX - 0.3, -BX + 1.9, 0.0, 2.6, 23.5, 26.5)
sub_h("DoorEast", BX - 1.9, BX + 0.3, 0.0, 2.6, 23.5, 26.5)
# A jog breaks the court-door to spawn-door line inside.
box_h("Jog", -5.0, 5.0, 0, CEIL_Y, 24.7, 25.3, "brick")
# Stairs: 6 m over 10 m (~31°). West climbs toward the spawn, east toward the court.
sub_h("StairWSlot", -10.45, -6.55, CEIL_Y - 0.15, ROOF_Y + 0.2, 21.2, 29.8)
sub_h("StairESlot", 6.55, 10.45, CEIL_Y - 0.15, ROOF_Y + 0.2, 20.2, 28.8)
ramp_z_h("StairW", -10.6, -6.4, 20.0, 30.0, ROOF_Y, "concrete")
ramp_z_h("StairE", 6.4, 10.6, 30.0, 20.0, ROOF_Y, "concrete")
box_h("StairWEdge", -10.6, -6.4, -0.06, 0.0, 19.85, 20.15, "hazard")
box_h("StairEEdge", 6.4, 10.6, -0.06, 0.0, 29.85, 30.15, "hazard")
box_h("RailWO", -10.85, -10.6, 0, CEIL_Y, 20.0, 28.6, "trim")
box_h("RailWI", -6.4, -6.15, 0, CEIL_Y, 20.0, 28.6, "trim")
box_h("RailEO", 10.6, 10.85, 0, CEIL_Y, 21.4, 30.0, "trim")
box_h("RailEI", 6.15, 6.4, 0, CEIL_Y, 21.4, 30.0, "trim")

# ---------------------------------------------------------------- court gutters and ramps
# Blue's court surf drops from its roof edge (z 16, 4.5 m) to the middle of the court (z -1, 0 m),
# its toe on x = GUTTER_X and its face open toward the middle (+X); Orange's is the half-turn. One
# face, ridden like any surf. A V of two faces does not work: in the crease Godot combines the two
# wall normals into a floor, and the rider just stands there (check_rooftops caught it).
# Its back is a vertical face up to 3.4 m above the toe: a wallrun in the court.
GUTTER_X = -4.0
GUTTER_HIGH = (BZ0 + 0.6, ROOF_Y - 1.0)  # (z, toe y): a 1 m drop in from the roof edge
GUTTER_LOW_Z = -1.0
for team, s in (("B", 1.0), ("O", -1.0)):
    b, o, dep = surf_line("CourtSurf_%s" % team,
                          (s * GUTTER_X, GUTTER_HIGH[1], s * GUTTER_HIGH[0]),
                          (s * GUTTER_X, 0.0, s * GUTTER_LOW_Z),
                          (s * 1.0, 0.0), poly=GUTTER_POLY, toe=GUTTER_TOE)
    strip_at("StripCourt_%s" % team, b, o, dep, 0.0, GUTTER_HIGH[1], GUTTER_TOE)
# Fill under each court surf, from its back to its toe: no crawlspace (and no eye line) under the
# face, and the back becomes one sloped block whose vertical side is the court wallrun.
fill_climb("FillCourt_B", GUTTER_X - GUTTER_TOE - 0.05, GUTTER_X - 0.15, GUTTER_LOW_Z, GUTTER_HIGH[0], GUTTER_HIGH[1])
fill_climb("FillCourt_O", -GUTTER_X + GUTTER_TOE + 0.05, -GUTTER_X + 0.15, -GUTTER_LOW_Z, -GUTTER_HIGH[0], GUTTER_HIGH[1])
# The drop-in from the roof edge, marked on the edge itself.
box_h("CourtSurfLip", GUTTER_X, GUTTER_X + 0.4, GUTTER_HIGH[1] - 0.2, GUTTER_HIGH[1], BZ0, BZ0 + 0.8, "hazard")
# Court ramp up to the roof, on the other side of the court door from the gutter: the other
# team's gutter exit runs straight up it. 4 m wide, 6 m over 11 m (~29°): bots walk it.
RAMP_X0, RAMP_X1 = 2.4, 6.4
ramp_z_h("CourtRamp", RAMP_X0, RAMP_X1, 5.0, BZ0, ROOF_Y, "concrete")
box_h("CourtRampEdge", RAMP_X0, RAMP_X1, -0.06, 0.0, 4.85, 5.15, "hazard")

# Parapets on the court edge with gaps: gutter mouth, ramp top, skybridge mouths.
def parapet_court(z0, z1, gaps):
    x = -BX
    parts = []
    for a, b in sorted(gaps):
        if a - x > 0.4:
            parts.append((x, a))
        x = b
    if BX - x > 0.4:
        parts.append((x, BX))
    for i, (a, b) in enumerate(parts):
        box_h("ParCourt%d" % i, a, b, ROOF_Y, ROOF_Y + PARAPET, z0, z1, "concrete")


GUTTER_GAP = (GUTTER_X - 0.6, GUTTER_X + GUTTER_TOE + 1.6)
parapet_court(BZ0, BZ0 + 0.5, [(-BX, -12.0), GUTTER_GAP, (RAMP_X0, RAMP_X1), (12.0, BX)])
# Spawn-side parapet: full height, so the roof does not look into the yard over it.
box_h("ParSpawn", -BX, BX, ROOF_Y, ROOF_Y + 2.4, BZ1 - 0.5, BZ1, "concrete")
# Side parapets, open where the launch deck (west) and the east roof step meet the roof.
box_h("ParWestA", -BX, -BX + 0.5, ROOF_Y, ROOF_Y + PARAPET, BZ0, 26.8, "concrete")
box_h("ParEast", BX - 0.5, BX, ROOF_Y, ROOF_Y + PARAPET, BZ0, BZ1, "concrete")
# Roof cover: two AC blocks (1.10) and a 2.6 m stair head that also breaks the roof-to-roof line.
box_h("AC1", -3.0, -0.4, ROOF_Y, ROOF_Y + 1.1, 19.0, 21.6, "ac")
box_h("AC2", 1.0, 3.6, ROOF_Y, ROOF_Y + 1.1, 27.0, 29.6, "ac")

# ---------------------------------------------------------------- skybridges
box_h("BridgeW", -BX, -12.0, ROOF_Y - 0.3, ROOF_Y, -BZ0, BZ0, "roof")
box_h("BridgeWLipA", -BX, -BX + 0.4, ROOF_Y, ROOF_Y + 0.45, -BZ0, BZ0, "concrete")
box_h("BridgeWLipB", -12.4, -12.0, ROOF_Y, ROOF_Y + 0.45, -BZ0, BZ0, "concrete")

# ---------------------------------------------------------------- grapple gantry
# Steel portal over the middle of the court at 11 m, posts in the flank mouths. It holds nothing:
# it is the anchor. High enough that no surf or bridge runs into it.
GANTRY_Y = 10.6
box("GantryBeam", -21.0, 21.0, GANTRY_Y, GANTRY_Y + 0.7, -0.5, 0.5, "steel")
box("GantryPostW", -21.0, -20.2, 0.0, GANTRY_Y + 0.7, -0.5, 0.5, "steel")
box("GantryPostE", 20.2, 21.0, 0.0, GANTRY_Y + 0.7, -0.5, 0.5, "steel")
box("GantryEdge", -21.0, 21.0, GANTRY_Y - 0.06, GANTRY_Y, -0.5, 0.5, "hazard")

# ---------------------------------------------------------------- flank surf and launch deck
# Blue's: the launch deck runs west off its roof at 6 m to the surf on the west wall; the surf's
# toe runs from the deck (z FLANK_HIGH_Z, 6 m) down to the floor at FLANK_LOW_Z in Orange's back
# lane. Orange's is the half-turn on the east wall.
FLANK_TOE_X = -HX + 0.05 + SURF_TOE  # the profile sits 5 cm into the wall
FLANK_HIGH_Z = 29.0
FLANK_LOW_Z = -19.0
DECK_Z0, DECK_Z1 = 26.8, 32.6
fb, fo, fdep = surf_line("SurfFlank_B", (FLANK_TOE_X, ROOF_Y, FLANK_HIGH_Z),
                         (FLANK_TOE_X, 0.0, FLANK_LOW_Z), (1.0, 0.0))
surf_line("SurfFlank_O", (-FLANK_TOE_X, ROOF_Y, -FLANK_HIGH_Z),
          (-FLANK_TOE_X, 0.0, -FLANK_LOW_Z), (-1.0, 0.0))
fill_climb("FillFlank_B", -HX + 0.05, FLANK_TOE_X - 0.15, FLANK_LOW_Z, FLANK_HIGH_Z, ROOF_Y)
fill_climb("FillFlank_O", HX - 0.05, -FLANK_TOE_X + 0.15, -FLANK_LOW_Z, -FLANK_HIGH_Z, ROOF_Y)
# Strips: one where the toe is halfway down, one at the foot.
mid = fdep * 0.5
strip_at("StripFlankMid_B", fb, fo, mid, ROOF_Y * 0.5, ROOF_Y * 0.5)
strip_at("StripFlankFoot_B", fb, fo, fdep, 0.0, ROOF_Y)
ob = ((-fb[0][0], fb[0][1], -fb[0][2]), (-fb[1][0], fb[1][1], -fb[1][2]), (-fb[2][0], fb[2][1], -fb[2][2]))
oo = (-fo[0], fo[1], -fo[2])
strip_at("StripFlankMid_O", ob, oo, mid, ROOF_Y * 0.5, ROOF_Y * 0.5)
strip_at("StripFlankFoot_O", ob, oo, fdep, 0.0, ROOF_Y)
# The deck: roof level from the block's west wall to the surf's toe, over the flank lane.
box_h("LaunchDeck", FLANK_TOE_X, -BX, ROOF_Y - 0.3, ROOF_Y, DECK_Z0, DECK_Z1, "roof")
box_h("LaunchDeckLip", FLANK_TOE_X + 0.6, -BX, ROOF_Y, ROOF_Y + 0.45, DECK_Z1 - 0.4, DECK_Z1, "concrete")
box_h("LaunchPostA", -26.0, -25.2, 0.0, ROOF_Y - 0.3, DECK_Z0 + 0.4, DECK_Z0 + 1.2, "concrete")
box_h("LaunchPostB", -26.0, -25.2, 0.0, ROOF_Y - 0.3, DECK_Z1 - 1.2, DECK_Z1 - 0.4, "concrete")
box_h("LaunchEdge", FLANK_TOE_X, FLANK_TOE_X + 0.3, ROOF_Y - 0.06, ROOF_Y, DECK_Z0, DECK_Z1, "hazard")
# The block wall behind the deck opens onto the roof.
sub_h("DeckNotch", -BX - 0.1, -BX + 0.6, ROOF_Y - 0.2, ROOF_Y + 0.3, DECK_Z0, DECK_Z1)

# ---------------------------------------------------------------- flanks: lanes, cover, wallrun walls
# box_h places the half-turn copy too, so each call below puts one piece on BOTH flanks (the west one
# at the coordinates given, the east one turned). check_rooftops measures every ground lane at eye
# height; these pieces are what keeps the longest under 35 m.
# A 14 m, 3.4 m, 3 m thick block down the middle of each flank: a wallrun on either face.
box_h("FlankWall", -25.0, -22.0, 0, 3.4, -7.0, 7.0, "concrete")
# Truck height (1.90) against the block walls beside the side doors, both ends of the flank.
box_h("LaneBlockN", -22.5, -16.0, 0, 1.9, 19.0, 22.0, "van")
box_h("LaneBlockS", -22.5, -16.0, 0, 1.9, -22.0, -19.0, "van")
box_h("LaneLowMid", -22.5, -16.0, 0, 1.9, -1.5, 1.5, "van")  # around the gantry post
# Truck height: a lane at eye height (1.6) needs 1.90 to break, 1.40 is body cover the eye sees over.
# Along the surf's toe, under the rider (who is on the face, metres up) and out of the run-out at
# the far end (the rider lands against the outer wall, x < -31, z -20..-27).
# Pieces overlap in x (toe blocks 27.5..31.6, up to the toe, flank blocks 24..28, the wall 22..25, the
# door and mid blocks 16..22.5): no seam a 1 m lane can run through. A ray that grazes
# one edge is caught by the next.
box_h("ToeLowA", -31.6, -27.5, 0, 1.9, 19.0, 22.0, "van")
box_h("ToeLowB", -31.6, -27.5, 0, 1.9, -6.0, -3.0, "van")
box_h("ToeLowC", -31.6, -27.5, 0, 1.9, -32.0, -29.0, "van")
box_h("FlankBlockN", -28.0, -24.0, 0, 1.9, 7.0, 15.2, "van")
box_h("FlankBlockS", -28.0, -24.0, 0, 1.9, -15.2, -7.0, "van")
# The yard exits: one block in each, so the exit is entered from the side.
box_h("ExitBlockW", -21.0, -17.5, 0, 1.9, 38.0, 41.0, "van")
box_h("ExitBlockE", 17.5, 21.0, 0, 1.9, 38.0, 41.0, "van")

# ---------------------------------------------------------------- court cover
# Big pieces only. The gutter exits (x ±4 from z 0 to the far ramp) stay clear.
box_h("CourtBlock", -13.0, -10.0, 0, 1.9, 2.0, 5.0, "van")
box_h("CourtMid", 7.5, 12.0, 0, 1.9, -9.0, -7.6, "concrete")  # in front of the court doors: the door-to-door line

# ---------------------------------------------------------------- spawn yards
SPAWN_WALL_Z = 37.0
box_h("SpawnWall", -12.0, 12.0, 0, 3.2, SPAWN_WALL_Z, SPAWN_WALL_Z + 0.7, "team_blue", "team_orange")
box_h("BaffleW", -HX, -20.0, 0, 3.2, SPAWN_WALL_Z, SPAWN_WALL_Z + 0.7, "concrete")
box_h("BaffleE", 20.0, HX, 0, 3.2, SPAWN_WALL_Z, SPAWN_WALL_Z + 0.7, "concrete")
box_h("Truck", -1.6, 1.6, 0, 1.9, 44.0, 47.6, "van")
# The street between the block's back and the spawn wall runs the full width: two blocks break it
# and leave the spawn door (|x| < 1.5) and both yard exits open.
box_h("BackBlockW", -9.0, -6.0, 0, 1.9, 34.6, 36.4, "van")
box_h("BackBlockE", 6.0, 9.0, 0, 1.9, 34.6, 36.4, "van")
# Two containers (2.60) in each yard: the yard is 70 m wide, and a flanker who gets in should not see
# all of it. Everyone spawns between them (|x| < 14). The corners behind the baffles are closed off
# by the containers and the exit blocks, so nobody spawns there (maps.gd).
box_h("YardBoxW", -18.0, -14.0, 0, 2.6, 40.0, 49.6, "van")
box_h("YardBoxE", 14.0, 18.0, 0, 2.6, 40.0, 49.6, "van")

# ---------------------------------------------------------------- lights (omni: no shadows)
WARM = (1.0, 0.86, 0.70)
COOL = (0.78, 0.86, 1.0)
light("SouthInside", (0.0, 2.4, 25.0), WARM, 0.8, 14.0)
light("NorthInside", (0.0, 2.4, -25.0), WARM, 0.8, 14.0)
light("CourtA", (-8.0, 5.0, 6.0), COOL, 0.45, 16.0)
light("CourtB", (8.0, 5.0, -6.0), COOL, 0.45, 16.0)
light("GantryLight", (0.0, 9.6, 0.0), COOL, 0.4, 14.0)


def main():
    mats = []
    for n in nodes:
        if n[4] not in mats:
            mats.append(n[4])
    out = ["[gd_scene load_steps=%d format=3]" % (len(mats) + 1 + speed_strip.LOAD_STEPS), ""]
    out += [
        '[sub_resource type="Environment" id="Env_rooftops"]',
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
    out += speed_strip.resources()
    for m in mats:
        (r, g, b), rough = MATS[m]
        out += ['[sub_resource type="StandardMaterial3D" id="Mat_%s"]' % m,
                "albedo_color = Color(%s, %s, %s, 1)" % (fmt(r), fmt(g), fmt(b)),
                "roughness = %s" % fmt(rough), ""]
    out += ['[node name="Rooftops" type="Node3D"]', ""]
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env_rooftops")', ""]
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
