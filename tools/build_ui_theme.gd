extends SceneTree
## Builds res://ui/menu_theme.tres (main menu, pause menu, settings). Re-run after editing:
##   godot --headless --path . --script res://tools/build_ui_theme.gd

const ACCENT := Color(1.0, 0.72, 0.22)        # amber, the game's highlight colour
const TEXT := Color(0.92, 0.94, 0.96)
const MUTED := Color(0.62, 0.66, 0.72)
const BG := Color(0.06, 0.07, 0.09, 0.88)
const FIELD := Color(0.11, 0.12, 0.15, 0.92)
const FIELD_HOVER := Color(0.16, 0.17, 0.21, 0.95)


func _sb(bg: Color, border := Color(0, 0, 0, 0), left := 0, all := 0, radius := 2, pad_h := 14, pad_v := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = maxi(left, all)
	s.border_width_top = all
	s.border_width_right = all
	s.border_width_bottom = all
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	return s


func _init() -> void:
	var t := Theme.new()
	t.default_font_size = 17
	var bold := FontVariation.new()
	bold.variation_embolden = 0.6
	bold.spacing_glyph = 1
	var title := FontVariation.new()
	title.variation_embolden = 1.0
	title.spacing_glyph = 4

	# Buttons: dark slab, amber bar on the left when hovered or focused (mouse and pad look the same).
	var normal := _sb(Color(0.08, 0.09, 0.11, 0.78), Color(1, 1, 1, 0.06), 0, 1)
	var hover := _sb(Color(0.15, 0.16, 0.19, 0.92), ACCENT, 4, 0)
	hover.content_margin_left = 22
	var pressed := _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9), ACCENT, 4, 0)
	pressed.content_margin_left = 22
	var disabled := _sb(Color(0.08, 0.09, 0.11, 0.4))
	var focus := _sb(Color(0, 0, 0, 0), ACCENT, 4, 1)
	focus.draw_center = false
	for type in ["Button", "OptionButton", "CheckBox"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, hover)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color(0.08, 0.08, 0.1))
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(MUTED.r, MUTED.g, MUTED.b, 0.5))
		t.set_font("font", type, bold)
	t.set_constant("h_separation", "Button", 10)
	t.set_constant("align_to_largest_stylebox", "Button", 1)
	# CheckBox: no slab behind it, only the box (rows already draw a background).
	var clear := _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2, 4, 4)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", clear)
	t.set_color("font_pressed_color", "CheckBox", TEXT)

	# Primary call to action (Play, Start match): amber slab.
	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.92)))
	var p_hover := _sb(Color(1.0, 0.8, 0.36), Color.WHITE, 4, 0)
	p_hover.content_margin_left = 22
	t.set_stylebox("hover", "PrimaryButton", p_hover)
	t.set_stylebox("pressed", "PrimaryButton", _sb(Color(0.85, 0.58, 0.14)))
	t.set_color("font_color", "PrimaryButton", Color(0.07, 0.07, 0.09))
	t.set_color("font_hover_color", "PrimaryButton", Color(0.07, 0.07, 0.09))
	t.set_color("font_focus_color", "PrimaryButton", Color(0.07, 0.07, 0.09))
	var p_focus := _sb(Color(0, 0, 0, 0), Color.WHITE, 4, 2)
	p_focus.draw_center = false
	t.set_stylebox("focus", "PrimaryButton", p_focus)

	# Big left-aligned home entries.
	t.add_type("MenuButtonBig")
	t.set_type_variation("MenuButtonBig", "Button")
	t.set_font_size("font_size", "MenuButtonBig", 22)
	var big_normal := _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 0, 18, 10)
	var big_hover := _sb(Color(1, 1, 1, 0.08), ACCENT, 5, 0, 0, 28, 10)
	t.set_stylebox("normal", "MenuButtonBig", big_normal)
	t.set_stylebox("hover", "MenuButtonBig", big_hover)
	t.set_stylebox("hover_pressed", "MenuButtonBig", big_hover)
	t.set_stylebox("pressed", "MenuButtonBig", _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25), ACCENT, 5, 0, 0, 28, 10))
	var big_focus := _sb(Color(1, 1, 1, 0.08), ACCENT, 5, 0, 0, 28, 10)
	t.set_stylebox("focus", "MenuButtonBig", big_focus)
	t.set_color("font_color", "MenuButtonBig", Color(0.82, 0.85, 0.89))
	t.set_color("font_focus_color", "MenuButtonBig", ACCENT)
	t.set_color("font_hover_color", "MenuButtonBig", ACCENT)
	t.set_color("font_pressed_color", "MenuButtonBig", Color.WHITE)
	t.set_constant("h_separation", "MenuButtonBig", 0)

	# Text fields and spin boxes.
	var le := _sb(FIELD, Color(1, 1, 1, 0.08), 0, 1, 2, 10, 6)
	var le_focus := _sb(Color(0, 0, 0, 0), ACCENT, 0, 2, 2, 10, 6)
	le_focus.draw_center = false
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED.r, MUTED.g, MUTED.b, 0.6))
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))

	# Sliders: thin track, amber fill.
	var track := _sb(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 0, 2, 0, 3)
	var fill := _sb(ACCENT, Color(0, 0, 0, 0), 0, 0, 2, 0, 3)
	var fill_hi := _sb(Color(1.0, 0.82, 0.4), Color(0, 0, 0, 0), 0, 0, 2, 0, 3)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	var sl_focus := _sb(Color(0, 0, 0, 0), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7), 0, 1, 3, 0, 0)
	sl_focus.draw_center = false
	sl_focus.expand_margin_top = 6
	sl_focus.expand_margin_bottom = 6
	sl_focus.expand_margin_left = 4
	sl_focus.expand_margin_right = 4
	t.set_stylebox("focus", "HSlider", sl_focus)
	t.set_constant("center_grabber", "HSlider", 1)

	# Popups (OptionButton lists).
	t.set_stylebox("panel", "PopupMenu", _sb(Color(0.07, 0.08, 0.1, 0.98), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5), 0, 1, 2, 6, 6))
	t.set_stylebox("hover", "PopupMenu", _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25), ACCENT, 3, 0, 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font_size("font_size", "PopupMenu", 16)

	# Scroll bars: slim.
	var bar := _sb(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 0, 0, 3, 3, 0)
	var grab := _sb(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 0, 0, 3, 3, 0)
	var grab_hi := _sb(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.8), Color(0, 0, 0, 0), 0, 0, 3, 3, 0)
	t.set_stylebox("scroll", "VScrollBar", bar)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_hi)

	# Labels and panels.
	t.set_color("font_color", "Label", TEXT)
	t.add_type("TitleLabel")
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title)
	t.set_font_size("font_size", "TitleLabel", 30)
	t.set_color("font_color", "TitleLabel", Color.WHITE)
	t.add_type("HeroLabel")
	t.set_type_variation("HeroLabel", "Label")
	t.set_font("font", "HeroLabel", title)
	t.set_font_size("font_size", "HeroLabel", 64)
	t.set_color("font_color", "HeroLabel", Color.WHITE)
	t.set_color("font_shadow_color", "HeroLabel", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_y", "HeroLabel", 3)
	t.add_type("SectionLabel")
	t.set_type_variation("SectionLabel", "Label")
	t.set_font("font", "SectionLabel", bold)
	t.set_font_size("font_size", "SectionLabel", 14)
	t.set_color("font_color", "SectionLabel", ACCENT)
	t.add_type("HintLabel")
	t.set_type_variation("HintLabel", "Label")
	t.set_font_size("font_size", "HintLabel", 13)
	t.set_color("font_color", "HintLabel", MUTED)
	t.add_type("MenuPanel")
	t.set_type_variation("MenuPanel", "PanelContainer")
	var mp := _sb(BG, Color(1, 1, 1, 0.07), 0, 1, 4, 28, 24)
	mp.border_width_top = 3
	mp.border_color = Color(1, 1, 1, 0.07)
	t.set_stylebox("panel", "MenuPanel", mp)
	t.add_type("SettingRow")
	t.set_type_variation("SettingRow", "PanelContainer")
	t.set_stylebox("panel", "SettingRow", _sb(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 0, 2, 12, 4))
	t.set_stylebox("panel", "PanelContainer", _sb(BG, Color(1, 1, 1, 0.07), 0, 1, 4, 24, 20))

	var err := ResourceSaver.save(t, "res://ui/menu_theme.tres")
	print("menu_theme.tres saved: ", error_string(err))
	quit(0 if err == OK else 1)
