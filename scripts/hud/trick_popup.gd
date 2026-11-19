class_name TrickPopup
extends VBoxContainer
## Trickshot by this machine's pawn (part of the HUD): the big gold word above the crosshair, the
## points and combo under it, a sting. Pops in, holds HOLD, fades over FADE. Gold: a trick reward.

const HOLD := 1.5
const FADE := 0.45
const _SFX := preload("res://assets/sounds/trickshot.wav")

var title: Label
var sub: Label
var sfx: AudioStreamPlayer
var _tw: Tween


func _init() -> void:
	name = "TrickPopup"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -480.0
	offset_right = 480.0
	offset_top = -250.0
	offset_bottom = -140.0
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 0)
	visible = false
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", HudLayout.TRICK)
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0, 0.95))
	title.add_theme_constant_override("outline_size", 12)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	sub = Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(1, 0.95, 0.82))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 6)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sub)
	sfx = AudioStreamPlayer.new()
	sfx.stream = _SFX
	sfx.bus = "UI"
	sfx.volume_db = -3.0
	add_child(sfx)


func show_trick(text: String, points: int, multiplier: float) -> void:
	if text == "":
		return
	title.text = text + "!"
	# Long combos ("HEADSHOT STREAK + SPRAY TRANSFER + AIRSHOT!") shrink to stay inside the popup.
	var fs := clampi(roundi(58.0 * 44.0 / float(maxi(title.text.length(), 1))), 34, 58)
	title.add_theme_font_size_override("font_size", fs)
	var line := "+%d STYLE" % points
	if multiplier > 1.001:
		line += "   x%s COMBO" % String.num(multiplier, 2).trim_suffix("0").trim_suffix(".")
	sub.text = line
	if _tw:
		_tw.kill()
	visible = true
	modulate.a = 1.0
	pivot_offset = size * 0.5
	scale = Vector2(1.35, 1.35)
	_tw = create_tween()
	_tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_interval(HOLD)
	_tw.tween_property(self, "modulate:a", 0.0, FADE)
	_tw.tween_callback(hide_trick)
	sfx.play()


## The word on screen ("" when hidden), for the checks.
func text() -> String:
	return title.text if visible else ""


func hide_trick() -> void:
	if _tw:
		_tw.kill()
		_tw = null
	visible = false
