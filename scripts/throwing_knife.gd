class_name ThrowingKnife
extends Node3D
## Throwing knife (grenade slot, key F). The server steps the flight with rays: a fast, flat arc
## (a third of normal gravity) that kills on any body hit and sticks in walls for a moment.
## Clients get the start (spawn RPC) and the end (done RPC) and fly a visual copy in between with
## the same numbers, so it lines up without streaming poses. Not retrieved: it fades after STICK_TIME.

const SPEED := 30.0 # m/s along the aim
const LIFT := 1.2 # m/s up at the release, so the arc reads as a throw
const GRAVITY_SCALE := 0.35
const DAMAGE := 200.0 # one hit, any body part (spawn protection still blocks it)
const MAX_FLIGHT := 1.6 # s before a miss into the sky is dropped (~48 m)
const STICK_TIME := 2.0
const SPIN := 22.0 # rad/s end over end (visual only)
const HURT_MASK := 1 | 2 | 4

var thrower_id := 0
var thrower_team := 0
var velocity := Vector3.ZERO
var origin := Vector3.ZERO
var airborne := false # thrower was in the air or surfing at the release (YEET x2)
var is_visual := false # client copy: no hits, the server says where it ends
var _net_id := 0
var _flight := 0.0
var _stuck_left := -1.0
var _spin_pivot: Node3D
var _exclude: Array[RID] = []


static func launch(thrower: Player, from: Vector3, dir: Vector3) -> ThrowingKnife:
	var k := ThrowingKnife.new()
	k.thrower_id = thrower.peer_id
	k.thrower_team = thrower.team_id
	k.origin = from
	k.velocity = initial_velocity(dir)
	k.airborne = thrower.air_time >= Style.AIR_MIN_TIME or thrower.style_surfing()
	k._exclude = Game.shot_exclude(thrower)
	k._net_id = Game.next_grenade_id()
	var root := thrower.get_tree().current_scene
	root.add_child(k)
	k.global_position = from
	k._face(k.velocity)
	if Game.is_networked():
		Game.sync_knife_spawn.rpc(k._net_id, from, k.velocity)
	return k


static func initial_velocity(dir: Vector3) -> Vector3:
	return dir.normalized() * SPEED + Vector3.UP * LIFT


## Where the knife is `t` seconds after the release, if nothing is hit (tests and clients use this).
static func position_at(from: Vector3, vel0: Vector3, t: float) -> Vector3:
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity")) * GRAVITY_SCALE
	return from + vel0 * t + Vector3.DOWN * (0.5 * g * t * t)


func _ready() -> void:
	add_to_group("knife") # killcam records it; Game.reset_session frees leftovers
	_spin_pivot = Node3D.new()
	add_child(_spin_pivot)
	var model := Weapon.KNIFE_SCENE.instantiate() as Node3D
	Weapon.no_shadows(model)
	_spin_pivot.add_child(model)
	# Modeled along +X; turn the tip down -Z (the flight direction). ~40 cm so it reads in flight.
	model.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	model.scale = Vector3.ONE * 1.25
	if not Game.is_dedicated and not is_visual:
		_play(preload("res://assets/sounds/knife_throw.wav"), -3.0)


func net_id() -> int:
	return _net_id


func _physics_process(delta: float) -> void:
	if _stuck_left >= 0.0:
		_stuck_left -= delta
		if _stuck_left <= 0.0:
			queue_free()
		return
	_flight += delta
	if _spin_pivot:
		_spin_pivot.rotation.x -= SPIN * delta
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity")) * GRAVITY_SCALE
	velocity.y -= g * delta
	var motion := velocity * delta
	if is_visual:
		_visual_step(motion)
	else:
		_server_step(motion)
	if _flight >= MAX_FLIGHT and _stuck_left < 0.0 and not is_queued_for_deletion():
		if not is_visual and Game.is_networked():
			Game.sync_knife_done.rpc(_net_id, global_position, Vector3.ZERO, false)
		queue_free()


func _server_step(motion: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + motion)
	query.collision_mask = HURT_MASK
	query.exclude = _exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position = from + motion
		_face(velocity)
		return
	var victim := hit.collider as Player
	if victim:
		var enemy := victim.peer_id != thrower_id and Game.is_enemy_ids(thrower_team, victim.team_id, thrower_id, victim.peer_id)
		if victim.is_dead or not enemy:
			_exclude.append(victim.get_rid()) # dead or friendly body: fly on
			global_position = from + motion
			return
		Game.knife_hit(self, victim, hit.position, hit.normal)
		_finish(hit.position, Vector3.ZERO, false)
		return
	_finish(hit.position, hit.normal, true)


## Clients: world only (players are where the server says). The done RPC has the last word.
func _visual_step(motion: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position
	var query := PhysicsRayQueryParameters3D.create(from, from + motion)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position = from + motion
		_face(velocity)
		return
	stick(hit.position, hit.normal) # the server will confirm (or move it) in a moment


## Server: show it, tell clients, then stick or vanish.
func _finish(pos: Vector3, normal: Vector3, stuck: bool) -> void:
	if Game.is_networked():
		Game.sync_knife_done.rpc(_net_id, pos, normal, stuck)
	if stuck:
		stick(pos, normal)
	else:
		if not Game.is_dedicated:
			_play(preload("res://assets/sounds/melee_hit.wav"), -4.0)
		queue_free()


func stick(pos: Vector3, normal: Vector3) -> void:
	if _stuck_left >= 0.0:
		global_position = pos - velocity.normalized() * 0.08
		return
	_stuck_left = STICK_TIME
	global_position = pos - velocity.normalized() * 0.08 # the blade sinks in, the handle sticks out
	_face(velocity)
	if _spin_pivot:
		_spin_pivot.rotation.x = 0.0
	if not Game.is_dedicated and normal != Vector3.ZERO:
		_play(preload("res://assets/sounds/knife_hit.wav"), -2.0)


func _face(v: Vector3) -> void:
	if v.length_squared() < 0.0001 or not is_inside_tree():
		return
	var up := Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.FORWARD
	look_at(global_position + v, up)


func _play(stream: AudioStream, db: float) -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = stream
	s.volume_db = db
	s.bus = "SFX"
	s.unit_size = 5.0
	s.max_distance = 45.0
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return
	scene.add_child(s)
	s.global_position = global_position
	s.play()
	s.finished.connect(s.queue_free)
