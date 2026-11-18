extends Node
## #145: the Shank class. Backstab is 100, front and side are 50, the lunge is a short sprint
## step, and the preset is a knife plus a pistol. Headless:
##   godot --headless --path . res://tools/check_shank.tscn
##
## A scene, not -s: Melee and PlayerClasses name the Game autoload, which a -s run does not
## register. Class migration uses a throwaway file and never touches user://classes.cfg.

const TMP := "user://check_shank_classes.cfg"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print(("  PASS " if c else "  FAIL ") + msg)
	if not c:
		fails += 1


func _ready() -> void:
	_angles()
	_numbers()
	_class_and_lists()
	_migration()
	await _lunge_gate()
	_cleanup()
	print("SHANK CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _angles() -> void:
	# Victim looks down -Z. Behind them is +Z, so forward · to_attacker is -1.
	var fwd := Vector3(0, 0, -1)
	_ok(Melee.shank_damage_for(fwd, Vector3(0, 0, 1)) == Melee.BACK_DAMAGE, "straight behind is 100")
	_ok(Melee.shank_damage_for(fwd, Vector3(0, 5, 1)) == Melee.BACK_DAMAGE, "height does not change a backstab")
	_ok(Melee.shank_damage_for(fwd, Vector3(0, 0, -1)) == Melee.FRONT_DAMAGE, "straight ahead is 50")
	_ok(Melee.shank_damage_for(fwd, Vector3(1, 0, 0)) == Melee.FRONT_DAMAGE, "a side is 50")
	# cos = -0.33 is just outside the rear wedge (threshold -0.34).
	var outside := Vector3(sqrt(1.0 - 0.33 * 0.33), 0, 0.33)
	_ok(absf(fwd.normalized().dot(outside.normalized()) - (-0.33)) < 0.001, "outside sample sits at dot -0.33")
	_ok(Melee.shank_damage_for(fwd, outside) == Melee.FRONT_DAMAGE, "just outside the rear wedge is 50")
	var inside := Vector3(sqrt(0.75), 0, 0.5)
	_ok(Melee.shank_damage_for(fwd, inside) == Melee.BACK_DAMAGE, "clearly inside the rear wedge is 100")
	var on_edge := Vector3(sqrt(1.0 - 0.34 * 0.34), 0, 0.34)
	_ok(Melee.behind(fwd, on_edge), "the threshold itself is a backstab")
	_ok(Melee.shank_damage_for(fwd, Vector3.ZERO) == Melee.FRONT_DAMAGE, "an overlapping pawn is not a free backstab")


func _numbers() -> void:
	var shank := load("res://data/weapons/shank.tres") as WeaponDef
	_ok(shank != null and shank.melee and shank.id == &"shank", "shank.tres is a melee weapon")
	_ok(shank.damage == Melee.FRONT_DAMAGE and shank.headshot_multiplier == 1.0, "the resource damage is the front hit, no headshot")
	_ok(is_equal_approx(shank.move_speed_mult, 1.23), "shank move speed is x1.23")
	_ok(absf(Player.SPRINT_SPEED * shank.move_speed_mult - 14.0) < 0.05, "sprint with the shank is about 14 m/s (%.2f)" % (Player.SPRINT_SPEED * shank.move_speed_mult))
	_ok(shank.mag_size == 0 and shank.reload_style == &"mag", "no magazine, and the reload style still round-trips")
	_ok(is_equal_approx(Melee.SHANK_RANGE, 2.2) and is_equal_approx(shank.range_m, 2.2), "reach is 2.2 m")
	_ok(is_equal_approx(Melee.LUNGE_M, 2.5) and is_equal_approx(Melee.LUNGE_TIME, 0.16), "lunge is 2.5 m over 0.16 s")
	var lunge_speed := Melee.LUNGE_M / Melee.LUNGE_TIME
	_ok(lunge_speed < 18.0 * 1.4, "lunge speed %.1f m/s stays under the position-claim cap" % lunge_speed)
	_ok(Melee.SHANK_CONE_DEG < Melee.CONE_DEG and Melee.SHANK_CONE_DEG <= 28.0, "the shank cone is tighter than the bash")
	_ok(is_equal_approx(Melee.DAMAGE, 50.0) and is_equal_approx(Melee.CONE_DEG, 40.0) and is_equal_approx(Melee.COOLDOWN, 0.8), "the bash is still 50 / 40 deg / 0.8 s")
	_ok(Melee.SHANK_SLACK < Melee.SERVER_SLACK, "shank server slack is tighter than the bash")
	_ok(Melee.BACK_DOT <= -0.34 and Melee.BACK_DOT > -0.5, "the rear wedge stays about 110 deg off the nose")
	var knife_node := Node3D.new()
	var shank_node := Node3D.new()
	var knife_fit := WeaponModel.fit_model(knife_node, &"knife", Vector3.ZERO)
	var shank_fit := WeaponModel.fit_model(shank_node, &"shank", Vector3.ZERO)
	_ok(knife_fit.root.is_equal_approx(shank_fit.root), "the shank viewmodel uses the throwing-knife fit")
	knife_node.free()
	shank_node.free()


func _class_and_lists() -> void:
	_ok(PlayerClasses.PRIMARIES.has(&"shank"), "shank is a primary")
	var preset: Dictionary = {}
	for c in PlayerClasses.DEFAULTS:
		if str(c.name) == "Shank":
			preset = PlayerClasses.sanitize_class(c)
	_ok(not preset.is_empty(), "defaults include a Shank class")
	_ok(str(preset.get("primary", "")) == "shank" and str(preset.get("secondary", "")) == "pistol", "Shank is shank + pistol")
	var g: Dictionary = preset.get("grenades", {})
	_ok(int(g.get("frag", -1)) == 1 and int(g.get("knife", -1)) == 0, "Shank carries 1 frag and no throwing knives")
	var parsed := PlayerClasses.parse_loadout(PlayerClasses.to_loadout(preset))
	_ok(not parsed.is_empty() and str(parsed.primary) == "shank", "the server accepts a shank loadout")
	_ok(GunGame.DEMOTE_WEAPONS.has(&"shank") and not GunGame.LADDER.has(&"shank"), "gun game demotes a shank and it is not on the ladder")
	_ok(Style.MOVE_WEAPONS.has(&"shank"), "slide and dive tags still count with the shank")
	_ok(not Weapon.LOADOUT.is_empty() and Weapon.LOADOUT[Weapon.LOADOUT.size() - 1].id == &"shank", "shank is appended to the armory")
	_ok(Game.WEAPON_DEFS.has(&"shank"), "the server knows the shank")
	_ok(KillFeed.ICONS.has(&"shank"), "the kill feed has a shank icon")


func _migration() -> void:
	_write_save(1, _classes(4))
	var grown: Dictionary = PlayerClasses.load_file(TMP)
	_ok(bool(grown.migrated) and grown.classes.size() == 5, "an older save with a free slot gains Shank")
	_ok(str(grown.classes[4].primary) == "shank", "the added class is the shank")
	_write_save(1, _classes(PlayerClasses.MAX_CLASSES))
	var full: Dictionary = PlayerClasses.load_file(TMP)
	_ok(bool(full.migrated) and full.classes.size() == PlayerClasses.MAX_CLASSES, "a full older save is marked migrated and does not grow")
	var still_full := true
	for c in full.classes:
		if str(c.primary) == "shank":
			still_full = false
	_ok(still_full, "a full save does not gain a shank by dropping another class")
	_write_save(PlayerClasses.FILE_VERSION, _classes(2))
	var current: Dictionary = PlayerClasses.load_file(TMP)
	_ok(not bool(current.migrated) and current.classes.size() == 2, "a version-2 save is left alone")
	_cleanup()
	var fresh: Dictionary = PlayerClasses.load_file(TMP)
	_ok(not bool(fresh.migrated) and fresh.classes.size() == PlayerClasses.DEFAULTS.size(), "a missing file is the defaults, not a migration")


## The lunge only ever speeds a pawn up, and only on the ground. It sets the horizontal velocity, so
## a stab at surf, grapple or carry speed used to brake the run to 15.6 m/s and bend it to the look
## direction, and in the air it was a free air-dash.
func _lunge_gate() -> void:
	var base := Vector3(0, 300, 0)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40, 1, 40)
	cs.shape = shape
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = base + Vector3(0, -0.5, 0)
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = -1
	p.is_bot = true
	p.set_physics_process(false)
	add_child(p)
	for i in 3:
		await get_tree().physics_frame
	var look := Vector3.FORWARD
	var cases := [
		["sprinting on the ground lunges the full step", base, Player.SPRINT_SPEED, true],
		["walking does not lunge", base, Player.WALK_SPEED * 0.6, false],
		["at surf speed (18 m/s) the stab does not brake you", base, 18.0, false],
		["in the air the stab is not an air-dash", base + Vector3(0, 4, 0), Player.SPRINT_SPEED, false],
	]
	for c in cases:
		p.global_position = c[1]
		p.velocity = look * float(c[2])
		p.is_sprinting = false
		var d: float = Game.melee.lunge_distance(p, look)
		_ok((d > Melee.LUNGE_M - 0.01) == bool(c[3]), "%s (%.2f m)" % [c[0], d])
	p.queue_free()
	floor_body.queue_free()


func _classes(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append({"name": "Class %d" % (i + 1), "primary": "rifle", "secondary": "pistol", "grenades": {"frag": 1}})
	return out


func _write_save(version: int, classes: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", version)
	cfg.set_value("meta", "count", classes.size())
	cfg.set_value("meta", "last", 0)
	for i in classes.size():
		var c: Dictionary = classes[i]
		var sec := "class_%d" % i
		cfg.set_value(sec, "name", c.name)
		cfg.set_value(sec, "primary", c.primary)
		cfg.set_value(sec, "secondary", c.secondary)
		cfg.set_value(sec, "grenades", c.grenades)
	cfg.save(TMP)


func _cleanup() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
