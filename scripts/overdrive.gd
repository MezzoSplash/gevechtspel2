class_name Overdrive
extends Node
## Overdrive (#388): the 10 s movement streak. Everything about it is a buff on the body, so it lives
## on the pawn like the LOS hands do: one node per owner, in the GROUP, on every machine.
##
## The server owns the clock, the extension and the stats; a client's copy is a countdown for the HUD
## and the glow. Movement is predicted on the owner's machine, so the buffs are read on every machine
## (speed, wallrun, dive, lunge, style) and the server's position check (#B1) accepts the higher speed
## while it is running — otherwise the server pulls the sprinter back.
##
## Being visible and audible is part of the design: the enemy must be able to see the glow and hear it
## coming, or a 25% faster body with a lunge on every gun is simply unfair.

const GROUP := "overdrive"
const DURATION := 10.0
const EXTEND := 2.0 # s per kill while it runs
const MAX_TIME := 16.0 # the ceiling for DURATION + extensions
const SPEED_MULT := 1.25
const STYLE_MULT := 2
const GLOW_COLOR := Color(1.0, 0.36, 0.86)
const GLOW_RADIUS := 0.78
const TRAIL_AMOUNT := 64
const SFX := "res://assets/sounds/combo_special.wav"
## The claim check (#B1) is a fixed speed cap; while Overdrive runs it gets SPEED_MULT of headroom plus
## a little, so a sprint at 14 m/s is not read as a teleport.
const CLAIM_BONUS := 1.35

var owner_peer := 0
var time_left := DURATION
var _glow: MeshInstance3D
var _trail: CPUParticles3D
var _sfx: AudioStreamPlayer3D
var _hud_t := 0.0

static var _live: Dictionary = {} # owner_peer -> Overdrive


static func for_owner(peer: int) -> Overdrive:
	return _live.get(peer, null)


## Is this pawn's Overdrive running on this machine?
static func active(p: Player) -> bool:
	return _for_player(p) != null


static func _for_player(p: Player) -> Overdrive:
	if p == null or not p.is_inside_tree():
		return null
	return _live.get(_peer_of(p), null)


static func _peer_of(p: Player) -> int:
	return p.peer_id if p.peer_id != 0 else p._owner_peer()


## Seconds left on this pawn's Overdrive, 0 when it is not running. The HUD and the checks read this.
static func time_for(p: Player) -> float:
	var o := _for_player(p)
	return o.time_left if o else 0.0


## #B1: the speed cap a claim is judged against. Normal play keeps the plain cap.
static func claim_cap_mult(p: Player) -> float:
	return CLAIM_BONUS if active(p) else 1.0


static func speed_mult(p: Player) -> float:
	return SPEED_MULT if active(p) else 1.0


static func style_mult(p: Player) -> int:
	return STYLE_MULT if active(p) else 1


## Overdrive lends the shank's lunge to whatever is in your hands.
static func lunges(p: Player) -> bool:
	return active(p)


static func wallrun_free(p: Player) -> bool:
	return active(p)


static func dive_free(p: Player) -> bool:
	return active(p)


## Match authority (server, or offline): start the buff on `p`. A second one on the same pawn only
## refreshes the clock, it never stacks.
static func launch(p: Player) -> bool:
	if p == null or p.is_dead or Game.play_locked():
		return false
	if not Game._is_match_authority():
		return false
	var existing := _for_player(p)
	if existing:
		existing.time_left = minf(maxf(existing.time_left, DURATION), MAX_TIME)
		_publish(existing)
		return true
	var o := Overdrive.new()
	o.owner_peer = _peer_of(p)
	o.time_left = DURATION
	o.name = "Overdrive%d" % o.owner_peer
	p.add_child(o)
	_live[o.owner_peer] = o
	o._build_fx(p)
	_publish(o)
	return true


## Server → everyone: the buff is running for `peer` with `seconds` left. Clients build the visuals
## from this, so the enemy sees the glow and hears the cue.
static func spawn_remote(peer: int, seconds: float) -> void:
	var p := Game.player_for_peer(peer)
	if p == null or for_owner(peer) != null:
		return
	var o := Overdrive.new()
	o.owner_peer = peer
	o.time_left = seconds
	o.name = "Overdrive%d" % peer
	p.add_child(o)
	_live[peer] = o
	o._build_fx(p)


## Server: a kill while it runs adds EXTEND, up to MAX_TIME, and every machine hears the new clock.
static func server_kill(peer: int) -> void:
	var o := _live.get(peer, null) as Overdrive
	if o == null:
		return
	o.time_left = minf(o.time_left + EXTEND, MAX_TIME)
	_publish(o)


## Everyone: the new clock, after an extension.
static func sync_time(peer: int, seconds: float) -> void:
	var o := _live.get(peer, null) as Overdrive
	if o == null:
		return
	o.time_left = maxf(o.time_left, seconds)


## Server → everyone: over.
static func abort_for(peer: int, tell_net := true) -> void:
	var o := _live.get(peer, null) as Overdrive
	if o == null:
		return
	o._end(tell_net)


static func abort_all() -> void:
	for id in _live.keys():
		abort_for(int(id))


## Kills double their style while it runs: read by the style payout on the authority.
static func style_points(p: Player, pts: int) -> int:
	return pts * style_mult(p)


static func _publish(o: Overdrive) -> void:
	if not Game.is_networked() or not Game.multiplayer.is_server():
		return
	Game.sync_overdrive.rpc(o.owner_peer, o.time_left)


func _physics_process(delta: float) -> void:
	if not Game._is_match_authority():
		# The server's sync_overdrive_end closes it; this clock only drives the glow and the HUD.
		time_left = maxf(time_left - delta, 0.0)
		_fx_tick(delta)
		return
	time_left -= delta
	_fx_tick(delta)
	if time_left <= 0.0:
		_end(true)


func _end(tell_net: bool) -> void:
	if not _live.has(owner_peer):
		return
	_live.erase(owner_peer)
	if tell_net and Game.is_networked() and Game.multiplayer.is_server():
		Game.sync_overdrive_end.rpc(owner_peer)
	var p := Game.player_for_peer(owner_peer)
	if p and p.is_local():
		var hud := Game.get_tree().get_first_node_in_group("hud") as Hud
		if hud:
			hud.show_overdrive(0.0)
	queue_free()


## The glow around the body and a trail behind it. Built on every machine, so the other team sees it.
func _build_fx(p: Player) -> void:
	_glow = MeshInstance3D.new()
	_glow.name = "OverdriveGlow"
	var sphere := SphereMesh.new()
	sphere.radius = GLOW_RADIUS
	sphere.height = GLOW_RADIUS * 3.1
	sphere.radial_segments = 10
	sphere.rings = 5
	_glow.mesh = sphere
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.16)
	m.emission_enabled = true
	m.emission = GLOW_COLOR
	m.emission_energy_multiplier = 0.55
	_glow.material_override = m
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = Vector3(0.0, 1.05, 0.0)
	p.add_child(_glow)

	_trail = CPUParticles3D.new()
	_trail.name = "OverdriveTrail"
	_trail.amount = TRAIL_AMOUNT
	_trail.lifetime = 0.6
	_trail.emitting = true
	_trail.gravity = Vector3.ZERO
	# Local space with a backward push: the trail streams behind the body no matter how it moves, which
	# is what a speed buff should look like to the player watching it come at them.
	_trail.local_coords = true
	_trail.direction = Vector3(0.0, 0.0, 1.0)
	_trail.spread = 10.0
	_trail.initial_velocity_min = 2.0
	_trail.initial_velocity_max = 3.5
	_trail.scale_amount_min = 0.14
	_trail.scale_amount_max = 0.3
	_trail.color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.8)
	_trail.position = Vector3(0.0, 0.9, 0.0)
	var draw := BoxMesh.new()
	draw.size = Vector3(0.16, 0.16, 0.16)
	# Unlit and additive, so the trail reads as light instead of grey cubes.
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.vertex_color_use_as_albedo = true
	tm.albedo_color = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.85)
	draw.material = tm
	_trail.mesh = draw
	p.add_child(_trail)

	_sfx = AudioStreamPlayer3D.new()
	_sfx.name = "OverdriveSfx"
	var stream := load(SFX) as AudioStream
	if stream:
		_sfx.stream = stream
	_sfx.unit_size = 40.0 # heard from far: the enemy must hear it coming
	_sfx.max_distance = 140.0
	_sfx.pitch_scale = 0.72
	p.add_child(_sfx)
	if _sfx.stream:
		_sfx.play()


func _fx_tick(delta: float) -> void:
	if _glow and is_instance_valid(_glow):
		var t := Time.get_ticks_msec() * 0.001
		_glow.scale = Vector3.ONE * (1.0 + 0.05 * sin(t * 9.0))
	_hud_t += delta
	var p := Game.player_for_peer(owner_peer)
	if p == null or not p.is_local():
		return
	if _hud_t >= 0.1:
		_hud_t = 0.0
		var hud := Game.get_tree().get_first_node_in_group("hud") as Hud
		if hud:
			hud.show_overdrive(time_left)
