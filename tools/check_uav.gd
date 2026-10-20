extends Node3D
## Headless checks for the UAV streak and the minimap. Run:
##   godot --headless --path . res://tools/check_uav.tscn
## With a display, `-- shot=/path.png` also saves a frame with the minimap on Townhouses.
## Prints "UAV CHECK OK" or "FAILED".

var fails := 0
var shot := ""


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL ", msg)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			shot = a.substr(5)
	_run.call_deferred()


func _pawn(n: String, team: int, pos: Vector3, yaw := 0.0) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.is_bot = true
	p.name = n
	p.team_id = team
	add_child(p)
	p.global_position = pos
	p.rotation.y = yaw
	return p


func _run() -> void:
	_ok(Game.STREAK_AT == 3, "UAV at 3 kills")
	_ok(Game.RADAR_TIME >= 20.0 and Game.RADAR_TIME <= 30.0, "UAV lasts 20 to 30 s (%.0f)" % Game.RADAR_TIME)
	_ok(Game.NET_VERSION == "0.3.7", "NET_VERSION bumped")
	var map: Node3D = null
	for id in Maps.ORDER:
		var m := (load(str(Maps.info(id).scene)) as PackedScene).instantiate() as Node3D
		add_child(m)
		var floors: Array[PackedVector2Array] = []
		var walls: Array[PackedVector2Array] = []
		Minimap.collect_outline(m, floors, walls)
		print("outline %s: %d floors, %d walls" % [id, floors.size(), walls.size()])
		_ok(floors.size() > 0 and walls.size() > 10, "%s has an outline" % id)
		if id == &"townhouses":
			map = m
		else:
			m.queue_free()
	await get_tree().physics_frame
	Game.mode = 0 if Game.mode == Game.MODE_FFA else Game.mode
	var me := _pawn(str(multiplayer.get_unique_id()), 0, Vector3(0, 0.1, 20))
	me.peer_id = multiplayer.get_unique_id()
	var mate := _pawn("bot2", 0, Vector3(-6, 0.1, 14), 0.6)
	var foe := _pawn("bot3", 1, Vector3(8, 0.1, 6))
	var foe2 := _pawn("bot4", 1, Vector3(-10, 0.1, 2))
	await get_tree().physics_frame
	var now := Time.get_ticks_msec()
	Game.clear_radar()
	_ok(Minimap.mark_for(mate, me, false, now) == Minimap.MARK_FRIEND, "teammate always shows")
	_ok(Minimap.mark_for(foe, me, false, now) == Minimap.MARK_NONE, "enemy hidden without UAV")
	# Enemy team's UAV: we only hear it, no markers for us.
	Game._apply_radar(1, "bot3", Game.RADAR_TIME, -3)
	_ok(Game.radar_left == 0.0, "enemy UAV gives us nothing")
	Game._apply_radar(0, "bot2", Game.RADAR_TIME, -2)
	_ok(is_equal_approx(Game.radar_left, Game.RADAR_TIME), "team UAV runs for us (%.1f)" % Game.radar_left)
	_ok(Minimap.mark_for(foe, me, Game.radar_left > 0.0, now) == Minimap.MARK_ENEMY, "enemy shows on UAV")
	foe.is_dead = true
	_ok(Minimap.mark_for(foe, me, true, now) == Minimap.MARK_NONE, "dead enemy hidden")
	foe.is_dead = false
	Game.clear_radar()
	_ok(Game.radar_left == 0.0, "clear_radar ends the UAV")
	if foe2.weapon:
		foe2.weapon.play_fire_sfx()
	now = Time.get_ticks_msec()
	_ok(Minimap.mark_for(foe2, me, false, now) == Minimap.MARK_ENEMY, "enemy shot shows a dot")
	_ok(Minimap.mark_for(foe2, me, false, now + Minimap.SHOT_SHOW_MS + 10) == Minimap.MARK_NONE, "shot dot fades")
	Game.mode = Game.MODE_FFA
	_ok(Minimap.mark_for(mate, me, false, now) == Minimap.MARK_NONE, "FFA: no teammates")
	Game.mode = 0
	# Fade: lost contact leaves a ghost at the last spot that fades over FADE_MS.
	var mm := Minimap.new()
	add_child(mm)
	mm.set_process(false)
	mm.track_contacts({1: Vector2(3, 4), 2: Vector2(5, 6)}, 1000)
	mm.track_contacts({2: Vector2(5, 7)}, 1100) # 1 lost (UAV over / died)
	_ok(mm._ghosts.has(1) and mm._ghosts[1].pos == Vector2(3, 4), "lost enemy leaves a ghost at the last spot")
	_ok(not mm._ghosts.has(2), "still visible enemy is no ghost")
	_ok(is_equal_approx(Minimap.ghost_alpha(1100, 1600), 0.5), "half faded after half the time")
	mm.track_contacts({1: Vector2(9, 9)}, 1500) # 1 back, 2 lost
	_ok(not mm._ghosts.has(1) and mm._ghosts.has(2), "seen again drops the ghost")
	mm.track_contacts({1: Vector2(9, 9)}, 1500 + Minimap.FADE_MS)
	_ok(not mm._ghosts.has(2), "ghost gone after FADE_MS")
	_ok(Minimap.ghost_alpha(0, Minimap.FADE_MS) == 0.0, "alpha 0 at the end")
	mm.queue_free()
	var ahead := Minimap.to_local_map(Vector2(-10, 20), Vector2(0, 20), PI * 0.5)
	_ok(ahead.y < -9.9 and absf(ahead.x) < 0.01, "facing -X: a pawn 10 m to -X is straight up (%s)" % ahead)
	var right := Minimap.to_local_map(Vector2(5, 0), Vector2.ZERO, 0.0)
	_ok(right.x > 4.9, "facing -Z: +X is to the right")
	if shot != "":
		await _shot(me)
	print("UAV CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails else 0)


func _shot(me: Player) -> void:
	for n in get_tree().get_nodes_in_group("player"):
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	me.rotation.y = 0.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = me.global_position + Vector3(0, 1.6, 0)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as Control
	layer.add_child(hud)
	var mm := hud.get_node("Minimap") as Minimap
	mm.player = me
	mm._map_ref = weakref(null)
	# Not under Main here, so feed the outline straight from the map.
	mm.set_process(false)
	for c in get_children():
		if c.scene_file_path.ends_with("townhouses.tscn"):
			Minimap.collect_outline(c, mm._floors, mm._walls)
	Game._apply_radar(0, "bot2", Game.RADAR_TIME, -2)
	mm._sweep = 0.12
	for i in 10:
		await get_tree().process_frame
		mm.queue_redraw()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot)
	img.get_region(Rect2i(0, 0, 420, 300)).save_png(shot.get_basename() + "_crop.png")
	print("shot -> ", shot)
