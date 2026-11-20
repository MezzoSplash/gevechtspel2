class_name GrenadeLook
extends Node3D
## The frag as the player sees it (#342): a faceted olive crystal (art guide: frag #26732E, emission is
## for the frag) with a fuse band round its middle and a pale cap. One source for every copy: the
## flying grenade on each machine and the killcam's replay grenades build this same node.
## It tumbles along its flight, trails a thin streak when fast, and its band pulses faster and faster
## and turns from ice to red over the last DANGER_TIME of the fuse, so you see when to dive away.
## Visual only: the spin and the pulse come from its own motion and the fuse time every copy already
## runs, nothing new goes over the wire.

const BODY_COLOR := Color(0.149, 0.451, 0.180) # #26732E, the art guide's frag olive
const BODY_GLOW := 0.35 # a little emission: the frag reads in shadow like the pawns do
const DANGER_TIME := 0.4 # s of fuse left where the band turns red
const PULSE_SLOW := 5.0 # rad/s of the band's pulse at the throw
const PULSE_FAST := 34.0 # rad/s just before the boom
const SPIN_PER_MS := 0.9 # tumble rad/s per m/s of speed
const SPIN_MAX := 16.0 # rad/s, so a fast throw still reads as a crystal and not a blur
const TRAIL_FROM := 9.0 # m/s: slower than this has no streak
const TRAIL_FULL := 20.0 # m/s: the streak's full length
const TRAIL_LEN := 0.9 # m at TRAIL_FULL
const SNAP_SPEED := 45.0 # m/s: faster than any throw, a free fall or a blast can make a frag move
const STILL_AFTER := 0.12 # s without motion before the frag counts as lying still

## Seconds of fuse left. INF (the killcam, which records no fuse) keeps the band calm and ice.
var fuse_left := INF
var spin: Node3D
var band: MeshInstance3D
var cap: MeshInstance3D
var trail: MeshInstance3D
var _band_mat: StandardMaterial3D
var _trail_mat: StandardMaterial3D
var _phase := 0.0
var _last := Vector3.INF
var _vel := Vector3.ZERO
var _since_move := 0.0


func _init() -> void:
	name = "Look"
	spin = Node3D.new()
	spin.name = "Spin"
	add_child(spin)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = CrystalMesh.part(&"grenade")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BODY_COLOR
	mat.roughness = 0.4
	mat.metallic = 0.1
	mat.emission_enabled = true
	mat.emission = BODY_COLOR
	mat.emission_energy_multiplier = BODY_GLOW
	body.material_override = mat
	spin.add_child(body)
	band = MeshInstance3D.new()
	band.name = "Band"
	band.mesh = CrystalMesh.part(&"grenade_seam")
	_band_mat = CrystalMesh.glow_material(CrystalStyle.ICE)
	band.material_override = _band_mat
	spin.add_child(band)
	cap = MeshInstance3D.new()
	cap.name = "Cap"
	cap.mesh = CrystalMesh.part(&"grenade_pin")
	cap.position.y = 0.095
	cap.material_override = CrystalMesh.shell_material()
	spin.add_child(cap)
	trail = MeshInstance3D.new()
	trail.name = "Trail"
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, 1.0)
	trail.mesh = box
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.albedo_color = Color(CrystalStyle.ICE, 0.0)
	trail.material_override = _trail_mat
	trail.visible = false
	add_child(trail)
	for m in [body, band, cap, trail]:
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_band()


## The thrower's team on the cap, so an enemy frag reads at a glance. FFA (no teams) keeps it pale.
func set_team(team: int) -> void:
	if team < 0 or Game.is_ffa():
		cap.material_override = CrystalMesh.shell_material()
	else:
		cap.material_override = CrystalMesh.glow_material(Player.team_color(team))


func _process(delta: float) -> void:
	tick(delta)


## One frame: velocity from the node's own motion (the grenade's arc, the killcam's positions), the
## tumble, the streak and the band. Public so a check can step it without a running scene.
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if not is_visible_in_tree():
		_last = Vector3.INF # the killcam hides and reuses its copies: no streak from the old spot
		return
	var pos := global_position
	# The grenade moves on physics ticks and the killcam on its snapshots, so most frames see no motion:
	# measure over the time since the node last moved, and only call it still after STILL_AFTER.
	_since_move += delta
	if _last == Vector3.INF:
		_last = pos
		_since_move = 0.0
	elif not pos.is_equal_approx(_last):
		# Faster than SNAP_SPEED is a snap (net correction, replay cut), not a throw. A speed and not a
		# distance, so a client at a low frame rate still gets its tumble and streak.
		var step := (pos - _last) / maxf(_since_move, 0.001)
		_vel = step if step.length() < SNAP_SPEED else Vector3.ZERO
		_last = pos
		_since_move = 0.0
	elif _since_move > STILL_AFTER:
		_vel = Vector3.ZERO
	var speed := _vel.length()
	if speed > 0.5:
		var axis := _vel.cross(Vector3.UP)
		if axis.length_squared() < 0.0001:
			axis = Vector3.RIGHT
		spin.rotate(axis.normalized(), -minf(speed * SPIN_PER_MS, SPIN_MAX) * delta)
	var reach := trail_length(speed)
	trail.visible = reach > 0.01
	if trail.visible:
		var dir := _vel / speed
		trail.global_basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
		trail.scale = Vector3(1.0, 1.0, reach)
		trail.global_position = pos - dir * reach * 0.5
		_trail_mat.albedo_color.a = 0.55 * reach / TRAIL_LEN
	_phase += pulse_rate(fuse_left) * delta
	_apply_band()


func _apply_band() -> void:
	var pulse := 0.5 + 0.5 * sin(_phase)
	var col := band_color(fuse_left)
	_band_mat.albedo_color = col.lightened(0.15)
	_band_mat.emission = col
	_band_mat.emission_energy_multiplier = lerpf(1.6, 4.5, pulse * maxf(danger(fuse_left), 0.35))


## 0 before the last DANGER_TIME of the fuse, 1 at the boom.
static func danger(fuse: float) -> float:
	if fuse == INF:
		return 0.0
	return clampf(1.0 - fuse / DANGER_TIME, 0.0, 1.0)


## The band's colour: ice, turning red (the HUD's own danger colour) over the last DANGER_TIME.
static func band_color(fuse: float) -> Color:
	return CrystalStyle.ICE.lerp(CrystalUi.DANGER, danger(fuse))


## How fast the band pulses: slow at the throw, frantic at the boom. Calm with no fuse (killcam).
static func pulse_rate(fuse: float) -> float:
	if fuse == INF:
		return PULSE_SLOW
	var urgency := clampf(1.0 - fuse / Grenade.FUSE, 0.0, 1.0)
	return lerpf(PULSE_SLOW, PULSE_FAST, urgency * urgency)


## Length of the streak behind a grenade at `speed` m/s.
static func trail_length(speed: float) -> float:
	return clampf((speed - TRAIL_FROM) / (TRAIL_FULL - TRAIL_FROM), 0.0, 1.0) * TRAIL_LEN
