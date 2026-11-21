# Gevechtspel

Feel-first arena FPS built around style and movement: surf, wallrun, dive, slide, and land Tony Hawk style combos and trickshots. If a change does not make shooting, moving or pulling off tricks more satisfying, it is out of scope. When making maps, props or weapons, follow [docs/art/index.html](docs/art/index.html).

Current game: 6 modes (TDM, FFA, Style TDM, Style FFA, Gun Game, CTF on Quay), 5 maps (Townhouses, Foundry, Rooftops, Quay, Skyline; see `scripts/maps.gd`), 8 guns plus frag, knife and melee, a grapple, bots up to 16, UAV (a physical drone you can shoot down), RC-XD and LOS scorestreaks, MVP killcam, B1 crystal bodies.

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

- `shared/game.gd` (autoload `Game`) is being split. Pure logic moves into `RefCounted` helpers with static functions (`shared/tricks.gd`, `shared/combo_ledger.gd`, `shared/match_rules.gd`). State, signals and every `@rpc` stay in `game.gd` on the same node path, and the old function names stay as thin wrappers. `player.gd` follows the same pattern with `shared/style_track.gd`: a helper may hold state, as long as it is one job, stays off the network and stays reachable through the pawn's own function names. `hud.gd` follows the HUD's own pattern: each piece is a node or helper in `scripts/hud/` (`ScoreboardView`, `ComboMeter`, `SpeedMeter`, `DeathReport`, `HudChat`, `PerfOverlay`, `WeaponBar`, `StreakColumn`, `HudSkin`, `HudBoard`, `TrickPopup`, `StandingLine`, `HudOverlay`, `HudVitals`) and `Hud` keeps the scene nodes, the signal hookups, the key handling and its old function names as wrappers (#315, done). A new HUD piece gets its own file there, not a block in `hud.gd`.
- One responsibility per file, a file stops around 700 lines and a function around 60; going past that is a signal, not a rule. `game.gd` and `player.gd` still carry more than one job and are split in that order (`hud.gd` is done, #315). One source per data table: a second copy of the same mapping (shadow quality, layout offsets, score order) is a bug waiting for one side to change.
- A change to anything sent over the network bumps `NET_VERSION`. A refactor must not.

## Checks

- `tools/run_checks.sh` imports the project and runs every headless `tools/check_*`; CI runs it on every push and PR. It must exit 0 before a merge, and only merge when the PR's own CI is green: no overrides or auto-merge on red. Known-failing and skipped checks are listed at the top of the script.
- Add a `tools/check_*.tscn` for new behaviour.

## Recent work

- #317 slice 1 (bot_brain.gd split): the movement tricks are `BotTricks` (`scripts/bot_tricks.gd`: `tick`,
  `tick_wall_trick`, `try_start_wall_trick`, `aim_into_wall`, `end_wall_trick`), the frag `BotGrenade`
  (`try_throw`, `pitches`, `throw_pitched`, `arc_clear`) and Hard's cover reload `BotCover` (`seeks_cover`,
  `should_reload`, `hold_last_round`, `tick_reload`, `pick`, `floor_ok`). Static on the brain (`b: BotBrain`)
  like Movement on the pawn: BotBrain keeps the state, the constants and every old name as a wrapper (the
  checks read both). bot_brain.gd 1550 -> 1300 lines. Parity: `tools/bot_parity.sh` (new) runs
  `tools/probe_bot_trace` (new) - a seeded 60 s TDM fight of 8 Hard bots, one line per bot per tick - on
  Quay, Foundry, Townhouses and Rooftops; this branch is byte-identical to main. It is deterministic only
  with navigation updates made synchronous (Godot threads them) and only for Hard in TDM on those maps:
  Easy/Medium hearing reads `Time.get_ticks_msec`, FFA spawns are spaced by wall-clock time, Skyline lands
  on one of two traces. It runs Godot with its own `XDG_DATA_HOME`, because the menu saves every match
  choice to `settings.cfg` (`run_checks.sh` does not isolate that yet). No behaviour or protocol change.
- #316 slice 8 (game.gd split): who fills which side is `BotRoster` (`shared/bot_roster.gd`, static and
  pure: `split_active`, `target`, `count`, `first_bot_on`, `smaller_team`, `larger_team`, `team_to_fill`,
  `bot_to_drop`). It takes `bot_split_active` / `bot_target` from Game (kept as wrappers; the numbers
  stay on Game) and the counting and choosing from main.gd, whose `_fill_bots` / `_trim_bots` now only
  ask, spawn or free, both bounded at `BOT_COUNT_MAX * 2` (the balanced fill and trim were `while`
  loops). main.gd's `_team_count`, `_human_count`, `_smaller_team`, `_larger_team`, `_bot_pawn_count`,
  `_bot_count_on`, `_first_bot_on`, `_team_short_of_bots` and `_team_over_bots` are gone. Check:
  `tools/check_bot_roster` (new, loose pawns, no match); `check_tdm_team_setup` unchanged. No behaviour
  or protocol change.
- Export deps: the muzzle flashes' `@tool` preview script lived in `tools/`, which `export_presets.cfg`
  leaves out, so the first export for v0.6.0 lost all eight flashes and the gun scenes holding them (fine in
  the editor and CI). It is `assets/vfx/play_muzzle_inspector_tool.gd` now. Check: `tools/check_export_deps`
  (no .tscn/.tres ext_resource or .gd preload into an excluded folder). No protocol change.
- Weapon kits: an artist adds or replaces a gun's art without code (`docs/art/wapens.md`, Dutch, the
  artist's side). `WeaponKit` (`scripts/weapon_kit.gd`) finds it by name: `assets/weapons/<id>/<id>.tscn`
  (or `<id>.glb`), then the flat files from before (`assets/weapons/<id>.glb|.tscn`), and the sounds in
  the folder by the start of their name (`fire*` - several are variations, picked per shot - `reload`,
  `draw`/`equip`, `dry`/`empty`; ogg/wav/mp3) over `WeaponDef.fire_sound`. `SHARED` maps the shank to the
  knife kit; `_`-folders (`_template`) are not guns. Loaded once, warmed in `Game._ready` like the old
  preload table (`Weapon.MODEL_SCENES` / `KNIFE_SCENE` are `Weapon.model_scene(id)` / `knife_scene()`).
  The scene contract is in `WeaponModel`: a non-mesh node named `Muzzle` (older `muzzle_flash`; the
  low-poly barrel-tip meshes named Muzzle are not it) is where tracers leave and everything under it is
  the flash - particles (GPU and CPU) burst per shot, meshes/sprites/lights show for `flash_time`
  (`show_flash`, also in the killcam), a light there replaces the shared muzzle light, and the flash is
  left out of the gun's size (`aabb_in_parent(..., skip)`); an optional `Sight` marker sets the ADS
  height (older `Front_Sight*` mesh); clips `fire` / `reload` / `draw` by name (library prefix or a
  `_fire` suffix, the SMG's). A reload clip is stretched to `reload_time` and replaces the code's gun
  tilt and loose mag (the hand keeps the style's curve); draw plays on a switch with the kit's draw
  sound. `WeaponKit.problems(id)` says what is wrong with a folder in the artist's words. The SMG moved
  to `smg/smg.tscn`; every other gun still uses its flat file, unchanged. Tools: `tools/weapon_lab`
  (F6 in the editor: every gun, no death, frozen clock, L rereads the files, problems on screen;
  `-- --shot DIR` renders each gun firing) and `assets/weapons/_template`. Check:
  `tools/check_weapon_kits`. No protocol change.
- #342 the frag is a crystal: `GrenadeLook` (`scripts/grenade_look.gd`) replaces the green sphere - a cut
  olive gem (`CrystalMesh.part(&"grenade")`, 0.22 m, the art guide's frag #26732E with a little emission), a
  fuse band round its belt (`grenade_seam`) and a pale cap (`grenade_pin`) that glows in the thrower's team
  colour in team modes (`set_team`; FFA keeps it pale). It tumbles along its flight and trails a thin
  streak above `TRAIL_FROM` 9 m/s, both from its own motion (sampled since it last moved, faster than
  `SNAP_SPEED` is a snap), and the band pulses from `PULSE_SLOW` to `PULSE_FAST` and turns from ice to
  `CrystalUi.DANGER` over the last `DANGER_TIME` 0.4 s of the fuse (`Grenade._age`, on every copy). One
  source: the flying grenade and the killcam's replay grenades build the same node (the killcam had its own
  sphere and now lerps them between snapshots). `LOOK_LIFT` keeps a resting frag on its point instead of in
  the floor. The boom bursts into `grenade_frag` splinters (ice, olive, fire) that end between 65% and 100%
  of the splash radius (`Grenade.spawn_shards`; the RC-XD uses its own radius) and a flat ice ring runs out
  to the radius (`spawn_shock_ring`); flash, light and sound are unchanged. Client copies get the thrower
  from the spawn RPC that already carried it (`Grenade.set_thrower`). Check: `tools/check_grenade_look`;
  `tools/shot_grenade` renders it in a studio lit like Townhouses (xvfb). No protocol change.
- #316 slice 7 (player.gd split): what a pawn carries is `PawnKit` (`scripts/pawn_kit.gd`: `weapon_ids`,
  `grenade_max`, `knife_max`, `apply_loadout`, `apply_bot_loadout`, `try_throw_grenade`, `try_throw_knife`,
  `notify_grenades`, `gun_speed_mult`, `start_lunge`, `consume_lunge`, `spread_multiplier`,
  `min_spread_multiplier`) and how it looks is `PawnBody` (`scripts/pawn_body.gd`: `set_display_name`,
  `arms_enabled`, `attach_arms`, `team_color`, `paint_body`, `update_stance`, `apply_stance`, `pose_figure`,
  `ceiling_blocked`, `play_pickup_flash`, `throw_amt`, `roll_flip`, `pose_body`, `draw_grapple`). Static
  on the pawn; `team_color`, `paint_body` and `pose_body` stay static on Player too (killcam, HUD, minimap).
  Player keeps the state, the input callbacks, the grapple press and pull, and every old name.
  player.gd ~1425 -> ~1270 lines. Checks: the suite (178), the movement trace byte-identical to main,
  `tools/net_grenade.sh` and `check_death_report -- --net` clean. No behaviour or protocol change.
- #338: the server's position corrections reach the client again. `Game.correct_position(peer_id, v)` was
  called with only the position (`PawnNet.accept_claim`, `PawnVitals.pull_out_of_void`), so every client
  dropped it ("Method expected 2 argument(s)") and a refused claim (#B1) or a remote void pull never put
  anyone back. Both pass the peer now; the signature is unchanged, so no `NET_VERSION` bump. Check:
  `tools/check_rpc_args` (new, a SceneTree script) reads every `@rpc func` and every `.rpc(` / `.rpc_id(`
  call in scripts/ and shared/ and fails on a wrong argument count (it found exactly these two of 116).
  `check_movement -- --net` flies the pawn to its test area under the claim limits (collision off on the
  way: its own floor slab is in the route) instead of teleporting, asserts a refused 40 m jump is pulled
  back, and online expects no wallrun moves along walls the server does not have (#B2's `wall_beside`);
  in that run the deliberate jump is the only claim the server refuses.
- #316 slice 6 (player.gd split): how a pawn lives on other machines is `PawnNet` (`scripts/pawn_net.gd`:
  `apply_network_pose`, `update_nametag`, `enemy_in_sight`, `receive_net_pos`, `accept_claim`,
  `claim_reachable`, `apply_snap`, `smooth_remote`, `apply_remote_visual`) and how it is set up is
  `PawnSetup` (`scripts/pawn_setup.gd`: `ready`, `tick_audio_bus`, `init_loadout`, `configure_control`,
  `dup_body_mat`, `apply_team_visual`). Static on the pawn; Player keeps the synced properties, the input
  callbacks and every old name. player.gd ~1620 -> ~1425 lines. Checks: the suite, the movement trace still
  byte-identical to main, `check_death_report -- --net` clean. `check_movement -- --net` fails "WALL TO WALL
  in the combo" on main as well: the server's `correct_position` RPC is called with one argument where it
  takes two, so no correction ever reached a client (#338, fixed since). No behaviour or protocol change here.
- #316 slice 5 (player.gd split): a pawn's life is `PawnVitals` (`scripts/pawn_vitals.gd`: `check_kill_y`,
  `pull_out_of_void`, `apply_hit`, `point_hits_head`, `apply_hurt_state`, `die`, `apply_respawn_state`) and how
  it feels and sounds while it moves is `PawnFeel` (`scripts/pawn_feel.gd`: `tick_feet`, `apply_carry_fov`,
  `tick_move_fx`, `tick_speed_fx`, `tick_speed_lines`, `tick_wind`). Both static on the pawn like `Movement`;
  Player keeps the state, the constants, the signals and every old name as a wrapper. player.gd ~1880 ->
  ~1620 lines. Checks: 19 checks on hits, deaths, pickups, killcam, speed FX and movement; the movement
  trace (`tools/probe_move_trace`) still matches main byte for byte; `check_death_report -- --net` against
  a local 8-bot server, no script errors on either side. No behaviour or protocol change.
- #316 slice 4 (player.gd split, the first): the local human's movement tick left `_physics_process` (188
  lines -> 22) for `MoveTick` (`scripts/move_tick.gd`, static on the pawn like `Movement`): `run` calls
  `read_keys` (the lock and the `_in_*` keys), the pawn's slide/dive/stance/grapple starts, `tick_jump`
  (gravity, jump buffer, wall jump, slide-dive, crouch jump, roll lock), `wish` (direction, speed, sprint,
  LOS coast), `horizontal` (lunge, air, knockback, `carry`, roll, slide, ground), the wallrun's horizontal,
  `vertical` (wallrun sink, grapple pull, surf clip), `move_and_slide` and `after_move`, in the old order;
  every phase is under 60 lines. Bots and remote pawns keep their branches in `_physics_process`.
  player.gd 2052 -> ~1880 lines. Checks: the 15 movement checks, and `tools/probe_move_trace` (new, a
  parity probe: a fixed input script traced per tick) gives byte-identical traces on main and this
  branch, slide, dive and wallrun included. No behaviour or protocol change.
- #316 slice 3 (game.gd split): streaks, rounds and scores. `Streaks` has `request_use`, the RC-XD RPC bodies
  (`rc_drive`, `rc_detonate`, `on_rc_pose`, `on_rc_end`, `on_rc_hp`; drive and detonate keep their
  owner-only sender rule), `announce_rc` / `show_rc_announce`, `uav_shot_down` and `uav_end`. `MatchFlow` has
  `killcam_pick`, `apply_all_scores`, `apply_freeze` (one body for `set_round_frozen` and
  `sync_round_frozen`, which were two copies), `apply_regen`, `push_bot_poses` / `apply_bot_poses` and
  `apply_roster`; `Tricks.apply` is `_apply_trick`, `CTF.tick_any` / `apply_flags` are `_tick_ctf` /
  `_apply_flags`. The score order is `MatchRules.sort_scores`, one source: `Game._sort_scores` and
  `HudBoard.sort_scores` were two copies and now both call it. game.gd ~2210 -> ~2060 lines. Checks: the
  suite, `tools/net_grenade.sh` and `check_death_report -- --net` (a client in an 8-bot match, no script
  errors on either side). No behaviour or protocol change.
- #316 slice 2 (game.gd split): the shot path and the throwables' RPC bodies left Game. `Combat` has
  `request_fire` (the server side of `request_weapon_fire`: class, freeze, fire-rate and origin checks, lag
  rewind, tracer and hit marker), `on_shot_fx`, `announce_weapon`, `request_switch`, `on_weapon_sync`,
  `notify_reload`, `request_reload` and `weapon_display_name`; `Throwables` has `request_grenade` /
  `request_knife`, the grenade and knife counts, and the client sides of `sync_grenade_spawn` / `pose` /
  `boom` and `sync_knife_spawn` / `done`. The RPC signatures and channels are untouched; `request_weapon_switch`
  and `request_reload` keep their own sender rule (no fallback to the local id). game.gd ~2360 -> ~2210
  lines. Checks: the existing ones, plus `tools/net_grenade.sh` and `check_death_report -- --net` against a
  local server. No behaviour or protocol change.
- #316 slice 1 (game.gd split): the bot difficulty table is `BotProfiles` (`shared/bot_profiles.gd`: `EASY..HARD`,
  `IDS`, `NAMES`, `PROFILES`, `profile`, `parse`); Game's `BOT_*` names are aliases of it. The lobby RPC bodies
  (`submit_display_name`, `apply_display_name`, `submit_chat`, `request_lobby_team`) and `set_player_name`
  are `Lobby.submit_name` / `apply_name` / `submit_chat` / `request_team` / `set_player_name` (`Lobby.sender`
  is the peer whose RPC runs); the settings entry points (`remember_match_choice`, `set_colorblind`,
  `should_relaunch`, `relaunch_with_renderer`, `set_perf_overlay`, `_apply_fov_now`, `remember_server`,
  `add_favorite`, `remove_favorite`) are in `GameSettings`. The RPCs and names stay on Game.
  game.gd 2504 -> ~2360 lines. Check: `tools/check_game_helpers` (new; also green on the code before the
  move). No behaviour or protocol change.
- #315 slice 4 (hud.gd split, the last): everything `Hud._draw` drew is `HudOverlay`, a full-rect Control that
  is the HUD's first child, so it draws under every other node as before - crosshair (gap from spread and
  `fire_punch`, none on sniper hip), LOS bar, hurt vignette (`HURT_TIME`), damage wedges (`DMG_*`, static
  `dir_angle`) and hit markers (`HIT_TIME` / `KILL_HIT_TIME`). `hurt` / `punch` / `clear` redraw at once, so a
  frozen HUD (a shot tool) shows the same as a live one. HP bar, armour bar, pickup toast and the knife blink
  are `HudVitals` (`set_health` returns whether HP dropped, static `fill_for`, `HP_OK/MID/LOW`). `Hud` keeps
  `add_damage_dir`, `dir_angle`, `punch_crosshair`, `set_sniper_ads/hip`, `_on_hit`, `_on_health`,
  `_on_armour`, `flash_pickup`, `blink_knives` and a `pickup_toast` property; unused constant aliases are gone.
  hud.gd 1642 -> ~700 lines over the four slices, a coordinator. Check: `tools/check_hud_overlay` (new);
  `shot_hud` renders pixel-identical to main inside the vignette border. No behaviour or protocol change.
- #315 slice 3 (hud.gd split): the Tab board's timing and the round-end cards are `HudBoard` (`open`,
  `tick(delta, tab)`, `round_ended`, `killcam_finished`, the winner card and style king, static
  `sort_scores`; `ScoreboardView` still builds the board), the trickshot word is a `TrickPopup` node
  (`show_trick`, `text`, `hide_trick`) and the line under the clock a `StandingLine` label (FFA place / CTF
  flags, `place`, static `ordinal`). Reachable as `hud.board` / `hud.trick` / `hud._standing`; `Hud`
  keeps `show_trick`, `trick_text`, `_hide_trick`, `style_king_text`, `_refresh_scoreboard`,
  `_refresh_standing`, `_place_standing`, `_sort_scores`, `_ordinal` and `_popup_top`. hud.gd 1142 -> ~880
  lines. Check: `tools/check_hud_board` (new); `shot_hud` / `shot_scoreboard` set `hud.board.open`.
  No behaviour or protocol change.
- #315 slice 2 (hud.gd split): the weapon slots and grenade pill are `WeaponBar`, the scorestreak column
  (caption, pips, three slots with cost/READY tags, arrow-key `sel`, the RC-XD drive line, the announcer
  and its radar-voice cooldown) is `StreakColumn`, and the crystal skin behind a ColorRect is static
  `HudSkin` (`skin`, `paint`, `fit_label`). Both are `RefCounted` over the scene's own nodes, reachable as
  `hud.weapons` / `hud.streaks`; `Hud.set_ammo`, `set_weapon_slots`, `set_weapon_index`, `set_grenades`,
  `set_streak`, `set_rc_drive`, `clear_radar`, `_skin`, `_paint`, `_refresh_streak_ui` and
  `_play_radar_voice` stay as wrappers, the popups stay in `Hud`. The streak slots' white frame bars (always
  hidden since the crystal restyle) are gone. hud.gd ~1470 -> 1142 lines. Check: `tools/check_hud_bars`
  (new); `check_uav_voice`, `check_crystal_style`, `check_crystal_layout` and `shot_hud` read
  `hud.streaks`. No behaviour or protocol change.
- #315 slice 1 (hud.gd split): the death report is its own `DeathReport` node (`scripts/hud/death_report.gd`,
  same "V/..." children, `show_report`), chat and the join/leave feed are `HudChat` (a `RefCounted` over the
  scene's `ChatLog` / `ChatInput` / `PresenceFeed`, given the HUD's `_name_color`; `bb_escape` is static),
  and the perf overlay text is `PerfOverlay` (`text`, `gpu_ms`, static `hint`). `Hud.show_death_report`,
  `_open_chat` / `_close_chat`, `_on_chat_message`, `_on_presence`, `_bb_escape`, `_perf_text` and
  `Hud.perf_hint` stay as wrappers; key handling stays in `Hud._input`. hud.gd 1642 -> ~1470 lines.
  Check: `tools/check_hud_chat` (new); `check_death_report`, `check_perf_hint`, `check_crystal_layout`
  unchanged. No behaviour or protocol change.
- #314 the last flat HUD pieces: the death report is a smoke shard with a red (`CrystalUi.DANGER`) top
  seam and caps head, the streak pips are tiny slanted shards (`Hud.PIP_OFF` / `PIP_MARK`, lit in the
  accent), and the combo timer is a slim shard whose bottom seam is the time left (`ComboMeter.fill` is
  that `CrystalStyle`; its `seam_color` is the state: pale, red under `Combo.WARN`, frozen ice). The HUD
  builds no `StyleBoxFlat` any more; `check_crystal_layout` asserts that over `hud.gd` and
  `scripts/hud/*.gd`. `tools/shot_hud` renders `/tmp/hud-combo*.png`. No protocol change.
- #312/#313 crystal scoreboard and class select: the Tab board (`ScoreboardView`) is floating shards - a
  header shard, one panel per team whose top seam is the team colour lit to score / `score_limit()`
  (`ScoreboardView.progress`), a faint shard per row and your own row as pale shell with an ice seam
  (no more gold name; gold stays on the STYLE column and the style king, trick rewards). The winner card
  is a shard with the accent on its bottom seam ("YOU WIN" is pale shell), the style king a slim shard
  with a gold seam. The in-game `ClassSelect` takes `CrystalTheme` itself (it is built in code): a
  centred staggered column of `MenuButtonBig` shards with the loadout as a button hint, widened so a
  long loadout never runs into the name, the countdown as a seam that runs out over `AUTO_TIME` (red
  in the last 3 s), "‹ BACK" and a footer shard under the column. Shared pieces are `CrystalUi.shard`,
  `caption` and `bold_font`; `Hud._sb_box` and `ScoreboardView.box` are gone. Check: scoreboard and
  class-select asserts in `tools/check_crystal_layout`; `tools/shot_scoreboard`, `shot_winner` and
  `shot_hud` render them. No protocol change.
- Townhouses v2 (`tools/gen_townhouses.py`, the third map rebuild; the old scene was hand-written):
  a Dutch canal street, 64 x 96, walls 15 m. Canal down the middle at -3 m (`kill_y` -6), quay walls
  as wallruns, boats, two bridges and a drawbridge under an 11 m steel portal (landmark and anchor).
  Each team owns one row of canal houses whose 57° roof is the flow line: 9 m at its own end to 3 m
  past the middle, mid and foot strips. A back-alley ramp reaches the roof deck; each ramp ends flush
  on the edge it climbs (overlapped into a deck it came out 0.6 m low, past the nav agent's 0.5 m).
  Accepted as a blockout after one playtest. `check_townhouses` was rewritten on the Foundry pattern.
- #145 Shank class (#306): knife primary (`data/weapons/shank.tres`, `WeaponDef.melee`), pistol, 1 frag.
  Fire or E stabs through `Melee.swing_shank`: 100 from behind (`BACK_DOT` -0.34), 50 from the front
  or side, `SHANK_RANGE` 2.2 m, a tighter cone than the bash, same 0.8 s cooldown. Holding it moves
  you x1.23 (sprint about 14 m/s). At sprint, on the ground and slower than the lunge itself, a stab
  lunges `LUNGE_M` 2.5 m in 0.16 s and the blade reaches from where the step ends; faster than the
  lunge (surf, grapple, carry) or in the air there is no lunge, because it sets the horizontal velocity
  and would brake the run or air-dash (`check_shank` covers both). Gun Game demotes a shank kill; bots
  can draw it and close in and stab (`_fight_shank`). An older `classes.cfg` gains the preset once.
  `NET_VERSION` 0.5.20 (unreleased) covers the new weapon id.
- Menu song: "Reload" (made with Mystellic) replaces the synthesized menu loop. It is
  `assets/sounds/songs/Reload.ogg` (Ogg Vorbis q6, 2.9 MB; it was added as a 24 MB WAV), loaded as a
  loop from `MatchAudio.MENU_SONG`; `music_menu.wav` and its generator are gone. `MENU_MUSIC_DB` went
  -6 -> 0: the song averages 7.6 dB under the old loop and peaks at 0 dBFS. CREDITS/ASSETS list it;
  its commercial terms are still to be confirmed (#135). `check_bot_kit` asserts it loops.
- Foundry v2 (`tools/gen_foundry.py`, the second map rebuild, done blockout first and playtested in
  rounds): 64 x 90, walls 16 m. A real foundry, not boxes: the casting hall with the cupola furnace in
  the middle (stack through the skylight to 18 m; landmark, anchor, and the roof's divider), a 3 m
  mezzanine, press, pouring line of flasks; per team an ore bunker (10 m) with a 51 m surf down the
  outer wall (mid and foot strips), a ramp to the hall roof; crane runways at 11 m with hanging
  ladles as grapple anchors; per flank a container island, a shed and the tank; sand heap, ingots,
  ladle cars, smokestacks outside. Playtest notes that shaped it: round 1 was too open ("er mag meer
  staan, vooral binnen"), round 2 was generic blocks ("het moet een echte foundry zijn"). The longest
  clean ground lane is printed by `check_foundry`, not enforced (see the Rooftops lesson below).
  `heap_h` / `cylinder_h` place a piece and its half-turn. `NET_VERSION` stays 0.5.20 (unreleased).
- Rooftops is back as it was (the original layout from before the map pass; #304 reverted). A v2
  rebuilt around flow lines (#303, closed) played too busy: the 35 m clean-lane rule was met with truck
  blocks everywhere, and the map turned into a maze of sightline blockers. Lesson for the rebuilds:
  break lanes with height and real geometry (decks, ramps, roofs, surfs, landmarks), not with a block
  every few metres, and make the pieces belong to the place (Foundry v2: furnace, ladles, moulds).
- Grapple (`shared/grapple.gd`, a stateful helper like StyleTrack): `grapple` (V / Mouse 4, rebindable)
  fires a ray from the eye up to `RANGE` 32 m; a hit anchors and pulls while the key is held
  (`PULL_ACCEL` 55 m/s² up to `PULL_SPEED` 22 m/s, sideways bleed `SIDE_DAMP`), from the floor with a
  `GROUND_LIFT`. It ends on release, arrival (`ARRIVE` 1.8 m), `PULL_TIME` 1.6 s, a wallrun or dive taking
  over, death, or the line being cut - traced from `LINE_FROM` 1.5 m (the eye's height: from the chest a
  wall the eye saw over cut the rope on tick one) after `CUT_GRACE`. The velocity is kept: the release
  is the move. `COOLDOWN` 3 s from the start, `MISS_COOLDOWN` 0.35 s after a miss. `move_fx` gains
  `MOVE_GRAPPLE` (wallrun and dive outrank it); `grappling` / `grapple_at` are synced so every client
  draws `GrappleRope` from the left hand, which `CrystalHands.reach_toward` points at the anchor (body and
  view hands). Style: `GRAPPLE KILL` (175, within `GRAPPLE_RECENT` 0.5 s of the rope, not also an
  AIRSHOT), combo move GRAPPLE (60), speed meter chip. Not yet: bots, the rope in the killcam.
  Check: `tools/check_grapple`. `NET_VERSION` 0.5.20.
- Crouch pose: the crouched torso no longer sticks out behind the legs. The crouched head (0.78 m, the
  hitbox) leaves a neck at 0.59 m, and the torso hung from it at 68° with the hips left under the head,
  so its bottom ended 0.54 m behind the pelvis like a tail. Now `CROUCH_LEAN` 55°, `CROUCH_TORSO_SCALE`
  0.80 along the spine, `CROUCH_HANG` 0.15 (the torso's top tucks under the head), the hips go back
  `HIP_CROUCH_BACK` 0.28 and down to 0.36 to meet its bottom, knees forward 0.26: a squat. Head and
  hitbox are untouched. Check: two crouch asserts in `tools/check_crystal_body` (bottom meets the
  pelvis, no tail); `tools/shot_crouch` renders it from outside (needs a display). No protocol change.
- #270 wallrun routes run the wall: `tools/probe_bot_route` (not CI) plays an FFA per map and counts
  route chances, picks, completions and wallruns on/off a route. It measured 1 wallrun per 15 routes:
  a route is exactly `BotWall.MIN_LEN` of face, so the one scan per `TRICK_SCAN` came too late, the
  last trick's `TRICK_CD` blocked a third of the picks and a route left `state` on FIGHT. On a wallrun
  route a bot now scans every tick through the cooldown, skips the dice (Easy's 0 still means never)
  and hunts; that is about 1 in 4 (Medium 8 -> 34, Hard 9 -> 36 wallruns on a route over five maps).
  Check: route asserts in `tools/check_bot_wall`. No protocol change.
- #270 (all maps): Townhouses, Foundry and Quay ship route hints too, so all five maps do
  (`data/bot_routes/*.json`, 60 wallrun routes each). `tools/gen_bot_routes` validates every candidate
  before it trims, and trims round-robin over wall faces (plane + height, both run directions, a start
  every `FACE_STEP` 6 m), so short walls survive the 60-route cap: Foundry's roof walls only got a
  route that way. Seeded per map, so one map alone writes the same file as a full run. Skyline and
  Rooftops were regenerated with the same tool. `check_bot_route` asserts every map in `Maps.ORDER`.
  No protocol change.
- Resolution pick survives a second monitor: `load_settings` used to clamp the saved size to the monitor the
  window *started* on and save the result, so with a 1080p primary and a 1440p game monitor a 2560x1440 pick
  became 1920x1080 on every launch (XWayland reports the primary until the compositor moves the window, so
  remembering a monitor index does not help). The pick is now only replaced when no connected monitor can
  show it (`GameSettings.largest_screen`); `apply_window` still fits the window to its current monitor but
  no longer writes that back into `Game.window_size`. Check: `tools/check_window_pick`. No protocol change.
- UI crystal step 5 (layout, `docs/ui-crystal/HANDOFF.md` 4.4): the screens follow the mockups, not only
  the theme. `CrystalUi` (`scripts/ui/crystal_ui.gd`) holds the shared pieces - the wordmark (light GEVECHT
  over bold SPEL beside `CrystalMark`, the gem from the mockup), a tracked hint inside a button, a red seam
  for leave/quit (`seam_color` duplicates the theme shard, the theme's own stays ice), unequal widths
  (`stagger`), the key-hint footer shard and the pause score shards. Main menu: wordmark, a movement tag
  line, hints in the buttons, the status line under them. Pause: team scores in team colours around a
  pale clock (FFA: you against the leader), a centred staggered column, the footer. Settings: a
  "SETTINGS" caption over the tab's name, the six tabs as one row of `ChoiceChip` shards, glowing slider
  fill with a diamond grabber (`CrystalTheme.diamond`), a short pale "‹ BACK". Kill feed rows draw a
  smoke shard with the killer's colour on the right seam from the row's `draw` signal, so a row's
  children are unchanged. Not done: the HP gem (optional in the brief). Check:
  `tools/check_crystal_layout`; `tools/shot_pause` renders the pause menu. No protocol change.
- Speed meter (UI crystal step 4, `docs/ui-crystal/HANDOFF.md`): `SpeedMeter` (`scripts/hud/speed_meter.gd`)
  is a row of the bottom stack right above `HpRow`, so the notice and RELOAD rows come and go above it.
  The big number is the local pawn's horizontal speed, never smoothed; the shard's bottom seam is the
  meter (full at `FULL_SPEED` 24 m/s, eased at `SEAM_EASE`, a notch at `SPRINT_SPEED`), the number turns
  ice from `CARRY_ENTER_SPEED`, and a pale chip names WALLRUN / DIVE / SLIDE / SURF in that priority.
  Hidden without a live local pawn, while dead and in the final killcam. The stack grew a row, so the
  combo meter is pushed up to clear it (`Hud._place_combo`, at 720p it overlapped the notice before).
  Checks: `tools/check_speed_meter`, combo/speed rows in `tools/check_hud_layout`; `tools/shot_hud`
  renders `/tmp/hud-speed-*.png`. No protocol change.
- #269: a Hard bot reloads out of sight. `cover` on `Game.BOT_PROFILES` is true only for Hard. An empty
  mag (or a reload already running) sprints to the nearest standable spot within `COVER_R` 8 m that a
  chest ray from the enemy hits world before, searched once with `_side_open` on the heading. No such
  spot: sprint straight away, back to the enemy. The reload keeps running after line of sight breaks, so
  the hunt cannot walk them back into the open. One round left inside `RELOAD_HOLD_R` 6 m is a bash, not
  a reload; inside `MELEE_R` the bash still wins over both. Easy and Medium are unchanged. Check:
  `tools/check_bot_cover`. No protocol change.
- #255: the viewmodel spring is integrated in steps of at most 1/60 s, and `_sway_p.x` / `.z` are clamped
  like `.y`. At 60 fps it is still one step of the old spring. A half-second frame used to send the gun
  metres off screen. Check: `tools/check_sway`.
- #271: a bot grenade samples eight rays along `Grenade.initial_velocity` (the +4 m/s lob included) and
  refuses the throw when the arc hits the world. The cooldown is not spent, and one higher pitch is
  tried first. Player throws are untouched. Check: `tools/check_bot_grenade`.
- #261: an LOS landing probes the standing and crouched capsules plus a short floor ray, and returns INF
  when the body would end up under the floor or in the air. Every map has `Maps.kill_y` (scene metadata
  still wins; Skyline's -3 matches, the other four are -4). Under it, `Player._check_kill_y` is a fall
  death and the normal respawn puts you back on a spawn, except during the first second of spawn
  protection, which puts the body back on its spawn without a second death. The remaining spawn
  protection used to swallow the hit (`apply_hit` returns while `_spawn_protect > 0`), so a fall in
  that window never started the respawn. The plane clears that protection for the one hit. Check:
  `tools/check_void`, and the crouch/air cases in `tools/check_los`. No protocol change.
- v0.6.0 (released): weapon kits and real gun models with fire clips and muzzle VFX (#344, #347, #348),
  the crystal frag (#342), the G2 boot splash and icon (#346), muzzle flashes that survive the export (#350), position corrections that arrive (#338) and
  the hud/game/player splits (#315, #316 slices 1-7). `NET_VERSION` stays 0.5.20 - nothing new on the wire.
- v0.5.20 (released): the grapple (#302), Foundry v2 as a foundry (#307), Townhouses v2 as a canal street
  (#309), the Shank class (#306), the crouch as a squat (#301), bots taking and running wallrun routes on
  every map (#299, #300) and "Reload" as the menu song (#308). Rooftops went out and came back unchanged
  (#304, #305). `NET_VERSION` 0.5.20 - the rope is synced, two maps have new collision and the shank is a
  new weapon id, so a 0.5.19 peer is refused.
- v0.5.19 (released): the UI crystal restyle (#292 theme, #293 HUD skin, #295 speed meter, #296 layout of
  menu, pause, settings and kill feed; `docs/ui-crystal/HANDOFF.md`, only the HP gem is left) and a saved
  resolution that survives a second, smaller monitor (#297). `NET_VERSION` stays 0.5.16 - nothing goes over
  the wire.
- v0.5.18 (released): bots have characters (#267 - aggressive, holder, flanker and chaos as `data/bots/*.tres`
  behind `BotStyle`, assigned per bot slot, so difficulty sets how sharp a bot is and the character how it
  fights), they find and run wallrun walls themselves (#278, raycast only, `trick` chance per difficulty) and
  they follow route hints generated from the map (#270 slice 1: `BotRoutes` + `data/bot_routes/*.json`,
  validated once at load). Bot state is one `State` enum with a separate `Route` axis (#268, no behaviour
  change), the pawn roster is built once per tick and each bot caches LOS for 6 ticks (#272). `NET_VERSION`
  stays 0.5.16 - bots are server pawns, so only the server has to update.
- v0.5.17 (released): bots only know what they notice (#266, #274) - below Hard a bot knows an enemy it
  saw, was shot by or heard (`omni`/`memory`/`hear` per profile), hunts the last known spot and patrols
  when it knows nobody, while Hard keeps the old omniscience. A reload of another player plays the gun
  they hold (#252 follow-up). No behaviour change from the further splits of game.gd, player.gd and
  hud.gd, and three headless checks that only passed on their retry are deterministic. `NET_VERSION`
  stays 0.5.16 - nothing new goes over the wire, so only the server has to update.

- v0.5.16 (released): a landing roll cannot be cut by a jump (#249), the carry is steered and hands over at
  sprint instead of stopping you (#251), every gun has its own reload style in first person and everyone
  else sees it (#252), and the final killcam is cut around the play with a VHS fast-forward and a landed
  sting (#258). `NET_VERSION` 0.5.16 - a 0.5.15 peer is refused.

- #258: the killcam is cut around the play. `Killcam` gets a director of pure static functions —
  `event_hits` (only events the killer or victim is part of count; in a bot match there is always a shot
  somewhere else, and unfiltered events made "dull" impossible), `action_at` (a frame counts when the
  killer moves faster than `DULL_SPEED` 4 m/s, does a move, or a killer/victim event lands within
  `DULL_PAD` 0.35 s), `action_start` (walks back from the kill over the run that leads into it, stops at
  a `CHAIN_GAP` 0.9 s of nothing, `LEAD_IN` of run-up, floored at `LOOKBACK` 9 s and always at least
  `MIN_LEN` 2.5 s before the kill, so the replay never has to hold a frame for its whole length) and
  `dull_runs` / `rate_at` (stretches longer than `FOLD_MIN` 0.5 s play at `FAST` 2.5x, the kill window
  stays slow). `KEEP` went 10 -> 14 s so the start can reach back 9 s and `_slice` cuts the wider
  window. `_plan_playback` fits the clip to the wall clock and `_rate` is the only playback rate: when the
  fast-forward would make the replay shorter than `play_length()`, earlier footage is pulled in (it plays
  as tape) and the rest goes into the kill's slow motion (`_kill_rate`, from `KILL_RATE_MIN` 0.12 up to
  real time); when the clip is too long — a 9 s chain at 1x used to run past the server's unlock and get
  cut off before the kill — everything before the last `RUNUP_KEEP` (1.5 s) is compressed up to
  `MAX_RUNUP` (3x), with the same VHS look. Either way the replay lasts exactly `play_length()`, so the
  kill is always shown and the server's unlock timing is untouched (at most a beat of held frame). On top:
  `vhs_amount` drives a VHS fast-forward overlay (`_draw_vhs`: scanlines, a rolling tracking band, tape
  noise, a `>> SP` OSD with a timecode) that fades over `VHS_FADE` and never covers the kill, the top
  bar's payout climbs from 0 to the bank and lands on the shot, and `_play_landed` layers the HUD's own
  combo samples under `_sfx_kill` (the special sting from `SPECIAL_BANK` 400 style, quiet if the replay
  is already over). Check: `tools/check_killcam_director` (synthetic buffers, no match);
  `tools/shot_killcam` renders the replay on a real screen (xvfb, `--vhs` forces the overlay into the
  shots).

- #252 (2/2, the wire): everyone else sees the reload now. `Weapon._start_reload` calls
  `Game.notify_reload`, a client asks the server over `request_reload` (channel 1, reliable, clamped to
  10 s so a pawn cannot reload for an hour) and the server broadcasts `sync_reload(peer_id,
  weapon_index, reload_time)` on the cosmetic channel (2, unreliable — it is one body animation).
  `Weapon.play_remote_reload` keeps that timer, `reload_anim()` reports it for remote pawns, and
  `reload_style_now()` takes the style from the LOADOUT index in the message, so a body matches even if
  `sync_weapon` is still in flight. `Player.reload_style()` rides `pose_body` into `CrystalBody`, which
  pulls the body's left hand off the gun through `CrystalHands.reach` with the same `ReloadAnims` curves
  as the shooter (the reload wins over the wall-run touch). The killcam passes the recorded weapon
  index, so a ghost reloads like the gun it holds. `NET_VERSION` 0.5.16: a 0.5.15 peer shows no reload
  on anyone else, so it is refused.

- #252 (1/2, first person): a reload looks like its gun now. `WeaponDef.reload_style` picks one of four
  styles — `mag` (rifle, smg, pistol, lmg), `shells` (shotgun, slug), `cylinder` (revolver), `bolt`
  (sniper) — and `scripts/reload_anims.gd` turns each into keyframed curves over the reload's own
  progress: gun rotation/offset, where the left hand goes, and the travel of the loose parts. Data, not
  branches: `solve(style, t, shells, cover)` returns one pose, `check_reload_anim` samples it without a
  pawn, and `Weapon` applies it. `accelerate`-free and no new assets: the magazine, the shell and the
  LMG's feed cover are procedural crystal blocks (`Weapon._setup_reload_rig`), and the left hand is the
  pawn's own first-person `CrystalHands`, pulled off the foregrip with its `reach` weight. The `mag`
  style tilts the gun ~35° on its side, drops the old mag, seats a new one with a jolt at ~60% and pulls
  the charging handle at ~85%; `shells` loads one shell per missing round over its load window and ends
  with a pump; `cylinder` rolls 70°, flicks the cases out and closes with a spin; `bolt` lifts the gun,
  pulls the bolt back 7 cm and seats a clip. `reload_cover` (LMG only) hinges the feed cover open at
  18-74%. Every style beats the amplitude floor the eye needs (0.3 rad of gun, 12 cm of hand) and the
  four differ measurably at 25/50/75%. `tools/shot_reload` renders one image per style per point
  (xvfb-run; not in CI). Timing, ammo and netcode are untouched — the body pose and the remote sync are
  the second half of #252.

- #251: a carry steered instead of drifted. `Movement.accelerate` only adds speed along the wish direction, so at 15 m/s the old forward speed stayed put and a held key bent the path sideways — the "ice" feel Gianni reported, since `CARRY_FRICTION` 0.06 is 150x less than ground friction. The carry branch now turns the horizontal velocity toward the wish direction at `CARRY_TURN_RATE` (7 rad/s) with its speed kept (`Movement.carry_steer`, the same trick as #152's `air_steer`), a wish further than `CARRY_COUNTER_ANGLE` (120°) brakes on `CARRY_COUNTER_FRICTION` (5) instead of turning, no keys keeps `CARRY_RELEASE_FRICTION`, and `CARRY_TIME` went 4.0 -> 2.5 with the last `CARRY_FADE` (0.6 s) ramping the friction up to `GROUND_FRICTION` while `accelerate` refills toward wish speed in the same tick (only while steering), so a carry you run out hands over at sprint instead of dumping you at walking speed (playtest; worst frame 2.15 -> 0.40 m/s, ending at 11.4 m/s). The landing roll steers through the same helper at `ROLL_TURN_RATE` (3.5). All six are `##` tunables. `check_carry_grip` drives a real pawn through every case; with the old `accelerate` back it turns 28° instead of 90°, with the fade removed it drops 2.15 m/s in one frame.

- #249: a landing roll cannot be cut by a jump any more. The dive -> tap space hop carried the whole `DIVE_MAX` (15 m/s) into the air, repeatable every `DIVE_COOLDOWN`, because the grounded jump branch runs before `Movement.tick_dive_roll` and never looked at `_diving`/`_roll_t`. The first `ROLL_JUMP_LOCK` (0.3 s) of a roll now refuses the jump and holds the press in the buffer instead of eating it, and a jump out of the roll drops the horizontal speed to `SPRINT_SPEED`; rolling the roll out still pays `ROLL_CARRY`, so finishing it is the reward. Slide-dive and wall jump are untouched. `check_dive_jump` drives a real pawn through slide -> dive -> roll and jumps at the landing frame, inside the lock and after it.

- v0.5.15 (released): pickup pads on all five maps (same three types). `NET_VERSION` 0.5.15 - a 0.5.14 client knows no pads outside Townhouses.

- v0.5.14 (released): map pickups on Townhouses (#144) — Extra Messen, Schildplaat, Herstelkern, server-authoritative with a late-joiner state sync and vitals sync for remote pawns; armour absorbs damage before HP. `NET_VERSION` 0.5.14.

- #144 pickups: three server-authoritative pads on every map now - Townhouses (Extra Messen x ±8, Herstelkern, Schildplaat on the west flank), Foundry, Rooftops, Quay and Skyline (their pads are listed in docs/MAPS.md). `shared/pickups.gd` holds the state `{id, type, pos, ready, timer}` and decides on the match authority; clients draw the same nodes from the same map data (`Maps.pickups(id)`), and `sync_pickup_taken` / `sync_pickup_state` carry the rest. Effects per spec: knives +2 capped at 3, armour 40 (never stacked, gone on death), heal +45 capped at 100, and a pickup does nothing (and stays) when it would do nothing. Armour absorbs damage in `Player.apply_hit` before HP and rides `broadcast_hurt` to the victim HUD. Visuals are procedural (`CrystalMesh.part(&"pickup_*")` + a real annulus from `ring_mesh`), the ring dims and an arc fills to respawn. No new audio asset: the take chime is the existing knife hit, pitched per type (#135 is still open). `check_pickups` covers the effects, the caps, armour absorption, touch and respawn; `check_pickup_pads` loads every map and asserts each pad stands on floor, has clearance, is 7 m or more from a spawn/base and is reachable on the navmesh. `NET_VERSION` 0.5.14.

- v0.5.13 (released): character facelift (limbs, crouch, reload animation), knife-throw and roll visible to every client and in the killcam, hit-confirm layers + combo ladder + UI limiter, perf-overlay vsync/GPU hint, renderer choice, Skyline spawn sightlines. `NET_VERSION` 0.5.13 (Skyline collision changed).

- #164 facelift: the crystal figure has real limbs and a real crouch. `BodyPose` now emits `arms` (shoulder shard -> hand on the gun) and `legs` (thigh + shin per side, 2 cm overlap at the knee), the hips stand at 0.80 m and fold to 0.40 m when crouched instead of the torso being squashed through them, and `CROUCH_LEAN` went 40 -> 68 deg so the torso goes near-horizontal under a head that drops 0.74 m. The reload is procedural and timed on the weapon's own `reload_time`: the viewmodel tilts, dips and pops at the mag swap (`Weapon.reload_anim()`, `_reload_dip`), the body takes the same progress through `pose_body(..., reload)`, and the killcam records it as snapshot field 9. Remote pawns show no reload yet: reload state is not synced (that would be a protocol change), so only the owner sees it. `check_crystal_body` and `check_reload_anim` cover the geometry and the timing.

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
