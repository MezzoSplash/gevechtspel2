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
## Reload animation (#252): which of the four styles this gun plays — `mag` (rifle, smg, pistol, lmg),
## `shells` (shotgun, slug), `cylinder` (revolver) or `bolt` (sniper). See `scripts/reload_anims.gd`.
## Visual only: the reload still finishes on `reload_time`.
@export var reload_style: StringName = &"mag"
## The `mag` style with a hinged feed cover instead of an open well: the LMG's cover lifts at the start
## of the reload and closes again before the mag is seated (#252).
@export var reload_cover: bool = false
@export var tracer_width: float = 0.022
@export var fire_sound: AudioStream
@export var pellet_count: int = 1
@export var automatic: bool = true
## Damage falloff (#147), applied by the server per hit (Combat): full damage up to falloff_start_m,
## then linear down to damage × falloff_min_mult at falloff_end_m and beyond. Tune per gun in its .tres.
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
## Seconds to bring iron sights up (0.09 = SMG snap; the LMG is heavy).
@export var ads_time: float = 0.09

## --- Feel numbers that used to live in the gun-id match chains (weapon.gd, bot_brain.gd) ---
## One source per gun: set them in the .tres. A new gun must not need a new branch in a script.

## Viewmodel kick back per shot, in metres.
@export var view_kick_z: float = 0.055
## Muzzle flash visibility time, in seconds.
@export var flash_time: float = 0.045
## Muzzle light energy while the flash is up.
@export var flash_energy: float = 4.5
## HUD crosshair punch per shot (the sprinting case is gun-independent and lives in Weapon).
@export var crosshair_punch: float = 1.0
## Tracer body colour and its glow.
@export var tracer_color: Color = Color(1.0, 0.82, 0.28)
@export var tracer_glow: Color = Color(1.0, 0.7, 0.15)

## Bots: extra spread on top of the movement spread, so a bot is not a laser.
@export var bot_spread_mult: float = 2.4
## Bots: the distance they try to hold while fighting (gun choice changes the fight distance).
@export var bot_fight_range: float = 13.0
## Bots: shots per burst (min/max, inclusive) and the pause after a burst, in seconds.
@export var bot_burst_min: int = 2
@export var bot_burst_max: int = 5
@export var bot_burst_pause_min: float = 0.35
@export var bot_burst_pause_max: float = 0.85
## Bots: aim feel per gun. The SMG fights inside 12 m at 20 shots/s, where the metre wobble still
## covers the body: a wider hand (higher scale) and a slower track (lower scale) keep a strafe alive.
## The player's own SMG is unchanged.
@export var bot_aim_wobble_scale: float = 1.0
@export var bot_aim_track_scale: float = 1.0


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
