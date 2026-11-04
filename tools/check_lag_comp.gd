extends Node
## #105: a shot at where a moving target WAS hits with lag-compensation rewind and misses without.
##   godot --headless res://tools/check_lag_comp.tscn
## Shooter and target float high above the map (nothing else in the ray), the target slides along x
## while LagComp records it each physics tick, then one ray aims at its position 150 ms ago.
## Also proves rewind_ms_for clamps a far-past stamp to MAX_REWIND_MS + INTERP_MS.
const BACK_MS := 150
var target: Player
const SPEED := 10.0 # m/s: 1.5 m in BACK_MS, well clear of the capsule


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	Game.last_bots = 1
	Game.bot_count = 1
	var menu = main.get_node("CanvasLayer/Menu")
	menu.set_match_choice(&"quay", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	target = null
	for i in 100:
		await get_tree().create_timer(0.1).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		for n in get_tree().get_nodes_in_group("player"):
			if n != me and not (n as Player).is_dead:
				target = n
		if me and target and me.weapon and me.weapon.def and not Game.play_locked():
			break
	if me == null or target == null:
		_done(false, "no players")
		return
	for p: Player in [me, target]:
		p.set_physics_process(false)
	me.global_position = Vector3(0, 300, 0)
	var start := Vector3(0, 300, -10)
	var t0 := LagComp.now_ms()
	while true:
		await get_tree().physics_frame
		var dt := (LagComp.now_ms() - t0) / 1000.0
		target.global_position = start + Vector3(SPEED * dt, 0, 0)
		LagComp.record(Game)
		if dt > 0.4:
			break
	var past: Variant = LagComp.transform_at(Game, target, BACK_MS)
	var aim_at := (past as Transform3D).origin + Vector3(0, 1.0, 0)
	var origin := me.global_position + Vector3(0, 1.0, 0)
	var dir := (aim_at - origin).normalized()
	var def := me.weapon.def
	# Peer 2 has no ping sample here: an ancient stamp stops at the absolute cap.
	if LagComp.rewind_ms_for(Game, 2, 1) != LagComp.MAX_REWIND_MS + LagComp.INTERP_MS:
		_done(false, "clamp")
		return
	Game.pings[2] = 80
	var rtt_cap := LagComp.rewind_ms_for(Game, 2, 1)
	Game.pings[2] = 900
	var abs_cap := LagComp.rewind_ms_for(Game, 2, 1)
	Game.pings.erase(2)
	if rtt_cap != 80 + LagComp.INTERP_MS or abs_cap != LagComp.MAX_REWIND_MS + LagComp.INTERP_MS:
		_done(false, "rtt cap %d / %d" % [rtt_cap, abs_cap])
		return
	var miss := _shoot(me, origin, dir, def, 0)
	var hit := _shoot(me, origin, dir, def, BACK_MS)
	print("without rewind hit=%s, with rewind hit=%s" % [miss, hit])
	_done(not miss and hit, "")


func _shoot(me: Player, origin: Vector3, dir: Vector3, def: WeaponDef, back: int) -> bool:
	Game._shot_rewind = LagComp.offsets_for(Game, me, back)
	var best := Combat.resolve_shot_rays(Game, me, origin, dir, def, 0.0, 1)
	Game._shot_rewind = []
	return bool(best.get("hit", false))


func _done(ok: bool, why: String) -> void:
	print("LAG COMP CHECK ", "OK" if ok else "FAILED %s" % why)
	get_tree().quit()
