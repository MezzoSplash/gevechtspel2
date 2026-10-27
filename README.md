<div align="center">

# Gevechtspel

**A fast little arena shooter for Linux and Windows. Surf, strafe, and outplay your friends.**

<img width="1080" height="1080" alt="image" src="https://github.com/user-attachments/assets/4e8daae6-9dc6-4691-8135-47efd86c3735" />

[Download](https://github.com/MezzoSplash/gevechtspel2/releases) · [Changelog](CHANGELOG.md) · [Maps](docs/MAPS.md) · [Credits](CREDITS.md)

</div>

Gevechtspel is a multiplayer first-person shooter built in Godot 4. Matches are quick, movement matters, and stylish kills earn bonus points. Play alone against bots, host a match for friends on your network, or run a dedicated server.

## Features

- **5 maps:** Townhouses, Foundry, Rooftops, Quay and Skyline ([map guide](docs/MAPS.md))
- **2 modes:** Team Deathmatch and Free For All, with your own kill limit and round length
- **8 guns:** Rifle, SMG, Shotgun, Sniper, LMG and Slug Shotgun as primaries, and Pistol or Revolver as secondaries. You also get frag grenades, throwing knives and a melee bash.
- **Custom classes:** up to 8 loadouts, each with a primary, a secondary and 3 throwables
- **Scorestreaks:** a UAV after 3 kills in one life (enemies show on the minimap) and an RC-XD after 5 (a drivable explosive car)
- **Style tricks:** bonus points for NOSCOPE, 360 NOSCOPE, AIRSHOT, LONGSHOT, SURF KILL, RUN & GUN, SIX SHOOTER, MOW DOWN, SLUG SNIPE, YEET and more
- **Surfing and air strafing:** ride the ramps, keep your speed, and cross a LINE strip for extra points
- **Bots:** up to 16. They switch guns every life, throw grenades and use scorestreaks.
- **Online play:** host from the menu or run a headless dedicated server. There is a server list with status, ping and player count, and **Find LAN** finds servers on your home network.
- **Final killcam:** everyone watches the last kill of the round
- **Settings:** video, mouse, key rebinding, crosshair, accessibility options, and separate Master, SFX, Music, UI and Enemies volume (enemy gunshots and footsteps get their own slider, louder by default)
- **Music:** a calm menu loop, a build-up when the round starts, and tense music in the final 30 seconds or when someone is close to winning

## Play

1. Download the latest Windows or Linux build from [Releases](https://github.com/MezzoSplash/gevechtspel2/releases).
2. Start the game and pick **Singleplayer** to play against bots, or **Multiplayer** to host or join.
3. Everyone in a match needs the same version, including the server. If the versions don't match, the server turns you away with a message.

### Controls

All keys can be changed in **Settings**.

| Action | Key |
| --- | --- |
| Move / jump | **WASD** / **Space** |
| Sprint / crouch (crouch while sprinting to slide) | **Shift** / **Ctrl** or **C** |
| Dive (jump out of a slide, or crouch in the air while sprinting); you roll on landing | **Shift** + **Ctrl**, then **Space** |
| Wallrun: hold sprint + forward in the air along a wall; jump to wall jump | **Shift** + **W** |
| Fire / aim or scope | **Left mouse** / **Right mouse** |
| Reload | **R** |
| Switch weapon | **Q**, or **1**–**4** |
| Frag grenade / throwing knife | **G** / **F** |
| Melee | **E** |
| Pick a scorestreak / use it | **Up**/**Down** / **Enter** |
| Chat | **T** |
| Scoreboard | **Tab** |
| Pause menu | **Esc** |

## Host a dedicated server

The server runs headless with `run-server.sh` (the first argument is the port):

```bash
./run-server.sh 7777                                    # Townhouses, Team Deathmatch
./run-server.sh 7777 --map skyline --mode ffa --bots 12
./run-server.sh 7777 --map quay --mode tdm --kills 30 --time 10 --bots 9
```

| Option | Values |
| --- | --- |
| `--port` | game port, default `7777` |
| `--map` | `townhouses`, `foundry`, `rooftops`, `quay`, `skyline` |
| `--mode` | `tdm`, `ffa`, `style-tdm` or `style-ffa` (most style points wins) |
| `--kills` | 5–50 (style modes: style per minute in hundreds; 25 × 10 min = 25 000 to win) |
| `--style` | style modes: total style to win, e.g. `25000` (turned into a per-minute rate) |
| `--time` | round length in minutes, 1–20 |
| `--bots` | 0–16 |

**Guided setup:** `./server-menu.sh` walks you through map, mode, bots, kill limit, time limit and port, shows the exact command and starts the server. It uses the newest exported `gevechtspel-*-linux-x86_64` next to the script (or `GEVECHTSPEL_BIN=...`), otherwise it runs from source. It can save your choices as defaults (`./server-menu.sh --defaults` starts with them right away) and, after you confirm, install them as the `gevechtspel-server` systemd user service (the old service file is backed up first).

**Ports (UDP):** the game uses `7777`. The server list reads status, ping and players on the game port + 1 (`7778`). To be reachable from outside your network, forward both ports on your router and open them in your firewall. Joining works without `7778`, but then the status doesn't show.

To connect from the command line: `./run.sh -- --connect 1.2.3.4:7777 --name Friend`

## Build from source

You need **Godot 4.7** (the scripts expect a portable `godot` binary at `~/.local/bin/godot`).

```bash
git clone https://github.com/MezzoSplash/gevechtspel2.git
cd gevechtspel2
./run.sh            # play
./run.sh --editor   # open in the Godot editor
```

On Windows, open `project.godot` in Godot 4.7. To make Windows and Linux x86_64 builds, use the export presets in `export_presets.cfg`.

Foundry, Rooftops and Quay are generated by the scripts in `tools/` (`gen_foundry.py`, `gen_rooftops.py`, `gen_quay.py`). After you change Quay, run `godot --headless --path . -s res://tools/check_quay.gd` to check collision, routes, bot navigation and the surfs.

## Credits

Made by [MezzoSplash](https://github.com/MezzoSplash). The gun, footstep, impact and UI sounds are CC0, from the Free Firearm Sound Library and Kenney. The radar voice lines use Piper TTS, and the music is synthesized in this project. Discord Rich Presence uses an MIT addon. See [CREDITS.md](CREDITS.md) for the full list.
