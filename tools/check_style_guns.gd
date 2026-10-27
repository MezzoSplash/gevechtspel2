extends SceneTree
## godot --headless --script res://tools/check_style_guns.gd
func _init() -> void:
	var f := 0
	var a := Style.detect({"weapon": &"lmg", "mag_kills": 3})
	var b := Style.detect({"weapon": &"lmg", "mag_kills": 2})
	var c := Style.detect({"weapon": &"slug", "dist": 26.0})
	var d := Style.detect({"weapon": &"slug", "dist": 12.0})
	if not a.has(Style.MOW) or b.has(Style.MOW): f += 1
	if not c.has(Style.SLUG_SNIPE) or d.has(Style.SLUG_SNIPE): f += 1
	print("STYLE GUNS CHECK ", "OK" if f == 0 else "FAILED (%d)" % f, "  ", Style.label(a), " / ", Style.label(c))
	quit()
