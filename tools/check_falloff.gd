extends SceneTree
## #147: damage falloff per gun. Every gun in data/weapons/ has a real falloff (end > start, 0 < min <= 1),
## damage never rises with distance, and the sniper headshot kills up close but not across the map.
## Prints a body / headshot damage table. Headless:
##   godot --headless --path . -s res://tools/check_falloff.gd

const DISTS := [5.0, 20.0, 40.0, 60.0, 100.0]
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print(("  PASS " if c else "  FAIL ") + msg)
	if not c:
		fails += 1


func _initialize() -> void:
	var dir := "res://data/weapons/"
	print("gun        " + "  ".join(DISTS.map(func(d): return "%5dm" % d)) + "   (body / headshot per shot)")
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var d := load(dir + f) as WeaponDef
		if d == null:
			continue
		var row := PackedStringArray()
		for dist in DISTS:
			row.append("%3d/%-3d" % [roundi(d.damage_at_distance(dist) * d.pellet_count), roundi(d.damage_at_distance(dist) * d.pellet_count * d.headshot_multiplier)])
		print("%-10s %s" % [d.id, " ".join(row)])
		_ok(d.falloff_end_m > d.falloff_start_m and d.falloff_min_mult > 0.0 and d.falloff_min_mult <= 1.0,
			"%s has a falloff (%.0f-%.0f m, x%.2f)" % [d.id, d.falloff_start_m, d.falloff_end_m, d.falloff_min_mult])
		var prev := INF
		var mono := true
		for m in range(0, 250, 5):
			var v := d.damage_at_distance(float(m))
			mono = mono and v <= prev + 0.0001
			prev = v
		_ok(mono, "%s damage never rises with distance" % d.id)
	var sn := load(dir + "sniper.tres") as WeaponDef
	_ok(sn.damage_at_distance(sn.falloff_start_m) * sn.headshot_multiplier >= 100.0, "sniper headshot one-shots up to %.0f m" % sn.falloff_start_m)
	_ok(sn.damage_at_distance(100.0) * sn.headshot_multiplier < 100.0, "sniper headshot at 100 m is no longer a one-shot")
	print("FALLOFF CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
