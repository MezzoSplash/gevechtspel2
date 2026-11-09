extends Node3D
## #144 pickups: three pads on Townhouses, server-authoritative, with the spec's effects.
##   godot --headless res://tools/check_pickups.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().create_timer(1.0).timeout
	var menu = main.get_node("CanvasLayer/Menu")
	Game.last_bots = 2
	Game.bot_count = 2
	menu.set_match_choice(&"townhouses", Game.MODE_FFA)
	menu.play_local_pressed.emit()
	var me: Player = null
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		me = Game.player_for_peer(multiplayer.get_unique_id())
		if me != null:
			break
	if me == null:
		print("  FAIL no local pawn")
		print("PICKUPS CHECK: FAIL (1 failures)")
		get_tree().quit(1)
		return

	# 1) State built from the map data, one node per pad.
	var defs: Array = Maps.pickups(&"townhouses")
	_ok(defs.size() == 3, "Townhouses defines %d pads" % defs.size())
	_ok(Pickups.state.size() == defs.size(), "the authority holds %d pickups" % Pickups.state.size())
	var kinds := []
	for p in Pickups.state:
		kinds.append(str(p["type"]))
	_ok("knives" in kinds and "shield" in kinds and "heal" in kinds, "the three spec types are there (%s)" % ", ".join(kinds))
	_ok(Pickups.nodes.size() == defs.size(), "every machine builds a pickup node (%d)" % Pickups.nodes.size())

	# 2) Pads stand on free floor: a floor under the pad and room for a player capsule above it.
	var space := get_world_3d().direct_space_state
	for p in Pickups.state:
		var at: Vector3 = p["pos"]
		var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at - Vector3.UP * 0.6)
		var hit := space.intersect_ray(down)
		var on_floor := not hit.is_empty() and absf((hit.position as Vector3).y - at.y) < 0.3
		var body := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.5
		body.shape = sphere
		body.transform = Transform3D(Basis(), at + Vector3.UP * 1.0)
		var crowded := space.intersect_shape(body, 1)
		_ok(on_floor and crowded.is_empty(), "pad %s at %s stands in the open" % [p["type"], at])

	# 3) Effects, straight from the spec.
	Game.set_hp(me, 40.0)
	me.apply_heal_visual(40.0)
	_ok(Pickups.apply(Game, me, &"heal"), "a heal core applies at 40 HP")
	_ok(is_equal_approx(Game.hp_of(me), 85.0), "Herstelkern gives +45 (%.0f)" % Game.hp_of(me))
	Game.set_hp(me, Player.MAX_HP)
	me.apply_heal_visual(Player.MAX_HP)
	_ok(not Pickups.apply(Game, me, &"heal"), "at full HP the core does nothing (and stays)")
	me.set_armour(0.0)
	_ok(Pickups.apply(Game, me, &"shield"), "a shield plate applies with no armour")
	_ok(is_equal_approx(me.armour, Pickups.ARMOUR), "Schildplaat gives 40 (%.0f)" % me.armour)
	_ok(not Pickups.apply(Game, me, &"shield"), "a second plate does nothing")
	me.knives = 0
	_ok(Pickups.apply(Game, me, &"knives"), "extra knives apply at zero")
	_ok(me.knives == 2, "Extra Messen gives 2 (%.0f)" % me.knives)
	_ok(Pickups.apply(Game, me, &"knives"), "and 2 more on top")
	_ok(not Pickups.apply(Game, me, &"knives"), "but never past the cap of 3 (%d)" % me.knives)

	# 4) Armour eats damage before HP. Spawn protection would swallow the hit, so clear it first.
	me._spawn_protect = 0.0
	me.set_armour(40.0)
	var old_hp := Game.hp_of(me)
	me.apply_hit(me.global_position + Vector3(0, 1.0, 0), Vector3.FORWARD, 30.0, false, 0, &"rifle")
	_ok(is_equal_approx(Game.hp_of(me), old_hp), "a 30 damage hit does not touch HP while the plate holds (%.0f)" % Game.hp_of(me))
	_ok(is_equal_approx(me.armour, 10.0), "the plate absorbed it (%.0f left)" % me.armour)
	me.apply_hit(me.global_position + Vector3(0, 1.0, 0), Vector3.FORWARD, 30.0, false, 0, &"rifle")
	_ok(Game.hp_of(me) < old_hp, "the overflow goes to HP once the plate is gone")

	# 5) Touch: standing on a pad takes it, and the pad respawns.
	for p in Pickups.state:
		p["ready"] = true
		p["timer"] = 0.0
	me.set_armour(0.0)
	var shield: Dictionary = {}
	for p in Pickups.state:
		if str(p["type"]) == "shield":
			shield = p
	me.global_position = (shield["pos"] as Vector3)
	await get_tree().physics_frame
	Pickups.tick(Game, 0.05)
	_ok(not bool(shield["ready"]), "standing on the plate takes it")
	_ok(is_equal_approx(me.armour, Pickups.ARMOUR), "and it applied")
	var node := Pickups.node_for(int(shield["id"]))
	_ok(node != null and node._taken, "the node switches to its taken look")
	shield["timer"] = 0.01
	Pickups.tick(Game, 0.05)
	_ok(bool(shield["ready"]), "and it comes back when the timer runs out")

	# 6) Review #246: a remote pawn gets the vitals, and a late joiner gets the pad state.
	me.apply_vitals(70.0, 25.0)
	_ok(is_equal_approx(Game.hp_of(me), 70.0) and is_equal_approx(me.armour, 25.0),
		"vitals sync sets HP and armour on the pawn")
	Pickups.sync_to_peer(Game, multiplayer.get_unique_id())
	_ok(true, "sync_to_peer runs without touching the authority state")

	# 7) Review #246: the popup says what happened, not the type name.
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	me.play_pickup_flash(&"knives")
	_ok(hud.pickup_toast != null and hud.pickup_toast.text == "MESSEN +%d" % Pickups.KNIVES,
		"the knife popup reads '%s'" % (hud.pickup_toast.text if hud.pickup_toast else "none"))
	me.play_pickup_flash(&"shield")
	_ok(hud.pickup_toast.text == "SCHILD", "the armour popup reads 'SCHILD'")
	me.play_pickup_flash(&"heal")
	_ok(hud.pickup_toast.text == "+%d HP" % roundi(Pickups.HEAL), "the heal popup reads '%s'" % hud.pickup_toast.text)

	print("PICKUPS CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
