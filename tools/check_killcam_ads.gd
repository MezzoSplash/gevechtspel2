extends Node
## #381: the killcam replays what the killer's sights were doing. Synthetic frames in the recorder's own
## format (index 10 = the ADS blend), played through the real playback: the camera FOV, the viewmodel's
## ADS pose, and the sniper scope (model hidden, scope drawn). Old frames without the field are hip.
##   ./run.sh --headless res://tools/check_killcam_ads.tscn   → "KILLCAM ADS CHECK OK"
var fails := 0


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _frame(t: float, ads: float, wi: int, grappling := false) -> Array:
	return [t, {1: [Vector3(0, 0, 0), 0.0, 0.0, 0.0, wi, true, 0, 0.0, 0.0, 0.0, ads, grappling, Vector3.ZERO]}, PackedVector3Array(), []]


func _index_of(id: StringName) -> int:
	for i in Weapon.LOADOUT.size():
		if Weapon.LOADOUT[i].id == id:
			return i
	return 0


## A fresh replay of three snapshots: hip, half, full ADS.
func _play(frames: Array) -> Killcam:
	var kc := Killcam.new()
	add_child(kc)
	kc._clips[1] = {"t_kill": float(frames[1][0]), "frames": frames, "events": [], "meta": {1: ["K", 0]}}
	kc.play_final({"k": 1, "v": 1, "kt": 0, "vt": 0, "kn": "K", "vn": "V", "w": "rifle"})
	return kc


func _ready() -> void:
	var rifle := _index_of(&"rifle")
	var sniper := _index_of(&"sniper")
	var rifle_def: WeaponDef = Weapon.LOADOUT[rifle]

	# 1) Hip on the first snapshot: the replay camera keeps the settings FOV and the viewmodel its rest.
	var kc := _play([_frame(1.0, 0.0, rifle), _frame(1.1, 0.0, rifle), _frame(1.2, 0.0, rifle)])
	_ok(kc.is_playing(), "the replay plays")
	KillcamPuppets.apply_frames(kc, 1.0)
	var g: Dictionary = kc._ghosts[1]
	var cam := g.pivot as Camera3D
	_ok(is_equal_approx(cam.fov, Game.fov), "hip: the camera keeps the settings FOV (%.1f)" % cam.fov)
	_ok(not kc._scope, "hip: no scope")
	_ok((g.model as Node3D).visible, "hip: the gun is drawn")
	var rest := Vector3((g.fit as Dictionary).root)
	_ok((g.gun_root as Node3D).position.is_equal_approx(rest), "hip: the viewmodel sits at its rest pose")

	# 2) Full ADS: the camera goes to the gun's ads_fov and the gun to the sight point.
	var kc_ads := _play([_frame(1.0, 0.0, rifle), _frame(1.1, 1.0, rifle), _frame(1.2, 1.0, rifle)])
	KillcamPuppets.apply_frames(kc_ads, 1.2)
	g = kc_ads._ghosts[1]
	cam = g.pivot as Camera3D
	_ok(is_equal_approx(cam.fov, rifle_def.ads_fov), "ADS: the camera goes to the rifle's ads_fov (%.1f)" % cam.fov)
	var ads_pose := Weapon.ads_pose_for(g.fit, rest)
	_ok((g.gun_root as Node3D).position.is_equal_approx(ads_pose), "ADS: the viewmodel moves to the sight point")
	_ok((g.model as Node3D).visible, "ADS: the rifle model stays (iron sights)")
	_ok(not kc_ads._scope, "ADS: a rifle is not a scope")
	kc_ads._end_playback()

	# 3) A sniper scoped: the model is hidden and the overlay gets the scope.
	var kc2 := _play([_frame(1.0, 0.0, sniper), _frame(1.1, 1.0, sniper), _frame(1.2, 1.0, sniper)])
	KillcamPuppets.apply_frames(kc2, 1.2)
	var g2: Dictionary = kc2._ghosts[1]
	_ok(kc2._scope, "a scoped sniper sets the scope overlay")
	_ok(not (g2.model as Node3D).visible, "a scoped sniper hides its model")
	_ok(is_equal_approx((g2.pivot as Camera3D).fov, (Weapon.LOADOUT[sniper] as WeaponDef).ads_fov),
		"the scope camera uses the sniper's ads_fov")
	kc2._end_playback()

	# 4) Half way: the replay blends instead of snapping.
	var kc3 := _play([_frame(1.0, 0.0, rifle), _frame(1.1, 1.0, rifle), _frame(1.2, 1.0, rifle)])
	KillcamPuppets.apply_frames(kc3, 1.05)
	var mid := (kc3._ghosts[1].pivot as Camera3D).fov
	_ok(mid > minf(Game.fov, rifle_def.ads_fov) and mid < maxf(Game.fov, rifle_def.ads_fov),
		"half way the FOV is between hip and ADS (%.1f)" % mid)
	kc3._end_playback()

	# 5) An old frame without the field plays as hip, not as a broken pose.
	var old := _frame(1.1, 0.0, rifle)
	var pawn: Array = (old[1] as Dictionary)[1]
	pawn.remove_at(12)
	pawn.remove_at(11)
	pawn.remove_at(10)
	var kc4 := _play([old, old.duplicate(true), old.duplicate(true)])
	KillcamPuppets.apply_frames(kc4, 1.1)
	var g4: Dictionary = kc4._ghosts[1]
	_ok(is_equal_approx((g4.pivot as Camera3D).fov, Game.fov) and (g4.model as Node3D).visible,
		"a frame from before #381 plays as hip")
	kc4._end_playback()

	print("KILLCAM ADS CHECK: %s (%d failures)" % ["OK" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
