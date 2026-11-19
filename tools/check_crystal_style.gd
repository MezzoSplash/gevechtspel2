extends Node
## CrystalStyle (shared/crystal_style.gd), the cut-crystal shard every UI piece is drawn with
## (docs/ui-crystal/HANDOFF.md). Outline, facet fan, seam ends, and that a script StyleBox really
## gets its _draw called through StyleBox.draw(); and CrystalTheme.install() on the menu theme. Headless:
##   godot --headless --path . res://tools/check_crystal_style.tscn

var fails := 0


class Probe extends CrystalStyle:
	var drawn := 0

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		drawn += 1
		super(to_canvas_item, rect)


func _ok(c: bool, msg: String) -> void:
	print(("  PASS " if c else "  FAIL ") + msg)
	if not c:
		fails += 1


func _ready() -> void:
	_outline()
	_facets()
	_seams()
	await _draw_and_redraw()
	_theme()
	await _hud()
	print("CRYSTAL STYLE CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _inside(pts: PackedVector2Array, r: Rect2) -> bool:
	var grown := r.grow(0.001)
	for p in pts:
		if not grown.has_point(p) and not is_equal_approx(p.x, r.end.x) and not is_equal_approx(p.y, r.end.y):
			return false
	return true


func _distinct(pts: PackedVector2Array) -> bool:
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if pts[i].distance_to(pts[j]) < 0.0001:
				return false
	return true


func _outline() -> void:
	var r := Rect2(10, 20, 300, 60)
	var pts := CrystalStyle.outline(r, Vector4(14, 6, 18, 8))
	_ok(pts.size() == 8, "outline has 8 points")
	_ok(_inside(pts, r), "outline stays inside the rect")
	_ok(pts[0] == Vector2(24, 20) and pts[4] == Vector2(292, 80), "cuts follow [tl,tr,br,bl] (%s, %s)" % [pts[0], pts[4]])
	var zero := CrystalStyle.outline(r, Vector4.ZERO)
	_ok(_distinct(zero) and _inside(zero, r), "cuts = 0 still gives 8 distinct points")
	var big := CrystalStyle.outline(r, Vector4(500, 500, 500, 500))
	_ok(_distinct(big) and _inside(big, r), "huge cuts are clamped (no crossing)")
	for s in [Vector2(3, 3), Vector2(0.5, 0.5), Vector2(400, 2)]:
		var tiny := Rect2(Vector2.ZERO, s)
		var tp := CrystalStyle.outline(tiny, Vector4(14, 6, 18, 8))
		_ok(_distinct(tp) and _inside(tp, tiny), "tiny rect %s: distinct points inside" % s)


func _facets() -> void:
	var r := Rect2(0, 0, 240, 70)
	var pts := CrystalStyle.outline(r, Vector4(14, 6, 18, 8))
	var a := CrystalStyle.facets(pts, r, 3)
	var b := CrystalStyle.facets(pts, r, 3)
	var c := CrystalStyle.facets(pts, r, 4)
	_ok(a.size() == 8, "one facet per edge")
	_ok(str(a) == str(b), "same variant, same facets")
	_ok(str(a) != str(c), "different variant, different facets")
	var centre: Vector2 = a[0].tri[2]
	_ok(Rect2(r.size * 0.25, r.size * 0.5).grow(0.001).has_point(centre), "fan centre in the middle half")
	var ok_alpha := true
	for f in a:
		ok_alpha = ok_alpha and f.alpha > 0.0 and f.alpha <= 0.25
	_ok(ok_alpha, "facet alphas in the mockup range")


func _seams() -> void:
	var r := Rect2(0, 0, 200, 50)
	var pts := CrystalStyle.outline(r, Vector4(10, 10, 10, 10))
	var l := CrystalStyle.seam_ends(pts, CrystalStyle.Side.LEFT, 0.0)
	var bo := CrystalStyle.seam_ends(pts, CrystalStyle.Side.BOTTOM, 0.0)
	var t := CrystalStyle.seam_ends(pts, CrystalStyle.Side.TOP, 0.0)
	var ri := CrystalStyle.seam_ends(pts, CrystalStyle.Side.RIGHT, 0.0)
	_ok(l == [Vector2(0, 10), Vector2(0, 40)], "left seam runs top to bottom (%s)" % [l])
	_ok(bo == [Vector2(10, 50), Vector2(190, 50)], "bottom seam runs left to right (%s)" % [bo])
	_ok(t == [Vector2(10, 0), Vector2(190, 0)], "top seam runs left to right (%s)" % [t])
	_ok(ri == [Vector2(200, 10), Vector2(200, 40)], "right seam runs top to bottom (%s)" % [ri])
	_ok(CrystalStyle.seam_ends(pts, CrystalStyle.Side.NONE).is_empty(), "no seam, no ends")
	var inset := CrystalStyle.seam_ends(pts, CrystalStyle.Side.BOTTOM, 2.0)
	_ok(inset[0].y == 48.0, "inset moves the seam into the shard")


func _draw_and_redraw() -> void:
	var s := Probe.new()
	_ok(s is StyleBox, "CrystalStyle.new() is a StyleBox")
	var ci := RenderingServer.canvas_item_create()
	s.seam_side = CrystalStyle.Side.BOTTOM
	s.seam_lit = 0.4
	s.draw(ci, Rect2(0, 0, 200, 50))
	s.draw(ci, Rect2(0, 0, 0.5, 0.5))
	_ok(s.drawn == 2, "StyleBox.draw() reaches the script _draw (%d)" % s.drawn)
	RenderingServer.free_rid(ci)
	# The real path: a Panel with the style as its "panel" draws through it, and setting a field
	# (emit_changed) queues a redraw without anyone calling queue_redraw.
	var p := Panel.new()
	p.size = Vector2(200, 50)
	p.add_theme_stylebox_override("panel", s)
	add_child(p)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := s.drawn
	_ok(before > 2, "a Panel draws with it (%d draws)" % before)
	s.seam_lit = 0.9
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(s.drawn > before, "changing a field redraws the Panel")
	var changed := [0]
	s.changed.connect(func() -> void: changed[0] += 1)
	s.cuts = Vector4(4, 4, 4, 4)
	s.pale = true
	_ok(changed[0] == 2, "every field emits changed")
	_ok(s.get_minimum_size() == Vector2.ZERO, "no content margins unless asked (theme sets them)")
	p.queue_free()


func _theme() -> void:
	var t := CrystalTheme.install()
	_ok(t != null, "CrystalTheme.install() returns the theme")
	_ok(CrystalTheme.install() == t, "install() is idempotent (same instance)")
	_ok(load(CrystalTheme.PATH) == t, "load() of the theme path returns the patched instance")
	for slot in [["normal", "Button"], ["hover", "MenuButtonBig"], ["normal", "PrimaryButton"],
			["pressed", "ChoiceChip"], ["panel", "MenuPanel"], ["panel", "PopupMenu"], ["focus", "LineEdit"]]:
		_ok(t.get_stylebox(slot[0], slot[1]) is CrystalStyle, "%s/%s is a CrystalStyle" % [slot[1], slot[0]])
	var raw := ResourceLoader.load(CrystalTheme.PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as Theme
	var same := true
	for slot in [["normal", "OptionButton"], ["hover", "MenuButtonBig"], ["panel", "MenuPanel"], ["normal", "ChoiceChip"]]:
		var a := raw.get_stylebox(slot[0], slot[1])
		var b := t.get_stylebox(slot[0], slot[1])
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			same = same and is_equal_approx(a.get_content_margin(side), b.get_content_margin(side))
	_ok(same, "content margins kept (OptionButton right %.0f)" % t.get_stylebox("normal", "OptionButton").get_content_margin(SIDE_RIGHT))
	var sel := t.get_stylebox("pressed", "ChoiceChip") as CrystalStyle
	_ok(sel.pale and sel.seam_side != CrystalStyle.Side.NONE, "selected chip is pale shell with a seam")
	_ok(t.get_color("font_hover_color", "MenuButtonBig").v < 0.3, "big menu row hover text is dark on the shell")
	var amber := Color(1.0, 0.72, 0.22)
	var left_amber := []
	for type in t.get_color_type_list():
		for n in t.get_color_list(type):
			var c := t.get_color(n, type)
			if Color(c, 1.0).is_equal_approx(amber):
				left_amber.append("%s/%s" % [type, n])
	_ok(left_amber.is_empty(), "no amber colours left %s" % [left_amber])
	var raw_tracking := (raw.get_font("font", "Button") as FontVariation).spacing_glyph
	_ok((t.get_font("font", "Button") as FontVariation).spacing_glyph == raw_tracking + 1, "button type tracked wider, once")


func _skin_of(rect: Control) -> CrystalStyle:
	var p := rect.get_node_or_null("Skin") as Panel
	return p.get_theme_stylebox("panel") as CrystalStyle if p else null


## The HUD's slots go through hud.gd _skin/_paint: crystal shards, the held weapon pale.
func _hud() -> void:
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	hud.set_process(false)
	hud.set_weapon_slots(PackedStringArray(["Rifle", "Pistol"]))
	hud.set_weapon_index(1)
	var held := _skin_of(hud._slots[1])
	var idle := _skin_of(hud._slots[0])
	_ok(held != null and idle != null, "weapon slots are skinned with CrystalStyle")
	if held and idle:
		_ok(held.pale and held.seam_side == CrystalStyle.Side.BOTTOM, "held weapon: pale shell + bottom seam")
		_ok(not idle.pale and idle.seam_side == CrystalStyle.Side.NONE, "idle weapon: smoke, no seam")
		_ok(held.variant != idle.variant, "slots get different facet fans")
	hud.streaks.sel = 0
	hud.set_streak(3, Game.CHARGE_RADAR, Game.CHARGE_RADAR)
	var uav := _skin_of(hud._streak_slots[0])
	var rc := _skin_of(hud._streak_slots[1])
	_ok(uav != null and uav.pale, "selected ready streak is the pale shell")
	_ok(rc != null and not rc.pale and rc.seam_side == CrystalStyle.Side.NONE, "empty streak stays smoke")
	hud._on_health(20.0, 100.0)
	var hp := _skin_of(hud.hp_fill)
	_ok(hp != null and hp.fill == hud.HP_LOW, "low HP fill is red")
	hud._on_health(100.0, 100.0)
	_ok(hp != null and hp.fill == hud.HP_OK, "full HP fill is ice")
	hud.queue_free()
