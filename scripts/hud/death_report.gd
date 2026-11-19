class_name DeathReport
extends PanelContainer
## #64 death report (part of the HUD): "KILLED BY X" with the weapon, their damage to you and yours to
## them, under RESPAWNING; it stays a few seconds into the next life and fades. A smoke shard with a
## red seam on top (#314). The HUD makes it on the first death and calls show_report.

const HOLD := 5.0 # s fully visible
const FADE := 0.6 # s fade-out after HOLD
const HALF_W := 215.0

var _tw: Tween


func _init() -> void:
	name = "DeathReport"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -HALF_W
	offset_right = HALF_W
	offset_top = 48.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Red is danger, and this is what killed you.
	var sb := CrystalUi.shard(Vector4(14, 6, 18, 8), 33, false, CrystalStyle.Side.TOP, CrystalUi.DANGER, 1.0, Vector2(20, 10))
	sb.content_margin_bottom = 12
	sb.fill = ScoreboardView.PANEL
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.name = "V"
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := CrystalUi.caption("", 17, ScoreboardView.TEXT)
	head.name = "Head"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var wl := CrystalUi.caption("", 12, CrystalUi.MUTE.lightened(0.2))
	wl.name = "Weapon"
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(wl)
	for row in ["Taken", "Dealt"]:
		var h := HBoxContainer.new()
		h.name = row
		var l := Label.new()
		l.name = "L"
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", CrystalUi.MUTE.lightened(0.15))
		h.add_child(l)
		var r := Label.new()
		r.name = "R"
		r.add_theme_font_size_override("font_size", 16)
		h.add_child(r)
		v.add_child(h)


## Fills the card and shows it; a second death restarts the hold.
func show_report(killer: String, taken: int, taken_hits: int, dealt: int, dealt_hits: int, killer_hp: int, weapon: String = "") -> void:
	var v := get_node("V")
	(v.get_node("Head") as Label).text = "KILLED BY %s" % " ".join(killer.strip_edges().to_upper().split(" ", false))
	var wlab := v.get_node("Weapon") as Label
	wlab.text = "with %s" % weapon.strip_edges().to_upper() if weapon.strip_edges() != "" else ""
	wlab.visible = wlab.text != ""
	(v.get_node("Taken/L") as Label).text = "Their damage to you"
	(v.get_node("Taken/R") as Label).text = "%d  ·  %d %s" % [taken, taken_hits, "hit" if taken_hits == 1 else "hits"]
	(v.get_node("Taken/R") as Label).add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
	(v.get_node("Dealt/L") as Label).text = "Your damage to them"
	var tail := "  ·  %d HP left" % killer_hp if killer_hp > 0 else ""
	(v.get_node("Dealt/R") as Label).text = "%d  ·  %d %s%s" % [dealt, dealt_hits, "hit" if dealt_hits == 1 else "hits", tail]
	(v.get_node("Dealt/R") as Label).add_theme_color_override("font_color", HudLayout.ACCENT if dealt > 0 else ScoreboardView.MUTED)
	visible = true
	modulate.a = 1.0
	if _tw and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_interval(HOLD)
	_tw.tween_property(self, "modulate:a", 0.0, FADE)
	_tw.tween_callback(func() -> void: visible = false)
