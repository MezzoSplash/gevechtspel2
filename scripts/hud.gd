class_name Hud
extends Control
## Crosshair, bottom HP bar + weapon slots, Tab scoreboard, kill feed. Mouse-filter ignore.

var _hit_timer := 0.0
var _kill_hit := false
var _head_hit := false
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
var _freeze_left := 0.0
var _radar_left := 0.0
var _streak_n := 0
var _streak_charges := 0
var _streak_earned := 0
var _streak_sel := 0
var _rc_on := false
var _rc_hint: Label
var _announcer: AudioStreamPlayer
var _sniper_ads := false
var _sniper_hip := false # sniper in hand and RMB zoom off: draw no crosshair
var _weapon_index := 0
var _ammo := 30
var _mag := 30
var _notice: Label
var _notice_tween: Tween
var _player: Player # the local pawn from bind_player; crosshair bloom follows it
var _dmg_dirs: Array[Dictionary] = [] # {pos: Vector3, t: float}: where recent damage came from
var _standing: Label # FFA: your place and kills under the clock
var _standing_t := 0.0

const DMG_DIR_LIFE := 1.3 # seconds a damage direction wedge stays (fades out)
const DMG_DIR_MAX := 6
const DMG_DIR_RADIUS := 118.0 # px from screen centre to the wedge
const DMG_DIR_HALF := 0.36 # rad: half the wedge's arc (~20°)

const _SLOT_IDLE := Color(0.06, 0.07, 0.09, 0.78)
const _SLOT_ON := Color(0.12, 0.11, 0.07, 0.9)
const HUD_ACCENT := Color(1.0, 0.84, 0.42) # gold: held weapon, selected streak, own scoreboard row
const HUD_PANEL := Color(0.05, 0.06, 0.08, 0.78)
var _slot_names: PackedStringArray = ["RIFLE", "PISTOL", "SHOTGUN", "SNIPER"] # the local pawn's guns

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
@onready var countdown_label: Label = $Countdown
@onready var grenade_label: Label = $Bottom/Grenades
@onready var streak_label: Label = $StreakSlots/Streak
@onready var _streak_slots: Array[ColorRect] = [
	$StreakSlots/Slot0,
	$StreakSlots/Slot1,
	$StreakSlots/Slot2,
]
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
	&"grenade": preload("res://assets/ui/icon_grenade.svg"),
	&"smg": preload("res://assets/ui/icon_smg.svg"),
	&"revolver": preload("res://assets/ui/icon_revolver.svg"),
	&"knife": preload("res://assets/ui/icon_knife.svg"),
	&"melee": preload("res://assets/ui/icon_melee.svg"),
	&"lmg": preload("res://assets/ui/icon_lmg.svg"),
	&"slug": preload("res://assets/ui/icon_slug.svg"),
	&"rcxd": preload("res://assets/ui/icon_rcxd.svg"),
	&"fall": preload("res://assets/ui/icon_fall.svg"), # kill_y (map drop), see player._check_kill_y
}
const _FEED_MAX := 6
const _FEED_LIFE := 5.0
const _POPUP_HOLD := 2.4 # streak popup under the clock: hold, then fade
const _POPUP_FADE := 0.6
const _POPUP_FRIENDLY := Color(1.0, 0.86, 0.4)
const _POPUP_HOSTILE := Color(1.0, 0.36, 0.3)
const TRICK_COLOR := Color(1.0, 0.78, 0.22) # trickshot gold: popup, feed tag, killcam, style king
const _TRICK_HOLD := 1.5
const _TRICK_FADE := 0.45
const _TRICK_SFX := preload("res://assets/sounds/trickshot.wav")

var _trick: VBoxContainer # big centred trickshot word for the shooter
var _trick_title: Label
var _trick_sub: Label
var _trick_tween: Tween
var _trick_sfx: AudioStreamPlayer
var _style_king: Label # round end, under the winner
var _winner: PanelContainer # round end: winner card on top of the scoreboard
var _round_end_peer := 0 # FFA: winner peer; TDM: winning team

var _popup: VBoxContainer
var _popup_title: Label
var _popup_by: RichTextLabel
var _popup_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	Game.hit_confirmed.connect(_on_hit)
	Game.score_changed.connect(_on_score_changed)
	Game.round_ended.connect(_on_round_ended)
	Game.kill_feed.connect(_on_kill_feed)
	Game.trick_scored.connect(_on_trick_scored)
	Game.presence.connect(_on_presence)
	Game.chat_message.connect(_on_chat_message)
	Game.round_freeze_changed.connect(_on_round_freeze)
	Game.intermission_started.connect(show_intermission)
	Game.killcam.finished.connect(_on_killcam_finished)
	reload_label.visible = false
	fps_label.visible = Game.show_fps
	Game.hud_settings_changed.connect(_apply_hud_settings)
	_apply_hud_settings()
	death_layer.visible = false
	scoreboard_container.visible = false
	scoreboard_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	round_end_label.visible = false
	intermission_label.visible = false
	if countdown_label:
		countdown_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_bottom()
	_facelift_hud()
	_refresh_weapon_slots()
	for slot in _streak_slots:
		_add_streak_frame(slot)
	_announcer = AudioStreamPlayer.new()
	_announcer.bus = "UI"
	_announcer.volume_db = -2.0
	add_child(_announcer)
	_refresh_streak_ui()
	_build_popup()
	_build_trick_popup()
	if chat_input:
		chat_input.visible = false
		chat_input.text_submitted.connect(_on_chat_submit)
		chat_input.gui_input.connect(_on_chat_gui_input)
	call_deferred("bind_player", null)


func _apply_hud_settings() -> void:
	var mm := get_node_or_null("Minimap") as Control
	if mm:
		mm.visible = Game.show_minimap
	if kill_feed:
		kill_feed.visible = Game.show_killfeed
	queue_redraw()


func bind_player(player: Player) -> void:
	if player == null:
		player = _local_player()
	if player == null:
		return
	_player = player
	var mm := get_node_or_null("Minimap") as Minimap
	if mm:
		mm.player = player
	_local_peer_id = player.peer_id
	if not player.health_changed.is_connected(_on_health):
		player.health_changed.connect(_on_health)
	if not player.died.is_connected(_on_died):
		player.died.connect(_on_died)
	if not player.respawned.is_connected(_on_respawned):
		player.respawned.connect(_on_respawned)
	if not player.damage_from.is_connected(add_damage_dir):
		player.damage_from.connect(add_damage_dir)
	_on_health(player.hp, Player.MAX_HP)


## Damage direction indicator: a red wedge around the crosshair pointing at `from_pos`. Each hit
## adds one (they stack); they turn with your view and fade over DMG_DIR_LIFE.
func add_damage_dir(from_pos: Vector3) -> void:
	_dmg_dirs.append({"pos": from_pos, "t": DMG_DIR_LIFE})
	while _dmg_dirs.size() > DMG_DIR_MAX:
		_dmg_dirs.pop_front()
	queue_redraw()


## Screen angle of a world point around the crosshair: 0 = ahead (up), +PI/2 = right, PI = behind.
static func dir_angle(view: Transform3D, world_pos: Vector3) -> float:
	var to := world_pos - view.origin
	var local := view.basis.inverse() * to
	return atan2(local.x, -local.z)


func _draw_damage_dirs(c: Vector2) -> void:
	if _dmg_dirs.is_empty() or not is_instance_valid(_player):
		return
	var view := Transform3D(Basis(Vector3.UP, _player.rotation.y), _player.global_position)
	for d in _dmg_dirs:
		var a := dir_angle(view, d.pos) - PI * 0.5 # draw_* angles: 0 = right, clockwise on screen
		var alpha := clampf(float(d.t) / DMG_DIR_LIFE, 0.0, 1.0)
		alpha = alpha * alpha * (3.0 - 2.0 * alpha)
		var pts := PackedVector2Array()
		var steps := 10
		for i in steps + 1:
			var t := a - DMG_DIR_HALF + DMG_DIR_HALF * 2.0 * float(i) / steps
			pts.append(c + Vector2(cos(t), sin(t)) * DMG_DIR_RADIUS)
		for i in range(steps, -1, -1):
			var t := a - DMG_DIR_HALF * 0.55 + DMG_DIR_HALF * 1.1 * float(i) / steps
			pts.append(c + Vector2(cos(t), sin(t)) * (DMG_DIR_RADIUS + 26.0))
		draw_colored_polygon(pts, Color(0.92, 0.1, 0.08, 0.72 * alpha))
		var tip := c + Vector2(cos(a), sin(a)) * (DMG_DIR_RADIUS + 34.0)
		var l := c + Vector2(cos(a - 0.1), sin(a - 0.1)) * (DMG_DIR_RADIUS + 25.0)
		var r := c + Vector2(cos(a + 0.1), sin(a + 0.1)) * (DMG_DIR_RADIUS + 25.0)
		draw_colored_polygon(PackedVector2Array([l, tip, r]), Color(1.0, 0.2, 0.15, 0.85 * alpha))


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
	if Game.pause_open:
		return
	# Driving: the car has the mouse and LMB. Streak keys and chat wait until it is gone.
	if Game.rc_view:
		if (
			event.is_action_pressed("ui_up")
			or event.is_action_pressed("ui_down")
			or event.is_action_pressed("use_streak")
			or event.is_action_pressed("chat")
		):
			get_viewport().set_input_as_handled()
		return
	# Arrows pick a streak box. Enter asks the server to fire it. Chat keeps Enter.
	if not Game.chat_open and not event.is_echo():
		if event.is_action_pressed("ui_up"):
			_streak_sel = (_streak_sel + 2) % 3
			_refresh_streak_ui()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_down"):
			_streak_sel = (_streak_sel + 1) % 3
			_refresh_streak_ui()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("use_streak"):
			Game.request_use_streak(_streak_sel)
			get_viewport().set_input_as_handled()
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
	var col: Color = _name_color(n, team)
	row.text = "[color=#%s]%s[/color]  %s" % [col.to_html(false), _bb_escape(n), _bb_escape(text)]
	chat_log.add_child(row)
	while chat_log.get_child_count() > 8:
		var old := chat_log.get_child(0)
		chat_log.remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(8.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.5)


## Player text must not become BBCode ([img], [font_size], …). [lb] is a literal "[".
func _bb_escape(s: String) -> String:
	return s.replace("[", "[lb]")


## Leave to menu: drop streak/radar/death overlay from the old session.
func reset_session() -> void:
	_player = null
	_local_peer_id = 0
	_dmg_dirs.clear()
	_streak_n = 0
	_streak_charges = 0
	_streak_earned = 0
	_radar_left = 0.0
	set_rc_drive(false, 0.0, 0.0)
	_hide_popup()
	_hide_notice()
	_hide_trick()
	if _style_king:
		_style_king.visible = false
	if _winner:
		_winner.visible = false
	_freeze_left = 0.0
	_round_end_timer = 0.0
	_round_end_winner = ""
	_intermission_timer = 0.0
	death_layer.visible = false
	round_end_label.visible = false
	if _winner:
		_winner.visible = false
	intermission_label.visible = false
	if countdown_label:
		countdown_label.visible = false
	_refresh_streak_ui()


## Freeze is the round start. The countdown and the "Round starting" line share that moment.
func _on_round_freeze(on: bool) -> void:
	_freeze_left = Game.FREEZE_TIME if on else 0.0
	if countdown_label:
		countdown_label.visible = on
		if on:
			countdown_label.text = str(ceili(_freeze_left))
	if on:
		_play_announcer("res://assets/sounds/round_starting.wav")


func punch_crosshair(amount: float = 1.0) -> void:
	_fire_punch = maxf(_fire_punch, amount)


func set_ammo(current: int, mag: int) -> void:
	_ammo = current
	_mag = mag
	_refresh_weapon_slots()


## The class decides the guns: one box per carried gun, keys 1..n in that order.
func set_weapon_slots(names: PackedStringArray) -> void:
	var upper: PackedStringArray = []
	for n in names:
		upper.append(n.strip_edges().to_upper())
	if upper == _slot_names:
		return
	_slot_names = upper
	_refresh_weapon_slots()


## Tight crosshair + faint ring while sniper RMB zoom is held.
func set_sniper_ads(on: bool) -> void:
	if _sniper_ads == on:
		return
	_sniper_ads = on
	queue_redraw()


## The sniper has no hip crosshair. Bars and the centre dot return while zoomed.
func set_sniper_hip(on: bool) -> void:
	if _sniper_hip == on:
		return
	_sniper_hip = on
	queue_redraw()


func set_weapon_index(index: int) -> void:
	_weapon_index = clampi(index, 0, maxi(_slot_names.size() - 1, 0))
	_refresh_weapon_slots()


## Bottom HUD: rounded HP bar (track + fill), grenade/knife pill, outlined streak counter.
func _style_bottom() -> void:
	var bg := get_node_or_null("Bottom/HpWrap/HpBg") as ColorRect
	if bg:
		bg.color = Color(0.04, 0.05, 0.06, 0.8)
		_skin(bg, 8)
		_paint(bg, Color(0.04, 0.05, 0.06, 0.8))
	if hp_fill:
		_skin(hp_fill, 8)
		_paint(hp_fill, Color(0.27, 0.82, 0.48, 0.95))
		(hp_fill.get_node("Skin").get_theme_stylebox("panel") as StyleBoxFlat).border_width_top = 0
	if grenade_label:
		var sb := StyleBoxFlat.new()
		sb.bg_color = HUD_PANEL
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		grenade_label.add_theme_stylebox_override("normal", sb)
		grenade_label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.96))
		grenade_label.add_theme_font_size_override("font_size", 16)
		grenade_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if streak_label:
		streak_label.add_theme_font_size_override("font_size", 14)


## Rounded panel behind a ColorRect slot (a ColorRect has no corners or border). The rect itself
## goes transparent; _paint recolours the panel. Same nodes and labels as before.
func _skin(rect: ColorRect, radius: int = 8) -> void:
	if rect == null or rect.get_node_or_null("Skin"):
		return
	var p := Panel.new()
	p.name = "Skin"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.show_behind_parent = true
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = rect.color
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	rect.add_child(p)
	rect.move_child(p, 0)
	rect.color = Color(0, 0, 0, 0)


## `accent` draws a border (selection / held weapon); `top` thickens only the top edge.
func _paint(rect: ColorRect, bg: Color, accent: Color = Color(0, 0, 0, 0), top: int = 0) -> void:
	var p := rect.get_node_or_null("Skin") as Panel
	if p == null:
		rect.color = bg
		return
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	sb.bg_color = bg
	sb.border_color = accent if accent.a > 0.0 else Color(1, 1, 1, 0.07)
	var w := 2 if accent.a > 0.0 else 1
	sb.border_width_left = w
	sb.border_width_right = w
	sb.border_width_bottom = w
	sb.border_width_top = maxi(w, top)


## Shrink a one-line label until it fits `max_w` (SLUG SHOTGUN in a 122 px slot, #58).
func _fit_label(l: Label, max_w: float, size: int, min_size: int) -> void:
	var font := l.get_theme_font("font")
	var fs := size
	while fs > min_size and font and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _refresh_weapon_slots() -> void:
	if _slots.is_empty() or _slots[0] == null:
		return
	for i in _slots.size():
		var slot := _slots[i]
		slot.visible = i < _slot_names.size()
		if not slot.visible:
			continue
		var on := i == _weapon_index
		_skin(slot)
		_paint(slot, _SLOT_ON if on else _SLOT_IDLE, HUD_ACCENT if on else Color(0, 0, 0, 0), 3 if on else 0)
		var name_l := slot.get_node("Name") as Label
		var ammo_l := slot.get_node("Ammo") as Label
		var key_l := slot.get_node_or_null("Key") as Label
		if key_l:
			key_l.text = str(i + 1)
		if name_l:
			name_l.text = _slot_names[i]
			_fit_label(name_l, slot.custom_minimum_size.x - 14.0, 16, 12)
			name_l.modulate = Color(1, 0.92, 0.55) if on else Color(0.72, 0.74, 0.78)
		if ammo_l:
			ammo_l.text = ("%d / %d" % [_ammo, _mag]) if on else ""


## A new radar charge plays "Radar on standby", a new RC-XD charge "RC-XD ready for deployment".
## Only the player who owns the streak gets this call. The slot stays armed until Enter, including after death.
func set_streak(n: int, charges: int, earned: int) -> void:
	var radar_new := (_streak_charges & Game.CHARGE_RADAR) == 0 and (charges & Game.CHARGE_RADAR) != 0
	var rcxd_new := (_streak_charges & Game.CHARGE_RCXD) == 0 and (charges & Game.CHARGE_RCXD) != 0
	_streak_n = n
	_streak_charges = charges
	_streak_earned = earned
	_refresh_streak_ui()
	# Both at once is not expected (3 vs 5 kills); the RC-XD line wins then, it is the newer reward.
	if rcxd_new:
		_play_announcer("res://assets/sounds/rcxd_ready.wav")
	elif radar_new:
		_play_announcer("res://assets/sounds/radar_standby.wav")


## Team radar switched on. Your team, including the player who turned it on, hears
## "Friendly radar online" and gets the markers. The other team hears "Enemy radar online".
## Popups stay gold for your team and red for the other.
func show_radar_event(by_name: String, team: int, friendly: bool) -> void:
	if friendly:
		_radar_left = maxf(_radar_left, Game.radar_left)
		_refresh_streak_ui()
		_play_announcer("res://assets/sounds/radar_friendly.wav")
		show_popup("UAV", _POPUP_FRIENDLY, by_name, team)
	else:
		_play_announcer("res://assets/sounds/radar_enemy.wav")
		show_popup("ENEMY UAV", _POPUP_HOSTILE, by_name, team)


## RC-XD switched on. Own team gets the plain title. The other team gets the enemy title. No voice line.
func show_rc_event(by_name: String, team: int, friendly: bool) -> void:
	if friendly:
		show_popup("RC-XD", _POPUP_FRIENDLY, by_name, team)
	else:
		show_popup("ENEMY RC-XD", _POPUP_HOSTILE, by_name, team)


## While the local camera is in the car. `on` false hides the line.
func set_rc_drive(on: bool, hp: float, life: float) -> void:
	_rc_on = on
	if not on:
		if _rc_hint:
			_rc_hint.visible = false
		_refresh_streak_ui()
		return
	if _rc_hint == null:
		_rc_hint = Label.new()
		_rc_hint.name = "RcHint"
		_rc_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rc_hint.anchor_left = 0.5
		_rc_hint.anchor_right = 0.5
		_rc_hint.anchor_top = 0.5
		_rc_hint.anchor_bottom = 0.5
		_rc_hint.offset_left = -220.0
		_rc_hint.offset_right = 220.0
		_rc_hint.offset_top = 48.0
		_rc_hint.offset_bottom = 80.0
		_rc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rc_hint.add_theme_font_size_override("font_size", 20)
		_rc_hint.add_theme_color_override("font_color", Color(1, 0.86, 0.35))
		_rc_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_rc_hint.add_theme_constant_override("outline_size", 6)
		add_child(_rc_hint)
	_rc_hint.text = "LMB DETONATE    %d HP    %ds" % [ceili(maxf(hp, 0.0)), ceili(maxf(life, 0.0))]
	_rc_hint.visible = true
	_refresh_streak_ui()


func clear_radar() -> void:
	if _radar_left <= 0.0:
		return
	_radar_left = 0.0
	_refresh_streak_ui()


## Top centre, under the round clock: what was switched on, and by whom (name in team colour).
func show_popup(title: String, title_col: Color, by_name: String, team: int) -> void:
	if _popup == null:
		return
	_popup_title.text = title
	_popup_title.add_theme_color_override("font_color", title_col)
	var col: Color = _name_color(by_name, team)
	_popup_by.text = "[center][color=#d8dade]by[/color] [color=#%s]%s[/color][/center]" % [
		col.to_html(false), _bb_escape(by_name)
	]
	if _popup_tween:
		_popup_tween.kill()
	_popup.modulate.a = 1.0
	_popup.visible = true
	_popup_tween = _popup.create_tween()
	_popup_tween.tween_interval(_POPUP_HOLD)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, _POPUP_FADE)
	_popup_tween.tween_callback(_hide_popup)


func _hide_popup() -> void:
	if _popup_tween:
		_popup_tween.kill()
		_popup_tween = null
	if _popup:
		_popup.visible = false


## Small line above the weapon boxes ("Class changes at next spawn"). Fades by itself.
func show_notice(text: String, seconds: float = 3.0) -> void:
	if _notice == null:
		_build_notice()
	_notice.text = text
	if _notice_tween:
		_notice_tween.kill()
	_notice.modulate.a = 1.0
	_notice.visible = true
	_notice_tween = _notice.create_tween()
	_notice_tween.tween_interval(seconds)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, 0.5)
	_notice_tween.tween_callback(_hide_notice)


func notice_text() -> String:
	return _notice.text if _notice and _notice.visible else ""


func _hide_notice() -> void:
	if _notice_tween:
		_notice_tween.kill()
		_notice_tween = null
	if _notice:
		_notice.visible = false


func _build_notice() -> void:
	_notice = Label.new()
	_notice.name = "Notice"
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.anchor_left = 0.5
	_notice.anchor_right = 0.5
	_notice.anchor_top = 1.0
	_notice.anchor_bottom = 1.0
	_notice.offset_left = -300.0
	_notice.offset_right = 300.0
	_notice.offset_top = -196.0
	_notice.offset_bottom = -168.0
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 18)
	_notice.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	_notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_notice.add_theme_constant_override("outline_size", 6)
	_notice.visible = false
	add_child(_notice)


func _build_popup() -> void:
	_popup = VBoxContainer.new()
	_popup.name = "StreakPopup"
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.anchor_left = 0.5
	_popup.anchor_right = 0.5
	_popup.offset_left = -220.0
	_popup.offset_right = 220.0
	_popup.offset_top = 66.0
	_popup.offset_bottom = 136.0
	_popup.add_theme_constant_override("separation", 0)
	_popup.visible = false
	add_child(_popup)
	_popup_title = Label.new()
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_title.add_theme_font_size_override("font_size", 30)
	_popup_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_popup_title.add_theme_constant_override("outline_size", 8)
	_popup_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(_popup_title)
	_popup_by = RichTextLabel.new()
	_popup_by.bbcode_enabled = true
	_popup_by.fit_content = true
	_popup_by.scroll_active = false
	_popup_by.autowrap_mode = TextServer.AUTOWRAP_OFF
	_popup_by.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_by.add_theme_font_size_override("normal_font_size", 18)
	_popup_by.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_popup_by.add_theme_constant_override("outline_size", 6)
	_popup.add_child(_popup_by)


## Left column: slot 0 radar (3), slot 1 RC-XD (5), slot 2 empty.
## The white frame is the arrow-key selection, not "ready". A gold box is a charge you still hold.
func _refresh_streak_ui() -> void:
	_refresh_streak_extras()
	for i in _streak_slots.size():
		var slot := _streak_slots[i]
		if slot == null:
			continue
		var selected := i == _streak_sel
		var ready := false
		if i == 0:
			ready = (_streak_charges & Game.CHARGE_RADAR) != 0
		elif i == 1:
			ready = (_streak_charges & Game.CHARGE_RCXD) != 0
		var name_l := slot.get_node_or_null("Name") as Label
		if name_l and i == 1:
			var col := Color(1, 0.92, 0.55) if ready else Color(0.55, 0.58, 0.62)
			name_l.add_theme_color_override("font_color", col)
		_skin(slot)
		var bg := Color(0.06, 0.07, 0.09, 0.6 if i > 0 else 0.78)
		if ready:
			bg = Color(0.3, 0.24, 0.07, 0.94) if selected else Color(0.2, 0.16, 0.05, 0.88)
		elif selected:
			bg = Color(0.12, 0.13, 0.16, 0.9)
		var edge := Color(0, 0, 0, 0)
		if selected:
			edge = HUD_ACCENT if ready else Color(0.92, 0.94, 0.97, 0.9)
		elif ready:
			edge = Color(HUD_ACCENT, 0.45)
		_paint(slot, bg, edge)
		_set_streak_frame(slot, false) # the rounded border replaces the old white bars


## Four thin bars. A ColorRect has no border, so the selection is drawn as children.
func _add_streak_frame(slot: ColorRect) -> void:
	if slot == null or slot.get_node_or_null("FrameTop"):
		return
	var edges := {
		"FrameTop": [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 3.0],
		"FrameBottom": [0.0, 1.0, 1.0, 1.0, 0.0, -3.0, 0.0, 0.0],
		"FrameLeft": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 3.0, 0.0],
		"FrameRight": [1.0, 0.0, 1.0, 1.0, -3.0, 0.0, 0.0, 0.0],
	}
	for edge_name in edges:
		var spec: Array = edges[edge_name]
		var bar := ColorRect.new()
		bar.name = edge_name
		bar.color = Color.WHITE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		slot.add_child(bar)
		bar.anchor_left = spec[0]
		bar.anchor_top = spec[1]
		bar.anchor_right = spec[2]
		bar.anchor_bottom = spec[3]
		bar.offset_left = spec[4]
		bar.offset_top = spec[5]
		bar.offset_right = spec[6]
		bar.offset_bottom = spec[7]


func _set_streak_frame(slot: ColorRect, on: bool) -> void:
	for edge_name in ["FrameTop", "FrameBottom", "FrameLeft", "FrameRight"]:
		var bar := slot.get_node_or_null(edge_name) as ColorRect
		if bar:
			bar.visible = on


func _play_announcer(path: String) -> void:
	if _announcer == null:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_announcer.stream = stream
	_announcer.play()


## Grenade slot: frags on G, throwing knives on F (only shown when the class carries knives).
## Sits at the right end of the HP row (#65); the key letter is dimmer than the count.
func set_grenades(n: int, knives: int = 0) -> void:
	if grenade_label:
		grenade_label.text = "G  FRAG %d" % n if knives <= 0 else "G  FRAG %d    F  KNIFE %d" % [n, knives]


var _streak_pips: HBoxContainer
var _streak_costs: Array[Label] = []


## #65: one HP row (bar + grenade/knife pill), even weapon slots, a scorestreak column with
## kill pips and cost/ready tags. The key hint line at the top (over the clock) is gone;
## the keys are in Settings > Controls.
func _facelift_hud() -> void:
	if hint_label:
		hint_label.visible = false
	_hint_timer = 0.0
	var bottom := get_node_or_null("Bottom") as VBoxContainer
	var wrap := get_node_or_null("Bottom/HpWrap") as Control
	if bottom and wrap and grenade_label and wrap.get_parent() == bottom:
		var row := HBoxContainer.new()
		row.name = "HpRow"
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var at := wrap.get_index()
		bottom.add_child(row)
		bottom.move_child(row, at)
		wrap.reparent(row, false)
		wrap.custom_minimum_size = Vector2(0, 28)
		wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grenade_label.reparent(row, false)
		grenade_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grenade_label.add_theme_font_size_override("font_size", 15)
	if hp_label:
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hp_label.offset_left = 12.0
		hp_label.add_theme_font_size_override("font_size", 17)
		hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		hp_label.add_theme_constant_override("outline_size", 4)
	# Scorestreak column: small caps title, then one pip per kill toward the next reward.
	if streak_label:
		streak_label.add_theme_font_size_override("font_size", 13)
		streak_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_streak_pips = HBoxContainer.new()
		_streak_pips.name = "Pips"
		_streak_pips.add_theme_constant_override("separation", 4)
		_streak_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := streak_label.get_parent()
		col.add_child(_streak_pips)
		col.move_child(_streak_pips, streak_label.get_index() + 1)
		for i in Game.RCXD_AT:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(20, 6)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := StyleBoxFlat.new()
			sb.set_corner_radius_all(3)
			sb.bg_color = Color(1, 1, 1, 0.14)
			pip.add_theme_stylebox_override("panel", sb)
			_streak_pips.add_child(pip)
	for i in _streak_slots.size():
		var slot := _streak_slots[i]
		var cost: Label = null
		if slot and i < 2:
			cost = Label.new()
			cost.name = "Cost"
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cost.anchor_left = 0.0
			cost.anchor_right = 1.0
			cost.anchor_top = 1.0
			cost.anchor_bottom = 1.0
			cost.offset_top = -20.0
			cost.offset_bottom = -4.0
			cost.offset_right = -8.0
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cost.add_theme_font_size_override("font_size", 11)
			slot.add_child(cost)
		_streak_costs.append(cost)


func _refresh_streak_extras() -> void:
	if streak_label:
		streak_label.text = "SCORESTREAK"
	var goal := Game.RCXD_AT
	if _streak_pips:
		for i in _streak_pips.get_child_count():
			var pip := _streak_pips.get_child(i) as Panel
			var sb := pip.get_theme_stylebox("panel") as StyleBoxFlat
			var lit := i < _streak_n
			var mark := i == Game.STREAK_AT - 1 or i == goal - 1 # UAV and RC-XD steps
			sb.bg_color = HUD_ACCENT if lit else (Color(1, 1, 1, 0.26) if mark else Color(1, 1, 1, 0.12))
	for i in _streak_costs.size():
		var c := _streak_costs[i]
		if c == null:
			continue
		var bit := Game.CHARGE_RADAR if i == 0 else Game.CHARGE_RCXD
		var is_ready := (_streak_charges & bit) != 0
		c.text = "READY · ENTER" if is_ready else "%d KILLS" % (Game.STREAK_AT if i == 0 else Game.RCXD_AT)
		c.add_theme_color_override("font_color", HUD_ACCENT if is_ready else Color(0.62, 0.66, 0.72, 0.85))


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
		var fill := Color(0.92, 0.2, 0.16, 0.96) if t < 0.3 else Color(0.27, 0.82, 0.48, 0.95)
		if t >= 0.3 and t < 0.6:
			fill = Color(0.95, 0.72, 0.25, 0.95)
		_paint(hp_fill, fill)


var _death_report: PanelContainer
var _death_report_tw: Tween


## #64: "Killed by X" card under RESPAWNING, then it stays a few seconds into the next life.
func show_death_report(killer: String, taken: int, taken_hits: int, dealt: int, dealt_hits: int, killer_hp: int) -> void:
	if _death_report == null:
		_death_report = PanelContainer.new()
		_death_report.name = "DeathReport"
		_death_report.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_death_report.anchor_left = 0.5
		_death_report.anchor_right = 0.5
		_death_report.anchor_top = 0.5
		_death_report.anchor_bottom = 0.5
		_death_report.offset_left = -190.0
		_death_report.offset_right = 190.0
		_death_report.offset_top = 48.0
		_death_report.grow_horizontal = Control.GROW_DIRECTION_BOTH
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.08, 0.88)
		sb.set_corner_radius_all(12)
		sb.border_color = Color(0.92, 0.3, 0.25)
		sb.border_width_top = 3
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 10
		sb.content_margin_bottom = 12
		_death_report.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.name = "V"
		v.add_theme_constant_override("separation", 6)
		_death_report.add_child(v)
		var head := Label.new()
		head.name = "Head"
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 18)
		v.add_child(head)
		for row in ["Taken", "Dealt"]:
			var h := HBoxContainer.new()
			h.name = row
			var l := Label.new()
			l.name = "L"
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
			h.add_child(l)
			var r := Label.new()
			r.name = "R"
			r.add_theme_font_size_override("font_size", 16)
			h.add_child(r)
			v.add_child(h)
		add_child(_death_report)
	var v2 := _death_report.get_node("V")
	(v2.get_node("Head") as Label).text = "KILLED BY  %s" % killer.to_upper()
	(v2.get_node("Taken/L") as Label).text = "Their damage to you"
	(v2.get_node("Taken/R") as Label).text = "%d  ·  %d %s" % [taken, taken_hits, "hit" if taken_hits == 1 else "hits"]
	(v2.get_node("Taken/R") as Label).add_theme_color_override("font_color", Color(0.95, 0.45, 0.4))
	(v2.get_node("Dealt/L") as Label).text = "Your damage to them"
	var tail := "  ·  %d HP left" % killer_hp if killer_hp > 0 else ""
	(v2.get_node("Dealt/R") as Label).text = "%d  ·  %d %s%s" % [dealt, dealt_hits, "hit" if dealt_hits == 1 else "hits", tail]
	(v2.get_node("Dealt/R") as Label).add_theme_color_override("font_color", HUD_ACCENT if dealt > 0 else SB_MUTED)
	_death_report.visible = true
	_death_report.modulate.a = 1.0
	if _death_report_tw and _death_report_tw.is_valid():
		_death_report_tw.kill()
	_death_report_tw = create_tween()
	_death_report_tw.tween_interval(5.0)
	_death_report_tw.tween_property(_death_report, "modulate:a", 0.0, 0.6)
	_death_report_tw.tween_callback(func() -> void: _death_report.visible = false)


func _on_died() -> void:
	death_layer.visible = true


func _on_respawned() -> void:
	death_layer.visible = false
	_hurt_flash = 0.0
	_dmg_dirs.clear()


## Newest row on top. Local name gets a white outline (CS-style).
func _on_presence(player_name: String, joined: bool, team: int) -> void:
	if presence_feed == null:
		return
	var row := Label.new()
	var team_n: String = Game.TEAM_NAMES[clampi(team, 0, 1)]
	if joined and Game.is_ffa():
		row.text = "%s joined" % player_name
		row.add_theme_color_override("font_color", Color(0.55, 0.92, 0.62, 0.95))
	elif joined:
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


func _on_kill_feed(
	killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int,
	tricks: String = ""
) -> void:
	if kill_feed == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var k := Label.new()
	k.text = killer_name
	k.add_theme_font_size_override("font_size", 16)
	k.add_theme_color_override("font_color", _name_color(killer_name, killer_team))
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
	v.add_theme_color_override("font_color", _name_color(victim_name, victim_team))
	if victim_name == _local_name():
		v.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
		v.add_theme_constant_override("outline_size", 4)
	row.add_child(k)
	row.add_child(icon)
	row.add_child(v)
	if tricks != "":
		var tag := Label.new()
		tag.name = "TrickTag"
		tag.text = tricks
		tag.add_theme_font_size_override("font_size", 14)
		tag.add_theme_color_override("font_color", TRICK_COLOR)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		tag.add_theme_constant_override("outline_size", 4)
		row.add_child(tag)
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


## Team colour; FFA: your own name gold, everyone else the enemy colour.
func _name_color(n: String, team: int) -> Color:
	if Game.is_ffa():
		return Player.SELF_COLOR if n == _local_name() else Player.FFA_COLOR
	return Player.team_color(team)


func _local_name() -> String:
	var p := _local_player()
	if p:
		return p.display_name
	return Game.local_resolved_name()


func _on_hit(killed: bool, headshot: bool) -> void:
	_hit_timer = 0.16 if killed or headshot else 0.085
	_kill_hit = killed
	_head_hit = headshot
	queue_redraw()


func _on_score_changed(_peer_id: int, _score: int, _n: String) -> void:
	if _scoreboard_open:
		_refresh_scoreboard()


func _sort_scores(a: Dictionary, b: Dictionary) -> bool:
	if not Game.is_ffa() and int(a.get("team", 0)) != int(b.get("team", 0)):
		return int(a.team) < int(b.team)
	if a.kills == b.kills:
		return str(a.name) < str(b.name)
	return a.kills > b.kills


func _on_round_ended(winner_peer_id: int, winner_name: String, _scores: Dictionary) -> void:
	_round_end_timer = 5.0
	_round_end_winner = winner_name
	_round_end_peer = winner_peer_id
	round_end_label.text = "%s WINS" % winner_name # kept for anything reading it; the card replaces it on screen
	round_end_label.visible = false
	_show_winner(winner_peer_id, winner_name)
	_show_style_king()
	_scoreboard_open = true
	scoreboard_container.visible = true
	_refresh_scoreboard()


## The final killcam hid the round-end board; show it again for its full time.
func _on_killcam_finished() -> void:
	if _round_end_winner != "":
		_on_round_ended(_round_end_peer, _round_end_winner, {})


func show_intermission() -> void:
	_intermission_timer = 10.0
	intermission_label.text = "INTERMISSION - NEXT ROUND SOON"
	intermission_label.visible = true


## Trickshot by this machine's pawn: big word in the middle, points and combo under it, a sting.
func _on_trick_scored(killer_peer_id: int, tricks: String, points: int, multiplier: float, _total: int) -> void:
	var killer := Game.player_for_peer(killer_peer_id)
	if killer == null or not killer.is_local():
		return
	show_trick(Style.label(Style.unpack(tricks)), points, multiplier)


func show_trick(text: String, points: int, multiplier: float) -> void:
	if _trick == null or text == "":
		return
	_trick_title.text = text + "!"
	# Long combos ("HEADSHOT STREAK + SPRAY TRANSFER + AIRSHOT!") shrink to stay inside the popup.
	var size := clampi(roundi(58.0 * 44.0 / float(maxi(_trick_title.text.length(), 1))), 34, 58)
	_trick_title.add_theme_font_size_override("font_size", size)
	var sub := "+%d STYLE" % points
	if multiplier > 1.001:
		sub += "   x%s COMBO" % String.num(multiplier, 2).trim_suffix("0").trim_suffix(".")
	_trick_sub.text = sub
	if _trick_tween:
		_trick_tween.kill()
	_trick.visible = true
	_trick.modulate.a = 1.0
	_trick.pivot_offset = _trick.size * 0.5
	_trick.scale = Vector2(1.35, 1.35)
	_trick_tween = _trick.create_tween()
	_trick_tween.tween_property(_trick, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_trick_tween.tween_interval(_TRICK_HOLD)
	_trick_tween.tween_property(_trick, "modulate:a", 0.0, _TRICK_FADE)
	_trick_tween.tween_callback(_hide_trick)
	if _trick_sfx:
		_trick_sfx.play()


func trick_text() -> String:
	return _trick_title.text if _trick and _trick.visible else ""


func _hide_trick() -> void:
	if _trick_tween:
		_trick_tween.kill()
		_trick_tween = null
	if _trick:
		_trick.visible = false


func _build_trick_popup() -> void:
	_trick = VBoxContainer.new()
	_trick.name = "TrickPopup"
	_trick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trick.anchor_left = 0.5
	_trick.anchor_right = 0.5
	_trick.anchor_top = 0.5
	_trick.anchor_bottom = 0.5
	_trick.offset_left = -480.0
	_trick.offset_right = 480.0
	_trick.offset_top = -250.0
	_trick.offset_bottom = -140.0
	_trick.alignment = BoxContainer.ALIGNMENT_CENTER
	_trick.add_theme_constant_override("separation", 0)
	_trick.visible = false
	add_child(_trick)
	_trick_title = Label.new()
	_trick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trick_title.add_theme_font_size_override("font_size", 58)
	_trick_title.add_theme_color_override("font_color", TRICK_COLOR)
	_trick_title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0, 0.95))
	_trick_title.add_theme_constant_override("outline_size", 12)
	_trick_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trick.add_child(_trick_title)
	_trick_sub = Label.new()
	_trick_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trick_sub.add_theme_font_size_override("font_size", 22)
	_trick_sub.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	_trick_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_trick_sub.add_theme_constant_override("outline_size", 6)
	_trick_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trick.add_child(_trick_sub)
	_trick_sfx = AudioStreamPlayer.new()
	_trick_sfx.stream = _TRICK_SFX
	_trick_sfx.bus = "UI"
	_trick_sfx.volume_db = -3.0
	add_child(_trick_sfx)


## Round end: a compact card above the scoreboard (never over its header). Small caps line on top,
## the name under it. FFA: gold, or "YOU WIN" for this machine's player. TDM: the team's colour.
func _show_winner(winner_peer_id: int, winner_name: String) -> void:
	if _winner == null:
		_winner = PanelContainer.new()
		_winner.name = "WinnerCard"
		_winner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_winner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_winner.custom_minimum_size = Vector2(340, 0)
		var v := VBoxContainer.new()
		v.name = "V"
		v.add_theme_constant_override("separation", 0)
		_winner.add_child(v)
		for n in ["Kicker", "Name"]:
			var l := Label.new()
			l.name = n
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", 4)
			v.add_child(l)
		(v.get_node("Kicker") as Label).add_theme_font_size_override("font_size", 14)
		(v.get_node("Name") as Label).add_theme_font_size_override("font_size", 30)
		scoreboard_container.add_child(_winner)
		scoreboard_container.move_child(_winner, 0)
	var accent := HUD_ACCENT
	var kicker := "WINNER"
	var title := winner_name.to_upper()
	if not Game.is_ffa():
		accent = Player.team_color(clampi(winner_peer_id, Game.TEAM_A, Game.TEAM_B))
		kicker = "YOUR TEAM WINS" if Game.local_team() == winner_peer_id else "WINNING TEAM"
	elif winner_peer_id != 0 and winner_peer_id == _local_peer_id:
		kicker = "WINNER"
		title = "YOU WIN"
	elif winner_peer_id == 0:
		kicker = "ROUND OVER"
		title = "NO WINNER"
		accent = SB_MUTED
	var sb := _sb_box(SB_BG, 12)
	sb.border_color = accent
	sb.border_width_top = 3
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	_winner.add_theme_stylebox_override("panel", sb)
	var k := _winner.get_node("V/Kicker") as Label
	k.text = kicker
	k.add_theme_color_override("font_color", Color(accent, 0.9) if accent != SB_MUTED else SB_MUTED)
	var nm := _winner.get_node("V/Name") as Label
	nm.text = title
	nm.add_theme_color_override("font_color", accent.lightened(0.15))
	_winner.visible = true


## Round end, under the winner card: who got the most style this round (FFA and TDM alike).
func _show_style_king() -> void:
	var king := Game.style_king()
	if _style_king == null:
		_style_king = Label.new()
		_style_king.name = "StyleKing"
		_style_king.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style_king.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_king.add_theme_font_size_override("font_size", 22)
		_style_king.add_theme_color_override("font_color", TRICK_COLOR)
		_style_king.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_style_king.add_theme_constant_override("outline_size", 6)
		# Lives in the scoreboard, right under the team totals (moved there on every refresh), so it
		# never overlaps the winner line or the rows at any window size.
		scoreboard_container.add_child(_style_king)
	if king.is_empty():
		_style_king.visible = false
		return
	_style_king.text = "STYLE KING  ·  %s  ·  %d style" % [str(king.name), int(king.style)]
	_style_king.visible = true


func style_king_text() -> String:
	return _style_king.text if _style_king and _style_king.visible else ""


## FFA only: "2nd · 7 / 20 kills" (leader 9) under the clock. Team mode hides it.
func _refresh_standing() -> void:
	if _standing == null:
		_standing = Label.new()
		_standing.name = "FfaStanding"
		_standing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_standing.anchor_left = 0.5
		_standing.anchor_right = 0.5
		_standing.offset_left = -220.0
		_standing.offset_right = 220.0
		_standing.offset_top = 46.0
		_standing.offset_bottom = 68.0
		_standing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_standing.add_theme_font_size_override("font_size", 16)
		_standing.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_standing.add_theme_constant_override("outline_size", 5)
		add_child(_standing)
	_standing.visible = Game.is_ffa() and _local_peer_id != 0
	if not _standing.visible:
		return
	var board := Game.get_scores()
	var place := 0
	var mine := 0
	var best := 0
	for i in board.size():
		best = maxi(best, int(board[i].kills))
		if int(board[i].peer_id) == _local_peer_id:
			place = i + 1
			mine = int(board[i].kills)
	if place == 0:
		_standing.text = "FREE FOR ALL"
		return
	var lead := "  ·  leader %d" % best if place > 1 else ("  ·  leading" if mine > 0 else "")
	_standing.text = "%s  ·  %d / %d kills%s" % [_ordinal(place), mine, Game.win_kills(), lead]
	_standing.add_theme_color_override(
		"font_color", Player.SELF_COLOR if place == 1 and mine > 0 else Color(0.92, 0.93, 0.95)
	)


static func _ordinal(n: int) -> String:
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


const SB_BG := Color(0.05, 0.06, 0.08, 0.82)
const SB_ROW_A := Color(1, 1, 1, 0.035)
const SB_ROW_B := Color(1, 1, 1, 0.0)
const SB_ROW_SELF := Color(1.0, 0.84, 0.42, 0.16)
const SB_MUTED := Color(0.62, 0.66, 0.72)
const SB_COLS := [["#", 26], ["NAME", 200], ["K", 48], ["D", 48], ["K/D", 58], ["STYLE", 64], ["PING", 56]]


func _sb_box(col: Color, radius: int = 0, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
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


func _sb_label(text: String, size: int, col: Color, width: int = 0, right: bool = false) -> Label:
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


## Column row (header or player). `values` follows SB_COLS; the name column stays left-aligned.
func _sb_row(values: Array, size: int, col: Color, name_col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for i in SB_COLS.size():
		row.add_child(_sb_label(str(values[i]), size, name_col if i == 1 else col, SB_COLS[i][1], i > 1))
	return row


## One team (or the FFA field): coloured header with name + score, column headers, striped rows.
func _sb_panel(title: String, score_text: String, team_col: Color, rows: Array, ffa: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb_box(Color(0.09, 0.1, 0.13, 0.9), 8, team_col))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var head := HBoxContainer.new()
	var t := _sb_label(title, 20, team_col)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if score_text != "":
		head.add_child(_sb_label(score_text, 26, Color(0.95, 0.95, 0.97), 0, true))
		head.add_child(_sb_label("/ %d" % Game.win_kills(), 15, SB_MUTED, 0, true))
	v.add_child(head)
	if score_text != "":
		# Team progress toward the kill limit, in the team colour.
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		bar.max_value = maxf(float(Game.win_kills()), 1.0)
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
	for c in SB_COLS:
		cols.append(c[0])
	var hdr := PanelContainer.new()
	hdr.add_theme_stylebox_override("panel", _sb_box(Color(1, 1, 1, 0.0)))
	hdr.add_child(_sb_row(cols, 13, SB_MUTED, SB_MUTED))
	v.add_child(hdr)
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(1, 1, 1, 0.12))
	v.add_child(sep)
	var i := 0
	for entry in rows:
		var deaths := int(entry.get("deaths", 0))
		var style_pts := int(entry.get("style", 0))
		var ping_ms := int(entry.get("ping", -1))
		var me: bool = entry.peer_id == _local_peer_id
		var bot: bool = int(entry.peer_id) < 0
		var vals := [
			str(i + 1), str(entry.name), entry.kills, deaths, "%.2f" % (float(entry.kills) / float(maxi(deaths, 1))),
			str(style_pts) if style_pts > 0 else "—", "BOT" if bot else ("—" if ping_ms < 0 else str(ping_ms)),
		]
		var bg := SB_ROW_SELF if me else (SB_ROW_A if i % 2 == 0 else SB_ROW_B)
		var rp := PanelContainer.new()
		var rsb := _sb_box(bg, 6)
		rsb.content_margin_top = 5
		rsb.content_margin_bottom = 5
		if me:
			rsb.border_color = HUD_ACCENT
			rsb.border_width_left = 3
		rp.add_theme_stylebox_override("panel", rsb)
		var row := _sb_row(vals, 17, Color(0.88, 0.9, 0.93), Color(1.0, 0.9, 0.55) if me else Color(0.95, 0.95, 0.97))
		var rank := row.get_child(0) as Label
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rank.add_theme_font_size_override("font_size", 14)
		rank.add_theme_color_override("font_color", HUD_ACCENT if (i == 0 and ffa) else SB_MUTED)
		(row.get_child(2) as Label).add_theme_color_override("font_color", Color(1, 1, 1))
		(row.get_child(3) as Label).add_theme_color_override("font_color", SB_MUTED)
		var ping_l := row.get_child(6) as Label
		ping_l.add_theme_font_size_override("font_size", 14)
		if bot or ping_ms < 0:
			ping_l.add_theme_color_override("font_color", Color(SB_MUTED, 0.7))
		else:
			ping_l.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55) if ping_ms < 60 else (Color(0.95, 0.8, 0.35) if ping_ms < 120 else Color(0.95, 0.45, 0.4)))
		if style_pts > 0:
			(row.get_child(5) as Label).add_theme_color_override("font_color", TRICK_COLOR)
		rp.add_child(row)
		v.add_child(rp)
		i += 1
	if rows.is_empty():
		v.add_child(_sb_label("No players", 15, SB_MUTED))
	return panel


## Mode · map on the left, goal and clock on the right, gold rule under it (#66).
func _sb_header(ffa: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var h := HBoxContainer.new()
	var left := _sb_label("%s  ·  %s" % [Game.mode_name().to_upper(), Maps.display_name(Game.map_id).to_upper()], 16, Color(0.95, 0.95, 0.97))
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var t := int(ceil(Game.get_round_time_left()))
	var goal := "first to %d" % Game.win_kills() if ffa else "%d kills wins" % Game.win_kills()
	h.add_child(_sb_label("%s  ·  %d:%02d" % [goal, t / 60, t % 60], 15, SB_MUTED, 0, true))
	v.add_child(h)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = Color(HUD_ACCENT, 0.55)
	v.add_child(rule)
	return v


func _refresh_scoreboard() -> void:
	for c in scoreboard_container.get_children():
		if c != _style_king and c != _winner:
			c.queue_free()
	_scores = Game.get_scores()
	_scores.sort_custom(_sort_scores)
	var ffa := Game.is_ffa()

	var backdrop := PanelContainer.new()
	var bsb := _sb_box(SB_BG, 12)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bsb.content_margin_top = 14
	bsb.content_margin_bottom = 16
	backdrop.add_theme_stylebox_override("panel", bsb)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	backdrop.add_child(body)
	body.add_child(_sb_header(ffa))
	if ffa:
		body.add_child(_sb_panel("PLAYERS  ·  %d" % _scores.size(), "", Color(0.9, 0.9, 0.92), _scores, true))
	else:
		var teams := HBoxContainer.new()
		teams.add_theme_constant_override("separation", 14)
		for team_id in [Game.TEAM_A, Game.TEAM_B]:
			var rows := _scores.filter(func(e: Dictionary) -> bool: return int(e.get("team", 0)) == team_id)
			teams.add_child(_sb_panel(
				Game.TEAM_NAMES[team_id], str(Game.get_team_kills(team_id)), Player.team_color(team_id), rows, false
			))
		body.add_child(teams)
	scoreboard_container.add_child(backdrop)
	if _style_king:
		scoreboard_container.move_child(_style_king, backdrop.get_index())
	if _winner:
		scoreboard_container.move_child(_winner, 0)


func _process(delta: float) -> void:
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_fire_punch = move_toward(_fire_punch, 0.0, delta * 9.0)
	if _hint_timer > 0.0:
		_hint_timer -= delta
		hint_label.modulate.a = clampf(_hint_timer, 0.0, 1.0)
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	for i in range(_dmg_dirs.size() - 1, -1, -1):
		_dmg_dirs[i].t = float(_dmg_dirs[i].t) - delta
		if float(_dmg_dirs[i].t) <= 0.0:
			_dmg_dirs.remove_at(i)
	_standing_t -= delta
	if _standing_t <= 0.0:
		_standing_t = 0.25
		_refresh_standing()
	fps_label.visible = Game.show_fps
	fps_label.text = "%d fps" % roundi(Engine.get_frames_per_second())
	
	var time_left: float = Game.get_round_time_left()
	var mins: int = int(time_left / 60)
	var secs: int = int(time_left) % 60
	timer_label.text = "%d:%02d" % [mins, secs]
	timer_label.visible = Game._round_active
	if _radar_left > 0.0:
		_radar_left = maxf(_radar_left - delta, 0.0)
		if _radar_left <= 0.0:
			_refresh_streak_ui()
	if _freeze_left > 0.0:
		_freeze_left = maxf(_freeze_left - delta, 0.0)
		if countdown_label:
			var n := ceili(_freeze_left)
			countdown_label.text = str(n) if n > 0 else "GO"
			if _freeze_left <= 0.0:
				countdown_label.visible = false

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
			if _style_king:
				_style_king.visible = false
			if _winner:
				_winner.visible = false
			if not tab_pressed:
				_scoreboard_open = false
				scoreboard_container.visible = false
	
	if _intermission_timer > 0.0:
		_intermission_timer -= delta
		if _intermission_timer <= 0.0:
			intermission_label.visible = false
	
	queue_redraw()


## Crosshair gap grows with spread/punch. The sniper draws none until RMB zoom.
## Hurt vignette, damage wedges, and hit markers stay up either way.
func _draw() -> void:
	var c := size * 0.5
	var stance := 0.0
	var player := _player if is_instance_valid(_player) else null
	if player:
		stance = maxf(player.spread_multiplier() - 1.0, 0.0) * 5.0
	var sz := Game.crosshair_size
	var gap := ((2.0 if _sniper_ads else 5.0) + _fire_punch * 7.0 + stance) * sz
	var length := 8.0 * sz
	var col := Game.crosshair_rgb()
	col.a = 0.92
	var thick := maxf(2.0 * sqrt(sz), 1.0)
	var style := Game.crosshair_style # 0 cross+dot, 1 cross, 2 dot, 3 circle
	# Hip-firing the sniper is unguided. Zoom (and every other gun) keeps the bars.
	if not _sniper_hip:
		if style <= 1:
			_bar(c + Vector2(gap, 0), Vector2(length, 0), col, thick)
			_bar(c + Vector2(-gap, 0), Vector2(-length, 0), col, thick)
			_bar(c + Vector2(0, gap), Vector2(0, length), col, thick)
			_bar(c + Vector2(0, -gap), Vector2(0, -length), col, thick)
		elif style == 3:
			draw_arc(c, gap + length * 0.5, 0.0, TAU, 40, col, thick, true)
		if style != 1:
			draw_circle(c, (2.2 if style == 2 else 1.4) * sz, col)
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

	_draw_damage_dirs(c)

	if _hit_timer > 0.0:
		var hit_a := clampf(_hit_timer / 0.08, 0.0, 1.0)
		var hit_col := Color(1, 1, 1, hit_a)
		if _kill_hit:
			hit_col = Color(1.0, 0.22, 0.18, hit_a)
		elif _head_hit:
			hit_col = Color(1.0, 0.86, 0.2, hit_a)
		var s := 11.0 if _kill_hit or _head_hit else 8.0
		draw_line(c + Vector2(-s, -s), c + Vector2(-s * 0.35, -s * 0.35), hit_col, 2.2, true)
		draw_line(c + Vector2(s, -s), c + Vector2(s * 0.35, -s * 0.35), hit_col, 2.2, true)
		draw_line(c + Vector2(-s, s), c + Vector2(-s * 0.35, s * 0.35), hit_col, 2.2, true)
		draw_line(c + Vector2(s, s), c + Vector2(s * 0.35, s * 0.35), hit_col, 2.2, true)


func _bar(from: Vector2, delta: Vector2, col: Color, thick: float) -> void:
	draw_line(from, from + delta, col, thick, true)
