class_name RcXd
extends CharacterBody3D
## RC-XD killstreak. The server body is the one that drives, takes damage, and explodes.
## The driver's machine also runs a local copy so the wheel does not wait on ping.
## Other clients only follow synced poses. One car per player.

const SPEED := 10.0
const REVERSE := 6.0
const TURN_RATE := 2.2 # rad/s added by A/D; the mouse sets yaw directly, raw
const LIFE := 25.0
const MAX_HP := 48.0 # two rifle hits (34)
const BLAST_RADIUS := 4.5
const BLAST_DAMAGE := 140.0
const SNAP_M := 2.0
const SEND_DT := 0.05
const WIDTH := 0.7
const HEIGHT := 0.45
const LENGTH := 1.1
const PITCH_MIN := -0.45
const PITCH_MAX := 0.40
const BODY_SCENE := preload("res://assets/gadgets/RCExplody.glb")
const INPUT_STALE := 0.25 # s without a packet: the remote car coasts to a stop

var owner_peer := 0
var owner_team := 0
var net_id := 0
var hp := MAX_HP
var life := LIFE
var yaw := 0.0
var authority_sim := false # server (or offline) body: damage and the blast happen here
var predict := false # driver's client copy, when they are not the server
var _pitch := 0.0
var _throttle := 0.0
var _net_yaw := 0.0
var _net_throttle := 0.0
var _input_age := 0.0
var _send_t := 0.0
var _ended := false
var _detonating := false # click is in: stop driving while the server blast catches up
var _cam: Camera3D


## Authority only. False if this player already has a car or there is no scene to put it in.
static func launch(driver: Player) -> bool:
	if driver == null or not driver.is_inside_tree() or driver.is_dead:
		return false
	if for_owner(driver.peer_id) != null:
		return false
	var scene := driver.get_tree().current_scene
	if scene == null:
		return false
	var car := RcXd.new()
	car.owner_peer = driver.peer_id
	car.owner_team = driver.team_id
	car.net_id = Game.next_rc_id()
	car.authority_sim = true
	car.yaw = driver.rotation.y
	car.name = "rc_%d" % car.net_id
	scene.add_child(car)
	car.global_position = _drop_point(driver)
	car.rotation.y = car.yaw
	if Game.is_networked():
		Game.sync_rc_spawn.rpc(car.net_id, car.owner_peer, car.owner_team, car.global_position, car.yaw)
	Game.announce_rc(car.owner_peer, car.owner_team)
	return true


## Client visual. The driver predicts; everyone else snaps to poses.
static func spawn_visual(net_id: int, peer: int, team: int, pos: Vector3, yaw_in: float) -> void:
	if by_id(net_id) != null:
		return
	var scene := (Engine.get_main_loop() as SceneTree).current_scene
	if scene == null:
		return
	var car := RcXd.new()
	car.net_id = net_id
	car.owner_peer = peer
	car.owner_team = team
	car.yaw = yaw_in
	car.authority_sim = false
	car.predict = peer == _local_peer()
	car.name = "rc_%d" % net_id
	scene.add_child(car)
	car.global_position = pos
	car.rotation.y = yaw_in


static func for_owner(peer: int) -> RcXd:
	for n in _cars():
		var c := n as RcXd
		if c and c.authority_sim and not c._ended and c.owner_peer == peer:
			return c
	return null


static func by_id(id: int) -> RcXd:
	for n in _cars():
		var c := n as RcXd
		if c and not c._ended and c.net_id == id:
			return c
	return null


static func authority_by_id(id: int) -> RcXd:
	var c := by_id(id)
	if c and c.authority_sim:
		return c
	return null


## Death, round end, killcam, leave: the car is gone and does not explode.
static func abort_for(peer: int) -> void:
	var c := for_owner(peer)
	if c:
		c.shutdown(false)


static func abort_all() -> void:
	for n in _cars():
		var c := n as RcXd
		if c == null or c._ended:
			continue
		if c.authority_sim:
			c.shutdown(false)
		else:
			c.dismiss_visual()


## Local driver died or left the view: drop the camera. The server copy is freed by abort_for.
static func release_view() -> void:
	Game.rc_view = false
	var hud := _hud()
	if hud:
		hud.set_rc_drive(false, 0.0, 0.0)
	var local := _local_player()
	if local:
		local.make_active_camera()
	for n in _cars():
		var c := n as RcXd
		if c and c.predict and not c.authority_sim and not c._ended:
			c.dismiss_visual()


static func _cars() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	return tree.get_nodes_in_group("rc_xd")


static func _drop_point(driver: Player) -> Vector3:
	var fwd := -driver.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var chest := driver.global_position + Vector3(0.0, 0.6, 0.0)
	var ahead := chest + fwd * 1.5
	var space := driver.get_world_3d().direct_space_state
	var wall := PhysicsRayQueryParameters3D.create(chest, ahead)
	wall.collision_mask = 1
	if not space.intersect_ray(wall).is_empty():
		ahead = chest
	var drop := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 1.2, ahead + Vector3.DOWN * 6.0)
	drop.collision_mask = 1
	var hit := space.intersect_ray(drop)
	if hit.is_empty():
		return driver.global_position + Vector3(0.0, HEIGHT * 0.5, 0.0)
	return hit.position + Vector3(0.0, HEIGHT * 0.5 + 0.02, 0.0)


func _ready() -> void:
	add_to_group("rc_xd")
	collision_layer = 4 # SHOT_MASK already includes this, so guns and knives hit the car
	collision_mask = 1 if authority_sim or predict else 0
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, LENGTH)
	shape.shape = box
	add_child(shape)
	_build_body()
	if _local_driver():
		_add_camera()
	rotation.y = yaw


func _exit_tree() -> void:
	# Freed without shutdown (scene leave): give the pawn its camera back. shutdown already cleared it.
	if _cam and _cam.current and _local_driver():
		_drop_camera()


func apply_remote_input(yaw_in: float, throttle_in: float) -> void:
	_net_yaw = yaw_in
	_net_throttle = clampf(throttle_in, -1.0, 1.0)
	_input_age = 0.0


func apply_net_pose(pos: Vector3, yaw_in: float, life_in: float) -> void:
	if _ended:
		return
	if predict:
		life = life_in
		if global_position.distance_to(pos) > SNAP_M:
			global_position = pos
			yaw = yaw_in
			rotation.y = yaw
			velocity = Vector3.ZERO
		return
	global_position = pos
	yaw = yaw_in
	rotation.y = yaw


func apply_hp(value: float) -> void:
	hp = clampf(value, 0.0, MAX_HP)
	_show_hud()


## Shots and knives. Destroying it does not splash, so shooting the car is safe.
func damage(amount: float) -> void:
	if not authority_sim or _ended or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_push_hp()
	if hp <= 0.0:
		shutdown(false)


func dismiss_visual() -> void:
	if _ended:
		return
	_ended = true
	_drop_camera()
	queue_free()


## `splash` is the detonator and the 25s timer. A shot, a death, or a round end passes false.
func shutdown(splash: bool) -> void:
	if _ended:
		return
	_ended = true
	var pos := global_position
	_drop_camera()
	if authority_sim and splash:
		_blast(pos)
		if not Game.is_dedicated:
			Grenade.play_boom(pos)
	if authority_sim and _rpc_live():
		Game.mark_rc_done(net_id)
		Game.sync_rc_end.rpc(net_id, pos, splash)
	queue_free()


func client_end(exploded: bool, pos: Vector3) -> void:
	if _ended:
		return
	_ended = true
	_drop_camera()
	if exploded and not Game.is_dedicated:
		Grenade.play_boom(pos)
	queue_free()


func _physics_process(delta: float) -> void:
	if _ended:
		return
	if authority_sim:
		_input_age += delta
		life -= delta
		if life <= 0.0:
			shutdown(true)
			return
		_step(delta)
		_publish_pose(delta)
	elif predict:
		_step(delta)
		_send_input(delta)
	if _local_driver():
		_show_hud()


func _input(event: InputEvent) -> void:
	if not _local_driver() or _ended or event.is_echo():
		return
	if Game.pause_open or Game.play_locked() or Game.chat_open:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var look_y := motion.relative.y
		if Game.invert_y:
			look_y = -look_y
		var sens := Player.MOUSE_SENS * Game.mouse_sens
		yaw -= motion.relative.x * sens
		_pitch = clampf(_pitch - look_y * sens, PITCH_MIN, PITCH_MAX)
		rotation.y = yaw
		if _cam:
			_cam.rotation.x = _pitch
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("fire"):
		_detonate()
		get_viewport().set_input_as_handled()


func _step(delta: float) -> void:
	_read_controls(delta)
	var rate := SPEED if _throttle >= 0.0 else REVERSE
	var wish := -global_transform.basis.z * _throttle * rate
	velocity.x = wish.x
	velocity.z = wish.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y += float(get_gravity().y) * delta
	move_and_slide()
	rotation.x = 0.0
	rotation.z = 0.0
	rotation.y = yaw


func _read_controls(delta: float) -> void:
	if _local_driver():
		if _detonating or Game.pause_open or Game.play_locked() or Game.chat_open:
			_throttle = 0.0
			return
		yaw += Input.get_axis("move_right", "move_left") * TURN_RATE * delta
		var forward := Input.get_action_strength("move_forward")
		var back := Input.get_action_strength("move_back")
		_throttle = clampf(forward - back, -1.0, 1.0)
		return
	yaw = _net_yaw
	_throttle = 0.0 if _input_age > INPUT_STALE else _net_throttle


func _send_input(delta: float) -> void:
	if not Game.is_networked():
		return
	_send_t -= delta
	if _send_t > 0.0:
		return
	_send_t = SEND_DT
	Game.rc_drive.rpc_id(1, net_id, yaw, _throttle)


func _publish_pose(delta: float) -> void:
	if not Game.is_networked():
		return
	_send_t -= delta
	if _send_t > 0.0:
		return
	_send_t = SEND_DT
	Game.sync_rc_pose.rpc(net_id, global_position, yaw, life)


func _detonate() -> void:
	if _ended or _detonating or Game.pause_open or Game.play_locked():
		return
	_detonating = true
	_throttle = 0.0
	if authority_sim:
		shutdown(true)
	elif predict and Game.is_networked():
		Game.rc_drive.rpc_id(1, net_id, yaw, 0.0)
		Game.rc_detonate.rpc_id(1, net_id)


## Same rules as the grenade: no teammates, the driver can still hurt their own pawn.
func _blast(pos: Vector3) -> void:
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead:
			continue
		if p.peer_id != owner_peer and p.team_id == owner_team and not Game.is_ffa():
			continue
		var dist := pos.distance_to(p.global_position + Vector3(0.0, 1.0, 0.0))
		if dist > BLAST_RADIUS or not _blast_reaches(pos, p):
			continue
		var dmg := BLAST_DAMAGE * (1.0 - dist / BLAST_RADIUS)
		p.apply_hit(p.global_position + Vector3(0, 1, 0), Vector3.UP, dmg, false, owner_peer, &"rcxd", 1.0, pos)


func _blast_reaches(pos: Vector3, p: Player) -> bool:
	var space := get_world_3d().direct_space_state
	for h in [1.0, 1.6, 0.3]:
		var query := PhysicsRayQueryParameters3D.create(pos, p.global_position + Vector3(0.0, h, 0.0))
		query.collision_mask = 1
		if space.intersect_ray(query).is_empty():
			return true
	return false


func _push_hp() -> void:
	if _local_driver():
		_show_hud()
	elif Game.is_networked() and authority_sim and owner_peer > 0:
		Game.sync_rc_hp.rpc_id(owner_peer, net_id, hp)


func _add_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "RcCam"
	_cam.fov = 80.0
	# Behind the low RCExplody body. The old spot sat over the roof and showed only the fenders.
	_cam.position = Vector3(0.0, 0.55, 0.85)
	add_child(_cam)
	_cam.current = true
	Game.rc_view = true
	_show_hud()


func _drop_camera() -> void:
	if _cam:
		_cam.current = false
	# Only the car this machine is driving may steal the view back. Aborting someone else's car must not.
	if not _local_driver():
		return
	Game.rc_view = false
	var hud := _hud()
	if hud:
		hud.set_rc_drive(false, 0.0, 0.0)
	var local := _local_player()
	if local and is_instance_valid(local):
		local.make_active_camera()


func _show_hud() -> void:
	var hud := _hud()
	if hud and _local_driver():
		hud.set_rc_drive(true, hp, life)


## RCExplody faces +Z. The car and its camera look down -Z, so the mesh is turned around.
## Scaled onto the existing hitbox: shots still use WIDTH / HEIGHT / LENGTH.
func _build_body() -> void:
	var model := BODY_SCENE.instantiate() as Node3D
	model.name = "Body"
	model.rotation.y = PI
	add_child(model)
	var bounds := _mesh_bounds(model)
	var span := maxf(bounds.size.z, 0.05)
	model.scale = Vector3.ONE * (LENGTH / span)
	bounds = _mesh_bounds(model)
	var mid := bounds.get_center()
	model.position -= Vector3(mid.x, bounds.position.y + HEIGHT * 0.5, mid.z)
	_add_team_mark(-HEIGHT * 0.5 + bounds.size.y)


func _mesh_bounds(model: Node3D) -> AABB:
	var acc := AABB()
	var has := false
	var stack: Array = [[model, model.transform]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var box: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
			acc = box if not has else acc.merge(box)
			has = true
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
			else:
				stack.append([child, xf])
	return acc if has else AABB(Vector3.ZERO, Vector3.ONE)


## The GLB uses one paint for both teams. The roof bar is how you tell them apart.
func _add_team_mark(top_y: float) -> void:
	var mark := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.02, 0.36)
	mark.mesh = box
	var paint := Player.team_color(owner_team)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = paint
	mat.emission_enabled = true
	mat.emission = paint
	mat.emission_energy_multiplier = 0.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.material_override = mat
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.position = Vector3(0.0, top_y - 0.005, 0.0)
	add_child(mark)


func _local_driver() -> bool:
	var p := Game.player_for_peer(owner_peer)
	return p != null and p.is_local()


func _rpc_live() -> bool:
	if not Game.is_networked():
		return false
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


static func _local_peer() -> int:
	if not Game.is_networked():
		return 1
	return Game.multiplayer.get_unique_id()


static func _hud() -> Hud:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("hud") as Hud


static func _local_player() -> Player:
	for n in _cars_players():
		var p := n as Player
		if p and p.is_local():
			return p
	return null


static func _cars_players() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return []
	return tree.get_nodes_in_group("player")
