extends Node3D
## #342: the frag is a faceted crystal (GrenadeLook), not a green sphere. One look for every copy (the
## flying grenade and the killcam's), a fuse band that turns red over the last DANGER_TIME, a tumble
## and a streak from its own motion, the thrower's team on the cap, and a boom that bursts into shards
## reaching the splash radius plus a ring over the ground.
##   godot --headless res://tools/check_grenade_look.tscn
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _ready() -> void:
	# 1) The shape: a crystal of about 0.22 m, the band round its widest ring, the cap on top.
	var aabb := CrystalMesh.part(&"grenade").get_aabb()
	_ok(aabb.size.y > 0.2 and aabb.size.y < 0.24, "frag is ~0.22 m tall (%.3f)" % aabb.size.y)
	_ok(aabb.size.x > 0.14 and aabb.size.x < 0.22, "frag is ~0.16-0.18 m wide (%.3f)" % aabb.size.x)
	var band := CrystalMesh.part(&"grenade_seam").get_aabb()
	_ok(band.size.x > aabb.size.x, "the band sits outside the body (%.3f > %.3f)" % [band.size.x, aabb.size.x])

	# 2) The fuse band: ice, then red over the last DANGER_TIME; the pulse speeds up.
	_ok(GrenadeLook.band_color(Grenade.FUSE).is_equal_approx(CrystalStyle.ICE), "band is ice at the throw")
	_ok(GrenadeLook.band_color(GrenadeLook.DANGER_TIME + 0.01).is_equal_approx(CrystalStyle.ICE), "still ice just before the danger window")
	_ok(GrenadeLook.band_color(0.0).is_equal_approx(CrystalUi.DANGER), "band is the danger red at the boom")
	_ok(is_equal_approx(GrenadeLook.danger(GrenadeLook.DANGER_TIME * 0.5), 0.5), "half way through the window is half red")
	_ok(GrenadeLook.pulse_rate(0.1) > GrenadeLook.pulse_rate(0.6) and GrenadeLook.pulse_rate(0.6) > GrenadeLook.pulse_rate(Grenade.FUSE), "the pulse speeds up toward the boom")
	_ok(GrenadeLook.band_color(INF).is_equal_approx(CrystalStyle.ICE) and GrenadeLook.pulse_rate(INF) == GrenadeLook.PULSE_SLOW, "no fuse (killcam): calm ice")
	_ok(GrenadeLook.trail_length(5.0) == 0.0 and is_equal_approx(GrenadeLook.trail_length(30.0), GrenadeLook.TRAIL_LEN), "streak only when fast")

	# 3) A look in motion tumbles and streaks; at rest it does neither.
	var look := GrenadeLook.new()
	add_child(look)
	var b0 := look.spin.basis
	for i in 10:
		look.global_position += Vector3(0.3, 0.0, 0.0) # 18 m/s at 60 fps
		look.tick(1.0 / 60.0)
	_ok(not look.spin.basis.is_equal_approx(b0), "it tumbles while flying")
	_ok(look.trail.visible and look.trail.scale.z > 0.3, "it streaks at throw speed (%.2f m)" % look.trail.scale.z)
	look.global_position += Vector3(0.075, 0.0, 0.0) # 18 m/s, drawn at 240 fps: one moving frame,
	look.tick(1.0 / 240.0) # then three that see none; still the same throw
	for i in 3:
		look.tick(1.0 / 240.0)
	_ok(look.trail.visible, "frames between physics ticks keep the streak")
	for i in 12:
		look.tick(1.0 / 60.0)
	_ok(not look.trail.visible, "no streak once it lies still")
	look.fuse_left = 0.05
	look.tick(1.0 / 60.0)
	_ok(look.band.material_override.emission.r > 0.8 and look.band.material_override.emission.b < 0.5, "the band is red right before the boom")

	# 4) The cap carries the thrower's team in team modes, and stays pale in FFA.
	var old_mode := Game.mode
	Game.mode = Game.MODE_TDM
	look.set_team(1)
	var cap := look.cap.material_override as StandardMaterial3D
	_ok(cap.emission_enabled and cap.emission.is_equal_approx(Player.team_color(1)), "team mode: the cap glows in the thrower's team colour")
	Game.mode = Game.MODE_FFA
	look.set_team(1)
	_ok(not (look.cap.material_override as StandardMaterial3D).emission_enabled, "FFA: the cap stays pale")
	Game.mode = old_mode
	look.queue_free()

	# 5) A flying grenade carries the look and runs its fuse on it.
	var g := Grenade.spawn_visual(self, Vector3(0.0, 30.0, 0.0), Vector3(4.0, 0.0, 0.0))
	_ok(g.look is GrenadeLook and g.look.get_parent() == g, "a grenade builds a GrenadeLook")
	var spheres := 0
	for n in g.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh is SphereMesh:
			spheres += 1
	_ok(spheres == 0, "no sphere left on the grenade")
	await get_tree().create_timer(0.95).timeout
	_ok(g.look.fuse_left < GrenadeLook.DANGER_TIME and g.look.fuse_left > 0.0, "the fuse runs on the look (%.2f s left)" % g.look.fuse_left)
	g.queue_free()

	# 6) The killcam's replay grenades are the same look, not a second copy of the old ball.
	var kc := FileAccess.get_file_as_string("res://scripts/killcam.gd")
	_ok(kc.contains("GrenadeLook.new()") and not kc.contains("SphereMesh"), "the killcam builds GrenadeLook, no sphere")

	# 7) The boom: shards end inside the splash radius, near its edge, and a ring runs out to it.
	var shards := Grenade.spawn_shards(self, Vector3.ZERO, Grenade.RADIUS)
	_ok(shards.size() == Grenade.SHARDS, "%d shards" % shards.size())
	var inside := true
	for s in shards:
		var d: float = (s.get_meta("end") as Vector3).length()
		inside = inside and d >= Grenade.RADIUS * Grenade.SHARD_REACH_MIN - 0.01 and d <= Grenade.RADIUS + 0.01
	_ok(inside, "every shard ends between %.0f%% and 100%% of the splash radius" % (Grenade.SHARD_REACH_MIN * 100.0))
	var ring := Grenade.spawn_shock_ring(self, Vector3.ZERO, Grenade.RADIUS)
	_ok(is_equal_approx(float(ring.get_meta("reach")), Grenade.RADIUS), "the ring runs out to the splash radius")
	await get_tree().create_timer(Grenade.RING_TIME + 0.3).timeout
	_ok(not is_instance_valid(ring) and not is_instance_valid(shards[0]), "shards and ring clean themselves up")

	print("GRENADE LOOK CHECK: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)
