extends Node
## WeaponBar and StreakColumn (scripts/hud/, split out of hud.gd in #315): the held slot shows its
## ammo and is pale, names are upper-cased and the index clamped, the grenade pill shows knives only
## when carried; streak selection wraps, a new charge plays its announcer line once, a held charge
## reads READY, the pips count the kills, and reset clears it all. Driven through the real HUD.
##   godot --headless res://tools/check_hud_bars.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var hud: Hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	hud.set_process(false)
	await get_tree().process_frame
	var w := hud.weapons
	hud.set_weapon_slots(PackedStringArray(["smg ", "Revolver"]))
	_ok(w.names == PackedStringArray(["SMG", "REVOLVER"]), "names are trimmed and upper-cased")
	_ok(hud._slots[1].visible and not hud._slots[2].visible, "one slot per carried gun")
	hud.set_weapon_index(9)
	_ok(w.index == 1, "the index is clamped to the guns carried")
	hud.set_ammo(12, 30)
	var held := hud._slots[1].get_node("Ammo") as Label
	var other := hud._slots[0].get_node("Ammo") as Label
	_ok(held.text == "12 / 30" and other.text == "", "only the held slot shows its ammo")
	var skin := hud._slots[1].get_node("Skin").get_theme_stylebox("panel") as CrystalStyle
	_ok(skin.pale and skin.seam_side == CrystalStyle.Side.BOTTOM, "the held slot is pale shell with a lit seam")
	hud.set_grenades(2)
	_ok(hud.grenade_label.text == "G  FRAG 2", "frags only")
	hud.set_grenades(1, 3)
	_ok(hud.grenade_label.text.ends_with("F  KNIFE 3"), "knives when carried")

	var s := hud.streaks
	s.sel = 0
	s.select(-1)
	_ok(s.sel == 2, "up from the first slot wraps to LOS")
	s.select(1)
	_ok(s.sel == 0, "down from LOS wraps to the UAV")
	hud.set_streak(3, Game.CHARGE_RADAR, Game.CHARGE_RADAR)
	_ok(s.announcer.stream != null and s.announcer.stream.resource_path.ends_with("radar_standby.wav"), "a new radar charge: 'radar on standby'")
	var played: AudioStream = s.announcer.stream
	s.announcer.stream = null
	hud.set_streak(4, Game.CHARGE_RADAR, Game.CHARGE_RADAR)
	_ok(s.announcer.stream == null and played != null, "a charge already held plays nothing")
	_ok((hud._streak_slots[0].get_node("Cost") as Label).text == "READY · ENTER", "a held charge reads READY")
	_ok((hud._streak_slots[1].get_node("Cost") as Label).text == "%d KILLS" % Game.RCXD_AT, "an empty slot shows its cost")
	var lit := 0
	for pip in s.pips.get_children():
		if ((pip as Panel).get_theme_stylebox("panel") as CrystalStyle).fill == HudLayout.ACCENT:
			lit += 1
	_ok(lit == 4, "the pips count the kills (%d lit)" % lit)
	hud.set_rc_drive(true, 40.0, 6.0)
	_ok(s.rc_hint != null and s.rc_hint.visible and s.rc_hint.text.begins_with("LMB DETONATE"), "the RC-XD line shows while driving")
	hud.reset_session()
	_ok(s.n == 0 and s.charges == 0 and not s.rc_hint.visible, "leaving the match clears the column")

	hud.queue_free()
	print("HUD BARS CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
