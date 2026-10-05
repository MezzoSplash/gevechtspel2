# Gevechtspel

A small native Linux + Windows arena shooter. Feel first, art later.

**v0.2.20** — Foundry: walk ramps west of the big doors up to the 7.3 m hall roof, a bridge across the skylight, and surf ramps along the west wall. Bots take the ramp when someone is on the roof. **Not compatible with 0.2.19 or older** (NET_VERSION 0.2.20): everyone must update, including the dedicated server.

## Play (Linux)

Godot 4.7.2 is expected at `~/.local/bin/godot` (portable binary, not the distro package).

```bash
./run.sh
```

- **WASD** move, **Space** jump, **mouse** look
- **Shift** sprint (less accurate), **Ctrl** or **C** crouch (hides behind cover); crouch while sprinting slides
- **LMB** fire (rifle and SMG hold; pistol, revolver, shotgun and sniper fire once per click), **R** reload, **Q** or **1/2** switch between your class's primary and secondary
- **RMB** sniper scope, or SMG iron sights (small zoom, tighter spread)
- **G** frag grenade, **F** throwing knife (whatever your class's grenade slot holds, 3 per life)
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
./run-server.sh 7777 --map rooftops --mode tdm   # Rooftops, Team Deathmatch
./run.sh -- --connect 127.0.0.1:7777 --name Friend
```

`--map` takes `townhouses`, `foundry` or `rooftops` (or `1`/`2`/`3`), `--mode` takes `tdm` or `ffa`.

Bots fill empty slots to 10 players (5v5 in Team Deathmatch). Same guns as you. Use cover. Health comes back after 4.5 seconds without damage. Die and you respawn after 2 seconds. Tab shows the scoreboard. When a round ends, everyone watches the final killcam: the last kill of the round through the killer's eyes, slowed down at the kill, before the scoreboard.

## Maps

- **Townhouses**: two rows of houses with upstairs rooms, a street with a bus, backyards and side flanks.
- **Foundry**: a compact industrial yard. Roofed warehouse hall in the middle (skylight, big doors north and south, side doors east) with a 3 m mezzanine that looks out over the container yard. Walk ramps just west of the big doors reach the 7.3 m roof; a bridge crosses the skylight to the east half. Surf ramps run along the hall's west wall, one each side of the container. Container hill and stacks on the west side; an alley with offset gates, two sheds with three doors each, and a water-tank courtyard on the east side; loading docks behind both spawns. No spawn sees the other spawn, and the long alley is broken up so the sniper has lanes but no lane covers the whole map.
- **Rooftops**: two blocks around a court, roofs at 6 m. Surf ramps run the long flanks onto a 4 m deck, then a walk-ramp up to the roof. A short surf triangle crosses the court. Walk off a parapet gap for the drop; stairs inside each block are the way up without surfing, and they stay clear of the side doors. The ground floor is one room with doors on four sides. The flank lanes are long, with crates beside them. Spawn yards sit behind a wall and two baffles.

## Modes

- **Team Deathmatch**: 5v5, first team to 25 kills or the most kills after 10 minutes.
- **Free For All**: everyone against everyone (bots fill to 10 players). First to 20 kills, or the top player after 10 minutes. You respawn at the spawn point farthest from everyone else. All other players have enemy name tags (only visible in line of sight); the scoreboard and the line under the clock show your place.

## Settings

Main menu or **Esc → Settings**: master and SFX volume, **mouse sensitivity** (0.1–4.0, 1.0 = default) and **aim / scope** sensitivity (multiplier while aiming down sights or scoped, default 0.45). Slider or type the number. Saved in `user://settings.cfg`.

When you get hit, a red wedge around the crosshair points at where the damage came from (shooter, melee attacker or grenade blast); it turns with your view and fades after about 1.3 seconds.

## Weapons

| Gun | Damage | Rate | Mag | Reload | Notes |
| --- | --- | --- | --- | --- | --- |
| Rifle | 24 (falls to 55% from 16 to 42 m) | 600 rpm, auto | 30 | 1.55 s | all-rounder |
| SMG | 12 (falls to 40% from 15 to 30 m) | 1200 rpm, auto | 35 | 1.7 s | moves 8% faster, half the running spread penalty, iron sights on RMB |
| Shotgun | 24 × 8 pellets (falls off from 7 m) | 93 rpm | 6 | 2.1 s | close range |
| Sniper | 50, head ×2 | 69 rpm | 10 | 1.75 s | scope on RMB |
| Pistol | 34 | 360 rpm | 18 | 1.15 s | secondary |
| Revolver | 55, head ×2 (2 body or 1 head) | 132 rpm | 6 | 2.8 s | secondary, heavy kick |
| Throwing knife | one hit kills | — | grenade slot | — | F; a fast, slightly dropping throw; sticks in walls |

## Classes

Main menu → **Classes**: create, rename, edit and delete up to 8 classes. A class is a primary (rifle, SMG, shotgun or sniper), a secondary (pistol or revolver) and a **grenade slot** of 3 throwables in any mix of frag grenades (G) and throwing knives (F): pick a preset (3 frags, 2 + 1, 1 + 2, 3 knives) or set the two counts. Defaults: **Rifleman** (rifle, pistol, 2 frags), **Breacher** (shotgun, pistol, 3 frags), **Sniper** (sniper, pistol, 1 frag), **Runner** (SMG, revolver, 1 frag + 2 knives). Saved in `user://classes.cfg` (Linux: `~/.local/share/godot/app_userdata/Gevechtspel/classes.cfg`).

When you first spawn into a match you pick a class (keys 1–8 or click); after 10 seconds your last used class is picked for you. **Esc → Change class** during a match: the new class applies at your next spawn. The server checks every loadout (known guns, at most 3 throwables) and only lets you switch to and fire the guns in your class. Bots keep their fixed guns (all six, the SMG and revolver included).

## Trickshots

Style points only, never extra damage. Besides NOSCOPE, 360 NOSCOPE, AIRSHOT, LONGSHOT, POINT BLANK, DOUBLE, SPRAY TRANSFER, HEADSHOT STREAK, SURF KILL and DROP KILL:

- **RUN & GUN** (125): SMG kill while sprinting or air-strafing, above 9 m/s for half a second without stopping
- **HOSE** (150): a second (or later) SMG kill from the same magazine, no reload in between
- **QUICKDRAW** (150): revolver kill within 0.4 s of switching to it
- **SIX SHOOTER** (200): a third revolver kill from one cylinder
- **YEET** (250): throwing-knife kill; **YEET ×2** (500) when you threw it in the air or while surfing

## Editor

```bash
./run.sh --editor
```

Foundry is generated from `tools/gen_foundry.py`, Rooftops from `tools/gen_rooftops.py` (CSG boxes, collision on the `Arena` combiner). Edit the script and run it to rebuild the `.tscn`. Spawn points per map live in `scripts/maps.gd`.

## Credits

Gun, footstep, hurt, melee, grenade, knife and trickshot sounds are CC0 (Free Firearm Sound Library, Kenney); the radar voice lines are Piper TTS with the public-domain LJ Speech voice. See [CREDITS.md](CREDITS.md).
