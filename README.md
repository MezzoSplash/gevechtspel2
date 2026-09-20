# Gevechtspel

A small native Linux + Windows arena shooter. Feel first, art later.

**v0.2.3** — GLB weapon models, join/leave notices, code comments.

## Play (Linux)

Godot 4.7.2 is expected at `~/.local/bin/godot` (portable binary, not the distro package).

```bash
./run.sh
```

- **WASD** move, **Space** jump, **mouse** look
- **Shift** sprint (less accurate), **Ctrl** or **C** crouch (hides behind cover)
- **LMB** fire, **R** reload, **Q** or **1/2/3** switch guns (rifle, pistol, shotgun)
- **Esc** frees the mouse, click the window to recapture
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

Bots fill empty slots to 5v5. Same guns as you. Use cover. Die and you respawn after 2 seconds. Tab shows team score.

## Editor

```bash
./run.sh --editor
```
