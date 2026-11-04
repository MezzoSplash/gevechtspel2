class_name LagComp
extends RefCounted
## Server-side lag compensation for hitscan shots (#105).
##
## The server keeps ~1 s of player transforms (one sample per physics tick). When a client's shot
## arrives, each ray is tested against the targets where that client saw them (offsets_for +
## intersect_ray); the bodies themselves never move. The rewind is clamped so a lying client cannot
## reach further back than that peer's measured round trip (#140). Static helpers on the Game autoload; the RPC stays in game.gd.

## How much history to keep per player.
const HISTORY_MS := 1000
## Hard cap on how far back a shot may rewind, plus the snapshot interpolation allowance.
## 300 ms covers a real ~250 ms RTT. History is already ~1 s (#140).
const MAX_REWIND_MS := 300
const INTERP_MS := 50


## Server clock used for history and shot stamps (ms since the server started).
static func now_ms() -> int:
	return Time.get_ticks_msec()


## Server, every physics tick: append each live player's transform and drop samples older than HISTORY_MS.
static func record(game: GameState) -> void:
	var t := now_ms()
	var kept: Dictionary = {} # rebuilt each tick, so freed players drop out on their own
	for n in game.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null:
			continue
		var hist: Array = game._lag_history.get(p.get_instance_id(), [])
		hist.append({"t": t, "x": p.global_transform, "dead": p.is_dead})
		while hist.size() > 1 and t - int(hist[0].t) > HISTORY_MS:
			hist.pop_front()
		kept[p.get_instance_id()] = hist
	game._lag_history = kept


## Client: the server time of the world this machine is showing now (0 until the first stamp).
## Remote pawns arrive about one trip late, so the last server stamp plus local time since is close.
static func view_ms(game: GameState) -> int:
	if game._server_clock_offset == 0:
		return 0
	return maxi(now_ms() + game._server_clock_offset, 1)


## Client: remember the server stamp that came with sync_pings.
static func note_server_time(game: GameState, server_ms: int) -> void:
	if server_ms > 0:
		game._server_clock_offset = server_ms - now_ms()


## How many ms to rewind for a shot the client stamped with `view_ms` (its estimate of the server
## time it was looking at). 0 = no stamp: fall back to the peer's measured round trip.
## A stamp older than that round trip is ignored past the trip plus interpolation, so claiming
## an ancient view_ms does not rewind further than the peer's real lag. No sample yet: the absolute cap.
static func rewind_ms_for(game: GameState, peer: int, view_ms: int) -> int:
	var back := now_ms() - view_ms if view_ms > 0 else int(game.pings.get(peer, 0))
	var cap := MAX_REWIND_MS + INTERP_MS
	var rtt := int(game.pings.get(peer, 0))
	if rtt > 0:
		cap = mini(cap, rtt + INTERP_MS)
	return clampi(back, 0, cap)


## Transform `p` had `back_ms` ago, interpolated between samples. Null when there is no usable sample.
static func transform_at(game: GameState, p: Player, back_ms: int) -> Variant:
	var hist: Array = game._lag_history.get(p.get_instance_id(), [])
	if hist.is_empty():
		return null
	var t := now_ms() - back_ms
	if t <= int(hist[0].t):
		return null if hist[0].dead else hist[0].x
	for i in range(hist.size() - 1, -1, -1):
		var a: Dictionary = hist[i]
		if int(a.t) > t:
			continue
		if a.dead:
			return null
		if i == hist.size() - 1:
			return a.x
		var b: Dictionary = hist[i + 1]
		var span := float(int(b.t) - int(a.t))
		var w := 0.0 if span <= 0.0 else float(t - int(a.t)) / span
		return (a.x as Transform3D).interpolate_with(b.x, w)
	return null


## Per-target offsets for a shot rewound `back_ms`: [{p, rid, delta}] with delta = now - then.
## Bodies are NOT moved: the physics server only applies a kinematic body's new transform at the next
## step, so instead each ray is shifted by the target's delta (see intersect_ray). Empty = no rewind.
static func offsets_for(game: GameState, shooter: Player, back_ms: int) -> Array:
	var out: Array = []
	if back_ms <= 0:
		return out
	for n in game.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p == shooter or p.is_dead:
			continue
		var past: Variant = transform_at(game, p, back_ms)
		if past == null:
			continue
		var delta := p.global_position - (past as Transform3D).origin
		if delta.length_squared() > 0.000001:
			out.append({"p": p, "rid": p.get_rid(), "delta": delta})
	return out


## Like space.intersect_ray(query), but rewound targets are hit where they were: the world and the
## other players use the plain ray, each rewound target gets the ray shifted by its delta, and the
## nearest hit wins. The hit position is moved back into the rewound frame; `rewind_delta` maps it onto the body now. Capsules only translate
## here (yaw does not change a capsule), so this matches moving the bodies back.
static func intersect_ray(space: PhysicsDirectSpaceState3D, query: PhysicsRayQueryParameters3D, offsets: Array) -> Dictionary:
	if offsets.is_empty():
		return space.intersect_ray(query)
	var from := query.from
	var to := query.to
	var base_exclude: Array[RID] = query.exclude
	var rewound: Array[RID] = []
	for o in offsets:
		rewound.append(o.rid)
	var plain := PhysicsRayQueryParameters3D.create(from, to, query.collision_mask, base_exclude + rewound)
	var best := space.intersect_ray(plain)
	var best_d := INF if best.is_empty() else from.distance_to(best.position)
	for o in offsets:
		var others: Array[RID] = base_exclude.duplicate()
		for r in rewound:
			if r != o.rid:
				others.append(r)
		var d3: Vector3 = o.delta
		var q := PhysicsRayQueryParameters3D.create(from + d3, to + d3, query.collision_mask & 2, others)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider != o.p:
			continue
		hit.position -= d3
		hit.rewind_delta = d3 # the same point on the body as it is now (Combat.apply_shot_hit)
		var d := from.distance_to(hit.position)
		if d < best_d:
			best = hit
			best_d = d
	return best
