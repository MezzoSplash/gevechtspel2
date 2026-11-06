extends Node
## #B4 headless: the server counts the rounds. A networked client cannot keep shooting without
## reloading, and cannot skip the reload time by bumping its magazine counter.
##   godot --headless --path . res://tools/check_reload.tscn   → "RELOAD CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var def := load("res://data/weapons/smg.tres") as WeaponDef
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.set_physics_process(false)
	add_child(p)
	p.peer_id = 11 # a remote human: strict path
	Game._mags.clear()

	# A whole magazine fires; the next round is refused.
	var fired := 0
	for i in def.mag_size:
		if not Combat.mag_for(Game, p, def, 1, true).is_empty():
			fired += 1
	_ok(fired == def.mag_size, "the whole magazine fires (%d of %d)" % [fired, def.mag_size])
	_ok(Combat.mag_for(Game, p, def, 1, true).is_empty(), "an empty magazine refuses the next shot")

	# Bumping the counter does not skip the reload.
	_ok(Combat.mag_for(Game, p, def, 2, true).is_empty(), "a bumped counter does not skip the reload")

	# A "fresh magazine" halfway through the gun is refused too: the counter is not the truth.
	Game._mags.clear()
	Combat.mag_for(Game, p, def, 1, true)
	Combat.mag_for(Game, p, def, 1, true)
	_ok(Combat.mag_for(Game, p, def, 2, true).is_empty(), "a fresh magazine on a half-full gun is refused")

	# After the reload time it is a real fresh magazine.
	Game._mags.clear()
	for i in def.mag_size:
		Combat.mag_for(Game, p, def, 1, true)
	Game._mags[11][def.id]["last_s"] -= def.reload_time
	_ok(not Combat.mag_for(Game, p, def, 2, true).is_empty(), "after the reload time the fresh magazine is accepted")

	# The local path stays lenient on purpose: offline play, the host's own pawn and bots are not a
	# cheat surface, and a bot must never run dry because of a server rule.
	Game._mags.clear()
	var lenient := 0
	for i in def.mag_size * 2:
		if not Combat.mag_for(Game, p, def, 0).is_empty():
			lenient += 1
	_ok(lenient == def.mag_size * 2, "the local path still never refuses (%d of %d)" % [lenient, def.mag_size * 2])

	print("RELOAD CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
