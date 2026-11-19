class_name CrystalUi
extends RefCounted
## Layout pieces the crystal screens share (docs/ui-crystal/HANDOFF.md 4.4): the wordmark, the
## small key/hint text inside a menu button, the red seam on leave/quit, unequal button widths and
## the hint footer shard. The theme itself (every control's shard) is shared/crystal_theme.gd; this
## only builds or adjusts nodes, so the menu, pause and settings screens look like one family.

## Seam colour for leaving: red is only for danger/leave (HANDOFF 2.4).
const DANGER := Color(0.92, 0.33, 0.28)
## Muted caption grey: readable on smoke glass and on the pale shell of a hovered button.
const MUTE := Color(0.50, 0.55, 0.62)
const HINT_FONT := 11
const WORD_FONT := 64

static var _light: FontVariation
static var _bold: FontVariation
static var _caps: FontVariation


## Thin, bold and tracked caption faces, made once from the theme's default font.
static func _fonts() -> void:
	if _light != null:
		return
	var base := ThemeDB.fallback_font
	_light = FontVariation.new()
	_light.base_font = base
	_light.variation_embolden = -0.75
	_light.spacing_glyph = 4
	_bold = FontVariation.new()
	_bold.base_font = base
	_bold.variation_embolden = 1.0
	_bold.spacing_glyph = 2
	_caps = FontVariation.new()
	_caps.base_font = base
	_caps.variation_embolden = 0.5
	_caps.spacing_glyph = 3


static func light_font() -> FontVariation:
	_fonts()
	return _light


static func caps_font() -> FontVariation:
	_fonts()
	return _caps


## "GEVECHT" light over "SPEL" bold, the crystal mark beside it.
static func wordmark() -> HBoxContainer:
	_fonts()
	var row := HBoxContainer.new()
	row.name = "Wordmark"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 22)
	var mark := CrystalMark.new()
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -18)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in [["GEVECHT", _light], ["SPEL", _bold]]:
		var l := Label.new()
		l.text = part[0]
		l.add_theme_font_override("font", part[1])
		l.add_theme_font_size_override("font_size", WORD_FONT)
		l.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97))
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_y", 3)
		words.add_child(l)
	row.add_child(words)
	return row


## Small tracked caption on the right edge of a button ("PLAY AGAINST BOTS", "ESC").
static func button_hint(btn: Button, text: String, right := 26.0) -> Label:
	_fonts()
	var l := Label.new()
	l.name = "Hint"
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_right = -right
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _caps)
	l.add_theme_font_size_override("font_size", HINT_FONT)
	l.add_theme_color_override("font_color", MUTE)
	btn.add_child(l)
	return l


## Every state of `btn` keeps its theme shard, with the seam in `col` (leave/quit in red).
static func seam_color(btn: Button, col: Color) -> void:
	var type := btn.theme_type_variation if btn.theme_type_variation != &"" else &"Button"
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var sb := btn.get_theme_stylebox(st, type) as CrystalStyle
		if sb == null:
			continue
		var own := sb.duplicate() as CrystalStyle
		own.seam_color = Color(col, sb.seam_color.a)
		btn.add_theme_stylebox_override(st, own)


## Unequal widths, longest first, so a column of buttons reads as cut pieces, not a list.
## `centred` for a centred column (pause), otherwise left-aligned (main menu).
static func stagger(buttons: Array, widths: Array, centred := false) -> void:
	for i in buttons.size():
		var b := buttons[i] as Control
		if b == null:
			continue
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if centred else Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size.x = widths[mini(i, widths.size() - 1)]


static func bold_font() -> FontVariation:
	_fonts()
	return _bold


## A shard for a piece built in code (scoreboard, round-end card, class select): smoke glass, or
## pale shell with `pale`; a seam on `side` in `seam`, lit to `lit` (0..1, the value on a meter).
## `margin` is the content margin (x left/right, y top/bottom). One source for these pieces, so
## no screen keeps its own flat-box copy of the look.
static func shard(cuts: Vector4, variant: int, pale := false, side := CrystalStyle.Side.NONE,
		seam := CrystalStyle.ICE, lit := 1.0, margin := Vector2(14, 6)) -> CrystalStyle:
	var sb := CrystalStyle.new()
	sb.cuts = cuts
	sb.variant = variant
	if pale:
		sb.fill = CrystalStyle.SHELL
		sb.pale = true
		sb.edge_alpha = 0.0
	sb.seam_side = side
	sb.seam_color = seam
	sb.seam_lit = lit
	sb.content_margin_left = margin.x
	sb.content_margin_right = margin.x
	sb.content_margin_top = margin.y
	sb.content_margin_bottom = margin.y
	return sb


## Tracked uppercase caption ("BLUE", "CHOOSE CLASS", column heads) in the caps face.
static func caption(text: String, size: int, col: Color) -> Label:
	_fonts()
	var l := Label.new()
	l.text = text.to_upper()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _caps)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## The key-hint line at the foot of a screen as a slim smoke shard, sized to its text.
static func footer(l: Label) -> void:
	_fonts()
	var sb := CrystalStyle.new()
	sb.cuts = Vector4(6, 3, 10, 4)
	sb.variant = 61
	sb.facet_strength = 0.6
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	l.add_theme_stylebox_override("normal", sb)
	l.add_theme_font_override("font", _caps)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", MUTE.lightened(0.15))
	l.text = l.text.to_upper()
	# An anchored label spans its offsets; shrink it to the text so the shard hugs it.
	if not (l.get_parent() is Container):
		l.offset_right = l.offset_left + l.get_combined_minimum_size().x
		l.offset_top = l.offset_bottom - l.get_combined_minimum_size().y


## A shard with one big centred number and an optional caption under it: the pause menu's
## score pieces. `pale` is the clock in the middle.
static func score_shard(cuts: Vector4, variant: int, pale := false) -> PanelContainer:
	_fonts()
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := CrystalStyle.new()
	sb.cuts = cuts
	sb.variant = variant
	if pale:
		sb.fill = CrystalStyle.SHELL
		sb.pale = true
		sb.edge_alpha = 0.0
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num := Label.new()
	num.name = "Num"
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.add_theme_font_override("font", _bold)
	num.add_theme_font_size_override("font_size", 34 if pale else 44)
	num.add_theme_color_override("font_color", Color(0.07, 0.08, 0.10) if pale else Color(0.93, 0.95, 0.97))
	col.add_child(num)
	var cap := Label.new()
	cap.name = "Cap"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_override("font", _caps)
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", Color(0.30, 0.35, 0.42) if pale else MUTE)
	col.add_child(cap)
	p.add_child(col)
	return p


## Sets a score shard's number, caption and seam (Side.NONE without a colour).
static func set_score(p: PanelContainer, num: String, cap: String, seam := Color(0, 0, 0, 0)) -> void:
	(p.get_node("Col/Num") as Label).text = num
	var c := p.get_node("Col/Cap") as Label
	c.text = cap
	c.visible = cap != ""
	var sb := p.get_theme_stylebox("panel") as CrystalStyle
	var side := CrystalStyle.Side.BOTTOM if seam.a > 0.0 else CrystalStyle.Side.NONE
	if sb.seam_side != side:
		sb.seam_side = side
	if seam.a > 0.0 and sb.seam_color != seam:
		sb.seam_color = seam
