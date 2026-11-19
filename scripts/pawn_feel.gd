class_name PawnFeel
extends RefCounted
## How a pawn feels and sounds while it moves (#316): footsteps and the landing thump, `move_fx` and the
## camera's wallrun lean, dive pitch and roll flip, the speed FX (landing dip, speed lines, wind) and the
## sprint/carry FOV kick. Static on the pawn `p`, like Movement; Player keeps the state and the constants.


## Uses velocity when we simulate, otherwise position delta (puppets have velocity zeroed).
static func tick_feet(p: Player, delta: float) -> void:
	var moved := p.global_position - p._feet_last
	var inst_speed := minf(Vector2(moved.x, moved.z).length() / maxf(delta, 0.0001), p.SPRINT_SPEED * 1.5)
	p._obs_speed = lerpf(p._obs_speed, inst_speed, 0.15)
	if p.is_dead:
		p._was_air = false
		p._feet_last = p.global_position
		return
	var dpos := p.global_position - p._feet_last
	var horiz := Vector2(p.velocity.x, p.velocity.z).length()
	if horiz < 0.35:
		horiz = Vector2(dpos.x, dpos.z).length() / maxf(delta, 0.0001)
	var grounded := p.is_on_floor() or absf(dpos.y) < 0.05
	if p._was_air and grounded and p.land_sfx:
		p.land_sfx.pitch_scale = randf_range(0.92, 1.06)
		p.land_sfx.volume_db = -14.0 if p.is_local() else -8.0
		p.land_sfx.play()
	p._was_air = not grounded
	p._feet_last = p.global_position
	if p._sliding:
		p._step_t = 0.2
		return
	if not grounded or horiz < 1.15:
		p._step_t = 0.12
		return
	var interval := 0.40
	if p.crouch > 0.45:
		interval = 0.52
	elif horiz > p.WALK_SPEED * 1.15:
		interval = 0.28
	p._step_t -= delta
	if p._step_t > 0.0:
		return
	p._step_t = interval
	if p.step_sfx == null:
		return
	var pick := randi() % (p.STEP_SOUNDS.size() - 1)
	if pick >= p._step_last:
		pick += 1
	p._step_last = pick
	p.step_sfx.stream = p.STEP_SOUNDS[pick]
	p.step_sfx.pitch_scale = randf_range(0.92, 1.08)
	var quiet := -16.0 if p.is_local() else -9.0
	if p.crouch > 0.45:
		quiet -= 6.0
	p.step_sfx.volume_db = quiet
	p.step_sfx.play()


## Hip FOV while running. Speed FX on: the extra FOV scales with horizontal speed from sprint on
## (speed_fov_extra), so a surf or a dive widens the view and walking does not. Speed FX off: the old
## plain sprint flag plus the carry stack. ADS clears it either way; Game.fov stays the hip base.
static func apply_carry_fov(p: Player) -> void:
	if p.weapon == null or p.camera == null:
		return
	if p.weapon.is_ads():
		p.camera.extra_fov = 0.0
		return
	if Game.speed_fx:
		p.camera.extra_fov = p.speed_fov_extra(p._hspeed())
		return
	var extra := p.SPRINT_FOV if p.is_sprinting else 0.0
	if p._carry_t > 0.0:
		extra += lerpf(p.CARRY_FOV_MIN, p.CARRY_FOV_MAX, clampf(p._hspeed() / p.CARRY_MAX, 0.0, 1.0))
	p.camera.extra_fov = minf(extra, p.FOV_EXTRA_CAP)


static func tick_move_fx(p: Player, delta: float) -> void:
	p._throw_t = maxf(p._throw_t - delta, 0.0)
	if p._wallrunning:
		p.move_fx = p.MOVE_WALLRUN
	elif p._diving:
		p.move_fx = p.MOVE_DIVE
	elif p._grapple.active:
		p.move_fx = p.MOVE_GRAPPLE
	elif p._roll_t > 0.0:
		p.move_fx = p.MOVE_ROLL
	else:
		p.move_fx = p.MOVE_NONE
	if p.camera == null:
		return
	# Take last tick's landing dip back out before the pitch is re-derived below. Without this the dip
	# fed back into the decay: every tick added it again while the decay only shaved ~10% off, and at
	# 60 Hz the camera dipped to ~2.3x LAND_CAM_DIP_MAX. The cap was never wrong, the channel was.
	p.camera.move_pitch -= p._land_dip_applied
	p._land_dip_applied = 0.0
	var roll_target := 0.0
	if p._wallrunning:
		var right := p.transform.basis.x
		# Speed FX leans a touch further into the wall run; the away-from-wall direction is the feel (#80).
		roll_target = -signf(right.dot(p._wall_n)) * p.WALLRUN_TILT * (1.1 if Game.speed_fx else 1.0) * Game.shake_scale()
	p.camera.move_roll = lerpf(p.camera.move_roll, roll_target, 1.0 - exp(-10.0 * delta))
	if p._roll_t > 0.0:
		var t := 1.0 - p._roll_t / p.ROLL_TIME
		if Game.shake_scale() >= 0.5:
			p.camera.move_pitch = -TAU * ease(t, -1.8) # full forward flip
		else:
			p.camera.move_pitch = -deg_to_rad(25.0) * sin(t * PI) # reduced motion: a dip
	elif p._diving:
		p.camera.move_pitch = lerpf(p.camera.move_pitch, -0.12, 1.0 - exp(-8.0 * delta))
	else:
		p.camera.move_pitch = lerpf(wrapf(p.camera.move_pitch, -PI, PI), 0.0, 1.0 - exp(-14.0 * delta))


## Speed FX, local player only (Game.speed_fx): the landing camera dip and its easing back to 0.
## Runs right after _tick_move_fx, so the dip is added on top of whatever pitch the dive or the roll
## asked for and never fights it. A dive roll already pitches the camera, so it skips the dip.
## The FOV kick lives in _apply_carry_fov; the speed lines and the wind latch onto this tick too.
static func tick_speed_fx(p: Player, delta: float) -> void:
	if p.camera == null:
		return
	if p.is_dead:
		p._fall_vy = 0.0
		p._was_fall = false
	elif p.is_on_floor():
		if p._was_fall:
			if Game.speed_fx and not (p._roll_t > 0.0 or p._diving):
				p._land_cam_pitch = minf(p._land_cam_pitch, p.speed_land_dip(-p._fall_vy))
			p._fall_vy = 0.0
			p._was_fall = false
	else:
		p._fall_vy = minf(p._fall_vy, p.velocity.y)
		p._was_fall = true
	if p._land_cam_pitch != 0.0:
		if Game.speed_fx:
			p.camera.move_pitch += p._land_cam_pitch
			p._land_dip_applied = p._land_cam_pitch
		p._land_cam_pitch = lerpf(p._land_cam_pitch, 0.0, 1.0 - exp(-p.LAND_CAM_RECOVER * delta))
		if absf(p._land_cam_pitch) < 0.0005:
			p._land_cam_pitch = 0.0
	# Speed lines and wind run off the same horizontal speed. Aiming, death, the pause menu and anything
	# else that locks play (chat, round freeze, RC view) silences both, so a fight never reads through a
	# blurred screen and a menu never keeps the wind howling.
	var quiet := p.is_dead or Game.chat_open or Game.pause_open or Game.play_locked() or Game.rc_view
	if not quiet and p.weapon != null and p.weapon.is_ads():
		quiet = true
	var fast := Game.speed_fx and not quiet
	var hspeed := p._hspeed()
	p._tick_speed_lines(p.speed_lines_intensity(hspeed) if fast else 0.0, delta)
	p._tick_wind(p.speed_wind_level(hspeed) if fast else 0.0)


## Speed FX: eases the speed-lines overlay toward `target` (0..1). A missing overlay (headless,
## dedicated server) is not an error: there is simply nothing on screen to draw on.
static func tick_speed_lines(p: Player, target: float, delta: float) -> void:
	if Game.speed_lines == null:
		return
	Game.speed_lines.set_intensity_smooth(target, delta, p.SPEED_LINES_SMOOTH)


## Speed FX wind: one looped player, louder and a little higher with speed, stopped when slow.
## Local pawn only, so it is on the SFX bus (the Effects slider) and never on the Enemies bus.
static func tick_wind(p: Player, level: float) -> void:
	if p._wind == null:
		return
	if level <= 0.0:
		if p._wind.playing:
			p._wind.stop()
		return
	if not p._wind.playing:
		p._wind.play()
	p._wind.volume_db = lerpf(p.WIND_VOL_DB_MIN, p.WIND_VOL_DB_MAX, level)
	p._wind.pitch_scale = lerpf(p.WIND_PITCH_MIN, p.WIND_PITCH_MAX, level)
