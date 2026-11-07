# Gevechtspel

Feel-first arena FPS built around style and movement: surf, wallrun, dive, slide, and land Tony Hawk style combos and trickshots. If a change does not make shooting, moving or pulling off tricks more satisfying, it is out of scope. When making maps, props or weapons, follow [docs/art/index.html](docs/art/index.html).

Current game: 6 modes (TDM, FFA, Style TDM, Style FFA, Gun Game, CTF on Quay), 5 maps (Townhouses, Foundry, Rooftops, Quay, Skyline; see `scripts/maps.gd`), 8 guns plus frag, knife and melee, bots up to 16, UAV (a physical drone you can shoot down), RC-XD and LOS scorestreaks, MVP killcam, B1 crystal bodies.

## Stack

- Godot **4.7** + **GDScript**. No C#.
- One Godot project. Dedicated server is a launch flag (`-- --server`), not a second repo.
- Run editor/binary: `~/.local/bin/godot` (Godot 4.7.2). Prefer `./run.sh`.

## Architecture

- Server is authority. Clients never decide hits, deaths, or bot actions.
- Shared weapon stats live in `data/weapons/` + `shared/weapon_def.gd`. Do not duplicate numbers in client and server scripts.
- Bots are server pawns using the same simulation as players. They are not client puppets.
- Hitscan first. No projectiles until the three guns feel good.

## Direction

- Hectic and chaotic. Avoid anything that makes players stand still or camp.
- Movement feels very fluid and slightly floaty (light apex hang time, generous air control), but stays responsive.
- No-scoping stays viable. Do not nerf it.
- Characters are B1: abstract, non-gendered crystal bodies with floating hands and feet (`scripts/crystal_*.gd`, poses in `scripts/body_pose.gd`). Every new move needs a pose; wall run, crouch and dive must keep working.

## Feel rules

- TTK target ~0.4–0.8s on body. Headshots matter.
- The sniper (0.87s) and the slug (0.91s) are deliberately slower than that band, and the shotgun is faster (one close hit with all pellets is a kill). A sniper headshot is an instant kill: 50 damage x 2.0. Do not "fix" those three into the band.
- Every shot: muzzle flash, camera kick, tracer, audio. Confirmed hit: hit marker + tick. Kill: red marker + hitstop + distinct sound.
- Ground movement is quake-style accel/friction, not Godot's default character. Air feel is tuned in `scripts/player.gd` (`APEX_*`, `AIR_*`, `DIVE_*`).
- Mouse look is raw. No input smoothing.

## Scope

Polish what is there before adding more. New modes, maps or guns only when they serve the style/movement loop and come with a headless check. No shops, cosmetics, Steam or matchmaking yet.

## Code structure

- `shared/game.gd` (autoload `Game`) is being split. Pure logic moves into `RefCounted` helpers with static functions (`shared/tricks.gd`, `shared/combo_ledger.gd`, `shared/match_rules.gd`). State, signals and every `@rpc` stay in `game.gd` on the same node path, and the old function names stay as thin wrappers. Use the same pattern for `hud.gd` and `player.gd`.
- A change to anything sent over the network bumps `NET_VERSION`. A refactor must not.

## Checks

- `tools/run_checks.sh` imports the project and runs every headless `tools/check_*`; CI runs it on every push and PR. It must exit 0 before a merge, and only merge when the PR's own CI is green: no overrides or auto-merge on red. Known-failing and skipped checks are listed at the top of the script.
- Add a `tools/check_*.tscn` for new behaviour.

## Recent work

- v0.5.2 (released): B1 crystal bodies and poses, crouch pose, CTF HUD fix, Gun Game, CTF, balance pass, and the stance (crouch + `move_fx`) of bots synced to clients.
- #170: floaty movement. `DIVE_BOOST` 2.5 → 1.9 (half fades out), dive/slide cooldowns 0.6/0.3 s, `APEX_GRAVITY_SCALE` 0.6 below 2.2 m/s, `AIR_WISH_CAP` 1.25, `AIR_STEER_RATE` 1.4.
- #171/#172: the UAV is a drone that circles the map and can be shot down (`scripts/uav_drone.gd`). Released in v0.5.3 (`NET_VERSION` 0.5.3).
- #173: `check_bot_kit` is deterministic (seeded, streaks handed out).
- #177/#178: speed effects (`Game.speed_fx`, Access tab, default on). The hip FOV kicks with horizontal speed from sprint on (`Player.speed_fov_extra`), speed lines fade in above ~12 m/s (`SpeedLines` + `shaders/speed_lines.gdshader`), a hard landing dips the camera once, and a wind loop follows the speed. Local player only; off keeps the old sprint + carry FOV.
- LOS scorestreak (slot 2, 7 kills, 5 s): the body keeps its line, the hands fly and melee from there. One bash from the hands is a kill, and a landed bash snaps the body to the hands and ends the streak early — that snap is the payoff. A snap from `Style.LOS_LONG_M` (25 m) or more pays `LOS LONG` (350) instead of `LOS` (175), and the body lands in the nearest free spot when the capsule does not fit under the hands. The streak key again recalls the hands early without a snap. A thin gold bar under the crosshair is the window. `NET_VERSION` 0.5.8. Check: `tools/check_los.tscn`.

## Commands

```
./run.sh                  # play
./run.sh --editor         # editor
./run.sh --headless --quit-after 1
tools/run_checks.sh       # all headless checks
```
