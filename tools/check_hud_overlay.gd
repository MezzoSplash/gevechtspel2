extends Node
## HudOverlay and HudVitals (scripts/hud/, split out of hud.gd in #315): the overlay draws under every
## other HUD node; a kill or headshot marker holds longer than a body hit; fire punch decays; damage
## wedges point the right way, stack up to DMG_MAX and fade; a drop in HP flashes the vignette and a
## heal does not; the HP fill goes ice -> amber -> red; the pickup toast fades; a respawn clears it all.
##   godot --headless res://tools/check_hud_overlay.tscn
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
	var o := hud.overlay
	_ok(o.get_index() == 0 and o.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the overlay is the first child and click-through")

	var view := Transform3D.IDENTITY # looking down -Z
	_ok(is_zero_approx(HudOverlay.dir_angle(view, Vector3(0, 0, -5))), "ahead reads 0")
	_ok(is_equal_approx(HudOverlay.dir_angle(view, Vector3(5, 0, 0)), PI * 0.5), "right reads +PI/2")
	_ok(is_equal_approx(absf(HudOverlay.dir_angle(view, Vector3(0, 0, 5))), PI), "behind reads PI")

	hud._on_hit(false, false)
	var body := o.hit_timer
	hud._on_hit(true, false)
	_ok(o.hit_timer > body and o.kill_hit, "a kill marker holds longer than a body hit")
	o.tick(1.0)
	_ok(o.hit_timer == 0.0, "the marker runs out")
	hud.punch_crosshair(1.0)
	o.tick(0.05)
	_ok(o.fire_punch > 0.0 and o.fire_punch < 1.0, "fire punch decays")

	for i in HudOverlay.DMG_MAX + 3:
		hud.add_damage_dir(Vector3(i, 0, 0))
	_ok(o.dmg_dirs.size() == HudOverlay.DMG_MAX, "damage wedges are capped at DMG_MAX")
	o.tick(HudOverlay.DMG_LIFE + 0.01)
	_ok(o.dmg_dirs.is_empty(), "and fade out after DMG_LIFE")

	hud._on_health(100.0, 100.0)
	o.hurt_flash = 0.0
	hud._on_health(60.0, 100.0)
	_ok(o.hurt_flash > 0.0, "losing HP flashes the vignette")
	o.hurt_flash = 0.0
	hud._on_health(90.0, 100.0)
	_ok(o.hurt_flash == 0.0, "a heal does not")
	_ok(HudVitals.fill_for(0.9) == Hud.HP_OK and HudVitals.fill_for(0.45) == Hud.HP_MID and HudVitals.fill_for(0.1) == Hud.HP_LOW,
		"HP fill: ice, amber, red")
	_ok(hud.hp_label.text == "90" and is_equal_approx(hud.hp_fill.anchor_right, 0.9), "the bar and number follow HP")

	hud.flash_pickup("+45 HP", Color.GREEN)
	_ok(hud.pickup_toast != null and hud.pickup_toast.text == "+45 HP", "a pickup shows its toast")
	hud.vitals.tick(HudVitals.TOAST_TIME + 0.1)
	_ok(is_zero_approx(hud.pickup_toast.modulate.a), "and the toast fades")

	hud.set_sniper_hip(true)
	_ok(o.sniper_hip, "sniper hip: no crosshair")
	hud.add_damage_dir(Vector3.ONE)
	o.hurt()
	hud._on_respawned()
	_ok(o.dmg_dirs.is_empty() and o.hurt_flash == 0.0, "a respawn clears wedges and vignette")

	hud.queue_free()
	print("HUD OVERLAY CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
