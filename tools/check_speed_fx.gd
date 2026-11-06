extends Node
## Speed FX headless: the pure FOV / speed-line / wind / landing-dip math, the sprint and ADS paths
## of Player._apply_carry_fov, and the settings round trip of Game.speed_fx (access/speed_fx).
##   godot --headless --path . res://tools/check_speed_fx.tscn   → "SPEED FX CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	# Constants: the kick grows with speed, the ranges are the right way round.
	_ok(Player.SPRINT_SPEED == 11.4, "SPRINT_SPEED is 11.4")
	_ok(Player.SPEED_FOV_REF < Player.SPEED_FOV_FULL, "FOV reference below the full speed")
	_ok(Player.SPEED_FOV_AT_SPRINT < Player.SPEED_FOV_MAX, "FOV kick grows from sprint to full")
	_ok(Player.SPEED_FOV_MAX <= Player.FOV_EXTRA_CAP + 0.0001, "FOV kick stays inside FOV_EXTRA_CAP")
	_ok(Player.SPEED_LINES_START < Player.SPEED_LINES_FULL, "speed lines start before full")
	_ok(Player.WIND_START < Player.WIND_FULL, "wind ramps up")
	_ok(Player.LAND_CAM_DIP_MAX > 0.0, "landing dip has a depth")

	# Pure helpers: what the local tick writes for a horizontal speed.
	_ok(Player.speed_fov_extra(0.0) == 0.0, "standing: no FOV kick")
	_ok(Player.speed_fov_extra(Player.WALK_SPEED) == 0.0, "walking: no FOV kick")
	_ok(is_equal_approx(Player.speed_fov_extra(Player.SPRINT_SPEED), Player.SPEED_FOV_AT_SPRINT), "sprint: SPEED_FOV_AT_SPRINT")
	var full := Player.speed_fov_extra(Player.CARRY_MAX)
	_ok(is_equal_approx(full, Player.SPEED_FOV_MAX), "carry speed: SPEED_FOV_MAX (%.1f)" % full)
	_ok(Player.speed_fov_extra(Player.CARRY_MAX * 3.0) <= Player.FOV_EXTRA_CAP, "faster than full stays capped")
	_ok(Player.speed_lines_intensity(Player.SPEED_LINES_START) == 0.0, "lines off at SPEED_LINES_START")
	_ok(Player.speed_lines_intensity(Player.SPEED_LINES_FULL) == 1.0, "lines full at SPEED_LINES_FULL")
	_ok(Player.speed_wind_level(Player.WIND_START) == 0.0, "wind silent at WIND_START")
	_ok(Player.speed_wind_level(Player.WIND_FULL) == 1.0, "wind full at WIND_FULL")
	_ok(is_equal_approx(Player.speed_land_dip(Player.LAND_CAM_MIN_SPEED), 0.0), "soft landing: no dip")
	_ok(Player.speed_land_dip(Player.CARRY_MAX) < 0.0, "hard landing: the dip looks down")
	_ok(is_equal_approx(Player.speed_land_dip(1000.0), -Player.LAND_CAM_DIP_MAX), "dip is capped at LAND_CAM_DIP_MAX")

	# The local pawn paths. Physics is off, the test drives the fields itself.
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.set_physics_process(false)
	add_child(p)
	var cam := p.camera
	_ok(cam != null and p.weapon != null, "pawn has the camera and the gun")
	if cam == null or p.weapon == null:
		_finish(p)
		return
	Game.speed_fx = true
	p.velocity = Vector3(0.0, 0.0, -Player.WALK_SPEED)
	p._apply_carry_fov()
	_ok(cam.extra_fov == 0.0, "walking tick: extra_fov 0")
	p.velocity = Vector3(0.0, 0.0, -Player.SPRINT_SPEED)
	p._apply_carry_fov()
	_ok(is_equal_approx(cam.extra_fov, Player.SPEED_FOV_AT_SPRINT), "sprint tick: extra_fov %.2f (hspeed %.4f)" % [cam.extra_fov, p._hspeed()])
	p.velocity = Vector3(0.0, 0.0, -Player.CARRY_MAX * 2.0)
	p._apply_carry_fov()
	_ok(is_equal_approx(cam.extra_fov, Player.SPEED_FOV_MAX), "surf tick: extra_fov %.2f" % cam.extra_fov)
	p.velocity = Vector3.ZERO
	p._apply_carry_fov()
	_ok(cam.extra_fov == 0.0, "standing still: extra_fov back to 0")

	# ADS wins over the kick: the scope FOV stays absolute.
	p.velocity = Vector3(0.0, 0.0, -Player.CARRY_MAX)
	p.weapon._ads = true
	cam.extra_fov = 5.0
	p._apply_carry_fov()
	_ok(cam.extra_fov == 0.0, "ADS clears the FOV kick")
	p.weapon._ads = false
	cam.extra_fov = 0.0

	# The landing dip is a transient channel: it may never stack past its own cap and it must leave no
	# residue in move_pitch. This is the regression test for the ~2.3x dip that the old code produced
	# at 60 Hz by adding the dip on top of itself every tick.
	Game.speed_fx = true
	cam.move_pitch = 0.0
	p._land_cam_pitch = Player.speed_land_dip(Player.CARRY_MAX)
	p._land_dip_applied = 0.0
	var deepest := 0.0
	var dt := 1.0 / 60.0
	for i in range(240):
		p._tick_move_fx(dt)
		p._tick_speed_fx(dt)
		deepest = minf(deepest, cam.move_pitch)
	_ok(deepest >= -Player.LAND_CAM_DIP_MAX - 0.0001,
		"landing dip stays inside its cap (%.4f vs %.4f rad)" % [deepest, -Player.LAND_CAM_DIP_MAX])
	_ok(deepest <= -Player.LAND_CAM_DIP_MAX * 0.9, "landing dip is actually felt (%.4f rad)" % deepest)
	_ok(absf(cam.move_pitch) < 0.001, "landing dip leaves no residue in move_pitch (%.4f)" % cam.move_pitch)

	# The pause menu silences the speed lines; they must not keep drawing behind the menu.
	Game.pause_open = true
	p.velocity = Vector3(0.0, 0.0, -Player.CARRY_MAX)
	for i in range(120):
		p._tick_speed_fx(dt)
	_ok(Game.speed_lines.intensity() < 0.05,
		"pause menu: speed lines go dark (%.3f)" % Game.speed_lines.intensity())
	Game.pause_open = false
	for i in range(120):
		p._tick_speed_fx(dt)
	_ok(Game.speed_lines.intensity() > 0.9,
		"menu closed: speed lines come back (%.3f)" % Game.speed_lines.intensity())
	Game.speed_lines.set_intensity(0.0)
	p.velocity = Vector3.ZERO

	# Toggle off: the old plain sprint FOV, and the carry stack on top of it.
	Game.speed_fx = false
	p.is_sprinting = true
	p._carry_t = 0.0
	p.velocity = Vector3(0.0, 0.0, -Player.SPRINT_SPEED)
	p._apply_carry_fov()
	_ok(is_equal_approx(cam.extra_fov, Player.SPRINT_FOV), "speed_fx off: plain sprint FOV (%.1f)" % cam.extra_fov)
	p.is_sprinting = false

	# Settings round trip, the same cfg path check_settings uses.
	Game.speed_fx = false
	Game.save_settings()
	Game.speed_fx = true
	Game.load_settings()
	_ok(not Game.speed_fx, "speed_fx survives a save/load round trip")
	Game.set_speed_fx(true)
	Game.load_settings()
	_ok(Game.speed_fx, "restored to on")

	# Speed lines: the shader loads and the overlay maps intensity to a drawn frame.
	var shader := load("res://shaders/speed_lines.gdshader") as Shader
	_ok(shader != null, "speed_lines.gdshader loads")
	var lines := SpeedLines.new()
	add_child(lines)
	_ok(lines.intensity() == 0.0 and not lines.is_drawing(), "overlay starts dark")
	lines.set_intensity(1.0)
	_ok(is_equal_approx(lines.intensity(), 1.0) and lines.is_drawing(), "intensity 1 draws")
	lines.set_intensity(0.0)
	_ok(lines.intensity() == 0.0 and not lines.is_drawing(), "intensity 0 hides")
	lines.set_intensity_smooth(1.0, 0.1, Player.SPEED_LINES_SMOOTH)
	var eased := lines.intensity()
	_ok(eased > 0.0 and eased < 1.0, "smooth eases in (%.2f)" % eased)
	lines.set_intensity(0.0)
	lines.queue_free()
	_ok(Game.speed_lines != null, "Game owns the speed lines overlay")

	# Wind: the asset loads, the copy the pawn plays is looped, and the ramp constants are sane.
	var wind := load("res://assets/sounds/wind_loop.wav") as AudioStreamWAV
	_ok(wind != null, "wind_loop.wav loads as AudioStreamWAV")
	var looped := Player.looped_wind()
	_ok(looped.loop_mode == AudioStreamWAV.LOOP_FORWARD, "wind copy loops forward (mode %d)" % looped.loop_mode)
	_ok(looped.loop_end > 0 and looped.get_length() > 1.0, "wind loop covers the whole clip (%.2fs)" % looped.get_length())
	var pawn_wind := (p._wind.stream as AudioStreamWAV) if p._wind != null else null
	_ok(pawn_wind != null and pawn_wind.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the local pawn plays a looped wind")
	_ok(p._wind != null and p._wind.bus == "SFX", "wind is on the SFX bus (Effects slider)")
	_ok(Player.WIND_VOL_DB_MIN < Player.WIND_VOL_DB_MAX, "wind volume ramps up")
	_ok(Player.WIND_PITCH_MIN < Player.WIND_PITCH_MAX, "wind pitch ramps up")
	_finish(p)


func _finish(p: Player) -> void:
	if p != null and is_instance_valid(p):
		p.queue_free()
	print("SPEED FX CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
