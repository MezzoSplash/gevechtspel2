extends Node
## #373: does a stab actually reach? Runs the real swing (`Game.melee.swing_shank`, so lunge, cone and
## reach are the shipped ones) against a dummy on a flat floor, standing and sprinting, at the distances
## and angles from the issue. A hit shows up as damage on the dummy.
##   godot --headless --path . res://tools/check_shank_reach.tscn
## Expected: standing reaches to SHANK_RANGE, a sprint reaches to lunge + SHANK_RANGE, and a wall or
## 6 m never hits. Before #373 a sprinting stab missed everything closer than ~2.4 m.
const BASE := Vector3(0, 300, 0)
const FWD := Vector3(0, 0, -1)
const HP := 1000.0
## [label, distance, angle off the look direction, wall in between, expected hit standing, expected hit sprinting]
const CASES := [
	["0.8 m recht vooruit", 0.8, 0.0, false, true, true],
	["1.5 m recht vooruit", 1.5, 0.0, false, true, true],
	["2.2 m recht vooruit", 2.2, 0.0, false, true, true],
	["3.5 m recht vooruit", 3.5, 0.0, false, false, true],
	["4.5 m recht vooruit", 4.5, 0.0, false, false, true],
	["1.5 m op 20 graden", 1.5, 20.0, false, true, true],
	["1.5 m op 35 graden", 1.5, 35.0, false, true, true],
	["1.5 m achter een muur", 1.5, 0.0, true, false, false],
	# #373 review: high ping. The client aimed straight ahead, but the server's copy of the target is newer
	# and stands about a metre off that line (10 m/s for 100 ms): it must still be a hit when sprinting.
	["3 m vooruit, 1 m opzij", 3.16, 18.4, false, false, true],
	["2.5 m vooruit, 1.5 m opzij", 2.92, 31.0, false, false, true],
	["6 m recht vooruit", 6.0, 0.0, false, false, false],
]

var fails := 0
var _attacker: Player
var _victim: Player
var _wall: StaticBody3D
var _shank: WeaponDef


func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	return b


func _pawn(peer: int, team: int) -> Player:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Player
	p.peer_id = peer
	# Not a bot: the bot director would tick it and walk it out of the test. Not local either, so nothing
	# moves it and the only thing that decides the stab is the swing itself.
	p.is_bot = false
	p.team_id = team
	p.set_physics_process(false)
	add_child(p)
	# Player.spawn() adds a pawn to this group; resolve() walks it to find a victim.
	p.add_to_group("player")
	return p


func _ready() -> void:
	await get_tree().physics_frame
	_box(BASE + Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	_wall = _box(BASE + Vector3(0, 1.5, -40), Vector3(4, 3, 0.4)) # parked far away until a case needs it
	_attacker = _pawn(-1, 0)
	_victim = _pawn(-2, 1)
	_shank = load("res://data/weapons/shank.tres") as WeaponDef
	for i in 4:
		await get_tree().physics_frame
	_attacker.global_position = BASE
	_attacker.rotation.y = 0.0 # looks down -Z
	await get_tree().physics_frame
	for sprinting in [false, true]:
		print("== %s ==" % ("sprintend" if sprinting else "staand"))
		for c in CASES:
			await _case(String(c[0]), float(c[1]), float(c[2]), bool(c[3]), sprinting, bool(c[5] if sprinting else c[4]))
	await _path_case()
	print("SHANK REACH CHECK %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(1 if fails > 0 else 0)


func _case(label: String, dist: float, deg: float, wall: bool, sprinting: bool, expect: bool) -> void:
	var dir := FWD.rotated(Vector3.UP, deg_to_rad(deg))
	# Only the wall case gets a wall halfway; every other case keeps it parked out of the way.
	_wall.global_position = (BASE + dir * (dist * 0.5) + Vector3(0, 1.5, 0)) if wall else (BASE + Vector3(0, 1.5, -40))
	_victim.global_position = BASE + dir * dist
	# Damage runs through Game.hp_of/set_hp, not the pawn's own field; that is what a hit is read from.
	Game.set_hp(_victim, HP)
	_victim.is_dead = false
	_victim._spawn_protect = 0.0
	_attacker.global_position = BASE
	_attacker._lunge_left = 0.0
	Game.melee.reset()
	await get_tree().physics_frame
	# Speed and weapon go on right before the swing: the pawn ticks between cases and would clear them.
	_attacker.velocity = (FWD * Player.SPRINT_SPEED) if sprinting else Vector3.ZERO
	_attacker.is_sprinting = sprinting
	_attacker.weapon.def = _shank
	_attacker.weapon._melee_cd = 0.0
	var plan: Array = Melee.shank_step(_attacker, Vector3(0, 0, -1), Melee.shank_target(_attacker, Vector3(0, 0, -1)))
	var lunge: float = float(plan[1])
	var hp_before := Game.hp_of(_victim)
	var swung := Game.melee.swing_shank(_attacker)
	var hurt := HP - Game.hp_of(_victim)
	var hit := hurt > 0.0
	var ok := hit == expect
	if not ok:
		fails += 1
	print("  %s %-22s %4.1f m %4.0f graden%s -> %s (%.0f schade)%s" % [
		"PASS" if ok else "FAIL", label, dist, deg, " + muur" if wall else "",
		"HIT" if hit else "MIS", hurt, " lunge %.2f m" % lunge])
	# The wall would stay in the way of the next case, so it goes back to its parking spot.
	_wall.global_position = BASE + Vector3(0, 1.5, -40)
	await get_tree().physics_frame


## #373 review: the hit is judged along the whole step, not only from its end. A full 2.5 m step that ends
## past a body 1.5 m ahead (the server's copy closer than the client planned, or no target picked in time)
## is still a hit, and the same body behind the start is not.
func _path_case() -> void:
	print("== pad van de lunge ==")
	_attacker.global_position = BASE
	_attacker.rotation.y = 0.0
	Game.melee.reset()
	await get_tree().physics_frame
	var start := _attacker.camera.global_position
	var end := start + FWD * Melee.LUNGE_M
	for c in [["lichaam 1.5 m vooruit, stap eindigt erachter", -1.5, true], ["lichaam 1.5 m achter de start", 1.5, false]]:
		_victim.global_position = BASE + Vector3(0, 0, float(c[1]))
		Game.set_hp(_victim, HP)
		_victim.is_dead = false
		_victim._spawn_protect = 0.0
		await get_tree().physics_frame
		var res: Dictionary = Game.melee.resolve(_attacker, start, FWD, Melee.SHANK_RANGE, Melee.DAMAGE, true, end)
		var ok := bool(res.hit) == bool(c[2])
		if not ok:
			fails += 1
		print("  %s %s -> %s" % ["PASS" if ok else "FAIL", String(c[0]), "HIT" if res.hit else "MIS"])
