extends Node
## #250 step 1: play the same seeded bot match per map and diff it against a baseline.
##   tools/replay_match.sh [map] [--update-baseline] [seed] [ticks]   (fresh user://, fixed 60 fps; see there)
##   godot --headless --fixed-fps 60 res://tools/replay_match.tscn -- [map] [--update-baseline] [seed] [ticks]
## Defaults: quay, seed 1234, 2700 ticks (45 s at 60 Hz), TDM with 6 Hard bots.
## Deterministic run to run at --fixed-fps 60: the match RNG is seeded (Game.set_rng_seed), each
## BotBrain rng is seeded by slot, TDM respawns on fixed team spots and navigation updates are made
## synchronous (Godot threads them by default, so the first path would land on a varying frame).
## What the summary holds: team score, kills per weapon, deaths per weapon, per-move counts and a
## quantised position hash per bot every 5 s. Counts may drift 20% (tolerance); hashes are only
## reported, never failed on: a movement tweak always changes them.
##   godot --headless --fixed-fps 60 res://tools/replay_match.tscn -- skyline --update-baseline
const BOTS := 6
const SEED := 1234
const TICKS := 2700
const HASH_EVERY := 300 # ticks: 5 s
const TOLERANCE := 0.2
const MAPS := ["quay", "foundry", "townhouses", "rooftops", "skyline"]
const BASELINE_DIR := "res://tools/replay_baseline"
const PARK := Vector3(0, 400, 0)
const MOVES := {Player.MOVE_DIVE: "dive", Player.MOVE_WALLRUN: "wallrun", Player.MOVE_ROLL: "roll"}

var _kills: Dictionary = {} # weapon -> count
var _deaths: Dictionary = {} # weapon -> count
var _moves: Dictionary = {"dive": 0, "wallrun": 0, "roll": 0, "slide": 0}
var _hashes: Array = [] # [{t, hash}]
var _stance := {"ticks": 0, "slide": 0, "dive": 0, "roll": 0, "plain": 0} # #371
## #382: a bot that sees an enemy within reach and does nothing. Per bot the longest run of ticks in that
## state, with the style and the behaviour state it was in; the summary keeps it so a run can be compared.
const IDLE_RANGE := 30.0
const IDLE_ACT_TICKS := 60 # 1 s: a shot, grenade, stab or slide this recent still counts as acting
var _idle: Dictionary = {} # peer -> {max, state, style, streak, last_act, ammo, nades, melee}


func _box(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var s := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	s.shape = sh
	b.add_child(s)
	get_tree().root.add_child(b)
	b.global_position = pos


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id := StringName(args[0]) if args.size() > 0 and args[0] in MAPS else &"quay"
	var update := args.has("--update-baseline")
	var seed_v := SEED
	var ticks := TICKS
	for a in args:
		if a.is_valid_int() and int(a) > 100:
			ticks = int(a)
		elif a.is_valid_int():
			seed_v = int(a)
	if not map_id in MAPS:
		print("REPLAY CHECK FAIL: unknown map %s" % map_id)
		get_tree().quit(1)
		return
	Game.set_rng_seed(seed_v)
	seed(1)
	# Godot updates navigation maps and regions on a worker thread by default: the frame a bot first gets
	# a path would vary run to run.
	NavigationServer3D.map_set_use_async_iterations(get_viewport().world_3d.navigation_map, false)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is NavigationRegion3D:
			NavigationServer3D.region_set_use_async_iterations((n as NavigationRegion3D).get_rid(), false))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(map_id, Game.MODE_TDM)
	Game.last_bots = BOTS
	Game.bot_count = BOTS
	for b in menu._bot_boxes:
		b.value = BOTS
	for b in menu._ally_boxes:
		b.value = BOTS / 2 - 1
	for b in menu._enemy_boxes:
		b.value = BOTS / 2
	for o in menu._skill_opts:
		o.selected = BotProfiles.HARD
	Game.last_bot_difficulty = BotProfiles.HARD
	Game.bot_difficulty = BotProfiles.HARD
	menu.play_local_pressed.emit()
	Game.bot_difficulty = BotProfiles.HARD
	var me: Player = null
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not Game.play_locked() and Game._round_active:
			break
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	Game.kill_feed.connect(_on_kill)
	_box(PARK + Vector3(0, -0.5, 0), Vector3(6, 1, 6))
	me._spawn_protect = 1.0e9
	await get_tree().physics_frame
	me.global_position = PARK + Vector3(1.2, 0, 0)
	me.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var last_fx: Dictionary = {}
	var _was_sliding: Dictionary = {}
	for t in ticks:
		await get_tree().physics_frame
		for p in Game.players():
			if not p.is_bot:
				continue
			var was := int(last_fx.get(p.peer_id, Player.MOVE_NONE))
			var now := int(p.move_fx)
			if now != was and MOVES.has(now):
				_moves[MOVES[now]] += 1
			last_fx[p.peer_id] = now
			var sliding := bool(p._sliding)
			if sliding and not bool(_was_sliding.get(p.peer_id, false)):
				_moves["slide"] += 1
			_was_sliding[p.peer_id] = sliding
		if (t + 1) % HASH_EVERY == 0:
			_hashes.append({"t": (t + 1) / 60, "hash": _position_hash()})
		_stance_tick()
		_idle_tick(t)
	var summary := _summary(map_id, seed_v, ticks)
	Game.kill_feed.disconnect(_on_kill)
	var code := _compare(map_id, summary, update)
	get_tree().quit(code)


## #371: how the bots stand, counted on the same deterministic run as the rest of the summary.
func _stance_tick() -> void:
	for p in Game.players():
		if not p.is_bot or p.is_dead:
			continue
		_stance["ticks"] = int(_stance["ticks"]) + 1
		if p.crouch <= 0.5:
			continue
		if p._sliding:
			_stance["slide"] = int(_stance["slide"]) + 1
		elif p._diving:
			_stance["dive"] = int(_stance["dive"]) + 1
		elif p._roll_t > 0.0:
			_stance["roll"] = int(_stance["roll"]) + 1
		else:
			_stance["plain"] = int(_stance["plain"]) + 1


## #382: longest idle run per bot, in seconds, with its style and state; and the worst per style.
## Own line-of-sight ray, not the brain's: calling _can_see(..., true) from a probe writes the bot's LOS
## cache and would change the match it is measuring (#382).
func _sees(p: Player, foe: Player) -> bool:
	var space := p.get_world_3d().direct_space_state
	var from := p.head.global_position
	for to in [(foe as Player).aim_point(), (foe as Player).head_point()]:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1 | 2 # the brain's SHOT_MASK: world and pawns
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.get("collider") == foe:
			return true
	return false


func _idle_summary() -> Dictionary:
	var out := {"bots": {}, "styles": {}}
	for id in _idle:
		var rec: Dictionary = _idle[id]
		var secs: float = round(10.0 * float(rec["max"]) / 60.0) / 10.0
		out["bots"][str(id)] = {"max_s": secs, "style": rec["style"], "state": rec["state"],
			"spd": round(10.0 * float(rec.get("spd", 0.0))) / 10.0, "dist": round(float(rec.get("dist", 0.0))),
			"ammo": int(rec.get("ammo", 0)), "rc": bool(rec.get("rc", false))}
		var st: String = String(rec["style"])
		out["styles"][st] = maxf(float(out["styles"].get(st, 0.0)), secs)
	return out


func _stance_pct(key: String) -> float:
	var n := int(_stance["ticks"])
	return 0.0 if n == 0 else round(1000.0 * float(_stance[key]) / float(n)) / 10.0


## #382: every tick, per bot: does it see an enemy within reach, and has it done anything in the last
## second? A run of such ticks is a bot standing around while it has business with you. Walking in a ring
## counts as doing nothing: only shots, grenades, stabs and slides reset the clock.
func _idle_tick(t: int) -> void:
	for p in Game.players():
		if not p.is_bot or p._bot_brain == null or p.is_dead:
			continue
		var b = p._bot_brain
		var rec: Dictionary = _idle.get(p.peer_id, {"max": 0, "state": "", "style": "", "streak": 0,
			"last_act": -100000, "ammo": 0, "nades": 0, "melee": 0.0})
		var ammo: int = p.weapon.ammo if p.weapon != null else 0
		var nades: int = p.grenades
		var melee: float = p.weapon._melee_cd if p.weapon != null else 0.0
		var acted := ammo < int(rec["ammo"]) or nades < int(rec["nades"]) or melee > float(rec["melee"]) + 0.01 or p._sliding
		rec["ammo"] = ammo
		rec["nades"] = nades
		rec["melee"] = melee
		if acted:
			rec["last_act"] = t
		# The brain's own sight test on its current target, freshly: _seen_target is only ever set, never
		# cleared, so reading that field counts phantom enemies behind walls (#382).
		var seen := false
		var foe = b._target
		if foe != null and is_instance_valid(foe) and not (foe as Player).is_dead:
			seen = p.global_position.distance_to((foe as Player).global_position) <= IDLE_RANGE and _sees(p, foe)
		# Travelling counts as acting too (#382): a bot that really changes position is not idling, a bot
		# that circles in place is. The anchor is the spot where the streak started.
		if int(rec["streak"]) == 0 or rec.get("anchor") == null:
			rec["anchor"] = p.global_position
		elif p.global_position.distance_to(rec["anchor"] as Vector3) > 3.0:
			rec["last_act"] = t
			rec["anchor"] = p.global_position
		var recent := t - int(rec["last_act"]) <= IDLE_ACT_TICKS
		if seen and not recent:
			rec["streak"] = int(rec["streak"]) + 1
			rec["state"] = String(Player.Brain.State.keys()[b.state]) if b.state < Player.Brain.State.size() else "?"
			rec["style"] = String(b.style.id) if b.style != null else "?"
			if int(rec["streak"]) > int(rec["max"]):
				rec["max"] = rec["streak"]
				rec["spd"] = sqrt(p.velocity.x * p.velocity.x + p.velocity.z * p.velocity.z)
				rec["dist"] = p.global_position.distance_to((foe as Player).global_position) if foe != null else 0.0
				rec["ammo"] = ammo
				rec["rc"] = p.rc_view if "rc_view" in p else false
		else:
			rec["streak"] = 0
		_idle[p.peer_id] = rec


func _on_kill(_kn: String, _vn: String, weapon_id: StringName, _kt: int, _vt: int, _tricks: String) -> void:
	var w := String(weapon_id)
	_kills[w] = int(_kills.get(w, 0)) + 1
	_deaths[w] = int(_deaths.get(w, 0)) + 1


## Quantised positions of every bot, so a small drift in one bot shows up as a different hash.
func _position_hash() -> int:
	var parts: Array[String] = []
	var bots: Array[Player] = []
	for p in Game.players():
		if p.is_bot:
			bots.append(p)
	bots.sort_custom(func(a: Player, b: Player) -> bool: return a.peer_id > b.peer_id)
	for p in bots:
		var pos := p.global_position
		parts.append("%d:%.1f,%.1f,%.1f" % [p.peer_id, pos.x, pos.y, pos.z])
	return hash(",".join(parts))


func _team_scores() -> Array:
	var out := [0, 0]
	for id in Game.scores:
		var s: Dictionary = Game.scores[id]
		var team := int(s.get("team", 0))
		if team >= 0 and team < 2:
			out[team] += int(s.get("kills", 0))
	return out


func _summary(map_id: StringName, seed_v: int, ticks: int) -> Dictionary:
	return {
		"map": String(map_id),
		"mode": Game.mode_name(),
		"bots": BOTS,
		"seed": seed_v,
		"ticks": ticks,
		"teams": _team_scores(),
		"kills": _sorted(_kills),
		"deaths": _sorted(_deaths),
		"moves": _sorted(_moves),
		"stance_pct": {"slide": _stance_pct("slide"), "dive": _stance_pct("dive"),
			"roll": _stance_pct("roll"), "plain": _stance_pct("plain")},
		"idle": _idle_summary(),
		"hashes": _hashes,
	}


func _sorted(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = d[k]
	return out


func _print_idle(now: Dictionary) -> void:
	var idle: Dictionary = now.get("idle", {})
	for id in idle.get("bots", {}):
		var row: Dictionary = idle["bots"][id]
		print("  idle bot %s: %.1f s (%s / %s, spd %.1f, dist %.0f m, ammo %d%s)" % [str(id), float(row["max_s"]),
			str(row["style"]), str(row["state"]), float(row.get("spd", 0.0)), float(row.get("dist", 0.0)),
			int(row.get("ammo", 0)), ", RC" if bool(row.get("rc", false)) else ""])
	for st in idle.get("styles", {}):
		print("  idle style %s: %.1f s" % [str(st), float(idle["styles"][st])])


func _baseline_path(map_id: StringName) -> String:
	return "%s/%s.json" % [BASELINE_DIR, map_id]


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed


## Writes the baseline, or diffs against it. Counts fail outside TOLERANCE; hashes only report.
func _compare(map_id: StringName, now: Dictionary, update: bool) -> int:
	var path := _baseline_path(map_id)
	if update or _read(path) == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASELINE_DIR))
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify(now, "  "))
		f.close()
		print("REPLAY %s: baseline geschreven -> %s" % [map_id, path])
		_print_idle(now)
		print("REPLAY CHECK OK")
		return 0
	var old: Dictionary = _read(path)
	var fails := 0
	print("REPLAY %s (%s, seed %d, %d ticks)" % [map_id, now.mode, now.seed, now.ticks])
	for section in ["kills", "deaths", "moves"]:
		var a: Dictionary = old.get(section, {})
		var b: Dictionary = now.get(section, {})
		var keys := a.keys()
		for k in b.keys():
			if not k in keys:
				keys.append(k)
		keys.sort()
		for k in keys:
			var was := int(a.get(k, 0))
			var is_now := int(b.get(k, 0))
			var limit := maxi(1, int(round(float(maxi(was, is_now)) * TOLERANCE)))
			if absi(is_now - was) > limit:
				print("  DIFF %s %s: %d -> %d (tol %d)" % [section, k, was, is_now, limit])
				fails += 1
	var ot: Array = old.get("teams", [0, 0])
	var nt: Array = now.get("teams", [0, 0])
	for i in 2:
		var was := int(ot[i])
		var is_now := int(nt[i])
		var limit := maxi(1, int(round(float(maxi(was, is_now)) * TOLERANCE)))
		if absi(is_now - was) > limit:
			print("  DIFF team %d kills: %d -> %d (tol %d)" % [i, was, is_now, limit])
			fails += 1
	var oh: Array = old.get("hashes", [])
	var nh: Array = now.get("hashes", [])
	var changed := 0
	for i in mini(oh.size(), nh.size()):
		if int(oh[i].get("hash", 0)) != int(nh[i].get("hash", 0)):
			changed += 1
	print("  posities: %d/%d hashes anders (alleen ter info)" % [changed, nh.size()])
	var os_: Dictionary = old.get("stance_pct", {})
	var ns: Dictionary = now.get("stance_pct", {})
	print("  stance: plain %.1f%% -> %.1f%% | slide %.1f%% -> %.1f%%" % [
		float(os_.get("plain", 0.0)), float(ns.get("plain", 0.0)),
		float(os_.get("slide", 0.0)), float(ns.get("slide", 0.0))])
	_print_idle(now)
	if fails > 0:
		print("REPLAY CHECK FAIL (%d diffs buiten tolerantie)" % fails)
		return 1
	print("REPLAY CHECK OK")
	return 0
