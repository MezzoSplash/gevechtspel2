class_name CTF
extends RefCounted
## Capture the Flag (#160). Two teams, a flag on each base (Maps "flag_bases"). Touch the enemy flag to
## take it, bring it to your own base while your flag is home to capture. A carrier who dies drops it;
## a teammate touching your dropped flag returns it, else it goes home after RETURN_TIME.
## Static helpers on the Game autoload `g`; Game keeps `flags` / `ctf_caps` and the @rpcs (sync_flags,
## sync_flag_event). Match authority only decides; clients mirror for visuals and the HUD.

const CAPTURES_TO_WIN := 3
const RETURN_TIME := 20.0 # s a dropped flag lies before it goes home by itself
const KILL_Y := -15.0 # a flag dropped below this (fell off the map) goes home at once
const TEAM_NAMES := ["BLUE", "ORANGE"]


## The map has both flag bases, so CTF can be played there.
static func available(map_id: StringName) -> bool:
	return Maps.flag_bases(map_id).size() == 2


## Every machine: fresh flags on the current map's bases, captures 0-0.
static func setup(g: Node) -> void:
	var bases := Maps.flag_bases(g.map_id)
	g.flags = []
	for t in 2:
		g.flags.append(Objective.make(bases[t] if bases.size() == 2 else Vector3.ZERO))
	g.ctf_caps = [0, 0]


## Authority: reset the flags for a new round and tell everyone.
static func reset(g: Node) -> void:
	setup(g)
	_broadcast(g)


## Authority, every physics tick while the round runs: carriers, drops, returns, pickups, captures.
static func tick(g: Node, delta: float) -> void:
	if not g.is_ctf() or not g._is_match_authority() or g.flags.size() != 2:
		return
	if not g._round_active or g.play_locked():
		return
	var dirty := false
	for t in 2:
		var f: Dictionary = g.flags[t]
		if int(f.state) == Objective.CARRIED:
			var c: Player = g.player_for_peer(int(f.carrier))
			if c == null or c.is_dead:
				var at: Vector3 = f.pos if c == null else c.global_position
				var by := int(f.carrier)
				Objective.drop(f, at, RETURN_TIME)
				if at.y < KILL_Y:
					Objective.send_home(f)
					_event(g, "returned", t, 0)
				else:
					_event(g, "dropped", t, by)
				dirty = true
			else:
				f.pos = c.global_position
		elif int(f.state) == Objective.DROPPED:
			if Objective.tick(f, delta):
				_event(g, "returned", t, 0)
				dirty = true
	for n in g.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead or p.team_id < 0 or p.team_id > 1:
			continue
		var own: Dictionary = g.flags[p.team_id]
		var enemy: Dictionary = g.flags[1 - p.team_id]
		var at := p.global_position
		if int(enemy.state) != Objective.CARRIED and Objective.in_zone(at, enemy.pos):
			Objective.pick_up(enemy, p.peer_id)
			_event(g, "taken", 1 - p.team_id, p.peer_id)
			dirty = true
		if int(own.state) == Objective.DROPPED and Objective.in_zone(at, own.pos):
			Objective.send_home(own)
			_event(g, "returned", p.team_id, p.peer_id)
			dirty = true
		if int(enemy.carrier) == p.peer_id and int(own.state) == Objective.AT_HOME and Objective.in_zone(at, own.home):
			Objective.send_home(enemy)
			_capture(g, p.team_id, p.peer_id)
			dirty = true
	if dirty:
		_broadcast(g)


## Authority: a capture scores for `team`; reaching CAPTURES_TO_WIN ends the round.
static func _capture(g: Node, team: int, peer: int) -> void:
	g.ctf_caps[team] = int(g.ctf_caps[team]) + 1
	if g.scores.has(peer):
		g.scores[peer]["captures"] = int(g.scores[peer].get("captures", 0)) + 1
	_event(g, "captured", 1 - team, peer)
	if int(g.ctf_caps[team]) >= CAPTURES_TO_WIN and g._round_active:
		_broadcast(g) # the final score must reach clients before the round-end screen
		g._end_round_team(team)


## Flag `team`'s event (taken / dropped / returned / captured) by `peer` (0: nobody, e.g. timer).
static func _event(g: Node, kind: String, team: int, peer: int) -> void:
	g._apply_flag_event(kind, team, peer)
	if g.is_networked():
		g.sync_flag_event.rpc(kind, team, peer)


static func _broadcast(g: Node) -> void:
	var packed := [Objective.pack(g.flags[0]), Objective.pack(g.flags[1])]
	g._apply_flags(packed, int(g.ctf_caps[0]), int(g.ctf_caps[1]))
	if g.is_networked():
		g.sync_flags.rpc(packed, int(g.ctf_caps[0]), int(g.ctf_caps[1]))


## Late joiner: the current flags and score.
static func send_to(g: Node, peer: int) -> void:
	if g.is_ctf() and g.flags.size() == 2:
		g.sync_flags.rpc_id(peer, [Objective.pack(g.flags[0]), Objective.pack(g.flags[1])], int(g.ctf_caps[0]), int(g.ctf_caps[1]))


## Where a flag is in the world right now (on its carrier's back when carried, if we know the pawn).
static func flag_world_pos(g: Node, team: int) -> Vector3:
	var f: Dictionary = g.flags[team]
	if int(f.state) == Objective.CARRIED:
		var c: Player = g.player_for_peer(int(f.carrier))
		if c:
			return c.global_position
	return f.pos


## Bots: where to walk when nobody is in sight. Carrier → home; own flag lying around → return it;
## else even peers attack the enemy flag, odd peers guard their base. Vector3.INF: no CTF goal.
static func bot_goal(g: Node, p: Player) -> Vector3:
	if not g.is_ctf() or g.flags.size() != 2 or p.team_id < 0 or p.team_id > 1:
		return Vector3.INF
	var own: Dictionary = g.flags[p.team_id]
	var enemy: Dictionary = g.flags[1 - p.team_id]
	if int(enemy.carrier) == p.peer_id:
		return own.home
	if int(own.state) == Objective.DROPPED:
		return own.pos
	if int(own.state) == Objective.CARRIED:
		return flag_world_pos(g, p.team_id) # chase the thief
	if absi(p.peer_id) % 2 == 0:
		return flag_world_pos(g, 1 - p.team_id)
	return own.home


## HUD: one line about a flag, e.g. "BLUE FLAG: HOME", "TAKEN BY Bob", "DROPPED 12s".
static func status_text(g: Node, team: int) -> String:
	if g.flags.size() != 2:
		return ""
	var f: Dictionary = g.flags[team]
	match int(f.state):
		Objective.CARRIED:
			return "%s FLAG: TAKEN BY %s" % [TEAM_NAMES[team], g._display_name_for(int(f.carrier))]
		Objective.DROPPED:
			return "%s FLAG: DROPPED %ds" % [TEAM_NAMES[team], ceili(float(f.drop_t))]
	return "%s FLAG: HOME" % TEAM_NAMES[team]
