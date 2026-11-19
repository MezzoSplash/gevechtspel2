class_name PawnBody
extends RefCounted
## How a pawn looks (#316): the name tag, the crystal body and its arms, the team colour, the stance
## (capsule, eye and the crouch that stays under a low ceiling), the body pose (roll flip, knife throw,
## reload), the pickup flash and the grapple rope with the reaching hand. Static on the pawn `p`, like
## Movement; Player keeps the nodes, the state and its old function names. `team_color`, `paint_body`
## and `pose_body` need no pawn: the killcam ghosts, the HUD and the minimap call them too.


static func set_display_name(p: Player, n: String) -> void:
	p.display_name = n
	if p.nametag:
		p.nametag.text = n
		p.nametag.modulate = team_color(p.team_id)


## #164: the crystal body is visuals only; a dedicated server never builds it.
static func arms_enabled(p: Player) -> bool:
	return not Game.is_dedicated and p.body_mesh != null and p.weapon != null


## #164: B1 crystal body with floating hands that hold the gun (CrystalBody).
static func attach_arms(p: Player) -> void:
	if arms_enabled(p):
		CrystalBody.attach(p.body_mesh, p.weapon)


## Body/tag/feed colour of a team. FFA has no teams: everyone gets FFA_COLOR.
static func team_color(team: int) -> Color:
	if Game.is_ffa():
		return Player.FFA_COLOR
	var pal: Array = Game.COLORBLIND_TEAMS[Game.colorblind] if Game.colorblind > 0 else Player.TEAM_COLORS
	return pal[clampi(team, 0, pal.size() - 1)]


## Team colour on a body material. Also used for the killcam ghosts.
static func paint_body(mat: StandardMaterial3D, team: int) -> void:
	var col: Color = team_color(team)
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.45
	mat.emission_energy_multiplier = 0.7


static func update_stance(p: Player, delta: float, _on_floor: bool) -> void:
	var want := p._sliding or p._diving or p._roll_t > 0.0 or ((not p.is_dead) and p._in_crouch)
	if (not want) and p.crouch > 0.05 and ceiling_blocked(p):
		want = true
	var target := 1.0 if want else 0.0
	p.crouch = move_toward(p.crouch, target, p.CROUCH_BLEND * delta)
	apply_stance(p)


static func apply_stance(p: Player) -> void:
	if p._capsule == null:
		return
	var h := lerpf(p.STAND_CAPSULE, p.CROUCH_CAPSULE, p.crouch)
	p._capsule.height = h
	p.col_shape.position.y = h * 0.5
	p.head.position.y = lerpf(p.STAND_EYE, p.CROUCH_EYE, p.crouch)
	pose_figure(p)


static func pose_figure(p: Player) -> void:
	pose_body(p.body_mesh, p.crouch, p.move_fx, roll_flip(p), throw_amt(p), p.reload_amt(), p.reload_style())


static func ceiling_blocked(p: Player) -> bool:
	var space := p.get_world_3d().direct_space_state
	var from := p.global_position + Vector3(0.0, p.CROUCH_CAPSULE + 0.02, 0.0)
	var to := p.global_position + Vector3(0.0, p.STAND_CAPSULE + 0.02, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [p.get_rid()]
	return space.intersect_ray(query).has("collider")


## A pickup did something to this pawn: a short HUD flash in its colour plus a chime.
static func play_pickup_flash(p: Player, t: StringName) -> void:
	if not p.is_local():
		return
	var info := Pickups.type_info(t)
	if p.pickup_sfx and p.pickup_sfx.stream:
		p.pickup_sfx.pitch_scale = float(info["pitch"])
		p.pickup_sfx.play()
	var h := p.get_tree().get_first_node_in_group("hud") as Hud
	if h == null or not h.has_method("flash_pickup"):
		return
	# The popup says what happened, not which type it was (#246 review).
	var text := String(info["label"])
	match t:
		&"knives":
			text = "MESSEN +%d" % Pickups.KNIVES
		&"shield":
			text = "SCHILD"
		&"heal":
			text = "+%d HP" % roundi(Pickups.HEAL)
	h.flash_pickup(text, info["color"])
	if t == &"knives" and h.has_method("blink_knives"):
		h.blink_knives()


## 0..1 through the throw: wind up, then snap forward. Visual only.
static func throw_amt(p: Player) -> float:
	if p._throw_t <= 0.0:
		return 0.0
	var t := 1.0 - p._throw_t / p.THROW_ANIM_TIME
	if t < 0.45:
		return smoothstep(0.0, 0.45, t) # behind the shoulder
	return smoothstep(0.45, 1.0, t) # follow through


## The landing roll as a rotation for the body, the same forward flip the local camera does (#205).
## 0 outside a roll, so a body that is not tumbling reads as flat.
static func roll_flip(p: Player) -> float:
	if p._roll_t <= 0.0:
		return 0.0
	var pr := 1.0 - p._roll_t / p.ROLL_TIME
	return -TAU * ease(pr, -1.8)


## Puts the head marker (the hit target) on the stance's head height and hands the synced state to
## the crystal body (CrystalBody/BodyPose), which poses itself every frame.
static func pose_body(body: Node3D, crouch_amt: float, fx := Player.MOVE_NONE, flip := 0.0, throw := 0.0, reload := 0.0, reload_kind: StringName = &"mag") -> void:
	if body == null:
		return
	var head_y := lerpf(Player.HEAD_STAND_Y, Player.HEAD_CROUCH_Y, crouch_amt)
	var hit := body.get_node_or_null("HeadHit") as Node3D
	if hit:
		hit.position.y = head_y
	var crystal := CrystalBody.ensure(body)
	if crystal:
		crystal.crouch = crouch_amt
		crystal.head_y = head_y
		crystal.move_fx = fx
		crystal.flip = flip
		crystal.throw_amt = throw
		crystal.reload_amt = reload
		crystal.reload_style = reload_kind


## Every machine, every frame: the rope from the reaching hand to the anchor, and the hand itself.
static func draw_grapple(p: Player) -> void:
	if Game.is_dedicated:
		return
	var on := p.grappling and not p.is_dead
	var crystal := p.body_mesh.get_node_or_null("Crystal") as CrystalBody if p.body_mesh else null
	if crystal:
		crystal.grapple_on = on
		crystal.grapple_at = p.grapple_at
	var view_hands := p.camera.get_node_or_null("ViewHands") as CrystalHands if p.camera and p.is_local() else null
	if view_hands:
		view_hands.reach[0] = [view_hands.reach_toward(0, p.grapple_at, p.GRAPPLE_VIEW_ARM), 1.0] if on else [Vector3.ZERO, 0.0]
	if not on and p.get_node_or_null("GrappleRope") == null:
		return
	var from := p.global_position + Vector3.UP * Grapple.CHEST
	var hands: CrystalHands = view_hands if view_hands else (crystal.hands if crystal else null)
	if hands and hands.get_child_count() > 0:
		from = (hands.get_child(0) as Node3D).global_position
	GrappleRope.ensure(p).show_line(on, from, p.grapple_at)
