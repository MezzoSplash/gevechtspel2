# Gevechtspel

Feel-first arena FPS built around style and movement: surf, wallrun, dive, slide, and land Tony Hawk style combos and trickshots. If a change does not make shooting, moving or pulling off tricks more satisfying, it is out of scope. When making maps, props or weapons, follow [docs/art/index.html](docs/art/index.html).

Current game: 4 modes (TDM, FFA, Style TDM, Style FFA), 5 maps (Townhouses, Foundry, Rooftops, Quay, Skyline; see `scripts/maps.gd`), 8 guns plus frag, knife and melee, bots up to 16, UAV and RC-XD scorestreaks, final best-trick killcam.

## Stack

- Godot **4.7** + **GDScript**. No C#.
- One Godot project. Dedicated server is a launch flag (`-- --server`), not a second repo.
- Run editor/binary: `~/.local/bin/godot` (Godot 4.7.2). Prefer `./run.sh`.

## Architecture

- Server is authority. Clients never decide hits, deaths, or bot actions.
- Shared weapon stats live in `data/weapons/` + `shared/weapon_def.gd`. Do not duplicate numbers in client and server scripts.
- Bots are server pawns using the same simulation as players. They are not client puppets.
- Hitscan first. No projectiles until the three guns feel good.

## Feel rules

- TTK target ~0.4–0.8s on body. Headshots matter.
- Every shot: muzzle flash, camera kick, tracer, audio. Confirmed hit: hit marker + tick. Kill: red marker + hitstop + distinct sound.
- Movement is snappy (quake-style accel/friction). Do not leave Godot's floaty default character.
- Mouse look is raw. No input smoothing.

## Scope

Polish what is there before adding more. New modes, maps or guns only when they serve the style/movement loop and come with a headless check. No shops, cosmetics, Steam or matchmaking yet.

## Code structure

- `shared/game.gd` (autoload `Game`) is being split. Pure logic moves into `RefCounted` helpers with static functions (`shared/tricks.gd`, `shared/combo_ledger.gd`, `shared/match_rules.gd`). State, signals and every `@rpc` stay in `game.gd` on the same node path, and the old function names stay as thin wrappers. Use the same pattern for `hud.gd` and `player.gd`.
- A change to anything sent over the network bumps `NET_VERSION`. A refactor must not.

## Checks

- `tools/run_checks.sh` imports the project and runs every headless `tools/check_*`; CI runs it on every push and PR. It must exit 0 before a merge. Known-failing and skipped checks are listed at the top of the script.
- Add a `tools/check_*.tscn` for new behaviour.

## Commands

```
./run.sh                  # play
./run.sh --editor         # editor
./run.sh --headless --quit-after 1
tools/run_checks.sh       # all headless checks
```
