# UI restyle "crystal" — handoff

Owner: MezzoSplash. Language with the owner: Dutch. Code, comments and commit messages: follow the repo (mixed, mostly English comments).
This file is the brief; the mockups next to it are the target. Status: steps 1-5 merged (#292, #293, #295, #296); the Tab scoreboard, the round-end winner card / style king and the in-game class select follow it too (#312, #313). The death report, streak pips and combo timer followed in #314, so the HUD builds no flat boxes any more. Left open: the HP gem (#319).

## 1. What the owner wants

Restyle the **main menu, the pause ("drop down") menu, the settings menu and the HUD**. Leave the 3D assets alone.
It must make the chaos legible, make you want to go fast, and give energy. It must **not** look like a generic "gamer UI".

History, so you do not redo it:
- Round 1 (yellow/black, slanted italic type, neon accent): rejected as "AI slop". Do not build it. PR #290 tried it in the theme and was closed unmerged; ignore it.
- Round 2 (this brief): the owner picked the direction **"spelwereld-eigen"**: UI shapes derived from the game's own crystal bodies, and said the result "is already better". This is the one to build.

## 2. Design language (the rules)

The characters are faceted pale crystal shells with glowing team-colour seams and floating detached parts. The UI is made the same way.

1. **No rectangles.** Every piece is a *cut crystal*: a rectangle with 4 unequal chamfered corners (8 vertices). Different pieces use different cut sizes so it never reads as a template.
2. **Facets.** Each piece has flat facets: a fan of triangles from an interior point to every edge, each a little lighter or darker (deterministic from a seed). Faint 1 px light edges.
3. **The seam is the information.** One edge of a piece can carry a glowing line in a colour. It encodes meaning: team colour on score and kill feed, and on meters the lit length of the seam is the value (speed, ammo). A selected or active piece turns pale shell with dark text and a lit seam.
4. **Two materials only:** smoke glass (dark, translucent, `~#0F141B` at 0.6 alpha) and pale shell (`~#E8EEF4`). Seam colours: team blue `#408CF2`, team orange `#EB6138` (these are `Player.TEAM_COLORS`; the real values must keep following colour-blind settings, never hard-code them in HUD code), vis/ice `#BFF3FF` for neutral, red only for danger/leave.
5. **Floating.** HUD pieces are separate shards with gaps, not boxed panels.
6. **Type:** clean, upright, uppercase, wide tracking; weights light/medium/bold. No italic, no slanted boxes. Numbers big and tabular.
7. **Background of the mockups is a fake low-poly stand-in** for the untouched 3D scene. Ignore it.

Mockups (1920x1080), in `docs/ui-crystal/mockups/`:
`menu.png`, `pause.png`, `settings.png`, `hud.png`. Their sources (`*.html`, `crystal.js`, `crystal.css`) contain the exact shard algorithm in `crystal.js` (`poly()`, `shard()`): chamfer order `[tl, tr, br, bl]`, polygon `(tl,0) (w-tr,0) (w,tr) (w,h-br) (w-br,h) (bl,h) (0,h-bl) (0,tl)`, facet fan, seam on the `left`/`bottom`/`top`/`right` edge with a partial `lit` length. Open the html files in a browser to see them live.

Only real content is shown. The things in the mockups that **do not exist in the game yet** and are proposals: the speed meter, the wall-side edge light during a wallrun, the explanation card in settings. Everything else (weapons, tricks, streak names, settings rows) mirrors what is in the repo.

## 3. What is in the repo (verified, so you do not have to re-discover it)

- **Theme is generated.** `ui/menu_theme.tres` is produced by `tools/build_ui_theme.gd` (`godot --headless --path . --script res://tools/build_ui_theme.gd`). Never hand-edit the `.tres`; change the builder. Consumers: `scenes/menu.tscn`, `scenes/pause.tscn`, `scripts/settings_panel.gd` (loads it itself). Custom types: `PrimaryButton`, `MenuButtonBig`, `ChoiceChip`, `TitleLabel`, `HeroLabel`, `SectionLabel`, `HintLabel`, `MenuPanel`, `SettingRow`. All styles are `StyleBoxFlat` built by `_sb(...)`. Accent today is amber `Color(1.0, 0.72, 0.22)`.
- **HUD** (`scripts/hud.gd`, `scenes/hud.tscn`, helpers in `scripts/hud/`): the HP bar, weapon slots and streak slots are `ColorRect`s that already get a skin through `_skin(rect, radius)` and `_paint(rect, bg, accent, top)` (hud.gd ~lines 478-540, call sites ~485-490, 563-564, 727-738, 971). That is the one choke point for restyling HP, weapon slots and streak slots. `_style_bottom()` builds the grenade pill with a `StyleBoxFlat`. Streak pips (~888) and one cast at ~490 (`as StyleBoxFlat`) must be handled when the stylebox type changes.
- **Palette lives in `shared/hud_layout.gd`** (`ACCENT` gold, `PANEL`, `SLOT_IDLE`, `SLOT_ON`, trick/popup colours). `tools/check_hud_column.gd` reads the layout constants and the `.tscn`, so keep the geometry constants and node positions intact. Only the colours may change.
- `scripts/hud/combo_meter.gd` has its own `COLOR` gold. `scripts/hud/kill_feed.gd` builds plain `HBoxContainer` rows (no background), check before restructuring since `tools/check_*kill*` / HUD checks may read the rows.
- **Repo rules:** every `tools/check_*.tscn` is run by CI (`tools/run_checks.sh`) and must exit 0. `.uid` files are tracked: add the `.uid` for each new `.gd`. Bump `NET_VERSION` only for wire changes (this work has none). No Godot binary was available where this brief was written, so **nothing below has been run**.

## 4. Implementation plan

### 4.1 `CrystalStyle` (new, `shared/crystal_style.gd`, `class_name CrystalStyle extends StyleBox`)
A custom StyleBox that draws the shard. Override `func _draw(to_canvas_item: RID, rect: Rect2) -> void` and draw with `RenderingServer.canvas_item_add_polygon` / `canvas_item_add_line`. Fields: `fill: Color`, `pale: bool`, `seam_color: Color`, `seam_side` (enum NONE/LEFT/BOTTOM/TOP/RIGHT), `seam_lit: float` (0..1 of the edge), `cuts: Vector4` (tl,tr,br,bl px), `facet_strength: float`, `variant: int` (seed), `edge_alpha: float`. Keep these pure and static so they are testable without a renderer:
- `static func outline(rect, cuts) -> PackedVector2Array` (8 points; clamp each cut to `min(w,h)*0.45` and at least 1 px so no two points coincide).
- `static func facets(pts, rect, variant) -> Array` (fan from an interior point, `RandomNumberGenerator` seeded by `variant`, same sequence for the same variant).
- `static func seam_ends(pts, side, inset := 2.0) -> Array[Vector2]`.
Seam drawing: a faint full-length track, then a wider low-alpha glow line, then a 3 px core line, up to `seam_lit`. After changing fields at runtime call `emit_changed()` so controls redraw. Pass full-size colour arrays to `canvas_item_add_polygon` (one colour per point) to be safe.

**Unverified risk, test first:** the docs call `StyleBox` an "abstract base class". Scripts extending it with the `_draw` virtual is the intended way to make custom styleboxes, but check in the editor that `CrystalStyle.new()` works. If it does not, fall back to a `Control`-based `CrystalPanel` (same drawing code in `_draw()`) and give theme buttons a `CrystalPanel` child through a small helper.
Also unverified: whether a scripted `StyleBox` saves/loads cleanly inside a `.tres`. Because of that, the plan below installs the styles **from code at startup** instead of from the generated `.tres`.

### 4.2 `CrystalTheme` (new, `shared/crystal_theme.gd`)
`static func install()`: load `res://ui/menu_theme.tres` once, keep it in a `static var` (so the cached resource stays alive and every later `load` returns the same patched instance), replace its styleboxes with `CrystalStyle`s, recolour. Call it from `Game._ready()` (skip when `is_dedicated`). Mapping (keep the existing content margins from `build_ui_theme.gd`):
- `Button`/`OptionButton`: normal = smoke; hover/focus = lighter smoke + lit `LEFT` seam in vis colour; pressed/hover_pressed = pale shell (font already dark); disabled = faint smoke. `focus` = outline only (`fill.a = 0`, `facet_strength = 0`, brighter `edge_alpha`). `CheckBox` stays clear. `OptionButton` keeps its 30 px right margin.
- `PrimaryButton`: pale shell fill, dark text, seam on hover/focus.
- `MenuButtonBig`: normal = smoke (not transparent); hover/focus = pale shell + seam, set `font_hover_color`/`font_focus_color` to dark; different `cuts` per button via `variant` is a nice touch (set in the scenes or by index).
- `ChoiceChip`: normal smoke, hover seam, **pressed = pale shell** (selected), disabled faint.
- `MenuPanel`, `PanelContainer`, `SettingRow`: smoke with subtle facets, `MenuPanel` gets a short `TOP` seam.
- Recolour amber everywhere else to the vis colour: `SectionLabel`, `LineEdit` caret/selection/focus border, `HSlider` fill (fill glow colour `#BFF3FF`, highlight white), `PopupMenu` border/hover, scroll bar highlight. Slider look in the mockup: thin track, glowing fill, diamond-shaped grabber (optional, theme grabber icon).
- Fonts: same `FontVariation`s, only `spacing_glyph` up for wider tracking. No italic.
Also update `tools/build_ui_theme.gd` palette comments if you touch it, but do not regenerate the `.tres` expecting scripted styleboxes in it.

### 4.3 HUD
- `_skin()`: build the `Panel`'s `"panel"` stylebox as a `CrystalStyle` instead of `StyleBoxFlat` (the `radius` argument becomes unused). `_paint()`: set `fill = bg`, seam on `BOTTOM` when `accent.a > 0` with `seam_color = accent`, then `emit_changed()`. Remove the `as StyleBoxFlat` cast at ~490.
- Weapon slots: the held weapon becomes **pale shell** (set `pale`, `fill = shell`) with dark text/key label; idle slots smoke. Streak slots: ready/selected get a lit seam.
- HP: keep the bar (do not rebuild it as the mockup's gem unless time allows); fill colour healthy = ice `~(0.78, 0.93, 1.0)`, mid amber, low red; track = smoke. The gem in the mockup is optional polish.
- `HudLayout.ACCENT` → vis colour. Keep `TRICK` gold (rewards) unless the owner objects. `COMBO_METER.COLOR` → vis.
- **Speed meter (new, `scripts/hud/speed_meter.gd`, `class_name SpeedMeter`)**: bottom centre, horizontal speed in m/s (big number), state label (WALLRUN / DIVE / SLIDE / SURF, in that priority; `Player._wallrunning`, `_diving`, `_sliding`, `is_surfing()`), drawn on a `CrystalStyle` whose **bottom seam length is the speed** (full at `MAX_SPEED` 40 m/s, tick at `Player.SPRINT_SPEED` 11.4). Local live pawn only: hide when `_player` is null, `Game.killcam_active`, or `death_layer.visible`. Instantiate in `hud.gd _ready()` and update from `_process` (`p.velocity`). Static helpers `flat_speed(v)`, `fill_of(s)`, `state_of(p)` so a check can test them.
- Wallrun edge light (optional): when `_wallrunning`, a soft vertical glow on the wall's side of the screen.
- Kill feed (optional, last): wrap each row in a small `CrystalStyle` panel with the killer's team colour on the right seam. Look at the existing kill-feed check first.

### 4.4 Menus
Mostly free through 4.2. Then adjust layout where the mockups differ: wordmark (light "GEVECHT" + bold "SPEL" with a small crystal mark), unequal button widths, pause menu centred column with the score shards (blue / pale clock / orange) above it. Settings: tabs as joined shards (active = pale), rows with the seam-slider look, one-line hint footer. Keep every existing setting and its behaviour; only the look changes.

### 4.5 Check (CI)
Add `tools/check_crystal_style.gd/.tscn` (+ `.uid`): outline has 8 points inside the rect and handles `cuts = 0` and tiny rects; same variant gives identical facets and different variants differ; `seam_ends` for each side; `CrystalStyle.new()` can `draw()` onto a `CanvasItem` without error; after `CrystalTheme.install()` the theme's `Button/normal`, `MenuButtonBig/hover`, `PrimaryButton/normal` are `CrystalStyle` and `install()` is idempotent; `SpeedMeter.fill_of/state_of/flat_speed`. `tools/check_hud_column` must stay green. If the existing HUD checks read stylebox types, update them.

## 5. Order of work (small PRs, owner merges only when CI is green)
1. `CrystalStyle` + check; verify in the editor that it draws (this settles the risk in 4.1 early).
2. `CrystalTheme` + `Game._ready()` hook → menu, pause, settings change look. Screenshot with `tools/shot_*` style scripts if one fits, otherwise ask the owner for a screenshot.
3. HUD skin swap + palette + weapon slots.
4. Speed meter. Done: a row of the bottom stack above HP, not bottom-centre on its own (HP and weapons still live there until step 5 moves them).
5. Layout polish of the menu/pause/settings screens, kill feed, HP gem. Done except the HP gem (`scripts/ui/crystal_ui.gd`, `tools/check_crystal_layout`).

## 6. Definition of done
Side by side with `docs/ui-crystal/mockups/*.png` the in-game screens read as the same family: unequal cut shards, glowing seams, pale selected state, no amber, no rounded rectangles. All `tools/check_*` pass. No gameplay, networking or 3D asset changes.
