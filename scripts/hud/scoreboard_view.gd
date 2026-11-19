class_name ScoreboardView
extends RefCounted
## Tab scoreboard (part of the HUD): builds the board from Game.get_scores(). Static builders only; the
## HUD owns the container, when it opens, and the winner / style-king cards that live in it.
## Crystal look (docs/ui-crystal/HANDOFF.md): separate floating shards, no boxed panel. A team's seam
## is its colour and its lit length is the score toward the limit; your own row is pale shell.

const PANEL := Color(0.059, 0.078, 0.106, 0.84) # = CrystalTheme.SMOKE_PANEL: readable over the 3D scene
const ROW := Color(0.059, 0.078, 0.106, 0.35) # = the theme's SettingRow: a faint shard per row
const TEXT := Color(0.92, 0.94, 0.96)
const DARK := Color(0.07, 0.08, 0.10) # text on pale shell
const MUTED := CrystalUi.MUTE
const COLS := [["#", 26], ["NAME", 200], ["K", 48], ["D", 48], ["K/D", 58], ["STYLE", 64], ["PING", 56]]
const _PING_GOOD := Color(0.5, 0.85, 0.55)
const _PING_MID := Color(0.95, 0.8, 0.35)
const _PING_BAD := Color(0.95, 0.45, 0.4)


## The whole board: header shard, then the FFA field or both teams side by side.
static func build(scores: Array, ffa: bool, local_peer_id: int) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.name = "Board"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 10)
	body.add_child(header(ffa))
	if ffa:
		# The board arrives sorted on the mode's score, so the first row is the leader.
		var lead := float(scores[0].get(Game.score_word(), 0)) if not scores.is_empty() else 0.0
		body.add_child(panel("PLAYERS  ·  %d" % scores.size(), "", Color(CrystalStyle.ICE, 0.6), lead, scores, true, local_peer_id, 11))
	else:
		var teams := HBoxContainer.new()
		teams.mouse_filter = Control.MOUSE_FILTER_IGNORE
		teams.add_theme_constant_override("separation", 14)
		for team_id in [Game.TEAM_A, Game.TEAM_B]:
			var rows := scores.filter(func(e: Dictionary) -> bool: return int(e.get("team", 0)) == team_id)
			var score := Game.team_score(team_id)
			teams.add_child(panel(
				Game.TEAM_NAMES[team_id], str(score), Player.team_color(team_id), float(score), rows, false, local_peer_id, 12 + team_id
			))
		body.add_child(teams)
	return body


## Lit share of a seam for `score` toward the round's limit.
static func progress(score: float) -> float:
	return clampf(score / maxf(float(Game.score_limit()), 1.0), 0.0, 1.0)


## Scoreboard label: size, colour, optional fixed width and right alignment.
static func label(text: String, size: int, col: Color, width: int = 0, right: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var r := HBoxContainer.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_constant_override("separation", 10)
	for i in COLS.size():
		r.add_child(label(str(values[i]), size, name_col if i == 1 else col, COLS[i][1], i > 1))
	return r


## One team (or the FFA field): a shard whose top seam is the team colour, lit to `lit_score` of the
## limit; name + score, column heads, one faint shard per player.
static func panel(title: String, score_text: String, team_col: Color, lit_score: float, rows: Array,
		ffa: bool, local_peer_id: int, variant: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Team" if not ffa else "Field"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cuts := Vector4(16, 6, 20, 8) if variant % 2 == 0 else Vector4(6, 16, 8, 20)
	var sb := CrystalUi.shard(cuts, variant, false, CrystalStyle.Side.TOP, team_col, progress(lit_score), Vector2(16, 12))
	sb.fill = PANEL
	sb.facet_strength = 0.5
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := CrystalUi.caption(title, 18, team_col.lightened(0.1))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(t)
	if score_text != "":
		var num := label(score_text, 30, TEXT, 0, true)
		num.add_theme_font_override("font", CrystalUi.bold_font())
		head.add_child(num)
		var lim := CrystalUi.caption("/ %d" % Game.score_limit(), 12, MUTED)
		lim.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(lim)
	v.add_child(head)
	var heads := []
	for c in COLS:
		heads.append(c[0])
	var hdr := row(heads, 11, MUTED, MUTED)
	for l in hdr.get_children():
		(l as Label).add_theme_font_override("font", CrystalUi.caps_font())
	var hdr_pad := MarginContainer.new()
	hdr_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_pad.add_theme_constant_override("margin_left", 12)
	hdr_pad.add_theme_constant_override("margin_right", 12)
	hdr_pad.add_theme_constant_override("margin_top", 6)
	hdr_pad.add_child(hdr)
	v.add_child(hdr_pad)
	var i := 0
	for entry in rows:
		v.add_child(player_row(entry, i, ffa, entry.peer_id == local_peer_id))
		i += 1
	if rows.is_empty():
		var none := CrystalUi.caption("No players", 12, MUTED)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(none)
	return p


## One player: a faint smoke shard, or pale shell with an ice seam and dark text for your own row.
static func player_row(entry: Dictionary, i: int, ffa: bool, me: bool) -> PanelContainer:
	var deaths := int(entry.get("deaths", 0))
	var style_pts := int(entry.get("style", 0))
	var ping_ms := int(entry.get("ping", -1))
	var bot: bool = int(entry.peer_id) < 0
	var vals := [
		str(i + 1), str(entry.name), entry.kills, deaths, "%.2f" % (float(entry.kills) / float(maxi(deaths, 1))),
		str(style_pts) if style_pts > 0 else "—", "BOT" if bot else ("—" if ping_ms < 0 else str(ping_ms)),
	]
	var rp := PanelContainer.new()
	rp.name = "Me" if me else "Row"
	rp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cuts := Vector4(4 + (i * 3) % 7, 2 + (i * 5) % 5, 5 + (i * 2) % 6, 3)
	var sb := CrystalUi.shard(cuts, 20 + i, me, CrystalStyle.Side.LEFT if me else CrystalStyle.Side.NONE,
			HudLayout.ACCENT, 1.0, Vector2(12, 4))
	if not me:
		sb.fill = ROW
		sb.facet_strength = 0.35
		sb.edge_alpha = 0.07
	rp.add_theme_stylebox_override("panel", sb)
	var text := DARK if me else Color(0.88, 0.9, 0.93)
	var muted := Color(DARK, 0.6) if me else MUTED
	var r := row(vals, 17, text, DARK if me else Color(0.95, 0.95, 0.97))
	var rank := r.get_child(0) as Label
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rank.add_theme_font_size_override("font_size", 14)
	rank.add_theme_color_override("font_color", HudLayout.ACCENT if (i == 0 and ffa and not me) else muted)
	(r.get_child(2) as Label).add_theme_font_override("font", CrystalUi.bold_font())
	(r.get_child(2) as Label).add_theme_color_override("font_color", DARK if me else TEXT)
	(r.get_child(3) as Label).add_theme_color_override("font_color", muted)
	var ping_l := r.get_child(6) as Label
	ping_l.add_theme_font_size_override("font_size", 14)
	var ping_col := Color(muted, 0.7) if bot or ping_ms < 0 \
			else (_PING_GOOD if ping_ms < 60 else (_PING_MID if ping_ms < 120 else _PING_BAD))
	if me and not (bot or ping_ms < 0):
		ping_col = ping_col.darkened(0.45)
	ping_l.add_theme_color_override("font_color", ping_col)
	if style_pts > 0:
		# Gold stays for trick rewards (HANDOFF 2): style points are one.
		(r.get_child(5) as Label).add_theme_color_override("font_color", Hud.TRICK_COLOR.darkened(0.45) if me else Hud.TRICK_COLOR)
	rp.add_child(r)
	return rp


## Mode · map on the left, goal and clock on the right, on one slim shard (#66).
static func header(ffa: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Header"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := CrystalUi.shard(Vector4(10, 4, 14, 6), 10, false, CrystalStyle.Side.NONE, CrystalStyle.ICE, 1.0, Vector2(18, 8))
	sb.fill = PANEL
	sb.facet_strength = 0.6
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := CrystalUi.caption("%s  ·  %s" % [Game.mode_name(), Maps.display_name(Game.map_id)], 14, CrystalStyle.ICE)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var t := int(ceil(Game.get_round_time_left()))
	var goal := "first to %d %s" % [Game.score_limit(), Game.score_word()] if ffa else "%d %s wins" % [Game.score_limit(), Game.score_word()]
	h.add_child(CrystalUi.caption("%s  ·  %d:%02d" % [goal, t / 60, t % 60], 13, MUTED.lightened(0.15)))
	p.add_child(h)
	return p
