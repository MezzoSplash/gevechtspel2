class_name WeaponDef
extends Resource
## Shared gun numbers. Live in data/weapons/*.tres — do not copy into client/server scripts.

@export var id: StringName = &"rifle"
@export var display_name: String = "Rifle"
@export var fire_rate: float = 10.0
@export var damage: float = 24.0
@export var headshot_multiplier: float = 1.6
@export var spread_deg: float = 0.35
@export var kick_pitch_deg: float = 0.62
@export var kick_yaw_deg: float = 0.22
@export var kick_fov: float = 1.35
@export var range_m: float = 180.0
@export var mag_size: int = 30
@export var reload_time: float = 1.55
@export var tracer_width: float = 0.022
@export var fire_sound: AudioStream
@export var pellet_count: int = 1
@export var automatic: bool = true
@export var falloff_start_m: float = 0.0
@export var falloff_end_m: float = 0.0
@export var falloff_min_mult: float = 1.0


## Linear falloff after start_m. If end <= start, damage is constant (no dropoff).
func damage_at_distance(dist: float) -> float:
	if falloff_end_m <= falloff_start_m:
		return damage
	var t := clampf((dist - falloff_start_m) / (falloff_end_m - falloff_start_m), 0.0, 1.0)
	return damage * lerpf(1.0, falloff_min_mult, t)
