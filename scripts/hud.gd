class_name Hud
extends Control
## Crosshair, bottom HP bar + weapon slots, Tab scoreboard, kill feed. Mouse-filter ignore.

var _hit_timer := 0.0
var _kill_hit := false
var _fire_punch := 0.0
var _hint_timer := 8.0
var _hurt_flash := 0.0
var _hp := 100.0
var _max_hp := 100.0
var _scoreboard_open := false
var _scores: Array[Dictionary] = []
var _local_peer_id := 0
var _round_end_timer := 0.0
var _round_end_winner := ""
var _intermission_timer := 0.0
var _board_refresh := 0.0
var _sniper_ads := false
var _weapon_index := 0
var _ammo := 30
var _mag := 30

const _SLOT_IDLE := Color(0.08, 0.09, 0.11, 0.82)
const _SLOT_ON := Color(0.18, 0.16, 0.08, 0.92)
const _SLOT_NAMES := ["RIFLE", "PISTOL", "SHOTGUN", "SNIPER"]

@onready var hint_label: Label = $Hint
@onready var fps_label: Label = $Fps
@onready var reload_label: Label = $Reloading
@onready var hp_fill: ColorRect = $Bottom/HpWrap/HpFill
@onready var hp_label: Label = $Bottom/HpWrap/HpLabel
@onready var death_layer: ColorRect = $Death
@onready var _slots: Array[ColorRect] = [
	$Bottom/Weapons/Slot0,
	$Bottom/Weapons/Slot1,
	$Bottom/Weapons/Slot2,
	$Bottom/Weapons/Slot3,
]
@onready var scoreboard_container: VBoxContainer = $Scoreboard
@onready var round_end_label: Label = $RoundEnd
@onready var intermission_label: Label = $Intermission
@onready var timer_label: Label = $Timer
@onready var kill_feed: VBoxContainer = $KillFeed
@onready var presence_feed: VBoxContainer = $PresenceFeed
@onready var chat_log: VBoxContainer = $ChatLog
@onready var chat_input: LineEdit = $ChatInput

const _FEED_ICONS := {
	&"rifle": preload("res://assets/ui/icon_rifle.svg"),
	&"pistol": preload("res://assets/ui/icon_pistol.svg"),
	&"shotgun": preload("res://assets/ui/icon_shotgun.svg"),
	&"sniper": preload("res://assets/ui/icon_sniper.svg"),
}
const _FEED_MAX := 6
const _FEED_LIFE := 5.0


func _ready() -> void:
	add_to_group("hud")
	Game.hit_confirmed.connect(_on_hit)
	Game.score_changed.connect(_on_score_changed)
	Game.round_ended.connect(_on_round_ended)
	Game.kill_feed.connect(_on_kill_feed)
	Game.presence.connect(_on_presence)
	Game.chat_message.connect(_on_chat_message)
	reload_label.visible = false
	death_layer.visible = false
	scoreboard_container.visible = false
	scoreboard_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_end_label.visible = false
	intermission_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_weapon_slots()
	if chat_input:
		chat_input.visible = false
		chat_input.text_submitted.connect(_on_chat_submit)
		chat_input.gui_input.connect(_on_chat_gui_input)
	call_deferred("bind_player", null)


func bind_player(player: Player) -> void:
	if player == null:
		player = _local_player()
	if player == null:
		return
	_local_peer_id = player.peer_id
	if not player.health_changed.is_connected(_on_health):
		player.health_changed.connect(_on_health)
	if not player.died.is_connected(_on_died):
		player.died.connect(_on_died)
	if not player.respawned.is_connected(_on_respawned):
		player.respawned.connect(_on_respawned)
	_on_health(player.hp, Player.MAX_HP)


func _local_player() -> Player:
	for n in get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and p.is_local():
			return p
	return null


## T opens chat. Esc/toggle_mouse closes it without unlocking the cursor.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Game.chat_open:
		if event.is_action_pressed("toggle_mouse") or event.is_action_pressed("ui_cancel"):
			_close_chat(false)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("chat") and not event.is_echo():
		_open_chat()
		get_viewport().set_input_as_handled()


## Deferred focus so the T that opened chat is not typed into the box.
func _open_chat() -> void:
	Game.chat_open = true
	if chat_input:
		chat_input.visible = true
		chat_input.text = ""
		chat_input.call_deferred("grab_focus")
	if chat_log:
		for c in chat_log.get_children():
			(c as CanvasItem).modulate.a = 1.0


func _close_chat(send: bool) -> void:
	if send and chat_input:
		Game.send_chat(chat_input.text)
	Game.chat_open = false
	if chat_input:
		chat_input.release_focus()
		chat_input.text = ""
		chat_input.visible = false


func _on_chat_submit(text: String) -> void:
	Game.send_chat(text)
	_close_chat(false)


func _on_chat_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_mouse"):
		_close_chat(false)
		get_viewport().set_input_as_handled()


## Newest at the bottom. Name uses team colour; lines fade after 8s.
func _on_chat_message(n: String, team: int, text: String) -> void:
	if chat_log == null:
		return
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = Player.TEAM_COLORS[clampi(team, 0, 1)]
	row.text = "[color=#%s]%s[/color]  %s" % [col.to_html(false), n, text]
	chat_log.add_child(row)
	while chat_log.get_child_count() > 8:
		var old := chat_log.get_child(0)
		chat_log.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.5)


func punch_crosshair(amount: float = 1.0) -> void:
	_fire_punch = maxf(_fire_punch, amount)


func set_ammo(current: int, mag: int) -> void:
	_ammo = current
	_mag = mag
	_refresh_weapon_slots()


func set_weapon_name(n: String) -> void:
	var key := n.strip_edges().to_upper()
	for i in _SLOT_NAMES.size():
		if _SLOT_NAMES[i] == key:
			_weapon_index = i
			break
	_refresh_weapon_slots()


## Tight crosshair + faint ring while sniper RMB zoom is held.
func set_sniper_ads(on: bool) -> void:
	if _sniper_ads == on:
		return
	_sniper_ads = on
	queue_redraw()


func set_weapon_index(index: int) -> void:
	_weapon_index = clampi(index, 0, _SLOT_NAMES.size() - 1)
	_refresh_weapon_slots()


func _refresh_weapon_slots() -> void:
	if _slots.is_empty() or _slots[0] == null:
		return
	for i in _slots.size():
		var slot := _slots[i]
		var on := i == _weapon_index
		slot.color = _SLOT_ON if on else _SLOT_IDLE
		var name_l := slot.get_node("Name") as Label
		var ammo_l := slot.get_node("Ammo") as Label
		if name_l:
			name_l.modulate = Color(1, 0.92, 0.55) if on else Color(0.72, 0.74, 0.78)
		if ammo_l:
			ammo_l.text = ("%d / %d" % [_ammo, _mag]) if on else ""


func set_reloading(on: bool) -> void:
	reload_label.visible = on


func _on_health(hp: float, max_hp: float) -> void:
	if hp < _hp:
		_hurt_flash = 0.35
	_hp = hp
	_max_hp = max_hp
	var t := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	if hp_label:
		hp_label.text = str(roundi(hp))
	if hp_fill:
		hp_fill.anchor_right = t
		hp_fill.color = Color(0.92, 0.16, 0.12, 0.96) if t < 0.3 else Color(0.78, 0.12, 0.1, 0.95)


func _on_died() -> void:
	death_layer.visible = true


func _on_respawned() -> void:
	death_layer.visible = false
	_hurt_flash = 0.0


## Newest row on top. Local name gets a white outline (CS-style).
func _on_presence(player_name: String, joined: bool, team: int) -> void:
	if presence_feed == null:
		return
	var row := Label.new()
	var team_n: String = Game.TEAM_NAMES[clampi(team, 0, 1)]
	if joined:
		row.text = "%s joined  (%s)" % [player_name, team_n]
		row.add_theme_color_override("font_color", Color(0.55, 0.92, 0.62, 0.95))
	else:
		row.text = "%s left" % player_name
		row.add_theme_color_override("font_color", Color(0.92, 0.55, 0.5, 0.95))
	row.add_theme_font_size_override("font_size", 16)
	row.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	row.add_theme_constant_override("outline_size", 4)
	presence_feed.add_child(row)
	presence_feed.move_child(row, 0)
	while presence_feed.get_child_count() > 5:
		var old := presence_feed.get_child(presence_feed.get_child_count() - 1)
		presence_feed.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(row, "modulate:a", 0.0, 0.4)
	tw.tween_callback(row.queue_free)


func _on_kill_feed(killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int) -> void:
	if kill_feed == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var k := Label.new()
	k.text = killer_name
	k.add_theme_font_size_override("font_size", 16)
	k.add_theme_color_override("font_color", Player.TEAM_COLORS[clampi(killer_team, 0, 1)])
	if killer_name == _local_name():
		k.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
		k.add_theme_constant_override("outline_size", 4)
	var icon := TextureRect.new()
	icon.texture = _FEED_ICONS.get(weapon_id, _FEED_ICONS[&"rifle"])
	icon.custom_minimum_size = Vector2(56, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 1, 1, 0.95)
	var v := Label.new()
	v.text = victim_name
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_color_override("font_color", Player.TEAM_COLORS[clampi(victim_team, 0, 1)])
	if victim_name == _local_name():
		v.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
		v.add_theme_constant_override("outline_size", 4)
	row.add_child(k)
	row.add_child(icon)
	row.add_child(v)
	kill_feed.add_child(row)
	kill_feed.move_child(row, 0)
	while kill_feed.get_child_count() > _FEED_MAX:
		var old := kill_feed.get_child(kill_feed.get_child_count() - 1)
		kill_feed.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(_FEED_LIFE)
	tw.tween_property(row, "modulate:a", 0.0, 0.45)
	tw.tween_callback(row.queue_free)


func _local_name() -> String:
	var p := _local_player()
	if p:
		return p.display_name
	return Game.player_name


func _on_hit(killed: bool, _headshot: bool) -> void:
	_hit_timer = 0.16 if killed else 0.085
	_kill_hit = killed
	queue_redraw()


func _on_score_changed(_peer_id: int, _score: int, _n: String) -> void:
	if _scoreboard_open:
		_refresh_scoreboard()


func _sort_scores(a: Dictionary, b: Dictionary) -> bool:
	if int(a.get("team", 0)) != int(b.get("team", 0)):
		return int(a.team) < int(b.team)
	if a.kills == b.kills:
		return str(a.name) < str(b.name)
	return a.kills > b.kills


func _on_round_ended(_winner_peer_id: int, winner_name: String, _scores: Dictionary) -> void:
	_round_end_timer = 5.0
	_round_end_winner = winner_name
	round_end_label.text = "%s WINS" % winner_name
	round_end_label.visible = true
	_scoreboard_open = true
	scoreboard_container.visible = true
	_refresh_scoreboard()


func show_round_end(winner_name: String, scores: Dictionary) -> void:
	_on_round_ended(0, winner_name, scores)


func show_intermission() -> void:
	_intermission_timer = 10.0
	intermission_label.text = "INTERMISSION - NEXT ROUND SOON"
	intermission_label.visible = true


func _refresh_scoreboard() -> void:
	for c in scoreboard_container.get_children():
		c.queue_free()
	_scores = Game.get_scores()
	_scores.sort_custom(_sort_scores)

	var totals := Label.new()
	totals.text = "BLUE %d    ORANGE %d" % [Game.get_team_kills(Game.TEAM_A), Game.get_team_kills(Game.TEAM_B)]
	totals.add_theme_font_size_override("font_size", 22)
	totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_container.add_child(totals)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	for title in ["TEAM", "NAME", "KILLS", "PING"]:
		var h := Label.new()
		h.text = title
		h.add_theme_font_size_override("font_size", 16)
		if title == "NAME":
			h.custom_minimum_size = Vector2(180, 0)
		elif title == "TEAM":
			h.custom_minimum_size = Vector2(90, 0)
		else:
			h.custom_minimum_size = Vector2(70, 0)
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(h)
	scoreboard_container.add_child(header)

	for entry in _scores:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var team_id := int(entry.get("team", 0))
		var team_col: Color = Player.TEAM_COLORS[team_id]
		var team_l := Label.new()
		team_l.text = Game.TEAM_NAMES[team_id]
		team_l.custom_minimum_size = Vector2(90, 0)
		team_l.add_theme_color_override("font_color", team_col)
		var name_l := Label.new()
		name_l.text = entry.name
		name_l.custom_minimum_size = Vector2(180, 0)
		if entry.peer_id == _local_peer_id:
			name_l.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		else:
			name_l.add_theme_color_override("font_color", team_col)
		var kills_l := Label.new()
		kills_l.text = str(entry.kills)
		kills_l.custom_minimum_size = Vector2(70, 0)
		kills_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var ping_l := Label.new()
		var ping_ms := int(entry.get("ping", -1))
		ping_l.text = "—" if ping_ms < 0 else str(ping_ms)
		ping_l.custom_minimum_size = Vector2(70, 0)
		ping_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(team_l)
		row.add_child(name_l)
		row.add_child(kills_l)
		row.add_child(ping_l)
		scoreboard_container.add_child(row)


func _process(delta: float) -> void:
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_fire_punch = move_toward(_fire_punch, 0.0, delta * 9.0)
	if _hint_timer > 0.0:
		_hint_timer -= delta
		hint_label.modulate.a = clampf(_hint_timer, 0.0, 1.0)
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	fps_label.text = "%d fps" % roundi(Engine.get_frames_per_second())
	
	var time_left: float = Game.get_round_time_left()
	var mins: int = int(time_left / 60)
	var secs: int = int(time_left) % 60
	timer_label.text = "%d:%02d" % [mins, secs]
	timer_label.visible = Game._round_active

	var tab_pressed := Input.is_key_pressed(KEY_TAB)
	var want_board := tab_pressed or _round_end_timer > 0.0
	if want_board != _scoreboard_open:
		_scoreboard_open = want_board
		scoreboard_container.visible = _scoreboard_open
		if _scoreboard_open:
			_board_refresh = 0.0
			_refresh_scoreboard()
	elif _scoreboard_open:
		_board_refresh += delta
		if _board_refresh >= 0.45:
			_board_refresh = 0.0
			_refresh_scoreboard()

	if _round_end_timer > 0.0:
		_round_end_timer -= delta
		if _round_end_timer <= 0.0:
			round_end_label.visible = false
			if not tab_pressed:
				_scoreboard_open = false
				scoreboard_container.visible = false
	
	if _intermission_timer > 0.0:
		_intermission_timer -= delta
		if _intermission_timer <= 0.0:
			intermission_label.visible = false
	
	queue_redraw()


## Crosshair gap grows with spread/punch. Hurt vignette + hit/kill markers.
func _draw() -> void:
	var c := size * 0.5
	var stance := 0.0
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		stance = maxf(player.spread_multiplier() - 1.0, 0.0) * 5.0
	var gap := (2.0 if _sniper_ads else 5.0) + _fire_punch * 7.0 + stance
	var length := 8.0
	var col := Color(0.95, 0.95, 0.95, 0.92)
	var thick := 2.0
	_bar(c + Vector2(gap, 0), Vector2(length, 0), col, thick)
	_bar(c + Vector2(-gap, 0), Vector2(-length, 0), col, thick)
	_bar(c + Vector2(0, gap), Vector2(0, length), col, thick)
	_bar(c + Vector2(0, -gap), Vector2(0, -length), col, thick)
	draw_circle(c, 1.4, col)
	if _sniper_ads:
		draw_arc(c, 22.0, 0.0, TAU, 48, Color(0.05, 0.05, 0.05, 0.45), 2.0, true)

	if _hurt_flash > 0.0:
		var a := _hurt_flash * 0.55
		var red := Color(0.7, 0.05, 0.05, a)
		var t := 70.0
		draw_rect(Rect2(0, 0, size.x, t), red)
		draw_rect(Rect2(0, size.y - t, size.x, t), red)
		draw_rect(Rect2(0, 0, t, size.y), red)
		draw_rect(Rect2(size.x - t, 0, t, size.y), red)

	if _hit_timer > 0.0:
		var hit_a := clampf(_hit_timer / 0.08, 0.0, 1.0)
		var hit_col := Color(1.0, 0.22, 0.18, hit_a) if _kill_hit else Color(1, 1, 1, hit_a)
		var s := 11.0 if _kill_hit else 8.0
		draw_line(c + Vector2(-s, -s), c + Vector2(-s * 0.35, -s * 0.35), hit_col, 2.2, true)
		draw_line(c + Vector2(s, -s), c + Vector2(s * 0.35, -s * 0.35), hit_col, 2.2, true)
		draw_line(c + Vector2(-s, s), c + Vector2(-s * 0.35, s * 0.35), hit_col, 2.2, true)
		draw_line(c + Vector2(s, s), c + Vector2(s * 0.35, s * 0.35), hit_col, 2.2, true)


func _bar(from: Vector2, delta: Vector2, col: Color, thick: float) -> void:
	draw_line(from, from + delta, col, thick, true)
