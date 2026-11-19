class_name StandingLine
extends Label
## The line under the round clock (part of the HUD). FFA: "2nd · 7 / 20 kills · leader 9" (Gun Game adds
## the level); CTF (#160): captures and both flags on three lines with a gap below the clock. Other team
## modes hide it. The HUD refreshes it a few times a second.


func _init() -> void:
	name = "FfaStanding"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -220.0
	offset_right = 220.0
	offset_top = HudLayout.STANDING_TOP
	offset_bottom = HudLayout.STANDING_BOTTOM
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", HudLayout.STANDING_FONT)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 5)


func refresh(local_peer_id: int) -> void:
	visible = (Game.is_ffa() or Game.is_ctf()) and local_peer_id != 0
	if not visible:
		return
	place()
	if Game.is_ctf():
		text = CtfStatus.line(Game, local_peer_id)
		add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
		return
	var board := Game.get_scores()
	var at := 0
	var mine := 0
	var best := 0
	for i in board.size():
		var sc := int(board[i].get(Game.score_word(), 0))
		best = maxi(best, sc)
		if int(board[i].peer_id) == local_peer_id:
			at = i + 1
			mine = sc
	if at == 0:
		text = "FREE FOR ALL"
		return
	var lead := "  ·  leader %d" % best if at > 1 else ("  ·  leading" if mine > 0 else "")
	text = "%s  ·  %d / %d %s%s" % [ordinal(at), mine, Game.score_limit(), Game.score_word(), lead]
	if Game.is_gun_game():
		text += "  ·  " + GunGame.hud_line(GunGame.level_of(Game, local_peer_id)) # #148
	add_theme_color_override("font_color", Player.SELF_COLOR if at == 1 and mine > 0 else Color(0.92, 0.93, 0.95))


## FFA: one line right under the clock. CTF: three lines with a clear gap below the clock; the
## streak/flag popup then moves under them (Hud._popup_top), so the two never overlap.
func place() -> void:
	var ctf := Game.is_ctf()
	offset_top = HudLayout.CTF_TOP if ctf else HudLayout.STANDING_TOP
	offset_bottom = offset_top + (HudLayout.CTF_HEIGHT if ctf else HudLayout.STANDING_HEIGHT)
	add_theme_font_size_override("font_size", HudLayout.CTF_LINE_FONT if ctf else HudLayout.STANDING_FONT)


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]
