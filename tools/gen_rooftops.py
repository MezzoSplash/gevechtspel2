#!/usr/bin/env python3
"""Generates scenes/maps/rooftops.tscn: "Rooftops", a flat-roof housing court.

Same pipeline as Foundry: CSG under one Arena combiner (collision layer 1), so main.gd bakes the
bot navmesh from it. Re-run after editing:  python3 tools/gen_rooftops.py

Mirrored by a half-turn (Blue spawns at +Z, Orange at -Z). Flat colours, no PBR.

Layout (metres, Y up, Blue at +Z). Rotated 180°, not mirrored, so surf bases stay det +1:
  - Court in the middle (about 30 x 26) with chest-high cover. A small surf triangle across the
    court (east-west) is the crossing. Roof-to-roof over it is the knife lane.
  - South and north blocks: roof at 6.0 m, room ceiling at 3.2 m so the ground floor stays CQB.
    Doors on four sides. Stairs sit inboard of the flank doors (the door needs a clear corridor;
    a ramp against that wall seals it). Two ~28° stairs per block, low end on the floor.
  - Both flanks: a 60° surf along the outer wall, pitched ~5° so the toe climbs ~4.15 m onto a
    deck. A separate ~14° walk-ramp joins that deck to the 6 m roof, clear of the side door.
    40° kickers (world angle) at both ends of the surf. West runs low-north to high-south; east
    runs low-south to high-north. Fill under the toe stops short of the face. The outer wall is
    taller than the ridge and the face opens inward, so the ramp stays in the map.
  - Walkway beside each surf stays open. Eye-height sightline down it is about 42 m, crates beside
    it so the lane is not one sniper tunnel. Baffles keep the spawn yards out of that lane.
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

# ~57° face (still inside 55–65). Wider than the Townhouses section so a surf line
# can drift toward the toe for the whole climb and still be on the face at the deck.
# Buried 0.1 m into the wall and the floor.
SURF_POLY = (-0.1, -0.1, 3.30, -0.1, -0.1, 5.15)
SURF_TOE = 3.30  # local X of the toe

nodes = []  # (name, type, transform, extra_lines, mat)
lights = []


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


def box_m(name, x0, x1, y0, y1, z0, z1, mat, mat_o=None):
    """Blue-side box (positive Z) plus the Orange mirror."""
    box(name + "_B", x0, x1, y0, y1, z0, z1, mat)
    box(name + "_O", x0, x1, y0, y1, -z1, -z0, mat_o or mat)


def sub(name, x0, x1, y0, y1, z0, z1):
    """Subtract from whatever was unioned before this node. Order in the file matters."""
    box(name, x0, x1, y0, y1, z0, z1, "concrete", op=2)


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


def light(name, pos, col, energy, rng):
    lights.append((name, pos, col, energy, rng))


def _kick_basis(deg, sign):
    """Tilt around local X. sign +1 cuts the origin end, -1 cuts the far end."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a) * sign
    return ((1, 0, 0), (0, c, s), (0, -s, c))


def surf(name, origin, basis, depth, kicks, mat="surf", kick_start=40.0, kick_end=40.0):
    """60° wall-surf. Extrusion runs along local -Z for `depth` metres (Townhouses).

    kicks: "both", "start" (the origin end), "end" (the far end), or "none".
    Bevels are child subtracts, same 40° cut as Townhouses, so a sprint meets a slope
    instead of a vertical face.
    """
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
    """Right-handed pitch around X. Positive beta lowers the far end (local -Z)."""
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


# Yaw 180, det +1. Local +X becomes world -X, local -Z becomes world +Z.
YAW180 = ((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0))


# ---------------------------------------------------------------- shell
# Inner play about 56 x 80. Walls are 9.6 m: the surf ridge stays under them.
WALL_H = 9.6
box("Floor", -29.2, 29.2, -1.0, 0.0, -41.2, 41.2, "floor")
box("WallWest", -29.2, -28.4, 0, WALL_H, -41.2, 41.2, "outer")
box("WallEast", 28.4, 29.2, 0, WALL_H, -41.2, 41.2, "outer")
box("WallSouth", -29.2, 29.2, 0, WALL_H, 40.4, 41.2, "team_blue")
box("WallNorth", -29.2, 29.2, 0, WALL_H, -41.2, -40.4, "team_orange")

# ---------------------------------------------------------------- roofs. Ground floor is carved out below.
# South block x -15.2..15.2, z 13..28. North is the mirror, built explicitly so stairs can differ.
# Roof is 6 m (the drop). The room stops at 3.2 m so the ground floor stays a CQB box, not a hall.
ROOF_Y = 6.0
CEIL_Y = 3.2
box("SouthShell", -15.2, 15.2, 0, ROOF_Y, 13.0, 28.2, "brick")
box("NorthShell", -15.2, 15.2, 0, ROOF_Y, -28.2, -13.0, "brick")
# Interior void. Subtract starts at y=0 so the floor slab is not nicked.
sub("SouthVoid", -13.6, 13.6, 0.0, CEIL_Y, 14.6, 26.6)
sub("NorthVoid", -13.6, 13.6, 0.0, CEIL_Y, -26.6, -14.6)
# Doors: 3.0 m wide, 2.6 m tall, so the nav agent (radius 0.5, height 1.75) fits.
# South block doors: court (north), spawn (south), both flanks.
sub("SouthDoorCourt", -1.6, 1.6, 0.0, 2.6, 12.7, 14.7)
sub("SouthDoorSpawn", -1.6, 1.6, 0.0, 2.6, 26.5, 28.5)
sub("SouthDoorWest", -15.5, -13.5, 0.0, 2.6, 18.6, 21.6)
sub("SouthDoorEast", 13.5, 15.5, 0.0, 2.6, 18.6, 21.6)
sub("NorthDoorCourt", -1.6, 1.6, 0.0, 2.6, -14.7, -12.7)
sub("NorthDoorSpawn", -1.6, 1.6, 0.0, 2.6, -28.5, -26.5)
sub("NorthDoorWest", -15.5, -13.5, 0.0, 2.6, -21.6, -18.6)
sub("NorthDoorEast", 13.5, 15.5, 0.0, 2.6, -21.6, -18.6)
# Jog breaks the court-door to spawn-door line. It stops at |x|=4.6 so it does not cross a flank door.
box("SouthJog", -4.6, 4.6, 0, CEIL_Y, 20.15, 20.7, "brick")
box("NorthJog", -4.6, 4.6, 0, CEIL_Y, -20.7, -20.15, "brick")
# Crates inside, hip height. Clear of both stairs (|x| 5.8..9.6) and the jog.
box("SouthCrateA", -4.2, -2.2, 0, 1.1, 16.2, 18.2, "cover")
box("SouthCrateB", 2.2, 4.2, 0, 1.1, 22.6, 24.6, "cover")
box("NorthCrateA", 2.2, 4.2, 0, 1.1, -18.2, -16.2, "cover")
box("NorthCrateB", -4.2, -2.2, 0, 1.1, -24.6, -22.6, "cover")

# Stairs: 6 m over 10 m is ~31°, under the 45° walk limit and the 46° nav limit.
# Inboard of the flank doors. A ramp against that jamb left a 0.6 m gap; the capsule is 0.8 m.
# The low end sits 1.6 m inside the room so you can stand on the tread (wall inner face is
# 0.4 m of capsule away from a foot that starts on the wall).
# Slot is the shaft through the roof mass. The ramp is wider than the slot and runs past the
# high end, so the opening has no lip and no gap beside the tread.
# Opens early: the capsule is 1.8 m, so the head meets a 3.2 m ceiling when the tread is only
# at 1.4 m. From there the shaft is open, or the climb wedges.
sub("SouthStairWSlot", -9.45, -5.95, CEIL_Y - 0.15, ROOF_Y + 0.2, 17.4, 25.9)
sub("SouthStairESlot", 5.95, 9.45, CEIL_Y - 0.15, ROOF_Y + 0.2, 15.3, 23.6)
sub("NorthStairESlot", 5.95, 9.45, CEIL_Y - 0.15, ROOF_Y + 0.2, -25.9, -17.4)
sub("NorthStairWSlot", -9.45, -5.95, CEIL_Y - 0.15, ROOF_Y + 0.2, -23.6, -15.3)
# South-west climbs toward the spawn (+Z). South-east climbs toward the court. North is the half-turn.
ramp_z("SouthStairW", -9.6, -5.8, 16.2, 26.2, ROOF_Y, "concrete")
ramp_z("SouthStairE", 5.8, 9.6, 25.0, 15.0, ROOF_Y, "concrete")
ramp_z("NorthStairE", 5.8, 9.6, -16.2, -26.2, ROOF_Y, "concrete")
ramp_z("NorthStairW", -9.6, -5.8, -25.0, -15.0, ROOF_Y, "concrete")
# Yellow only on the ramp edge, not as a stripe across the fight.
# Flush with the floor. A proud curb stops the capsule; the yellow is only the edge mark.
box("SouthStairWEdge", -9.6, -5.8, -0.06, 0.0, 16.05, 16.35, "hazard")
box("SouthStairEEdge", 5.8, 9.6, -0.06, 0.0, 24.85, 25.15, "hazard")
box("NorthStairEEdge", 5.8, 9.6, -0.06, 0.0, -16.35, -16.05, "hazard")
box("NorthStairWEdge", -9.6, -5.8, -0.06, 0.0, -25.15, -24.85, "hazard")
# Rails in the room, both sides, so the tread is not a drop. They stop at the ceiling.
box("SouthRailWO", -9.85, -9.6, 0, CEIL_Y, 16.2, 24.8, "trim")
box("SouthRailWI", -5.8, -5.55, 0, CEIL_Y, 16.2, 24.8, "trim")
box("SouthRailEO", 9.6, 9.85, 0, CEIL_Y, 15.6, 25.0, "trim")
box("SouthRailEI", 5.55, 5.8, 0, CEIL_Y, 15.6, 25.0, "trim")
box("NorthRailEO", 9.6, 9.85, 0, CEIL_Y, -24.8, -16.2, "trim")
box("NorthRailEI", 5.55, 5.8, 0, CEIL_Y, -24.8, -16.2, "trim")
box("NorthRailWO", -9.85, -9.6, 0, CEIL_Y, -25.0, -15.6, "trim")
box("NorthRailWI", -5.8, -5.55, 0, CEIL_Y, -25.0, -15.6, "trim")

# Parapet 1.15 m on the court edge, with three gaps wide enough to walk off (the drop).
def parapet_court(prefix, z0, z1, gaps):
    x = -15.2
    for i, (a, b) in enumerate(gaps):
        if a - x > 0.4:
            box("%sPar%d" % (prefix, i), x, a, ROOF_Y, ROOF_Y + 1.15, z0, z1, "concrete")
        x = b
    if 15.2 - x > 0.4:
        box("%sParEnd" % prefix, x, 15.2, ROOF_Y, ROOF_Y + 1.15, z0, z1, "concrete")


# Gaps at -8..-4.6, -1.5..1.5, 4.6..8. Landing in the court under them is kept clear.
parapet_court("South", 13.0, 13.5, [(-8.0, -4.6), (-1.5, 1.5), (4.6, 8.0)])
parapet_court("North", -13.5, -13.0, [(-8.0, -4.6), (-1.5, 1.5), (4.6, 8.0)])
# Side parapets. The gap on the south-west (and the north-east mirror) is where the deck step
# meets the roof. Stairs come up through the roof, so the other edges stay closed.
box("SouthParSpawnL", -15.2, -13.6, ROOF_Y, ROOF_Y + 1.15, 27.7, 28.2, "concrete")
box("SouthParSpawnR", 13.6, 15.2, ROOF_Y, ROOF_Y + 1.15, 27.7, 28.2, "concrete")
box("SouthParWestA", -15.2, -14.7, ROOF_Y, ROOF_Y + 1.15, 13.0, 16.2, "concrete")
box("SouthParWestB", -15.2, -14.7, ROOF_Y, ROOF_Y + 1.15, 18.6, 28.2, "concrete")
box("SouthParEast", 14.7, 15.2, ROOF_Y, ROOF_Y + 1.15, 13.0, 28.2, "concrete")
box("NorthParSpawnL", -15.2, -13.6, ROOF_Y, ROOF_Y + 1.15, -28.2, -27.7, "concrete")
box("NorthParSpawnR", 13.6, 15.2, ROOF_Y, ROOF_Y + 1.15, -28.2, -27.7, "concrete")
box("NorthParWest", -15.2, -14.7, ROOF_Y, ROOF_Y + 1.15, -28.2, -13.0, "concrete")
box("NorthParEastA", 14.7, 15.2, ROOF_Y, ROOF_Y + 1.15, -16.2, -13.0, "concrete")
box("NorthParEastB", 14.7, 15.2, ROOF_Y, ROOF_Y + 1.15, -28.2, -18.8, "concrete")

# AC boxes on the roof: head-glitch cover for the mid-range roof fight. Not on the drop gaps or the shafts.
box("SouthAC1", -4.0, -1.6, ROOF_Y, ROOF_Y + 1.1, 17.6, 20.2, "ac")
box("SouthAC2", 1.6, 4.2, ROOF_Y, ROOF_Y + 1.1, 21.4, 24.0, "ac")
box("NorthAC1", 1.6, 4.0, ROOF_Y, ROOF_Y + 1.1, -20.2, -17.6, "ac")
box("NorthAC2", -4.2, -1.6, ROOF_Y, ROOF_Y + 1.1, -24.0, -21.4, "ac")

# Notch the wall top where the deck step lands, then union the step. Subtract before the step
# or the step is cut too. Stays above the room ceiling, so it is not a hole into the floor.
sub("SouthStepNotch", -15.55, -13.45, ROOF_Y - 0.5, ROOF_Y + 0.25, 16.15, 18.85)
sub("NorthStepNotch", 13.45, 15.55, ROOF_Y - 0.5, ROOF_Y + 0.25, -18.85, -16.15)

# ---------------------------------------------------------------- surf landings
# The deck is the flat the flank surf runs onto. It stays at 4 m: the surf climb is tuned for
# that, and a sprint cannot pay for a 6 m rise. A ~14° ramp walks the rest of the way up.
# The ramp and the step stay clear of the flank door (door z 18.6..21.6, step ends at 18.6).
DECK_Y = 4.0
box("WestDeck", -26.6, -16.2, DECK_Y - 0.15, DECK_Y, 21.2, 27.0, "roof")
box("EastDeck", 16.2, 26.6, DECK_Y - 0.15, DECK_Y, -27.0, -21.2, "roof")
ramp_z("WestRoofRamp", -20.8, -16.4, 25.2, 17.2, ROOF_Y - DECK_Y, "concrete", y0=DECK_Y)
ramp_z("EastRoofRamp", 16.4, 20.8, -25.2, -17.2, ROOF_Y - DECK_Y, "concrete", y0=DECK_Y)
box("WestRoofStep", -20.8, -13.3, ROOF_Y - 0.32, ROOF_Y, 16.4, 18.6, "roof")
box("EastRoofStep", 13.3, 20.8, ROOF_Y - 0.32, ROOF_Y, -18.6, -16.4, "roof")
box("WestPostA", -22.6, -21.6, 0, DECK_Y - 0.15, 22.6, 23.6, "concrete")
box("WestPostB", -18.6, -17.6, 0, DECK_Y - 0.15, 24.4, 25.4, "concrete")
box("EastPostA", 21.6, 22.6, 0, DECK_Y - 0.15, -23.6, -22.6, "concrete")
box("EastPostB", 17.6, 18.6, 0, DECK_Y - 0.15, -25.4, -24.4, "concrete")

# ---------------------------------------------------------------- surfs
# 60° face, pitched so the toe climbs CLIMB_RISE over the extrusion.
# The basis is a real rotation (det +1). A mirror makes CSG drop the collision.
# Origin sits at the HIGH end. Extrusion (local -Z) runs toward the LOW end, and rx()
# drops that end onto the floor. West opens toward +X; east is yaw 180 (opens toward -X).
CLIMB_DEPTH = 46.0
CLIMB_RISE = 4.15
CLIMB_PITCH = math.asin(CLIMB_RISE / CLIMB_DEPTH)
# High-end toe height is CLIMB_RISE; the polygon base is 0.1 below local Y=0.
SURF_ORIGIN_Y = CLIMB_RISE + 0.1 * math.cos(CLIMB_PITCH)

WEST_BASIS = rx(CLIMB_PITCH)  # +X into the map, far end (north) lower
# East: yaw 180 first so +X points into the map, then the same pitch (far end south, lower).
# mul(yaw, rx) would pitch in local space before the yaw and send the drop the wrong way.
# Pitch in world: rx then yaw, i.e. mul(yaw, rx) applies rx first. Check with the print below.
EAST_BASIS = mul_basis(YAW180, rx(CLIMB_PITCH))

# West high end on the south-west deck (deck z 14.5..26.5). Low end stays south of the orange baffle.
# kick_start is the high (origin) end, kick_end is the low entry. Tuned so both
# measure about 40° in world after the 5° pitch (a local 40° lands near 45° / 35°).
surf("SurfWest", (-28.15, SURF_ORIGIN_Y, 22.5), WEST_BASIS, CLIMB_DEPTH, "both",
     kick_start=46.0, kick_end=34.0)
surf("SurfEast", (28.15, SURF_ORIGIN_Y, -22.5), EAST_BASIS, CLIMB_DEPTH, "both",
     kick_start=46.0, kick_end=34.0)


def _toe_world(basis, origin, along):
    """World position of the toe (local x = SURF_TOE, y = -0.1) `along` metres down local -Z."""
    local = (SURF_TOE, -0.1, -along)
    return tuple(origin[i] + basis[0][i] * local[0] + basis[1][i] * local[1] + basis[2][i] * local[2]
                 for i in range(3))


# Fill under the rising toe, from the wall out to the toe, so the flank has no crawlspace.
# The fill's top is the toe line (a few centimetres under it). It must not cover the 60° face.
def fill_climb(name, x_wall, x_toe, z_low, z_high, h):
    length = abs(z_high - z_low)
    # Proper rotation, det +1. Local +X runs low → high along Z. Local -Z extrudes toward the toe.
    if z_high > z_low:
        # West: wall is -X, toe is +X of the wall. Extrude toward +X.
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


# Toe x is about 2.66 in from the surf node. Stop the fill 0.15 short of the toe so the
# 60° face is the surface you hit, and the fill only plugs the void under it.
fill_climb("FillWest", -28.55, -25.05, 22.5 - CLIMB_DEPTH * math.cos(CLIMB_PITCH), 22.5, CLIMB_RISE)
fill_climb("FillEast", 28.55, 25.05, -22.5 + CLIMB_DEPTH * math.cos(CLIMB_PITCH), -22.5, CLIMB_RISE)

# ---------------------------------------------------------------- cross surf
# Short copy of the flank wedge, turned east-west, so you can surf from one side to the other.
# Same 60° triangle, 40° kickers, no pitch (either direction holds). Origin is the east end;
# local -Z runs west. Face opens toward -Z. Ends 17 m inside the outer wall.
# local +X → world -Z, local +Z → world +X. det +1.
CROSS_BASIS = ((0.0, 0.0, -1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0))
CROSS_DEPTH = 22.0
surf("SurfCross", (CROSS_DEPTH / 2.0, 0.1, 1.6), CROSS_BASIS, CROSS_DEPTH, "both",
     kick_start=40.0, kick_end=40.0)
box("CrossEdgeE", 10.7, 11.15, -0.06, 0.0, -1.4, 1.5, "hazard")
box("CrossEdgeW", -11.15, -10.7, -0.06, 0.0, -1.4, 1.5, "hazard")

# Downhill toes of the flank surfs, and the far end of the flat cross.
strips = []


def _end_strip(name, basis, origin, along, floor_y, drop=0.0):
    """Catch volume at the downhill toe, as tall as this surf."""
    toe_pos = _toe_world(basis, origin, along)
    strips.append(speed_strip.make(
        name, toe_pos, speed_strip.forward_xz(basis, 1.0), floor_y, height=drop))


_end_strip("StripSurfWest", WEST_BASIS, (-28.15, SURF_ORIGIN_Y, 22.5), CLIMB_DEPTH, 0.0, CLIMB_RISE)
_end_strip("StripSurfEast", EAST_BASIS, (28.15, SURF_ORIGIN_Y, -22.5), CLIMB_DEPTH, 0.0, CLIMB_RISE)
_end_strip("StripSurfCross", CROSS_BASIS, (CROSS_DEPTH / 2.0, 0.1, 1.6), CROSS_DEPTH, 0.0)

# ---------------------------------------------------------------- court (mid-range)
# Chest cover. The three drop-landing strips (x -8..-4.6, -1.5..1.5, 4.6..8 at |z| 9..13) stay empty.
# The centre wall moved off the surf triangle (|z| < 1.9, |x| < 10).
box("CourtWall_B", -3.6, 3.6, 0, 1.1, 3.55, 4.2, "concrete")
box("CourtWall_O", -3.6, 3.6, 0, 1.1, -4.2, -3.55, "concrete")
box("CourtCrateA", -10.5, -8.6, 0, 1.1, 4.2, 6.2, "cover")
box("CourtCrateB", 8.4, 10.4, 0, 1.1, -6.4, -4.2, "cover")
box("CourtCrateC", -11.2, -9.4, 0, 1.1, -5.2, -3.2, "cover")
box("CourtCrateD", 5.6, 7.6, 0, 2.2, 3.4, 5.4, "cover")  # double, breaks a head-glitch
box("VanBody", -2.4, 2.6, 0.35, 1.4, -7.6, -4.6, "van")
box("VanCab", 2.6, 3.6, 0.35, 1.35, -7.3, -4.9, "steel")
# Planters off the triangle. Still a half-turn pair.
box("PlantA", -8.4, -7.0, 0, 1.1, 3.2, 6.0, "brick")
box("PlantB", 7.0, 8.4, 0, 1.1, -6.0, -3.2, "brick")

# ---------------------------------------------------------------- flanks: walkway cover, not in the 42 m line (that line is x=±21.5)
# West lane line x=-21.5 from z=-21 to 21 must stay clear. Crates sit at x=-18.
box("LaneCrateW1", -19.3, -17.4, 0, 1.1, -8.2, -6.2, "cover")
box("LaneCrateW2", -19.0, -17.2, 0, 1.1, 6.4, 8.6, "cover")
box("LaneCrateE1", 17.2, 19.0, 0, 1.1, -7.2, -5.0, "cover")
box("LaneCrateE2", 17.4, 19.3, 0, 1.1, 5.2, 7.4, "cover")
# Baffles in front of the flank spawns, with the gap on the building side so the lane is entered
# from the side, not seen from the spawn point.
box("BaffleW_B", -28.2, -18.6, 0, 3.2, 27.3, 28.0, "concrete")
box("BaffleW_O", -28.2, -18.6, 0, 3.2, -28.0, -27.3, "concrete")
box("BaffleE_B", 18.6, 28.2, 0, 3.2, 27.3, 28.0, "concrete")
box("BaffleE_O", 18.6, 28.2, 0, 3.2, -28.0, -27.3, "concrete")
# Spawn walls: team colour, only here. Flanks around them ( |x| > 12 ) are the way out.
box("SpawnWall_B", -12.0, 12.0, 0, 3.2, 30.3, 31.0, "team_blue")
box("SpawnWall_O", -12.0, 12.0, 0, 3.2, -31.0, -30.3, "team_orange")
# A truck behind each spawn wall, between the centre spawns, so two neighbours do not share a line.
box("Truck_B", -1.6, 1.6, 0, 1.9, 33.2, 36.4, "van")
box("Truck_O", -1.6, 1.6, 0, 1.9, -36.4, -33.2, "van")
box("SpawnCrateW_B", -22.4, -20.4, 0, 1.1, 33.6, 35.4, "cover")
box("SpawnCrateE_B", 20.4, 22.4, 0, 1.1, 34.2, 36.0, "cover")
box("SpawnCrateW_O", -22.4, -20.4, 0, 1.1, -35.4, -33.6, "cover")
box("SpawnCrateE_O", 20.4, 22.4, 0, 1.1, -36.0, -34.2, "cover")

# ---------------------------------------------------------------- lights (omni: no shadows)
WARM = (1.0, 0.86, 0.70)
COOL = (0.78, 0.86, 1.0)
light("SouthInside", (0.0, 2.4, 20.5), WARM, 0.8, 12.0)
light("NorthInside", (0.0, 2.4, -20.5), WARM, 0.8, 12.0)
light("CourtA", (-6.0, 4.5, 6.0), COOL, 0.45, 14.0)
light("CourtB", (6.0, 4.5, -6.0), COOL, 0.45, 14.0)
light("WestDeckLight", (-23.5, 7.8, 22.0), WARM, 0.45, 11.0)
light("EastDeckLight", (23.5, 7.8, -22.0), WARM, 0.45, 11.0)
light("CrossLight", (0.0, 6.2, 0.0), COOL, 0.35, 12.0)


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
    stair_deg = math.degrees(math.atan(ROOF_Y / 10.0))
    print("wrote %s (%d csg nodes, %d strips, climb pitch %.2f deg, stair %.1f deg, roof %.1f)" % (
        os.path.normpath(OUT), len(nodes), len(strips), math.degrees(CLIMB_PITCH), stair_deg, ROOF_Y))
    for s in strips:
        c = s["center"]
        print("  strip %-16s center=(%.1f, %.1f, %.1f) ramp=%.2f" % (
            s["name"], c[0], c[1], c[2], s["ramp_h"]))
    print("  cross det=%.3f" % basis_det(CROSS_BASIS))
    for label, basis, origin in (
        ("west", WEST_BASIS, (-28.15, SURF_ORIGIN_Y, 22.5)),
        ("east", EAST_BASIS, (28.15, SURF_ORIGIN_Y, -22.5)),
    ):
        lo = _toe_world(basis, origin, CLIMB_DEPTH)
        hi = _toe_world(basis, origin, 0.0)
        print("  %s det=%.3f high toe=%s low toe=%s" % (
            label, basis_det(basis),
            tuple(round(v, 2) for v in hi), tuple(round(v, 2) for v in lo)))


if __name__ == "__main__":
    main()
