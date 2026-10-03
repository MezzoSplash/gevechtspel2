#!/usr/bin/env python3
"""Generates scenes/maps/foundry.tscn: "Foundry", a compact industrial yard for 5v5 and FFA.

Mirrored north/south (Blue spawns at +Z, Orange at -Z, like Townhouses). Every piece is a CSGBox3D
(or one CSGCylinder3D) under one CSGCombiner3D "Arena" with collision, so main.gd bakes the bot
navmesh from it the same way. Re-run after editing:  python3 tools/gen_foundry.py

Layout (top view, Blue half; Orange is the mirror):
  - Hall (x -11..11, z -10..10): roofed warehouse with a skylight, big doors north/south,
    two doors east, a west mezzanine (3 m) with windows onto the container yard, presses,
    a conveyor and a 5.2 m wide crate block that kills the door-to-door sightline.
  - West yard: container "hill" in the middle (ramps from both sides, roof 2.6 m),
    a container against the hall wall, a double stack and loose crates. Staggered so no lane
    runs spawn to spawn.
  - East: alley along the hall with offset gates and a pipe stack (breaks the long sniper line),
    two sheds (doors on three sides, small rooms) and a courtyard around a water tank.
  - Spawn yards: loading dock (1.2 m, ramps at both ends), a 3 m spawn wall, a parked truck.
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "maps", "foundry.tscn")

MATS = {
    "floor": ((0.25, 0.25, 0.24), 0.92),
    "concrete": ((0.36, 0.36, 0.35), 0.88),
    "outer": ((0.30, 0.31, 0.33), 0.86),
    "hall": ((0.46, 0.30, 0.20), 0.84),       # rust corrugated
    "hall_trim": ((0.20, 0.21, 0.22), 0.88),
    "steel": ((0.30, 0.32, 0.35), 0.6),
    "hazard": ((0.78, 0.62, 0.14), 0.75),
    "crate": ((0.50, 0.40, 0.28), 0.82),
    "c_red": ((0.56, 0.20, 0.15), 0.78),
    "c_blue": ((0.19, 0.32, 0.52), 0.78),
    "c_green": ((0.20, 0.40, 0.27), 0.78),
    "c_yellow": ((0.70, 0.55, 0.16), 0.78),
    "shed": ((0.40, 0.42, 0.40), 0.85),
    "team_blue": ((0.27, 0.46, 0.62), 0.82),
    "team_orange": ((0.70, 0.44, 0.18), 0.82),
    "tank": ((0.55, 0.57, 0.58), 0.5),
    "truck": ((0.22, 0.30, 0.36), 0.7),
    "cab": ((0.62, 0.62, 0.60), 0.7),
}

nodes = []
lights = []


def fmt(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def xform(basis_cols, origin):
    (X, Y, Z) = basis_cols
    # tscn Transform3D is row-major: x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z, origin
    vals = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2]] + list(origin)
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in vals)


IDENT = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


def box(name, x0, x1, y0, y1, z0, z1, mat):
    """Axis-aligned box from min/max corners."""
    c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    s = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
    nodes.append((name, "CSGBox3D", xform(IDENT, c), "size = Vector3(%s, %s, %s)" % tuple(fmt(v) for v in s), mat))


def box_m(name, x0, x1, y0, y1, z0, z1, mat, mat_o=None):
    """Blue-side box plus its Orange mirror (z → -z)."""
    box(name + "_B", x0, x1, y0, y1, z0, z1, mat)
    box(name + "_O", x0, x1, y0, y1, -z1, -z0, mat_o or mat)


def ramp_z(name, x0, x1, z_low, z_high, h, mat, t=0.3):
    """Ramp along Z: ground at z_low, top surface at height h at z_high."""
    dz = z_high - z_low
    length = math.hypot(dz, h)
    Z = (0.0, h / length, dz / length)            # local +Z runs up the slope
    Y = (0.0, abs(dz) / length, -h / length * (1 if dz > 0 else -1))
    if Y[1] < 0:
        Y = tuple(-v for v in Y)
    X = (Y[1] * Z[2] - Y[2] * Z[1], Y[2] * Z[0] - Y[0] * Z[2], Y[0] * Z[1] - Y[1] * Z[0])
    mid = ((x0 + x1) / 2, h / 2, (z_low + z_high) / 2)
    c = tuple(mid[i] - Y[i] * t / 2 for i in range(3))
    nodes.append((name, "CSGBox3D", xform((X, Y, Z), c),
                  "size = Vector3(%s, %s, %s)" % (fmt(abs(x1 - x0)), fmt(t), fmt(length)), mat))


def ramp_x(name, z0, z1, x_low, x_high, h, mat, t=0.3):
    """Ramp along X: ground at x_low, top surface at height h at x_high."""
    dx = x_high - x_low
    length = math.hypot(dx, h)
    X = (dx / length, h / length, 0.0)            # local +X runs up the slope
    Y = (-h / length * (1 if dx > 0 else -1), abs(dx) / length, 0.0)
    Z = (X[1] * Y[2] - X[2] * Y[1], X[2] * Y[0] - X[0] * Y[2], X[0] * Y[1] - X[1] * Y[0])
    mid = ((x_low + x_high) / 2, h / 2, (z0 + z1) / 2)
    c = tuple(mid[i] - Y[i] * t / 2 for i in range(3))
    nodes.append((name, "CSGBox3D", xform((X, Y, Z), c),
                  "size = Vector3(%s, %s, %s)" % (fmt(length), fmt(t), fmt(abs(z1 - z0))), mat))


def ramp_z_m(name, x0, x1, z_low, z_high, h, mat):
    ramp_z(name + "_B", x0, x1, z_low, z_high, h, mat)
    ramp_z(name + "_O", x0, x1, -z_low, -z_high, h, mat)


def ramp_x_m(name, z0, z1, x_low, x_high, h, mat):
    ramp_x(name + "_B", z0, z1, x_low, x_high, h, mat)
    ramp_x(name + "_O", -z1, -z0, x_low, x_high, h, mat)


def light(name, pos, col, energy, rng):
    lights.append((name, pos, col, energy, rng))


def light_m(name, pos, col, energy, rng):
    light(name + "_B", pos, col, energy, rng)
    light(name + "_O", (pos[0], pos[1], -pos[2]), col, energy, rng)


# ---------------------------------------------------------------- shell
H = 8.0
box("Floor", -26.25, 26.25, -1.0, 0.0, -34.75, 34.75, "floor")
box("WallWest", -26.25, -25.75, 0, H, -34.75, 34.75, "outer")
box("WallEast", 25.75, 26.25, 0, H, -34.75, 34.75, "outer")
box("WallSouth", -26.25, 26.25, 0, H, 34.25, 34.75, "team_blue")
box("WallNorth", -26.25, 26.25, 0, H, -34.75, -34.25, "team_orange")

# ---------------------------------------------------------------- hall
HH = 7.0
# south/north walls with a 5 m door (x -2.5..2.5, 4.5 m tall)
box_m("HallS_W", -11.25, -2.5, 0, HH, 9.75, 10.25, "hall")
box_m("HallS_E", 2.5, 11.25, 0, HH, 9.75, 10.25, "hall")
box_m("HallS_Lintel", -2.5, 2.5, 4.5, HH, 9.75, 10.25, "hall")
box_m("HallS_DoorTrim", -2.7, 2.7, 4.3, 4.5, 9.7, 10.3, "hazard")
# west wall: windows z -3..3 at 3.9..5.4 above the mezzanine
box_m("HallW_Side", -11.25, -10.75, 0, HH, 3.0, 10.25, "hall")
box("HallW_Low", -11.25, -10.75, 0, 3.9, -3.0, 3.0, "hall")
box("HallW_High", -11.25, -10.75, 5.4, HH, -3.0, 3.0, "hall")
box("HallW_Mullion", -11.2, -10.8, 3.9, 5.4, -0.15, 0.15, "hall_trim")
# east wall: doors z ±(5..7.5), 3 m tall
box("HallE_Mid", 10.75, 11.25, 0, HH, -5.0, 5.0, "hall")
box_m("HallE_End", 10.75, 11.25, 0, HH, 7.5, 10.25, "hall")
box_m("HallE_Lintel", 10.75, 11.25, 3.0, HH, 5.0, 7.5, "hall")
# roof with a skylight strip x -4..4
box("HallRoofW", -11.25, -4.0, HH, HH + 0.3, -10.25, 10.25, "hall_trim")
box("HallRoofE", 4.0, 11.25, HH, HH + 0.3, -10.25, 10.25, "hall_trim")
box_m("HallSkyBeam", -4.0, 4.0, HH, HH + 0.3, 3.2, 3.6, "steel")
# mezzanine (west), ramps down toward both big doors
box("Mezz", -10.75, -7.25, 2.78, 3.0, -4.0, 4.0, "steel")
box("MezzRail", -7.45, -7.25, 3.0, 4.05, -3.0, 3.0, "hazard")
ramp_z_m("MezzRamp", -10.75, -7.25, 9.4, 4.0, 3.0, "steel")
box_m("MezzPost", -7.55, -7.25, 0, 2.78, 3.6, 3.9, "steel")
# crate block (blocks door-to-door), side crates, presses, conveyor
box("HallCrateBlock", -2.6, 2.6, 0, 2.2, -1.5, 1.5, "crate")
box_m("HallCrateSide", 1.3, 2.7, 0, 1.1, 2.0, 3.2, "crate")
box_m("HallCrateLow", -5.2, -3.8, 0, 1.1, 5.0, 6.6, "crate")
box_m("Press", 4.4, 6.6, 0, 2.6, 4.9, 7.1, "steel")
box_m("PressTop", 4.6, 6.4, 2.6, 3.1, 5.1, 6.9, "hazard")
box("Conveyor", 7.3, 8.5, 0, 1.0, -3.5, 3.5, "hall_trim")

# ---------------------------------------------------------------- west yard
# center hill: container across the midline, ramps up from both halves
box("HillContainer", -20.2, -17.8, 0, 2.6, -3.05, 3.05, "c_red")
ramp_z_m("HillRamp", -20.2, -17.8, 9.05, 3.05, 2.6, "hazard")
# container against the hall wall (with the hall it is one long barrier)
box("WallContainer", -13.69, -11.25, 0, 2.6, -3.05, 3.05, "c_blue")
# containers along the outer wall and a double stack toward each spawn
box_m("YardContainer", -25.75, -19.65, 0, 2.6, 12.28, 14.72, "c_green", "c_yellow")
box_m("Stack", -18.0, -11.9, 0, 2.6, 17.0, 19.44, "c_blue", "c_red")
box_m("StackTop", -18.0, -11.9, 2.6, 5.2, 17.0, 19.44, "c_yellow", "c_green")
box_m("YardCrate1", -24.2, -22.8, 0, 1.1, 6.3, 7.7, "crate")
box_m("YardCrate2", -14.6, -13.4, 0, 1.1, 5.5, 7.5, "crate")

# ---------------------------------------------------------------- east: alley, sheds, courtyard
# pipe stack against the hall in the alley center + offset gates near the spawn yards
box("AlleyPipes", 11.25, 14.0, 0, 2.6, -1.0, 1.0, "steel")
box("AlleyPipesBand", 11.25, 14.05, 1.2, 1.5, -1.05, 1.05, "hazard")
box_m("AlleyGate", 13.4, 16.5, 0, 3.0, 24.25, 24.75, "concrete")
box_m("AlleyRackA", 11.25, 14.0, 0, 1.0, 18.6, 19.4, "steel")
box_m("AlleyRackB", 13.75, 16.5, 0, 1.0, 7.6, 8.4, "steel")
# sheds: x 16.5..25.75, z 13..23; doors west (alley), north (courtyard) and south (spawn yard)
SH = 3.4
box_m("ShedW_A", 16.5, 16.9, 0, SH, 13.0, 16.0, "shed")
box_m("ShedW_B", 16.5, 16.9, 0, SH, 18.5, 23.0, "shed")
box_m("ShedW_Lintel", 16.5, 16.9, 2.6, SH, 16.0, 18.5, "shed")
box_m("ShedN_A", 16.5, 19.0, 0, SH, 13.0, 13.4, "shed")
box_m("ShedN_B", 21.5, 25.75, 0, SH, 13.0, 13.4, "shed")
box_m("ShedN_Lintel", 19.0, 21.5, 2.6, SH, 13.0, 13.4, "shed")
box_m("ShedS_A", 16.5, 22.0, 0, SH, 22.6, 23.0, "shed")
box_m("ShedS_B", 24.5, 25.75, 0, SH, 22.6, 23.0, "shed")
box_m("ShedS_Lintel", 22.0, 24.5, 2.6, SH, 22.6, 23.0, "shed")
box_m("ShedRoof", 16.3, 25.75, SH, SH + 0.3, 12.8, 23.2, "hall_trim")
box_m("ShedCrate", 22.8, 24.2, 0, 1.1, 17.3, 18.7, "crate")
box_m("ShedBench", 17.2, 18.0, 0, 0.9, 19.5, 22.0, "steel")
# courtyard
box_m("CourtCrate", 17.8, 19.2, 0, 1.1, 6.8, 8.2, "crate")
box_m("CourtWall", 24.25, 24.75, 0, 1.1, 5.8, 8.2, "concrete")

# ---------------------------------------------------------------- spawn yards
box_m("SpawnWall", -8.0, 8.0, 0, 3.0, 24.0, 24.5, "team_blue", "team_orange")
box_m("SpawnWallCap", -8.1, 8.1, 3.0, 3.15, 23.95, 24.55, "hall_trim")
box_m("Dock", -14.0, 14.0, 0, 1.2, 30.75, 34.25, "concrete")
box_m("DockEdge", -14.0, 14.0, 1.05, 1.25, 30.6, 30.9, "hazard")
ramp_x_m("DockRampE", 30.75, 34.25, 18.0, 14.0, 1.2, "concrete")
ramp_x_m("DockRampW", 30.75, 34.25, -18.0, -14.0, 1.2, "concrete")
# truck (body + cab) between hall and spawn wall
box_m("TruckBody", 3.0, 10.0, 0.5, 2.8, 14.6, 17.2, "truck")
box_m("TruckChassis", 3.2, 11.8, 0, 0.5, 14.8, 17.0, "hall_trim")
box_m("TruckCab", 10.0, 11.8, 0.5, 2.0, 14.6, 17.2, "cab")
box_m("YardCrateA", -6.1, -3.9, 0, 1.1, 14.3, 15.7, "crate")
box_m("YardCrateStack", -9.3, -7.7, 0, 2.2, 18.2, 19.8, "crate")
box_m("YardCrateB", -2.7, -1.3, 0, 1.1, 19.9, 21.1, "crate")

# ---------------------------------------------------------------- lights (no shadows: cheap on a Pi)
WARM = (1.0, 0.82, 0.62)
COOL = (0.75, 0.86, 1.0)
light_m("HallLight", (6.0, 5.6, 5.0), WARM, 1.2, 12.0)
light_m("HallLightW", (-7.0, 5.6, 6.0), WARM, 1.0, 11.0)
light("MezzLight", (-9.0, 5.8, 0.0), WARM, 0.6, 7.0)
light_m("ShedLight", (21.0, 2.9, 18.0), COOL, 0.7, 7.5)
light_m("YardLight", (0.0, 4.0, 29.0), WARM, 0.6, 12.0)


# ---------------------------------------------------------------- write
def main():
    mats = sorted(set(n[4] for n in nodes))
    out = ["[gd_scene load_steps=%d format=3]" % (len(mats) + 3), ""]
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
    for m in mats:
        (r, g, b), rough = MATS[m]
        out += ['[sub_resource type="StandardMaterial3D" id="Mat_%s"]' % m,
                "albedo_color = Color(%s, %s, %s, 1)" % (fmt(r), fmt(g), fmt(b)),
                "roughness = %s" % fmt(rough), ""]
    out += ['[sub_resource type="StandardMaterial3D" id="Mat_tank_cyl"]',
            "albedo_color = Color(%s, %s, %s, 1)" % tuple(fmt(v) for v in MATS["tank"][0]),
            "roughness = 0.5", ""]
    out += ['[node name="Foundry" type="Node3D"]', ""]
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]',
            'environment = SubResource("Env_foundry")', ""]
    out += ['[node name="Sun" type="DirectionalLight3D" parent="."]',
            "transform = Transform3D(0.5, -0.6124, 0.6124, 0, 0.7071, 0.7071, -0.866, -0.3536, 0.3536, 0, 16, 0)",
            "light_energy = 1.1",
            "light_color = Color(1, 0.88, 0.74, 1)",
            "shadow_enabled = true", ""]
    out += ['[node name="NavigationRegion3D" type="NavigationRegion3D" parent="."]', ""]
    out += ['[node name="Arena" type="CSGCombiner3D" parent="."]',
            "use_collision = true", "collision_layer = 1", "collision_mask = 0", ""]
    for name, typ, xf, size, mat in nodes:
        out += ['[node name="%s" type="%s" parent="Arena"]' % (name, typ),
                "transform = %s" % xf, size, 'material = SubResource("Mat_%s")' % mat, ""]
    out += ['[node name="Tank" type="CSGCylinder3D" parent="Arena"]',
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 21.5, 2.5, 0)",
            "radius = 2.2", "height = 5.0", "sides = 20",
            'material = SubResource("Mat_tank_cyl")', ""]
    out += ['[node name="TankRing" type="CSGCylinder3D" parent="Arena"]',
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 21.5, 3.6, 0)",
            "radius = 2.28", "height = 0.25", "sides = 20",
            'material = SubResource("Mat_hazard")', ""]
    for name, pos, col, energy, rng in lights:
        out += ['[node name="%s" type="OmniLight3D" parent="."]' % name,
                "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % tuple(fmt(v) for v in pos),
                "light_color = Color(%s, %s, %s, 1)" % tuple(fmt(v) for v in col),
                "light_energy = %s" % fmt(energy), "omni_range = %s" % fmt(rng), "shadow_enabled = false", ""]
    open(OUT, "w").write("\n".join(out).rstrip("\n") + "\n")
    print("wrote %s: %d boxes, %d lights" % (os.path.normpath(OUT), len(nodes), len(lights)))


main()
