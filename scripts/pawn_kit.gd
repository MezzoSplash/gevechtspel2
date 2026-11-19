class_name PawnKit
extends RefCounted
## What a pawn carries and how it uses it (#316): the class loadout (guns, frag and knife counts, the
## bot's loadout), the G and F throws, the shank lunge and the spread a gun gets from moving. Static on
## the pawn `p`, like Movement; Player keeps the state, the constants and its old function names.


static func weapon_ids(p: Player) -> Array[StringName]:
	var ids: Array[StringName] = []
	if Game.is_gun_game(): # #148: only the ladder step's gun, for humans and bots
		ids.append(GunGame.weapon_at(GunGame.level_of(Game, p.peer_id)))
		return ids
	if p.loadout.is_empty():
		for w in Weapon.LOADOUT:
			ids.append(w.id)
		return ids
	ids.append(StringName(p.loadout.primary))
	ids.append(StringName(p.loadout.secondary))
	return ids


## Per type in the class (frags on G, knives on F); the class shares PlayerClasses.MAX_GRENADES slots.
static func grenade_max(p: Player) -> int:
	if Game.is_gun_game():
		return 0 # #148: guns and the knife only
	if p.loadout.is_empty():
		return p.GRENADE_MAX
	var g: Dictionary = p.loadout.get("grenades", {})
	return clampi(int(g.get("frag", 0)), 0, PlayerClasses.MAX_GRENADES)


static func knife_max(p: Player) -> int:
	if Game.is_gun_game():
		return 0
	if p.loadout.is_empty():
		return 0
	var g: Dictionary = p.loadout.get("grenades", {})
	return clampi(int(g.get("knife", 0)), 0, PlayerClasses.MAX_GRENADES)


## Carry the class's guns (holding the primary), full ammo, class grenades.
static func apply_loadout(p: Player) -> void:
	if p.weapon:
		p.weapon.set_slots(weapon_ids(p))
		p.weapon.refill()
	p.grenades = grenade_max(p)
	p.knives = knife_max(p)
	notify_grenades(p)


static func apply_bot_loadout(p: Player) -> void:
	if p.weapon and Game.is_gun_game():
		apply_loadout(p) # #148: the bot's ladder step, not its fixed gun
	elif p.weapon:
		p.weapon.equip_loadout(p.loadout_index)


## G. Offline/host throws here; a client only sends origin and look direction.
static func try_throw_grenade(p: Player) -> void:
	if p.grenades <= 0 or p.camera == null:
		return
	var origin := p.camera.global_position + (-p.camera.global_basis.z) * 0.6
	var dir := -p.camera.global_basis.z
	if Game.is_networked() and not p.multiplayer.is_server():
		# Show it now; the server still decides (count, death, freeze) and adopts this copy.
		var seq := 0
		if not Game.play_locked():
			seq = Game.predict_grenade(p, origin, dir)
		Game.request_grenade.rpc_id(1, origin, dir, seq)
	else:
		Game.throw_grenade(p, origin, dir)


## F. The knife leaves from the right hand, a little lower than the eye, along the crosshair.
static func try_throw_knife(p: Player) -> void:
	if p.knives <= 0 or p.camera == null or (p.weapon and p.weapon.is_throwing()):
		return
	var origin := p.camera.global_position + (-p.camera.global_basis.z) * 0.5 + p.camera.global_basis.x * 0.12
	var dir := -p.camera.global_basis.z
	if p.weapon:
		p.weapon.play_throw()
	if Game.is_networked() and not p.multiplayer.is_server():
		Game.request_knife.rpc_id(1, origin, dir)
	else:
		Game.throw_knife(p, origin, dir)


static func notify_grenades(p: Player) -> void:
	if not p.is_local():
		return
	var hud := p.get_tree().get_first_node_in_group("hud") as Hud
	if hud:
		hud.set_grenades(p.grenades, p.knives)


## Held gun's movement speed factor (SMG 1.08, shank 1.23). Bots use it too.
static func gun_speed_mult(p: Player) -> float:
	if p.weapon == null or p.weapon.def == null:
		return 1.0
	return p.weapon.def.move_speed_mult


## Commit a shank lunge. The next movement tick spends it; walls stop it via move_and_slide.
static func start_lunge(p: Player, look_dir: Vector3, dist: float) -> void:
	var flat := Vector3(look_dir.x, 0.0, look_dir.z)
	if flat.length_squared() < 0.0001 or dist <= 0.05:
		return
	flat = flat.normalized()
	p._lunge_dir = flat
	p._lunge_speed = dist / Melee.LUNGE_TIME
	p._lunge_left = Melee.LUNGE_TIME


## One tick of an in-progress lunge. Sets the horizontal velocity and shortens the timer.
static func consume_lunge(p: Player, delta: float) -> void:
	p._lunge_left = maxf(p._lunge_left - delta, 0.0)
	p.velocity.x = p._lunge_dir.x * p._lunge_speed
	p.velocity.z = p._lunge_dir.z * p._lunge_speed


## Server floor for a remote human's claimed spread: half the walk penalty at the speed we see them move.
## Lenient on purpose (sync lag), it only stops "always standing still" clients.
static func min_spread_multiplier(p: Player) -> float:
	return 1.0 + minf(p._obs_speed / p.WALK_SPEED, 1.0) * p.SPREAD_WALK_K * 0.5


## 1.0 is standing still. Walk, sprint, then slide stack on top of the gun's own spread.
static func spread_multiplier(p: Player) -> float:
	# Still is the accurate state. Slide is wider than sprint, which is wider than walking.
	if p.is_sliding():
		return p.SPREAD_SLIDE
	if p.is_sprinting:
		return p.SPREAD_SPRINT
	var move := minf(Vector2(p.velocity.x, p.velocity.z).length() / p.WALK_SPEED, 1.0)
	return 1.0 + move * p.SPREAD_WALK_K
