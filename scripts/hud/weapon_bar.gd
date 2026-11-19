class_name WeaponBar
extends RefCounted
## The weapon slots and the grenade/knife pill at the bottom of the HUD (part of the HUD). One box
## per gun the class carries, keys 1..n in that order; the held one is pale shell with the ammo.
## The HUD owns the nodes from its scene and forwards set_ammo / set_weapon_slots / ... here.

var slots: Array[ColorRect] = []
var grenade_label: Label
var names: PackedStringArray = ["RIFLE", "PISTOL", "SHOTGUN", "SNIPER"] # the local pawn's guns
var index := 0
var ammo := 30
var mag := 30


func _init(slot_rects: Array[ColorRect], grenades: Label) -> void:
	slots = slot_rects
	grenade_label = grenades


func set_ammo(current: int, mag_size: int) -> void:
	ammo = current
	mag = mag_size
	refresh()


## The class decides the guns. Same names (case-insensitive): nothing to redraw.
func set_names(new_names: PackedStringArray) -> void:
	var upper: PackedStringArray = []
	for n in new_names:
		upper.append(n.strip_edges().to_upper())
	if upper == names:
		return
	names = upper
	refresh()


func set_index(i: int) -> void:
	index = clampi(i, 0, maxi(names.size() - 1, 0))
	refresh()


## Frags on G, throwing knives on F (only shown when the class carries knives).
func set_grenades(n: int, knives: int = 0) -> void:
	if grenade_label:
		grenade_label.text = "G  FRAG %d" % n if knives <= 0 else "G  FRAG %d    F  KNIFE %d" % [n, knives]


## The grenade pill as a small smoke shard, shrunk to its text, at the end of the HP row (#65).
func style_grenades() -> void:
	if grenade_label == null:
		return
	var sb := CrystalStyle.new()
	sb.fill = HudLayout.PANEL
	sb.cuts = Vector4(6, 3, 7, 4)
	sb.variant = 21
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	grenade_label.add_theme_stylebox_override("normal", sb)
	grenade_label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.96))
	grenade_label.add_theme_font_size_override("font_size", 16)
	grenade_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func refresh() -> void:
	if slots.is_empty() or slots[0] == null:
		return
	for i in slots.size():
		var slot := slots[i]
		slot.visible = i < names.size()
		if not slot.visible:
			continue
		var on := i == index
		HudSkin.skin(slot)
		HudSkin.paint(slot, HudLayout.SLOT_ON if on else HudLayout.SLOT_IDLE, HudLayout.ACCENT if on else Color(0, 0, 0, 0), on)
		var name_l := slot.get_node("Name") as Label
		var ammo_l := slot.get_node("Ammo") as Label
		var key_l := slot.get_node_or_null("Key") as Label
		var ink := HudLayout.SLOT_TEXT_ON if on else Color.WHITE
		if key_l:
			key_l.text = str(i + 1)
			key_l.modulate = ink
		if ammo_l:
			ammo_l.modulate = ink
		if name_l:
			name_l.text = names[i]
			HudSkin.fit_label(name_l, slot.custom_minimum_size.x - 14.0, 16, 12)
			name_l.modulate = ink if on else Color(0.72, 0.74, 0.78)
		if ammo_l:
			ammo_l.text = "" if not on else ("—" if mag <= 0 else ("%d / %d" % [ammo, mag]))
