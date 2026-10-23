extends Node
## Headless: LMG + slug shotgun numbers, class validation, then a bot match that must produce
## kills with both.   godot --headless res://tools/check_new_guns.tscn

var _kills := {}

func _ready() -> void:
	var fails := 0
	print("gun       body@5m  body@25m  body@40m  head@5m  ttk@5m(s)")
	for id in [&"rifle", &"smg", &"shotgun", &"slug", &"lmg", &"revolver"]:
		var d: WeaponDef = Game.weapon_def(id)
		var ttk := float(d.shots_to_kill(5.0) - 1) / d.fire_rate
		print("%-9s %7d  %8d  %8d  %7d  %9.2f" % [id, d.shots_to_kill(5.0), d.shots_to_kill(25.0),
			d.shots_to_kill(40.0), ceili(100.0 / (d.damage_at_distance(5.0) * d.headshot_multiplier * d.pellet_count)), ttk])
	var slug: WeaponDef = Game.weapon_def(&"slug")
	var sg: WeaponDef = Game.weapon_def(&"shotgun")
	fails += _check("slug one-shot head up close", slug.damage * slug.headshot_multiplier >= 100.0)
	fails += _check("slug 2 body close", slug.shots_to_kill(5.0) == 2)
	fails += _check("slug outranges pellets at 25 m", slug.damage_at_distance(25.0) > sg.damage_at_distance(25.0) * sg.pellet_count * 0.5)
	var lmg: WeaponDef = Game.weapon_def(&"lmg")
	fails += _check("lmg 100 rounds, slow ADS, slow move", lmg.mag_size == 100 and lmg.ads_time > 0.2 and lmg.move_speed_mult < 1.0)
	for id in [&"lmg", &"slug"]:
		var lo := PlayerClasses.parse_loadout({"primary": String(id), "secondary": "pistol", "grenades": {"frag": 1}})
		fails += _check("class accepts %s" % id, not lo.is_empty() and StringName(lo.primary) == id)
		fails += _check("in armory %s" % id, Weapon.LOADOUT.any(func(w: WeaponDef) -> bool: return w.id == id))
		fails += _check("feed icon %s" % id, Hud._FEED_ICONS.has(id))
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	Game.bot_count = 16
	Game.kill_feed.connect(func(_k: String, _v: String, w: StringName, _a = null, _b = null, _c = null) -> void:
		_kills[w] = int(_kills.get(w, 0)) + 1
	)
	main.get_node("CanvasLayer/Menu").set_match_choice(&"townhouses", Game.MODE_TDM)
	main.get_node("CanvasLayer/Menu").play_local_pressed.emit()
	var held := {}
	for t in 18:
		await get_tree().create_timer(5.0).timeout
		for n in get_tree().get_nodes_in_group("player"):
			var p := n as Player
			if p and p.is_bot and p.weapon and p.weapon.def:
				held[p.weapon.def.id] = true
	print("bot guns seen: ", held.keys())
	print("kills by weapon: ", _kills)
	fails += _check("bots hold the LMG", held.has(&"lmg"))
	fails += _check("bots hold the slug", held.has(&"slug"))
	fails += _check("an LMG or slug kill happened", _kills.has(&"lmg") or _kills.has(&"slug"))
	print("NEW GUNS CHECK: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	get_tree().quit(fails)


func _check(what: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + what)
	return 0 if ok else 1
