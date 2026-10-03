# Gevechtspel

A small native Linux + Windows arena shooter. Feel first, art later.

**v0.2.13** — classes (custom loadouts), melee on E, bullet impacts, punchier shotgun, team radar with announcer.

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
- **Up/Down** pick a streak slot, **Enter** activates it (radar after 3 kills: your whole team sees the enemies for 4 seconds, and the other team hears "Enemy radar online")
- **T** chat (Enter sends, Esc cancels)
- **Esc** pause menu (resume, change class, settings, leave, quit)
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

Bots fill empty slots to 5v5. Same guns as you. Use cover. Health comes back after 4.5 seconds without damage. Die and you respawn after 2 seconds. Tab shows team score. When a round ends, everyone watches the final killcam: the last kill of the round through the killer's eyes, slowed down at the kill, before the scoreboard.

## Classes

Main menu → **Classes**: create, rename, edit and delete up to 8 classes. A class is a primary (rifle, shotgun or sniper), a secondary (pistol) and up to 3 grenades. Defaults: **Rifleman** (rifle, pistol, 2 frags), **Breacher** (shotgun, pistol, 3 frags), **Sniper** (sniper, pistol, 1 frag). Saved in `user://classes.cfg` (Linux: `~/.local/share/godot/app_userdata/Gevechtspel/classes.cfg`).

When you first spawn into a match you pick a class (keys 1–8 or click); after 10 seconds your last used class is picked for you. **Esc → Change class** during a match: the new class applies at your next spawn. The server checks every loadout (known guns, at most 3 grenades) and only lets you switch to and fire the guns in your class. Bots keep their fixed guns.

## Editor

```bash
./run.sh --editor
```

## Credits

Gun, footstep, hurt, melee and grenade sounds are CC0 (Free Firearm Sound Library, Kenney); the radar voice lines are Piper TTS with the public-domain LJ Speech voice. See [CREDITS.md](CREDITS.md).
