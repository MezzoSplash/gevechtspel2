extends SceneTree
## Guards the "one source per gun" rule. Every per-gun feel number lives in data/weapons/*.tres and
## is read through WeaponDef. This check fails if a gun-id branch creeps back into the scripts, if a
## gun is missing a value, or if the spread ladder drifts apart between client, server and the cap.
##
## Headless:  godot --headless --path . -s res://tools/check_weapon_defs.gd
##
## Deliberately dependency-free: it loads the WeaponDef resources and reads the scripts as text.
## Reaching for Player or the Game autoload from a -s check is flaky (a -s run has no scene tree, so
## the autoloads are not always registered and a depended script fails to compile), and reading the
## text is the stronger guard anyway: it also catches a constant that is never wired up.

## Role order for the fight distance: the shotgun closes in, the LMG holds a lane. A new gun has to
## be slotted in here on purpose, which is the point.
const FIGHT_ORDER := [&"shotgun", &"smg", &"pistol", &"revolver", &"rifle", &"slug", &"sniper", &"lmg"]
## Smells that mean a script is branching on a gun id again. A single feature test such as
## `def.id == &"sniper"` for the scope is fine; a match or a chain of comparisons is not.
const FORBIDDEN := ["match _gun_id", "match def.id", "elif def.id ==", "SMG_WOBBLE_SCALE", "SMG_AIM_TRACK"]
const SCANNED := ["res://scripts/weapon.gd", "res://scripts/bot_brain.gd"]

var fails := 0


func _ok(c: bool, msg: String) -> void:
	print(("  PASS " if c else "  FAIL ") + msg)
	if not c:
		fails += 1


func _text(pad: String) -> String:
	var f := FileAccess.open(pad, FileAccess.READ)
	if f == null:
		_ok(false, "cannot read %s" % pad)
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## `const NAME := 1.23` out of a script text. -1.0 when it is not there.
func _const_num(src: String, naam: String) -> float:
	var re := RegEx.new()
	re.compile("const\\s+" + naam + "\\s*:=\\s*([0-9.]+)")
	var m := re.search(src)
	return m.get_string(1).to_float() if m != null else -1.0


func _initialize() -> void:
	# quit() from here, not from _run(): the file handles and resources of a function still on the
	# stack count as leaked at exit.
	quit(1 if _run() > 0 else 0)


func _run() -> int:
	var dir := "res://data/weapons/"
	var guns: Dictionary = {}
	print("gun        spread  fight  burst      pause          kick   flash  punch  aim")
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"):
			continue
		var d := load(dir + f) as WeaponDef
		if d == null:
			continue
		guns[d.id] = d
		print("%-10s %5.2f  %5.1f  %2d-%-2d  %.2f-%.2f  %.3f  %.3f  %.2f  %.2fx/%.2fx" % [
			d.id, d.bot_spread_mult, d.bot_fight_range, d.bot_burst_min, d.bot_burst_max,
			d.bot_burst_pause_min, d.bot_burst_pause_max, d.view_kick_z, d.flash_time,
			d.crosshair_punch, d.bot_aim_wobble_scale, d.bot_aim_track_scale])
		_ok(d.bot_spread_mult > 0.0, "%s bot spread multiplier is set" % d.id)
		_ok(d.bot_fight_range > 0.0, "%s bot fight range is set" % d.id)
		_ok(d.bot_burst_min >= 1 and d.bot_burst_max >= d.bot_burst_min, "%s burst range is sane" % d.id)
		_ok(d.bot_burst_pause_min > 0.0 and d.bot_burst_pause_max >= d.bot_burst_pause_min, "%s burst pause is sane" % d.id)
		_ok(d.view_kick_z > 0.0 and d.flash_time > 0.0 and d.flash_energy > 0.0, "%s kick and flash are set" % d.id)
		_ok(d.crosshair_punch > 0.0, "%s crosshair punch is set" % d.id)
		_ok(d.tracer_color.v > 0.05, "%s tracer colour is not black" % d.id)
		_ok(d.bot_aim_wobble_scale > 0.0 and d.bot_aim_track_scale > 0.0, "%s bot aim scales are set" % d.id)

	_ok(guns.size() >= 8, "all guns are loaded (%d)" % guns.size())
	var prev := -1.0
	var order_ok := true
	for id in FIGHT_ORDER:
		if not guns.has(id):
			order_ok = false
			continue
		var r: float = guns[id].bot_fight_range
		if prev >= 0.0 and r < prev:
			order_ok = false
		prev = r
	_ok(order_ok, "fight distances follow the role order (shotgun closest, LMG furthest)")

	for pad in SCANNED:
		var tekst := _text(pad)
		for smell in FORBIDDEN:
			_ok(not tekst.contains(smell), "%s has no `%s`" % [pad.get_file(), smell])

	# The spread ladder: one source in player.gd, and the cap in game.gd points at it.
	var pl := _text("res://scripts/player.gd")
	var walk := _const_num(pl, "SPREAD_WALK_K")
	var sprint := _const_num(pl, "SPREAD_SPRINT")
	var slide := _const_num(pl, "SPREAD_SLIDE")
	_ok(walk > 1.0 and sprint > walk and slide > sprint,
		"the spread ladder climbs: walk %.2f < sprint %.1f < slide %.1f" % [walk, sprint, slide])
	_ok(_text("res://shared/game.gd").contains("const SPREAD_MAX := Player.SPREAD_SLIDE"),
		"Game.SPREAD_MAX points at Player.SPREAD_SLIDE instead of carrying its own copy")

	print("WEAPON DEFS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	return fails
