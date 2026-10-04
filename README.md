# Gevechtspel

A small native Linux + Windows arena shooter. Feel first, art later.

**v0.2.16** — version number shown top-right in the main menu. Still compatible with 0.2.14/0.2.15 (same NET_VERSION).

## Play (Linux)

Godot 4.7.2 is expected at `~/.local/bin/godot` (portable binary, not the distro package).

```bash
./run.sh
```

- **WASD** move, **Space** jump, **mouse** look
- **Shift** sprint (less accurate), **Ctrl** or **C** crouch (hides behind cover); crouch while sprinting slides
- **LMB** fire (rifle holds; pistol, shotgun and sniper fire once per click), **R** reload, **Q** or **1/2** switch between your class's primary and secondary
- **RMB** zoom (sniper only)
- **G** grenade (as many as your class carries, max 3 per life)
- **E** melee: weapon bash, 2 m reach, 50 damage (two hits kill), once per 0.8 s
- **Up/Down** pick a streak slot, **Enter** activates it (radar after 3 kills: your whole team sees the enemies for 4 seconds, and the other team hears "Enemy radar online"; in Free For All only you see everyone else)
- **T** chat (Enter sends, Esc cancels)
- **Esc** pause menu (resume, change class, settings, leave, quit)
- **Tab** scoreboard

Boot menu: **Singleplayer** (with bots), **Multiplayer** (host or connect), **Classes**, **Settings**. In Singleplayer and under Multiplayer (for hosting) you pick the **map** and the **mode**; the menu remembers your last pick. Clients always get the server's map and mode when they join, also mid-match.

Two windows on this PC:

1. `./run.sh` → Host game
2. `./run.sh` → Connect `127.0.0.1`

Dedicated server (optional):

```bash
./run-server.sh 7777                              # Townhouses, Team Deathmatch
./run-server.sh 7777 --map foundry --mode ffa     # Foundry, Free For All
./run.sh -- --connect 127.0.0.1:7777 --name Friend
```

`--map` takes `townhouses` or `foundry` (or `1`/`2`), `--mode` takes `tdm` or `ffa`.

Bots fill empty slots to 10 players (5v5 in Team Deathmatch). Same guns as you. Use cover. Health comes back after 4.5 seconds without damage. Die and you respawn after 2 seconds. Tab shows the scoreboard. When a round ends, everyone watches the final killcam: the last kill of the round through the killer's eyes, slowed down at the kill, before the scoreboard.

## Maps

- **Townhouses**: two rows of houses with upstairs rooms, a street with a bus, backyards and side flanks.
- **Foundry**: a compact industrial yard. Roofed warehouse hall in the middle (skylight, big doors north and south, side doors east) with a 3 m mezzanine that looks out over the container yard; a container hill and stacks on the west side; an alley with offset gates, two sheds with three doors each, and a water-tank courtyard on the east side; loading docks behind both spawns. No spawn sees the other spawn, and the long alley is broken up so the sniper has lanes but no lane covers the whole map.

## Modes

- **Team Deathmatch**: 5v5, first team to 25 kills or the most kills after 10 minutes.
- **Free For All**: everyone against everyone (bots fill to 10 players). First to 20 kills, or the top player after 10 minutes. You respawn at the spawn point farthest from everyone else. All other players have enemy name tags (only visible in line of sight); the scoreboard and the line under the clock show your place.

## Settings

Main menu or **Esc → Settings**: master and SFX volume, **mouse sensitivity** (0.1–4.0, 1.0 = default) and **aim / scope** sensitivity (multiplier while aiming down sights or scoped, default 0.45). Slider or type the number. Saved in `user://settings.cfg`.

When you get hit, a red wedge around the crosshair points at where the damage came from (shooter, melee attacker or grenade blast); it turns with your view and fades after about 1.3 seconds.

## Classes

Main menu → **Classes**: create, rename, edit and delete up to 8 classes. A class is a primary (rifle, shotgun or sniper), a secondary (pistol) and up to 3 grenades. Defaults: **Rifleman** (rifle, pistol, 2 frags), **Breacher** (shotgun, pistol, 3 frags), **Sniper** (sniper, pistol, 1 frag). Saved in `user://classes.cfg` (Linux: `~/.local/share/godot/app_userdata/Gevechtspel/classes.cfg`).

When you first spawn into a match you pick a class (keys 1–8 or click); after 10 seconds your last used class is picked for you. **Esc → Change class** during a match: the new class applies at your next spawn. The server checks every loadout (known guns, at most 3 grenades) and only lets you switch to and fire the guns in your class. Bots keep their fixed guns.

## Editor

```bash
./run.sh --editor
```

Foundry is generated from `tools/gen_foundry.py` (CSG boxes, collision on the `Arena` combiner). Edit the script and run `python3 tools/gen_foundry.py` to rebuild `scenes/maps/foundry.tscn`. Spawn points per map live in `scripts/maps.gd`.

## Credits

Gun, footstep, hurt, melee, grenade and trickshot sounds are CC0 (Free Firearm Sound Library, Kenney); the radar voice lines are Piper TTS with the public-domain LJ Speech voice. See [CREDITS.md](CREDITS.md).
