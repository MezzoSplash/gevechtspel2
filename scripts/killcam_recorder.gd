class_name KillcamRecorder
extends RefCounted
## The recording side of the killcam (#317-vervolg, uit scripts/killcam.gd): the notes that come in
## during a match, the 30 Hz snapshot of every pawn, and the slice of that history a death turns into.
## Static on the Killcam node; the buffers (_frames, _events, _clips, ...) stay on Killcam and this is
## called with the node as `k`.


## Not while the dedicated server runs (nobody watches), not in the lobby, and not while a replay plays.
static func should_record(k: Killcam) -> bool:
	return not Game.is_dedicated and not Game.in_lobby and not k._playing


static func note_fire(k: Killcam, peer_id: int, weapon_id: StringName) -> void:
	note(k, "fire", peer_id, weapon_id)


static func note_tracer(k: Killcam, peer_id: int, from: Vector3, to: Vector3, weapon_id: StringName) -> void:
	note(k, "tracer", peer_id, from, to, weapon_id)


static func note_hurt(k: Killcam, peer_id: int) -> void:
	note(k, "hurt", peer_id)


static func note_death(k: Killcam, peer_id: int) -> void:
	if should_record(k):
		k._pending_clips.append([peer_id, k._clock])
		if k._trick_wait.has(peer_id):
			var w: Array = k._trick_wait[peer_id]
			k._trick_wait.erase(peer_id)
			if k._clock - float(w[1]) <= Killcam.TRICK_WAIT_MAX:
				k._trick_deaths.append([int(w[0]), k._clock])
	note(k, "death", peer_id)


## Game._apply_trick: this kill is the round's new best trickshot. Its victim's death comes right after
## (same tick on the server, the next reliable message on clients).
static func note_trick(k: Killcam, trick_id: int, victim_peer_id: int) -> void:
	if not should_record(k):
		return
	# A new best replaces any older one still waiting: only the latest best is ever replayed.
	k._trick_wait.clear()
	for i in range(k._events.size() - 1, -1, -1):
		var e: Array = k._events[i]
		if k._clock - float(e[0]) > Killcam.TRICK_DEATH_BEFORE:
			break
		if e[1] == "death" and int(e[2]) == victim_peer_id:
			k._trick_deaths.append([trick_id, float(e[0])]) # the death was recorded first
			return
	k._trick_wait[victim_peer_id] = [trick_id, k._clock]


static func note_boom(k: Killcam, pos: Vector3, heavy := false) -> void:
	note(k, "boom", pos, heavy)


static func note(k: Killcam, kind: String, a: Variant = null, b: Variant = null, c: Variant = null, d: Variant = null) -> void:
	if not should_record(k):
		return
	k._events.append([k._clock, kind, a, b, c, d])


static func snapshot(k: Killcam) -> void:
	var pawns := {}
	for n in k.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_queued_for_deletion() or p.head == null:
			continue
		var wpn := p.weapon.armory_index() if p.weapon else 0
		# Index 7 is the body's roll flip (#205): the pose used to be yaw + head pitch only, so a
		# player who rolled to their death stood upright in the replay.
		pawns[p.peer_id] = [p.global_position, p.rotation.y, p.head.rotation.x, p.crouch, wpn, not p.is_dead, p.move_fx, p.roll_flip(), p.throw_amt(), p.reload_amt(), p.ads_amt, p.grappling, p.grapple_at]
		# 10 = ADS 0..1 (#381), 11/12 = the grapple's rope (#381). Frames recorded before those fields
		# existed simply have a shorter array: the replay plays them as hip and draws no rope.
		k._meta[p.peer_id] = [p.display_name, p.team_id]
	if pawns.is_empty():
		return
	var nades := PackedVector3Array()
	for g in k.get_tree().get_nodes_in_group("grenade"):
		var n3 := g as Node3D
		if n3 and n3.is_inside_tree() and not n3.is_queued_for_deletion():
			nades.append(n3.global_position)
	var knives: Array[Transform3D] = []
	for n in k.get_tree().get_nodes_in_group("knife"):
		var k3 := n as Node3D
		if k3 and k3.is_inside_tree() and not k3.is_queued_for_deletion():
			knives.append(k3.global_transform)
	k._frames.append([k._clock, pawns, nades, knives])


## LOOKBACK before to POST after the kill, plus a little margin for blending. The replay itself starts
## where the director says (#258), not at the front of this window.
static func slice(k: Killcam, t_kill: float) -> Dictionary:
	var t0 := t_kill - Killcam.LOOKBACK - 0.2
	var t1 := t_kill + Killcam.POST + 0.2
	var frames: Array = []
	for f in k._frames:
		if float(f[0]) >= t0 and float(f[0]) <= t1:
			frames.append(f)
	var events: Array = []
	for e in k._events:
		if float(e[0]) >= t_kill - Killcam.LOOKBACK and float(e[0]) <= t1:
			events.append(e)
	return {"t_kill": t_kill, "frames": frames, "events": events, "meta": k._meta.duplicate(true)}


## The victim's latest death still in the buffer, else the clip kept from their last death.
static func find_clip(k: Killcam, victim: int) -> Dictionary:
	for i in range(k._events.size() - 1, -1, -1):
		var e: Array = k._events[i]
		if e[1] == "death" and int(e[2]) == victim:
			return slice(k, float(e[0]))
	return k._clips.get(victim, {})


## The kept replay of trick `trick_id`, or a fresh slice when it happened less than POST ago.
static func trick_clip_for(k: Killcam, trick_id: int) -> Dictionary:
	if int(k._trick_clip.get("trick_id", -1)) == trick_id:
		return k._trick_clip
	for td in k._trick_deaths:
		if int(td[0]) == trick_id:
			return slice(k, float(td[1]))
	return {}


static func clip_usable(k: Killcam, clip: Dictionary, killer: int) -> bool:
	return not clip.is_empty() and (clip.frames as Array).size() >= 2 and clip_has(clip, killer)


static func clip_has(clip: Dictionary, peer_id: int) -> bool:
	for f in clip.frames:
		if (f[1] as Dictionary).has(peer_id):
			return true
	return false
