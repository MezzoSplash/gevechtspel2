class_name MoveTick
extends RefCounted
## One physics tick of the local human's movement (#316), in phases: read the keys, jump, the wish
## direction and speed, the horizontal velocity, the vertical extras, move, and what follows the move.
## Static helpers on the pawn `p`, like Movement (whose primitives these phases call); Player keeps the
## state, the constants and the order of the tick in _physics_process. Nothing here is on the network.


static func run(p: Player, delta: float) -> void:
	var input_locked := read_keys(p, delta)
	var on_floor := p.is_on_floor()
	p._try_start_slide(on_floor, input_locked)
	p._try_air_dive(on_floor, input_locked)
	p._update_stance(delta, on_floor)
	p._tick_grapple_input(on_floor, input_locked, delta)
	var jumped := tick_jump(p, delta, on_floor, input_locked)
	var input_vec := Vector2.ZERO
	if not p.is_dead and not input_locked:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var w := wish(p, input_vec, on_floor, input_locked)
	var lunging := p._lunge_left > 0.0
	var horiz := horizontal(p, w[0], w[1], jumped, on_floor, delta)
	if p._wallrunning and not lunging:
		horiz = p._wallrun_horiz(horiz, w[0], delta)
	p.velocity.x = horiz.x
	p.velocity.z = horiz.z
	vertical(p, on_floor, delta)
	var pre_move := p.velocity
	p.move_and_slide()
	after_move(p, pre_move, jumped, on_floor, input_vec, input_locked, delta)


## Every menu or lock that takes the keys away from the pawn: chat, the pause menu, a round freeze or
## killcam, the RC view, LOS. The pause menu was missing here once, so the local pawn kept walking,
## sprinting and jumping behind the menu while only look and fire were blocked. LOS locks the stick but
## does not zero the velocity: the body keeps the line it had. Returns whether the keys are locked.
static func read_keys(p: Player, delta: float) -> bool:
	var locked := Game.chat_open or Game.pause_open or Game.play_locked() or Game.rc_view or Game.los_view
	# The movement keys, once per tick. Movement itself never touches Input any more (see _in_sprint).
	p._in_sprint = (not locked) and Input.is_action_pressed("sprint")
	p._in_crouch = (not locked) and Input.is_action_pressed("crouch")
	p._in_crouch_down = (not locked) and Input.is_action_just_pressed("crouch")
	p._carry_t = maxf(p._carry_t - delta, 0.0)
	p._kb_t = maxf(p._kb_t - delta, 0.0)
	p._tick_strip_cd(delta)
	if Game.rc_view:
		p._sliding = false
		p.velocity.x = 0.0
		p.velocity.z = 0.0
	return locked


## Gravity in the air, the jump buffer, wall jump, slide-dive and the plain or crouched jump. Returns
## whether this tick jumped off the ground (it is then already an air tick: no ground friction).
static func tick_jump(p: Player, delta: float, on_floor: bool, locked: bool) -> bool:
	# A jump pressed during the roll lock is held, not eaten: the buffer does not run down until the
	# roll lets a jump through again (#249). Only on the ground, so an air press still expires.
	if not (on_floor and p._roll_jump_locked()):
		p._jump_buffer = maxf(p._jump_buffer - delta, 0.0)
	if (not p.is_dead) and (not locked) and Input.is_action_just_pressed("jump"):
		p._jump_buffer = Player.JUMP_BUFFER
	var jumped := false
	if not on_floor:
		p.velocity.y += float(p.get_gravity().y) * delta * Movement.gravity_scale(p)
		p._sliding = false
		if (p._wallrunning or p._wall_off_t <= Player.WALLRUN_COYOTE) and (not p.is_dead) and (not locked) and p._jump_buffer > 0.0:
			p._wall_jump()
			p._jump_buffer = 0.0
	elif (not p.is_dead) and (not locked) and p._jump_buffer > 0.0 and p._sliding and p._dive_cd <= 0.0:
		p._sliding = false
		p._start_dive(true) # sprint + crouch (slide), then jump: dive
		jumped = true
		p._jump_buffer = 0.0
	elif (not p.is_dead) and (not locked) and p._jump_buffer > 0.0 and not p._roll_jump_locked():
		p._sliding = false
		var out_of_roll := p._roll_t > 0.0
		p._roll_t = 0.0
		if p.crouch > 0.2:
			if not p._ceiling_blocked():
				p.crouch = 0.0
				p._apply_stance()
				p.velocity.y = Player.JUMP_SPEED
				jumped = true
		else:
			p.velocity.y = Player.JUMP_SPEED
			jumped = true
		if jumped:
			p._jump_buffer = 0.0
			if out_of_roll:
				p._cap_roll_jump_speed()
	return jumped


## [wish direction, wish speed] from the stick, the stance, the slide, sprint and the gun; sets
## is_sprinting. LOS coasts on the speed the body already has.
static func wish(p: Player, input_vec: Vector2, on_floor: bool, locked: bool) -> Array:
	var w := p.transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)
	w.y = 0.0
	if w.length_squared() > 1.0:
		w = w.normalized()
	elif input_vec.length_squared() > 0.0001:
		w = w.normalized() * minf(input_vec.length(), 1.0)
	var wish_speed := Player.WALK_SPEED
	p.is_sprinting = false
	if p._sliding:
		w = p._slide_dir
		wish_speed = Player.SPRINT_SPEED
		p.is_sprinting = false
	elif on_floor and (not p.is_dead) and (not locked) and p.crouch < 0.2 and Input.is_action_pressed("sprint") and w.length_squared() > 0.04:
		wish_speed = Player.SPRINT_SPEED
		p.is_sprinting = true
	elif p.crouch > 0.5:
		wish_speed = Player.CROUCH_SPEED
	if not p._sliding:
		wish_speed *= p.gun_speed_mult()
	# #388: Overdrive is a real speed buff, on the owner's machine and on the server's copy alike.
	wish_speed *= Overdrive.speed_mult(p)
	# LOS: wish is the speed the body already has, so friction does not park it.
	# Below COAST_MIN it stands. No new jump, slide or dive (input_locked covers those).
	if p.los_coast:
		var hv := Vector3(p.velocity.x, 0.0, p.velocity.z)
		var spd := hv.length()
		if spd >= LosHands.COAST_MIN:
			w = hv / spd
			wish_speed = spd
		else:
			w = Vector3.ZERO
			wish_speed = 0.0
	return [w, wish_speed]


## The horizontal velocity for this tick, by the first state that holds: the shank's lunge, the air
## (or the jump tick), knockback, a carry, a landing roll, a slide, plain ground.
static func horizontal(p: Player, w: Vector3, wish_speed: float, jumped: bool, on_floor: bool, delta: float) -> Vector3:
	var horiz := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if p._lunge_left > 0.0:
		# The shank's step. Friction would eat it before it covered the 2.5 m.
		p._lunge_left = maxf(p._lunge_left - delta, 0.0)
		return p._lunge_dir * p._lunge_speed
	if jumped or not on_floor:
		# The jump tick is already air: no ground friction, so sprint speed carries into the jump.
		horiz = p._air_accelerate(horiz, w, Player.WALK_SPEED * minf(w.length(), 1.0), delta)
		if not p._air_steer_locked:
			horiz = Movement.air_steer(horiz, w, delta)
		return horiz
	if p._kb_t > 0.0:
		horiz = p._friction_amount(horiz, delta, Player.KB_FRICTION)
		return p._accelerate(horiz, w, wish_speed, Player.GROUND_ACCEL * 0.5, delta)
	if p._carry_t > 0.0:
		return carry(p, horiz, w, wish_speed, delta)
	if p._roll_t > 0.0:
		horiz = p._friction_amount(horiz, delta, Player.ROLL_FRICTION) # the roll keeps the dive's speed
		if w.length_squared() > 0.04:
			horiz = Movement.carry_steer(horiz, w, Player.ROLL_TURN_RATE, delta) # #251: steered, but slower
		return horiz
	if p._sliding:
		return p._friction_amount(horiz, delta, Player.SLIDE_FRICTION)
	horiz = p._friction(horiz, delta)
	return p._accelerate(horiz, w, wish_speed, Player.GROUND_ACCEL, delta)


## #251: held keys steer the carry instead of drifting through it. The velocity turns toward the wish
## direction with its speed kept, so 15 m/s corners like grip; accelerate is only back during the fade,
## where it hands the carry over to normal ground movement: the friction ramps up and accelerate refills
## toward wish speed in the same tick, so a carry you run out ends at sprint and never at a stop
## (playtest on #251: the boost used to dump you at walking speed).
static func carry(p: Player, horiz: Vector3, w: Vector3, wish_speed: float, delta: float) -> Vector3:
	var carry_friction := Player.CARRY_FRICTION
	var steered := false
	if w.length_squared() <= 0.04:
		carry_friction = Player.CARRY_RELEASE_FRICTION # no keys: brake, so the next shot is a choice
	elif absf(horiz.signed_angle_to(w, Vector3.UP)) > Player.CARRY_COUNTER_ANGLE:
		carry_friction = Player.CARRY_COUNTER_FRICTION # pressing S is braking, not a 180 turn
	else:
		steered = true
		horiz = Movement.carry_steer(horiz, w, Player.CARRY_TURN_RATE, delta)
	var fade := clampf(1.0 - p._carry_t / Player.CARRY_FADE, 0.0, 1.0)
	horiz = p._friction_amount(horiz, delta, lerpf(carry_friction, Player.GROUND_FRICTION, fade))
	if steered and not p._sliding:
		horiz = p._accelerate(horiz, w, wish_speed, Player.GROUND_ACCEL, delta)
	return horiz


## The wallrun's sink replaces gravity, the grapple pulls, a surf ramp clips the velocity to its plane.
static func vertical(p: Player, on_floor: bool, delta: float) -> void:
	if p._wallrunning:
		var sink := lerpf(Player.WALLRUN_SINK_START, Player.WALLRUN_SINK_END, clampf(p._wallrun_t / Player.WALLRUN_TIME, 0.0, 1.0))
		# Gravity was added above; the wall replaces it. A jump's rise bleeds off instead of snapping.
		var vy := p.velocity.y - float(p.get_gravity().y) * delta
		p.velocity.y = move_toward(vy, -sink, Player.WALLRUN_RISE_DAMP * delta) if vy > -sink else -sink
	p._apply_grapple_pull(delta)
	p._surf_t = maxf(p._surf_t - delta, 0.0)
	if not on_floor and p._surf_t > 0.0:
		p.velocity = p.clip_to_plane(p.velocity, p._surf_normal)


## After move_and_slide: step-ups, surf contact and the carry it starts, speed strips, slide end, boosts,
## wallrun, dive/roll, and the feel (move_fx, speed fx, feet, step view, the gun's sway speed).
static func after_move(p: Player, pre_move: Vector3, jumped: bool, on_floor: bool, input_vec: Vector2, locked: bool,
		delta: float) -> void:
	# Small lips (slab seams, curbs, ramp edges up to StepUp.MAX_HEIGHT) are walked over, not
	# a wall. Floor only: air strafing and surfing are untouched.
	if not jumped:
		p._smooth_step(StepUp.try_step(p, pre_move, on_floor, delta))
	p._note_surf_contact()
	# Landing is an air frame (no ground friction yet). Carry starts here, so the next
	# grounded frame keeps the speed instead of scrubbing it.
	var surfing := p.is_surfing()
	if p._was_surfing and not surfing:
		p._begin_carry()
	p._was_surfing = surfing
	p._boost_through_strips()
	p._apply_carry_fov()
	p._finish_slide()
	Movement.tick_boosts(p, delta)
	p._tick_wallrun(delta, input_vec, locked)
	p._tick_dive_roll(delta)
	p._tick_move_fx(delta)
	p._tick_speed_fx(delta)
	p._tick_feet(delta)
	p._tick_step_view(delta)
	p.weapon.speed_factor = Vector2(p.velocity.x, p.velocity.z).length() / Player.WALK_SPEED
