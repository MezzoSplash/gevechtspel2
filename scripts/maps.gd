class_name Maps
extends RefCounted
## Map registry: scene, spawns and menu camera per map. main.gd loads the scene under World;
## the server tells joiners which one (Game.sync_match_config). Ids go over the wire as Strings.
## Blue (team 0) spawns at +Z and faces -Z; Orange at -Z faces +Z. FFA spawns face the map centre.

const DEFAULT := &"townhouses"
const ORDER: Array[StringName] = [&"townhouses", &"foundry", &"rooftops", &"quay"]

const INFO := {
	&"townhouses": {
		"name": "Townhouses",
		"blurb": "Two rows of houses, a street with a bus, backyards and flanks.",
		"scene": "res://scenes/maps/townhouses.tscn",
		"menu_cam": [Vector3(26, 24, 62), Vector3(0, 2, 0)],
		# Two rows in the backyard, past the wings (they end at z=33.5) and short of the south wall (z=41).
		# Twelve points so 16 bots do not share a spot.
		"team_spawns": [
			[Vector3(-23, 0, 34.8), Vector3(-15, 0, 34.8), Vector3(-7, 0, 34.8), Vector3(1, 0, 34.8), Vector3(9, 0, 34.8), Vector3(17, 0, 34.8), Vector3(-19, 0, 38.6), Vector3(-11, 0, 38.6), Vector3(-3, 0, 38.6), Vector3(5, 0, 38.6), Vector3(13, 0, 38.6), Vector3(21, 0, 38.6)],
			[Vector3(-23, 0, -34.8), Vector3(-15, 0, -34.8), Vector3(-7, 0, -34.8), Vector3(1, 0, -34.8), Vector3(9, 0, -34.8), Vector3(17, 0, -34.8), Vector3(-19, 0, -38.6), Vector3(-11, 0, -38.6), Vector3(-3, 0, -38.6), Vector3(5, 0, -38.6), Vector3(13, 0, -38.6), Vector3(21, 0, -38.6)],
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
		# One row on the floor in front of the dock (dock face z=30.6, spawn wall ends z=24.5).
		# Not on the dock: that slab is 1.2 m high. Twelve points so 16 bots do not share a spot.
		"team_spawns": [
			[Vector3(-24.2, 0, 27.5), Vector3(-19.8, 0, 27.5), Vector3(-15.4, 0, 27.5), Vector3(-11, 0, 27.5), Vector3(-6.6, 0, 27.5), Vector3(-2.2, 0, 27.5), Vector3(2.2, 0, 27.5), Vector3(6.6, 0, 27.5), Vector3(11, 0, 27.5), Vector3(15.4, 0, 27.5), Vector3(19.8, 0, 27.5), Vector3(24.2, 0, 27.5)],
			[Vector3(-24.2, 0, -27.5), Vector3(-19.8, 0, -27.5), Vector3(-15.4, 0, -27.5), Vector3(-11, 0, -27.5), Vector3(-6.6, 0, -27.5), Vector3(-2.2, 0, -27.5), Vector3(2.2, 0, -27.5), Vector3(6.6, 0, -27.5), Vector3(11, 0, -27.5), Vector3(15.4, 0, -27.5), Vector3(19.8, 0, -27.5), Vector3(24.2, 0, -27.5)],
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
		# Two rows behind the spawn wall (ends z=31). The truck sits at z 33.2–36.4, the crates beside it.
		# Twelve points so 16 bots do not share a spot. Not on the surf or the roof.
		"team_spawns": [
			[Vector3(-24, 0, 32.6), Vector3(-15, 0, 32.6), Vector3(-6, 0, 32.6), Vector3(3, 0, 32.6), Vector3(12, 0, 32.6), Vector3(21, 0, 32.6), Vector3(-20, 0, 38.2), Vector3(-11, 0, 38.2), Vector3(-2, 0, 38.2), Vector3(6, 0, 38.2), Vector3(14, 0, 38.2), Vector3(23, 0, 38.2)],
			[Vector3(-24, 0, -32.6), Vector3(-15, 0, -32.6), Vector3(-6, 0, -32.6), Vector3(3, 0, -32.6), Vector3(12, 0, -32.6), Vector3(21, 0, -32.6), Vector3(-20, 0, -38.2), Vector3(-11, 0, -38.2), Vector3(-2, 0, -38.2), Vector3(6, 0, -38.2), Vector3(14, 0, -38.2), Vector3(23, 0, -38.2)],
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
	&"quay": {
		"name": "Quay",
		"blurb": "Dry dock with a high quay, downhill surfs, and a curved corner.",
		"scene": "res://scenes/maps/quay.tscn",
		"menu_cam": [Vector3(48, 42, 86), Vector3(0, 4, 0)],
		# One row behind the trucks (they end at z=59), short of the south wall (inner face z=61.2).
		# Twelve points so 16 bots, or a team stacked with humans, do not share a spot.
		"team_spawns": [
			[Vector3(-39, 0, 59.9), Vector3(-32, 0, 59.9), Vector3(-25, 0, 59.9), Vector3(-18, 0, 59.9), Vector3(-11, 0, 59.9), Vector3(-4, 0, 59.9), Vector3(4, 0, 59.9), Vector3(11, 0, 59.9), Vector3(18, 0, 59.9), Vector3(25, 0, 59.9), Vector3(32, 0, 59.9), Vector3(39, 0, 59.9)],
			[Vector3(39, 0, -59.9), Vector3(32, 0, -59.9), Vector3(25, 0, -59.9), Vector3(18, 0, -59.9), Vector3(11, 0, -59.9), Vector3(4, 0, -59.9), Vector3(-4, 0, -59.9), Vector3(-11, 0, -59.9), Vector3(-18, 0, -59.9), Vector3(-25, 0, -59.9), Vector3(-32, 0, -59.9), Vector3(-39, 0, -59.9)],
		],
		"ffa_spawns": [
			Vector3(-33, 0, 57.6), Vector3(0, 0, 56.6), Vector3(33, 0, 57.4),
			Vector3(33, 0, -57.6), Vector3(0, 0, -56.6), Vector3(-33, 0, -57.4),
			Vector3(-26, 4, 0), Vector3(26, 4, 0),
			Vector3(0, 0, 10), Vector3(0, 0, -12),
			Vector3(-24, 10, 38), Vector3(24, 10, -38),
			Vector3(24, 10, 26), Vector3(-8, 0, 6),
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
