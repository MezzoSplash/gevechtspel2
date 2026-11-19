class_name PawnVitals
extends RefCounted
## A pawn's life (#316): the kill plane and the void pull, damage (armour first, headshots on the drawn
## head, the kill and the death report), the hurt state every machine applies, death, and the respawn
## state. Static on the pawn `p`, like Movement; Player keeps the state, the constants, the signals and
## its old function names as wrappers, so nothing on the network changes.


## Falling under the map's kill_y is a suicide, and the death respawns you on the map.
## During the first second after a respawn it is a bad spawn instead: the body goes back to that
## spawn, so the fall does not start another death. Spawn protection lasts longer than that second
## and would swallow the hit; a fall after the grace has to kill anyway.
static func check_kill_y(p: Player) -> void:
	if p.is_dead or p.global_position.y >= Game.map_kill_y:
		return
	if p._spawn_protect > p.SPAWN_PROTECT - p.VOID_GRACE:
		p._pull_out_of_void()
		return
	var saved := p._spawn_protect
	p._spawn_protect = 0.0
	p.apply_hit(p.global_position, Vector3.UP, 10000.0, false, p.peer_id, &"fall")
	if not p.is_dead:
		p._spawn_protect = saved


## Authority copy only. A remote human also gets correct_position, which already exists for claims.
static func pull_out_of_void(p: Player) -> void:
	p.global_transform = p._spawn_xform
	p.velocity = Vector3.ZERO
	p._net_target = p.global_position
	p._net_has = true
	if Game.is_networked() and p.multiplayer.is_server() and not p.is_bot and p.peer_id in p.multiplayer.get_peers():
		Game.correct_position.rpc_id(p.peer_id, p.peer_id, p.global_position)


## Damage is applied on the server (or offline). Clients get HP via broadcast_hurt.
## `headshot_mult` comes from the gun's WeaponDef — never repeat the numbers here.
## Grenades pass allow_headshot false. The test uses the drawn head, not a height band.
static func apply_hit(
	p: Player,
	point: Vector3,
	_normal: Vector3,
	base_damage: float,
	allow_headshot: bool = true,
	killer_peer_id: int = 0,
	weapon_id: StringName = &"rifle",
	headshot_mult: float = 1.6,
	source_pos: Vector3 = Vector3.INF
) -> Dictionary:
	if p.is_dead or p._spawn_protect > 0.0 or Game.killcam_active:
		return {"killed": false, "headshot": false, "damage": 0}
	if Game.is_networked() and not p.multiplayer.is_server():
		return {"killed": false, "headshot": false, "damage": 0}
	var headshot := allow_headshot and p._point_hits_head(point)
	var dmg := roundi(base_damage * (headshot_mult if headshot else 1.0))
	# Armour first, then HP (#144). One shield plate absorbs 40 damage.
	var absorbed := mini(roundi(p.armour), dmg)
	if absorbed > 0:
		dmg -= absorbed
		p.set_armour(p.armour - float(absorbed))
	if dmg > 0:
		p.since_hurt = 0.0
	var old_hp := Game.hp_of(p)
	var new_hp := maxf(old_hp - float(dmg), 0.0)
	Game.set_hp(p, new_hp)
	Game.note_damage(killer_peer_id, p.peer_id, old_hp - new_hp)
	var killed := new_hp <= 0.0
	if killed:
		Game.register_kill(killer_peer_id, p.peer_id, weapon_id, headshot)
		Game.send_death_report(killer_peer_id, p.peer_id, weapon_id)
	# #150: bots turn toward the pawn that hit them. A low HP hit also breaks the trade.
	var attacker := Game.player_for_peer(killer_peer_id)
	if dmg > 0 and not killed and p.is_bot and p._bot_brain != null and attacker != null and attacker != p:
		p._bot_brain.note_threat(attacker)
	if dmg <= 0:
		source_pos = Vector3.INF
	elif not source_pos.is_finite():
		if attacker and attacker != p:
			source_pos = attacker.global_position
	if Game.is_networked():
		Game.broadcast_hurt.rpc(p.peer_id, new_hp, killed, source_pos, roundi(p.armour))
	else:
		p.apply_hurt_state(new_hp, killed, source_pos, roundi(p.armour))
	return {"killed": killed, "headshot": headshot, "damage": dmg}


## True when the capsule hit lands on the drawn head, including while crouched.
static func point_hits_head(p: Player, point: Vector3) -> bool:
	var center := p.global_position + Vector3(0.0, lerpf(p.HEAD_STAND_Y, p.HEAD_CROUCH_Y, p.crouch), 0.0)
	var mark := p.body_mesh.get_node_or_null("HeadHit") if p.body_mesh else null
	if mark is Node3D:
		center = (mark as Node3D).global_position
	return point.distance_to(center) <= p.HEAD_HIT_R


## `from_pos`: damage source for the HUD direction indicator (Vector3.INF = unknown).
static func apply_hurt_state(p: Player, new_hp: float, killed: bool, from_pos: Vector3 = Vector3.INF, armour_now := -1) -> void:
	p.hp = new_hp
	if armour_now >= 0:
		p.armour = float(armour_now)
		p.armour_changed.emit(p.armour)
	if not killed:
		Game.killcam.note_hurt(p.peer_id)
	if p.is_local() and from_pos.is_finite():
		p.damage_from.emit(from_pos)
	if p.is_local():
		p.camera.add_shake(0.85, randf_range(-0.35, 0.35), 2.2)
		if p.hurt_sfx.stream:
			p.hurt_sfx.pitch_scale = randf_range(0.92, 1.08)
			p.hurt_sfx.play()
		p.health_changed.emit(p.hp, p.MAX_HP)
	if killed:
		if not p.is_local():
			PhysFx.tumble(p, from_pos)
		p._die()


static func die(p: Player) -> void:
	if p.is_dead:
		return
	p.is_dead = true
	p._lunge_left = 0.0
	# The RC is gone with you, and it does not explode on the way out.
	# LOS ends the same way: camera back on the body, no bash from a corpse.
	if p.is_local() and Game.rc_view:
		RcXd.release_view()
	var los_id := p.peer_id if p.peer_id != 0 else p._owner_peer()
	if Game._is_match_authority():
		RcXd.abort_for(p.peer_id)
		LosHands.abort_for(los_id)
	elif p.is_local():
		LosHands.abort_for(los_id)
	Game.killcam.note_death(p.peer_id)
	p.velocity = Vector3.ZERO
	# #252: dying ends a reload. The weapon tells the other clients (a 0 on sync_reload) so a corpse and
	# the respawned body never show a hand stuck on the mag.
	if p.weapon != null:
		p.weapon.cancel_reload()
	p._carry_t = 0.0
	p._was_surfing = false
	p._grapple.release()
	p.grappling = false
	p.collision_layer = 0
	if p.is_local():
		p.weapon.visible = false
		p.died.emit()
	else:
		p.body_mesh.visible = false
		p.weapon.visible = false
	if Game.is_offline or p.multiplayer.is_server():
		p.get_tree().create_timer(p.RESPAWN_TIME).timeout.connect(p._server_respawn)


static func apply_respawn_state(p: Player) -> void:
	p.hp = p.MAX_HP
	# Armour does not survive a death (#144).
	if p.armour != 0.0:
		p.set_armour(0.0)
	# Round-start respawns come through here too; the server's HP copy must reset with them.
	if Game._is_match_authority():
		Game.set_hp(p, p.MAX_HP)
	p.is_dead = false
	p._spawn_protect = p.SPAWN_PROTECT
	p.collision_layer = 2
	p.velocity = Vector3.ZERO
	p.crouch = 0.0
	p.is_sprinting = false
	p.global_transform = p._spawn_xform
	p._yaw = p.rotation.y
	p._pitch = 0.0
	p._reset_style_track()
	p.head.rotation.x = 0.0
	p.weapon.visible = true
	if not p.loadout.is_empty() and p.weapon:
		p.weapon.set_slots(p.weapon_ids()) # spawn holding the primary
	p.grenades = p.grenade_max()
	p.knives = p.knife_max()
	p._notify_grenades()
	if p.weapon:
		p.weapon.refill()
	p._apply_stance()
	p._apply_team_visual()
	if p.is_local():
		p.health_changed.emit(p.hp, p.MAX_HP)
		p.respawned.emit()
	else:
		p.body_mesh.visible = true
