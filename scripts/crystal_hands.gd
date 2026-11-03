class_name CrystalHands
extends Node3D
## Two detached floating crystal hands that hold the gun (B1 body, replaces the #165 box arms).
## Purely visual and client-side: every machine places its own copy from the pawn's weapon node.
## Right hand on the grip (just behind the weapon root), left on the foregrip (part-way to the
## muzzle), so it fits every gun without per-weapon data. `reach` can pull one hand elsewhere (the
## wall-run touch); the pose driver sets it. Same script for the third-person body and the viewmodel.

## Foregrip: this far from the grip toward the muzzle (0 grip, 1 muzzle).
const SUPPORT_T := 0.45
## Grip point in the weapon's local space (just under and behind its origin).
const GRIP_OFFSET := Vector3(0.0, -0.04, 0.06)

var weapon: Weapon
## Optional override per hand: [point in this node's space, weight 0..1]. Empty = on the gun.
var reach: Array = [[Vector3.ZERO, 0.0], [Vector3.ZERO, 0.0]]
var _hands: Array[Node3D] = []
var _view := false
var _size := 1.0


## Third-person hands under `parent` (the crystal body).
static func attach_body(parent: Node3D, w: Weapon, glow: Material) -> CrystalHands:
	return _make(parent, "Hands", w, glow, 1.0, false)


## First-person hands under `cam`: smaller, they sit centimetres from the lens.
static func attach_view(cam: Node3D, w: Weapon, glow: Material) -> CrystalHands:
	return _make(cam, "ViewHands", w, glow, 0.6, true)


static func _make(parent: Node3D, n: String, w: Weapon, glow: Material, size: float, view: bool) -> CrystalHands:
	var h := CrystalHands.new()
	h.name = n
	h.weapon = w
	h._view = view
	h._size = size
	parent.add_child(h)
	var shell := CrystalMesh.shell_material()
	for i in 2:
		var hand := Node3D.new()
		h.add_child(hand)
		CrystalBody.mesh_part(hand, &"hand", shell).rotation.x = -PI / 2 # point along the gun
		var wrist := CrystalBody.mesh_part(hand, &"spark", glow)
		wrist.position = Vector3(0, 0, 0.08)
		h._hands.append(hand)
	return h


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


## Hand `i` position right now (for checks).
func hand_position(i: int) -> Vector3:
	return _hands[i].position


func _process(_delta: float) -> void:
	# A duplicate (corpse, fall icon) copies this node without its hand list: it keeps its last pose.
	if _hands.is_empty() or not is_visible_in_tree():
		return
	var t := hand_targets()
	var show := t.size() == 2 and (weapon.model_shown() if _view else true)
	for i in 2:
		_hands[i].visible = show
	if not show:
		return
	var aim := weapon.global_transform.basis.z
	var look := Basis.looking_at(global_transform.basis.inverse() * -aim, Vector3.UP) if absf(aim.y) < 0.98 else Basis()
	for i in 2:
		var w := float(reach[i][1])
		_hands[i].position = t[i].lerp(reach[i][0], w)
		_hands[i].basis = look.scaled(Vector3.ONE * _size)
