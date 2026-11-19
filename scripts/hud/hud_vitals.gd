class_name HudVitals
extends RefCounted
## HP, armour and pickups at the bottom of the HUD (part of the HUD): the crystal HP bar (ice when
## healthy, amber in the middle, red when low) with its number, the Schildplaat bar above it (#144),
## the pickup toast above the stack and the knife counter's blink. The HUD owns the scene nodes and
## forwards _on_health / _on_armour / flash_pickup / blink_knives here.

const HP_OK := Color(0.78, 0.93, 1.0, 0.95)
const HP_MID := Color(0.95, 0.72, 0.25, 0.95)
const HP_LOW := Color(0.92, 0.2, 0.16, 0.96)
const TOAST_TIME := 2.0 # s a pickup toast stays, fading over the last TOAST_FADE
const TOAST_FADE := 0.6

var bottom: Control # $Bottom: the toast's parent
var hp_bg: ColorRect
var hp_fill: ColorRect
var hp_label: Label
var armour_bg: ColorRect
var armour_fill: ColorRect
var grenade_label: Label # blinks when Extra Messen is taken
var hp := 100.0
var max_hp := 100.0
var toast: Label
var _toast_t := 0.0


func _init(bottom_stack: Control, bg: ColorRect, fill: ColorRect, number: Label, a_bg: ColorRect, a_fill: ColorRect, grenades: Label) -> void:
	bottom = bottom_stack
	hp_bg = bg
	hp_fill = fill
	hp_label = number
	armour_bg = a_bg
	armour_fill = a_fill
	grenade_label = grenades


## The crystal HP bar: smoke track, ice fill without a light edge, the number left-aligned on it.
func style() -> void:
	if hp_bg:
		hp_bg.color = CrystalStyle.SMOKE
		HudSkin.skin(hp_bg, 8)
		HudSkin.paint(hp_bg, CrystalStyle.SMOKE)
	if hp_fill:
		HudSkin.skin(hp_fill, 8)
		HudSkin.paint(hp_fill, HP_OK)
		(hp_fill.get_node("Skin").get_theme_stylebox("panel") as CrystalStyle).edge_alpha = 0.0
	if hp_label:
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hp_label.offset_left = 12.0
		hp_label.add_theme_font_size_override("font_size", 17)
		hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		hp_label.add_theme_constant_override("outline_size", 4)


## New HP. Returns true when it went down (the HUD flashes the vignette then).
func set_health(new_hp: float, new_max: float) -> bool:
	var hurt := new_hp < hp
	hp = new_hp
	max_hp = new_max
	var t := clampf(new_hp / maxf(new_max, 1.0), 0.0, 1.0)
	if hp_label:
		hp_label.text = str(roundi(new_hp))
	if hp_fill:
		hp_fill.anchor_right = t
		HudSkin.paint(hp_fill, fill_for(t))
	return hurt


## The HP fill for a share of max HP: red under 30 %, amber under 60 %, ice above.
static func fill_for(t: float) -> Color:
	if t < 0.3:
		return HP_LOW
	return HP_MID if t < 0.6 else HP_OK


## Schildplaat (#144): a thin bar above the HP bar, hidden when there is no armour.
func set_armour(a: float) -> void:
	var on := a > 0.5
	if armour_bg:
		armour_bg.visible = on
	if armour_fill:
		armour_fill.visible = on
		armour_fill.anchor_right = clampf(a / maxf(Pickups.ARMOUR, 1.0), 0.0, 1.0)
	if on:
		show_toast("+%d ARMOUR" % roundi(a), Pickups.type_info(&"shield")["color"])


## A short label in the pickup's colour above the HP bar (#144), made on the first pickup.
func show_toast(text: String, col: Color) -> void:
	if toast == null:
		toast = Label.new()
		toast.name = "PickupToast"
		bottom.add_child(toast)
		toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toast.anchor_left = 0.0
		toast.anchor_right = 1.0
		toast.offset_top = -46.0
		toast.offset_bottom = -18.0
		toast.add_theme_font_size_override("font_size", 20)
		toast.add_theme_constant_override("outline_size", 6)
		toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast.text = text
	toast.add_theme_color_override("font_color", col)
	toast.modulate.a = 1.0
	_toast_t = TOAST_TIME


## Extra Messen taken: the knife counter blinks so the new count is noticed (#144).
func blink_knives() -> void:
	if grenade_label == null:
		return
	var tw := grenade_label.create_tween()
	tw.tween_property(grenade_label, "modulate", Color(1.6, 1.6, 1.6, 1), 0.08)
	tw.tween_property(grenade_label, "modulate", Color.WHITE, 0.35)


func tick(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t = maxf(_toast_t - delta, 0.0)
		if toast:
			toast.modulate.a = clampf(_toast_t / TOAST_FADE, 0.0, 1.0)
