class_name BodyArms
extends Node3D
## Simple two-bone arms that hold the gun (#164). Purely visual and client-side: every machine poses
## its own copy from the pawn's weapon node, nothing is synced.
## Two uses, same script:
## - third person: child of BodyMesh, shoulders on the torso, team-coloured sleeves;
## - first person: child of the camera, shoulders just below/behind the screen edge (viewmodel).
## Hands: right on the grip (the weapon root), left on the foregrip (part-way to the muzzle), so it
## fits every gun without per-weapon data. Elbows bend down and outward with a cheap analytic IK.

const UPPER_LEN := 0.38
const FORE_LEN := 0.38
const THICK := 0.10
const HAND := Vector3(0.09, 0.08, 0.11)
## Foregrip: this far from the grip toward the muzzle (0 grip, 1 muzzle).
const SUPPORT_T := 0.45
## Grip point in the weapon's local space (just under and behind its origin).
const GRIP_OFFSET := Vector3(0.0, -0.04, 0.06)

var weapon: Weapon
## Sleeve thickness (m). The viewmodel uses thinner arms: they sit centimetres from the lens.
var thickness := THICK
## Shoulders in this node's local space: [left, right].
var shoulders: Array[Vector3] = [Vector3(-0.30, 1.30, 0.0), Vector3(0.30, 1.30, 0.0)]
var _upper: Array[MeshInstance3D] = []
var _fore: Array[MeshInstance3D] = []
var _hands: Array[MeshInstance3D] = []


## Third-person arms on `body` (BodyMesh), in the body material; hides the old static arm boxes.
static func attach_body(body: Node3D, w: Weapon, sleeve: Material) -> BodyArms:
	for n in ["ArmL", "ArmR"]:
		var old := body.get_node_or_null(n) as Node3D
		if old:
			old.visible = false
	var a := BodyArms.new()
	a.name = "Arms"
	a.weapon = w
	body.add_child(a)
	a.build(sleeve)
	return a


## First-person arms under `cam`: shoulders off-screen, so only forearms and hands show.
static func attach_view(cam: Node3D, w: Weapon, sleeve: Material) -> BodyArms:
	var a := BodyArms.new()
	a.name = "ViewArms"
	a.weapon = w
	a.shoulders = [Vector3(-0.16, -0.50, 0.22), Vector3(0.32, -0.46, 0.26)]
	a.thickness = 0.05
	cam.add_child(a)
	a.build(sleeve)
	return a


## Make the meshes (shared box meshes; one sleeve and one glove material).
func build(sleeve: Material) -> void:
	var limb := BoxMesh.new()
	limb.size = Vector3(thickness, thickness, 1.0) # stretched along local Z to the bone length
	var hand := BoxMesh.new()
	hand.size = HAND * (thickness / THICK)
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.12, 0.12, 0.13)
	for i in 2:
		_upper.append(_part(limb, sleeve))
		_fore.append(_part(limb, sleeve))
		_hands.append(_part(hand, glove))


func _part(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


## Grip and foregrip in this node's local space, or [] without a gun.
func hand_targets() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if weapon == null or not is_instance_valid(weapon):
		return out
	var wt := weapon.global_transform
	var grip := wt * GRIP_OFFSET
	var tip := weapon.muzzle.global_position if weapon.muzzle else wt * Vector3(0, 0, -0.5)
	var inv := global_transform.affine_inverse()
	out.append(inv * grip.lerp(tip, SUPPORT_T)) # left: foregrip
	out.append(inv * grip) # right: grip
	return out


## Elbow for a shoulder→hand chain: bends down and outward (`side` -1 left, +1 right).
static func elbow(shoulder: Vector3, hand: Vector3, side: float) -> Vector3:
	var d := hand - shoulder
	var dist := clampf(d.length(), 0.01, UPPER_LEN + FORE_LEN - 0.001)
	var dir := d.normalized()
	# Law of cosines: how far along the line the elbow projects, and how far it sticks out.
	var along := (dist * dist + UPPER_LEN * UPPER_LEN - FORE_LEN * FORE_LEN) / (2.0 * dist)
	var out := sqrt(maxf(UPPER_LEN * UPPER_LEN - along * along, 0.0))
	var bend := (Vector3.DOWN + Vector3(side * 0.6, 0, 0)).normalized()
	bend = (bend - dir * bend.dot(dir)).normalized()
	return shoulder + dir * along + bend * out


func _process(_delta: float) -> void:
	# A duplicate of BodyMesh (killcam ghost, fall icon) copies this node without its meshes: skip it.
	if _upper.is_empty() or not is_visible_in_tree():
		return
	var targets := hand_targets()
	var show := targets.size() == 2 and (weapon.model_shown() if name == "ViewArms" else true)
	for i in 2:
		_upper[i].visible = show
		_fore[i].visible = show
		_hands[i].visible = show
	if not show:
		return
	for i in 2:
		var s: Vector3 = shoulders[i]
		var h: Vector3 = targets[i]
		var reach := UPPER_LEN + FORE_LEN - 0.001
		if s.distance_to(h) > reach:
			h = s + (h - s).normalized() * reach # too far: point the arm at it
		var e := elbow(s, h, -1.0 if i == 0 else 1.0)
		_bone(_upper[i], s, e)
		_bone(_fore[i], e, h)
		_hands[i].transform = Transform3D(_look_basis(h - e), h)


## Stretch a unit-length box between two points.
static func _bone(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var v := b - a
	var basis := _look_basis(v).scaled_local(Vector3(1, 1, maxf(v.length(), 0.01)))
	m.transform = Transform3D(basis, (a + b) * 0.5)


static func _look_basis(v: Vector3) -> Basis:
	if v.length_squared() < 1e-6:
		return Basis()
	var up := Vector3.UP if absf(v.normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	return Basis.looking_at(v, up)
