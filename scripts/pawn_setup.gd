class_name PawnSetup
extends RefCounted
## How a pawn is set up (#316): _ready (group, collision, capsule, identity and authority, the bot brain,
## the local pawn's own sound players), the enemy audio bus, the loadout at spawn, local or remote
## control (camera, view hands, nametag, mouse), the body material and the team colour. Static on the
## pawn `p`, like Movement; Player keeps the nodes, the state and its old function names.


static func ready(p: Player) -> void:
	p._style = StyleTrack.new(p)
	p.add_to_group("player")
	Game.invalidate_roster() # #272: a pawn that appeared mid-tick must be seen at once
	p.floor_snap_length = 0.2
	p.collision_layer = 2
	p.collision_mask = 1
	p._spawn_xform = p.global_transform
	p._yaw = p.rotation.y # Orange spawns turned 180°; the first mouse move must not snap back
	p._capsule = p.col_shape.shape.duplicate() as CapsuleShape3D
	p.col_shape.shape = p._capsule
	if p.peer_id == 0:
		p.peer_id = p._owner_peer()
	p._dup_body_mat()
	p._attach_arms()
	p._apply_team_visual()
	p._init_loadout()
	# Bots/offline skip MultiplayerSynchronizer; bot poses are Game.sync_bot_poses.
	if p.has_node("Sync") and (Game.is_offline or p.is_bot or p.peer_id < 0):
		p.get_node("Sync").public_visibility = false
	if Game.is_offline:
		pass
	elif p.is_bot or p.peer_id < 0:
		p.set_multiplayer_authority(1, true)
	elif p.peer_id > 0:
		p.set_multiplayer_authority(p.peer_id, true)
	p._spawn_protect = p.SPAWN_PROTECT
	p._feet_last = p.global_position
	if p.is_bot and (Game.is_offline or p.multiplayer.is_server()):
		p._bot_brain = p.Brain.new()
		p._bot_brain.setup(p, p.get_node_or_null("NavigationAgent3D") as NavigationAgent3D)
	if p.is_bot:
		p.call_deferred("_apply_bot_loadout")
	if p.is_local():
		p._whoosh = AudioStreamPlayer.new()
		p._whoosh.stream = p.WHOOSH
		p._whoosh.bus = "SFX"
		p._whoosh.volume_db = -4.0
		p.add_child(p._whoosh)
		# Its own node: the carry whoosh belongs to Movement, with its own pitch.
		p._los_sfx = AudioStreamPlayer.new()
		p._los_sfx.stream = p.WHOOSH
		p._los_sfx.bus = "SFX"
		p._los_sfx.volume_db = -2.0
		p.add_child(p._los_sfx)
		p._wind = AudioStreamPlayer.new()
		p._wind.stream = p.looped_wind()
		p._wind.bus = "SFX"
		p._wind.volume_db = p.WIND_VOL_DB_MIN
		p.add_child(p._wind)
	p.call_deferred("_configure_control")


## Enemy pawns play their shots and movement on the "Enemies" bus (own slider, #59). Teams can change
## mid-match, so this is re-checked twice a second rather than once at spawn.
static func tick_audio_bus(p: Player, delta: float) -> void:
	p._bus_check_t -= delta
	if p._bus_check_t > 0.0:
		return
	p._bus_check_t = 0.5
	var bus := "SFX"
	if not p.is_local() and not Game.is_dedicated:
		# #370: a teammate's shots have to be as present as an enemy's, so every other player's weapons and
		# steps go on the same bus. That slider is "andere spelers" in practice; its label still says
		# enemies and is worth a look.
		bus = "Enemies"
	for path in p.ENEMY_SFX_NODES:
		var n := p.get_node_or_null(path)
		if n and n.get("bus") != null and n.bus != bus:
			n.bus = bus


## Server: what this peer picked (or the default). Owner: what the server last confirmed.
static func init_loadout(p: Player) -> void:
	if p.is_bot or p.peer_id < 0:
		return
	if Game._is_match_authority():
		p.loadout = Game.loadouts.spawn_loadout(p.peer_id)
	elif p.is_local():
		var mine := Game.loadouts.mine
		p.loadout = mine.duplicate(true) if not mine.is_empty() else PlayerClasses.default_loadout()
	else:
		return
	p.apply_loadout()


## Local: hide body, capture mouse. Remote/bot: show mesh, nametag, world gun.
static func configure_control(p: Player) -> void:
	p._apply_team_visual()
	if p.weapon:
		p.weapon.refit_view() # third-person guns sit closer to the body (B1)
	if p.is_local():
		p.body_mesh.visible = false
		p.weapon.visible = true
		if p._arms_enabled() and p.camera.get_node_or_null("ViewHands") == null:
			var crystal := p.body_mesh.get_node_or_null("Crystal") as CrystalBody
			CrystalHands.attach_view(p.camera, p.weapon, crystal.glow if crystal else p._body_mat) # #164: first-person crystal hands
		p.nametag.visible = false
		# Online the server's (deduplicated) name from the spawn data wins.
		if Game.player_name != "" and not Game.is_networked():
			p.set_display_name(Game.player_name)
		p.make_active_camera()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Game.local_player_ready.emit(p)
		p.health_changed.emit(p.hp, p.MAX_HP)
		p._notify_grenades()
		if Game.is_networked() and not p.multiplayer.is_server():
			Game.submit_display_name.rpc_id(1, Game.player_name)
	else:
		p.body_mesh.visible = not p.is_dead
		p.camera.current = false
		p.weapon.visible = true
		p.set_display_name(p.display_name)
		p._update_nametag(0.0, true)


static func dup_body_mat(p: Player) -> void:
	if p.body_mesh == null:
		return
	var src_mesh := p.body_mesh.get_node_or_null("Torso") as MeshInstance3D
	var src: Material = src_mesh.get_active_material(0) if src_mesh else null
	if src is StandardMaterial3D:
		p._body_mat = (src as StandardMaterial3D).duplicate()
	else:
		p._body_mat = StandardMaterial3D.new()
	for child in p.body_mesh.get_children():
		var part := child as MeshInstance3D
		if part:
			part.set_surface_override_material(0, p._body_mat)
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func apply_team_visual(p: Player) -> void:
	var col: Color = p.team_color(p.team_id)
	if p._body_mat:
		p.paint_body(p._body_mat, p.team_id)
	if p.nametag:
		p.nametag.modulate = col
	var crystal := p.body_mesh.get_node_or_null("Crystal") as CrystalBody if p.body_mesh else null
	if crystal:
		crystal.repaint(col)
