extends Node
## Style.detect for the gun-specific tricks (MOW, SLUG SNIPE).
## Runs as a scene, not with `-s`: Style -> Tricks -> LosHands reaches the Game autoload, and a `-s`
## run has no autoloads at all, so the whole chain fails to compile ("Identifier not found: Game").
##   godot --headless --path . res://tools/check_style_guns.tscn   → "STYLE GUNS CHECK OK"
func _ready() -> void:
	var f := 0
	var a := Style.detect({"weapon": &"lmg", "mag_kills": 3})
	var b := Style.detect({"weapon": &"lmg", "mag_kills": 2})
	var c := Style.detect({"weapon": &"slug", "dist": 26.0})
	var d := Style.detect({"weapon": &"slug", "dist": 12.0})
	if not a.has(Style.MOW) or b.has(Style.MOW):
		f += 1
	if not c.has(Style.SLUG_SNIPE) or d.has(Style.SLUG_SNIPE):
		f += 1
	print("STYLE GUNS CHECK ", "OK" if f == 0 else "FAILED (%d)" % f, "  ", Style.label(a), " / ", Style.label(c))
	get_tree().quit(1 if f > 0 else 0)
