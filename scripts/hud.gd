class_name Hud
extends Control
## The in-match HUD. It owns the scene's nodes, hooks them to Game and the local pawn, and handles
## the keys (chat, streak selection); each piece's behaviour lives in scripts/hud/ (#315): HudOverlay
## (crosshair, hit markers, damage wedges), HudVitals (HP, armour, pickups), WeaponBar, StreakColumn,
## HudBoard + ScoreboardView, TrickPopup, StandingLine, HudNotice, ComboMeter, SpeedMeter, KillFeed,
## DeathReport, HudChat and PerfOverlay. The old function names stay here as thin wrappers.

var _perf := PerfOverlay.new()
var _chat: HudChat
var _local_peer_id := 0
var _intermission_timer := 0.0
var _freeze_left := 0.0
## Notice line and streak/flag popup: scripts/hud/notice_layer.gd.
var _overdrive_label: Label # #388: the Overdrive countdown
var _notice_layer: HudNotice
var _player: Player # the local pawn from bind_player; crosshair bloom follows it
var _standing: StandingLine # FFA place / CTF flags under the clock, made on the first refresh
var _standing_t := 0.0

## Geometry and palette: shared/hud_layout.gd (one source; check_hud_column compares the scene with it).
const HUD_ACCENT := HudLayout.ACCENT
## HP fill: ice when healthy, amber in the middle, red when low. The track is smoke glass.
const HP_OK := HudVitals.HP_OK
const HP_MID := HudVitals.HP_MID
const HP_LOW := HudVitals.HP_LOW
## The crosshair layer (HudOverlay: crosshair, hit markers, damage wedges, hurt vignette, LOS bar) and
## HP / armour / pickups (HudVitals): scripts/hud/.
var overlay: HudOverlay
var vitals: HudVitals
## The pickup toast lives in HudVitals; this name stays for its callers.
var pickup_toast: Label:
	get:
		return vitals.toast if vitals else null
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
const _POPUP_HOSTILE := HudLayout.POPUP_HOSTILE
const TRICK_COLOR := HudLayout.TRICK
## Trick popup (TrickPopup), the Tab board and round-end cards (HudBoard): scripts/hud/.
var trick: TrickPopup
var board: HudBoard


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
	fps_label.visible = Game.perf_label_visible()
	Game.hud_settings_changed.connect(_apply_hud_settings)
	_apply_hud_settings()
	death_layer.visible = false
	board = HudBoard.new(scoreboard_container)
	intermission_label.visible = false
	if countdown_label:
		countdown_label.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = HudOverlay.new()
	add_child(overlay)
	move_child(overlay, 0) # under every other HUD node, where Hud._draw used to draw
	vitals = HudVitals.new($Bottom, get_node_or_null("Bottom/HpWrap/HpBg") as ColorRect, hp_fill, hp_label, armour_bg, armour_fill, grenade_label)
	weapons = WeaponBar.new(_slots, grenade_label)
	streaks = StreakColumn.new(self, streak_label, _streak_slots)
	_style_bottom()
	_facelift_hud()
	weapons.refresh()
	streaks.build()
	# #387: the slots show the player's pick from the first frame.
	streaks.set_choice(Game.streak_choice if not Game.streak_choice.is_empty() else StreakDefs.default_ids())
	_notice_layer = HudNotice.new()
	_notice_layer.name = "NoticeLayer"
	add_child(_notice_layer)
	_notice_layer.setup(get_node_or_null("Bottom") as VBoxContainer, self)
	trick = TrickPopup.new()
	add_child(trick)
	_chat = HudChat.new(chat_log, chat_input, presence_feed, _name_color)
	call_deferred("bind_player", null)


func _apply_hud_settings() -> void:
	var mm := get_node_or_null("Minimap") as Control
	if mm:
		mm.visible = Game.show_minimap
	if kill_feed:
		kill_feed.visible = Game.show_killfeed
	if fps_label:
		fps_label.visible = Game.perf_label_visible()
		fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if overlay:
		overlay.queue_redraw()


## Perf overlay text: scripts/hud/perf_overlay.gd. With the network line on (#364) the perf block
## keeps its own level and the net line is appended below it; with the perf overlay off the label
## carries the net line alone.
func _perf_text() -> String:
	var block := _perf.text(get_viewport(), get_process_delta_time()) if Game.show_fps else ""
	if not Game.show_net:
		return block
	var net := NetStats.text(Game, LagComp.INTERP_MS)
	return net if block.is_empty() else block + "\n" + net


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
	overlay.player = player
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


## Damage direction wedge pointing at `from_pos`: HudOverlay.add_damage_dir.
func add_damage_dir(from_pos: Vector3) -> void:
	overlay.add_damage_dir(from_pos)


## Screen angle of a world point around the crosshair: HudOverlay.dir_angle.
static func dir_angle(view: Transform3D, world_pos: Vector3) -> float:
	return HudOverlay.dir_angle(view, world_pos)


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
	overlay.player = null
	_local_peer_id = 0
	overlay.clear()
	streaks.reset()
	_hide_popup()
	_hide_notice()
	_hide_trick()
	board.reset()
	_freeze_left = 0.0
	_intermission_timer = 0.0
	death_layer.visible = false
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
	overlay.punch(amount)


## Weapon slots: WeaponBar (scripts/hud/weapon_bar.gd).
func set_ammo(current: int, mag: int) -> void:
	weapons.set_ammo(current, mag)


## The class decides the guns: one box per carried gun, keys 1..n in that order.
func set_weapon_slots(names: PackedStringArray) -> void:
	weapons.set_names(names)


## Tight crosshair + faint ring while sniper RMB zoom is held.
func set_sniper_ads(on: bool) -> void:
	if overlay.sniper_ads == on:
		return
	overlay.sniper_ads = on
	overlay.queue_redraw()


## The sniper has no hip crosshair. Bars and the centre dot return while zoomed.
func set_sniper_hip(on: bool) -> void:
	if overlay.sniper_hip == on:
		return
	overlay.sniper_hip = on
	overlay.queue_redraw()


func set_weapon_index(index: int) -> void:
	weapons.set_index(index)


## Bottom HUD: crystal HP bar (smoke track + fill), grenade/knife shard, outlined streak counter.
func _style_bottom() -> void:
	vitals.style()
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


## #387: the server's accepted pick, so the slots name the right streaks.
func set_streak_choice(ids: Array) -> void:
	streaks.set_choice(ids)


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


## #388: the Overdrive countdown, top centre. 0 hides it. The glow is on the body; this is the timer
## so the driver knows how long the monster lasts.
func show_overdrive(seconds: float) -> void:
	if _overdrive_label == null:
		_overdrive_label = Label.new()
		_overdrive_label.name = "OverdriveLabel"
		_overdrive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overdrive_label.add_theme_font_size_override("font_size", 20)
		_overdrive_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_overdrive_label.position.y += 96.0
		_overdrive_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_overdrive_label)
	_overdrive_label.visible = seconds > 0.0
	if seconds > 0.0:
		_overdrive_label.text = "OVERDRIVE  %.1f" % seconds
		_overdrive_label.add_theme_color_override("font_color", Overdrive.GLOW_COLOR)


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


func set_reloading(on: bool) -> void:
	reload_label.visible = on


## HP, armour and pickups: HudVitals (scripts/hud/hud_vitals.gd).
func _on_armour(a: float) -> void:
	vitals.set_armour(a)


func flash_pickup(label: String, col: Color) -> void:
	vitals.show_toast(label, col)


func blink_knives() -> void:
	vitals.blink_knives()


func _sound_pickup_hint(text: String, col: Color) -> void:
	vitals.show_toast(text, col)


func _on_health(hp: float, max_hp: float) -> void:
	if vitals.set_health(hp, max_hp):
		overlay.hurt()


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
	overlay.clear()


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
	overlay.hit(killed, headshot)


func _on_score_changed(_peer_id: int, _score: int, _n: String) -> void:
	if board.open:
		_refresh_scoreboard()


func _sort_scores(a: Dictionary, b: Dictionary) -> bool:
	return HudBoard.sort_scores(a, b)


func _on_round_ended(winner_peer_id: int, winner_name: String, _scores: Dictionary) -> void:
	board.local_peer_id = _local_peer_id
	board.round_ended(winner_peer_id, winner_name)


## The final killcam hid the round-end board; show it again for its full time.
func _on_killcam_finished() -> void:
	board.local_peer_id = _local_peer_id
	board.killcam_finished()


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
	if trick:
		trick.show_trick(text, points, multiplier)


func trick_text() -> String:
	return trick.text() if trick else ""


func _hide_trick() -> void:
	if trick:
		trick.hide_trick()


func style_king_text() -> String:
	return board.style_king_text()


func _refresh_standing() -> void:
	if _standing == null:
		_standing = StandingLine.new()
		add_child(_standing)
	_standing.refresh(_local_peer_id)


func _place_standing() -> void:
	if _standing:
		_standing.place()


## Top of the streak/flag popup: under the CTF status block in CTF, the usual spot otherwise.
static func _popup_top() -> float:
	return HudLayout.CTF_TOP + HudLayout.CTF_HEIGHT + HudLayout.POPUP_GAP if Game.is_ctf() else POPUP_TOP


static func _ordinal(n: int) -> String:
	return StandingLine.ordinal(n)




## The Tab board: HudBoard, built by ScoreboardView.
func _refresh_scoreboard() -> void:
	board.local_peer_id = _local_peer_id
	board.refresh()


func _process(delta: float) -> void:
	_tick_combo_ui(delta)
	_tick_speed_meter(delta)
	overlay.tick(delta)
	vitals.tick(delta)
	_standing_t -= delta
	if _standing_t <= 0.0:
		_standing_t = 0.25
		_refresh_standing()
	fps_label.visible = Game.perf_label_visible()
	if Game.perf_label_visible():
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

	board.local_peer_id = _local_peer_id
	board.tick(delta, Input.is_key_pressed(KEY_TAB))

	if _intermission_timer > 0.0:
		_intermission_timer -= delta
		if _intermission_timer <= 0.0:
			intermission_label.visible = false


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
