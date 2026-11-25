class_name StreakColumn
extends RefCounted
## The scorestreak column on the left of the HUD (part of the HUD): the SCORESTREAK caption, one pip
## per kill toward LOS, three slots with the picked streak's name and its cost or READY tag, the
## arrow-key selection, the RC-XD drive line and the announcer lines. The HUD owns the scene nodes
## and the popups ("UAV by X"); it forwards set_streak / set_rc_drive / ... here. #387: the slots show
## the player's pick (UAV/RC-XD/LOS by default), set with set_choice.

## Unlit pip, and unlit on a reward's kill (UAV, RC-XD, LOS).
const PIP_OFF := Color(1, 1, 1, 0.12)
const PIP_MARK := Color(1, 1, 1, 0.26)
## "Friendly/Enemy radar online" at most once per RADAR_VOICE_COOLDOWN per type. With 12 bots calling
## UAVs the line played all match long. The popup text still shows every time.
const RADAR_VOICE_COOLDOWN := 20.0

var host: Control # the HUD: parent of the RC line and the announcer
var label: Label
var slots: Array[ColorRect] = []
var pips: HBoxContainer
var costs: Array[Label] = []
var announcer: AudioStreamPlayer
var n := 0 # kills toward the next reward
var charges := 0 # Game.CHARGE_* bits held
var earned := 0
var sel := 0 # the slot Enter fires
var radar_left := 0.0
var rc_on := false
var rc_hint: Label
var radar_voice_t := {} # "friendly"/"enemy"/... -> last play (s, ticks)
var radar_voice_log: Array = [] # types that actually played (headless check)
## #387: the streak ids this player picked, one per slot. Empty slots read as &"".
var choice: Array = []


func _init(hud: Control, caption: Label, slot_rects: Array[ColorRect]) -> void:
	host = hud
	label = caption
	slots = slot_rects
	choice = StreakDefs.default_ids()
	announcer = AudioStreamPlayer.new()
	announcer.name = "Announcer"
	announcer.bus = "UI"
	announcer.volume_db = -2.0
	host.add_child(announcer)


## #65: small caps caption, the pips under it, a cost/ready tag in each slot.
func build() -> void:
	if label:
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		pips = HBoxContainer.new()
		pips.name = "Pips"
		pips.add_theme_constant_override("separation", 4)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := label.get_parent()
		col.add_child(pips)
		col.move_child(pips, label.get_index() + 1)
		# Each pip is a tiny slanted shard (one cut top-left, one bottom-right), so the row reads as
		# shards of the crystal, not rounded dots.
		for i in Game.LOS_AT:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(14, 6)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := CrystalUi.shard(Vector4(3, 0, 3, 0), 40 + i)
			sb.fill = PIP_OFF
			sb.facet_strength = 0.0
			sb.edge_alpha = 0.0
			pip.add_theme_stylebox_override("panel", sb)
			pips.add_child(pip)
	for i in slots.size():
		var slot := slots[i]
		var cost: Label = null
		if slot and i < 3:
			cost = Label.new()
			cost.name = "Cost"
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cost.anchor_left = 0.0
			cost.anchor_right = 1.0
			cost.anchor_top = 1.0
			cost.anchor_bottom = 1.0
			cost.offset_top = -25.0
			cost.offset_bottom = -7.0
			cost.offset_right = -10.0
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cost.add_theme_font_size_override("font_size", 11)
			slot.add_child(cost)
		costs.append(cost)
	refresh()


## A new radar charge plays "Radar on standby", a new RC-XD charge "RC-XD ready for deployment".
## Only the player who owns the streak gets this. The slot stays armed until Enter, including after death.
func set_streak(kills: int, held: int, earned_bits: int) -> void:
	var radar_new := (charges & Game.CHARGE_RADAR) == 0 and (held & Game.CHARGE_RADAR) != 0
	var rcxd_new := (charges & Game.CHARGE_RCXD) == 0 and (held & Game.CHARGE_RCXD) != 0
	n = kills
	charges = held
	earned = earned_bits
	refresh()
	# Both at once is not expected (3 vs 5 kills); the RC-XD line wins then, it is the newer reward.
	if rcxd_new:
		play_announcer("res://assets/sounds/rcxd_ready.wav")
	elif radar_new:
		play_announcer("res://assets/sounds/radar_standby.wav")


## Arrow keys: -1 up, +1 down, wrapping over the three slots.
func select(step: int) -> void:
	sel = posmod(sel + step, 3)
	refresh()


## Your team's radar came on (from you or a team mate): keep the longer of the two windows.
func radar_started() -> void:
	radar_left = maxf(radar_left, Game.radar_left)
	refresh()


func clear_radar() -> void:
	if radar_left <= 0.0:
		return
	radar_left = 0.0
	refresh()


func tick(delta: float) -> void:
	if radar_left > 0.0:
		radar_left = maxf(radar_left - delta, 0.0)
		if radar_left <= 0.0:
			refresh()


## Leave to menu: no kills, no charges, no radar, no car.
func reset() -> void:
	n = 0
	charges = 0
	earned = 0
	radar_left = 0.0
	set_rc_drive(false, 0.0, 0.0)


## While the local camera is in the car. `on` false hides the line.
func set_rc_drive(on: bool, hp: float, life: float) -> void:
	rc_on = on
	if not on:
		if rc_hint:
			rc_hint.visible = false
		refresh()
		return
	if rc_hint == null:
		rc_hint = Label.new()
		rc_hint.name = "RcHint"
		rc_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rc_hint.anchor_left = 0.5
		rc_hint.anchor_right = 0.5
		rc_hint.anchor_top = 0.5
		rc_hint.anchor_bottom = 0.5
		rc_hint.offset_left = -220.0
		rc_hint.offset_right = 220.0
		rc_hint.offset_top = 48.0
		rc_hint.offset_bottom = 80.0
		rc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rc_hint.add_theme_font_size_override("font_size", 20)
		rc_hint.add_theme_color_override("font_color", Color(1, 0.86, 0.35))
		rc_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		rc_hint.add_theme_constant_override("outline_size", 6)
		host.add_child(rc_hint)
	rc_hint.text = "LMB DETONATE    %d HP    %ds" % [ceili(maxf(hp, 0.0)), ceili(maxf(life, 0.0))]
	rc_hint.visible = true
	refresh()


## Slot 0 radar (3), slot 1 RC-XD (5), slot 2 LOS (7). Crystal: idle smoke; a held charge lights the
## ice seam; the selected held charge is the pale shell (the one Enter fires). Selected but empty is
## lighter smoke with a white seam (the arrow-key cursor).
func refresh() -> void:
	_refresh_extras()
	for i in slots.size():
		var slot := slots[i]
		if slot == null:
			continue
		var selected := i == sel
		var ready := (charges & _charge_bit(i)) != 0
		var name_l := slot.get_node_or_null("Name") as Label
		var shell := ready and selected
		if name_l:
			name_l.text = _slot_name(i)
			# The first slot's name always reads (it was never greyed); the others grey out while empty.
			var col := Color(0.92, 0.95, 0.98) if ready or i == 0 else Color(0.55, 0.58, 0.62)
			if shell:
				col = HudLayout.SLOT_TEXT_ON
			name_l.add_theme_color_override("font_color", col)
		HudSkin.skin(slot)
		var bg := Color(CrystalStyle.SMOKE, 0.5 if i > 0 else 0.62)
		if shell:
			bg = HudLayout.SLOT_ON
		elif ready or selected:
			bg = Color(0.11, 0.14, 0.18, 0.8)
		var edge := Color(0, 0, 0, 0)
		if ready:
			edge = HudLayout.ACCENT
		elif selected:
			edge = Color(0.92, 0.94, 0.97, 0.9)
		HudSkin.paint(slot, bg, edge, shell)


func _refresh_extras() -> void:
	if label:
		label.text = "SCORESTREAK"
	if pips:
		for i in pips.get_child_count():
			var sb := (pips.get_child(i) as Panel).get_theme_stylebox("panel") as CrystalStyle
			var lit := i < n
			# A brighter pip marks each cost the pick actually banks on (UAV/RCXplodie/LOS by default).
			var mark := _costs().has(i + 1)
			sb.fill = HudLayout.ACCENT if lit else (PIP_MARK if mark else PIP_OFF)
	for i in costs.size():
		var c := costs[i]
		if c == null:
			continue
		var is_ready := (charges & _charge_bit(i)) != 0
		var cost := _cost(i)
		c.text = "READY · ENTER" if is_ready else ("%d KILLS" % cost if cost > 0 else "—")
		var on_shell := is_ready and i == sel # refresh paints that slot pale
		c.add_theme_color_override("font_color", HudLayout.SLOT_TEXT_ON if on_shell else (HudLayout.ACCENT if is_ready else Color(0.62, 0.66, 0.72, 0.85)))


## #387: the HUD follows the player's pick. An empty slot (a pick of one or two) shows a dash.
func set_choice(ids: Array) -> void:
	choice = ids
	refresh()


func _id_at(i: int) -> StringName:
	if i < 0 or i >= choice.size():
		return &""
	return StringName(choice[i])


func _slot_name(i: int) -> String:
	var id := _id_at(i)
	return "—" if id == &"" else StreakDefs.name_of(id)


func _charge_bit(i: int) -> int:
	return StreakDefs.bit(_id_at(i))


func _cost(i: int) -> int:
	var id := _id_at(i)
	return 0 if id == &"" else StreakDefs.kills(id)


func _costs() -> Array:
	var out: Array = []
	for i in choice.size():
		var c := _cost(i)
		if c > 0:
			out.append(c)
	return out


## The radar/RC-XD lines on their cooldown (see RADAR_VOICE_COOLDOWN).
func play_radar_voice(kind: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if radar_voice_t.has(kind) and now - float(radar_voice_t[kind]) < RADAR_VOICE_COOLDOWN:
		return
	radar_voice_t[kind] = now
	radar_voice_log.append(kind)
	play_announcer("res://assets/sounds/%s.wav" % (kind if kind.begins_with("rcxd_") else "radar_" + kind))


func play_announcer(path: String) -> void:
	if announcer == null:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	announcer.stream = stream
	announcer.play()
