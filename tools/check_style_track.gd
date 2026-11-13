extends Node
## #106-split: the style track is its own object now (`shared/style_track.gd`), and the pawn still
## answers through the old names.
##   godot --headless --path . res://tools/check_style_track.tscn   → "STYLE TRACK CHECK OK"
##
## What this protects: the split moved every "did the server see this trick" rule at once. Two things
## have to hold. The pawn still reports the same things through `style_*()` and `air_time`, and a
## respawn starts with clean history (a fresh track cannot read the spawn as a fall or a spin).
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _pawn(id: int) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = id
	p.set_physics_process(false)
	p.set_process(false)
	add_child(p)
	return p


func _ready() -> void:
	var p := _pawn(1)
	_ok(p._style is StyleTrack and p._style.pawn == p, "every pawn owns a track that points back at it")

	# 1) A fresh track vouches for nothing: no move, no drop, no spin.
	_ok(not p.style_wallrun() and not p.style_walljump() and not p.style_dive() and not p.style_roll(),
		"a fresh track reports no wallrun/dive/roll")
	_ok(not p.style_surfing() and p.style_drop() == 0.0 and p.spin_degrees() == 0.0,
		"a fresh track reports no surf, no drop and no spin")
	_ok(p.air_time == 0.0 and not p._style.in_air, "a fresh track sits on the ground")

	# 2) The track's own state is what the pawn reports: no second copy to drift.
	p._style.wallrun_seen_t = p._style.clock
	p._style.dive_seen_t = p._style.clock
	p._style.roll_seen_t = p._style.clock
	p._style.landed_drop = 2.5
	p._style.landed_t = p._style.clock
	_ok(p.style_wallrun() and p.style_dive() and p.style_roll(), "the wrappers read the track")
	_ok(is_equal_approx(p.style_drop(), 2.5), "style_drop() reports the track's landed drop")

	# 3) Turn history: a quarter turn inside the window is a 90 degree spin. No physics tick runs in a
	# headless check, so the track is driven by hand.
	p._reset_style_track()
	p._style.clock = 0.0
	p.rotation.y = 0.0
	p._style.tick(0.016)
	p.rotation.y = deg_to_rad(90.0)
	p._style.tick(0.016)
	_ok(absf(p.spin_degrees() - 90.0) < 2.0, "a 90 degree turn reads as ~90 (%d)" % roundi(p.spin_degrees()))
	# The pawn's copy is written by _tick_style_track (the per-tick wrapper), not by the track itself.
	p._tick_style_track(0.0)
	_ok(p.air_time == p._style.air_time, "the per-tick wrapper mirrors the track's air time")

	# 4) A respawn resets everything, including the mirrored air time.
	p.air_time = 3.0
	p._reset_style_track()
	_ok(p._style.clock == 0.0 and p._style.yaw_samples.is_empty() and p.air_time == 0.0,
		"a reset drops the clock, the turn history and the air time")
	_ok(not p.style_wallrun() and p.style_drop() == 0.0, "and vouches for nothing again")

	p.queue_free()
	print("STYLE TRACK CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
