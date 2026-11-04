class_name UavDrone
extends AnimatableBody3D
## Physical UAV scorestreak: the UAV.glb model circles high over the map while its team's radar runs.
## Server-authoritative: the match authority picks the path (centre, radius, height, start angle) from
## the map's spawn points and sends it once (Game.sync_uav_spawn). The path is a pure function of the
## time since launch, so every machine flies its own copy without a pose stream.
## Only the authority's copy collides (layer 4, inside Game.SHOT_MASK): enemy hitscan shots and thrown
## knives damage it, friendly fire does nothing. At 0 HP the authority ends it (Game.sync_uav_end):
## everyone sees it spin down and blow up, the radar of that UAV stops early, the kill feed shows
## the shooter, and the shooter gets "UAV neergeschoten".

## Hit points: rifle hits are 34 up close, less at this range (falloff), so about four rifle hits.
const MAX_HP := 120.0
## Height above the highest spawn point (m).
const ALTITUDE := 26.0
## Circle radius: this share of the farthest spawn from the map centre, clamped to RADIUS_MIN..MAX.
const RADIUS_FILL := 0.75
const RADIUS_MIN := 14.0
const RADIUS_MAX := 48.0
## Seconds per lap.
const LAP_TIME := 22.0
## Bank angle into the turn (rad).
const BANK := 0.32
## Model size: wingspan fitted to this (m).
const WINGSPAN := 3.2
## Generous hit sphere: the shooter aims at a copy that may lag a few frames.
const HIT_RADIUS := 1.7
## Shot-down fall before the explosion (s).
const FALL_TIME := 1.6
## Yaw of the model inside the drone node: UAV.glb is authored nose along +Z, the node flies along -Z.
## Only the model turns, so the path and its bank (inner wing down, into the turn) stay as they were.
const MODEL_YAW_OFFSET := PI
const MODEL := preload("res://assets/gadgets/UAV.glb")

static var _next_id := 1

var net_id := 0
var team := 0
var owner_peer := 0
var hp := MAX_HP
var life := 0.0
var centre := Vector3.ZERO
var radius := 20.0
var height := 30.0
var phase0 := 0.0
var age := 0.0
var _falling := -1.0
var _fall_vel := Vector3.ZERO
var _light: OmniLight3D


## Authority: launch one for `peer` on `team`; tells every client.
static func launch(g: GameState, peer: int, team_id: int, seconds: float) -> UavDrone:
	var path := fit_path(g.map_id)
	var id := _next_id
	_next_id += 1
	var phase := randf() * TAU
	if g.is_networked():
		g.sync_uav_spawn.rpc(id, team_id, peer, path.centre, path.radius, path.height, phase, seconds)
	return spawn(g, id, team_id, peer, path.centre, path.radius, path.height, phase, seconds, true)


## Every machine: the drone node (collider only on the authority, model never on a dedicated server).
static func spawn(g: GameState, id: int, team_id: int, peer: int, c: Vector3, r: float, h: float,
		phase: float, seconds: float, authority: bool) -> UavDrone:
	var scene := g.get_tree().current_scene
	if scene == null:
		return null
	var d := UavDrone.new()
	d.name = "Uav%d" % id
	d.net_id = id
	d.team = team_id
	d.owner_peer = peer
	d.centre = c
	d.radius = r
	d.height = h
	d.phase0 = phase
	d.life = seconds
	d.sync_to_physics = false
	d.collision_layer = 4 if authority else 0
	d.collision_mask = 0
	d.add_to_group("uav_drone")
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS
	cs.shape = sphere
	d.add_child(cs)
	if not Game.is_dedicated:
		d._build_visual(Player.team_color(team_id))
	scene.add_child(d)
	d.global_transform = path_transform(c, r, h, phase, 0.0)
	return d


## Centre, radius and height of the circle for a map, from its spawn points (and flag bases).
static func fit_path(map: StringName) -> Dictionary:
	var pts: Array = []
	pts.append_array(Maps.team_spawns(map, 0))
	pts.append_array(Maps.team_spawns(map, 1))
	pts.append_array(Maps.ffa_spawns(map))
	pts.append_array(Maps.flag_bases(map))
	if pts.is_empty():
		return {"centre": Vector3.ZERO, "radius": RADIUS_MIN, "height": ALTITUDE}
	var sum := Vector3.ZERO
	var top := -INF
	for p in pts:
		sum += p as Vector3
		top = maxf(top, (p as Vector3).y)
	var c := sum / pts.size()
	c.y = 0.0
	var far := 0.0
	for p in pts:
		far = maxf(far, Vector2((p as Vector3).x - c.x, (p as Vector3).z - c.z).length())
	return {"centre": c, "radius": clampf(far * RADIUS_FILL, RADIUS_MIN, RADIUS_MAX), "height": top + ALTITUDE}


## Pose on the circle `t` seconds after launch: nose along the flight direction, banked inward.
static func path_transform(c: Vector3, r: float, h: float, phase: float, t: float) -> Transform3D:
	var a := phase + TAU * t / LAP_TIME
	var pos := c + Vector3(cos(a) * r, h, sin(a) * r)
	var fwd := Vector3(-sin(a), 0.0, cos(a)) # d(pos)/da: counter-clockwise seen from above
	var b := Basis.looking_at(fwd, Vector3.UP)
	b = b * Basis(Vector3.FORWARD, BANK) # roll toward the centre: the right wing (+X, inner side) goes down
	return Transform3D(b, pos)


## True when `shooter` may damage this drone (enemies only).
func hittable_by(shooter_team: int, shooter_peer: int) -> bool:
	return _falling < 0.0 and Game.is_enemy_ids(shooter_team, team, shooter_peer, owner_peer)


## Authority: a hit from `shooter_peer` with weapon `weapon_id`.
func damage(amount: float, shooter_peer: int, shooter_team: int, weapon_id: StringName) -> void:
	if collision_layer == 0 or amount <= 0.0 or not hittable_by(shooter_team, shooter_peer):
		return
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0:
		Game.uav_shot_down(self, shooter_peer, shooter_team, weapon_id)


## Seconds of radar this drone still gives (0 when falling or done).
func remaining() -> float:
	return 0.0 if _falling >= 0.0 else maxf(life - age, 0.0)


## Every machine: stop flying, spin down, explode after FALL_TIME.
func shoot_down() -> void:
	if _falling >= 0.0:
		return
	_falling = 0.0
	collision_layer = 0
	_fall_vel = -global_transform.basis.z * (TAU * radius / LAP_TIME) * 0.6
	if not Game.is_dedicated:
		Grenade.play_boom(global_position, false)


func _physics_process(delta: float) -> void:
	if _falling >= 0.0:
		_falling += delta
		_fall_vel.y -= 14.0 * delta
		global_position += _fall_vel * delta
		rotate_object_local(Vector3.FORWARD, 6.0 * delta)
		rotate_y(1.5 * delta)
		if _falling >= FALL_TIME:
			if not Game.is_dedicated:
				Grenade.play_boom(global_position, true)
			queue_free()
		return
	age += delta
	if age >= life:
		queue_free()
		return
	global_transform = path_transform(centre, radius, height, phase0, age)
	if _light:
		_light.light_energy = 2.0 + sin(age * 6.0) * 0.8 # slow team-coloured pulse


func _build_visual(col: Color) -> void:
	var model := MODEL.instantiate() as Node3D
	add_child(model)
	var box := _model_aabb(model, Transform3D.IDENTITY)
	var span := maxf(box.size.x, box.size.z)
	if span > 0.01:
		model.scale = Vector3.ONE * (WINGSPAN / span)
		model.position = -box.get_center() * model.scale
	model.rotation.y = MODEL_YAW_OFFSET
	model.position = Basis(Vector3.UP, MODEL_YAW_OFFSET) * model.position
	Weapon.no_shadows(model)
	_light = OmniLight3D.new()
	_light.light_color = col
	_light.omni_range = 7.0
	_light.position = Vector3(0, -0.6, 0)
	add_child(_light)
	var marker := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 0.1
	m.height = 0.2
	marker.mesh = m
	marker.material_override = CrystalMesh.glow_material(col)
	marker.position = Vector3(0, -0.3, 0)
	add_child(marker)


static func _model_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = t * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _model_aabb(c, t)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


## Live drone with this id, or null.
static func by_id(id: int) -> UavDrone:
	for d in Engine.get_main_loop().get_nodes_in_group("uav_drone"):
		if (d as UavDrone).net_id == id:
			return d
	return null


## Longest remaining radar of `team`'s live drones (FFA: `peer`'s), 0 if none.
static func team_remaining(team_id: int, peer: int, ffa: bool) -> float:
	var best := 0.0
	for d in Engine.get_main_loop().get_nodes_in_group("uav_drone"):
		var u := d as UavDrone
		if (ffa and u.owner_peer == peer) or ((not ffa) and u.team == team_id):
			best = maxf(best, u.remaining())
	return best


## Round end, killcam, leaving: no drone stays up.
static func clear_all() -> void:
	for d in Engine.get_main_loop().get_nodes_in_group("uav_drone"):
		(d as Node).queue_free()
