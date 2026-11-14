class_name HudNotice
extends Control
## The two short-lived messages above the weapon boxes and under the clock (#106 split out of hud.gd):
##
## - notice: one line inside the bottom stack ("Class changes at next spawn"), fading by itself.
## - popup: the streak/flag box under the match clock ("UAV / by NAME"), gold for friendly and red for
##   hostile, holding `_POPUP_HOLD` seconds and then fading.
##
## The layer renders; it does not decide. Colours and the "by NAME" line come in already resolved, so the
## HUD keeps its game knowledge (team colours, FFA's self colour) and this file stays about layout and
## timing. Position comes from `HudLayout.popup_top()`.
const POPUP_HOLD := 2.4 # hold, then fade
const POPUP_FADE := 0.6
const NOTICE_FADE := 0.5
const NOTICE_COLOR := Color(1, 0.92, 0.55)

var _notice: Label
var _notice_tween: Tween
var _popup: VBoxContainer
var _popup_title: Label
var _popup_by: RichTextLabel
var _popup_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The notice lives inside the HUD's bottom stack so it can never land on the HP bar or the weapon
## boxes, whatever the screen height; the popup stays a direct child of the HUD, where its anchors and
## its node name ("StreakPopup") are unchanged. Both may be null (a bare layer in a check). `setup` is what builds them.
func setup(bottom: VBoxContainer, root: Node = null) -> void:
	_build_notice(bottom)
	_build_popup(root if root != null else self)


func _build_notice(bottom: VBoxContainer) -> void:
	_notice = Label.new()
	_notice.name = "Notice"
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 18)
	_notice.add_theme_color_override("font_color", NOTICE_COLOR)
	_notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_notice.add_theme_constant_override("outline_size", 6)
	_notice.visible = false
	if bottom:
		bottom.add_child(_notice)
		bottom.move_child(_notice, 0)
	else:
		add_child(_notice)


func _build_popup(parent: Node) -> void:
	_popup = VBoxContainer.new()
	_popup.name = "StreakPopup"
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.anchor_left = 0.5
	_popup.anchor_right = 0.5
	_popup.offset_left = -220.0
	_popup.offset_right = 220.0
	_popup.offset_top = HudLayout.POPUP_TOP
	_popup.offset_bottom = HudLayout.POPUP_TOP + HudLayout.POPUP_HEIGHT
	_popup.add_theme_constant_override("separation", 0)
	_popup.visible = false
	parent.add_child(_popup)
	_popup_title = Label.new()
	_popup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_title.add_theme_font_size_override("font_size", 30)
	_popup_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_popup_title.add_theme_constant_override("outline_size", 8)
	_popup_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(_popup_title)
	_popup_by = RichTextLabel.new()
	_popup_by.name = "By"
	_popup_by.bbcode_enabled = true
	_popup_by.fit_content = true
	_popup_by.scroll_active = false
	_popup_by.autowrap_mode = TextServer.AUTOWRAP_OFF
	_popup_by.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_by.add_theme_font_size_override("normal_font_size", 18)
	_popup_by.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_popup_by.add_theme_constant_override("outline_size", 6)
	_popup.add_child(_popup_by)


## `by_html` is the already-escaped "by NAME" line in BBCode, `top` the popup's y for this mode (CTF
## puts the status block between the clock and the popup).
func show_popup(title: String, title_col: Color, by_html: String, top: float) -> void:
	if _popup == null:
		return
	_popup_title.text = title
	_popup.offset_top = top
	_popup.offset_bottom = top + HudLayout.POPUP_HEIGHT
	_popup_title.add_theme_color_override("font_color", title_col)
	_popup_by.text = by_html
	if _popup_tween:
		_popup_tween.kill()
	_popup.modulate.a = 1.0
	_popup.visible = true
	_popup_tween = _popup.create_tween()
	_popup_tween.tween_interval(POPUP_HOLD)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, POPUP_FADE)
	_popup_tween.tween_callback(hide_popup)


func hide_popup() -> void:
	if _popup_tween:
		_popup_tween.kill()
		_popup_tween = null
	if _popup:
		_popup.visible = false


## The popup's own Control (offset_top/bottom), for the layout checks.
func popup_box() -> Control:
	return _popup


func popup_visible() -> bool:
	return _popup != null and _popup.visible


func popup_title() -> String:
	return _popup_title.text if _popup_title else ""


func show_notice(text: String, seconds: float = 3.0) -> void:
	if _notice == null:
		_build_notice(null)
	_notice.text = text
	if _notice_tween:
		_notice_tween.kill()
	_notice.modulate.a = 1.0
	_notice.visible = true
	_notice_tween = _notice.create_tween()
	_notice_tween.tween_interval(seconds)
	_notice_tween.tween_property(_notice, "modulate:a", 0.0, NOTICE_FADE)
	_notice_tween.tween_callback(hide_notice)


## Empty when no notice is up, so callers can tell "nothing to say" from "saying".
func notice_text() -> String:
	return _notice.text if _notice and _notice.visible else ""


func hide_notice() -> void:
	if _notice_tween:
		_notice_tween.kill()
		_notice_tween = null
	if _notice:
		_notice.visible = false


## Back to the menu: drop whatever is on screen without waiting for its timer.
func reset() -> void:
	hide_popup()
	hide_notice()
