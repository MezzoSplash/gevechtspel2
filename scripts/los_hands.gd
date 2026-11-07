class_name LosHands
extends CharacterBody3D
## LOS scorestreak (# slot 2, 7 kills). The pawn stays the body and keeps its line.
## For DURATION seconds the driver looks through this pair of hands and melees from here.
## One bash from the hands is a kill, and that hit is the payoff: the body snaps to the hands
## and the streak ends right there, so the whole thing is a way to get somewhere you could not walk.
## The hands have no HP: shooting them does nothing. The body dying ends it.
## Server decides the bash. Poses go out unreliable so one lost packet does not stall the rest.

const DURATION := 5.0 # 3 s was tight for a 2 m bash at 14 m/s; five leaves room to line one up
const SPEED := 14.0 # m/s, between sprint (11.4) and a full carry (18)
const ACCEL := 48.0
const BASH_DAMAGE := 999.0 # lethal on purpose: the hands get a few swings, but only a hit counts
const EYE_H := 1.3 # m: where the hands leave the body, and how far the body lands under them
const SNAP_RADIUS := 0.45 # m: the body capsule plus a margin; a snap into a wall is worse than none
const COAST_MIN := 1.0 # m/s: slower than this, the body just stands
const ORIGIN_SLACK := 2.5 # m: a client's swing must start near the server's hands
const GROUP := &"los_hands"

var owner_peer := 0
var time_left := DURATION
var look := Vector3(0, 0, -1)
var _wish := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _cam: Camera3D
var _swing_cd := 0.0

static var _live: Dictionary = {} # peer id -> LosHands


static func for_owner(peer: int) -> LosHands:
	var n = _live.get(peer)
	if n is LosHands and is_instance_valid(n):
		return n
	return null


static func driving(p: Player) -> bool:
	if p == null:
		return false
	var id := p.peer_id if p.peer_id != 0 else p._owner_peer()
	return for_owner(id) != null


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
static func server_input(peer: int, wish: Vector3, yaw: float, pitch: float) -> void:
	var hands := for_owner(peer)
	if hands == null or hands._drives_here():
		return
	hands._wish = wish
	if hands._wish.length() > 1.0:
		hands._wish = hands._wish.normalized()
	hands._yaw = yaw
	hands._pitch = pitch


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


func _physics_process(delta: float) -> void:
	time_left -= delta
	_swing_cd = maxf(_swing_cd - delta, 0.0)
	var p := Game.player_for_peer(owner_peer)
	if time_left <= 0.0 or p == null or p.is_dead:
		_end(true)
		return
	if _drives_here():
		_read_stick()
		if Input.is_action_just_pressed("melee") or Input.is_action_just_pressed("fire"):
			_request_swing()
	_fly(delta)
	if _drives_here() and Game.is_networked() and not multiplayer.is_server():
		Game.los_input.rpc_id(1, _wish, _yaw, _pitch)
	elif Game._is_match_authority() and Game.is_networked():
		Game.sync_los_pose.rpc(owner_peer, global_position, velocity, _yaw, _pitch)


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
	# No gravity. The 14 m/s cap is the whole velocity, so a climb is not free extra speed.
	var v := Movement.accelerate(velocity, _wish, SPEED, ACCEL, delta)
	if v.length() > SPEED:
		v = v.normalized() * SPEED
	velocity = v
	move_and_slide()


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
	# One bash is the whole payoff: three seconds of flying, one hit that counts.
	var res: Dictionary = Game.melee.resolve(p, global_position, dir, Melee.RANGE, BASH_DAMAGE)
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
		_snap_back()


## The payoff: the body snaps to where the hands just landed the hit, and the streak ends there.
## A blocked landing still ends the streak, it just leaves the body where it was.
func _snap_back() -> void:
	_end(true, _landing())


## Where the body would stand under the hands, or INF when the capsule would end up inside a wall.
## The hands are a 0.18 m sphere, the body a crouchable capsule: the hands fit in places the body
## does not, and a snap into geometry is worse than no snap.
func _landing() -> Vector3:
	var p := Game.player_for_peer(owner_peer)
	if p == null:
		return Vector3.INF
	var eye := EYE_H
	if p.head:
		eye = maxf(p.head.global_position.y - p.global_position.y, 0.6)
	var feet := Vector3(global_position.x, global_position.y - eye, global_position.z)
	var probe := SphereShape3D.new()
	probe.radius = SNAP_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.9)
	q.collision_mask = Melee.WORLD_MASK
	if not p.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
		return Vector3.INF
	return feet


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
	var p := Game.player_for_peer(owner_peer)
	if p:
		p.los_coast = false
		_hide_body_hands(p, false)
		# Move the body first, so the camera that comes back is already in the new spot.
		if snap_to.is_finite():
			p.apply_snap(snap_to)
			if p.is_local():
				p.play_los_sfx(0.85)
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
