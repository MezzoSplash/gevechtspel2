#!/usr/bin/env python3
"""Writes the hand-made low-poly weapon scenes (SMG, revolver, throwing knife) as .tscn.

Plain Box/Cylinder/Prism meshes, flat materials, modeled along +X (muzzle / tip at +X) like the
GLB guns, so Weapon.fit_model can scale and place them the same way. Run from the repo root:
    python3 tools/build_lowpoly_weapons.py
"""
import math

MATS = {
    "metal": ((0.20, 0.21, 0.23), 0.55, 0.45),
    "dark": ((0.08, 0.08, 0.09), 0.2, 0.7),
    "wood": ((0.40, 0.22, 0.10), 0.0, 0.8),
    "steel": ((0.78, 0.80, 0.84), 0.85, 0.25),
    "wrap": ((0.16, 0.12, 0.10), 0.0, 0.9),
    "accent": ((0.85, 0.45, 0.10), 0.1, 0.6),
}


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Basis (rows): rotate about X, then Y, then Z (degrees)."""
    ax, ay, az = (math.radians(v) for v in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    X = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    Y = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    Z = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(Z, mul(Y, X))


def xf(pos, basis):
    # Godot Transform3D(x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z, o) with x/y/z the basis columns.
    cols = [[basis[r][c] for r in range(3)] for c in range(3)]
    nums = [v for col in cols for v in col] + list(pos)
    return "Transform3D(" + ", ".join(f"{v:.5g}" if abs(v) > 1e-9 else "0" for v in nums) + ")"


def scene(name, parts):
    subs, nodes = [], []
    mat_ids = {}
    for m in sorted({p[2] for p in parts}):
        col, metal, rough = MATS[m]
        mid = f"mat_{m}"
        mat_ids[m] = mid
        subs.append(
            f'[sub_resource type="StandardMaterial3D" id="{mid}"]\n'
            f"albedo_color = Color({col[0]}, {col[1]}, {col[2]}, 1)\nmetallic = {metal}\nroughness = {rough}\n"
        )
    for i, (pname, kind, mat, size, pos, r) in enumerate(parts):
        mid = f"mesh_{i}"
        if kind == "box":
            body = f"size = Vector3({size[0]}, {size[1]}, {size[2]})"
        elif kind == "cyl":  # along X: radius, length, sides
            body = f"top_radius = {size[0]}\nbottom_radius = {size[0]}\nheight = {size[1]}\nradial_segments = {size[2]}\nrings = 1"
            r = (r[0], r[1], r[2] - 90.0)
        elif kind == "prism":  # apex toward +X: width (y), length (x), thickness (z)
            body = f"size = Vector3({size[0]}, {size[1]}, {size[2]})"
            r = (r[0], r[1], r[2] - 90.0)
        elif kind == "prismflat":  # apex toward +X, lying flat: width (z), length (x), thickness (y)
            body = f"size = Vector3({size[0]}, {size[1]}, {size[2]})"
        mesh_type = {"box": "BoxMesh", "cyl": "CylinderMesh", "prism": "PrismMesh", "prismflat": "PrismMesh"}[kind]
        subs.append(f'[sub_resource type="{mesh_type}" id="{mid}"]\nmaterial = SubResource("{mat_ids[mat]}")\n{body}\n')
        # prismflat: local X (width) -> Z, local Y (apex) -> +X, local Z (thickness) -> Y
        basis = [[0, 1, 0], [0, 0, 1], [1, 0, 0]] if kind == "prismflat" else rot(*r)
        nodes.append(
            f'[node name="{pname}" type="MeshInstance3D" parent="."]\n'
            f"transform = {xf(pos, basis)}\nmesh = SubResource(\"{mid}\")\n"
        )
    out = f"[gd_scene load_steps={len(subs) + 1} format=3]\n\n" + "\n".join(subs)
    out += f'\n[node name="{name}" type="Node3D"]\n\n' + "\n".join(nodes)
    with open(f"assets/weapons/{name}.tscn", "w") as f:
        f.write(out)
    print(f"assets/weapons/{name}.tscn  {len(parts)} parts")


Z = (0.0, 0.0, 0.0)
scene("smg", [
    ("Receiver", "box", "metal", (0.30, 0.07, 0.05), (0.0, 0.0, 0.0), Z),
    ("TopRail", "box", "dark", (0.22, 0.012, 0.03), (0.0, 0.041, 0.0), Z),
    ("Shroud", "cyl", "dark", (0.024, 0.14, 8), (0.21, 0.008, 0.0), Z),
    ("Muzzle", "cyl", "metal", (0.014, 0.05, 8), (0.30, 0.008, 0.0), Z),
    ("Grip", "box", "dark", (0.042, 0.10, 0.042), (-0.07, -0.075, 0.0), (0, 0, -14)),
    ("Mag", "box", "dark", (0.036, 0.14, 0.03), (0.07, -0.10, 0.0), (0, 0, 6)),
    ("TriggerGuard", "box", "metal", (0.06, 0.008, 0.012), (-0.02, -0.05, 0.0), Z),
    ("Stock", "box", "metal", (0.15, 0.018, 0.018), (-0.22, 0.005, 0.0), Z),
    ("StockLow", "box", "metal", (0.13, 0.016, 0.016), (-0.21, -0.035, 0.0), (0, 0, 10)),
    ("ButtPlate", "box", "dark", (0.022, 0.08, 0.045), (-0.30, -0.015, 0.0), Z),
    ("FrontSight", "box", "accent", (0.015, 0.03, 0.01), (0.13, 0.06, 0.0), Z),
    ("RearSight", "box", "dark", (0.02, 0.025, 0.03), (-0.11, 0.055, 0.0), Z),
])
# Cylinder yaw stays 0: a cyl already lies along +X, and a yaw wedges the chamber into the frame.
# Grip and cap sit forward enough that the top of the grip enters the back of the frame.
scene("revolver", [
    ("Barrel", "cyl", "metal", (0.016, 0.17, 10), (0.125, 0.032, 0.0), Z),
    ("Rib", "box", "metal", (0.17, 0.018, 0.02), (0.125, 0.016, 0.0), Z),
    ("Frame", "box", "metal", (0.11, 0.065, 0.034), (0.0, 0.02, 0.0), Z),
    ("Cylinder", "cyl", "steel", (0.034, 0.06, 6), (0.02, 0.024, 0.0), Z),
    ("CylinderPin", "cyl", "dark", (0.008, 0.07, 6), (0.02, 0.024, 0.0), Z),
    ("Hammer", "box", "dark", (0.022, 0.03, 0.012), (-0.065, 0.06, 0.0), (0, 0, 25)),
    ("Grip", "box", "wood", (0.04, 0.10, 0.03), (-0.053, -0.045, 0.0), (0, 0, -22)),
    ("GripCap", "box", "metal", (0.044, 0.012, 0.032), (-0.072, -0.093, 0.0), (0, 0, -22)),
    ("TriggerGuard", "box", "metal", (0.04, 0.008, 0.01), (-0.015, -0.03, 0.0), Z),
    ("Trigger", "box", "dark", (0.008, 0.025, 0.006), (-0.02, -0.015, 0.0), (0, 0, -10)),
    ("FrontSight", "box", "accent", (0.012, 0.022, 0.006), (0.195, 0.055, 0.0), Z),
])
# Lies flat (thin in Y), so the blade face shows from above in the hand and while it tumbles.
scene("knife", [
    ("Blade", "box", "steel", (0.15, 0.008, 0.036), (0.055, 0.0, 0.0), Z),
    ("Tip", "prismflat", "steel", (0.036, 0.06, 0.008), (0.16, 0.0, 0.0), Z),
    ("Edge", "box", "metal", (0.15, 0.01, 0.006), (0.055, 0.0, 0.018), Z),
    ("Guard", "box", "dark", (0.012, 0.018, 0.056), (-0.026, 0.0, 0.0), Z),
    ("Handle", "box", "wrap", (0.10, 0.016, 0.026), (-0.085, 0.0, 0.0), Z),
    ("Pommel", "cyl", "accent", (0.016, 0.014, 8), (-0.14, 0.0, 0.0), Z),
])
