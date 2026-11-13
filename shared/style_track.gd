class_name StyleTrack
extends RefCounted
## Style tracking for one pawn, out of scripts/player.gd (#106 split): turn history (for 360s), time
## with free space under the feet (for airshots), the movement claims the combo and the trick rules ask
## for (wallrun, dive, roll, wall jump, surf, drop), and the RUN & GUN clock.
##
## The track is pure state and stays off the network: it holds no node, no signal and no @rpc. Its owner
## runs it once per tick on the match authority only (`Player._physics_per_tick`), because those claims
## decide points in the style modes.
## The pawn stays the yardstick: the owner is `pawn`, a Player, so the rays here use its position, its
## rotation and its `_obs_speed` (speed from position deltas, which a remote human's snapshots drive).
##
## Everything that decides "did the server see this move" lives here in one place, on purpose: the
## thresholds are lenient (#B2) and a false "no" costs a player a real trick, so they are read together.

## Seconds of turn history kept: a 360 that takes longer is not a 360.
const KEEP := 1.5
const RAMP_REACH := 1.0 # m from the body centre (capsule radius ~0.45, plus slack)
const TELEPORT_M := 3.0 # one tick moving further than this is a teleport (snapshots move < 1 m)
## #B2: how far a wall may be for a claimed wallrun (or wall jump) to be believed. Generous on purpose:
## our own probe must never refuse a trick the player really did.
const CLAIM_WALL_PROBE := 1.2 # m
const IDLE_T := -100.0 # "never seen this, or long ago"

var pawn: Player
var clock := 0.0
var yaw_samples: Array = [] # [[t, signed yaw delta rad], ...] over the last KEEP seconds
var last_yaw := 0.0
var has_yaw := false
var in_air := false
var fall_peak := 0.0 # highest y since the feet left the ground
var landed_drop := 0.0 # metres of the last fall, from its peak
var landed_t := IDLE_T
var surf_seen_t := IDLE_T # last clock with a steep ramp beside or under us
var last_pos := Vector3.INF # teleports (respawn, admin moves) never count as a fall
var run_t := 0.0 # s above Style.RUN_GUN_SPEED without stopping (RUN & GUN)
var run_low_t := 0.0 # s below it since the last fast tick: past RUN_GUN_GRACE the run is over
var wallrun_seen_t := IDLE_T # last clock with move_fx == MOVE_WALLRUN
var walljump_seen_t := IDLE_T
var walljumps_seen := -1
var dive_seen_t := IDLE_T
var roll_seen_t := IDLE_T
var air_time := 0.0 # seconds with free space under the feet
var combo_surf := false
var combo_slide := false
var combo_air := false


func _init(owner_pawn: Player) -> void:
	pawn = owner_pawn


## Match authority, every pawn: turn history (for 360s) and time with free space under the feet
## (for airshots). Works from the pawn's position/rotation, so remote humans count the same as bots.
func tick(delta: float) -> void:
	var p := pawn
	clock += delta
	var yaw := p.rotation.y
	if has_yaw:
		var d := wrapf(yaw - last_yaw, -PI, PI)
		if absf(d) > 0.00001:
			yaw_samples.append([clock, d])
	last_yaw = yaw
	has_yaw = true
	while not yaw_samples.is_empty() and float(yaw_samples[0][0]) < clock - KEEP:
		yaw_samples.pop_front()
	if p.is_dead or not p.is_inside_tree():
		air_time = 0.0
		in_air = false
		return
	# #84: every new move feeds the combo (worth nothing until a kill lands it).
	# #B2: a claim only counts when the server can back it up itself. A client owns its pawn, so a
	# modified client would otherwise farm WALLRUN / DIVE / ROLL / WALLJUMP by lying — and in the style
	# modes those points decide the match. The local pawn and bots are trusted: their state is the sim.
	var trust := p.is_local() or p.is_bot
	var fx := p.move_fx
	if fx == Player.MOVE_WALLRUN and (trust or claim_backed(fx)):
		if clock - wallrun_seen_t > Style.MOVE_RECENT:
			var w2w := clock - walljump_seen_t <= Style.WALL_TO_WALL_WINDOW
			Game.combo_move(p.peer_id, Combo.WALL_TO_WALL if w2w else Combo.WALLRUN)
		wallrun_seen_t = clock
	elif fx == Player.MOVE_DIVE and (trust or claim_backed(fx)):
		if clock - dive_seen_t > Style.MOVE_RECENT:
			Game.combo_move(p.peer_id, Combo.DIVE)
		dive_seen_t = clock
	elif fx == Player.MOVE_ROLL and (trust or claim_backed(fx)):
		if clock - roll_seen_t > Style.MOVE_RECENT:
			Game.combo_move(p.peer_id, Combo.ROLL)
		roll_seen_t = clock
	if p.walljumps != walljumps_seen:
		if walljumps_seen >= 0 and (trust or claim_backed(Player.MOVE_WALLRUN)):
			walljump_seen_t = clock
			Game.combo_move(p.peer_id, Combo.WALLJUMP)
		walljumps_seen = p.walljumps
	tick_combo_moves()
	if p.global_position.distance_to(last_pos) > TELEPORT_M:
		in_air = false
		landed_drop = 0.0
		air_time = 0.0
	last_pos = p.global_position
	# A remote human's speed comes from snapshots, so one slow tick is not a stop; a real stop is longer.
	if p._obs_speed >= Style.RUN_GUN_SPEED:
		run_t += delta
		run_low_t = 0.0
	else:
		run_low_t += delta
		if run_low_t > Style.RUN_GUN_GRACE:
			run_t = 0.0
	var under := feet_ray()
	# Nothing under the feet, or only a ramp too steep to stand on: in the air (surfing counts).
	var steep := not under.is_empty() and float((under.normal as Vector3).y) < Player.SURF_MAX_NORMAL_Y
	if under.is_empty() or steep:
		air_time += delta
		var y := p.global_position.y
		if not in_air:
			in_air = true
			fall_peak = y
		fall_peak = maxf(fall_peak, y)
		if steep or ramp_beside():
			surf_seen_t = clock
			fall_peak = y # riding a ramp is not falling: DROP counts the free fall after it
	else:
		if in_air:
			landed_drop = fall_peak - p.global_position.y
			landed_t = clock
		in_air = false
		air_time = 0.0


## Is a claimed movement trick backed by what the server itself can see? The client owns its pawn, so
## move_fx and walljumps arrive as claims, and in the style modes those claims are points. Every test
## here uses something the authority observes for itself: the feet ray (`in_air`), the air time, the
## speed from the snapshots, and a wall probe. Lenient thresholds, because a false "no" costs a player
## a real trick, while a false "yes" only costs what a liar could already claim.
func claim_backed(fx: int) -> bool:
	match fx:
		Player.MOVE_WALLRUN:
			return in_air and pawn._obs_speed >= Player.WALLRUN_KEEP_SPEED * 0.8 and wall_beside()
		Player.MOVE_DIVE:
			return pawn._obs_speed >= Player.DIVE_MIN_SPEED * 0.7 or air_time > 0.2
		Player.MOVE_ROLL:
			return pawn._obs_speed >= Player.WALK_SPEED * 0.9
		_:
			return false


## A near-vertical wall within CLAIM_WALL_PROBE of the body centre: eight horizontal rays.
func wall_beside() -> bool:
	var from := pawn.global_position + Vector3(0.0, 0.9, 0.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var to := from + Vector3(cos(a), 0.0, sin(a)) * CLAIM_WALL_PROBE
		if _wall_at(from, to):
			return true
	return false


## In the air: a surf ramp (steeper than walkable, not a wall) touching the capsule's side?
## Eight rays from the body centre, angled down like the contact normal on a 45-85° ramp.
func ramp_beside() -> bool:
	var from := pawn.global_position + Vector3(0.0, 0.9, 0.0)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a)) * 0.82 + Vector3(0.0, -0.57, 0.0) # ~35° down
		var hit := _ray(from, from + dir * RAMP_REACH)
		if hit.is_empty():
			continue
		var ny := float((hit.normal as Vector3).y)
		if ny > Player.SURF_MIN_NORMAL_Y and ny < Player.SURF_MAX_NORMAL_Y:
			return true
	return false


## What is under the feet, within Style.AIR_GAP (empty = nothing solid in reach).
func feet_ray() -> Dictionary:
	var p := pawn
	return _ray(p.global_position + Vector3(0.0, 0.05, 0.0), p.global_position - Vector3(0.0, Style.AIR_GAP, 0.0))


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := pawn.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [pawn.get_rid()]
	return space.intersect_ray(query)


func _wall_at(from: Vector3, to: Vector3) -> bool:
	var hit := _ray(from, to)
	return not hit.is_empty() and absf(float((hit.normal as Vector3).y)) < Player.WALLRUN_MAX_NY


## #84, match authority: surf, slide and long air as combo moves (rising edges only).
## Slides are not synced, so the server reads one from the synced crouch plus the observed speed.
func tick_combo_moves() -> void:
	var p := pawn
	var surf := surfing()
	if surf and not combo_surf:
		Game.combo_move(p.peer_id, Combo.SURF)
	combo_surf = surf
	var slide := (not in_air) and p.crouch > 0.6 and p._obs_speed >= Player.SPRINT_SPEED * 0.9 \
			and p.move_fx != Player.MOVE_ROLL
	if slide and not combo_slide:
		Game.combo_move(p.peer_id, Combo.SLIDE)
	combo_slide = slide
	var air := air_time >= Combo.AIR_TIME and not surf and p.move_fx == Player.MOVE_NONE
	if air and not combo_air:
		Game.combo_move(p.peer_id, Combo.AIR)
	combo_air = air_time >= Combo.AIR_TIME


## Match authority (#80/#81): movement the server saw on this pawn just now (synced move_fx/walljumps).
func wallrun() -> bool:
	return clock - wallrun_seen_t <= Style.MOVE_RECENT


## A wall jump within WALLJUMP_RECENT, still in the air from it.
func walljump() -> bool:
	return clock - walljump_seen_t <= Style.WALLJUMP_RECENT and (in_air or pawn.move_fx == Player.MOVE_WALLRUN)


func dive() -> bool:
	return clock - dive_seen_t <= Style.MOVE_RECENT


func roll() -> bool:
	return clock - roll_seen_t <= Style.ROLL_RECENT


## Match authority: surfing right now (or within Style.SURF_RECENT).
func surfing() -> bool:
	return in_air and clock - surf_seen_t <= Style.SURF_RECENT


## Match authority: how far we fell, while falling or just after landing (0 otherwise).
func drop() -> float:
	if in_air:
		return maxf(fall_peak - pawn.global_position.y, 0.0)
	if clock - landed_t <= Style.DROP_RECENT:
		return maxf(landed_drop, 0.0)
	return 0.0


## Largest one-way turn in degrees during the last `window` seconds (match authority).
func spin_degrees(window: float = Style.SPIN_WINDOW) -> float:
	return Style.spin_degrees(yaw_samples, clock, window)


## Spawn, respawn or an admin move: the next tick must not read the jump as a fall.
func forget_position() -> void:
	last_pos = Vector3.INF


## New life: drop the turn history, the air time and every claim, but keep the object itself (the pawn
## holds other references to it, and a fresh one would let a stale copy keep scoring).
func reset() -> void:
	clock = 0.0
	yaw_samples.clear()
	last_yaw = 0.0
	has_yaw = false
	in_air = false
	fall_peak = 0.0
	landed_drop = 0.0
	landed_t = IDLE_T
	surf_seen_t = IDLE_T
	last_pos = Vector3.INF
	run_t = 0.0
	run_low_t = 0.0
	wallrun_seen_t = IDLE_T
	walljump_seen_t = IDLE_T
	walljumps_seen = -1
	dive_seen_t = IDLE_T
	roll_seen_t = IDLE_T
	air_time = 0.0
	combo_surf = false
	combo_slide = false
	combo_air = false
