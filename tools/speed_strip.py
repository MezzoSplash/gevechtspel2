"""Flush speed strips for surf exits. No collision: the Node3D scale is the detection box.

Local space of the node is a unit cube (half-extent 0.5). The mesh is a thin hazard mark on
the bottom, so a proud curb never meets the movement capsule. Re-run the map generator after
editing a strip.
"""

import math

WIDTH = 4.0
DEPTH = 3.0
# Surf triangle shared by the maps: buried toe at y=-0.1, ridge at y=5.15.
# The catch volume is this tall (or the downhill drop, when that is taller) so a
# ride anywhere on the face still crosses the exit. A short box misses that line.
FACE_HEIGHT = 5.25
BURY = 0.2  # the box starts under the floor, so feet exactly on it still count
VIS_LIFT = 0.02
VIS_THICK = 0.03
LOAD_STEPS = 2  # BoxMesh + emissive material
SURF_TOE = 3.30


def fmt(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def xform(basis_cols, origin):
    """Same column order as the map generators."""
    (x, y, z) = basis_cols
    vals = [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]] + list(origin)
    return "Transform3D(%s)" % ", ".join(fmt(v) for v in vals)


def horiz(x, z):
    length = math.hypot(x, z)
    if length < 1e-8:
        return None
    return (x / length, z / length)


def toe(basis, origin, along, surf_toe=SURF_TOE):
    """Toe `along` metres down local -Z. basis columns are (X, Y, Z)."""
    local = (surf_toe, -0.1, -along)
    return tuple(
        origin[i] + basis[0][i] * local[0] + basis[1][i] * local[1] + basis[2][i] * local[2]
        for i in range(3)
    )


def forward_xz(basis, sign=1.0):
    """Horizontal travel. sign +1 follows local -Z (the extrusion)."""
    z = basis[2]
    return (-z[0] * sign, -z[2] * sign)


def catch_height(drop=0.0):
    """Metres above the exit floor. At least the full surf face; a taller drop wins."""
    return max(float(drop), FACE_HEIGHT)


def make(name, toe_pos, forward, floor_y, width=WIDTH, depth=DEPTH, height=0.0, open_xz=None):
    """Box center sits depth/2 past the toe. height is this ramp's vertical drop.

    The node scale is the catch volume: from floor-BURY up to floor+catch_height.
    The visible mark stays a thin stripe on the floor. `open_xz` is the flat side
    of the toe: the mark then stays on that side, instead of crossing onto the face.
    """
    fwd = horiz(forward[0], forward[1])
    if fwd is None:
        raise ValueError("strip %s has no travel direction" % name)
    fx, fz = fwd
    rx, rz = (fz, -fx)  # Y-up, local +Z is travel, det +1
    # Full width when the caller does not say which side is floor. Other maps keep that.
    mark_x, mark_sx = 0.0, 1.0
    if open_xz is not None:
        opened = horiz(open_xz[0], open_xz[1])
        if opened is not None:
            sign = 1.0 if opened[0] * rx + opened[1] * rz >= 0.0 else -1.0
            # Stay off the toe. A mark that starts on the centreline clips the face.
            mark_sx = 0.36
            gap = 0.08
            mark_x = sign * (gap + mark_sx * 0.5)
    ramp_h = catch_height(height)
    span = ramp_h + BURY
    center_lift = span * 0.5 - BURY
    center = (
        toe_pos[0] + fx * depth * 0.5,
        floor_y + center_lift,
        toe_pos[2] + fz * depth * 0.5,
    )
    return {
        "name": name,
        "center": center,
        "right": (rx, rz),
        "fwd": (fx, fz),
        "width": width,
        "depth": depth,
        "height": span,
        "ramp_h": ramp_h,
        "floor": floor_y,
        "mark_x": mark_x,
        "mark_sx": mark_sx,
    }


def resources():
    return [
        '[sub_resource type="BoxMesh" id="Mesh_line"]',
        "size = Vector3(1, 1, 1)",
        "",
        '[sub_resource type="StandardMaterial3D" id="Mat_line"]',
        "albedo_color = Color(0.78, 0.62, 0.14, 1)",
        "roughness = 0.45",
        "emission_enabled = true",
        "emission = Color(0.9, 0.72, 0.2, 1)",
        "emission_energy_multiplier = 0.45",
        "",
    ]


def nodes(strips):
    """One scaled Node3D per strip (group speed_strip) and a thin mark with no collision.

    The mark is a stripe across the toe, not the whole 3 m box, so it does not read as a floor.
    The rest of the box is only the catch volume.
    """
    out = []
    stripe = 0.35  # metres along travel
    for s in strips:
        rx, rz = s["right"]
        fx, fz = s["fwd"]
        w, h, d = s["width"], s["height"], s["depth"]
        basis = (
            (rx * w, 0.0, rz * w),
            (0.0, h, 0.0),
            (fx * d, 0.0, fz * d),
        )
        # Stripe sits on the floor. h is the full ramp, so the local Y is recomputed per strip.
        center_lift = h * 0.5 - BURY
        vis_y = (VIS_LIFT - center_lift) / h
        vis_sy = VIS_THICK / h
        local_sz = stripe / d
        mark_sx = s.get("mark_sx", 1.0)
        mark_xf = xform(
            ((mark_sx, 0.0, 0.0), (0.0, vis_sy, 0.0), (0.0, 0.0, local_sz)),
            (s.get("mark_x", 0.0), vis_y, -0.5 + local_sz * 0.5),
        )
        out += [
            '[node name="%s" type="Node3D" parent="." groups=["speed_strip"]]' % s["name"],
            "transform = %s" % xform(basis, s["center"]),
            "",
            '[node name="Mark" type="MeshInstance3D" parent="%s"]' % s["name"],
            "transform = %s" % mark_xf,
            'mesh = SubResource("Mesh_line")',
            'surface_material_override/0 = SubResource("Mat_line")',
            "cast_shadow = 0",
            "",
        ]
    return out


def _local(strip, world):
    """Inverse of the scaled basis, matching Player.segment_hits_strip's unit cube."""
    rx, rz = strip["right"]
    fx, fz = strip["fwd"]
    w, h, d = strip["width"], strip["height"], strip["depth"]
    cx, cy, cz = strip["center"]
    dx, dy, dz = world[0] - cx, world[1] - cy, world[2] - cz
    # Columns are orthogonal: local = component / scale.
    return (
        (dx * rx + dz * rz) / w,
        dy / h,
        (dx * fx + dz * fz) / d,
    )


def _self_check():
    basis = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    origin = (0.0, 0.1, 10.0)
    toe_pos = toe(basis, origin, 15.0)
    strip = make("T", toe_pos, forward_xz(basis, 1.0), 0.0)
    assert abs(strip["ramp_h"] - FACE_HEIGHT) < 1e-6
    feet = (toe_pos[0], 0.0, toe_pos[2])
    local = _local(strip, feet)
    assert abs(local[0]) <= 0.5 and abs(local[1]) <= 0.5 and abs(local[2]) <= 0.5, local
    # Top of the face is inside. A body above the ramp is not.
    crest = (toe_pos[0], FACE_HEIGHT, toe_pos[2])
    crest_l = _local(strip, crest)
    assert abs(crest_l[1] - 0.5) < 1e-6, crest_l
    above = (toe_pos[0], FACE_HEIGHT + 0.4, toe_pos[2])
    assert _local(strip, above)[1] > 0.5
    past = (toe_pos[0], 0.0, toe_pos[2] - DEPTH - 0.5)
    # forward of identity local -Z is world -Z, so the strip extends toward -Z.
    local_past = _local(strip, past)
    assert local_past[2] < -0.5 or local_past[2] > 0.5, local_past
    tall = make("D", toe_pos, forward_xz(basis, 1.0), 0.0, height=6.0)
    assert abs(tall["ramp_h"] - 6.0) < 1e-6
    assert abs(_local(tall, (toe_pos[0], 6.0, toe_pos[2]))[1] - 0.5) < 1e-6
    # Same end speed as player.gd: 16 m/s, CARRY_FRICTION 0.06, CARRY_TIME 4 s.
    kept = 16.0 * math.exp(-0.06 * 4.0)
    assert kept > 11.4, kept
    print("speed_strip ok, face %.2f m, 16 m/s after 4 s at friction 0.06 -> %.2f" % (
        FACE_HEIGHT, kept))


if __name__ == "__main__":
    _self_check()
