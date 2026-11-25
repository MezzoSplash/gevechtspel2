extends Node
## Overdrive (#388), headless:  godot --headless --path . res://tools/check_overdrive.tscn
## The streak sits on the 7-kill step with LOS, so a pick holds one of the two. While it runs: 25%
## speed, endless wallruns, dives on tap, the shank's lunge on any gun, double style, and +2 s per kill
## up to the cap. The server owns the clock and the #B1 claim check gets the headroom, or it would pull
## a boosting player back.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	Game.mode = Game.MODE_FFA
	_catalog()
	_charges()
	var floor := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	col.shape = box
	floor.add_child(col)
	floor.position = Vector3(0, -0.5, 0)
	add_child(floor)
	var p := _pawn(1, false)
	p.position = Vector3(0, 0.05, 0)
	var bot := _pawn(-3, true)
	bot.position = Vector3(0, 0.05, -6)
	for _i in 4:
		await get_tree().physics_frame
	p._spawn_protect = 0.0
	bot._spawn_protect = 0.0
	bot._bot_brain = null
	await _stats(p, bot)
	await _timer(p)
	await _claims(p)
	print("OVERDRIVE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _catalog() -> void:
	_ok(StreakDefs.kills(&"overdrive") == 7, "Overdrive costs 7 kills, the same step as LOS")
	_ok(StreakDefs.bots_allowed(&"overdrive"), "a bot may use Overdrive")
	_ok(StreakDefs.bit(&"overdrive") == Game.CHARGE_OVERDRIVE, "Overdrive has its own charge bit")
	_ok(StreakDefs.bit(&"overdrive") != StreakDefs.bit(&"los") and StreakDefs.bit(&"overdrive") != StreakDefs.bit(&"rcxd"),
		"the bit is not shared with another streak")
	var both := StreakDefs.sanitize(["uav", "los", "overdrive"])
	_ok(both == StreakDefs.default_ids(), "LOS and Overdrive cannot be picked together (same cost)")
	var over := StreakDefs.sanitize(["uav", "overdrive"])
	_ok(over.has(&"overdrive") and not over.has(&"los"), "picking Overdrive instead of LOS is allowed")
	_ok(StreakDefs.cost_conflict(["los", "overdrive"]), "the menu sees the shared 7-kill cost")


func _charges() -> void:
	Game.streak_progress.clear()
	Game.streak_charges.clear()
	Game.streak_earned.clear()
	Game.streak_choices[1] = ["uav", "overdrive"]
	for _i in 7:
		Game._bump_streak(1, 99)
	var bits := int(Game.streak_charges.get(1, 0))
	_ok((bits & Game.CHARGE_OVERDRIVE) != 0, "7 kills bank Overdrive when it is picked")
	_ok((bits & Game.CHARGE_LOS) == 0, "LOS does not bank on the same kills")
	Game.streak_choices[-4] = ["uav", "overdrive"]
	for _i in 7:
		Game._bump_streak(-4, 98)
	_ok((int(Game.streak_charges.get(-4, 0)) & Game.CHARGE_OVERDRIVE) != 0, "a bot banks Overdrive")
	Game.streak_choices.clear()


func _stats(p: Player, bot: Player) -> void:
	Game.streak_choices[1] = ["uav", "rcxd", "overdrive"]
	Game.streak_charges[1] = int(Game.streak_charges.get(1, 0)) | Game.CHARGE_OVERDRIVE
	var slot := StreakSelect.slot_for(Game, 1, &"overdrive")
	Game.try_activate_streak(1, slot)
	var o := Overdrive.for_owner(1)
	_ok(o != null and o.time_left > 9.5, "the streak starts with about 10 s (%.1f)" % (o.time_left if o else 0.0))
	_ok(Overdrive.active(p), "the buff is on the pawn")
	_ok(is_equal_approx(Overdrive.speed_mult(p), 1.25), "25% more speed")
	_ok(Overdrive.wallrun_free(p), "wallruns do not time out")
	_ok(Overdrive.dive_free(p), "the dive cooldown is gone")
	_ok(Overdrive.lunges(p), "the shank's lunge works on any weapon")
	_ok(Overdrive.style_mult(p) == 2, "kills count double for style")

	# Speed, measured through the real move tick: sprint speed times 1.25.
	Input.action_press("sprint")
	var fast: Array = MoveTick.wish(p, Vector2(0, -1), true, false)
	Input.action_release("sprint")
	_ok(absf(float(fast[1]) - Player.SPRINT_SPEED * 1.25) < 0.05,
		"the sprint wish is %.2f m/s, 1.25 x %.1f" % [float(fast[1]), Player.SPRINT_SPEED])

	# The dive: a second one in the same air time, which the plain rules refuse. The real door checks
	# the crouch and sprint keys and the minimum speed, so they are set the way a player would have them.
	p._dive_used = true
	p._in_crouch_down = true
	p._in_sprint = true
	p._diving = false
	p._dive_cd = 9.0 # and a cooldown that would block it outright
	p.velocity = Vector3(0, 0, -Player.SPRINT_SPEED)
	p.global_position = Vector3(0, 3.0, 0)
	Movement.try_air_dive(p, false, false)
	_ok(p._diving, "a second dive in one air time is allowed while Overdrive runs")
	p._diving = false
	p._dive_cd = 0.0
	p._dive_used = false
	p._in_crouch_down = false
	p._in_sprint = false
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO

	# The lunge on a rifle: the shank's step, on a gun that never had one.
	var bot_pos := Vector3(0, 0.05, -2.6)
	bot.global_position = bot_pos
	bot.is_dead = false
	bot.hp = Player.MAX_HP
	p.global_position = Vector3(0, 0.05, 0)
	p._yaw = 0.0
	p.rotation.y = 0.0
	p._lunge_left = 0.0
	p.velocity = Vector3(0, 0, -Player.SPRINT_SPEED)
	await get_tree().physics_frame
	Game.melee._last.clear()
	var swung := Game.melee.swing(p)
	_ok(swung and p._lunge_left > 0.0, "a rifle bash lunges while Overdrive runs (%.2f m left)" % p._lunge_left)
	p._lunge_left = 0.0

	# Double style: the same kill award, once with the buff and once without.
	var gain_on := _style_gain(p, bot)
	Overdrive.abort_for(1)
	await get_tree().physics_frame
	var gain_off := _style_gain(p, bot)
	_ok(gain_on == gain_off * 2, "the same kill pays %d with Overdrive and %d without" % [gain_on, gain_off])

	# Extension and its ceiling, then the buff being off.
	Game.streak_charges[1] = int(Game.streak_charges.get(1, 0)) | Game.CHARGE_OVERDRIVE
	Game.try_activate_streak(1, StreakSelect.slot_for(Game, 1, &"overdrive"))
	o = Overdrive.for_owner(1)
	var before := o.time_left if o else 0.0
	Overdrive.server_kill(1)
	_ok(o != null and is_equal_approx(o.time_left, before + 2.0), "+2 s for a kill (%.1f -> %.1f)" % [
		before, o.time_left if o else 0.0])
	for _i in 6:
		Overdrive.server_kill(1)
	_ok(o != null and is_equal_approx(o.time_left, Overdrive.MAX_TIME), "the clock stops at the cap (%.1f)" % (
		o.time_left if o else 0.0))
	Overdrive.abort_for(1)
	await get_tree().physics_frame
	_ok(not Overdrive.active(p) and is_equal_approx(Overdrive.speed_mult(p), 1.0), "after it ends the stats are plain again")


func _style_gain(p: Player, bot: Player) -> int:
	# A fresh chain per award, or the chain multiplier would jump between the two runs and the
	# comparison would say nothing about the doubling.
	Game._style_chain.clear()
	Game._combos.clear()
	Game.scores.clear()
	Game.register_participant(1, "P1", 0)
	var before := int(Game.scores[1].get("style", 0))
	bot.is_dead = false
	Game._award_style({"k": 1, "v": -3, "kn": "P1", "vn": "bot", "kt": 0, "vt": 0, "w": "rifle", "hs": true,
		"tags": "HEADSHOT"}, [Style.HS_STREAK] as Array[StringName])
	return int(Game.scores[1].get("style", 0)) - before


## #B1: a step that is too fast for the plain cap must pass while Overdrive runs.
func _claims(p: Player) -> void:
	Overdrive.abort_for(1)
	await get_tree().physics_frame
	var step := Vector3(2.1, 0.0, 0.0) # 2.1 m in 50 ms
	var plain := PawnNet.claim_reachable_delta(p, step, p.NET_CLAIM_MIN_DT)
	_ok(not plain, "without Overdrive a 2.1 m step in 50 ms is refused")
	Game.streak_choices[1] = ["uav", "rcxd", "overdrive"]
	Game.streak_charges[1] = int(Game.streak_charges.get(1, 0)) | Game.CHARGE_OVERDRIVE
	Game.try_activate_streak(1, StreakSelect.slot_for(Game, 1, &"overdrive"))
	_ok(Overdrive.active(p), "Overdrive is on for the claim test")
	var fast := PawnNet.claim_reachable_delta(p, step, p.NET_CLAIM_MIN_DT)
	_ok(fast, "the same step is accepted while Overdrive runs (cap %.1f m/s)" % p.claim_h_cap())
	Overdrive.abort_for(1)
	await get_tree().physics_frame


func _timer(p: Player) -> void:
	Game.streak_choices[1] = ["uav", "rcxd", "overdrive"]
	Game.streak_charges[1] = int(Game.streak_charges.get(1, 0)) | Game.CHARGE_OVERDRIVE
	Game.try_activate_streak(1, StreakSelect.slot_for(Game, 1, &"overdrive"))
	_ok(Overdrive.for_owner(1) != null, "Overdrive launched for the timer")
	for _i in 480: # ~8 s at 60 Hz
		await get_tree().physics_frame
	_ok(Overdrive.for_owner(1) != null, "still running after 8 s")
	for _i in 180: # past the 10 s window
		await get_tree().physics_frame
	_ok(Overdrive.for_owner(1) == null, "gone after 10 s")


func _pawn(id: int, bot: bool) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = id
	p.is_bot = bot
	p.name = ("bot%d" % -id) if bot else str(id)
	add_child(p)
	return p
