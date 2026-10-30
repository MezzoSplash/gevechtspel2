class_name KillFeed
extends VBoxContainer
## Kill feed (top right, part of the HUD): killer, weapon icon, victim, trick tag. Newest on top,
## MAX_ROWS rows, each fades after LIFE seconds. The HUD forwards Game.kill_feed here.

const ICONS := {
	&"rifle": preload("res://assets/ui/icon_rifle.svg"),
	&"pistol": preload("res://assets/ui/icon_pistol.svg"),
	&"shotgun": preload("res://assets/ui/icon_shotgun.svg"),
	&"sniper": preload("res://assets/ui/icon_sniper.svg"),
	&"grenade": preload("res://assets/ui/icon_grenade.svg"),
	&"smg": preload("res://assets/ui/icon_smg.svg"),
	&"revolver": preload("res://assets/ui/icon_revolver.svg"),
	&"knife": preload("res://assets/ui/icon_knife.svg"),
	&"melee": preload("res://assets/ui/icon_melee.svg"),
	&"lmg": preload("res://assets/ui/icon_lmg.svg"),
	&"slug": preload("res://assets/ui/icon_slug.svg"),
	&"rcxd": preload("res://assets/ui/icon_rcxd.svg"),
	&"fall": preload("res://assets/ui/icon_fall.svg"), # kill_y (map drop), see player._check_kill_y
}
const MAX_ROWS := 6
const LIFE := 5.0

## Set by the HUD: name colour (team / FFA self) and this machine's player name.
var name_color: Callable = func(_n: String, _team: int) -> Color: return Color.WHITE
var local_name: Callable = func() -> String: return ""


func add_kill(
	killer_name: String, victim_name: String, weapon_id: StringName, killer_team: int, victim_team: int,
	tricks: String = ""
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var k := Label.new()
	k.text = killer_name
	k.add_theme_font_size_override("font_size", 16)
	k.add_theme_color_override("font_color", name_color.call(killer_name, killer_team))
	if killer_name == local_name.call():
		k.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
		k.add_theme_constant_override("outline_size", 4)
	var icon := TextureRect.new()
	icon.texture = ICONS.get(weapon_id, ICONS[&"rifle"])
	icon.custom_minimum_size = Vector2(56, 18)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 1, 1, 0.95)
	var v := Label.new()
	v.text = victim_name
	v.add_theme_font_size_override("font_size", 16)
	v.add_theme_color_override("font_color", name_color.call(victim_name, victim_team))
	if victim_name == local_name.call():
		v.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
		v.add_theme_constant_override("outline_size", 4)
	row.add_child(k)
	row.add_child(icon)
	row.add_child(v)
	if tricks != "":
		var tag := Label.new()
		tag.name = "TrickTag"
		tag.text = tricks
		tag.add_theme_font_size_override("font_size", 14)
		tag.add_theme_color_override("font_color", Hud.TRICK_COLOR)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		tag.add_theme_constant_override("outline_size", 4)
		row.add_child(tag)
	add_child(row)
	move_child(row, 0)
	while get_child_count() > MAX_ROWS:
		var old := get_child(get_child_count() - 1)
		remove_child(old)
		old.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(LIFE)
	tw.tween_property(row, "modulate:a", 0.0, 0.45)
	tw.tween_callback(row.queue_free)
