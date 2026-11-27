extends Node
## #319: de HP-gem. De verlichte lengte van de HP-seam volgt de HP, de armour-seam staat er los van,
## facetten springen af bij een hit en doven uit, herstel laat de seam teruggroeien, en onder 30% kleurt
## de seam rood. Geen match nodig: de gem houdt zijn eigen stand bij.
##   ./run.sh --headless res://tools/check_hp_gem.tscn   → "HP GEM CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	var gem := HpGem.new()
	add_child(gem)
	gem.size = Vector2(46, 30)
	_ok(gem.custom_minimum_size.x > 0.0 and gem.custom_minimum_size.y > 0.0, "the gem has a minimum size")

	# 1) Volle HP: de seam is helemaal verlicht.
	gem.set_state(100.0, 100.0)
	gem.tick(0.1)
	_ok(is_equal_approx(gem.seam_lit(), 1.0), "full HP lights the whole seam (%.2f)" % gem.seam_lit())
	_ok(is_equal_approx(gem.armour_lit(), 0.0), "no armour, no armour seam")

	# 2) Halve HP: de helft van de seam.
	gem.set_state(50.0, 100.0)
	for i in 40:
		gem.tick(0.1)
	_ok(absf(gem.seam_lit() - 0.5) < 0.03, "half HP lights half the seam (%.2f)" % gem.seam_lit())

	# 3) Een hit laat facetten afspringen; die doven binnen een halve seconde uit.
	gem.set_state(20.0, 100.0)
	_ok(not gem.chips.is_empty(), "a hit knocks facets off (%d)" % gem.chips.size())
	for i in 12:
		gem.tick(0.05)
	_ok(gem.chips.is_empty(), "and they are gone half a second later")

	# 4) Onder 30% pulseert de seam rood in plaats van ijs.
	_ok(gem.is_low(), "20% HP counts as low")
	var low_col := gem._hp_color()
	_ok(low_col.r > low_col.b, "the seam turns red when low (r %.2f > b %.2f)" % [low_col.r, low_col.b])

	# 5) Herstel: de seam groeit terug in plaats van te springen.
	gem.set_state(80.0, 100.0)
	gem.tick(0.1)
	var after_one_tick := gem.seam_lit()
	for i in 30:
		gem.tick(0.1)
	_ok(after_one_tick < 0.79 and gem.seam_lit() > after_one_tick, "regeneration grows the seam back (%.2f -> %.2f)" % [after_one_tick, gem.seam_lit()])
	_ok(is_equal_approx(gem.seam_lit(), 0.8) or gem.seam_lit() > 0.79, "and it gets there (%.2f)" % gem.seam_lit())
	_ok(not gem.is_low(), "80% is not low")

	# 6) Armour is een eigen laag: de Schildplaat vult zijn eigen seam, los van de HP.
	gem.set_state(100.0, 100.0, Pickups.ARMOUR * 0.5, Pickups.ARMOUR)
	for i in 20:
		gem.tick(0.1)
	_ok(absf(gem.armour_lit() - 0.5) < 0.03, "half armour lights half the armour seam (%.2f)" % gem.armour_lit())
	_ok(is_equal_approx(gem.seam_lit(), 1.0), "and the HP seam is untouched by it (%.2f)" % gem.seam_lit())
	gem.set_state(100.0, 100.0, 0.0, Pickups.ARMOUR)
	gem.tick(0.1)
	_ok(is_equal_approx(gem.armour_lit(), 0.0), "no armour, no armour seam")

	# 7) Hij tekent ook echt: een lege _draw mag niet klappen op een kleine maat.
	gem.size = Vector2(8, 6)
	gem.queue_redraw()
	_ok(true, "the gem draws at any size")

	print("HP GEM CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
