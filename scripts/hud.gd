class_name Hud
extends Control
## Crosshair, bottom HP bar + weapon slots, Tab scoreboard, kill feed. Mouse-filter ignore.

var _hit_timer := 0.0
var _perf := PerfOverlay.new()
var _chat: HudChat
var _kill_hit := false
var _head_hit := false
var _fire_punch := 0.0
var pickup_toast: Label
var _pickup_toast_t := 0.0
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
## Notice line and streak/flag popup: scripts/hud/notice_layer.gd.
var _notice_layer: HudNotice
var _sniper_ads := false
var _sniper_hip := false # sniper in hand and RMB zoom off: draw no crosshair
var _player: Player # the local pawn from bind_player; crosshair bloom follows it
var _dmg_dirs: Array[Dictionary] = [] # {pos: Vector3, t: float}: where recent damage came from
var _standing: Label # FFA: your place and kills under the clock
var _standing_t := 0.0

## Geometry and palette: shared/hud_layout.gd (one source; check_hud_column compares the scene with it).
const DMG_DIR_LIFE := HudLayout.DMG_LIFE
const DMG_DIR_MAX := HudLayout.DMG_MAX
const DMG_DIR_RADIUS := HudLayout.DMG_RADIUS
const DMG_DIR_HALF := HudLayout.DMG_HALF
const _SLOT_IDLE := HudLayout.SLOT_IDLE
const _SLOT_ON := HudLayout.SLOT_ON
const HUD_ACCENT := HudLayout.ACCENT
const HUD_PANEL := HudLayout.PANEL
## HP fill: ice when healthy, amber in the middle, red when low. The track is smoke glass.
const HP_OK := Color(0.78, 0.93, 1.0, 0.95)
const HP_MID := Color(0.95, 0.72, 0.25, 0.95)
const HP_LOW := Color(0.92, 0.2, 0.16, 0.96)
## The weapon slots + grenade pill and the scorestreak column: scripts/hud/weapon_bar.gd and
## streak_column.gd. Their nodes stay in hud.tscn; these hold what happens to them.
var weapons: WeaponBar
var streaks: StreakColumn

@onready var fps_label: Label = $Fps
@onready var reload_label: Label = $Bottom/Reloading
@onready var hp_fill: ColorRect = $Bottom/HpWrap/HpFill
@onready var hp_label: Label = $Bottom/HpWrap/HpLabel
@onready var armour_bg: ColorRect = $Bottom/HpWrap/ArmourBg
@onready var armour_fill: ColorRect = $Bottom/HpWrap/ArmourFill
@onready var death_layer: ColorRect = $Death
@onready var _slots: Array[ColorRect] = [
	$Bottom/Weapons/Slot0,
	$Bottom/Weapons/Slot1,
	$Bottom/Weapons/Slot2,
	$Bottom/Weapons/Slot3,
]
@onready var scoreboard_container: VBoxContainer = $Scoreboard
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
@onready var kill_feed: KillFeed = $KillFeed
@onready var presence_feed: VBoxContainer = $PresenceFeed
@onready var chat_log: VBoxContainer = $ChatLog
@onready var chat_input: LineEdit = $ChatInput

const _FEED_ICONS := KillFeed.ICONS # killcam and checks read it here
const _POPUP_FRIENDLY := HudLayout.POPUP_FRIENDLY
const POPUP_TOP := HudLayout.POPUP_TOP
const POPUP_HEIGHT := HudLayout.POPUP_HEIGHT
const CTF_STATUS_TOP := HudLayout.CTF_TOP
const CTF_STATUS_H := HudLayout.CTF_HEIGHT
const _POPUP_HOSTILE := HudLayout.POPUP_HOSTILE
const TRICK_COLOR := HudLayout.TRICK
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



func _ready() -> void:
	add_to_group("hud")
	Game.hit_confirmed.connect(_on_hit)
	Game.score_changed.connect(_on_score_changed)
	Game.round_ended.connect(_on_round_ended)
	Game.kill_feed.connect(_on_kill_feed)
	Game.flag_event.connect(_on_flag_event)
	if kill_feed:
		kill_feed.name_color = _name_color
		kill_feed.local_name = _local_name
	Game.trick_scored.connect(_on_trick_scored)
	Game.combo_changed.connect(_on_combo_changed)
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
	intermission_label.visible = false
	if countdown_label:
		countdown_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapons = WeaponBar.new(_slots, grenade_label)
	streaks = StreakColumn.new(self, streak_label, _streak_slots)
	_style_bottom()
	_facelift_hud()
	weapons.refresh()
	streaks.build()
	_notice_layer = HudNotice.new()
	_notice_layer.name = "NoticeLayer"
	add_child(_notice_layer)
	_notice_layer.setup(get_node_or_null("Bottom") as VBoxContainer, self)
	_build_trick_popup()
	_chat = HudChat.new(chat_log, chat_input, presence_feed, _name_color)
	call_deferred("bind_player", null)


func _apply_hud_settings() -> void:
	var mm := get_node_or_null("Minimap") as Control
	if mm:
		mm.visible = Game.show_minimap
	if kill_feed:
		kill_feed.visible = Game.show_killfeed
	if fps_label:
		fps_label.visible = Game.show_fps
		fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	queue_redraw()


## Perf overlay text: scripts/hud/perf_overlay.gd.
func _perf_text() -> String:
	return _perf.text(get_viewport(), get_process_delta_time())


## The GPU time of the last frame (0 when the driver does not report it): PerfOverlay.gpu_ms.
func _gpu_ms() -> float:
	return _perf.gpu_ms(get_viewport())


## Which side is behind ("vsync", "gpu" or "cpu"): PerfOverlay.hint, kept here for its check.
static func perf_hint(frame_ms: float, cpu_ms: float, gpu_ms: float, refresh_hz: float, vsync: bool) -> String:
	return PerfOverlay.hint(frame_ms, cpu_ms, gpu_ms, refresh_hz, vsync)


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
	if not player.armour_changed.is_connected(_on_armour):
		player.armour_changed.connect(_on_armour)
	_on_armour(player.armour)
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
	# Driving the car or the hands: that camera has the mouse and LMB. Streak keys and chat wait.
	if Game.rc_view or Game.los_view:
		# LOS: the same key that fired the streak brings the hands back early, without a snap.
		if Game.los_view and event.is_action_pressed("use_streak"):
			LosHands.recall_local()
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
			streaks.select(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_down"):
			streaks.select(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("use_streak"):
			Game.request_use_streak(streaks.sel)
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


## Chat and the presence feed: scripts/hud/hud_chat.gd. These names stay for the HUD's own callers.
func _open_chat() -> void:
	_chat.open()


func _close_chat(send: bool) -> void:
	_chat.close(send)


func _on_chat_message(n: String, team: int, text: String) -> void:
	_chat.add_message(n, team, text)


func _bb_escape(s: String) -> String:
	return HudChat.bb_escape(s)


## Leave to menu: drop streak/radar/death overlay from the old session.
func reset_session() -> void:
	if combo_meter:
		combo_meter.reset()
	_player = null
	_local_peer_id = 0
	_dmg_dirs.clear()
	streaks.reset()
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
	if _winner:
		_winner.visible = false
	intermission_label.visible = false
	if countdown_label:
		countdown_label.visible = false


## Freeze is the round start: show the countdown (the build-up music starts in Game).
func _on_round_freeze(on: bool) -> void:
	_freeze_left = Game.FREEZE_TIME if on else 0.0
	if countdown_label:
		countdown_label.visible = on
		if on:
			countdown_label.text = str(ceili(_freeze_left))


func punch_crosshair(amount: float = 1.0) -> void:
	_fire_punch = maxf(_fire_punch, amount)


## Weapon slots: WeaponBar (scripts/hud/weapon_bar.gd).
func set_ammo(current: int, mag: int) -> void:
	weapons.set_ammo(current, mag)


## The class decides the guns: one box per carried gun, keys 1..n in that order.
func set_weapon_slots(names: PackedStringArray) -> void:
	weapons.set_names(names)


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
	weapons.set_index(index)


## Bottom HUD: crystal HP bar (smoke track + fill), grenade/knife shard, outlined streak counter.
func _style_bottom() -> void:
	var bg := get_node_or_null("Bottom/HpWrap/HpBg") as ColorRect
	if bg:
		bg.color = CrystalStyle.SMOKE
		_skin(bg, 8)
		_paint(bg, CrystalStyle.SMOKE)
	if hp_fill:
		_skin(hp_fill, 8)
		_paint(hp_fill, HP_OK)
		(hp_fill.get_node("Skin").get_theme_stylebox("panel") as CrystalStyle).edge_alpha = 0.0
	weapons.style_grenades()
	if streak_label:
		streak_label.add_theme_font_size_override("font_size", 14)


## The crystal skin behind a ColorRect (HP bar, slots): HudSkin (scripts/hud/hud_skin.gd).
func _skin(rect: ColorRect, radius: int = 8) -> void:
	HudSkin.skin(rect, radius)


## `top` is unused since the crystal restyle; kept so old callers read the same.
func _paint(rect: ColorRect, bg: Color, accent: Color = Color(0, 0, 0, 0), _top: int = 0, pale := false) -> void:
	HudSkin.paint(rect, bg, accent, pale)


## Scorestreaks: StreakColumn (scripts/hud/streak_column.gd). Only the owner gets set_streak.
func set_streak(n: int, charges: int, earned: int) -> void:
	streaks.set_streak(n, charges, earned)


## Team radar switched on. Your team, including the player who turned it on, hears
## "Friendly radar online" and gets the markers. The other team hears "Enemy radar online".
## Popups stay gold for your team and red for the other.
func show_radar_event(by_name: String, team: int, friendly: bool) -> void:
	if friendly:
		streaks.radar_started()
		_play_radar_voice("friendly")
		show_popup("UAV", _POPUP_FRIENDLY, by_name, team)
	else:
		_play_radar_voice("enemy")
		show_popup("ENEMY UAV", _POPUP_HOSTILE, by_name, team)


## RC-XD switched on. Own team (and you) get the plain title and "Friendly RC-XD deployed"; the other
## team (in FFA everyone else) the enemy title and "Enemy RC-XD inbound". Voice on the radar cooldown.
func show_rc_event(by_name: String, team: int, friendly: bool) -> void:
	if friendly:
		_play_radar_voice("rcxd_friendly")
		show_popup(Game.RCXD_DISPLAY_NAME.to_upper(), _POPUP_FRIENDLY, by_name, team)
	else:
		_play_radar_voice("rcxd_enemy")
		show_popup("ENEMY " + Game.RCXD_DISPLAY_NAME.to_upper(), _POPUP_HOSTILE, by_name, team)


## While the local camera is in the car. `on` false hides the line.
func set_rc_drive(on: bool, hp: float, life: float) -> void:
	streaks.set_rc_drive(on, hp, life)


func clear_radar() -> void:
	streaks.clear_radar()


## Top centre, under the round clock: what was switched on, and by whom (name in team colour).
## #160: popup for a flag event, gold when it is good for your team, red when not.
func _on_flag_event(kind: String, team: int, by_name: String) -> void:
	var good := CtfStatus.is_good(kind, team, Game.local_team())
	show_popup(CtfStatus.popup_title(kind, team), _POPUP_FRIENDLY if good else _POPUP_HOSTILE, by_name, CtfStatus.actor_team(kind, team))
	_standing_t = 0.0


## LOS came on. Gold, same family as a friendly radar. The box going gold is the unlock; no voice line.
func show_los(line: String, team: int) -> void:
	show_popup("LOS", _POPUP_FRIENDLY, line, team)


func show_popup(title: String, title_col: Color, by_name: String, team: int) -> void:
	if _notice_layer == null:
		return
	# The layer renders; the colours and the escaped name are this side's job (team/FFA knowledge).
	var col: Color = _name_color(by_name, team)
	var by := "[center][color=#d8dade]by[/color] [color=#%s]%s[/color][/center]" % [
		col.to_html(false), _bb_escape(by_name)
	]
	_notice_layer.show_popup(title, title_col, by, _popup_top())


func _hide_popup() -> void:
	if _notice_layer:
		_notice_layer.hide_popup()


## The streak/flag popup's Control, so a check can read where it sits (tools/check_ctf, check_hud_layout).
func popup_control() -> Control:
	return _notice_layer.popup_box() if _notice_layer else null


## Small line above the weapon boxes ("Class changes at next spawn"). Fades by itself.
func show_notice(text: String, seconds: float = 3.0) -> void:
	if _notice_layer == null:
		return
	_notice_layer.show_notice(text, seconds)


func notice_text() -> String:
	return _notice_layer.notice_text() if _notice_layer else ""


func _hide_notice() -> void:
	if _notice_layer:
		_notice_layer.hide_notice()


func _refresh_streak_ui() -> void:
	streaks.refresh()


func _play_radar_voice(kind: String) -> void:
	streaks.play_radar_voice(kind)


## Grenade slot: frags on G, throwing knives on F (only shown when the class carries knives).
## Sits at the right end of the HP row (#65); the key letter is dimmer than the count.
func set_grenades(n: int, knives: int = 0) -> void:
	weapons.set_grenades(n, knives)


## #65: one HP row (bar + grenade/knife pill), even weapon slots, a scorestreak column with
## kill pips and cost/ready tags. The key hint line at the top (over the clock) is gone;
## the keys are in Settings > Controls.
func _facelift_hud() -> void:
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
		# Speed meter (crystal step 4): the row right above HP, so the transient notice and
		# RELOAD rows come and go above it without moving it.
		speed_meter = SpeedMeter.new()
		speed_meter.visible = false
		bottom.add_child(speed_meter)
		bottom.move_child(speed_meter, row.get_index())
	if hp_label:
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hp_label.offset_left = 12.0
		hp_label.add_theme_font_size_override("font_size", 17)
		hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		hp_label.add_theme_constant_override("outline_size", 4)


func set_reloading(on: bool) -> void:
	reload_label.visible = on


## Schildplaat (#144): a thin bar above the HP bar, hidden when there is no armour.
func _on_armour(a: float) -> void:
	var on := a > 0.5
	if armour_bg:
		armour_bg.visible = on
	if armour_fill:
		armour_fill.visible = on
		armour_fill.anchor_right = clampf(a / maxf(Pickups.ARMOUR, 1.0), 0.0, 1.0)
	if on:
		_sound_pickup_hint("+%d ARMOUR" % roundi(a), Pickups.type_info(&"shield")["color"])


## Pickup taken: a short label in the pickup's colour above the HP bar (#144).
func flash_pickup(label: String, col: Color) -> void:
	_sound_pickup_hint(label, col)


## Extra Messen taken: the knife counter blinks so the new count is noticed (#144).
func blink_knives() -> void:
	if grenade_label == null:
		return
	var tw := create_tween()
	tw.tween_property(grenade_label, "modulate", Color(1.6, 1.6, 1.6, 1), 0.08)
	tw.tween_property(grenade_label, "modulate", Color.WHITE, 0.35)


func _sound_pickup_hint(text: String, col: Color) -> void:
	if pickup_toast == null:
		pickup_toast = Label.new()
		pickup_toast.name = "PickupToast"
		$Bottom.add_child(pickup_toast)
		pickup_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pickup_toast.anchor_left = 0.0
		pickup_toast.anchor_right = 1.0
		pickup_toast.offset_top = -46.0
		pickup_toast.offset_bottom = -18.0
		pickup_toast.add_theme_font_size_override("font_size", 20)
		pickup_toast.add_theme_constant_override("outline_size", 6)
		pickup_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	pickup_toast.text = text
	pickup_toast.add_theme_color_override("font_color", col)
	pickup_toast.modulate.a = 1.0
	_pickup_toast_t = 2.0


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
		var fill := HP_LOW if t < 0.3 else HP_OK
		if t >= 0.3 and t < 0.6:
			fill = HP_MID
		_paint(hp_fill, fill)


## #64 "Killed by X" card: scripts/hud/death_report.gd, made on the first death.
var _death_report: DeathReport


func show_death_report(killer: String, taken: int, taken_hits: int, dealt: int, dealt_hits: int, killer_hp: int, weapon: String = "") -> void:
	if _death_report == null:
		_death_report = DeathReport.new()
		add_child(_death_report)
	_death_report.show_report(killer, taken, taken_hits, dealt, dealt_hits, killer_hp, weapon)


func _on_died() -> void:
	death_layer.visible = true


func _on_respawned() -> void:
	death_layer.visible = false
	_hurt_flash = 0.0
	_dmg_dirs.clear()


func _on_presence(player_name: String, joined: bool, team: int) -> void:
	_chat.add_presence(player_name, joined, team)


func _on_kill_feed(
	killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int,
	tricks: String = ""
) -> void:
	if kill_feed:
		kill_feed.add_kill(killer_name, victim_name, weapon_id, killer_team, victim_team, tricks)


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
	var key := Game.score_word()
	if int(a.get(key, 0)) == int(b.get(key, 0)):
		if key == "style" and a.kills != b.kills:
			return a.kills > b.kills
		return str(a.name) < str(b.name)
	return int(a.get(key, 0)) > int(b.get(key, 0))


func _on_round_ended(winner_peer_id: int, winner_name: String, _scores: Dictionary) -> void:
	_round_end_timer = 5.0
	_round_end_winner = winner_name
	_round_end_peer = winner_peer_id
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


## Round end: a compact shard above the scoreboard (never over its header). Small caps line on top,
## the name under it, the seam under both in the accent. FFA: ice; "YOU WIN" for this machine's
## player is pale shell. TDM: the team's colour. No winner: no seam.
func _show_winner(winner_peer_id: int, winner_name: String) -> void:
	if _winner == null:
		_winner = PanelContainer.new()
		_winner.name = "WinnerCard"
		_winner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_winner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_winner.custom_minimum_size = Vector2(340, 0)
		var v := VBoxContainer.new()
		v.name = "V"
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 0)
		_winner.add_child(v)
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
		scoreboard_container.add_child(_winner)
		scoreboard_container.move_child(_winner, 0)
	var accent := HUD_ACCENT
	var kicker := "WINNER"
	var title := winner_name.to_upper()
	var pale := false
	if not Game.is_ffa():
		accent = Player.team_color(clampi(winner_peer_id, Game.TEAM_A, Game.TEAM_B))
		kicker = "YOUR TEAM WINS" if Game.local_team() == winner_peer_id else "WINNING TEAM"
		if Game.is_style_mode():
			kicker += "  ·  %d STYLE" % Game.team_score(clampi(winner_peer_id, Game.TEAM_A, Game.TEAM_B))
	elif winner_peer_id != 0 and winner_peer_id == _local_peer_id:
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
	_winner.add_theme_stylebox_override("panel", sb)
	var k := _winner.get_node("V/Kicker") as Label
	k.text = kicker
	k.add_theme_color_override("font_color", Color(ScoreboardView.DARK, 0.6) if pale else (accent.lightened(0.2) if accent.a > 0.0 else CrystalUi.MUTE))
	var nm := _winner.get_node("V/Name") as Label
	nm.text = title
	nm.add_theme_color_override("font_color", ScoreboardView.DARK if pale else ScoreboardView.TEXT)
	_winner.visible = true


## Round end, under the winner card: who got the most style this round (FFA and TDM alike). A slim
## shard with a gold seam: gold is for trick rewards, and this is the round's biggest one.
func _show_style_king() -> void:
	var king := Game.style_king()
	if _style_king == null:
		_style_king = CrystalUi.caption("", 14, TRICK_COLOR)
		_style_king.name = "StyleKing"
		_style_king.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_style_king.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var sb := CrystalUi.shard(Vector4(8, 3, 10, 4), 31, false, CrystalStyle.Side.BOTTOM, TRICK_COLOR, 1.0, Vector2(22, 6))
		sb.fill = ScoreboardView.PANEL
		_style_king.add_theme_stylebox_override("normal", sb)
		# Lives in the scoreboard, right under the team totals (moved there on every refresh), so it
		# never overlaps the winner line or the rows at any window size.
		scoreboard_container.add_child(_style_king)
	if king.is_empty():
		_style_king.visible = false
		return
	_style_king.text = "STYLE KING  ·  %s  ·  %d STYLE" % [str(king.name).to_upper(), int(king.style)]
	_style_king.visible = true


func style_king_text() -> String:
	return _style_king.text if _style_king and _style_king.visible else ""


## FFA: "2nd · 7 / 20 kills" (leader 9) under the clock; CTF: captures and flags. Other team modes hide it.
func _refresh_standing() -> void:
	if _standing == null:
		_standing = Label.new()
		_standing.name = "FfaStanding"
		_standing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_standing.anchor_left = 0.5
		_standing.anchor_right = 0.5
		_standing.offset_left = -220.0
		_standing.offset_right = 220.0
		_standing.offset_top = HudLayout.STANDING_TOP
		_standing.offset_bottom = HudLayout.STANDING_BOTTOM
		_standing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_standing.add_theme_font_size_override("font_size", HudLayout.STANDING_FONT)
		_standing.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_standing.add_theme_constant_override("outline_size", 5)
		add_child(_standing)
	_standing.visible = (Game.is_ffa() or Game.is_ctf()) and _local_peer_id != 0
	if not _standing.visible:
		return
	_place_standing()
	if Game.is_ctf(): # #160: captures and both flags instead of the FFA place
		_standing.text = CtfStatus.line(Game, _local_peer_id)
		_standing.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
		return
	var board := Game.get_scores()
	var place := 0
	var mine := 0
	var best := 0
	for i in board.size():
		var sc := int(board[i].get(Game.score_word(), 0))
		best = maxi(best, sc)
		if int(board[i].peer_id) == _local_peer_id:
			place = i + 1
			mine = sc
	if place == 0:
		_standing.text = "FREE FOR ALL"
		return
	var lead := "  ·  leader %d" % best if place > 1 else ("  ·  leading" if mine > 0 else "")
	_standing.text = "%s  ·  %d / %d %s%s" % [_ordinal(place), mine, Game.score_limit(), Game.score_word(), lead]
	if Game.is_gun_game():
		_standing.text += "  ·  " + GunGame.hud_line(GunGame.level_of(Game, _local_peer_id)) # #148
	_standing.add_theme_color_override(
		"font_color", Player.SELF_COLOR if place == 1 and mine > 0 else Color(0.92, 0.93, 0.95)
	)


## FFA: one line right under the clock. CTF: three lines with a clear gap below the clock; the
## streak/flag popup then moves under them (see _popup_top), so the two never overlap.
func _place_standing() -> void:
	var ctf := Game.is_ctf()
	_standing.offset_top = HudLayout.CTF_TOP if ctf else HudLayout.STANDING_TOP
	_standing.offset_bottom = _standing.offset_top + (HudLayout.CTF_HEIGHT if ctf else HudLayout.STANDING_HEIGHT)
	_standing.add_theme_font_size_override("font_size", HudLayout.CTF_LINE_FONT if ctf else HudLayout.STANDING_FONT)


## Top of the streak/flag popup: under the CTF status block in CTF, the usual spot otherwise.
static func _popup_top() -> float:
	return HudLayout.CTF_TOP + HudLayout.CTF_HEIGHT + HudLayout.POPUP_GAP if Game.is_ctf() else POPUP_TOP


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


const SB_MUTED := ScoreboardView.MUTED


## Scoreboard building lives in ScoreboardView (scripts/hud/scoreboard_view.gd).
func _refresh_scoreboard() -> void:
	for c in scoreboard_container.get_children():
		if c != _style_king and c != _winner:
			c.queue_free()
	_scores = Game.get_scores()
	_scores.sort_custom(_sort_scores)
	var ffa := Game.is_ffa()

	var backdrop := ScoreboardView.build(_scores, ffa, _local_peer_id)
	scoreboard_container.add_child(backdrop)
	if _style_king:
		scoreboard_container.move_child(_style_king, backdrop.get_index())
	if _winner:
		scoreboard_container.move_child(_winner, 0)


func _process(delta: float) -> void:
	_tick_combo_ui(delta)
	_tick_speed_meter(delta)
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_fire_punch = move_toward(_fire_punch, 0.0, delta * 9.0)
	if _pickup_toast_t > 0.0:
		_pickup_toast_t = maxf(_pickup_toast_t - delta, 0.0)
		if pickup_toast:
			pickup_toast.modulate.a = clampf(_pickup_toast_t / 0.6, 0.0, 1.0)
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
	if Game.show_fps:
		fps_label.text = _perf_text()
	
	var time_left: float = Game.get_round_time_left()
	var mins: int = int(time_left / 60)
	var secs: int = int(time_left) % 60
	timer_label.text = "%d:%02d" % [mins, secs]
	timer_label.visible = Game._round_active
	streaks.tick(delta)
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

	# LOS: one thin bar under the crosshair draining with the hands' time left. Local only and
	# drawn here, so it needs no node of its own. Gold, the streak family colour.
	var hands := LosHands.local()
	if hands:
		var frac := clampf(hands.time_left / LosHands.DURATION, 0.0, 1.0)
		var bar_w := 96.0
		var bar_y := c.y + 34.0
		draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w, 4.0), Color(1, 1, 1, 0.16))
		draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w * frac, 4.0), Color(1, 0.92, 0.55, 0.95))

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


# ---------------------------------------------------------------------------------------------
# #84 combo meter: scripts/hud/combo_meter.gd. Built on the first combo event (same child order as before).

var combo_meter: ComboMeter
const COMBO_GAP := 8.0 # px between the combo meter and the top of the bottom stack
## Speed meter: scripts/hud/speed_meter.gd, a row of the bottom stack (built in _facelift_hud).
var speed_meter: SpeedMeter
var combo_sfx_log: Array = [] # [kind, pitch] for the headless check (shared with combo_meter.sfx_log)


func _on_combo_changed(points: int, multiplier: float, time_left: float, moves: String, state: String, banked: int) -> void:
	if combo_meter == null:
		combo_meter = ComboMeter.new()
		combo_meter.sfx_log = combo_sfx_log
		add_child(combo_meter)
	combo_meter.on_combo_changed(points, multiplier, time_left, moves, state, banked)


func _tick_combo_ui(delta: float) -> void:
	if combo_meter:
		combo_meter.tick(delta)
		_place_combo()


## The combo sits at 66 % of the screen, but never on the bottom stack: at 720p the stack (notice,
## RELOAD, speed, HP, weapons) reaches above that line, so the combo is pushed up to clear it.
func _place_combo() -> void:
	var bottom := get_node_or_null("Bottom") as Control
	if combo_meter == null or bottom == null or not combo_meter.visible:
		return
	var limit := bottom.position.y - COMBO_GAP - combo_meter.size.y
	var anchor_y := size.y * combo_meter.anchor_top
	var top := minf(anchor_y, limit) - anchor_y
	if not is_equal_approx(combo_meter.offset_top, top):
		combo_meter.offset_top = top
		combo_meter.offset_bottom = top


## Local live pawn only: hidden without one, while dead and during the final killcam.
func _tick_speed_meter(delta: float) -> void:
	if speed_meter == null:
		return
	var p := _player if is_instance_valid(_player) else null
	var on := p != null and not death_layer.visible and not Game.killcam_active
	if speed_meter.visible != on:
		speed_meter.visible = on
	if on:
		speed_meter.show_speed(SpeedMeter.flat_speed(p.velocity), SpeedMeter.state_of(p), delta)
