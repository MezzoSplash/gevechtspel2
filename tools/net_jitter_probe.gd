extends Node
## Manual high-ping probe (not in run_checks). Start a dedicated server on 7799, then two clients:
##   godot --headless res://tools/net_jitter_probe.tscn -- --probe-role mover
##   godot --headless res://tools/net_jitter_probe.tscn -- --probe-role watcher
## The mover slides its pawn back and forth and jumps every other second; the watcher reports how long
## the mover's pose stays frozen, how big a single-frame step is, how long the pawn hangs in the air
## after a jump (#365), and how far apart (arrival - sender stamp) is, which tells whether the pose and
## its stamp ride in one replication packet. Point the clients at tools/netsim_proxy.py (PROBE_PORT=7800)
## for a lossy link.

const PROBE_S := 20.0
const JUMP_M := 1.0 # apex of the jump the mover makes every JUMP_EVERY seconds
const JUMP_EVERY := 2.0

var _role := ""
var _me: Player = null
var _t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--probe-role")
	_role = args[i + 1] if i >= 0 and i + 1 < args.size() else "watcher"
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_host_ip("127.0.0.1")
	menu.set_host_port(int(OS.get_environment("PROBE_PORT")) if OS.has_environment("PROBE_PORT") else 7799)
	menu.connect_pressed.emit()
	for k in 300:
		await get_tree().create_timer(0.1).timeout
		_me = Game.player_for_peer(multiplayer.get_unique_id())
		if _me and not Game.play_locked():
			break
	if _me == null:
		print("PROBE could not join (no pawn) — is the server up on the port?")
		get_tree().quit(2)
		return
	if _role == "mover":
		_move()
	else:
		_watch()


## A jump every JUMP_EVERY seconds: up for half of it, so the watcher can see a pawn hang in the air.
static func jump_height(t: float) -> float:
	var u := fmod(t, JUMP_EVERY) / (JUMP_EVERY * 0.5)
	return 4.0 * u * (1.0 - u) * JUMP_M if u <= 1.0 else 0.0


func _move() -> void:
	var base := _me.global_position
	while _t < PROBE_S + 40.0:
		await get_tree().physics_frame
		_t += get_physics_process_delta_time()
		_me.global_position = base + Vector3(sin(_t * 2.0) * 3.0, jump_height(_t), 0.0)
	get_tree().quit()


func _watch() -> void:
	var other: Player = null
	var waited := 0
	while other == null and waited < 100:
		await get_tree().create_timer(0.2).timeout
		waited += 1
		for p in get_tree().get_nodes_in_group("player"):
			# Same match as me: the menu's background match leaves pawns in another world, and those
			# get teleported between spawns (#360/#361 debugging found them here).
			if p != _me and not p.is_bot and _me != null and p.get_parent() == _me.get_parent():
				other = p
	if other == null:
		print("PROBE no other player in this match")
		get_tree().quit(2)
		return
	var last := other.global_position
	var floor_y := other.global_position.y
	var last_ms := Time.get_ticks_msec()
	var gaps: Array[int] = []
	var steps: Array[float] = [] # #361: how far the pawn moved in one frame — a jump reads here
	var teleports := 0
	var air := 0 # frames with the pawn off the floor
	var over := 0 # frames above the apex: that is the hover #365 describes
	var max_y := 0.0
	var off_min := 1 << 30
	var off_max := -(1 << 30)
	var frames := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < PROBE_S * 1000.0:
		await get_tree().physics_frame
		frames += 1
		var d := other.global_position.distance_to(last)
		if d > 10.0:
			# A respawn or a join teleport: #361 draws those at once on purpose, so they are not a
			# smoothness sample.
			teleports += 1
			last = other.global_position
			floor_y = other.global_position.y
			last_ms = Time.get_ticks_msec()
			continue
		if d > 0.001:
			gaps.append(Time.get_ticks_msec() - last_ms)
			last = other.global_position
			last_ms = Time.get_ticks_msec()
		steps.append(d)
		var h := other.global_position.y - floor_y
		if h > 0.15:
			air += 1
		if h > JUMP_M + 0.15:
			over += 1
		max_y = maxf(max_y, h)
		if other.get("_pose_off_last") != null and other._pose_off_last != 0:
			off_min = mini(off_min, int(other._pose_off_last))
			off_max = maxi(off_max, int(other._pose_off_last))
	steps.sort()
	gaps.sort()
	var big := gaps.filter(func(g): return g > 250).size()
	print("PROBE updates=%d p50=%d p99=%d max=%d frozen>250ms=%d | step p50=%.3f p99=%.3f max=%.2f m (jumps>0.5m=%d, teleports=%d) | air=%d%% max_y=%.2f m over_apex=%d | stamp spread=%d ms" % [
		gaps.size(), gaps[gaps.size() / 2], gaps[int(gaps.size() * 0.99)], gaps[-1], big,
		steps[steps.size() / 2], steps[int(steps.size() * 0.99)], steps[-1],
		steps.filter(func(s): return s > 0.5).size(), teleports,
		int(100.0 * float(air) / maxf(float(frames), 1.0)), max_y, over,
		(off_max - off_min) if off_max > off_min else -1])
	get_tree().quit()
