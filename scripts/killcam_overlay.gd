class_name KillcamOverlay
extends RefCounted
## The replay's 2D layer (#317 stap 2, uit scripts/killcam.gd): the two bars, the title, the killer's
## crosshair and hit markers, and the VHS tape amount. Static on the Killcam node; the nodes (_overlay,
## _draw, _title) and the playback clock stay on Killcam and this is called with the node as `k`.
## The VHS paint itself is KillcamVhs; this file only places it.


static func build(k: Killcam, info: Dictionary) -> void:
	k._overlay = CanvasLayer.new()
	k._overlay.layer = 20
	k.add_child(k._overlay)
	var full := Control.new()
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k._overlay.add_child(full)
	k._draw = Control.new()
	k._draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	k._draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	k._draw.draw.connect(on_draw.bind(k._draw))
	full.add_child(k._draw)
	var top := bar(full, true)
	var title_text := "FINAL KILLCAM"
	if info.has("trick_id"):
		title_text = "BEST TRICKSHOT"
		if int(info.get("bank", 0)) > 0:
			title_text = "BEST COMBO  ·  %d STYLE" % int(info.bank)
		elif int(info.get("pts", 0)) > 0:
			title_text += "  ·  %d STYLE" % int(info.pts)
	var title := label(title_text, 34, Color(1, 1, 1))
	k._title = title
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	var bottom := bar(full, false)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	var kt := clampi(int(info.get("kt", 0)), 0, 1)
	var vt := clampi(int(info.get("vt", 1)), 0, 1)
	# FFA: gold when the final killer is also the round winner (top of the board).
	var k_col: Color = Player.team_color(kt)
	if Game.is_ffa() and int(info.get("k", 0)) == Game.top_player():
		k_col = Player.SELF_COLOR
	row.add_child(label(str(info.get("kn", "?")), 26, k_col))
	var icon := TextureRect.new()
	var wid := StringName(str(info.get("w", "rifle")))
	icon.texture = Hud._FEED_ICONS.get(wid, Hud._FEED_ICONS[&"rifle"])
	icon.custom_minimum_size = Vector2(84, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	row.add_child(label(str(info.get("vn", "?")), 26, Player.team_color(vt)))
	if bool(info.get("hs", false)):
		row.add_child(label("HEADSHOT", 20, Color(1.0, 0.86, 0.2)))
	var tags := str(info.get("tags", ""))
	if tags != "":
		row.add_child(label(tags, 20, Hud.TRICK_COLOR))


static func bar(parent: Control, top: bool) -> ColorRect:
	var b := ColorRect.new()
	b.color = Color(0, 0, 0, 0.82)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.anchor_right = 1.0
	if top:
		b.anchor_bottom = 0.0
		b.offset_bottom = Killcam.BAR_H
	else:
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		b.offset_top = -Killcam.BAR_H
	parent.add_child(b)
	return b


static func label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## #258/#317: the VHS overlay is `KillcamVhs.paint`; the tape amount comes from the playback clock.
static func draw_vhs(k: Killcam, canvas: Control) -> void:
	KillcamVhs.paint(canvas, k._tape_amount(k._pt), k._real_t, Killcam.BAR_H)


## #258: the payout climbs with the bank and lands on the kill, and the title shows >> while the replay
## is fast-forwarding.
static func update_title(k: Killcam) -> void:
	if k._title == null or k._clip.is_empty():
		return
	var info: Dictionary = k._clip.get("info", {})
	if not info.has("trick_id"):
		return
	var bank := int(info.get("bank", 0))
	if bank <= 0:
		return
	var text := "BEST COMBO  ·  %d STYLE" % Killcam.ticker_value(bank, k._pt, k._t_start, k._t_kill)
	if k._tape_amount(k._pt) > 0.5:
		text += "   >>"
	k._title.text = text


## The killer's crosshair and hit markers, like the HUD draws them, plus the VHS fast-forward overlay.
static func on_draw(k: Killcam, canvas: Control) -> void:
	draw_vhs(k, canvas)
	var c := canvas.size * 0.5
	var col := Color(0.95, 0.95, 0.95, 0.85)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		canvas.draw_line(c + d * 5.0, c + d * 13.0, col, 2.0, true)
	if k._hit_t <= 0.0:
		return
	var a := clampf(k._hit_t / 0.12, 0.0, 1.0)
	var hit_col := Color(1, 1, 1, a)
	if k._hit_kill:
		hit_col = Color(1.0, 0.22, 0.18, a)
	elif k._hit_head:
		hit_col = Color(1.0, 0.86, 0.2, a)
	var s := 13.0 if k._hit_kill or k._hit_head else 9.0
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		canvas.draw_line(c + d * s, c + d * s * 0.35, hit_col, 2.4, true)
