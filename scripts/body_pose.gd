class_name BodyPose
extends RefCounted
## Stand/crouch pose of the blocky body (#164 part 2). Purely visual, every machine poses its own copy
## from the synced `crouch` amount (0 stand … 1 crouched), so remote players and killcam ghosts crouch
## the same way. Crouching bends the legs, drops and leans the torso forward, keeps the head (and the
## HeadHit marker, the hit target) exactly where gameplay puts it, and moves the shoulders so the arms
## (BodyArms) stay on the gun.
## The crouched head sits at Player.HEAD_CROUCH_Y (0.78 m), lower than a 0.92 m torso can reach by
## bending alone, so the torso still shortens a little (CROUCH_TORSO_SCALE) on top of the lean.

const TORSO_H := 0.92
const HIP_STAND := Vector3(0, 0.40, 0)
const HIP_CROUCH := Vector3(0, 0.14, 0.30) # low and back, so the leaned chest ends under the head
const LEAN_CROUCH := deg_to_rad(30.0) # chest forward
const CROUCH_TORSO_SCALE := 0.8
const HIP_HALF_W := 0.12
const THIGH := 0.23
const SHIN := 0.23
const LEG_T := 0.13
const FOOT := Vector3(0.12, 0.07, 0.24)
const SHOULDER_HALF_W := 0.30
const SHOULDER_DROP := 0.04 # shoulders sit this far under the torso top


## Pose `body` (a BodyMesh) for `crouch_amt`. Makes the legs on first use (not on a dedicated server).
static func apply(body: Node3D, crouch_amt: float, head_y: float) -> void:
	var k := clampf(crouch_amt, 0.0, 1.0)
	var hip := HIP_STAND.lerp(HIP_CROUCH, k)
	var lean := LEAN_CROUCH * k
	var torso_len := TORSO_H * lerpf(1.0, CROUCH_TORSO_SCALE, k)
	var up := Vector3(0, cos(lean), -sin(lean)) # torso axis; the body faces -Z
	var torso := body.get_node_or_null("Torso") as Node3D
	if torso:
		torso.position = hip + up * torso_len * 0.5
		torso.rotation = Vector3(-lean, 0, 0)
		torso.scale = Vector3(1, torso_len / TORSO_H, 1)
	var top := hip + up * torso_len
	var arms := body.get_node_or_null("Arms") as BodyArms
	if arms:
		for i in 2:
			arms.shoulders[i] = top + Vector3((-1.0 if i == 0 else 1.0) * SHOULDER_HALF_W, -SHOULDER_DROP, 0)
	# Static arm boxes (killcam ghosts, or a body without BodyArms) hang from the same shoulders.
	for i in 2:
		var box := body.get_node_or_null(["ArmL", "ArmR"][i]) as Node3D
		if box:
			box.position = top + Vector3((-1.0 if i == 0 else 1.0) * (SHOULDER_HALF_W + 0.04), -0.29, 0)
	var head_mesh := body.get_node_or_null("HeadMesh") as Node3D
	if head_mesh:
		head_mesh.position.y = head_y
	var hit := body.get_node_or_null("HeadHit") as Node3D
	if hit:
		hit.position.y = head_y
	_legs(body, hip)


## Thigh + shin + foot per side, knees bending forward. Feet stay planted under the hips.
static func _legs(body: Node3D, hip: Vector3) -> void:
	var legs := body.get_node_or_null("Legs") as Node3D
	if legs == null:
		legs = _make_legs(body)
		if legs == null:
			return
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var h := Vector3(side * HIP_HALF_W, hip.y, hip.z)
		var foot := Vector3(side * HIP_HALF_W, FOOT.y * 0.5 + 0.02, 0.0)
		var knee := knee_point(h, foot)
		_bone(legs.get_child(i * 3) as MeshInstance3D, h, knee)
		_bone(legs.get_child(i * 3 + 1) as MeshInstance3D, knee, foot)
		(legs.get_child(i * 3 + 2) as Node3D).position = foot + Vector3(0, 0, -0.04)


## Knee for a hip→foot chain of THIGH + SHIN, pushed forward (-Z) by the bend.
static func knee_point(hip: Vector3, foot: Vector3) -> Vector3:
	var d := foot - hip
	var dist := clampf(d.length(), 0.01, THIGH + SHIN - 0.001)
	var dir := d.normalized()
	var along := (dist * dist + THIGH * THIGH - SHIN * SHIN) / (2.0 * dist)
	var out := sqrt(maxf(THIGH * THIGH - along * along, 0.0))
	var bend := Vector3(0, 0, -1)
	bend = (bend - dir * bend.dot(dir)).normalized()
	return hip + dir * along + bend * out


static func _make_legs(body: Node3D) -> Node3D:
	if Game.is_dedicated:
		return null
	var torso := body.get_node_or_null("Torso") as MeshInstance3D
	var mat: Material = torso.get_active_material(0) if torso else null
	var legs := Node3D.new()
	legs.name = "Legs"
	body.add_child(legs)
	var limb := BoxMesh.new()
	limb.size = Vector3(LEG_T, LEG_T, 1.0)
	var foot := BoxMesh.new()
	foot.size = FOOT
	var boot := StandardMaterial3D.new()
	boot.albedo_color = Color(0.12, 0.12, 0.13)
	for i in 2:
		for part in [[limb, mat], [limb, mat], [foot, boot]]:
			var m := MeshInstance3D.new()
			m.mesh = part[0]
			m.material_override = part[1]
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			legs.add_child(m)
	return legs


static func _bone(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var v := b - a
	if v.length_squared() < 1e-6:
		return
	var up := Vector3.FORWARD if absf(v.normalized().dot(Vector3.UP)) > 0.98 else Vector3.UP
	m.transform = Transform3D(Basis.looking_at(v, up).scaled_local(Vector3(1, 1, v.length())), (a + b) * 0.5)
