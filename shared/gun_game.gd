class_name GunGame
extends RefCounted
## Gun Game (#148): FFA where every gun kill moves you one step up a fixed weapon ladder; a kill with
## the last gun wins the round. A melee (knife) kill or a suicide sets the victim one step back.
## Static helpers on the Game autoload `g`; Game keeps the state (`gun_level`) and the @rpc
## (sync_gun_level), so node paths and the protocol live in one place. Server-authoritative: the
## match authority decides every level, clients only mirror it for their gun and the HUD.

## The ladder, first to last. Ends on the pistol: the hardest gun to close a round with.
const LADDER: Array[StringName] = [&"smg", &"rifle", &"lmg", &"shotgun", &"slug", &"revolver", &"sniper", &"pistol"]
## Kills with these ids demote the victim (and do not promote the killer).
const DEMOTE_WEAPONS: Array[StringName] = [&"melee"]


## 0-based ladder step of `peer` (0 when unknown).
static func level_of(g: Node, peer: int) -> int:
	return clampi(int(g.gun_level.get(peer, 0)), 0, LADDER.size() - 1)


## Gun for a ladder step.
static func weapon_at(level: int) -> StringName:
	return LADDER[clampi(level, 0, LADDER.size() - 1)]


## Gun after `level`, or &"" on the last step.
static func next_weapon(level: int) -> StringName:
	return LADDER[level + 1] if level + 1 < LADDER.size() else &""


## Authority: a kill happened. Gun kills promote the killer (and win on the last step); melee demotes
## the victim. Grenades, RCXplodie, falls: nothing moves. Returns true when the round was won.
static func on_kill(g: Node, killer: int, victim: int, weapon_id: StringName) -> bool:
	if DEMOTE_WEAPONS.has(weapon_id):
		set_level(g, victim, level_of(g, victim) - 1)
		return false
	if not LADDER.has(weapon_id):
		return false
	var lvl := level_of(g, killer)
	if lvl >= LADDER.size() - 1:
		if g._round_active:
			g._end_round_player(killer)
		return true
	set_level(g, killer, lvl + 1)
	return false


## Authority: own grenade, own car, fall: one step back.
static func on_suicide(g: Node, peer: int) -> void:
	set_level(g, peer, level_of(g, peer) - 1)


## Authority: everyone back to step 0 (new round), told to all machines.
static func reset(g: Node) -> void:
	for id in g.scores.keys():
		set_level(g, int(id), 0)
	g.gun_level.clear()


## Authority: store, broadcast and arm the pawn with the step's gun.
static func set_level(g: Node, peer: int, level: int) -> void:
	level = clampi(level, 0, LADDER.size() - 1)
	g._apply_gun_level(peer, level)
	if g.is_networked():
		g.sync_gun_level.rpc(peer, level)


## Every machine: the pawn we simulate (our own, or any on the authority) carries only its step's gun.
## Remote copies on clients follow through sync_weapon like any other switch.
static func arm(g: Node, peer: int) -> void:
	var p: Player = g.player_for_peer(peer)
	if p == null or p.weapon == null:
		return
	if not (p.is_local() or g._is_match_authority()):
		return
	var id := weapon_at(level_of(g, peer))
	if p.weapon.def and p.weapon.def.id == id:
		return
	p.weapon.set_slots([id])
	p.weapon.refill()
	if g._is_match_authority() and g.is_networked():
		g.sync_weapon.rpc(peer, String(id))


## HUD line for a step: "RIFLE  →  next LMG", or "PISTOL  ·  LAST GUN".
static func hud_line(level: int) -> String:
	var now := Game.weapon_display_name(weapon_at(level)).to_upper()
	var nxt := next_weapon(level)
	if nxt == &"":
		return "%s  ·  LAST GUN" % now
	return "%s  →  next %s" % [now, Game.weapon_display_name(nxt).to_upper()]
