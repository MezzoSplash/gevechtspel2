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
## Movement: walk/sprint/crouch speed multiplier while this gun is held (SMG > 1).
@export var move_speed_mult: float = 1.0
## How much of the walk/sprint/slide spread penalty applies (1 = all of it; the SMG is built to run and gun).
@export var move_spread_scale: float = 1.0
## Aim down sights on RMB: FOV while aiming (0 = this gun has no ADS) and the spread multiplier while aiming.
@export var ads_fov: float = 0.0
@export var ads_spread_mult: float = 1.0
## Sniper scope: the viewmodel hides while aiming (iron sights keep it).
@export var ads_hides_model: bool = false


## Linear falloff after start_m. If end <= start, damage is constant (no dropoff).
func damage_at_distance(dist: float) -> float:
	if falloff_end_m <= falloff_start_m:
		return damage
	var t := clampf((dist - falloff_start_m) / (falloff_end_m - falloff_start_m), 0.0, 1.0)
	return damage * lerpf(1.0, falloff_min_mult, t)


## Spread multiplier from the player's movement penalty (1 = still) and ADS, for this gun.
func spread_mult_for(move_mult: float, ads: bool) -> float:
	var m := 1.0 + (move_mult - 1.0) * move_spread_scale
	if ads and ads_fov > 0.0:
		m *= ads_spread_mult
	return m


## Body shots to kill a full-health (100 HP) player at `dist` metres.
func shots_to_kill(dist: float, hp: float = 100.0) -> int:
	return ceili(hp / maxf(damage_at_distance(dist) * pellet_count, 0.001))
