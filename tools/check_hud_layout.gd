extends Node
## HUD layout: nothing in the top-centre column or the bottom stack may sit on top of another
## element, at every logical screen size the project can be stretched to.
## Regression guard: the streak column overlapped the minimap under 1080p, the standing line and the
## streak popup overlapped the match clock, the notice overlapped the RELOAD line, and the presence
## feed ran into the streak popup.
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	for sz in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(1600, 1000)]:
		await _check_size(sz)
	await _check_ctf_stack()
	print("HUD LAYOUT CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _check_size(sz: Vector2) -> void:
	print("-- %dx%d" % [sz.x, sz.y])
	var hud := await _live_hud(sz, Game.MODE_FFA)
	var rects := {}
	for n in ["Timer", "FfaStanding", "StreakPopup", "Minimap", "StreakSlots", "PresenceFeed", "ChatLog",
			"Bottom/Notice", "Bottom/Reloading", "Bottom/HpRow", "Bottom/Weapons", "Fps", "KillFeed"]:
		var c := hud.get_node_or_null(n) as Control
		if c == null:
			_ok(false, "%s exists" % n)
			continue
		rects[n] = c.get_global_rect()
	# Top-centre column, top to bottom: clock, standing line, streak/flag popup.
	_ok(not _hit(rects, "Timer", "FfaStanding"), "clock clear of the standing line")
	_ok(not _hit(rects, "FfaStanding", "StreakPopup"), "standing line clear of the streak popup")
	_ok(not _hit(rects, "Timer", "StreakPopup"), "clock clear of the streak popup")
	_ok(rects["Timer"].end.y <= rects["FfaStanding"].position.y + 0.5, "standing line below the clock")
	# Left column, top to bottom: minimap, streak slots, chat log.
	_ok(not _hit(rects, "Minimap", "StreakSlots"), "streak column clear of the minimap")
	_ok(not _hit(rects, "StreakSlots", "ChatLog"), "streak column clear of the chat log")
	_ok(not _hit(rects, "PresenceFeed", "StreakPopup"), "presence feed clear of the streak popup")
	_ok(not _hit(rects, "PresenceFeed", "StreakSlots"), "presence feed clear of the streak column")
	# The FPS/perf overlay is a three-line block in the bottom-right corner: it must clear the chat,
	# the weapon boxes and the kill feed.
	_ok(not _hit(rects, "Fps", "ChatLog"), "perf overlay clear of the chat log")
	_ok(not _hit(rects, "Fps", "Bottom/Weapons"), "perf overlay clear of the weapon boxes")
	_ok(not _hit(rects, "Fps", "KillFeed"), "perf overlay clear of the kill feed")
	# Bottom stack: the notice and RELOAD are rows of it now, not free-floating labels.
	var rows := ["Bottom/Notice", "Bottom/Reloading", "Bottom/HpRow", "Bottom/Weapons"]
	for i in rows.size():
		for j in range(i + 1, rows.size()):
			_ok(not _hit(rects, rows[i], rows[j]), "%s clear of %s" % [rows[i], rows[j]])
	for n in rects:
		var r: Rect2 = rects[n]
		var inside := r.position.x >= -0.5 and r.position.y >= -0.5 \
			and r.end.x <= sz.x + 0.5 and r.end.y <= sz.y + 0.5
		_ok(inside, "%s inside the screen (%s)" % [n, r])
	hud.get_parent().queue_free()
	await get_tree().process_frame


## CTF puts a three-line status block under the clock and moves the popup beneath it.
func _check_ctf_stack() -> void:
	print("-- CTF top stack")
	var hud := await _live_hud(Vector2(1920, 1080), Game.MODE_CTF)
	var timer := (hud.get_node("Timer") as Control).get_global_rect()
	hud._place_standing()
	await get_tree().process_frame
	var standing := (hud.get_node_or_null("FfaStanding") as Control).get_global_rect()
	_ok(timer.end.y <= standing.position.y + 0.5, "CTF status block below the clock (%s / %s)" % [timer, standing])
	_ok(Hud._popup_top() >= standing.end.y, "CTF popup below the status block")
	hud.get_parent().queue_free()
	await get_tree().process_frame


func _live_hud(sz: Vector2, mode: int) -> Hud:
	Game.mode = mode
	# The popup and the standing line are built lazily; both need a real HUD in a real rect.
	var root := Control.new()
	root.size = sz
	add_child(root)
	var hud: Hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud._local_peer_id = 1
	var timer := hud.get_node("Timer") as Label
	timer.visible = true
	timer.text = "10:00"
	hud.show_notice("Class: Rifle")
	hud.show_popup("UAV", Color.GOLD, "Bot 3", 0)
	hud.set_reloading(true)
	hud.set_grenades(2, 1)
	hud._refresh_standing()
	for i in 3:
		await get_tree().process_frame
	return hud


func _hit(rects: Dictionary, a: String, b: String) -> bool:
	if not rects.has(a) or not rects.has(b):
		return false
	return (rects[a] as Rect2).intersects(rects[b] as Rect2)
