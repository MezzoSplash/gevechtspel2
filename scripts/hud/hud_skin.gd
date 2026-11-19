class_name HudSkin
extends RefCounted
## Crystal skin for the HUD's ColorRect slots (HP bar, weapon slots, streak slots): a ColorRect has
## no shape of its own, so a Panel with a CrystalStyle goes behind it and the rect turns transparent.
## Static, one source for the HUD, the weapon bar and the streak column.

static var _seed := 11 # each skinned rect gets its own facet fan


## Puts the shard behind `rect` (once). `radius` is unused since the crystal restyle; under 8 it
## picks the slimmer cut for the bars.
static func skin(rect: ColorRect, radius: int = 8) -> void:
	if rect == null or rect.get_node_or_null("Skin"):
		return
	var p := Panel.new()
	p.name = "Skin"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.show_behind_parent = true
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := CrystalStyle.new()
	sb.fill = rect.color
	sb.cuts = Vector4(10, 4, 12, 6) if radius < 8 else Vector4(6, 3, 8, 4)
	sb.variant = _seed
	_seed += 1
	p.add_theme_stylebox_override("panel", sb)
	rect.add_child(p)
	rect.move_child(p, 0)
	rect.color = Color(0, 0, 0, 0)


## Recolours the shard. `accent` lights the bottom seam (selection / held weapon / ready); `pale`
## makes it the pale shell (white facets, no light edge). Without a skin it colours the rect.
static func paint(rect: ColorRect, bg: Color, accent: Color = Color(0, 0, 0, 0), pale := false) -> void:
	var p := rect.get_node_or_null("Skin") as Panel
	if p == null:
		rect.color = bg
		return
	var sb := p.get_theme_stylebox("panel") as CrystalStyle
	# Every setter emits `changed`; skip the ones that did not change so a per-frame caller
	# (HP) does not redraw for nothing.
	if sb.fill != bg:
		sb.fill = bg
	if sb.pale != pale:
		sb.pale = pale
		sb.edge_alpha = 0.0 if pale else 0.16
	var side := CrystalStyle.Side.BOTTOM if accent.a > 0.0 else CrystalStyle.Side.NONE
	if sb.seam_side != side:
		sb.seam_side = side
	if accent.a > 0.0 and sb.seam_color != accent:
		sb.seam_color = accent


## Shrink a one-line label until it fits `max_w` (SLUG SHOTGUN in a 122 px slot, #58).
static func fit_label(l: Label, max_w: float, size: int, min_size: int) -> void:
	var font := l.get_theme_font("font")
	var fs := size
	while fs > min_size and font and font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	l.add_theme_font_size_override("font_size", fs)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
