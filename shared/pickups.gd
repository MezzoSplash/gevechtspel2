class_name Pickups
extends RefCounted
## Map pickups (#144). Server-authoritative, like every other piece of match state: only the match
## authority decides that a pickup was taken, applies the effect and tells the clients.
##
## Spec v1 (issue #144): three types on one map. Extra Messen, Schildplaat, Herstelkern. No movement
## pickups - the dive boost is already heavy enough.
##
## State is one array of dictionaries, one per pickup: {id, type, pos, ready, timer}. `timer` counts the
## time left on a respawn, so both sides can draw the fill (clients get it from sync_pickup_state).

const TOUCH_RADIUS := 1.2
const TOUCH_HEIGHT := 1.2
const ARMOUR := 40.0 # Schildplaat: at least this much armour, never stacked higher
const HEAL := 45.0 # Herstelkern
const KNIVES := 2 # Extra Messen
const KNIFE_CAP := 3

## Colour is never team blue/orange and never cyan/teal (spec).
const TYPES := {
	&"knives": {"label": "EXTRA MESSEN", "color": Color(0.72, 0.30, 1.0), "respawn": 20.0, "pitch": 1.15},
	&"shield": {"label": "SCHILDPLAAT", "color": Color(0.95, 0.94, 0.90), "respawn": 28.0, "pitch": 0.95},
	&"heal": {"label": "HERSTELKERN", "color": Color(0.66, 0.92, 0.25), "respawn": 22.0, "pitch": 1.35},
}

static var state: Array[Dictionary] = []
static var nodes: Array[Node] = []


static func type_info(t: StringName) -> Dictionary:
	return TYPES.get(t, TYPES[&"heal"])


## Build the pickups for `map_id` under `parent` (the loaded map node) and reset the authority state.
static func setup(game, parent: Node, map_id: StringName) -> void:
	clear()
	var defs: Array = Maps.pickups(map_id)
	for i in defs.size():
		var d: Dictionary = defs[i]
		var t := StringName(d.get("type", "heal"))
		var pos: Vector3 = d.get("pos", Vector3.ZERO)
		state.append({"id": i, "type": t, "pos": pos, "ready": true, "timer": 0.0})
		if parent == null:
			continue
		var node := Pickup.new()
		node.name = "Pickup%d" % i
		node.pickup_id = i
		parent.add_child(node)
		node.global_position = pos
		node.setup(t)
		nodes.append(node)
	game.pickup_state_changed.emit()


## Drop the nodes (map change, match reset).
static func clear() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	state.clear()


static func find(pickup_id: int) -> Dictionary:
	for p in state:
		if int(p["id"]) == pickup_id:
			return p
	return {}


static func node_for(pickup_id: int) -> Node:
	for n in nodes:
		if is_instance_valid(n) and int(n.pickup_id) == pickup_id:
			return n
	return null


## Authority only, every physics tick: respawn timers, then who is standing on what.
static func tick(game, delta: float) -> void:
	if not game._is_match_authority():
		return
	for p in state:
		if not bool(p["ready"]):
			p["timer"] = maxf(float(p["timer"]) - delta, 0.0)
			if float(p["timer"]) <= 0.0:
				p["ready"] = true
				game.sync_pickup_state.rpc(int(p["id"]), true, 0.0)
				game.pickup_state_changed.emit()
				continue
		var at: Vector3 = p["pos"]
		for n in game.get_tree().get_nodes_in_group("player"):
			var pl := n as Player
			if pl == null or pl.is_dead or pl.is_queued_for_deletion():
				continue
			if not _in_touch(pl.global_position, at):
				continue
			if not apply(game, pl, StringName(p["type"])):
				continue # nothing it could do: the pickup stays on the floor
			_take(game, p, pl)
			break


static func _in_touch(pos: Vector3, centre: Vector3) -> bool:
	var d := Vector2(pos.x - centre.x, pos.z - centre.z)
	return d.length() <= TOUCH_RADIUS and absf(pos.y - centre.y) <= TOUCH_HEIGHT


static func _take(game, p: Dictionary, pl: Player) -> void:
	p["ready"] = false
	p["timer"] = float(type_info(StringName(p["type"]))["respawn"])
	game.sync_pickup_taken.rpc(int(p["id"]), pl.peer_id, StringName(p["type"]))
	game.pickup_state_changed.emit()


## The effect itself. Returns false when it would change nothing (full HP, full knives, armour cap),
## because the spec says the pickup then stays where it is.
static func apply(game, pl: Player, t: StringName) -> bool:
	match t:
		&"knives":
			if pl.knives >= KNIFE_CAP:
				return false
			pl.knives = mini(pl.knives + KNIVES, KNIFE_CAP)
			pl._notify_grenades()
			if game.is_networked():
				game.sync_knife_count.rpc(pl.peer_id, pl.knives)
			return true
		&"shield":
			if pl.armour >= ARMOUR:
				return false
			pl.set_armour(ARMOUR)
			# The pawn that took it can be a remote one: the armour has to reach that machine's HUD.
			if game.is_networked():
				game.sync_vitals.rpc(pl.peer_id, game.hp_of(pl), pl.armour)
			return true
		&"heal":
			var hp: float = game.hp_of(pl)
			if hp >= Player.MAX_HP:
				return false
			game.set_hp(pl, minf(hp + HEAL, Player.MAX_HP))
			pl.apply_heal_visual(float(game.hp_of(pl)))
			if game.is_networked():
				game.sync_vitals.rpc(pl.peer_id, game.hp_of(pl), pl.armour)
			return true
	return false


## A peer joined mid-match: hand it the current pad state, or it draws a taken pad as full until the
## next respawn (#246 review). Same channel and order as the match config, so the pads exist first.
static func sync_to_peer(game, peer_id: int) -> void:
	for p in state:
		game.sync_pickup_state.rpc_id(peer_id, int(p["id"]), bool(p["ready"]), float(p["timer"]))


## Client side: a pickup is gone (or back). Called from the RPCs on GameState.
static func on_taken(game, pickup_id: int, type: StringName) -> void:
	var p := find(pickup_id)
	if p.is_empty():
		return
	p["ready"] = false
	p["timer"] = float(type_info(type)["respawn"])
	var n := node_for(pickup_id)
	if n:
		n.set_taken(float(type_info(type)["respawn"]))
	game.pickup_state_changed.emit()


static func on_state(game, pickup_id: int, ready: bool, timer: float) -> void:
	var p := find(pickup_id)
	if p.is_empty():
		return
	p["ready"] = ready
	p["timer"] = timer
	var n := node_for(pickup_id)
	if n:
		if ready:
			n.set_ready()
		else:
			n.set_taken(timer)
	game.pickup_state_changed.emit()
