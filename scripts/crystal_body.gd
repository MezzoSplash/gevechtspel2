class_name CrystalBody
extends Node3D
## B1 crystal humanoid (#164 facelift): faceted team-coloured torso with a pale chest plate, shoulder
## shards and a hip shard, an angular pale head with a glowing visor, glowing seams at neck and waist,
## arms from the shoulder shard to the hands on the gun, legs (thigh + shin) down to the feet, and
## detached floating hands (CrystalHands) and feet. The limbs are separate crystal segments, not a
## skinned mesh - that is what keeps the figure readable at 20 m without any art assets.
## Lives as the "Crystal" child of a BodyMesh and reuses its Torso/HeadMesh nodes (their team
## material too, so killcam ghosts that repaint those nodes get the right colour).
##
## Visual only, built on demand and never on a dedicated server. Each machine drives its own copy from
## state it already has: the synced `crouch`/`move_fx` (set by Player.pose_body) and the body's own
## world motion (speed, air, gait), plus two short ray casts (floor, wall during a wall run). The pose
## maths is in BodyPose; this node blends the inputs smoothly and applies the result.

const BLEND := 7.0 # 1/s, how fast pose weights follow their targets
const GAIT_RATE := 4.4 # gait radians per metre travelled
const WALL_RAY := 0.9
const WALL_HAND_GAP := 0.06 # the wall-side hand stops this far from the wall

## Synced state, pushed in by Player.pose_body.
var crouch := 0.0
var head_y := 1.52
var move_fx := 0
var flip := 0.0 # rad, the landing roll (#205): the body tumbles forward, the camera already did
var throw_amt := 0.0 # 0..1, the knife throw's wind-up and follow-through (#25)
var reload_amt := 0.0 # 0..1, the procedural reload dip (#164), timed on the weapon's reload_time
## #252: which reload style the body's left hand plays (mag / shells / cylinder / bolt), from the pawn.
var reload_style: StringName = &"mag"
var glow: StandardMaterial3D
var hands: CrystalHands
var _torso: Node3D
var _head: Node3D
var _neck_seam: Node3D
var _waist_seam: Node3D
var _pelvis: Node3D
var _feet: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _w := {"walk": 0.0, "sprint": 0.0, "air": 0.0, "dive": 0.0, "wall": 0.0}
var _phase := 0.0
var _bob := 0.0
var _last := Vector3.INF
var _vel := Vector3.ZERO
var _wall_point := Vector3.ZERO


## The crystal body of `body`, built on first use. Null on a dedicated server.
static func ensure(body: Node3D) -> CrystalBody:
	if Game.is_dedicated or body == null:
		return null
	var c := body.get_node_or_null("Crystal") as CrystalBody
	if c == null or c._feet.is_empty() or c._legs.is_empty(): # a duplicate (corpse) keeps its copied meshes as they are
		if c != null:
			return null
		c = CrystalBody.new()
		c.name = "Crystal"
		body.add_child(c)
		c._build(body)
	return c


## Live pawn: crystal body plus hands that follow `w`.
static func attach(body: Node3D, w: Weapon) -> CrystalBody:
	var c := ensure(body)
	if c and c.hands == null:
		c.hands = CrystalHands.attach_body(c, w, c.glow)
	return c


## A MeshInstance3D of a cached crystal part under `parent`.
static func mesh_part(parent: Node3D, id: StringName, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = CrystalMesh.part(id)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


## Team colour change: the seams/visor glow (the torso shares the pawn's body material).
func repaint(col: Color) -> void:
	if glow:
		glow.albedo_color = col.lightened(0.15)
		glow.emission = col


func _build(body: Node3D) -> void:
	_torso = body.get_node_or_null("Torso") as Node3D
	_head = body.get_node_or_null("HeadMesh") as Node3D
	var team_mat := (_torso as MeshInstance3D).get_active_material(0) if _torso is MeshInstance3D else null
	var col: Color = (team_mat as StandardMaterial3D).albedo_color if team_mat is StandardMaterial3D else Color(0.3, 0.5, 1.0)
	glow = CrystalMesh.glow_material(col)
	var shell := CrystalMesh.shell_material()
	if _torso is MeshInstance3D:
		(_torso as MeshInstance3D).mesh = CrystalMesh.part(&"torso")
		mesh_part(_torso, &"chest", shell).position = Vector3(0, 0.12, -0.12)
		for side in [-1.0, 1.0]:
			var sh := mesh_part(_torso, &"shoulder", team_mat)
			sh.position = Vector3(side * 0.31, 0.27, 0)
	if _head is MeshInstance3D:
		var hm := _head as MeshInstance3D
		hm.mesh = CrystalMesh.part(&"head")
		hm.material_override = shell
		mesh_part(hm, &"visor", glow).position = Vector3(0, 0.02, -0.115)
	_neck_seam = mesh_part(self, &"seam", glow)
	_neck_seam.scale = Vector3.ONE * 0.6
	_waist_seam = mesh_part(self, &"seam", glow)
	_pelvis = mesh_part(self, &"pelvis", team_mat)
	for i in 2:
		var foot := Node3D.new()
		add_child(foot)
		mesh_part(foot, &"foot", shell)
		mesh_part(foot, &"spark", glow).position = Vector3(0, 0.02, 0.10) # ankle glow, above the heel
		_feet.append(foot)
	# Legs (thigh + shin per side) and arms (shoulder shard to the hand on the gun): the figure was a
	# floating torso with two blocks beside it (#164).
	for i in 4:
		var leg := Node3D.new()
		add_child(leg)
		mesh_part(leg, &"limb_leg", team_mat if i < 2 else shell)
		mesh_part(leg, &"spark", glow).position = Vector3(0, 1.0, 0) # joint glow at the far end
		_legs.append(leg)
	for i in 2:
		var arm := Node3D.new()
		add_child(arm)
		mesh_part(arm, &"limb", shell)
		_arms.append(arm)
	# The old box arms of #165 / the placeholder arm boxes: gone (scene) or hidden (old copies).
	for n in ["ArmL", "ArmR", "Arms", "Legs"]:
		var old := body.get_node_or_null(n) as Node3D
		if old:
			old.visible = false


func _process(delta: float) -> void:
	if _feet.is_empty() or not is_visible_in_tree():
		return
	tick(delta)


## Advance the blends by `delta` and pose every part (also called by checks).
func tick(delta: float) -> void:
	var pos := global_position
	if _last != Vector3.INF and delta > 0.0:
		var v := (pos - _last) / delta
		if v.length() < 40.0: # teleports/respawns: ignore
			_vel = _vel.lerp(v, clampf(delta * 12.0, 0.0, 1.0))
	_last = pos
	var local_v := global_transform.basis.inverse() * _vel
	var speed := Vector2(local_v.x, local_v.z).length()
	var wall_side := _wall_side() if move_fx == Player.MOVE_WALLRUN else 0.0
	var target := {
		"walk": clampf(speed / Player.WALK_SPEED * 1.6, 0.0, 1.0),
		"sprint": clampf((speed - Player.WALK_SPEED * 1.1) / (Player.SPRINT_SPEED - Player.WALK_SPEED * 1.1), 0.0, 1.0),
		"air": 0.0 if (move_fx != Player.MOVE_NONE or _grounded()) else 1.0,
		"dive": 1.0 if move_fx == Player.MOVE_DIVE else 0.0,
		"wall": wall_side,
	}
	var a := 1.0 - exp(-BLEND * delta) if delta > 0.0 else 1.0
	for key in _w:
		_w[key] = lerpf(_w[key], target[key], a)
	_phase = fmod(_phase + speed * GAIT_RATE * delta * (1.0 if move_fx != Player.MOVE_WALLRUN else 1.3), TAU)
	_bob = fmod(_bob + delta * 2.2, TAU)
	var p := _w.duplicate()
	p["crouch"] = crouch
	p["head_y"] = head_y
	p["flip"] = flip
	p["throw"] = throw_amt
	p["reload"] = reload_amt
	p["hands"] = hands.hand_targets() if hands else []
	p["phase"] = _phase
	p["bob"] = _bob
	p["dir"] = Vector3(local_v.x, 0, local_v.z)
	_apply(BodyPose.solve(p))


func _apply(pose: Dictionary) -> void:
	if _torso:
		_torso.transform = pose["torso"]
	if _head:
		_head.transform = pose["head"]
	_neck_seam.transform = (pose["neck_seam"] as Transform3D).scaled_local(Vector3.ONE * 0.6)
	_waist_seam.transform = pose["waist_seam"]
	_pelvis.transform = pose["pelvis"]
	for i in 2:
		_feet[i].transform = pose["feet"][i]
	var legs: Array = pose.get("legs", [])
	for i in mini(legs.size(), _legs.size()):
		_legs[i].transform = legs[i]
	var arms: Array = pose.get("arms", [])
	for i in mini(arms.size(), _arms.size()):
		_arms[i].transform = arms[i]
	if hands:
		var w := absf(_w["wall"])
		var reach_i := 0 if _w["wall"] < 0.0 else 1
		hands.reach = [[Vector3.ZERO, 0.0], [Vector3.ZERO, 0.0]]
		hands.reach[reach_i] = [_wall_point, 0.85 * w]
		# #252: a reloading body's left hand leaves the gun for the mag, the loading port or the
		# cylinder, exactly like the shooter's own first-person hand (the same ReloadAnims curves). The
		# reload wins over the wall-run touch: you cannot be reloading and holding a wall at once.
		if reload_amt > 0.001 and hands.weapon != null and is_instance_valid(hands.weapon):
			var s := ReloadAnims.solve(reload_style, reload_amt)
			var hw := float(s.hand_w)
			if hw > 0.001:
				hands.reach[0] = [hands.to_local(hands.weapon.to_global(s.hand as Vector3)), hw]


## Body on the floor (or close above it), from a short down ray.
func _grounded() -> bool:
	var hit := _ray(global_position + Vector3.UP * 0.3, global_position + Vector3.DOWN * 0.35)
	return not hit.is_empty()


## -1 wall on the left, +1 on the right, 0 none; stores where the wall hand goes.
func _wall_side() -> float:
	var from := global_transform * Vector3(0, head_y - 0.4, 0)
	for side in [-1.0, 1.0]:
		var to := global_transform * Vector3(side * WALL_RAY, head_y - 0.4, -0.2)
		var hit := _ray(from, to)
		if not hit.is_empty():
			var p: Vector3 = hit.position + (hit.normal as Vector3) * WALL_HAND_GAP
			_wall_point = global_transform.affine_inverse() * p
			return side
	return 0.0


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var pawn := get_parent().get_parent() as CollisionObject3D
	if pawn:
		q.exclude = [pawn.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)
