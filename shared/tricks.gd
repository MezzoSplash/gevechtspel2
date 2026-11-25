class_name Tricks
extends RefCounted
## Trick detection and per-killer trick history, pulled out of Game (shared/game.gd).
## Pure logic: Game keeps the state dictionaries and all @rpc functions, so node paths and the
## network protocol do not change. Static helpers only.


## The shot (or melee swing) resolving right now (game._shot_ctx) made this kill: what tricks was it?
## Grenades and anything outside a shot or swing have no context and no tricks.
static func detect(
	game: Node, killer_peer_id: int, victim_peer_id: int, weapon_id: StringName, headshot: bool = false
) -> Array[StringName]:
	var none: Array[StringName] = []
	if weapon_id == &"rcxd":
		return Style.detect({"weapon": weapon_id}) # #87: the RC blast has no shot context, but is a style kill
	var shot_ctx: Dictionary = game._shot_ctx
	if shot_ctx.is_empty():
		return none
	var shooter := shot_ctx.get("shooter") as Player
	if shooter == null or not is_instance_valid(shooter):
		return none
	if shooter.peer_id != killer_peer_id and shooter._owner_peer() != killer_peer_id:
		return none
	var victim: Player = game.player_for_peer(victim_peer_id)
	var origin: Vector3 = shot_ctx.get("origin", shooter.global_position)
	var dist := origin.distance_to(victim.aim_point()) if victim else 0.0
	var remote: bool = game.is_networked() and not shooter.is_bot and not shooter.is_local()
	var window := Style.SPIN_WINDOW
	if remote:
		window += Style.SPIN_NET_SLACK
	var now := Time.get_ticks_msec() / 1000.0
	var burst: Dictionary = shot_ctx.get("burst", {})
	var others := 0
	for v in burst.get("victims", []):
		if int(v) != victim_peer_id:
			others += 1
	var streak := int(game._hs_streak.get(killer_peer_id, 0))
	if weapon_id == &"rifle" and headshot:
		streak += 1
	var mag: Dictionary = shot_ctx.get("mag", {})
	var mag_kills := int(mag.get("kills", 0)) + 1 if StringName(mag.get("weapon", &"")) == weapon_id else 0
	var since_draw := INF
	if shooter.weapon and shooter.weapon.def and shooter.weapon.def.id == weapon_id:
		since_draw = shooter.weapon.since_draw()
	return Style.detect({
		"weapon": weapon_id,
		"scoped": bool(shot_ctx.get("scoped", false)),
		"bot": shooter.is_bot,
		"headshot": headshot,
		"spin": shooter.spin_degrees(window),
		"shooter_air": shooter.air_time,
		"victim_air": victim.air_time if victim else 0.0,
		"dist": dist,
		"speed": shooter._obs_speed,
		"surf": shooter.style_surfing(),
		"drop": shooter.style_drop(),
		"burst_victims": others,
		"double": weapon_id == &"shotgun" and now - float(game._shotgun_kill_t.get(killer_peer_id, -100.0)) <= Style.DOUBLE_WINDOW,
		"hs_streak": streak,
		"run_t": shooter.run_time(),
		"mag_kills": mag_kills,
		"since_draw": since_draw,
		"quickdraw_slack": Style.QUICKDRAW_NET_SLACK if remote else 0.0,
		"knife_air": bool(shot_ctx.get("knife_air", false)),
		"wallrun": shooter.style_wallrun(),
		"walljump": shooter.style_walljump(),
		"dive": shooter.style_dive(),
		"roll": shooter.style_roll(),
		"grapple": shooter.style_grapple(),
		# LOS reads the body's real horizontal speed. _obs_speed is smoothed and can still be 0
		# the moment a velocity is set, which would drop a fast bash.
		"los": LosHands.driving(shooter),
		# #384: the chain count, 1 on the first bash of a LOS and 2 or 3 on the extra kills.
		"los_kills": LosHands.chain_index_for(shooter),
		# How far the hands were from the body when the bash landed: the snap the killer is about
		# to get. Only meaningful while driving.
		"los_dist": LosHands.snap_m_for(shooter),
		"body_speed": Vector2(shooter.velocity.x, shooter.velocity.z).length(),
	})


## Per-killer history behind DOUBLE, SPRAY TRANSFER and HEADSHOT STREAK (after detect).
static func note_history(
	hs_streak: Dictionary, shotgun_kill_t: Dictionary, shot_ctx: Dictionary,
	killer_peer_id: int, victim_peer_id: int, weapon_id: StringName, headshot: bool
) -> void:
	hs_streak.erase(victim_peer_id) # dying ends your streak
	if weapon_id == &"rifle" and headshot:
		hs_streak[killer_peer_id] = int(hs_streak.get(killer_peer_id, 0)) + 1
	else:
		hs_streak.erase(killer_peer_id) # any other kill breaks the run
	if weapon_id == &"shotgun":
		shotgun_kill_t[killer_peer_id] = Time.get_ticks_msec() / 1000.0
	if not shot_ctx.is_empty():
		var burst: Dictionary = shot_ctx.get("burst", {})
		if not burst.is_empty():
			(burst.victims as Array).append(victim_peer_id)
		var mag: Dictionary = shot_ctx.get("mag", {})
		if not mag.is_empty() and StringName(mag.get("weapon", &"")) == weapon_id:
			mag.kills = int(mag.kills) + 1


## Next link in a killer's trick-kill chain (stored in style_chain as [count, time]); returns the count.
static func next_chain(style_chain: Dictionary, peer_id: int, now: float) -> int:
	var prev: Array = style_chain.get(peer_id, [0, -1000.0])
	var chain := int(prev[0]) + 1 if now - float(prev[1]) <= Style.CHAIN_WINDOW else 1
	style_chain[peer_id] = [chain, now]
	return chain


## Best trickshot rule: the biggest landed combo of the round wins, whoever landed it. Kills without a
## combo only count while nobody has landed one yet. On an equal payout a human's kill outranks a bot's,
## and then a kill on a real player outranks one on a bot (#149), so a bot's stray frag never takes the
## MVP killcam from the player whose combo it was (#358).
## `victim_is_bot` / `killer_is_bot`: that peer has a negative id.
static func is_best(best_trick: Dictionary, round_active: bool, bank: int, pts: int,
		victim_is_bot := false, killer_is_bot := false) -> bool:
	if not round_active:
		return false
	if best_trick.is_empty():
		return true
	var best_bank := int(best_trick.get("bank", 0))
	if bank != best_bank:
		return bank > best_bank # the combo payout decides, not who landed it
	if killer_is_bot != bool(best_trick.get("kbot", true)):
		return not killer_is_bot # same payout: a human's kill takes it from a bot's, never the other way
	if victim_is_bot != bool(best_trick.get("vbot", true)):
		return not victim_is_bot # then a kill on a real player beats a kill on a bot
	return bank == 0 and pts > int(best_trick.get("pts", 0))


## Every machine (sync_trick / the authority itself): the killer's style total, the replay kept for the
## final killcam when it is the round's best, the HUD told, and the style win checked on the authority.
static func apply(g: GameState, killer_peer_id: int, victim_peer_id: int, tricks: String, points: int,
		multiplier: float, total: int, trick_id: int, is_best: bool) -> void:
	if g.scores.has(killer_peer_id):
		g.scores[killer_peer_id].style = maxi(total, 0)
	if is_best and g.killcam:
		g.killcam.note_trick(trick_id, victim_peer_id)
	g.trick_scored.emit(killer_peer_id, tricks, points, multiplier, total)
	if g._is_match_authority():
		g._check_style_win(killer_peer_id)
	if g.scores.has(killer_peer_id):
		g.score_changed.emit(killer_peer_id, int(g.scores[killer_peer_id].kills), str(g.scores[killer_peer_id].name))
