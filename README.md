# Gevechtspel 
<img width="1080" height="1080" alt="image" src="https://github.com/user-attachments/assets/4e8daae6-9dc6-4691-8135-47efd86c3735" />


A small native Linux + Windows arena shooter. Feel first, art later.

**v0.3.2** — Surfing a ramp keeps your speed for 4 seconds. A yellow strip at the end of the surfs on Quay, Foundry and Rooftops scores LINE (+100) if you cross it fast, and LINE ×2 (+200) for a second strip in that window. Your team, including you, hears "Friendly radar online"; the other team hears "Enemy radar online". Same NET_VERSION 0.3.0 as v0.3.0 and v0.3.1, so those builds can still join. Not compatible with 0.2.22 or older.

**v0.3.1** — Revolver cylinder and grip sit on the gun. The streak counter stays `STREAK n/5` during radar and while driving the RC-XD. An unused killstreak clears when the next round starts. Every map has 12 team spawns, so a full bot match does not stack on one point. Discord shows that you are playing while the window is open. Same NET_VERSION 0.3.0 as v0.3.0, so 0.3.0 and 0.3.1 can still join each other. Not compatible with 0.2.22 or older.

**v0.3.0** — New map Quay: a dry dock with downhill surfs, a curved corner into the dock, and a steel walk from the quay up to the roof so you can take that corner again. **Not compatible with 0.2.22 or older** (NET_VERSION 0.3.0): everyone must update, including the dedicated server. Release builds are Windows x86_64 and Linux x86_64 only.

**v0.2.22** — Solo and host pick the kill limit, round length and bot count next to map and mode. Esc → Settings no longer crashes mid-match. SMG damage is 10 and falls off from 12 m; the rifle is 34 damage at 390 rpm with a headshot kill out to about 27 m; the revolver needs two headshots; the shotgun is 32 × 12 pellets; the sniper draws no crosshair until you zoom. **Not compatible with 0.2.21 or older** (NET_VERSION 0.2.22): everyone must update, including the dedicated server.

**v0.2.21** — Earned killstreaks stay until you use them. Radar unlocks at 3 kills in one life; RC-XD at 5 (drive the car from its own camera and detonate it). Bots commit to one strafe and flank instead of shimmying; SMG bots burst shorter. Settings save the window, resolution, VSync, FPS cap, FOV, render scale, antialiasing, invert Y and an FPS counter.

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
- **Up/Down** pick a streak slot, **Enter** uses it. A streak you earned stays until you use it, the next round starts, or you leave to the menu. Dying resets only the counter toward the next one. Radar is the first slot, after 3 kills in one life: your whole team sees the enemies for 4 seconds, and the other team hears "Enemy radar online"; in Free For All only you see everyone else. RC-XD is the second slot, after 5 kills in one life: you drive a small explosive car from its camera (WASD and mouse; **LMB** detonates). Your body stays where you left it.
- **T** chat (Enter sends, Esc cancels)
- **Esc** pause menu (resume, change class, settings, leave, quit)
- **Tab** scoreboard

Boot menu: **Singleplayer** (with bots), **Multiplayer** (host or connect), **Classes**, **Settings**. In Singleplayer and under Multiplayer (for hosting) you pick the **map**, **mode**, **kills**, **time** and **bots**; the menu remembers your last pick. Clients always get the server's map, mode, kill limit and round length when they join, also mid-match.

Two windows on this PC:

1. `./run.sh` → Host game
2. `./run.sh` → Connect `127.0.0.1`

Dedicated server (optional):

```bash
./run-server.sh 7777                              # Townhouses, Team Deathmatch
./run-server.sh 7777 --map foundry --mode ffa     # Foundry, Free For All
./run-server.sh 7777 --map rooftops --mode tdm --kills 15 --time 8 --bots 6
./run.sh -- --connect 127.0.0.1:7777 --name Friend
```

`--map` takes `townhouses`, `foundry`, `rooftops` or `quay` (or `1`/`2`/`3`/`4`), `--mode` takes `tdm` or `ffa`, `--kills` 5–50, `--time` minutes 1–20, `--bots` 0–16.

Bots: you pick how many (default 9, so one human is a 10-player match; 5v5 in Team Deathmatch when teams stay even). Same guns as you. Use cover. Health comes back after 4.5 seconds without damage. Die and you respawn after 2 seconds. Tab shows the scoreboard. When a round ends, everyone watches the final killcam: the last kill of the round through the killer's eyes, slowed down at the kill, before the scoreboard.

## Maps

- **Townhouses**: two rows of houses with upstairs rooms, a street with a bus, backyards and side flanks.
- **Foundry**: a compact industrial yard. Roofed warehouse hall in the middle (skylight, big doors north and south, side doors east) with a 3 m mezzanine that looks out over the container yard. Walk ramps just west of the big doors reach the 7.3 m roof; a bridge crosses the skylight to the east half. Surf ramps run along the hall's west wall, one each side of the container. Container hill and stacks on the west side; an alley with offset gates, two sheds with three doors each, and a water-tank courtyard on the east side; loading docks behind both spawns. No spawn sees the other spawn, and the long alley is broken up so the sniper has lanes but no lane covers the whole map.
- **Rooftops**: two blocks around a court, roofs at 6 m. Surf ramps run the long flanks onto a 4 m deck, then a walk-ramp up to the roof. A short surf triangle crosses the court. Walk off a parapet gap for the drop; stairs inside each block are the way up without surfing, and they stay clear of the side doors. The ground floor is one room with doors on four sides. The flank lanes are long, with crates beside them. Spawn yards sit behind a wall and two baffles.
- **Quay**: a dry dock, about 90 × 120 m. The dock floor is at 0 m, the side quays at 4 m, and the loods roofs at 10 m. A surf along each outer wall runs from a roof down to a quay, through the middle of the map. A shorter surf on each quay wall drops into the dock, and a flat surf crosses the dock. On the east roof a balcony feeds a quarter-circle surf (14 m radius, short straight segments, with a straight run-in and run-out) that turns west into the dock, toward the middle of the map. The orange corner turns east into the dock. A steel walk at the north-east corner of each loods climbs from the quay to the roof, about 24°, so you can reach that corner again. Stairs inside each loods and a narrow street ramp up to the roof are the other ways up, with the foot on open floor. Bots take those, not the surf.

## Modes

- **Team Deathmatch**: first team to the kill limit (default 25) or the most kills when the clock hits (default 10 minutes). Default fill is 9 bots + you.
- **Free For All**: everyone against everyone. First to the kill limit (default 20) or the top player when the clock hits. You respawn at the spawn point farthest from everyone else. All other players have enemy name tags (only visible in line of sight); the scoreboard and the line under the clock show your place.

## Settings

Main menu or **Esc → Settings**. Saved in `user://settings.cfg` (Linux: `~/.local/share/godot/app_userdata/Gevechtspel/settings.cfg`) and applied again on the next launch.

- **Name**: the name you play under. The Singleplayer and Multiplayer name boxes use the same one, and editing any of them saves it. `--name` on the command line overrides it for that launch only.
- **Video**: windowed, borderless or fullscreen; resolution (windowed and fullscreen); VSync; max FPS (0 on the slider is unlimited; VSync still follows the monitor); field of view (70–110, default 90; scopes keep their own zoom); render scale (50–100%, the 3D image only); antialiasing off / 2× / 4× / 8× (default 4×). On Wayland, fullscreen may behave as borderless.
- **Mouse**: sensitivity (0.1–4.0, 1.0 = default), aim / scope multiplier (default 0.45), invert Y. Slider or type the number.
- **Audio**: master and SFX volume.
- **FPS counter**: the number at the top left of the HUD. On by default.

A dedicated server ignores the video settings and stays at 60 fps.

When you get hit, a red wedge around the crosshair points at where the damage came from (shooter, melee attacker or grenade blast); it turns with your view and fades after about 1.3 seconds.

## Weapons

| Gun | Damage | Rate | Mag | Reload | Notes |
| --- | --- | --- | --- | --- | --- |
| Rifle | 34, head ×3.6 (falls to 50% from 16 to 48 m) | 390 rpm, auto | 30 | 1.55 s | one headshot out to about 27 m |
| SMG | 10 (falls to 40% from 12 to 26 m) | 1200 rpm, auto | 35 | 1.7 s | moves 8% faster, half the running spread penalty, iron sights on RMB |
| Shotgun | 32 × 12 pellets (falls off from 7 m) | 93 rpm | 6 | 2.1 s | close range |
| Sniper | 50, head ×2 | 69 rpm | 10 | 1.75 s | scope on RMB |
| Pistol | 34 | 360 rpm | 18 | 1.15 s | secondary |
| Revolver | 55, head ×1.6 (2 body or 2 head) | 132 rpm | 6 | 2.8 s | secondary, heavy kick |
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

Foundry is generated from `tools/gen_foundry.py`, Rooftops from `tools/gen_rooftops.py`, Quay from `tools/gen_quay.py` (CSG boxes, collision on the `Arena` combiner). Edit the script and run it to rebuild the `.tscn`. Spawn points per map live in `scripts/maps.gd`.

## Credits

Gun, footstep, hurt, melee, grenade, knife and trickshot sounds are CC0 (Free Firearm Sound Library, Kenney); the radar voice lines are Piper TTS with the public-domain LJ Speech voice. See [CREDITS.md](CREDITS.md).
