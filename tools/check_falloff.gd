extends SceneTree
## #147: damage falloff per gun. Every gun in data/weapons/ has a real falloff (end > start, 0 < min <= 1),
## damage never rises with distance, and the sniper headshot kills up close but not across the map.
## Prints a body / headshot damage table and a time-to-kill table (#rifle/SMG balance). Headless:
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
	_ttk_table(dir)
	var sn := load(dir + "sniper.tres") as WeaponDef
	_ok(sn.damage_at_distance(sn.falloff_start_m) * sn.headshot_multiplier >= 100.0, "sniper headshot one-shots up to %.0f m" % sn.falloff_start_m)
	_ok(sn.damage_at_distance(100.0) * sn.headshot_multiplier < 100.0, "sniper headshot at 100 m is no longer a one-shot")
	print("FALLOFF CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)


## Seconds from the first hit to the kill on a 100 HP player at `dist`, every shot landing
## (body, or head with the gun's headshot multiplier). Pellet guns count all pellets per shot.
static func ttk(d: WeaponDef, dist: float, head := false) -> float:
	var per := d.damage_at_distance(dist) * d.pellet_count * (d.headshot_multiplier if head else 1.0)
	return float(ceili(100.0 / maxf(per, 0.001)) - 1) / d.fire_rate


## Prints body/head TTK at 5/15/30/50 m for every gun and checks the rifle/SMG roles:
## the SMG kills faster up close (8 m), the rifle at mid range (40 m).
func _ttk_table(dir: String) -> void:
	print("TTK s      " + "  ".join([5, 15, 30, 50].map(func(m): return "%9dm" % m)) + "   (body / head)")
	for f in DirAccess.get_files_at(dir):
		var d := load(dir + f) as WeaponDef if f.ends_with(".tres") else null
		if d:
			print("%-10s %s" % [d.id, " ".join([5.0, 15.0, 30.0, 50.0].map(func(m): return "%.2f/%.2f" % [ttk(d, m), ttk(d, m, true)]))])
	var rifle := load(dir + "rifle.tres") as WeaponDef
	var smg := load(dir + "smg.tres") as WeaponDef
	_ok(ttk(smg, 8.0) < ttk(rifle, 8.0), "SMG beats the rifle at 8 m (%.2f vs %.2f s)" % [ttk(smg, 8.0), ttk(rifle, 8.0)])
	_ok(ttk(rifle, 40.0) < ttk(smg, 40.0), "rifle beats the SMG at 40 m (%.2f vs %.2f s)" % [ttk(rifle, 40.0), ttk(smg, 40.0)])
	_ok(ttk(smg, 40.0) < ttk(rifle, 40.0) * 2.0, "but not by an extreme margin (SMG under 2x the rifle at 40 m)")
