# Gevechtspel

Feel-first 5v5 arena FPS. Art is later. If a change does not make shooting or moving more satisfying, it is out of scope.

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

## Scope lock

Do not add game modes, shops, extra maps, cosmetics, Steam, or matchmaking until 5v5 TDM with bot-fill is fun.

Current slice: **two humans**. Offline Play locally still works. Host / Connect uses ENet. Hits and dummy AI are server-side. Client predicts its own movement (authority on owner). Dummies stay stationary until a later slice.

## Commands

```
./run.sh                  # play
./run.sh --editor         # editor
./run.sh --headless --quit-after 1
```
