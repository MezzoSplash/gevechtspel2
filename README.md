# Gevechtspel

A small native Linux + Windows arena shooter. Feel first, art later.

**v0.2.9** — visible heads, headshot tick and marker, network version check, join and bot fixes.

## Play (Linux)

Godot 4.7.2 is expected at `~/.local/bin/godot` (portable binary, not the distro package).

```bash
./run.sh
```

- **WASD** move, **Space** jump, **mouse** look
- **Shift** sprint (less accurate), **Ctrl** or **C** crouch (hides behind cover); crouch while sprinting slides
- **LMB** fire (rifle holds; pistol, shotgun and sniper fire once per click), **R** reload, **Q** or **1/2/3/4** switch guns (rifle, pistol, shotgun, sniper)
- **RMB** zoom (sniper only)
- **G** grenade (two per life)
- **Up/Down** pick a streak slot, **Enter** activates it (radar after 3 kills)
- **T** chat (Enter sends, Esc cancels)
- **Esc** pause menu (resume, settings, leave, quit)
- **Tab** scoreboard

Boot menu: **Play locally** (dummies), **Host game**, or **Connect**.

Two windows on this PC:

1. `./run.sh` → Host game
2. `./run.sh` → Connect `127.0.0.1`

Dedicated server (optional):

```bash
./run-server.sh 7777
./run.sh -- --connect 127.0.0.1:7777 --name Friend
```

Bots fill empty slots to 5v5. Same guns as you. Use cover. Health comes back after 4.5 seconds without damage. Die and you respawn after 2 seconds. Tab shows team score.

## Editor

```bash
./run.sh --editor
```

## Credits

Gun, footstep, hurt and grenade sounds are CC0 (Free Firearm Sound Library, Kenney). See [CREDITS.md](CREDITS.md).
