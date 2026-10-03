class_name Maps
extends RefCounted
## Map registry: scene, spawns and menu camera per map. main.gd loads the scene under World;
## the server tells joiners which one (Game.sync_match_config). Ids go over the wire as Strings.
## Blue (team 0) spawns at +Z and faces -Z; Orange at -Z faces +Z. FFA spawns face the map centre.

const DEFAULT := &"townhouses"
const ORDER: Array[StringName] = [&"townhouses", &"foundry"]

const INFO := {
	&"townhouses": {
		"name": "Townhouses",
		"blurb": "Two rows of houses, a street with a bus, backyards and flanks.",
		"scene": "res://scenes/maps/townhouses.tscn",
		"menu_cam": [Vector3(26, 24, 62), Vector3(0, 2, 0)],
		# Backyards behind the houses, not in the centre lane. Wings at x=±5.3 block the lane from them.
		"team_spawns": [
			[Vector3(-17.4, 0, 31.6), Vector3(-8.6, 0, 32.4), Vector3(-16.0, 0, 35.6), Vector3(8.6, 0, 32.4), Vector3(17.4, 0, 31.6)],
			[Vector3(-17.4, 0, -31.6), Vector3(-8.6, 0, -32.4), Vector3(-16.0, 0, -35.6), Vector3(8.6, 0, -32.4), Vector3(17.4, 0, -31.6)],
		],
		"ffa_spawns": [
			Vector3(-17.4, 0, 31.6), Vector3(8.6, 0, 32.4), Vector3(17.4, 0, -31.6), Vector3(-8.6, 0, -32.4),
			Vector3(-16.0, 0, 35.6), Vector3(16.0, 0, -35.6),
			Vector3(-23.5, 0, 8.0), Vector3(23.5, 0, -8.0), Vector3(-23.5, 0, -12.0), Vector3(23.5, 0, 12.0),
			Vector3(-6.5, 0, 4.0), Vector3(6.5, 0, -4.0), Vector3(3.5, 0, 10.5), Vector3(-3.5, 0, -10.5),
		],
	},
	&"foundry": {
		"name": "Foundry",
		"blurb": "Warehouse hall with a mezzanine, container yard, sheds and a long alley.",
		"scene": "res://scenes/maps/foundry.tscn",
		"menu_cam": [Vector3(34, 30, 46), Vector3(0, 0, 2)],
		"team_spawns": [
			[Vector3(-10, 0, 28.5), Vector3(-4, 0, 28), Vector3(4, 0, 28), Vector3(10, 0, 28.5), Vector3(0, 1.25, 32.5)],
			[Vector3(-10, 0, -28.5), Vector3(-4, 0, -28), Vector3(4, 0, -28), Vector3(10, 0, -28.5), Vector3(0, 1.25, -32.5)],
		],
		"ffa_spawns": [
			Vector3(-20, 0, 28), Vector3(20, 0, 28), Vector3(-20, 0, -28), Vector3(20, 0, -28),
			Vector3(0, 1.25, 32.5), Vector3(0, 1.25, -32.5),
			Vector3(-23, 0, 9.5), Vector3(-23, 0, -9.5), Vector3(-16, 0, 9), Vector3(-16, 0, -9),
			Vector3(21, 0, 17), Vector3(21, 0, -17), Vector3(23.5, 0, 10.5), Vector3(23.5, 0, -10.5),
			Vector3(-9, 3.05, 0), Vector3(9.6, 0, 1.6), Vector3(9.6, 0, -1.6),
		],
	},
}


static func has(id: StringName) -> bool:
	return INFO.has(id)


static func info(id: StringName) -> Dictionary:
	return INFO.get(id, INFO[DEFAULT])


static func display_name(id: StringName) -> String:
	return str(info(id).name)


## CLI / menu: "foundry", "Foundry" or the 1-based number in ORDER. Unknown → "".
static func parse(raw: String) -> StringName:
	var s := raw.strip_edges().to_lower()
	if s.is_valid_int():
		var i := int(s) - 1
		return ORDER[i] if i >= 0 and i < ORDER.size() else &""
	return StringName(s) if INFO.has(StringName(s)) else &""


static func team_spawns(id: StringName, team: int) -> Array:
	return info(id).team_spawns[clampi(team, 0, 1)]


static func ffa_spawns(id: StringName) -> Array:
	return info(id).ffa_spawns


## Yaw that faces the map centre from `pos` (FFA), or the team's forward.
static func spawn_yaw(pos: Vector3, team: int, ffa: bool) -> float:
	if ffa:
		var to := -Vector3(pos.x, 0, pos.z)
		if to.length_squared() < 0.01:
			return 0.0
		return atan2(-to.x, -to.z)
	return PI if team == 1 else 0.0
