class_name Maps
extends RefCounted
## Map registry: scene, spawns and menu camera per map. main.gd loads the scene under World;
## the server tells joiners which one (Game.sync_match_config). Ids go over the wire as Strings.
## Blue (team 0) spawns at +Z and faces -Z; Orange at -Z faces +Z. FFA spawns face the map centre.

const DEFAULT := &"townhouses"
const ORDER: Array[StringName] = [&"townhouses", &"foundry", &"rooftops", &"quay", &"skyline"]

const INFO := {
	&"townhouses": {
		"name": "Townhouses",
		"blurb": "A canal street: surf the canal houses' roofs, wallrun the quays, grapple the drawbridge.",
		# The canal floor is at -3 m: the void plane sits under it.
		"kill_y": -6.0,
		# v2 (tools/gen_townhouses.py): the back alleys and the drawbridge.
		"pickups": [
			{"type": &"knives", "pos": Vector3(-28.0, 0.0, 2.0)},
			{"type": &"heal", "pos": Vector3(28.0, 0.0, -2.0)},
			{"type": &"shield", "pos": Vector3(0.0, 0.0, 0.0)},
		],
		"scene": "res://scenes/maps/townhouses.tscn",
		"menu_cam": [Vector3(40, 30, 60), Vector3(0, 2, 0)],
		# Behind the spawn wall (|x| <= 10, z 41): three rows of four.
		"team_spawns": [
			[Vector3(-7.5, 0, 43), Vector3(-2.5, 0, 43), Vector3(2.5, 0, 43), Vector3(7.5, 0, 43), Vector3(-7.5, 0, 45), Vector3(-2.5, 0, 45), Vector3(2.5, 0, 45), Vector3(7.5, 0, 45), Vector3(-7.5, 0, 47), Vector3(-2.5, 0, 47), Vector3(2.5, 0, 47), Vector3(7.5, 0, 47)],
			[Vector3(7.5, 0, -43), Vector3(2.5, 0, -43), Vector3(-2.5, 0, -43), Vector3(-7.5, 0, -43), Vector3(7.5, 0, -45), Vector3(2.5, 0, -45), Vector3(-2.5, 0, -45), Vector3(-7.5, 0, -45), Vector3(7.5, 0, -47), Vector3(2.5, 0, -47), Vector3(-2.5, 0, -47), Vector3(-7.5, 0, -47)],
		],
		# Half-turn pairs: yards, quays, alleys, the canal, the roof decks, the plain roofs.
		"ffa_spawns": [
			Vector3(-14, 0, 44), Vector3(14, 0, -44),
			Vector3(8, 0, 4), Vector3(-8, 0, -4),
			Vector3(-28, 0, 14), Vector3(28, 0, -14),
			Vector3(0, -3, 26), Vector3(0, -3, -26),
			Vector3(-17, 9, 37), Vector3(17, 9, -37),
			Vector3(-17, 6, -24), Vector3(17, 6, 24),
			Vector3(28, 0, 30), Vector3(-28, 0, -30),
		],
	},
	&"foundry": {
		"name": "Foundry",
		"blurb": "Rust hall with a roof to fight on, ore bunkers with surfs down the walls, crane runways to grapple.",
		"kill_y": -4.0,
		# v2 (tools/gen_foundry.py): the flank lanes either side of the hall, and the hall floor under
		# the skylight.
		"pickups": [
			{"type": &"knives", "pos": Vector3(-26.0, 0.0, -9.5)},
			{"type": &"heal", "pos": Vector3(26.0, 0.0, 9.5)},
			{"type": &"shield", "pos": Vector3(0.0, 0.0, -5.0)},
		],
		"scene": "res://scenes/maps/foundry.tscn",
		"menu_cam": [Vector3(44, 38, 62), Vector3(0, 3, 0)],
		# Behind the spawn wall (|x| <= 10, z 37.5): two rows on the floor and one on the dock (1.2 m).
		"team_spawns": [
			[Vector3(-7.5, 0, 39.6), Vector3(-2.5, 0, 39.6), Vector3(2.5, 0, 39.6), Vector3(7.5, 0, 39.6), Vector3(-7.5, 0, 41.8), Vector3(-2.5, 0, 41.8), Vector3(2.5, 0, 41.8), Vector3(7.5, 0, 41.8), Vector3(-7.5, 1.2, 44), Vector3(-2.5, 1.2, 44), Vector3(2.5, 1.2, 44), Vector3(7.5, 1.2, 44)],
			[Vector3(7.5, 0, -39.6), Vector3(2.5, 0, -39.6), Vector3(-2.5, 0, -39.6), Vector3(-7.5, 0, -39.6), Vector3(7.5, 0, -41.8), Vector3(2.5, 0, -41.8), Vector3(-2.5, 0, -41.8), Vector3(-7.5, 0, -41.8), Vector3(7.5, 1.2, -44), Vector3(2.5, 1.2, -44), Vector3(-2.5, 1.2, -44), Vector3(-7.5, 1.2, -44)],
		],
		# Half-turn pairs: docks, flanks, the hall floor, its roof, the bunker tops, the yard.
		"ffa_spawns": [
			Vector3(-5, 1.2, 44), Vector3(5, 1.2, -44),
			Vector3(-26, 0, 2), Vector3(26, 0, -2),
			Vector3(-8, 0, 22), Vector3(8, 0, -22),
			Vector3(6, 7.3, -8), Vector3(-6, 7.3, 8),
			Vector3(-27, 10, 31), Vector3(27, 10, -31),
			Vector3(18, 0, 28), Vector3(-18, 0, -28),
			Vector3(5, 0, 5), Vector3(-5, 0, -5),
		],
	},
	&"rooftops": {
		"name": "Rooftops",
		"blurb": "Two roofed blocks, a court, flank surfs, and skybridges at roof height.",
		"kill_y": -4.0,
		"pickups": [
			{"type": &"knives", "pos": Vector3(-24.0, 0.0, 0.0)},
			{"type": &"heal", "pos": Vector3(24.0, 0.0, 0.0)},
			{"type": &"shield", "pos": Vector3(0.0, 0.0, 9.5)},
		],
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
		"blurb": "Dry dock with surfs, harbour offices, a crane, and screened roofs.",
		"kill_y": -4.0,
		"pickups": [
			{"type": &"knives", "pos": Vector3(-30.0, 4.0, 0.0)},
			{"type": &"heal", "pos": Vector3(30.0, 4.0, 0.0)},
			{"type": &"shield", "pos": Vector3(0.0, 0.0, 18.0)},
		],
		"scene": "res://scenes/maps/quay.tscn",
		"menu_cam": [Vector3(48, 42, 86), Vector3(0, 4, 0)],
		# Two rows of six in the yard, all behind the 3.2 m spawn wall (x -16..16, z 54.6..55.3).
		# The corners past the baffles are solid now, so nobody spawns out there.
		"team_spawns": [
			[Vector3(-13, 0, 57.4), Vector3(-7.8, 0, 57.4), Vector3(-2.6, 0, 57.4), Vector3(2.6, 0, 57.4), Vector3(7.8, 0, 57.4), Vector3(13, 0, 57.4), Vector3(-13, 0, 60.2), Vector3(-7.8, 0, 60.2), Vector3(-2.6, 0, 60.2), Vector3(2.6, 0, 60.2), Vector3(7.8, 0, 60.2), Vector3(13, 0, 60.2)],
			[Vector3(13, 0, -57.4), Vector3(7.8, 0, -57.4), Vector3(2.6, 0, -57.4), Vector3(-2.6, 0, -57.4), Vector3(-7.8, 0, -57.4), Vector3(-13, 0, -57.4), Vector3(13, 0, -60.2), Vector3(7.8, 0, -60.2), Vector3(2.6, 0, -60.2), Vector3(-2.6, 0, -60.2), Vector3(-7.8, 0, -60.2), Vector3(-13, 0, -60.2)],
		],
		# #160 CTF: one flag per team on that team's office roof (y 10, the roof nearest its yard), in the
		# open part of the roof south/north of both stairwells. Half-turn pair like the spawns.
		"flag_bases": [Vector3(-24, 10, 32), Vector3(24, 10, -32)],
		# Half-turn pairs. Yard, side-lane ground, quay deck beside the office, dock, roofs, balconies.
		"ffa_spawns": [
			Vector3(-26, 0, 58), Vector3(0, 0, 57), Vector3(26, 0, 58),
			Vector3(26, 0, -58), Vector3(0, 0, -57), Vector3(-26, 0, -58),
			Vector3(-38, 0, -47), Vector3(38, 0, 47),
			Vector3(-36.5, 4, -6), Vector3(36.5, 4, 6),
			Vector3(0, 0, 5), Vector3(0, 0, -5),
			Vector3(-24, 10, 38), Vector3(24, 10, -38),
			Vector3(24, 10, 26), Vector3(-24, 10, -26),
			Vector3(-8, 0, 6), Vector3(8, 0, -6),
		],
	},
	&"skyline": {
		"name": "Skyline",
		"blurb": "City rooftops from 4 to 15 m: a 10 m surf ridge, a wallrun alley, stairs and a tower stairwell.",
		"kill_y": -3.0,
		"pickups": [
			{"type": &"knives", "pos": Vector3(-25.0, 4.0, -1.0)},
			{"type": &"heal", "pos": Vector3(25.0, 4.0, 1.0)},
			{"type": &"shield", "pos": Vector3(5.0, 6.0, -6.0)},
		],
		"scene": "res://scenes/maps/skyline.tscn",
		"menu_cam": [Vector3(46, 40, 66), Vector3(0, 6, 0)],
		# Spawn roof at y 12 (x -16..16, z 36..46), behind the baffles and the jog. Half-turn for Orange.
		"team_spawns": [
			[Vector3(-13, 12, 40), Vector3(-8, 12, 40), Vector3(-3.4, 12, 40), Vector3(3.4, 12, 40), Vector3(8, 12, 40), Vector3(13, 12, 40), Vector3(-13, 12, 43.4), Vector3(-8, 12, 43.4), Vector3(-3.4, 12, 43.4), Vector3(3.4, 12, 43.4), Vector3(8, 12, 43.4), Vector3(13, 12, 43.4)],
			[Vector3(13, 12, -40), Vector3(8, 12, -40), Vector3(3.4, 12, -40), Vector3(-3.4, 12, -40), Vector3(-8, 12, -40), Vector3(-13, 12, -40), Vector3(13, 12, -43.4), Vector3(8, 12, -43.4), Vector3(3.4, 12, -43.4), Vector3(-3.4, 12, -43.4), Vector3(-8, 12, -43.4), Vector3(-13, 12, -43.4)],
		],
		# Half-turn pairs: spawn roofs, WA, WB, WM/EM, EA perch, EB, Mid, tower roof, tower room.
		"ffa_spawns": [
			Vector3(-13, 12, 41), Vector3(13, 12, -41),
			Vector3(-24.5, 9, 39), Vector3(24.5, 9, -39),
			Vector3(-22, 6, 12), Vector3(22, 6, -12),
			Vector3(-25, 4, -1), Vector3(25, 4, 1),
			Vector3(22, 15, 33), Vector3(-22, 15, -33),
			Vector3(26, 9, 9.2), Vector3(-26, 9, -9.2),
			Vector3(4, 6, 8), Vector3(-4, 6, -8),
			Vector3(-1, 12, 28.5), Vector3(1, 12, -28.5),
			Vector3(2, 6, 23), Vector3(-2, 6, -23),
			Vector3(-20, 6, 18), Vector3(20, 6, -18),
			Vector3(25, 15, 31), Vector3(-25, 15, -31),
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


## #160: [blue base, orange base] for CTF, or [] when the map has no flag markers yet.
## Pickup pads (#144): [{type, pos}]. Townhouses first, per the spec: knives and heal on the mid
## plaza, shield on a flank that both teams have to contest.
static func pickups(id: StringName) -> Array:
	return info(id).get("pickups", [])


static func flag_bases(id: StringName) -> Array:
	return info(id).get("flag_bases", [])


static func ffa_spawns(id: StringName) -> Array:
	return info(id).ffa_spawns


## Y under which a pawn has left the map. A scene may override this with metadata kill_y
## (Skyline does, and the number here matches that override).
static func kill_y(id: StringName) -> float:
	return float(info(id).get("kill_y", -INF))


## Yaw that faces the map centre from `pos` (FFA), or the team's forward.
static func spawn_yaw(pos: Vector3, team: int, ffa: bool) -> float:
	if ffa:
		var to := -Vector3(pos.x, 0, pos.z)
		if to.length_squared() < 0.01:
			return 0.0
		return atan2(-to.x, -to.z)
	return PI if team == 1 else 0.0
