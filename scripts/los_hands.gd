class_name LosHands
extends CharacterBody3D
## LOS scorestreak (slot 2, 7 kills) — LOS 2.0 (#384 optie A). The pawn stays the body and keeps its
## line. For DURATION seconds the driver looks through this pair of hands and melees from here.
## A bash is a kill, and a kill no longer ends the streak: the body clicks to the hands, the hands
## fly on, the timer gets CHAIN_TIME back, and up to MAX_KILLS kills fit in one LOS. A bash picks the
## enemy in a 4 m / 45 deg cone and counts a hit anywhere along the short lunge toward it, like the
## shank (#373). The body keeps a crystal coconut while the hands are out: half damage, still killable.
## The hands have no HP: shooting them does nothing. The body dying ends it.
## Server decides hits, the chain, the timer and the coconut. Poses go out unreliable so one lost
## packet does not stall the rest.

const DURATION := 8.0 # #384: 5 s was short to find a target, close on it and land a bash
const SPEED := 14.0 # m/s, between sprint (11.4) and a full carry (18)
const CROUCH_SPEED := 3.5 # #384: crouch is the air brake, not a hover
const NEAR_SPEED := 9.0 # #384: within NEAR_M of an enemy the hands slow down for control
const NEAR_M := 6.0
const ACCEL := 48.0
const DASH_SPEED := 30.0 # #384: one short burst per LOS, right mouse button
const DASH_TIME := 0.12
const BASH_DAMAGE := 999.0 # lethal on purpose: one bash is one kill
const CHAIN_TIME := 3.0 # #384: every chain kill gives this back
const MAX_KILLS := 3 # #384: at most three kills in one LOS
const SNAP_PAUSE := 0.35 # s: the timer rests while the body clicks to the hands
const BASH_PICK_M := 4.0 # #384: the bash reaches for a target in this radius
const BASH_PICK_DEG := 45.0
const LUNGE_M := 3.0 # #384: how far the hands are pulled toward the picked target
const LUNGE_STEPS := 10 # #384: the hit counts anywhere along the lunge path
const COCONUT_SCALE := 0.5 # #384: damage taken while the body sits in the coconut
const EYE_H := 1.3 # m: where the hands leave the body, and how far the body lands under them
const SNAP_RADIUS := 0.45 # m: the body capsule plus a margin; a snap into a wall is worse than none
const SNAP_SKIN := 0.06 # m: the probe sits this far off the floor, so standing on it is not a hit
const SNAP_FLOOR := 0.5 # m: a landing needs floor this close under the feet
const COAST_MIN := 1.0 # m/s: slower than this, the body just stands
const ORIGIN_SLACK := 2.5 # m: a client's swing must start near the server's hands
const SNAP_SEARCH := [0.5, 1.0, 1.5, 2.0] # m: rings tried when the body does not fit under the hands
const SNAP_DIRS := 8
const WHOOSH := preload("res://assets/sounds/whoosh.wav")
const GROUP := &"los_hands"

var owner_peer := 0
var time_left := DURATION
var kills := 0 # #384: kills in this LOS, at most MAX_KILLS
var look := Vector3(0, 0, -1)
var _wish := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _cam: Camera3D
var _swing_cd := 0.0
var snap_m := 0.0 # hands↔body distance at the last swing, read by Style for LOS_LONG
var _pause := 0.0 # s: timer held while the body snaps into place (#384)
var _crouching := false
var _dash_used := false
var _dash_left := 0.0
var _dash_flag := false # client: one input frame carries the dash request
var _coconut: Node3D

static var _live: Dictionary = {} # peer id -> LosHands


static func for_owner(peer: int) -> LosHands:
	var n = _live.get(peer)
	if n is LosHands and is_instance_valid(n):
		return n
	return null


static func driving(p: Player) -> bool:
	return _for_player(p) != null


## The hands this machine is driving, if any. Offline the local peer is 1, same as online.
static func local() -> LosHands:
	return _for_player(Game.player_for_peer(Game.multiplayer.get_unique_id()))


static func _for_player(p: Player) -> LosHands:
	if p == null:
		return null
	var id := p.peer_id if p.peer_id != 0 else p._owner_peer()
	return for_owner(id)


## Hands↔body distance at the last swing. Style pays LOS_LONG from Style.LOS_LONG_M on.
static func snap_m_for(p: Player) -> float:
	var hands := _for_player(p)
	return hands.snap_m if hands else 0.0


## #384: kills in the LOS this pawn is driving, 0 when its hands are not out. Style pays LOS CHAIN
## from the second kill on.
static func kills_for(p: Player) -> int:
	var hands := _for_player(p)
	return hands.kills if hands else 0


## #384: the kill this bash is about to be, counted while the hit is resolved: 1 for the first KO of
## a LOS, 2 and 3 for the chain kills. Style reads it before the hands' counter moves.
static func chain_index_for(p: Player) -> int:
	var hands := _for_player(p)
	return hands.kills + 1 if hands else 0


## #384: the coconut. While the hands are out the body takes this share of the damage and stays
## killable; everyone else takes a full hit.
static func damage_scale(p: Player) -> float:
	return COCONUT_SCALE if _for_player(p) != null else 1.0


## #384: the driver's hand-streak count, for the HUD and the checks: [kills, MAX_KILLS, time_left].
static func state_for(p: Player) -> Array:
	var hands := _for_player(p)
	if hands == null:
		return [0, MAX_KILLS, 0.0]
	return [hands.kills, MAX_KILLS, hands.time_left]


## The local driver pressed the streak key again: end it now, without a snap.
## Only the server may end it (it owns the hands and the body), so a client asks.
static func recall_local() -> void:
	var hands := local()
	if hands and hands._drives_here():
		hands._request_recall()


## Server: a recall request from `peer`. No snap, the charge is already spent.
static func server_recall(peer: int) -> void:
	var hands := for_owner(peer)
	if hands:
		hands._end(true)


## Authority. False when the charge must be kept (already out, dead, a car is out, a bot).
static func launch(p: Player) -> bool:
	if p == null or p.is_dead or p.is_bot:
		return false
	if RcXd.for_owner(p.peer_id) != null:
		return false
	var id := p.peer_id if p.peer_id != 0 else p._owner_peer()
	if id == 0 or for_owner(id) != null:
		return false
	var hands := LosHands.new()
	hands.owner_peer = id
	hands._yaw = p.rotation.y
	hands._pitch = p.head.rotation.x if p.head else 0.0
	p.get_parent().add_child(hands)
	hands.global_position = p.global_position + Vector3.UP * EYE_H
	hands._pose_cam()
	_live[id] = hands
	hands._hide_body_hands(p, true)
	hands._take_view(p)
	hands._popup(p)
	hands._make_coconut(p)
	if Game.is_networked():
		Game.sync_los_spawn.rpc(id, hands.global_position, hands._yaw, hands._pitch)
	return true


## A client (or a late join) builds the visual. The driver's machine also coasts the body.
static func spawn_remote(peer_id: int, pos: Vector3, yaw: float, pitch: float) -> void:
	if for_owner(peer_id) != null:
		return
	var hands := LosHands.new()
	hands.owner_peer = peer_id
	hands._yaw = yaw
	hands._pitch = pitch
	var host := Game.get_tree().current_scene if Game.get_tree() else null
	if host == null:
		return
	host.add_child(hands)
	hands.global_position = pos
	hands._pose_cam()
	_live[peer_id] = hands
	var p := Game.player_for_peer(peer_id)
	if p:
		hands._hide_body_hands(p, true)
		hands._take_view(p)
		hands._popup(p)
		hands._make_coconut(p)


static func abort_for(peer: int, snap_to: Vector3 = Vector3.INF) -> void:
	var hands := for_owner(peer)
	if hands:
		hands._end(true, snap_to) # only the server actually sends sync_los_end


static func abort_all() -> void:
	var ids: Array = _live.keys()
	for id in ids:
		abort_for(int(id))


## Server: a swing request. The origin has to be the hands, not the body's eye.
static func server_swing(peer: int, origin: Vector3, dir: Vector3) -> void:
	var hands := for_owner(peer)
	if hands == null or dir.length_squared() < 0.0001:
		return
	if hands.global_position.distance_to(origin) > ORIGIN_SLACK:
		return
	if not Game.melee._take_cooldown(peer):
		return
	hands._resolve_swing(dir)


## Owner → server, every physics tick. Wish is world space and follows the look, so pitch climbs.
## #384 flags: bit 0 = crouch held (the air brake), bit 1 = a dash request for this tick.
static func server_input(peer: int, wish: Vector3, yaw: float, pitch: float, flags: int = 0) -> void:
	var hands := for_owner(peer)
	if hands == null or hands._drives_here():
		return
	hands._wish = wish
	if hands._wish.length() > 1.0:
		hands._wish = hands._wish.normalized()
	hands._yaw = yaw
	hands._pitch = pitch
	hands._crouching = (flags & 1) != 0
	if (flags & 2) != 0:
		hands._dash()


static func apply_pose(peer: int, pos: Vector3, vel: Vector3, yaw: float, pitch: float) -> void:
	var hands := for_owner(peer)
	if hands == null or hands._drives_here():
		return
	hands.global_position = pos
	hands.velocity = vel
	hands._yaw = yaw
	hands._pitch = pitch
	hands.rotation.y = yaw


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0 # not a target: the body is the thing you shoot
	collision_mask = 1
	motion_mode = MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	shape.shape = sphere
	add_child(shape)
	var shell := CrystalMesh.shell_material()
	for side in [-1.0, 1.0]:
		var hand := Node3D.new()
		add_child(hand)
		hand.position = Vector3(side * 0.16, -0.05, -0.12)
		CrystalBody.mesh_part(hand, &"hand", shell)
	_cam = Camera3D.new()
	_cam.fov = Game.fov if Game.fov > 1.0 else 90.0
	add_child(_cam)
	# Everyone else hears the hands leave. The driver gets Player.play_los_sfx instead, and a
	# dedicated server has no ears.
	if not _drives_here() and not Game.is_dedicated:
		var sfx := AudioStreamPlayer3D.new()
		sfx.stream = WHOOSH
		sfx.bus = "SFX"
		sfx.unit_size = 18.0
		sfx.max_distance = 45.0
		sfx.volume_db = -3.0
		add_child(sfx)
		sfx.play()


func _physics_process(delta: float) -> void:
	_swing_cd = maxf(_swing_cd - delta, 0.0)
	_dash_left = maxf(_dash_left - delta, 0.0)
	# #384: the timer rests while the body clicks into place after a chain kill.
	if _pause > 0.0:
		_pause = maxf(_pause - delta, 0.0)
	else:
		time_left -= delta
	var p := Game.player_for_peer(owner_peer)
	if time_left <= 0.0 or p == null or p.is_dead:
		_end(true)
		return
	if _drives_here():
		_read_stick()
		if Input.is_action_just_pressed("melee") or Input.is_action_just_pressed("fire"):
			_request_swing()
		if Input.is_action_just_pressed("zoom"):
			_dash()
	_fly(delta)
	if _drives_here() and Game.is_networked() and not multiplayer.is_server():
		Game.los_input.rpc_id(1, _wish, _yaw, _pitch, _flags())
		_dash_flag = false
	elif Game._is_match_authority() and Game.is_networked():
		Game.sync_los_pose.rpc(owner_peer, global_position, velocity, _yaw, _pitch)


## #384: the input bits the server needs: crouch held, and a dash request for this tick.
func _flags() -> int:
	var f := 0
	if _crouching:
		f |= 1
	if _dash_flag:
		f |= 2
	return f


## #384: one short burst per LOS, to close the last few metres or to break off.
func _dash() -> void:
	if _dash_used:
		return
	_dash_used = true
	var dir := look
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	velocity = dir.normalized() * DASH_SPEED
	_dash_left = DASH_TIME
	if Game.is_networked() and not multiplayer.is_server():
		_dash_flag = true


## #384: distance to the closest living enemy, INF when there is none. Drives the slow-down.
func _nearest_enemy() -> float:
	var p := Game.player_for_peer(owner_peer)
	if p == null or not is_inside_tree():
		return INF
	var best := INF
	for n in get_tree().get_nodes_in_group("player"):
		var v := n as Player
		if v == null or v == p or v.is_dead or v.is_queued_for_deletion():
			continue
		if not Game.is_enemy(v, p):
			continue
		best = minf(best, global_position.distance_to(v.global_position))
	return best


func _input(event: InputEvent) -> void:
	if not _drives_here() or not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	var sens := Player.MOUSE_SENS * Game.mouse_sens
	var look_y := motion.relative.y
	if Game.invert_y:
		look_y = -look_y
	_yaw -= motion.relative.x * sens
	_pitch -= look_y * sens
	_pitch = clampf(_pitch, -Player.MAX_PITCH, Player.MAX_PITCH)
	get_viewport().set_input_as_handled()


## The machine that owns the body also flies the hands. Everyone else takes the pose.
func _drives_here() -> bool:
	var p := Game.player_for_peer(owner_peer)
	return p != null and p.is_local()


func _read_stick() -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# #384: crouch is the air brake; the cap is applied in _fly.
	_crouching = Input.is_action_pressed("crouch")
	_pose_cam()
	# W/S fly along the look, so pitching up climbs and pitching down dives. A/D stay level.
	var side := global_transform.basis.x
	side.y = 0.0
	if side.length_squared() > 0.0001:
		side = side.normalized()
	var aim := look if look.length_squared() > 0.0001 else -global_transform.basis.z
	aim = aim.normalized()
	_wish = side * input.x + aim * (-input.y)
	if _wish.length_squared() > 1.0:
		_wish = _wish.normalized()


## Yaw on the body, pitch on the camera, look along the pitched camera. The body pawn is not turned.
func _pose_cam() -> void:
	rotation.y = _yaw
	if _cam:
		_cam.rotation.x = _pitch
		look = -_cam.global_transform.basis.z
	else:
		look = -global_transform.basis.z


func _fly(delta: float) -> void:
	# #384: a dash is a short burst that holds its line; steering waits until it is over.
	if _dash_left > 0.0:
		move_and_slide()
		return
	# No gravity. The cap is the whole velocity, so a climb is not free extra speed. Crouch brakes
	# hard, and close to an enemy the hands slow down so a bash can actually be lined up.
	var cap := SPEED
	if _crouching:
		cap = CROUCH_SPEED
	elif _nearest_enemy() <= NEAR_M:
		cap = NEAR_SPEED
	var v := Movement.accelerate(velocity, _wish, cap, ACCEL, delta)
	if v.length() > cap:
		v = v.normalized() * cap
	velocity = v
	move_and_slide()


## Local driver pressed the streak key again: get out early, without a snap.
## The server owns the hands and the body, so a client only asks and the server ends it.
func _request_recall() -> void:
	if Game.is_networked() and not multiplayer.is_server():
		Game.los_recall.rpc_id(1)
		return
	_end(true)


func _request_swing() -> void:
	if _swing_cd > 0.0:
		return
	var p := Game.player_for_peer(owner_peer)
	if p == null or p.weapon == null or not p.weapon.melee_ready():
		return
	_swing_cd = Melee.COOLDOWN
	p.weapon.play_melee()
	var dir := look
	if Game.is_networked() and not multiplayer.is_server():
		Game.los_melee.rpc_id(1, global_position, dir)
		return
	if Game.melee:
		Game.melee._take_cooldown(owner_peer)
	_resolve_swing(dir)


func _resolve_swing(dir: Vector3) -> void:
	var p := Game.player_for_peer(owner_peer)
	if p == null or Game.melee == null:
		return
	# #384: pick the enemy in the 4 m / 45 deg cone and pull the hands toward it; the hit counts
	# anywhere along that short path, so flying past a body at 14 m/s no longer means a miss.
	var start := global_position
	var target := Melee.pick_target(start, dir, p, BASH_PICK_M, BASH_PICK_DEG)
	var aim := dir
	var step := 0.0
	if target != null:
		var to := Vector3(target.global_position.x - start.x, 0.0, target.global_position.z - start.z)
		if to.length_squared() > 0.0001:
			aim = to.normalized()
		step = minf(start.distance_to(target.global_position), LUNGE_M) / float(LUNGE_STEPS)
	# Measure the snap now: Style scores it inside resolve, and the body moves right after.
	snap_m = start.distance_to(p.global_position)
	var res := {}
	var samples := LUNGE_STEPS if target != null else 1
	for i in samples:
		var at := start + aim * (step * float(i))
		res = Game.melee.resolve(p, at, aim, Melee.RANGE, BASH_DAMAGE)
		if bool(res.get("hit", false)):
			global_position = at # the hands stop where the hit landed; the body follows them there
			break
	var hit := bool(res.get("hit", false))
	if hit and p.weapon:
		p.weapon.play_melee_hit()
		if p.is_local():
			Game.hit_confirmed.emit(bool(res.get("killed", false)), false)
			p.weapon.play_hit_feedback(bool(res.get("killed", false)), false)
	if Game.is_networked() and multiplayer.is_server():
		Game.melee.sync_melee.rpc(owner_peer, hit)
		if hit:
			Game.notify_hit.rpc_id(owner_peer, bool(res.get("killed", false)), false)
	if hit:
		_chain(p)


## #384: a hit no longer ends LOS. The body clicks to the hands, the hands fly on from there, the
## timer gets CHAIN_TIME back, and at MAX_KILLS the streak ends on its own.
func _chain(p: Player) -> void:
	kills += 1
	time_left += CHAIN_TIME
	_pause = SNAP_PAUSE
	var landing := _landing()
	if landing.is_finite():
		p.apply_snap(landing)
	if p.is_local():
		p.play_los_sfx(0.7)
		var hud := Game.get_tree().get_first_node_in_group("hud") as Hud
		if hud and kills < MAX_KILLS:
			hud.show_los("Ketting %d/%d." % [kills, MAX_KILLS], p.team_id)
	if kills >= MAX_KILLS:
		_end(true, Vector3.INF)


## Where the body would stand under the hands, or INF when it would not.
## The hands are a 0.18 m sphere. The body is a crouchable capsule, and the eye line of a standing
## pawn put under a crouched target used to compute feet below the floor: one sphere at chest
## height missed that, the body was shoved through the ground, and nothing brought it back.
## A spot counts when the standing capsule and the crouched capsule both fit, and a short ray
## finds floor under the feet. Anything else leaves the body where it is.
func _landing() -> Vector3:
	var p := Game.player_for_peer(owner_peer)
	if p == null:
		return Vector3.INF
	var eye := EYE_H
	if p.head:
		eye = maxf(p.head.global_position.y - p.global_position.y, 0.6)
	var target := Vector3(global_position.x, global_position.y - eye, global_position.z)
	var space := p.get_world_3d().direct_space_state
	if _spot_ok(space, target):
		return target
	# The hands fit where the body does not (nose in a corner, under a ledge). Look around them
	# before giving up: the nearest free spot beats no snap at all.
	for r in SNAP_SEARCH:
		for i in SNAP_DIRS:
			var a := TAU * float(i) / float(SNAP_DIRS)
			var c := target + Vector3(cos(a), 0.0, sin(a)) * float(r)
			if _spot_ok(space, c):
				return c
	return Vector3.INF


## Feet at `feet` can hold this pawn: both stances clear the world, and there is floor underneath.
func _spot_ok(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	if not _floor_under(space, feet):
		return false
	return _capsule_free(space, feet, Player.STAND_CAPSULE) and _capsule_free(space, feet, Player.CROUCH_CAPSULE)


func _capsule_free(space: PhysicsDirectSpaceState3D, feet: Vector3, height: float) -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = SNAP_RADIUS
	probe.height = maxf(height, probe.radius * 2.0 + 0.01)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.collision_mask = Melee.WORLD_MASK
	q.margin = 0.0
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (probe.height * 0.5 + SNAP_SKIN))
	return space.intersect_shape(q, 1).is_empty()


func _floor_under(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.2, feet + Vector3.DOWN * SNAP_FLOOR)
	q.collision_mask = Melee.WORLD_MASK
	return not space.intersect_ray(q).is_empty()


func _take_view(p: Player) -> void:
	if not p.is_local():
		return
	Game.los_view = true
	p.los_coast = true
	p.play_los_sfx(1.15) # the hands leave the body: higher, lighter than a carry whoosh
	if p.weapon:
		p.weapon.visible = false # the gun is gone; the click is the hand
	if p.camera:
		p.camera.current = false
	if _cam:
		_cam.current = true
	# #384: only the driver sees the outlines and the bash marker.
	add_child(LosOutline.new())


## #384: the crystal coconut around the body. Every machine builds it (the spawn RPC reaches all of
## them), so the other team sees the glint too and knows a bash is coming. The body stays killable.
func _make_coconut(p: Player) -> void:
	if _coconut != null or p == null or p.body_mesh == null:
		return
	var shell := MeshInstance3D.new()
	shell.name = "LosCoconut"
	var sphere := SphereMesh.new()
	sphere.radius = 0.62
	sphere.height = 2.0
	# Few segments on purpose: a faceted crystal shell, not a smooth balloon.
	sphere.radial_segments = 8
	sphere.rings = 4
	shell.mesh = sphere
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.94, 1.0, 0.1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.roughness = 0.05
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.rim_enabled = true
	m.rim = 1.0
	m.rim_tint = 0.7
	m.emission_enabled = true
	m.emission = Color(0.3, 0.6, 0.8)
	m.emission_energy_multiplier = 0.18
	shell.material_override = m
	shell.position = Vector3(0.0, 1.0, 0.0)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(shell)
	_coconut = shell


func _hide_body_hands(p: Player, hidden: bool) -> void:
	var crystal: CrystalBody = null
	if p.body_mesh:
		crystal = p.body_mesh.get_node_or_null("Crystal") as CrystalBody
	if crystal and crystal.hands:
		crystal.hands.visible = not hidden
	if p.camera:
		var view := p.camera.get_node_or_null("ViewHands")
		if view:
			view.visible = not hidden


func _popup(p: Player) -> void:
	var hud := Game.get_tree().get_first_node_in_group("hud") as Hud
	if hud == null or p == null:
		return
	if p.is_local():
		hud.show_los("Handen los.", p.team_id)


## `snap_to`: a landed bash puts the body there. INF means the streak just ran out or the body died.
func _end(tell_net: bool, snap_to: Vector3 = Vector3.INF) -> void:
	if not _live.has(owner_peer):
		return
	_live.erase(owner_peer)
	if _coconut and is_instance_valid(_coconut):
		_coconut.queue_free()
		_coconut = null
	var p := Game.player_for_peer(owner_peer)
	if p:
		p.los_coast = false
		_hide_body_hands(p, false)
		# Move the body first, so the camera that comes back is already in the new spot.
		if snap_to.is_finite():
			p.apply_snap(snap_to)
		# A snap lands heavy, a recall or a timeout just settles back into the body.
		if p.is_local():
			p.play_los_sfx(0.7 if snap_to.is_finite() else 0.95)
		if p.is_local():
			Game.los_view = false
			p._yaw = _yaw
			p.rotation.y = _yaw
			p._pitch = _pitch
			if p.head:
				p.head.rotation.x = _pitch
			p.make_active_camera()
			if p.weapon and not p.is_dead:
				p.weapon.visible = true
	if tell_net and Game.is_networked() and multiplayer.is_server():
		Game.sync_los_end.rpc(owner_peer, snap_to)
	queue_free()
