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

- #25: the knife throw is visible to every client. `Player.play_throw_anim()` (0.42 s wind-up + snap) rides `pose_body()` → `CrystalBody.throw_amt` → `BodyPose` (14° over the front foot, 16° with the throwing shoulder), and the trigger needs no protocol change: `sync_knife_count()` already reaches every client with the thrower's peer id, and a count that drops is a throw (a refill stays silent). `check_knife_throw_anim` covers it.
- Remote pawns get the landing roll from the synced `move_fx` (#236): they never run `Movement.tick_dive_roll`, so the frame `apply_network_pose()` sees `MOVE_ROLL` it starts the local roll timer that drives the body flip. The killcam interpolates the flip with `lerp_angle` (a plain lerp from near -TAU back to 0 spun the body the long way) and records the throw pose as snapshot field 8.

- #207: hit confirm carries weight and climbs with the combo. Two extra layers on the weapon (`ThudSfx`, `TickSfx`) reuse the existing body/head samples pitched down/up - no new assets until #135 settles licensing. Body = low thump with a random pitch offset; headshot = head sample pushed to 1.35 plus a transient above it; kill = sting on top. The pitch ladder is `ComboMeter`'s own (`PITCH_STEP` per `MULT_STEP`, capped at `PITCH_MAX`), so the bar and the sound climb together. `check_hit_sfx` covers the ladder, body-vs-headshot, the random offset and the buses.

- #205: a landing roll is visible to everyone now, not only to the player doing it. The body has a `flip` channel (`Player.roll_flip()` → `pose_body(..., flip)` → `CrystalBody.flip` → `BodyPose` rig), so the figure tumbles forward like the local camera already did, and the killcam records it as snapshot field 7 and interpolates it. `check_killcam_roll` drives a real pawn through a roll and asserts the flip turns, that pose_body forwards it, that the rig tilts 90° on a quarter turn, and that the snapshot carries it.

- A `.tscn` has **no comment syntax**: two `#` lines above a node in Townhouses made the scene parser drop the node that followed them, so the west alley had one wall in the game and two in the file. The map check now raycasts each alley face at chest height and asserts the hit normal is flatter than `Player.WALLRUN_MAX_NY` (the same rule `Movement.find_wall` uses) — a visual-only or missing wall passes every navmesh assertion.

- #212: Skyline spawn sightlines. The outer spawn columns (x = ±13) saw their half-turn counterpart straight across the map because the front baffles stopped at |x| 10; they now reach 13.6, and the tower-roof sign went 1.6 → 2.2 m wide because the inner columns (±3.4) passed it by 10 cm. `check_skyline` asserts all 144 spawn pairs are blocked at eye height (1.6 m above the roof).

- v0.5.12 (released): perf overlay modes + a renderer setting (Settings > HUD / Graphics; the renderer choice relaunches once with `--rendering-method`), and a movement pass on the other three maps — Rooftops skybridges, Foundry roof wallrun walls, Townhouses plaza alleys. `NET_VERSION` 0.5.12 (their collision changed).

- Townhouses movement pass: two 14 m wallrun alleys in the mid plaza (faces 3.4 m tall, 7.4 m apart, one each side of the street) — the plaza was 52 m of open floor with the bus as the only cover. The scene is hand-written, so the nodes are plain `CSGBox3D` children of `Arena` with `Mat_wall` + a `Mat_trim` cap. `tools/check_townhouses` bakes the navmesh and asserts both alleys are lane-clear end to end (a path that squeezes around the walls fails) and that plaza, street, backyards and both spawns stay connected.

- Foundry movement pass: two 18 m, 3.2 m tall wallrun walls along the skylight edges of the hall roof, split at the bridge (z ±1.9..9.0) so the roof crossing stays open, with a hazard cap. The outer roof edge is left open on purpose: dropping off it is the fast way down. `tools/check_foundry` bakes the navmesh and asserts the west roof reaches the east roof over the skylight bridge, that the mezzanine/container hill/courtyard/roofs are reachable, and that the spawn-to-spawn route stays on the floor. `tools/probe_clear` prints a free-space grid (with `--y0/--y1` for a height band) — that is how a wallrun pair gets placed on floor that is actually clear instead of guessed.

- Rooftops movement pass: two 4 m skybridges at 6 m across the court, flush with both block roofs, and the court parapet gets a matching gap at each bridge mouth (without it the 1.15 m parapet sat across the landing). Additive only — the surf/deck geometry is untouched. `tools/check_rooftops` bakes the navmesh and asserts the roof route crosses a bridge at 6 m, that the ground route stays on the floor, and that the deck/bridge/spawn targets are all reachable. `tools/shot_map` renders a map from `-- --map <id>`.

- v0.5.2 (released): B1 crystal bodies and poses, crouch pose, CTF HUD fix, Gun Game, CTF, balance pass, and the stance (crouch + `move_fx`) of bots synced to clients.
- #170: floaty movement. `DIVE_BOOST` 2.5 → 1.9 (half fades out), dive/slide cooldowns 0.6/0.3 s, `APEX_GRAVITY_SCALE` 0.6 below 2.2 m/s, `AIR_WISH_CAP` 1.25, `AIR_STEER_RATE` 1.4.
- #171/#172: the UAV is a drone that circles the map and can be shot down (`scripts/uav_drone.gd`). Released in v0.5.3 (`NET_VERSION` 0.5.3).
- #173: `check_bot_kit` is deterministic (seeded, streaks handed out).
- #177/#178: speed effects (`Game.speed_fx`, Access tab, default on). The hip FOV kicks with horizontal speed from sprint on (`Player.speed_fov_extra`), speed lines fade in above ~12 m/s (`SpeedLines` + `shaders/speed_lines.gdshader`), a hard landing dips the camera once, and a wind loop follows the speed. Local player only; off keeps the old sprint + carry FOV.
- LOS scorestreak (slot 2, 7 kills, 5 s): the body keeps its line, the hands fly and melee from there. One bash from the hands is a kill, and a landed bash snaps the body to the hands and ends the streak early — that snap is the payoff. A snap from `Style.LOS_LONG_M` (25 m) or more pays `LOS LONG` (350) instead of `LOS` (175), and the body lands in the nearest free spot when the capsule does not fit under the hands. The streak key again recalls the hands early without a snap. A thin gold bar under the crosshair is the window. `NET_VERSION` 0.5.8. Check: `tools/check_los.tscn`.
- #200: HUD layout pass. The top-centre column is clock (10–60) → standing/CTF line (64) → streak popup (92); the left column is minimap (40–240) → compact 36 px scorestreak rows (252–408) → chat log, with the presence feed above the chat instead of behind the popup. The round notice and RELOAD are rows of the bottom stack now, so they cannot land on the HP bar. Check: `tools/check_hud_layout.tscn` (no overlap at 1920×1080, 1600×1000, 1280×720).
- #201: map and mode are chip grids (`scripts/ui/choice_row.gd`, `ChoiceRow`) instead of dropdowns: every option on screen, the current one amber, a tooltip per chip, CTF greyed out with the reason. Chips are `ChoiceChip` styleboxes in `tools/build_ui_theme.gd` (regenerate `ui/menu_theme.tres` after editing it); the same rebuild restyles OptionButton and PopupMenu, so Settings and the server list follow. Check: `tools/check_menu_choices.tscn`.
- #202: team modes pick bots per side — `Game.bot_allies`/`bot_enemies`/`bot_team_base` with `bot_split_active()` and `bot_target(team)`, menu rows "Bots with you" / "Bots against you", persisted as `match/bots_allies` / `match/bots_enemies`. `bot_count` stays the single total for FFA (and the menu's hidden Bots row splits it evenly). `_trim_bots` leaves a split match alone, so a friend joining keeps "two of us against ten bots" — but only for a local or listen-host match: a dedicated server has no owner, so `bot_split_active()` refuses the split there and it keeps the balanced fill (otherwise every bot would stay when humans join). `--bots-allies`/`--bots-enemies` are stored for the menu and a listen host. Check: `tools/check_tdm_team_setup.tscn`.
- Skyline room pass (`tools/gen_skyline.py`, regenerate the scene after editing): footprints 40–90% larger at the same heights (Spawn 34×14, Mid 26×26, WA 13×18, EA 14×16), a 13 m wallrun alley with 3.6 m faces on the EA roof, and a 10 m × 20 m surf ridge that lands on the SurfDeck. Two traps: a roof parapet that runs past a ramp landing walls the navmesh route off, and a ramp whose upper end sits inside a building body is dropped by the bake — keep both clear of each other. Checks: `check_skyline`, `check_skyline_walk`, `check_skyline_bots`.
- Skyline review pass: `TowerTank` moved to the east margin (it sat on the spine and against the wallrun face), the sign back on the centre line so the spawn-to-spawn sight break is real (the wall is deliberately off-centre — a wall there would cut the spine in half), and `SpineCatchRamp` at 37° like every other walkable ramp.

- v0.5.11 (released): HUD layout pass, map/mode chips + rebuilt dropdown theme, bots per team (listen host), Skyline rebuilt (bigger roofs, spine, wallrun alley, wider surf street, catch ledges). `NET_VERSION` 0.5.11 — Skyline's collision changed, so 0.5.10 peers are refused.

## Commands

```
./run.sh                  # play
./run.sh --editor         # editor
./run.sh --headless --quit-after 1
tools/run_checks.sh       # all headless checks
```
