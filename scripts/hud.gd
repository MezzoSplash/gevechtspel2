class_name Hud
extends Control

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

@onready var ammo_label: Label = $Ammo
@onready var weapon_label: Label = $Weapon
@onready var hint_label: Label = $Hint
@onready var fps_label: Label = $Fps
@onready var reload_label: Label = $Reloading
@onready var hp_label: Label = $Hp
@onready var death_layer: ColorRect = $Death
@onready var scoreboard_container: VBoxContainer = $Scoreboard
@onready var round_end_label: Label = $RoundEnd
@onready var intermission_label: Label = $Intermission
@onready var timer_label: Label = $Timer


func _ready() -> void:
	add_to_group("hud")
	Game.hit_confirmed.connect(_on_hit)
	Game.score_changed.connect(_on_score_changed)
	Game.round_ended.connect(_on_round_ended)
	reload_label.visible = false
	death_layer.visible = false
	scoreboard_container.visible = false
	scoreboard_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_end_label.visible = false
	intermission_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func punch_crosshair(amount: float = 1.0) -> void:
	_fire_punch = maxf(_fire_punch, amount)


func set_ammo(current: int, mag: int) -> void:
	ammo_label.text = "%d / %d" % [current, mag]


func set_weapon_name(n: String) -> void:
	weapon_label.text = n


func set_reloading(on: bool) -> void:
	reload_label.visible = on


func _on_health(hp: float, max_hp: float) -> void:
	if hp < _hp:
		_hurt_flash = 0.35
	_hp = hp
	_max_hp = max_hp
	var t := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	hp_label.text = "HP  %d" % roundi(hp)
	hp_label.modulate = Color(1.0, 0.28, 0.22) if t < 0.3 else Color(0.85, 0.95, 0.85)


func _on_died() -> void:
	death_layer.visible = true


func _on_respawned() -> void:
	death_layer.visible = false
	_hurt_flash = 0.0


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


func _draw() -> void:
	var c := size * 0.5
	var stance := 0.0
	var player := get_tree().get_first_node_in_group("player") as Player
	if player:
		stance = maxf(player.spread_multiplier() - 1.0, 0.0) * 5.0
	var gap := 5.0 + _fire_punch * 7.0 + stance
	var length := 8.0
	var col := Color(0.95, 0.95, 0.95, 0.92)
	var thick := 2.0
	_bar(c + Vector2(gap, 0), Vector2(length, 0), col, thick)
	_bar(c + Vector2(-gap, 0), Vector2(-length, 0), col, thick)
	_bar(c + Vector2(0, gap), Vector2(0, length), col, thick)
	_bar(c + Vector2(0, -gap), Vector2(0, -length), col, thick)
	draw_circle(c, 1.4, col)

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
