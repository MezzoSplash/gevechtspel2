class_name Streaks
extends RefCounted
## Scorestreaks (#106): kill counts, UAV / RC-XD charges, using a charge, the UAV radar. Static helpers on
## the Game autoload `g`; Game keeps the state and every @rpc (sync_streak, sync_radar, ...).


## Humans and bots (bots have negative ids). Death clears this life's count, not a streak already earned.
## 3 banks the UAV, 5 banks the RC-XD. Each stays until Enter uses it,
## or until start_round clears every charge for the next round.
static func bump_streak(g: GameState, killer_peer_id: int, victim_peer_id: int) -> void:
	if victim_peer_id != 0:
		g.streak_progress[victim_peer_id] = 0
		g.streak_earned[victim_peer_id] = 0
		push_streak(g, victim_peer_id)
	if killer_peer_id == 0:
		return
	var n := int(g.streak_progress.get(killer_peer_id, 0))
	if n < g.RCXD_AT:
		n += 1
	g.streak_progress[killer_peer_id] = n
	var charges := int(g.streak_charges.get(killer_peer_id, 0))
	var earned := int(g.streak_earned.get(killer_peer_id, 0))
	if n >= g.STREAK_AT and (earned & g.CHARGE_RADAR) == 0:
		earned |= g.CHARGE_RADAR
		charges |= g.CHARGE_RADAR
	if n >= g.RCXD_AT and (earned & g.CHARGE_RCXD) == 0:
		earned |= g.CHARGE_RCXD
		charges |= g.CHARGE_RCXD
	g.streak_earned[killer_peer_id] = earned
	g.streak_charges[killer_peer_id] = charges
	push_streak(g, killer_peer_id)


static func push_streak(g: GameState, peer_id: int) -> void:
	var n := int(g.streak_progress.get(peer_id, 0))
	var charges := int(g.streak_charges.get(peer_id, 0))
	var earned := int(g.streak_earned.get(peer_id, 0))
	if peer_id < 0:
		return # bot: its brain reads streak_charges on the server, no HUD to update
	if not g.is_networked() or peer_id == g.multiplayer.get_unique_id():
		apply_streak_local(g, n, charges, earned)
		return
	g.sync_streak.rpc_id(peer_id, n, charges, earned)


static func apply_streak_local(g: GameState, n: int, charges: int, earned: int) -> void:
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_streak(n, charges, earned)


## Slot 0 is the UAV (3), slot 1 is the RC-XD (5). Using one spends only that charge.
## UAV still spends if one is already running (time is not stacked).
## Freeze, killcam, death, or a car already out: the charge is kept.
static func try_activate_streak(g: GameState, peer_id: int, slot: int) -> void:
	if not g._is_match_authority():
		return
	if g.play_locked() or peer_id == 0:
		return
	var p := g.player_for_peer(peer_id)
	if p == null or p.is_dead:
		return
	if RcXd.for_owner(peer_id) != null:
		return
	var bit := 0
	if slot == 0:
		bit = g.CHARGE_RADAR
	elif slot == 1:
		bit = g.CHARGE_RCXD
	else:
		return
	var charges := int(g.streak_charges.get(peer_id, 0))
	if (charges & bit) == 0:
		return
	if bit == g.CHARGE_RCXD and not RcXd.launch(p):
		return
	charges &= ~bit
	g.streak_charges[peer_id] = charges
	push_streak(g, peer_id)
	g.streak_used.emit(peer_id, slot)
	if bit == g.CHARGE_RADAR:
		grant_radar(g, peer_id)


## UAV: every machine hears about it; the activator's team gets enemies on the minimap,
## the other team only the "enemy radar" cue. The minimap reads the live pawns, so
## enemies that respawn during the radar show up too. FFA: only the activator gets markers
## (of everyone else); all others get the "enemy radar" cue.
static func grant_radar(g: GameState, peer_id: int) -> void:
	var team := 0
	var p := g.player_for_peer(peer_id)
	if p:
		team = p.team_id
	elif g.scores.has(peer_id):
		team = int(g.scores[peer_id].get("team", 0))
	var by := g._display_name_for(peer_id)
	if g.scores.has(peer_id):
		by = str(g.scores[peer_id].name)
	if g.is_networked():
		g.sync_radar.rpc(team, by, g.RADAR_TIME, peer_id)
	apply_radar(g, team, by, g.RADAR_TIME, peer_id)


static func apply_radar(g: GameState, team: int, by_name: String, seconds: float, by_peer: int) -> void:
	var mine := g.local_team()
	if mine < 0:
		return
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	var friendly := team == mine
	if g.is_ffa():
		friendly = by_peer == g.multiplayer.get_unique_id()
	if friendly:
		g.radar_team = team
		g.radar_peer = by_peer
		g.radar_left = maxf(g.radar_left, seconds)
	if hud:
		hud.show_radar_event(by_name, team, friendly)


## Round end, round start, killcam, and leaving: no markers carry over, and no RC stays out.
static func clear_radar(g: GameState) -> void:
	g.radar_left = 0.0
	g.radar_team = -1
	g.radar_peer = 0
	var hud := g.get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.clear_radar()
	RcXd.abort_all()


## New round drops this life's kill count and any charge still held.
## Leave-to-menu clears the same dictionaries in reset_session. Without this, a radar
## banked last round is still usable after intermission. Clients hear it via sync_streak.
static func clear_round_streaks(g: GameState) -> void:
	var humans := {}
	for src in [g.streak_progress, g.streak_charges, g.streak_earned]:
		for id in src:
			if int(id) > 0:
				humans[int(id)] = true
	g.streak_progress.clear()
	g.streak_charges.clear()
	g.streak_earned.clear()
	var me := g.multiplayer.get_unique_id() if g.is_networked() else 1
	if me > 0:
		humans[me] = true
	for id in humans:
		push_streak(g, int(id))
