class_name CameraFeel
extends Camera3D
## Recoil kick + FOV punch. Recovers exponentially. No look smoothing.

const RECOVER := 15.0
const FOV_RECOVER := 18.0
const BASE_FOV := 90.0 # fallback and the shipped default; the live hip FOV is Game.fov

var _kick := Vector2.ZERO
var extra_fov := 0.0
var move_pitch := 0.0 # rad, set by the player: dive roll flip (#81)
var move_roll := 0.0 # rad, set by the player: wallrun tilt (#80)
var ads_fov := 0.0 # 0 = hip fire; sniper sets ~38


func _ready() -> void:
	fov = hip_fov()


## Hip FOV from settings. ADS writes an absolute fov and must not scale with this.
func hip_fov() -> float:
	return Game.fov


func add_kick(pitch_deg: float, yaw_deg: float, fov_amt: float) -> void:
	_kick.x += deg_to_rad(pitch_deg)
	_kick.y += deg_to_rad(yaw_deg)
	fov = minf(fov + fov_amt * Game.shake_scale(), _base_fov() + 8.0)


## Hits, knockback, melee: pure feel, so Settings → Reduce camera shake scales all of it.
func add_shake(pitch_deg: float, yaw_deg: float, fov_amt: float) -> void:
	var k := Game.shake_scale()
	add_kick(pitch_deg * k, yaw_deg * k, fov_amt)


func _process(delta: float) -> void:
	var k := 1.0 - exp(-RECOVER * delta)
	_kick = _kick.lerp(Vector2.ZERO, k)
	rotation.x = -_kick.x + move_pitch
	rotation.y = _kick.y
	rotation.z = move_roll
	fov = lerpf(fov, _base_fov() + extra_fov, 1.0 - exp(-FOV_RECOVER * delta))


## Hip = Game.fov (default 90). Sniper zoom writes ads_fov (~38) while RMB is held.
func _base_fov() -> float:
	return ads_fov if ads_fov > 1.0 else hip_fov()
