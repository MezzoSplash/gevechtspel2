class_name Combat
extends RefCounted
## Damage, hits and kills (#106): server-side shot resolution (rays, pellets, spread, bursts, mags),
## hit application, HP and regen, damage log + death report, kill/suicide/death bookkeeping, respawns,
## networked shot tracers. Static helpers on the Game autoload `game`; Game keeps the state and every @rpc.

## B4: how much of a gun's reload time the server insists on before it accepts a fresh magazine.
## Slack for jitter and rounding, like FIRE_RATE_SLACK; never generous enough to skip a reload.
const RELOAD_SLACK := 0.85


## Current HP of a pawn as the authority sees it.
static func hp_of(game: GameState, p: Player) -> float:
	if not game.is_networked():
		return p.hp
	var id := p.peer_id
	if id == 0:
		id = p._owner_peer()
	if not game.net_hp.has(id):
		game.net_hp[id] = Player.MAX_HP
	return float(game.net_hp[id])


## Logs damage for the death report (taken by the victim, dealt by the attacker).
static func note_damage(game: GameState, attacker_peer: int, victim_peer: int, amount: float) -> void:
	if attacker_peer == 0 or attacker_peer == victim_peer or amount <= 0.0:
		return
	var per: Dictionary = game._dmg_log.get(victim_peer, {})
	var e: Array = per.get(attacker_peer, [0.0, 0])
	per[attacker_peer] = [float(e[0]) + amount, int(e[1]) + 1]
	game._dmg_log[victim_peer] = per


## Authority, right after a kill: tell the (human) victim what the killer did to them this life
## and what they did to the killer during the killer's current life.
static func send_death_report(game: GameState, killer_peer: int, victim_peer: int, weapon_id: StringName = &"") -> void:
	if killer_peer == 0 or killer_peer == victim_peer or victim_peer < 0:
		return
	var taken: Array = (game._dmg_log.get(victim_peer, {}) as Dictionary).get(killer_peer, [0.0, 0])
	var dealt: Array = (game._dmg_log.get(killer_peer, {}) as Dictionary).get(victim_peer, [0.0, 0])
	var name := game._display_name_for(killer_peer)
	if game.scores.has(killer_peer):
		name = str(game.scores[killer_peer].name)
	var killer := game.player_for_peer(killer_peer)
	var left := hp_of(game, killer) if killer else 0.0
	var args := [name, roundi(float(taken[0])), int(taken[1]), roundi(float(dealt[0])), int(dealt[1]), roundi(left), game.weapon_display_name(weapon_id)]
	if not game.is_networked() or victim_peer == game.multiplayer.get_unique_id():
		game._show_death_report(args)
	elif victim_peer in game.multiplayer.get_peers():
		game.sync_death_report.rpc_id(victim_peer, args)


## Forget a peer that left: HP, name/team, streak, ping, shot credit, and its scoreboard row (synced).
static func clear_peer_hp(game: GameState, peer_id: int) -> void:
	game.net_hp.erase(peer_id)
	game.pending_names.erase(peer_id)
	game.pending_teams.erase(peer_id)
	game.streak_progress.erase(peer_id)
	game.streak_charges.erase(peer_id)
	game.streak_earned.erase(peer_id)
	RcXd.abort_for(peer_id)
	LosHands.abort_for(peer_id)
	game.pings.erase(peer_id)
	game._fire_credit.erase(peer_id)
	if game.melee:
		game.melee.forget(peer_id)
	if game.loadouts:
		game.loadouts.forget(peer_id)
	game.drop_score(peer_id)


## Client eye vs. our copy of it. Position is client-synced, so this only stops "shoot from anywhere".
static func origin_plausible(game: GameState, shooter: Player, origin: Vector3) -> bool:
	var eye := shooter.camera.global_position if shooter.camera else shooter.global_position
	return eye.distance_to(origin) <= game.FIRE_ORIGIN_TOLERANCE


## Per gun: credit refills a bit faster than the fire rate and holds ~1.5 shots, so packet bunching passes
## but a fast-fire hack does not. Per gun because a switch does not reset the client's cooldown either.
static func take_fire_credit(game: GameState, peer: int, def: WeaponDef) -> bool:
	var interval := 1.0 / maxf(def.fire_rate, 0.01)
	var cap := interval * 1.5 + 0.1
	var now := Time.get_ticks_msec() / 1000.0
	if not game._fire_credit.has(peer):
		game._fire_credit[peer] = {}
	var per_gun: Dictionary = game._fire_credit[peer]
	var state: Array = per_gun.get(def.id, [cap, now])
	var credit := minf(float(state[0]) + (now - float(state[1])) * game.FIRE_RATE_SLACK, cap)
	if credit < interval * 0.85:
		per_gun[def.id] = [credit, now]
		return false
	per_gun[def.id] = [credit - interval, now]
	return true


## Host / offline / bots: resolve hits on this machine (must be match authority).
static func fire_weapon_locally(game: GameState, shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float = 1.0,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0,
	mag: int = 0) -> Dictionary:
	return resolve_weapon_fire(game, shooter, origin, look_dir, def, spread_mult, shot_seed, scoped, burst, mag)


## `shot_seed` drives the pellet spread, so Weapon._simulate_pellets_fx draws the same rays.
## Teammates are excluded: shots pass through friends instead of being soaked up by them.
## `scoped`: the shooter had the sniper scope up (only matters for the NOSCOPE trick, never for damage).
## `burst`: the shooter's held-trigger counter for automatic guns (SPRAY TRANSFER only; 0 = unknown).
## `mag`: the shooter's magazine counter for this gun (Weapon.mag_seq; HOSE / SIX SHOOTER only).
static func resolve_weapon_fire(game: GameState, shooter: Player,
	origin: Vector3,
	look_dir: Vector3,
	def: WeaponDef,
	spread_mult: float,
	shot_seed: int = 0,
	scoped: bool = false,
	burst: int = 0,
	mag: int = 0,
	strict_mag: bool = false) -> Dictionary:
	var magazine := mag_for(game, shooter, def, mag, strict_mag)
	if strict_mag and magazine.is_empty():
		# No round left and no finished reload: the shot does not happen at all (B4).
		return {"killed": false, "headshot": false, "hit": false,
			"end": origin + look_dir.normalized() * def.range_m, "refused": true}
	game._shot_ctx = {
		"shooter": shooter, "origin": origin, "scoped": scoped, "burst": burst_for(game, shooter, def, burst),
		"mag": magazine,
	}
	var best := resolve_shot_rays(game, shooter, origin, look_dir, def, spread_mult, shot_seed)
	game._shot_ctx = {}
	return best


## Casts every pellet/ray of a shot and returns the best hit per victim.
static func resolve_shot_rays(game: GameState, shooter: Player, origin: Vector3, look_dir: Vector3, def: WeaponDef, spread_mult: float, shot_seed: int) -> Dictionary:
	look_dir = look_dir.normalized()
	var spread := def.spread_deg * spread_mult
	var best := {"killed": false, "headshot": false, "hit": false, "end": origin + look_dir * def.range_m}
	var space := shooter.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = shot_seed if shot_seed != 0 else randi()
	var exclude := shot_exclude(game, shooter)
	for i in def.pellet_count:
		var dir := spread_dir(game, look_dir, spread, rng)
		var to := origin + dir * def.range_m
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.collision_mask = game.SHOT_MASK
		query.exclude = exclude
		var hit := LagComp.intersect_ray(space, query, game._shot_rewind)
		if i == 0:
			best.end = to if hit.is_empty() else hit.position
		if hit.is_empty():
			continue
		var dist := origin.distance_to(hit.position)
		var dmg := def.damage_at_distance(dist)
		var result := apply_shot_hit(game, shooter, hit, dmg, def)
		if result.is_empty():
			continue
		var end: Vector3 = best.end
		best = merge_hit_result(game, best, result)
		best.end = end
	return best


## The rifle burst this shot belongs to: same trigger hold (client counter) and no pause over
## Style.BURST_GAP. Kills append their victim (register_kill). {} for other guns.
static func burst_for(game: GameState, shooter: Player, def: WeaponDef, seq: int) -> Dictionary:
	if not def.automatic or seq == 0:
		return {}
	var now := Time.get_ticks_msec() / 1000.0
	var b: Dictionary = game._bursts.get(shooter.peer_id, {})
	if b.is_empty() or int(b.seq) != seq or now - float(b.t) > Style.BURST_GAP:
		b = {"seq": seq, "t": now, "victims": []}
		game._bursts[shooter.peer_id] = b
	b.t = now
	return b


## The magazine this shot comes from. `seq` is the client's fresh-magazine counter.
## `strict` (B4, the server deciding on a networked shot): the server counts, so a new magazine is only
## legal once the old one is empty AND the reload time has passed, and an empty magazine refuses the
## shot — a modified client cannot shoot forever by never reloading or by bumping the counter.
## Returns {} when the shot must be refused. Kills are added by register_kill; the SMG and revolver
## tricks read it.
static func mag_for(game: GameState, shooter: Player, def: WeaponDef, seq: int, strict := false) -> Dictionary:
	var per: Dictionary = game._mags.get(shooter.peer_id, {})
	game._mags[shooter.peer_id] = per
	var m: Dictionary = per.get(def.id, {})
	if not strict:
		if m.is_empty() or int(m.seq) != seq or int(m.shots) >= def.mag_size:
			m = {"seq": seq, "shots": 0, "kills": 0, "weapon": def.id}
			per[def.id] = m
		m.shots = int(m.shots) + 1
		return m
	var now := Time.get_ticks_msec() / 1000.0
	if m.is_empty():
		per[def.id] = {"seq": seq, "shots": 1, "kills": 0, "weapon": def.id, "last_s": now}
		return per[def.id]
	if int(m.seq) != seq:
		var empty := int(m.shots) >= def.mag_size
		var reloaded := now - float(m.get("last_s", now)) >= def.reload_time * RELOAD_SLACK
		if not (empty and reloaded):
			return {} # a fresh magazine without an empty gun and a finished reload
		m.seq = seq
		m.shots = 0
	if int(m.shots) >= def.mag_size:
		return {} # empty: the client has to reload
	m.shots = int(m.shots) + 1
	m.last_s = now
	return m


## Shooter plus living teammates (none in FFA). Used for shots, tracers, and bot line of sight.
static func shot_exclude(game: GameState, shooter: Player) -> Array[RID]:
	var out: Array[RID] = [shooter.get_rid()]
	if game.is_ffa():
		return out
	for n in game.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p and p != shooter and p.team_id == shooter.team_id and not p.is_dead:
			out.append(p.get_rid())
	return out


## Combines the results of one shot: a kill beats a headshot beats a plain hit.
static func merge_hit_result(game: GameState, best: Dictionary, result: Dictionary) -> Dictionary:
	if result.get("killed", false):
		return {"killed": true, "headshot": result.headshot, "hit": true}
	if best.killed:
		return best
	if result.get("headshot", false):
		return {"killed": false, "headshot": true, "hit": true}
	if best.headshot:
		return best
	return {"killed": false, "headshot": false, "hit": true}


## Shared by server hits and client tracers. Same rng seed → same pellets.
static func spread_dir(game: GameState, forward: Vector3, deg: float, rng: RandomNumberGenerator) -> Vector3:
	if deg <= 0.0:
		return forward.normalized()
	var rad := deg_to_rad(deg)
	var theta := rng.randf() * TAU
	var phi := rad * sqrt(rng.randf())
	var up := Vector3.UP
	var right := forward.cross(up)
	if right.length_squared() < 0.001:
		right = forward.cross(Vector3.RIGHT)
	right = right.normalized()
	up = right.cross(forward).normalized()
	return (forward.normalized() * cos(phi) + (right * cos(theta) + up * sin(theta)) * sin(phi)).normalized()


## Applies damage for a resolved hit and fires hit feedback.
static func apply_shot_hit(game: GameState, shooter: Player, hit: Dictionary, damage: float, def: WeaponDef) -> Dictionary:
	var collider := hit.collider as Node
	if collider == null:
		return {}
	var killer_id := shooter.peer_id
	if killer_id <= 0:
		killer_id = shooter._owner_peer()
	if collider is Player:
		var victim := collider as Player
		if victim == shooter or victim.is_dead:
			return {}
		if not game.is_enemy(victim, shooter):
			return {}
		# Lag-compensated hits (#105) land on the rewound body; the headshot test needs the live one.
		var on_body: Vector3 = hit.position + hit.get("rewind_delta", Vector3.ZERO)
		return victim.apply_hit(
			on_body, hit.normal, damage, true, killer_id, def.id, def.headshot_multiplier, shooter.global_position
		)
	# RC-XD sits on layer 4 (inside SHOT_MASK). Destroying it does not splash.
	var rc := collider as RcXd
	if rc:
		rc.damage(damage)
		return {"killed": false, "headshot": false, "hit": true}
	var uav := collider as UavDrone
	if uav and uav.hittable_by(shooter.team_id, killer_id):
		uav.damage(damage, killer_id, shooter.team_id, def.id)
		return {"killed": false, "headshot": false, "hit": true}
	return {}


## Server/offline only. Updates TDM score and kill feed (weapon_id is the gun used).
## Also remembers the kill as this round's final kill until a later one replaces it.
static func register_kill(game: GameState, killer_peer_id: int, victim_peer_id: int, weapon_id: StringName = &"rifle", headshot: bool = false) -> void:
	if not game._is_match_authority():
		return
	add_death(game, victim_peer_id)
	if killer_peer_id == 0:
		return
	if killer_peer_id == victim_peer_id:
		register_suicide(game, victim_peer_id, weapon_id)
		return
	if not game.scores.has(killer_peer_id):
		var killer := game.player_for_peer(killer_peer_id)
		var team := killer.team_id if killer else 0
		game.register_participant(killer_peer_id, game._display_name_for(killer_peer_id), team)
	var kills: int = int(game.scores[killer_peer_id].kills) + 1
	var n: String = game.scores[killer_peer_id].name
	var team_id: int = int(game.scores[killer_peer_id].get("team", 0))
	var killer_pawn := game.player_for_peer(killer_peer_id)
	if killer_pawn:
		team_id = killer_pawn.team_id # the pawn is the truth; a stale row must not credit the other team
	game._apply_score(killer_peer_id, kills, n, team_id)
	if game.is_networked():
		game.sync_score.rpc(killer_peer_id, kills, n, team_id)
	add_team_kill(game, team_id)
	var killer_name := n
	var victim_name := game._display_name_for(victim_peer_id)
	if game.scores.has(victim_peer_id):
		victim_name = str(game.scores[victim_peer_id].name)
	var victim_team := 0
	var victim := game.player_for_peer(victim_peer_id)
	if victim:
		victim_team = victim.team_id
	elif game.scores.has(victim_peer_id):
		victim_team = int(game.scores[victim_peer_id].get("team", 0))
	var tricks := game._detect_tricks(killer_peer_id, victim_peer_id, weapon_id, headshot)
	game._note_trick_history(killer_peer_id, victim_peer_id, weapon_id, headshot)
	var tag := Style.label(tricks)
	game._emit_kill_feed(killer_name, victim_name, weapon_id, team_id, victim_team, tag)
	if game.is_networked():
		game.sync_kill_feed.rpc(killer_name, victim_name, String(weapon_id), team_id, victim_team, tag)
	var kill_info := {
		"k": killer_peer_id, "v": victim_peer_id, "kn": killer_name, "vn": victim_name,
		"kt": team_id, "vt": victim_team, "w": String(weapon_id), "hs": headshot, "tags": tag,
	}
	if game._round_active:
		game.final_kill = kill_info # before the style award: a style-mode winning trick ends the round there
	if not tricks.is_empty() or Combo.active(game._combos.get(killer_peer_id, {})):
		game._award_style(kill_info, tricks)
	if game.is_gun_game():
		GunGame.on_kill(game, killer_peer_id, victim_peer_id, weapon_id) # #148: the ladder, not kills, wins
	elif game.is_ctf():
		pass # #160: captures end a CTF round, never kills
	elif game.is_style_mode():
		pass # style modes end on style points (_check_style_win), never on kills
	elif game.is_ffa():
		game._check_win_player(killer_peer_id)
	else:
		game._check_win_team(team_id)
	game._bump_streak(killer_peer_id, victim_peer_id)


## Own grenade or own RC: kill feed shows it, this life's kill count resets, banked streaks stay.
static func register_suicide(game: GameState, peer_id: int, weapon_id: StringName) -> void:
	game._hs_streak.erase(peer_id)
	var n := game._display_name_for(peer_id)
	if game.scores.has(peer_id):
		n = str(game.scores[peer_id].name)
	var team := 0
	var p := game.player_for_peer(peer_id)
	if p:
		team = p.team_id
	elif game.scores.has(peer_id):
		team = int(game.scores[peer_id].get("team", 0))
	game._emit_kill_feed(n, n, weapon_id, team, team, "")
	if game.is_networked():
		game.sync_kill_feed.rpc(n, n, String(weapon_id), team, team, "")
	if game.is_gun_game():
		GunGame.on_suicide(game, peer_id) # #148: a suicide costs a step
	game._bump_streak(0, peer_id)


## TDM: counts a kill for a team and syncs the totals.
static func add_team_kill(game: GameState, team_id: int) -> void:
	var t := clampi(team_id, game.TEAM_A, game.TEAM_B)
	game.team_kills[t] = int(game.team_kills[t]) + 1
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_team_kills.rpc(int(game.team_kills[0]), int(game.team_kills[1]))


## Server: one more death on the victim's row (scoreboard K/D), synced to everyone.
static func add_death(game: GameState, peer_id: int) -> void:
	game._combo_end(peer_id, "bailed", 0) # #84: dying with a combo up is a bail

	if not game.scores.has(peer_id):
		return
	var d := int(game.scores[peer_id].get("deaths", 0)) + 1
	game.scores[peer_id].deaths = d
	if game.is_networked():
		game.sync_deaths.rpc(peer_id, d)


## Authority: every respawn (death timer, round start) goes through here so a waiting class
## change reaches the owner before the respawn does, and everyone sees the primary in hand.
static func respawn_pawn(game: GameState, p: Player) -> void:
	if p == null:
		return
	game._dmg_log.erase(p.peer_id) # a new life: damage taken starts from zero
	game.set_hp(p, Player.MAX_HP)
	if game.loadouts:
		game.loadouts.promote_pending(p)
	if p.is_bot:
		reroll_bot_gun(game, p)
	var xf := p._spawn_xform
	if game.spawn_picker.is_valid():
		xf = game.spawn_picker.call(p)
	if game.is_networked():
		game.broadcast_respawn.rpc(p.peer_id, xf)
		if not p.is_bot and not p.loadout.is_empty():
			game.sync_weapon.rpc(p.peer_id, String(p.loadout.primary))
	else:
		p._spawn_xform = xf
		p.apply_respawn_state()


## Bots get a new gun every life, so a match sees the whole armory instead of one gun per bot.
## Everyone gets it through sync_weapon (by id); late joiners read loadout_index from the snapshot.
static func reroll_bot_gun(game: GameState, p: Player) -> void:
	var n := Weapon.LOADOUT.size()
	if n < 2:
		return
	var i := randi_range(0, n - 2)
	if i >= p.loadout_index:
		i += 1 # never the same gun twice in a row
	p.loadout_index = i
	p._apply_bot_loadout()
	if game.is_networked() and game.multiplayer.is_server():
		game.sync_weapon.rpc(p.peer_id, String(Weapon.LOADOUT[i].id))


## Health regen on the match authority: REGEN_DELAY s after the last hit, REGEN_RATE HP/s (bots too).
## Clients get the values in batches every REGEN_SYNC s; the last step to full HP is sent at once.
static func tick_regen(game: GameState, delta: float) -> void:
	if not game._is_match_authority():
		return
	var to_send := false
	for n in game.get_tree().get_nodes_in_group("player"):
		var p := n as Player
		if p == null or p.is_dead or p.is_queued_for_deletion():
			continue
		p.since_hurt += delta
		var cur := hp_of(game, p)
		if cur >= Player.MAX_HP or p.since_hurt < Player.REGEN_DELAY:
			continue
		var new_hp := minf(cur + Player.REGEN_RATE * delta, Player.MAX_HP)
		game.set_hp(p, new_hp)
		p.apply_regen_hp(new_hp)
		game._regen_dirty[p.peer_id] = new_hp
		if new_hp >= Player.MAX_HP:
			to_send = true
	if not game.is_networked():
		game._regen_dirty.clear()
		return
	game._regen_sync_t -= delta
	if game._regen_dirty.is_empty() or (game._regen_sync_t > 0.0 and not to_send):
		return
	game._regen_sync_t = game.REGEN_SYNC
	var batch: Array = []
	for id in game._regen_dirty:
		batch.append([id, float(game._regen_dirty[id])])
	game._regen_dirty.clear()
	if not game.multiplayer.get_peers().is_empty():
		game.sync_regen.rpc(batch)


## Host already played local FX. Remote humans need a tracer/sfx on the listen-server too.
static func broadcast_shot_fx(game: GameState, from: Vector3, to: Vector3, shooter_peer_id: int) -> void:
	if not game.is_networked() or not game.multiplayer.is_server():
		return
	if shooter_peer_id > 0 and shooter_peer_id != game.multiplayer.get_unique_id():
		spawn_net_tracer(game, from, to)
		var remote_shooter := game.player_for_peer(shooter_peer_id)
		if remote_shooter and remote_shooter.weapon:
			remote_shooter.weapon.play_fire_sfx()
		note_net_shot(game, from, to, remote_shooter)
	game.sync_shot_fx.rpc(from, to, shooter_peer_id)


## Someone else's shot as this machine saw it, for the killcam buffer. Own shots are noted in Weapon._fire.
static func note_net_shot(game: GameState, from: Vector3, to: Vector3, shooter: Player) -> void:
	if shooter == null or shooter.weapon == null or shooter.weapon.def == null:
		return
	game.killcam.note_fire(shooter.peer_id, shooter.weapon.def.id)
	game.killcam.note_tracer(shooter.peer_id, from, to, shooter.weapon.def.id)


## Tracer for a shot fired on another machine.
static func spawn_net_tracer(game: GameState, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	game.impacts.add_from_tracer(from, to)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.02, 0.02, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.82, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.15)
	mat.emission_energy_multiplier = 3.0
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.get_tree().root.add_child(mesh_inst)
	mesh_inst.global_position = (from + to) * 0.5
	if from.distance_squared_to(to) > 0.0001:
		mesh_inst.look_at(to, Vector3.UP)
	game.get_tree().create_timer(0.055).timeout.connect(mesh_inst.queue_free)
