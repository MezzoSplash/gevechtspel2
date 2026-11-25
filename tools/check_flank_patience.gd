extends Node
## #382: a flanker whose target keeps looking at it must still reach its patience. It only fires from the
## side; when the target keeps turning to face it, `from_side` is never true, so the only way it ever shoots
## is flank_patience. Before this, every single tick without sight wiped the patience, and a target that
## dips in and out of view (a corner, a crate, a wall, cover) reset it forever: the bot circled and never
## fired. Simulates 0.5 s of sight and 0.3 s without, over and over, and fails when the flanker has not
## fired within flank_patience + 0.5 s.
##   godot --headless --path . res://tools/check_flank_patience.tscn
const SEEN_S := 0.5
const BLIND_S := 0.3
const SLACK_S := 0.5
const DIST := 8.0

var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _pawn(peer: int, team: int) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = peer
	p.is_bot = false
	p.team_id = team
	p.set_physics_process(false)
	add_child(p)
	p.add_to_group("player")
	return p


func _ready() -> void:
	await get_tree().physics_frame
	var flanker_style: BotStyle = null
	for f in DirAccess.get_files_at("res://data/bots"):
		if f.begins_with("flanker"):
			flanker_style = load("res://data/bots/%s" % f) as BotStyle
	_ok(flanker_style != null and flanker_style.flank_only, "flanker-stijl gevonden (flank_only)")
	if flanker_style == null:
		get_tree().quit(1)
		return
	var pawn := _pawn(-1, 0)
	var foe := _pawn(-2, 1)
	pawn.global_position = Vector3(0, 300, 0)
	foe.global_position = Vector3(0, 300, -DIST)
	await get_tree().physics_frame
	var brain := BotBrain.new()
	brain.pawn = pawn
	brain.style = flanker_style
	# The target keeps looking straight at the flanker: from_side is never true, so only patience helps.
	foe.look_at(Vector3(pawn.global_position.x, foe.global_position.y, pawn.global_position.z), Vector3.UP)
	foe.rotation.x = 0.0
	foe.rotation.z = 0.0
	var dt := 1.0 / 60.0
	var t := 0.0
	var fired_at := -1.0
	var patience: float = flanker_style.flank_patience
	var limit := patience + SLACK_S
	while t < limit + 1.0:
		var phase := fmod(t, SEEN_S + BLIND_S)
		var seen := phase < SEEN_S
		if brain.has_method("_tick_flank_sight"):
			brain._tick_flank_sight(seen, dt)
		elif not seen:
			brain._flank_wait = 0.0 # the old code: any tick without sight wiped the patience (#382)
		elif seen:
			brain._flank_wait += dt
		if seen and brain._flank_aim_ok(foe, dt):
			fired_at = t
			break
		t += dt
	_ok(fired_at >= 0.0 and fired_at <= limit,
		"flanker schiet binnen %.1f s (geduld %.1f + %.1f), gevuurd op %.1f s" % [limit, patience, SLACK_S, fired_at])
	# A real loss of sight (longer than the grace) still starts the patience over.
	brain._flank_wait = 0.0
	brain._flank_lost = 0.0
	if brain.has_method("_tick_flank_sight"):
		var grace: float = brain.FLANK_SIGHT_GRACE
		for i in int((grace + 0.4) / dt):
			brain._tick_flank_sight(false, dt)
		_ok(brain._flank_lost > grace, "na %.1f s zonder zicht begint het geduld opnieuw (lost %.1f s)" % [
			grace, brain._flank_lost])
	print("FLANK PATIENCE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
