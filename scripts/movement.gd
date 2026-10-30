class_name Movement
extends RefCounted
## Player movement (#106): slide, surf contact and carry, speed strips, Quake/Source accel, wallrun +
## wall jump, dive + roll. Static helpers on the pawn `p`; Player keeps all state, constants, the
## synced properties and thin wrappers under the old names, so nothing on the network changes.

## Sprint, or already faster than a walk, plus crouch. Plain crouch stays the slow stance.
static func try_start_slide(p: Player, on_floor: bool, locked: bool) -> void:
	if p._sliding or locked or p.is_dead or not on_floor:
		return
	if not Input.is_action_just_pressed("crouch"):
		return
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if not p.is_sprinting and speed < Player.WALK_SPEED * 1.05:
		return
	p._sliding = true
	p._slide_t = 0.0
	p._slide_dir = Vector3(p.velocity.x, 0.0, p.velocity.z)
	if p._slide_dir.length_squared() < 0.04:
		p._slide_dir = -p.transform.basis.z
	p._slide_dir = p._slide_dir.normalized()
	p.crouch = 1.0
	if p.slide_sfx:
		p.slide_sfx.play()


## Minimum time so a tap still slides. After that: release, slow down, or a wall ends it.
static func finish_slide(p: Player) -> void:
	if not p._sliding:
		return
	p._slide_t += p.get_physics_process_delta_time()
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	var release := not Input.is_action_pressed("crouch")
	var slow := speed < Player.WALK_SPEED * 0.95
	var wall := false
	for i in p.get_slide_collision_count():
		var n := p.get_slide_collision(i).get_normal()
		if n.y < 0.45:
			wall = true
			break
	if p._slide_t >= Player.SLIDE_MIN and (release or slow or wall or not p.is_on_floor()):
		p._sliding = false


## Quake-style stop: no Godot default air float.
static func friction(vel: Vector3, delta: float) -> Vector3:
	return friction_amount(vel, delta, Player.GROUND_FRICTION)


static func friction_amount(vel: Vector3, delta: float, friction: float) -> Vector3:
	var speed := vel.length()
	if speed < 0.01:
		return Vector3.ZERO
	var control := Player.STOP_SPEED if speed < Player.STOP_SPEED else speed
	var drop := control * friction * delta
	var new_speed := maxf(speed - drop, 0.0)
	return vel * (new_speed / speed)


## Source AirAccelerate: the speed we may add along the wish direction is capped at AIR_WISH_CAP, the
## rate is not. Straight ahead adds nothing once you move; perpendicular (strafe + mouse) bends the
## velocity and adds a little speed, bounded by AIR_MAX_SPEED (speed you already had is kept).
static func air_accelerate(vel: Vector3, wish: Vector3, wish_speed: float, delta: float) -> Vector3:
	if wish.length_squared() < 0.0001 or wish_speed <= 0.0:
		return vel
	var dir := wish.normalized()
	var add := minf(wish_speed, Player.AIR_WISH_CAP) - vel.dot(dir)
	if add <= 0.0:
		return vel
	var before := vel.length()
	var out := vel + dir * minf(Player.AIR_ACCEL * wish_speed * delta, add)
	var limit := maxf(before, Player.AIR_MAX_SPEED)
	var speed := out.length()
	if speed > limit:
		out *= limit / speed
	return out


## Remember a steep ramp we touched this frame (not floor, not a wall): surfing clips against it.
static func note_surf_contact(p: Player) -> void:
	for i in p.get_slide_collision_count():
		var n := p.get_slide_collision(i).get_normal()
		if n.y > Player.SURF_MIN_NORMAL_Y and n.y < Player.SURF_MAX_NORMAL_Y:
			p._surf_normal = n
			p._surf_t = Player.SURF_MEMORY
			return
	# A clipped glide runs parallel to the ramp, so move_and_slide may not touch it every frame.
	if p._surf_t > 0.0 and not p.is_on_floor():
		var hit := KinematicCollision3D.new()
		if p.test_move(p.global_transform, -p._surf_normal * Player.SURF_PROBE, hit):
			var n2 := hit.get_normal()
			if n2.y > Player.SURF_MIN_NORMAL_Y and n2.y < Player.SURF_MAX_NORMAL_Y:
				p._surf_normal = n2
				p._surf_t = Player.SURF_MEMORY


## Surf just ended. Above sprint, keep that speed and add a small shove, capped at CARRY_MAX.
static func begin_carry(p: Player) -> void:
	if p.is_dead or Game.rc_view:
		return
	var horiz := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var speed := horiz.length()
	if speed <= Player.CARRY_ENTER_SPEED:
		return
	horiz = horiz.normalized() * minf(speed + Player.CARRY_EXIT_BOOST, Player.CARRY_MAX)
	p.velocity.x = horiz.x
	p.velocity.z = horiz.z
	p._carry_t = Player.CARRY_TIME
	if p._whoosh:
		p._whoosh.play()


## Local sim: a fast pass through a strip shoves you and refreshes carry. Points are the server's.
static func boost_through_strips(p: Player) -> void:
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	if speed < Player.STRIP_SPEED or p.is_dead or Game.rc_view:
		p._strip_prev = p.global_position
		return
	var prev := p._strip_prev if p._strip_prev.is_finite() else p.global_position
	p._strip_prev = p.global_position
	if prev.distance_to(p.global_position) > Player.STRIP_TELEPORT_M:
		return
	for n in p.get_tree().get_nodes_in_group("speed_strip"):
		var strip := n as Node3D
		if strip == null or not p.segment_hits_strip(strip, prev, p.global_position):
			continue
		var id := str(strip.name)
		if float(p._strip_cd.get(id, 0.0)) > 0.0:
			continue
		p._strip_cd[id] = Player.STRIP_COOLDOWN
		var horiz := Vector3(p.velocity.x, 0.0, p.velocity.z)
		horiz = horiz.normalized() * minf(horiz.length() + Player.STRIP_BOOST, Player.CARRY_MAX)
		p.velocity.x = horiz.x
		p.velocity.z = horiz.z
		p._carry_t = Player.CARRY_TIME
		return


static func tick_strip_cd(p: Player, delta: float) -> void:
	var dead: Array[String] = []
	for id in p._strip_cd:
		p._strip_cd[id] = float(p._strip_cd[id]) - delta
		if float(p._strip_cd[id]) <= 0.0:
			dead.append(str(id))
	for id in dead:
		p._strip_cd.erase(id)


static func accelerate(vel: Vector3, wish: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	if wish.length_squared() < 0.0001:
		return vel
	var wish_dir := wish.normalized()
	var current := vel.dot(wish_dir)
	var add := wish_speed - current
	if add <= 0.0:
		return vel
	var acc := minf(accel * wish_speed * delta, add)
	return vel + wish_dir * acc


## Along the wall only, never slower than WALLRUN_KEEP_SPEED while it lasts; a little steering.
static func wallrun_horiz(p: Player, horiz: Vector3, wish: Vector3, delta: float) -> Vector3:
	var n := Vector3(p._wall_n.x, 0.0, p._wall_n.z).normalized()
	var along := horiz - n * horiz.dot(n)
	if wish.length_squared() > 0.01:
		var wdir := wish - n * wish.dot(n)
		if wdir.length_squared() > 0.0001:
			along = accelerate(along, wdir.normalized(), maxf(along.length(), Player.SPRINT_SPEED), Player.GROUND_ACCEL * 0.25, delta)
	return along - n * 0.6 # lean in a little so move_and_slide keeps touching the wall


## A near-vertical wall beside us: contact from move_and_slide, else a short probe left/right.
static func find_wall(p: Player) -> Dictionary:
	for i in p.get_slide_collision_count():
		var c := p.get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) < Player.WALLRUN_MAX_NY:
			return {"n": n, "key": "%d:%s" % [c.get_collider_id(), str(n.snapped(Vector3(0.25, 0.25, 0.25)))]}
	var horiz := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if horiz.length_squared() < 1.0:
		return {}
	var side := horiz.normalized().cross(Vector3.UP)
	var space := p.get_world_3d().direct_space_state
	var from := p.global_position + Vector3(0.0, 0.9, 0.0)
	var dirs: Array[Vector3] = [side, -side]
	if p._wallrunning:
		dirs = [-Vector3(p._wall_n.x, 0.0, p._wall_n.z).normalized()]
	for d in dirs:
		var q := PhysicsRayQueryParameters3D.create(from, from + d * Player.WALLRUN_PROBE)
		q.collision_mask = 1
		q.exclude = [p.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if absf(n.y) < Player.WALLRUN_MAX_NY:
			return {"n": n, "key": "%d:%s" % [int(hit.collider_id), str(n.snapped(Vector3(0.25, 0.25, 0.25)))]}
	return {}


static func tick_wallrun(p: Player, delta: float, input_vec: Vector2, locked: bool) -> void:
	var on_floor := p.is_on_floor()
	if on_floor:
		p._wall_key = "" # the ground resets every wall
		p._wallruns_air = 0
		if p._wallrunning:
			end_wallrun(p)
		p._wall_off_t = 10.0
		return
	if p._wallrunning:
		p._wallrun_t += delta
		p._wall_off_t = 0.0
		var w := find_wall(p)
		var along := Vector3(p.velocity.x, 0.0, p.velocity.z).length()
		var drop := (not Input.is_action_pressed("sprint")) or Input.is_action_pressed("crouch")
		if w.is_empty() or p._wallrun_t >= Player.WALLRUN_TIME or along < Player.WALLRUN_KEEP_SPEED or drop or p.is_dead or locked:
			end_wallrun(p)
		else:
			p._wall_n = w.n
		return
	p._wall_off_t += delta
	if p.is_dead or locked or p.is_bot or p._surf_t > 0.0 or p._diving or p._wallruns_air >= Player.WALLRUN_PER_AIR:
		return
	if not Input.is_action_pressed("sprint") or input_vec.y > -0.3:
		return
	var w := find_wall(p)
	if w.is_empty() or str(w.key) == p._wall_key:
		return
	var n: Vector3 = w.n
	var horiz := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var along := horiz - Vector3(n.x, 0.0, n.z).normalized() * horiz.dot(Vector3(n.x, 0.0, n.z).normalized())
	if along.length() < Player.WALLRUN_MIN_SPEED:
		return
	p._wallrunning = true
	p._wall_n = n
	p._wall_key = str(w.key)
	p._wallrun_t = 0.0
	p._wall_off_t = 0.0
	p._wallruns_air += 1
	p._sliding = false


static func end_wallrun(p: Player) -> void:
	p._wallrunning = false
	p._wall_off_t = 0.0


## Off the wall: away from it, up, and along it with the speed you had. The wall stays "used".
static func wall_jump(p: Player) -> void:
	var n := Vector3(p._wall_n.x, 0.0, p._wall_n.z).normalized()
	if n.length_squared() < 0.5:
		return
	var horiz := Vector3(p.velocity.x, 0.0, p.velocity.z)
	var along := horiz - n * horiz.dot(n)
	horiz = along + n * Player.WALLJUMP_PUSH
	p.velocity.x = horiz.x
	p.velocity.z = horiz.z
	p.velocity.y = Player.WALLJUMP_UP
	p._wallrunning = false
	p._wall_off_t = 10.0
	p._dive_used = false # a wall jump earns a fresh dive
	p.walljumps += 1
	if p.land_sfx:
		p.land_sfx.play()


## In the air: crouch pressed while holding sprint and moving. On the ground the slide jump does it.
static func try_air_dive(p: Player, on_floor: bool, locked: bool) -> void:
	if on_floor or locked or p.is_dead or p.is_bot or p._diving or p._dive_used or p._wallrunning or p._surf_t > 0.0:
		return
	if not Input.is_action_just_pressed("crouch") or not Input.is_action_pressed("sprint"):
		return
	if Vector2(p.velocity.x, p.velocity.z).length() < Player.DIVE_MIN_SPEED:
		return
	start_dive(p, false)


static func start_dive(p: Player, from_ground: bool) -> void:
	var dir := Vector3(p.velocity.x, 0.0, p.velocity.z)
	if dir.length_squared() < 0.04:
		dir = -p.transform.basis.z
	dir = dir.normalized()
	var speed := minf(maxf(Vector2(p.velocity.x, p.velocity.z).length(), Player.SPRINT_SPEED) + Player.DIVE_BOOST, Player.DIVE_MAX)
	p.velocity.x = dir.x * speed
	p.velocity.z = dir.z * speed
	p.velocity.y = Player.DIVE_UP_GROUND if from_ground else maxf(p.velocity.y, Player.DIVE_UP_AIR)
	p._diving = true
	p._dive_used = true
	p._roll_dir = dir
	p.crouch = 1.0
	p._apply_stance()
	if p.slide_sfx:
		p.slide_sfx.play()


static func tick_dive_roll(p: Player, delta: float) -> void:
	if p._roll_t > 0.0:
		p._roll_t = maxf(p._roll_t - delta, 0.0)
		if p._roll_t <= 0.0 and p.is_on_floor():
			p._carry_t = maxf(p._carry_t, Player.ROLL_CARRY)
	if p.is_on_floor():
		p._dive_used = false
		if p._diving:
			p._diving = false
			p._roll_t = Player.ROLL_TIME
			if p.land_sfx:
				p.land_sfx.play()
			if p.camera:
				p.camera.add_shake(2.5, 0.0, 4.0)
	elif p._diving and (p._surf_t > 0.0 or p._wallrunning or p.is_dead):
		p._diving = false
