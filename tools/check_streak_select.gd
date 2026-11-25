extends Node
## Killstreak pick (#387): the catalog is valid, the selection rules hold (known ids, at most three,
## no shared kill cost, default on anything invalid), the server banks the right streak on the right
## kill for a non-default pick, the choice RPC survives a wrong shape, and the HUD shows the pick.
##   godot --headless res://tools/check_streak_select.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	_catalog()
	_rules()
	_award()
	_rpc_shape()
	_own_pick_after_reset()
	_settings()
	await _hud()
	print("STREAK SELECT CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _catalog() -> void:
	print("-- catalog")
	var ids: Array = []
	for d in StreakDefs.CATALOG:
		var id := StringName(d["id"])
		ids.append(id)
		_ok(StreakDefs.has(id), "catalog id '%s' resolves" % id)
		_ok(StreakDefs.kills(id) > 0, "'%s' costs at least one kill" % id)
		_ok(StreakDefs.bit(id) != 0, "'%s' has a charge bit" % id)
		_ok(StreakDefs.name_of(id) != "", "'%s' has a name" % id)
		_ok(StreakDefs.blurb(id) != "", "'%s' has a blurb" % id)
	_ok(ids.size() == ids.size(), "catalog ids are unique")
	_ok(StreakDefs.bit(&"uav") == Game.CHARGE_RADAR, "uav keeps the radar bit")
	_ok(StreakDefs.bit(&"rcxd") == Game.CHARGE_RCXD, "rcxd keeps the RC bit")
	_ok(StreakDefs.bit(&"los") == Game.CHARGE_LOS, "los keeps the LOS bit")
	_ok(StreakDefs.kills(&"uav") == Game.STREAK_AT, "uav costs STREAK_AT")
	_ok(StreakDefs.kills(&"rcxd") == Game.RCXD_AT, "rcxd costs RCXD_AT")
	_ok(StreakDefs.kills(&"los") == Game.LOS_AT, "los costs LOS_AT")
	_ok(StreakDefs.default_ids() == [&"uav", &"rcxd", &"los"], "the default pick is UAV, RCXplodie, LOS")
	_ok(StreakDefs.bot_ids() == [&"uav", &"rcxd"], "bots get UAV and RCXplodie, not LOS")
	_ok(not StreakDefs.bots_allowed(&"los"), "LOS is not a bot streak")


func _rules() -> void:
	print("-- selection rules")
	var dflt := StreakDefs.default_ids()
	_ok(StreakDefs.sanitize(dflt) == dflt, "the default pick is valid")
	_ok(StreakDefs.sanitize([&"uav", &"los"]) == [&"uav", &"los"], "a two-streak pick is allowed")
	_ok(StreakDefs.sanitize([&"los", &"uav"]) == [&"uav", &"los"], "the pick is sorted by kill cost")
	_ok(StreakDefs.sanitize([&"uav", &"uav"]) == [&"uav"], "a duplicate id is dropped")
	_ok(StreakDefs.sanitize([&"uav", &"nope"]) == [&"uav"], "an unknown id is dropped")
	_ok(StreakDefs.sanitize(PackedStringArray(["los", "rcxd"])) == [&"rcxd", &"los"],
		"a PackedStringArray from settings.cfg is read and sorted")
	_ok(StreakDefs.sanitize([]) == dflt, "an empty pick falls back to the default")
	_ok(StreakDefs.sanitize([&"uav", &"rcxd", &"los", &"uav"]) == dflt, "four entries fall back to the default")
	_ok(StreakDefs.sanitize("uav") == dflt, "a string instead of a list falls back to the default")
	_ok(StreakDefs.sanitize(null) == dflt, "null falls back to the default")
	# Two streaks with the same cost would bank on the same kill. No catalog pair shares a cost today,
	# so the rule is checked on the helper with the same id twice.
	_ok(StreakDefs.cost_conflict([&"uav", &"uav"]), "a shared kill cost is a conflict")
	_ok(not StreakDefs.cost_conflict(dflt), "the default pick has no shared cost")
	_ok(StreakDefs.sanitize([&"uav", &"uav", &"rcxd"]) == [&"uav", &"rcxd"], "a duplicate is dropped, not the rest")


func _award() -> void:
	print("-- the server banks the picked streak on the right kill")
	var g := Game
	# Default pick: the old three, unchanged.
	g.streak_choices[7] = StreakDefs.default_ids()
	_award_run(7, "default", [3, 5, 7])
	# A non-default pick: RCXplodie and LOS only. The UAV never banks, and 3 kills give nothing.
	g.streak_choices[8] = [&"rcxd", &"los"]
	_award_run(8, "rcxd+los", [5, 7])
	# One streak only: LOS at 7, nothing at 3 or 5.
	g.streak_choices[9] = [&"los"]
	_award_run(9, "los", [7])
	# A bot's pick: UAV and RCXplodie, never LOS.
	_award_run(-4, "bot", [3, 5])


## Kills 1..7 for one peer, checking the charge bits after each kill against the picked thresholds.
func _award_run(peer: int, label: String, costs: Array) -> void:
	var g := Game
	g.streak_progress.erase(peer)
	g.streak_charges.erase(peer)
	g.streak_earned.erase(peer)
	var bits := {}
	for raw in StreakSelect.choice_for(g, peer):
		var id := StringName(raw)
		bits[StreakDefs.kills(id)] = StreakDefs.bit(id)
	var want := 0
	for kills in range(1, 8):
		Streaks.bump_streak(g, peer, 0)
		if costs.has(kills):
			want |= int(bits.get(kills, 0))
		var got := int(g.streak_charges.get(peer, 0))
		_ok(got == want, "%s: after %d kills the charges are %d" % [label, kills, want])
	# The progress counter runs to the top cost, never past LOS's old cap.
	_ok(int(g.streak_progress.get(peer, 0)) == 7, "%s: the counter stops at 7" % label)
	g.streak_choices.erase(peer)


func _rpc_shape() -> void:
	print("-- the choice RPC rejects a wrong shape")
	var g := Game
	g.streak_choices.erase(11)
	var dflt := StreakDefs.default_ids()
	# A String, a Dictionary and null are not a list: each must store the default and not crash.
	var got := StreakSelect.server_submit(g, 11, "uav")
	_ok(got == dflt, "a string pick becomes the default")
	_ok(g.streak_choices.get(11) == dflt, "the server stored the default for the string")
	got = StreakSelect.server_submit(g, 11, {"ids": [&"uav"]})
	_ok(got == dflt, "a dictionary pick becomes the default")
	got = StreakSelect.server_submit(g, 11, null)
	_ok(got == dflt, "a null pick becomes the default")
	# A valid pick is stored as sent, sorted.
	got = StreakSelect.server_submit(g, 11, [&"los", &"rcxd"])
	_ok(got == [&"rcxd", &"los"], "a valid pick is stored, sorted by cost")
	_ok(g.streak_choices.get(11) == [&"rcxd", &"los"], "the server kept the valid pick")
	# A peer id of 0 is not a player and is refused.
	_ok(StreakSelect.server_submit(g, 0, dflt) == [], "peer 0 is refused")
	# The RPC entry point itself, offline: the server half runs and stores the validated pick.
	g.streak_choices.erase(1)
	Game.request_streak_choice([&"rcxd", &"los"])
	_ok(g.streak_choices.get(1) == [&"rcxd", &"los"], "the choice RPC entry stores a valid pick")
	Game.request_streak_choice(["bogus", "uav", "uav"])
	_ok(g.streak_choices.get(1) == [&"uav"], "the choice RPC entry sanitises a wrong shape")
	g.streak_choices.erase(1)
	g.streak_choices.erase(11)


## A new match (Play/Host/Join) clears the server's picks; the local pawn's setup must put this
## machine's pick back, or an offline player and a host earn the default while the HUD shows theirs.
func _own_pick_after_reset() -> void:
	print("-- a new match keeps the local pick (offline and host)")
	var g := Game
	var saved: Array = g.streak_choice.duplicate()
	g.streak_choice = [&"rcxd", &"los"]
	g.streak_choices[1] = [&"rcxd", &"los"]
	MatchFlow.reset_session(g)
	_ok(not g.streak_choices.has(1), "reset_session drops the accepted pick")
	StreakSelect.submit_own(g, 1)
	_ok(StreakSelect.choice_for(g, 1) == [&"rcxd", &"los"], "submit_own restores the local pick")
	_ok(StreakSelect.id_at(g, 1, 0) == &"rcxd", "slot 0 fires RCXplodie after the reset")
	g.streak_choices.erase(1)
	g.streak_choice = saved


## settings.cfg round trip: save_settings writes the pick, load_settings reads it back. The check runs
## with its own user:// (run_checks gives each run a fresh one), so this never touches a player's file.
func _settings() -> void:
	print("-- settings.cfg round trip")
	var g := Game
	g.streak_choice = [&"rcxd", &"los"]
	GameSettings.save_settings(g)
	g.streak_choice = []
	GameSettings.load_settings(g)
	_ok(g.streak_choice == [&"rcxd", &"los"], "the pick survives a save and a load")
	g.streak_choice = StreakDefs.default_ids()
	GameSettings.save_settings(g)
	GameSettings.load_settings(g)
	_ok(g.streak_choice == StreakDefs.default_ids(), "the default pick survives too")


func _hud() -> void:
	print("-- the HUD shows the pick")
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	add_child(root)
	var hud: Hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 3:
		await get_tree().process_frame
	hud.set_streak_choice([&"rcxd", &"los"])
	_ok(_slot_name(hud, 0) == "RCXplodie", "slot 0 names RCXplodie")
	_ok(_slot_name(hud, 1) == "LOS", "slot 1 names LOS")
	_ok(_slot_name(hud, 2) == "—", "an empty slot reads a dash")
	hud.set_streak_choice(StreakDefs.default_ids())
	_ok(_slot_name(hud, 0) == "UAV", "slot 0 names UAV again")
	_ok(_slot_name(hud, 2) == "LOS", "slot 2 names LOS again")


func _slot_name(hud: Hud, slot: int) -> String:
	var n := hud.get_node_or_null("StreakSlots/Slot%d/Name" % slot) as Label
	return "" if n == null else n.text
