class_name Maps
extends RefCounted
## Map registry: scene, spawns and menu camera per map. main.gd loads the scene under World;
## the server tells joiners which one (Game.sync_match_config). Ids go over the wire as Strings.
## Blue (team 0) spawns at +Z and faces -Z; Orange at -Z faces +Z. FFA spawns face the map centre.

const DEFAULT := &"townhouses"
const ORDER: Array[StringName] = [&"townhouses", &"foundry", &"rooftops"]

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
		"blurb": "Warehouse hall with roof ramps, west surf, a container yard and sheds.",
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
	&"rooftops": {
		"name": "Rooftops",
		"blurb": "Two roofed blocks, a court, flank surfs, and a ramp across the middle.",
		"scene": "res://scenes/maps/rooftops.tscn",
		"menu_cam": [Vector3(34, 26, 54), Vector3(0, 2, 0)],
		# Yards behind the spawn walls. Flanks sit behind the baffles; the truck breaks the centre line.
		# Not on the surf, not on a drop lip, not inside the truck (x=0, z≈35).
		"team_spawns": [
			[Vector3(-25.2, 0, 37.2), Vector3(-10.2, 0, 35.4), Vector3(-4.6, 0, 38.4), Vector3(8.4, 0, 36.2), Vector3(24.6, 0, 37.4)],
			[Vector3(-25.2, 0, -37.2), Vector3(-10.2, 0, -35.4), Vector3(-4.6, 0, -38.4), Vector3(8.4, 0, -36.2), Vector3(24.6, 0, -37.4)],
		],
		"ffa_spawns": [
			Vector3(-25.2, 0, 37.2), Vector3(-4.6, 0, 38.4), Vector3(24.6, 0, 37.4),
			Vector3(25.2, 0, -37.2), Vector3(4.6, 0, -38.4), Vector3(-24.6, 0, -37.4),
			Vector3(-16.2, 0, -11.2), Vector3(16.4, 0, 11.5),
			Vector3(-7.4, 0, 7.8), Vector3(12.2, 0, -1.5),
			Vector3(-1.2, 6.0, 22.0), Vector3(1.4, 6.0, -22.4),
			# Was (8.8, 16.8), which the east stair now covers. Floor of the south room, clear of both stairs.
			Vector3(3.2, 0, 17.8), Vector3(-2.5, 0, -16.2),
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
