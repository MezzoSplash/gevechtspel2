extends Node
## #371: how much of the time bots walk around crouched. Manual probe, not a check (run_checks skips
## probe_*): the same metric is deterministic inside tools/replay_match (stance_pct in the baseline), and
## this one is the client/server comparison — with --client it joins a dedicated server and measures what
## a player actually sees. Its per-run numbers swing (the match start differs), so treat it as a probe.
## Samples every physics tick of a bot match and
## splits it per bot: sliding, diving, rolling, and "plain" (crouch > 0.5 without any of those — the
## crawl Gianni saw). Prints one line per map plus a total, and fails when plain crouch is 5% or more.
##   godot --headless --fixed-fps 60 res://tools/probe_bot_stance.tscn -- [map|all] [ticks]
##   godot --headless --fixed-fps 60 res://tools/probe_bot_stance.tscn -- --client [port]
## The client mode joins a dedicated server and samples the remote bots' synced crouch, which is what a
## player actually sees; the server's own loop is the same without --client.
## Run it with a clean user:// like tools/replay_match.sh (XDG_DATA_HOME), or saved menu choices count.
const BOTS := 6
const TICKS := 1800 # 30 s at 60 Hz
const MAPS := ["quay", "foundry", "townhouses", "rooftops", "skyline"]
const PARK := Vector3(0, 400, 0)
const LIMIT := 0.05 # plain crouch may be this much of the time at most

var _plain := 0
var _slide := 0
var _dive := 0
var _roll := 0
var _samples := 0
var _per_bot: Dictionary = {} # peer -> [plain, total]
var _plain_want := 0 # crouched because the bot holds the key
var _plain_stuck := 0 # crouched without the key: the stance does not come back up
var _plain_ceil := 0 # of those: a ceiling keeps it crouched
var _last_pos: Dictionary = {} # peer -> last sampled position: the client copy does not carry velocity
var _trace: Dictionary = {} # peer -> {n, plain, buckets, stamps, sent_last, dead}


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
	var host := args.has("--host")
	if host:
		await _host(args)
		return
	var client := args.has("--client")
	if client:
		await _client(args)
		return
	var map_id := StringName(args[0]) if args.size() > 0 and args[0] in MAPS else &"quay"
	var ticks := int(args[1]) if args.size() > 1 and args[1].is_valid_int() else TICKS
	seed(1)
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
	_box(PARK + Vector3(0, -0.5, 0), Vector3(6, 1, 6))
	me._spawn_protect = 1.0e9
	await get_tree().physics_frame
	me.global_position = PARK + Vector3(1.2, 0, 0)
	me.velocity = Vector3.ZERO
	for t in ticks:
		await get_tree().physics_frame
		_sample()
	_report(String(map_id))


## Listen server: the same match Gianni plays when he hosts. Prints one trace line per bot per second, so a
## client trace of the same match can be laid next to it per peer id (#371).
func _host(args: Array) -> void:
	var port := int(args[args.find("--host") + 1]) if args.find("--host") + 1 < args.size() else 7799
	seed(1)
	NavigationServer3D.map_set_use_async_iterations(get_viewport().world_3d.navigation_map, false)
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is NavigationRegion3D:
			NavigationServer3D.region_set_use_async_iterations((n as NavigationRegion3D).get_rid(), false))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_TDM)
	menu.set_host_port(port)
	Game.last_bots = BOTS
	Game.bot_count = BOTS
	for b in menu._bot_boxes:
		b.value = BOTS
	for b in menu._ally_boxes:
		b.value = BOTS / 2
	for b in menu._enemy_boxes:
		b.value = BOTS / 2
	for o in menu._skill_opts:
		o.selected = BotProfiles.HARD
	Game.last_bot_difficulty = BotProfiles.HARD
	menu.host_pressed.emit()
	var me: Player = null
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not Game.play_locked():
			break
	if main.class_select != null and main.class_select.is_open():
		main.class_select.close_silently()
	Game.pause_open = false
	_trace_loop("srv", 45)


## One line per second per bot: what the authority has, or what a client received.
func _trace_loop(tag: String, seconds: int) -> void:
	for sec in seconds:
		await get_tree().create_timer(1.0).timeout
		var last: Dictionary = _last_pos
		for p in Game.players():
			if not p.is_bot:
				continue
			var prev: Variant = last.get(p.peer_id)
			var spd := 0.0 if prev == null else Vector2(p.global_position.x - (prev as Vector3).x, p.global_position.z - (prev as Vector3).z).length()
			last[p.peer_id] = p.global_position
			print("T%d %s %d crouch=%.2f fx=%d dead=%s spd=%.1f" % [sec, tag, p.peer_id, p.crouch, p.move_fx, str(p.is_dead), spd])
	_report(tag)


func _client(args: Array) -> void:
	var port := int(args[args.find("--client") + 1]) if args.find("--client") + 1 < args.size() else 7799
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_host_ip("127.0.0.1")
	menu.set_host_port(port)
	menu.connect_pressed.emit()
	var me: Player = null
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me and not Game.play_locked():
			break
	if me == null:
		print("STANCE CHECK FAIL: kon niet joinen op poort %d" % port)
		get_tree().quit(1)
		return
	for t in TICKS:
		await get_tree().physics_frame
		_sample()
	_report("client")


## One tick of every bot that is alive and in the world. `crouch` is the stance the pawn shows, so this
## works the same on the server and on a client copy filled by sync_bot_poses.
func _sample() -> void:
	for p in Game.players():
		if not p.is_bot or p.is_dead:
			continue
		# A bot copy on a client never learns that its bot died (health stays 0 there), so a bot that died
		# mid-slide keeps crouch = 1.0 forever and would count as crawling while standing still. The complaint
		# is a bot that walks crouched, so only ticks with real movement count.
		var last: Variant = _last_pos.get(p.peer_id)
		var speed := 0.0 if last == null else Vector2(p.global_position.x - (last as Vector3).x, p.global_position.z - (last as Vector3).z).length() / maxf(get_physics_process_delta_time(), 0.001)
		_last_pos[p.peer_id] = p.global_position
		var low := p.crouch > 0.5 and speed > 1.0
		var row: Array = _per_bot.get(p.peer_id, [0, 0])
		row[1] += 1
		_samples += 1 # every bot tick: the denominator for the percentages
		if not low:
			_per_bot[p.peer_id] = row
			continue
		if p._sliding:
			_slide += 1
		elif p.move_fx == Player.MOVE_DIVE:
			_dive += 1
		elif p.move_fx == Player.MOVE_ROLL:
			_roll += 1
		else:
			_plain += 1
			row[0] += 1
			if p._in_crouch:
				_plain_want += 1
			else:
				_plain_stuck += 1
				if PawnBody.ceiling_blocked(p):
					_plain_ceil += 1
		_per_bot[p.peer_id] = row


func _pct(n: int) -> float:
	return 0.0 if _samples == 0 else 100.0 * float(n) / float(_samples)


func _report(where: String) -> void:
	var worst := 0.0
	var worst_bot := 0
	for id in _per_bot:
		var row: Array = _per_bot[id]
		if int(row[1]) <= 0:
			continue
		var share := float(row[0]) / float(row[1])
		if share > worst:
			worst = share
			worst_bot = int(id)
	print("STANCE %s: %d samples | slide %.1f%% dive %.1f%% roll %.1f%% plain %.1f%% (worst bot %d: %.1f%%) | plain by key %.1f%% by stuck %.1f%% (ceiling %.1f%%)" % [
		where, _samples, _pct(_slide), _pct(_dive), _pct(_roll), _pct(_plain), worst_bot, worst * 100.0,
		_pct(_plain_want), _pct(_plain_stuck), _pct(_plain_ceil)])
	for id in _trace:
		var tr: Dictionary = _trace[id]
		var hist := ""
		for b in range(10):
			hist += "%d " % int((tr["buckets"] as Dictionary).get(b, 0))
		print("  bot %d: n=%d plain=%d dead=%s hist[0..1]=%s" % [int(id), int(tr["n"]), int(tr["plain"]), str(tr["dead"]), hist])
	var ok := _pct(_plain) < LIMIT * 100.0 and _samples > 100
	print("BOT STANCE CHECK %s" % ("OK" if ok else "FAIL (plain crouch above %.0f%%)" % (LIMIT * 100.0)))
	get_tree().quit(0 if ok else 1)
