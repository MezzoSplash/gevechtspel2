class_name ScoreboardView
extends RefCounted
## Tab scoreboard (part of the HUD): builds the board from Game.get_scores(). Static builders only; the
## HUD owns the container, when it opens, and the winner / style-king cards that live in it.

const BG := Color(0.05, 0.06, 0.08, 0.82)
const ROW_A := Color(1, 1, 1, 0.035)
const ROW_B := Color(1, 1, 1, 0.0)
const ROW_SELF := Color(1.0, 0.84, 0.42, 0.16)
const MUTED := Color(0.62, 0.66, 0.72)
const COLS := [["#", 26], ["NAME", 200], ["K", 48], ["D", 48], ["K/D", 58], ["STYLE", 64], ["PING", 56]]


## The whole board: header, then the FFA field or both teams side by side, on a dark backdrop.
static func build(scores: Array, ffa: bool, local_peer_id: int) -> PanelContainer:
	var backdrop := PanelContainer.new()
	var bsb := box(BG, 12)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.content_margin_top = 14
	bsb.content_margin_bottom = 16
	backdrop.add_theme_stylebox_override("panel", bsb)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	backdrop.add_child(body)
	body.add_child(header(ffa))
	if ffa:
		body.add_child(panel("PLAYERS  ·  %d" % scores.size(), "", Color(0.9, 0.9, 0.92), scores, true, local_peer_id))
	else:
		var teams := HBoxContainer.new()
		teams.add_theme_constant_override("separation", 14)
		for team_id in [Game.TEAM_A, Game.TEAM_B]:
			var rows := scores.filter(func(e: Dictionary) -> bool: return int(e.get("team", 0)) == team_id)
			teams.add_child(panel(
				Game.TEAM_NAMES[team_id], str(Game.team_score(team_id)), Player.team_color(team_id), rows, false, local_peer_id
			))
		body.add_child(teams)
	return backdrop


static func box(col: Color, radius: int = 0, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.border_width_top = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func label(text: String, size: int, col: Color, width: int = 0, right: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if width > 0:
		l.clip_text = true
		l.custom_minimum_size = Vector2(width, 0)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


## Column row (header or player). `values` follows COLS; the name column stays left-aligned.
static func row(values: Array, size: int, col: Color, name_col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i in COLS.size():
		row.add_child(label(str(values[i]), size, name_col if i == 1 else col, COLS[i][1], i > 1))
	return row


## One team (or the FFA field): coloured header with name + score, column headers, striped rows.
static func panel(title: String, score_text: String, team_col: Color, rows: Array, ffa: bool, local_peer_id: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(Color(0.09, 0.1, 0.13, 0.9), 8, team_col))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var t := label(title, 20, team_col)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if score_text != "":
		head.add_child(label(score_text, 26, Color(0.95, 0.95, 0.97), 0, true))
		head.add_child(label("/ %d" % Game.score_limit(), 15, MUTED, 0, true))
	v.add_child(head)
	if score_text != "":
		# Team progress toward the kill limit, in the team colour.
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		bar.max_value = maxf(float(Game.score_limit()), 1.0)
		bar.value = float(score_text.to_int())
		var bg_sb := StyleBoxFlat.new()
		bg_sb.bg_color = Color(1, 1, 1, 0.08)
		bg_sb.set_corner_radius_all(2)
		var fg_sb := StyleBoxFlat.new()
		fg_sb.bg_color = team_col
		fg_sb.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg_sb)
		bar.add_theme_stylebox_override("fill", fg_sb)
		v.add_child(bar)
	var cols := []
	for c in COLS:
		cols.append(c[0])
	var hdr := PanelContainer.new()
	hdr.add_theme_stylebox_override("panel", box(Color(1, 1, 1, 0.0)))
	hdr.add_child(row(cols, 13, MUTED, MUTED))
	v.add_child(hdr)
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(1, 1, 1, 0.12))
	v.add_child(sep)
	var i := 0
	for entry in rows:
		var deaths := int(entry.get("deaths", 0))
		var style_pts := int(entry.get("style", 0))
		var ping_ms := int(entry.get("ping", -1))
		var me: bool = entry.peer_id == local_peer_id
		var bot: bool = int(entry.peer_id) < 0
		var vals := [
			str(i + 1), str(entry.name), entry.kills, deaths, "%.2f" % (float(entry.kills) / float(maxi(deaths, 1))),
			str(style_pts) if style_pts > 0 else "—", "BOT" if bot else ("—" if ping_ms < 0 else str(ping_ms)),
		]
		var bg := ROW_SELF if me else (ROW_A if i % 2 == 0 else ROW_B)
		var rp := PanelContainer.new()
		var rsb := box(bg, 6)
		rsb.content_margin_top = 5
		rsb.content_margin_bottom = 5
		if me:
			rsb.border_color = Hud.HUD_ACCENT
			rsb.border_width_left = 3
		rp.add_theme_stylebox_override("panel", rsb)
		var row := row(vals, 17, Color(0.88, 0.9, 0.93), Color(1.0, 0.9, 0.55) if me else Color(0.95, 0.95, 0.97))
		var rank := row.get_child(0) as Label
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rank.add_theme_font_size_override("font_size", 14)
		rank.add_theme_color_override("font_color", Hud.HUD_ACCENT if (i == 0 and ffa) else MUTED)
		(row.get_child(2) as Label).add_theme_color_override("font_color", Color(1, 1, 1))
		(row.get_child(3) as Label).add_theme_color_override("font_color", MUTED)
		var ping_l := row.get_child(6) as Label
		ping_l.add_theme_font_size_override("font_size", 14)
		if bot or ping_ms < 0:
			ping_l.add_theme_color_override("font_color", Color(MUTED, 0.7))
		else:
			ping_l.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55) if ping_ms < 60 else (Color(0.95, 0.8, 0.35) if ping_ms < 120 else Color(0.95, 0.45, 0.4)))
		if style_pts > 0:
			(row.get_child(5) as Label).add_theme_color_override("font_color", Hud.TRICK_COLOR)
		rp.add_child(row)
		v.add_child(rp)
		i += 1
	if rows.is_empty():
		v.add_child(label("No players", 15, MUTED))
	return panel


## Mode · map on the left, goal and clock on the right, gold rule under it (#66).
static func header(ffa: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var h := HBoxContainer.new()
	var left := label("%s  ·  %s" % [Game.mode_name().to_upper(), Maps.display_name(Game.map_id).to_upper()], 16, Color(0.95, 0.95, 0.97))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var t := int(ceil(Game.get_round_time_left()))
	var goal := "first to %d %s" % [Game.score_limit(), Game.score_word()] if ffa else "%d %s wins" % [Game.score_limit(), Game.score_word()]
	h.add_child(label("%s  ·  %d:%02d" % [goal, t / 60, t % 60], 15, MUTED, 0, true))
	v.add_child(h)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(Hud.HUD_ACCENT, 0.55)
	v.add_child(rule)
	return v
