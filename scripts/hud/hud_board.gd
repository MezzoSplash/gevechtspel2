class_name HudBoard
extends RefCounted
## The Tab scoreboard and the round end (part of the HUD): when the board is open (Tab held, or the
## ROUND_END_SHOW seconds after a round), refreshing it every REFRESH s, and the winner card and style
## king above and under it. ScoreboardView builds the board itself; this owns its timing and cards.

const ROUND_END_SHOW := 5.0
const REFRESH := 0.45

var container: VBoxContainer # the HUD's $Scoreboard
var open := false
var scores: Array[Dictionary] = []
var local_peer_id := 0
var winner: PanelContainer # round end: winner card on top of the board
var style_king: Label # round end, under the team totals
var round_end_timer := 0.0
var round_end_winner := ""
var round_end_peer := 0 # FFA: winner peer; TDM: winning team
var _refresh_t := 0.0


func _init(board: VBoxContainer) -> void:
	container = board
	container.visible = false
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Team modes: team first; then the mode's score, style ties broken on kills, then the name.
static func sort_scores(a: Dictionary, b: Dictionary) -> bool:
	if not Game.is_ffa() and int(a.get("team", 0)) != int(b.get("team", 0)):
		return int(a.team) < int(b.team)
	var key := Game.score_word()
	if int(a.get(key, 0)) == int(b.get(key, 0)):
		if key == "style" and a.kills != b.kills:
			return a.kills > b.kills
		return str(a.name) < str(b.name)
	return int(a.get(key, 0)) > int(b.get(key, 0))


## Rebuilds the board, keeping the winner card on top and the style king under the totals.
func refresh() -> void:
	for c in container.get_children():
		if c != style_king and c != winner:
			c.queue_free()
	scores = Game.get_scores()
	scores.sort_custom(sort_scores)
	var board := ScoreboardView.build(scores, Game.is_ffa(), local_peer_id)
	container.add_child(board)
	if style_king:
		container.move_child(style_king, board.get_index())
	if winner:
		container.move_child(winner, 0)


func set_open(on: bool) -> void:
	open = on
	container.visible = on
	if on:
		_refresh_t = 0.0
		refresh()


## The round ended: cards up, board open for ROUND_END_SHOW.
func round_ended(winner_peer_id: int, winner_name: String) -> void:
	round_end_timer = ROUND_END_SHOW
	round_end_winner = winner_name
	round_end_peer = winner_peer_id
	show_winner(winner_peer_id, winner_name)
	show_style_king()
	set_open(true)


## The final killcam hid the round-end board; show it again for its full time.
func killcam_finished() -> void:
	if round_end_winner != "":
		round_ended(round_end_peer, round_end_winner)


## Per frame: open while Tab is held or the round end is showing, refreshed every REFRESH s.
func tick(delta: float, tab_pressed: bool) -> void:
	var want := tab_pressed or round_end_timer > 0.0
	if want != open:
		set_open(want)
	elif open:
		_refresh_t += delta
		if _refresh_t >= REFRESH:
			_refresh_t = 0.0
			refresh()
	if round_end_timer > 0.0:
		round_end_timer -= delta
		if round_end_timer <= 0.0:
			_hide_cards()
			if not tab_pressed:
				open = false
				container.visible = false


## Leave to menu: no cards, no round end pending.
func reset() -> void:
	_hide_cards()
	round_end_timer = 0.0
	round_end_winner = ""


func _hide_cards() -> void:
	if style_king:
		style_king.visible = false
	if winner:
		winner.visible = false


## Round end: a compact shard above the scoreboard (never over its header). Small caps line on top,
## the name under it, the seam under both in the accent. FFA: ice; "YOU WIN" for this machine's
## player is pale shell. TDM: the team's colour. No winner: no seam.
func show_winner(winner_peer_id: int, winner_name: String) -> void:
	if winner == null:
		winner = PanelContainer.new()
		winner.name = "WinnerCard"
		winner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		winner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		winner.custom_minimum_size = Vector2(340, 0)
		var v := VBoxContainer.new()
		v.name = "V"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 0)
		winner.add_child(v)
		var k := CrystalUi.caption("", 12, CrystalUi.MUTE)
		k.name = "Kicker"
		var nm := Label.new()
		nm.name = "Name"
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.add_theme_font_override("font", CrystalUi.bold_font())
		nm.add_theme_font_size_override("font_size", 32)
		for l in [k, nm]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(l)
		container.add_child(winner)
		container.move_child(winner, 0)
	var accent := HudLayout.ACCENT
	var kicker := "WINNER"
	var title := winner_name.to_upper()
	var pale := false
	if not Game.is_ffa():
		accent = Player.team_color(clampi(winner_peer_id, Game.TEAM_A, Game.TEAM_B))
		kicker = "YOUR TEAM WINS" if Game.local_team() == winner_peer_id else "WINNING TEAM"
		if Game.is_style_mode():
			kicker += "  ·  %d STYLE" % Game.team_score(clampi(winner_peer_id, Game.TEAM_A, Game.TEAM_B))
	elif winner_peer_id != 0 and winner_peer_id == local_peer_id:
		kicker = "WINNER"
		title = "YOU WIN"
		pale = true
	elif winner_peer_id == 0:
		kicker = "ROUND OVER"
		title = "NO WINNER"
		accent = Color(0, 0, 0, 0)
	var side := CrystalStyle.Side.BOTTOM if accent.a > 0.0 else CrystalStyle.Side.NONE
	var sb := CrystalUi.shard(Vector4(14, 6, 18, 8), 30, pale, side, accent, 1.0, Vector2(30, 8))
	sb.content_margin_bottom = 12
	if not pale:
		sb.fill = ScoreboardView.PANEL
	winner.add_theme_stylebox_override("panel", sb)
	var k := winner.get_node("V/Kicker") as Label
	k.text = kicker
	k.add_theme_color_override("font_color", Color(ScoreboardView.DARK, 0.6) if pale else (accent.lightened(0.2) if accent.a > 0.0 else CrystalUi.MUTE))
	var nm := winner.get_node("V/Name") as Label
	nm.text = title
	nm.add_theme_color_override("font_color", ScoreboardView.DARK if pale else ScoreboardView.TEXT)
	winner.visible = true


## Round end, under the winner card: who got the most style this round (FFA and TDM alike). A slim
## shard with a gold seam: gold is for trick rewards, and this is the round's biggest one.
func show_style_king() -> void:
	var king := Game.style_king()
	if style_king == null:
		style_king = CrystalUi.caption("", 14, HudLayout.TRICK)
		style_king.name = "StyleKing"
		style_king.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		style_king.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sb := CrystalUi.shard(Vector4(8, 3, 10, 4), 31, false, CrystalStyle.Side.BOTTOM, HudLayout.TRICK, 1.0, Vector2(22, 6))
		sb.fill = ScoreboardView.PANEL
		style_king.add_theme_stylebox_override("normal", sb)
		# Lives in the scoreboard, right under the team totals (moved there on every refresh), so it
		# never overlaps the winner line or the rows at any window size.
		container.add_child(style_king)
	if king.is_empty():
		style_king.visible = false
		return
	style_king.text = "STYLE KING  ·  %s  ·  %d STYLE" % [str(king.name).to_upper(), int(king.style)]
	style_king.visible = true


func style_king_text() -> String:
	return style_king.text if style_king and style_king.visible else ""
