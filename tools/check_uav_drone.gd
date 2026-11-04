extends Node
## Physical UAV headless: the circle fits every map (radius and height from the spawns), the path is
## smooth and banked, the UAV streak launches a drone, friendly fire does nothing, enemy damage
## shoots it down, which ends the team's radar early and frees the drone after its fall.
## Optional: -- shot=/path.png (needs a display) frames the drone.
##   godot --headless --path . res://tools/check_uav_drone.tscn   → "UAV DRONE CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	for id in Maps.ORDER:
		var p := UavDrone.fit_path(id)
		var top := -INF
		for s in Maps.team_spawns(id, 0) + Maps.team_spawns(id, 1):
			top = maxf(top, (s as Vector3).y)
		_ok(float(p.radius) >= UavDrone.RADIUS_MIN and float(p.radius) <= UavDrone.RADIUS_MAX
			and float(p.height) > top + 20.0, "%s: r %.0f m, h %.0f m" % [id, p.radius, p.height])
	var a := UavDrone.path_transform(Vector3.ZERO, 30.0, 40.0, 0.0, 0.0)
	var b := UavDrone.path_transform(Vector3.ZERO, 30.0, 40.0, 0.0, 0.1)
	_ok(absf(Vector2(a.origin.x, a.origin.z).length() - 30.0) < 0.01 and is_equal_approx(a.origin.y, 40.0), "on the circle")
	_ok(a.origin.distance_to(b.origin) < 1.5 and (-a.basis.z).dot((b.origin - a.origin).normalized()) > 0.95, "smooth, nose along the path")
	_ok(a.basis.x.y < -0.2 and a.basis.x.dot(-a.origin) > 0.0, "banked into the turn (inner wing down)")

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_TDM)
	for bx in menu._bot_boxes:
		bx.value = 1
	menu.play_local_pressed.emit()
	for i in 200:
		await get_tree().create_timer(0.1).timeout
		if Game._round_active and Game.player_for_peer(1):
			break
	var me := Game.player_for_peer(1)
	Streaks.grant_radar(Game, 1)
	await get_tree().physics_frame
	var drones := get_tree().get_nodes_in_group("uav_drone")
	_ok(drones.size() == 1 and Game.radar_left > 20.0, "UAV streak launches one drone + radar")
	var d := drones[0] as UavDrone
	_ok(d.collision_layer & Game.SHOT_MASK != 0, "authority drone is shootable (SHOT_MASK)")
	d.damage(500.0, 77, me.team_id, &"rifle")
	_ok(d.hp == UavDrone.MAX_HP, "friendly fire does nothing")
	var foe_team := 1 - me.team_id
	d.damage(40.0, 78, foe_team, &"rifle")
	_ok(d.hp < UavDrone.MAX_HP and Game.radar_left > 0.0, "enemy hit damages it")
	d.damage(500.0, 78, foe_team, &"rifle")
	_ok(Game.radar_left == 0.0, "shot down: radar ends early")
	_ok(d.collision_layer == 0 and d.remaining() == 0.0, "shot down: falls, no more hits")
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shot = arg.substr(5)
	if shot != "":
		Streaks.grant_radar(Game, 1)
		await get_tree().create_timer(0.5).timeout
		var d2 := get_tree().get_nodes_in_group("uav_drone").back() as UavDrone
		for cl in main.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		var cam := Camera3D.new()
		cam.fov = 35
		add_child(cam)
		cam.current = true
		for i in 3:
			cam.look_at_from_position(d2.global_position + d2.global_basis.z * 7.0 + Vector3(0, 1.2, 0), d2.global_position, Vector3.UP)
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	await get_tree().create_timer(UavDrone.FALL_TIME + 0.4).timeout
	_ok(not is_instance_valid(d), "falls and is freed")
	print("UAV DRONE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)
