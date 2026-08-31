class_name CameraFeel
extends Camera3D

const RECOVER := 15.0
const FOV_RECOVER := 18.0
const BASE_FOV := 90.0

var _kick := Vector2.ZERO
var extra_fov := 0.0


func _ready() -> void:
	fov = BASE_FOV


func add_kick(pitch_deg: float, yaw_deg: float, fov_amt: float) -> void:
	_kick.x += deg_to_rad(pitch_deg)
	_kick.y += deg_to_rad(yaw_deg)
	fov = minf(fov + fov_amt, BASE_FOV + 8.0)


func _process(delta: float) -> void:
	var k := 1.0 - exp(-RECOVER * delta)
	_kick = _kick.lerp(Vector2.ZERO, k)
	rotation.x = -_kick.x
	rotation.y = _kick.y
	fov = lerpf(fov, BASE_FOV + extra_fov, 1.0 - exp(-FOV_RECOVER * delta))
