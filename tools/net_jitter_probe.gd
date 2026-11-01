extends Node
## Manual high-ping probe (not in run_checks). Start a dedicated server on 7799, then two clients:
##   godot --headless res://tools/net_jitter_probe.tscn -- --probe-role mover
##   godot --headless res://tools/net_jitter_probe.tscn -- --probe-role watcher
## The mover slides its pawn back and forth; the watcher logs how long the mover's pose stays
## frozen on its screen. Point the clients at tools/netsim_proxy.py (PROBE_PORT=7800) for a lossy link.

const PROBE_S := 20.0

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
	if _role == "mover":
		_move()
	else:
		_watch()


func _move() -> void:
	var base := _me.global_position
	while _t < PROBE_S + 40.0:
		await get_tree().physics_frame
		_t += get_physics_process_delta_time()
		_me.global_position = base + Vector3(sin(_t * 2.0) * 3.0, 0.0, 0.0)
	get_tree().quit()


func _watch() -> void:
	var other: Player = null
	while other == null:
		await get_tree().create_timer(0.2).timeout
		for p in get_tree().get_nodes_in_group("player"):
			if p != _me and not p.is_bot:
				other = p
	var last := other.global_position
	var last_ms := Time.get_ticks_msec()
	var gaps: Array[int] = []
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < PROBE_S * 1000.0:
		await get_tree().physics_frame
		if other.global_position.distance_to(last) > 0.001:
			gaps.append(Time.get_ticks_msec() - last_ms)
			last = other.global_position
			last_ms = Time.get_ticks_msec()
	gaps.sort()
	var big := gaps.filter(func(g): return g > 250).size()
	print("PROBE updates=%d p50=%d p99=%d max=%d frozen>250ms=%d" % [
		gaps.size(), gaps[gaps.size() / 2], gaps[int(gaps.size() * 0.99)], gaps[-1], big])
	get_tree().quit()
