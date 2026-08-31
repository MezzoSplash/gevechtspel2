class_name Hud
extends Control

var _hit_timer := 0.0
var _kill_hit := false
var _fire_punch := 0.0
var _hint_timer := 8.0
var _hurt_flash := 0.0
var _hp := 100.0
var _max_hp := 100.0

@onready var ammo_label: Label = $Ammo
@onready var weapon_label: Label = $Weapon
@onready var hint_label: Label = $Hint
@onready var fps_label: Label = $Fps
@onready var reload_label: Label = $Reloading
@onready var hp_label: Label = $Hp
@onready var death_layer: ColorRect = $Death


func _ready() -> void:
	add_to_group("hud")
	Game.hit_confirmed.connect(_on_hit)
	reload_label.visible = false
	death_layer.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("bind_player", null)


func bind_player(player: Player) -> void:
	if player == null:
		player = _local_player()
	if player == null:
		return
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


func _process(delta: float) -> void:
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_fire_punch = move_toward(_fire_punch, 0.0, delta * 9.0)
	if _hint_timer > 0.0:
		_hint_timer -= delta
		hint_label.modulate.a = clampf(_hint_timer, 0.0, 1.0)
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	fps_label.text = "%d fps" % roundi(Engine.get_frames_per_second())
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
