# Spec: Snelheidseffecten (FOV kick, speed lines, cam roll/dip, wind, toggle)

Voor Hermes. Godot **4.7** / GDScript, repo `MezzoSplash/gevechtspel2` op commit van `main` (nu `46056b3` / v0.5.3).  
Kleine PRs, alleen mergen als de **eigen CI** van de PR groen is (`gh pr checks --watch`, dan `gh pr merge --merge --delete-branch`). Geen force-push. Geen `.claude/` in git. `##` doc comments op nieuwe/verplaatste functies en bestanden. **Geen netcode, geen `NET_VERSION`-bump.** Alleen de lokale speler.

Design (AGENTS.md): hectiek/chaos bewaren, movement fluid/floaty, noscope blijft viable. Dit is polish die snelheid *voelbaar* maakt, geen gameplay-nerf.

---

## Wat er al is (niet opnieuw uitvinden)

| Stuk | Waar | Gedrag nu |
|------|------|-----------|
| Hip FOV + ADS | `scripts/camera_feel.gd` (`CameraFeel`), `Game.fov`, `weapon.ads_fov` | `_base_fov()` = `ads_fov` als ADS, anders `hip_fov()` = `Game.fov`. `extra_fov` wordt erbij gesmooth met `FOV_RECOVER` (18). |
| Sprint/carry FOV | `Player._apply_carry_fov()` in `scripts/player.gd` (~L1209) | Bij ADS: `extra_fov = 0`. Anders: `SPRINT_FOV` (6) als `is_sprinting`, plus carry-lerp `CARRY_FOV_MIN..MAX` (4..8) terwijl `_carry_t > 0`. Cap `FOV_EXTRA_CAP` (10). Aangeroepen elk physics-frame (~L924). |
| Wallrun cam roll | `Player._tick_move_fx()` (~L1505) | Zet `camera.move_roll` naar `±WALLRUN_TILT` (0.16 rad) *away from wall* (`-sign(right·wall_n)`), gesmooth exp(-10Δt). Al lokaal via camera. |
| Dive/roll pitch | zelfde `_tick_move_fx` | Roll-flip / dive dip op `camera.move_pitch`. |
| Viewmodel land-dip | `Weapon._tick_sway()` in `scripts/weapon.gd` (~L223) | Gun dip bij landing; **camera zelf** niet. Geschaald met `Game.view_sway`. |
| Whoosh one-shot | `Player.WHOOSH` = `res://assets/sounds/whoosh.wav` (~0.22 s), `_whoosh` AudioStreamPlayer op local spawn; speelt in `Movement.begin_carry()` | Geen loop, geen wind-loop. |
| Overlay-patroon | `scripts/freeze_grade.gd` + `shaders/greyscale.gdshader`; aangemaakt in `Game` (~L1797) als child, `layer = 0` (onder HUD) | CanvasLayer + full-rect ColorRect + ShaderMaterial. |
| Settings persist | `shared/game_settings.gd` load/save `user://settings.cfg`; UI in `scripts/settings_panel.gd`; setters op `Game` (`set_reduce_shake`, …) | Bool-voorbeeld: `access/reduce_shake`. |
| Checks | `tools/check_*.gd` + `.tscn`; `tools/run_checks.sh` pikt automatisch `tools/check_*.tscn` op | Stijl: PASS/FAIL regels, `get_tree().quit(code)`. |

Node-pad camera: `Player` → `$Head/Camera3D` (`CameraFeel`). Scene: `scenes/player.tscn`.

---

## Doel (5 onderdelen)

1. **FOV kick** die schaalt met horizontale snelheid **vanaf** sprint (`SPRINT_SPEED` = 11.4), gesmooth (via bestaande `extra_fov` + `CameraFeel._process`).
2. **Speed lines** overlay (screen-space shader / CanvasLayer), fadet in bij hoge snelheid.
3. **Camera roll** tijdens wall run (bestaande tilt behouden/verfijnen) + **kleine camera-dip bij landing** geschaald met valsnelheid (nieuw, camera — niet alleen viewmodel).
4. **Wind-geluid** waarvan volume/pitch met snelheid meeschaalt (lokaal, loop).
5. Toggle **「Snelheidseffecten」** in settings, zelfde persist-patroon als andere settings. Default **aan**.

Alles **local player only** (`Player.is_local()`). Bots/remote/dedicated: geen overlay, geen wind, geen extra FOV-schrijven. ADS/noscope: **hip FOV-kick uit tijdens ADS** (`extra_fov = 0` zoals nu); ADS FOV blijft absoluut (~38 sniper). `Game.fov` blijft de hip-basis.

---

## Voorgestelde waarden (tunable constants)

Zet ze op `Player` (of een klein `scripts/speed_fx.gd` helper als `player.gd` te dik wordt — liever helper als je >~80 regels toevoegt).

```gdscript
## Speed FX (#TBD): FOV / lines / wind / land dip. Alleen local + Game.speed_fx.
const SPEED_FOV_REF := SPRINT_SPEED   # 11.4 — kick begint hier
const SPEED_FOV_FULL := CARRY_MAX     # 18.0 — max kick bij deze horiz snelheid
const SPEED_FOV_AT_SPRINT := 4.0      # graden extra_fov op precies sprint
const SPEED_FOV_MAX := 10.0           # graden extra_fov op SPEED_FOV_FULL
# Vervangt bij speed_fx=on de oude SPRINT_FOV (6) + carry FOV-stack; FOV_EXTRA_CAP mag 10 blijven
# of naar 12 als de kick te vroeg clipt — niet hoger, noscope-feel houden.

const SPEED_LINES_START := 12.0       # m/s horiz: lines beginnen zichtbaar
const SPEED_LINES_FULL := 16.5        # m/s: volle intensity
const SPEED_LINES_SMOOTH := 8.0       # exp smooth rate naar target intensity

const LAND_CAM_MIN_SPEED := 5.0       # m/s omlaag (|vy|) voor een dip
const LAND_CAM_DIP_MAX := 0.08        # rad max move_pitch dip (negatief = omlaag kijken)
const LAND_CAM_DIP_PER_MS := 0.012    # rad per m/s valsnelheid boven MIN
const LAND_CAM_RECOVER := 10.0        # exp recover rate terug naar 0 (naast bestaande move_fx pitch)

const WIND_START := 11.4              # m/s: wind hoorbaar
const WIND_FULL := 17.0
const WIND_VOL_DB_MIN := -28.0        # net hoorbaar
const WIND_VOL_DB_MAX := -8.0
const WIND_PITCH_MIN := 0.85
const WIND_PITCH_MAX := 1.25

# Wallrun: bestaande WALLRUN_TILT (0.16) laten; optioneel licht versterken naar 0.18
# als speed_fx aan is — niet omdraaien. Huidige richting is "away from wall" (#80); zo houden.
```

Smooth FOV-target elk frame (local, hip):

```text
t = clamp((hspeed - SPEED_FOV_REF) / (SPEED_FOV_FULL - SPEED_FOV_REF), 0, 1)
extra_target = lerpf(SPEED_FOV_AT_SPRINT, SPEED_FOV_MAX, t)   # als hspeed >= REF
             = 0                                               # als hspeed < REF
# optioneel: als is_sprinting en hspeed net onder REF door friction, toch SPEED_FOV_AT_SPRINT * 0.5
camera.extra_fov = minf(extra_target, FOV_EXTRA_CAP)   # CameraFeel lerpt zelf in _process
```

Bij `weapon.is_ads()`: altijd `extra_fov = 0` (zoals nu). Bij `not Game.speed_fx`: **oude** `_apply_carry_fov`-logica ongewijzigd houden (sprint binary + carry).

---

## Implementatie per onderdeel

### A. Setting `Game.speed_fx`

**Bestanden**

- `shared/game.gd`: `var speed_fx := true` naast `reduce_shake` / `view_sway` (~L247).
- `func set_speed_fx(on: bool) -> void:` → zet var, `save_settings()`. Geen display-apply nodig.
- `shared/game_settings.gd`:
  - `load_settings`: `g.speed_fx = bool(cfg.get_value("access", "speed_fx", true))` (of `"video"` — kies **access**, naast `reduce_shake`).
  - `save_settings`: `cfg.set_value("access", "speed_fx", g.speed_fx)`.
- `scripts/settings_panel.gd`:
  - Var `_speed_fx: CheckBox`.
  - In Access-tab (`_pages[5]`), onder/naast 「Less shake」: label **「Snelheidseffecten」** (of Engels 「Speed effects」 als de rest van die tab Engels is — huidige Access-labels zijn Engels: "Less shake", "Colourblind". Gebruik **「Speed effects」** in de UI om consistent te blijven; hint in hetzelfde idioom).
  - `refresh()`: `_speed_fx.set_pressed_no_signal(Game.speed_fx)`.
  - `toggled` → `Game.set_speed_fx(on)` als niet `_filling`.
  - Hint uitbreiden: *"Speed effects: FOV kick, speed lines, landing camera dip and wind when you move fast. Off keeps the old sprint FOV only."*

**Geen** `NET_VERSION`-wijziging. Geen RPC.

### B. FOV kick (uitbreiden `_apply_carry_fov`)

**Bestand:** `scripts/player.gd`

- Hernoem of wrap: houd publieke/aanroep `_apply_carry_fov()` (wordt al elke tick aangeroepen ~L924), inhoud:

```text
if not is_local() or camera == null or weapon == null: return
if weapon.is_ads():
    camera.extra_fov = 0.0
    return
if not Game.speed_fx:
    # bestaande sprint + carry logica (copy van huidige body)
    return
# nieuwe speed-scaled kick (zie formules hierboven)
```

- ADS / noscope: niet aanraken in `weapon.gd` / `CameraFeel._base_fov()`. Kick mag **nooit** `ads_fov` of `Game.fov` overschrijven — alleen `extra_fov`.
- `CameraFeel.add_kick` FOV-punch van recoil blijft onafhankelijk (tijdelijke `fov +=`, recovered naar `_base_fov()+extra_fov`).

### C. Speed lines overlay

**Nieuwe bestanden**

- `shaders/speed_lines.gdshader` — `shader_type canvas_item;` met `hint_screen_texture` of puur procedurele radial streaks (liever **procedureel**, geen screen read nodig: goedkoper, werkt headless-vriendelijker). Uniforms: `intensity` (0..1), eventueel `time`.
- `scripts/speed_lines.gd` — `class_name SpeedLines extends CanvasLayer`, spiegel `FreezeGrade`:
  - `layer = 0` (onder HUD).
  - ColorRect full-rect, `mouse_filter = IGNORE`, ShaderMaterial.
  - `func set_intensity(v: float) -> void` / smooth intern.
  - Dedicated server / menu: intensity 0, rect hidden.

**Hook**

- Instantiëren zoals FreezeGrade: in `Game` `_ready` (of waar `freeze_grade` wordt gemaakt ~L1797): `speed_lines = SpeedLines.new(); add_child(...)`.
- Of als child van de lokale player bij spawn — Game-child is simpeler (één instantie).
- Elke frame vanaf local player (in `_apply_carry_fov` / nieuwe `_tick_speed_fx(delta)` die je vanuit dezelfde physics-tick aanroept als FOV):

```text
hspeed = Vector2(velocity.x, velocity.z).length()
target = 0 if not Game.speed_fx or not is_local() or is_dead or weapon.is_ads() \
         else clamp((hspeed - SPEED_LINES_START) / (SPEED_LINES_FULL - SPEED_LINES_START), 0, 1)
Game.speed_lines.set_intensity_smooth(target, delta)  # of player schrijft direct
```

Visueel: subtiele witte/transparante radial lines vanuit centrum, niet UI-blokkerend, niet misselijkmakend. Intensity 1 mag nog steeds deels doorzichtig zijn (alpha ~0.35 max in shader).

### D. Camera roll (wall run) + landing dip

**Wall run:** bestaande code in `_tick_move_fx` laten. Niet omdraaien naar "toward wall" — huidige feel is #80 away-from-wall. Optioneel: als `Game.speed_fx`: `WALLRUN_TILT * 1.1`, anders ongewijzigd. Roll blijft ook bij speed_fx=off (gameplay-feel, geen "effect-toggle").

**Landing camera dip (nieuw):**

- In local physics: track `_fall_vy` = min(velocity.y, _fall_vy) terwijl `not is_on_floor()`; bij transitie air→floor (niet tijdens dive-roll flip):

```text
if Game.speed_fx and is_local() and camera and not (_roll_t > 0 or _diving):
    impact = -_fall_vy  # positief
    if impact >= LAND_CAM_MIN_SPEED:
        dip = minf((impact - LAND_CAM_MIN_SPEED) * LAND_CAM_DIP_PER_MS, LAND_CAM_DIP_MAX)
        _land_cam_pitch = -dip   # apart van move_pitch dive-flip
_fall_vy = 0 on floor after apply
```

- Apply in `_tick_move_fx`: na bestaande move_pitch-logica, **add** `_land_cam_pitch` op `camera.move_pitch` (of zet `camera.move_pitch += _land_cam_pitch` alleen in de else-tak die naar 0 lerpt), en recover `_land_cam_pitch` naar 0 met `LAND_CAM_RECOVER`.
- Niet stacken over de dive roll-flip (`_roll_t > 0`): dan skip land-dip.
- Viewmodel land-dip in `weapon.gd` blijft; die hangt aan `view_sway`, niet aan `speed_fx`.

Detectie landing: mirror weapon sway (`was air, now floor`) in player physics na `move_and_slide`, of hergebruik bestaande floor-edge in `Movement.tick_dive_roll` / player move — netjesste: klein blok in player na floor-check waar land_sfx al speelt voor dives; voor normale landings is er nu geen centrale hook — voeg `_tick_land_cam(delta)` toe naast `_tick_move_fx`.

### E. Wind sound

- Nieuwe local `AudioStreamPlayer` `_wind` (niet de one-shot `_whoosh` hergebruiken voor carry — die blijft one-shot in `begin_carry`).
- Asset:
  - **Eerste keuze:** als je een korte loop kunt maken, `assets/sounds/wind_loop.wav` (nieuw). Mag stil/placeholder (zachte noise), credit in `ASSETS.md` als GENERATE/VERIFY.
  - **Fallback zonder nieuw sample:** `whoosh.wav` met `loop_mode = LOOP_FORWARD` (of `AudioStreamWAV` loop begin/end) — klinkt herhalend; documenteer in PR dat een echte loop later beter is. Spec accepteert fallback.
- Bus: `"SFX"` (Effects-slider).
- Elk frame (local, speed_fx):

```text
t = clamp((hspeed - WIND_START) / (WIND_FULL - WIND_START), 0, 1)
if t <= 0 or dead or ads or not speed_fx:
    volume_db → -80 / stop of fade
else:
    if not playing: play()
    volume_db = lerpf(WIND_VOL_DB_MIN, WIND_VOL_DB_MAX, t)
    pitch_scale = lerpf(WIND_PITCH_MIN, WIND_PITCH_MAX, t)
```

- Mute volledig als `Game.speed_fx` uit, of bij pause/menu/rc_view/dead.

### F. Centrale tick (aanrader)

Voeg `Player._tick_speed_fx(delta)` toe (## doc), aangeroepen naast `_apply_carry_fov` / `_tick_move_fx` in de local physics-path (~L920+). Daarin: FOV-target, lines intensity, wind, land-cam recover. Houd `_apply_carry_fov` als FOV-deel of inline — één plek, local-guard bovenaan.

---

## Check: `tools/check_speed_fx`

Spiegel `check_floaty` / `check_settings`.

**Bestanden:** `tools/check_speed_fx.gd` + `tools/check_speed_fx.tscn` (scene = Node + script ext_resource, zoals floaty).  
`run_checks.sh` pikt hem automatisch op — **niet** aan SKIP/KNOWN_FAIL toevoegen.

**Asserts (headless, geen echte graphics nodig):**

1. Constants bestaan / sane ranges: `SPEED_FOV_AT_SPRINT < SPEED_FOV_MAX`, `SPEED_LINES_START < SPEED_LINES_FULL`, `LAND_CAM_DIP_MAX > 0`, `Player.SPRINT_SPEED == 11.4`.
2. Instantiate `player.tscn`, `set_physics_process(false)`, mark als local als nodig (of test pure helpers).
3. FOV helper (extraheer pure functie of static op `SpeedFx` / `Player`):
   - hspeed 0 → extra 0
   - hspeed == SPRINT_SPEED → ≈ `SPEED_FOV_AT_SPRINT`
   - hspeed == CARRY_MAX → ≈ `SPEED_FOV_MAX` (geclamped)
   - ADS path: force `extra_fov` 0 (roep `_apply_carry_fov` met gemockte ads of test dat ads-branch wint)
4. `Game.speed_fx = false` → oude sprint/carry pad: sprintend zonder carry → `extra_fov == SPRINT_FOV` (6).
5. Settings round-trip: `Game.speed_fx = false; save; speed_fx = true; load` → false; restore true. (Zelfde cfg-pad als `check_settings`.)
6. `SpeedLines` / shader preload pad bestaat (`load("res://shaders/speed_lines.gdshader")` ok).
7. Wind asset preload ok (`WHOOSH` of `wind_loop`).
8. Print `SPEED FX CHECK OK` / `FAILED` + exit code.

Voorbeeld-aanroep: `godot --headless --path . res://tools/check_speed_fx.tscn`.

---

## PR-splitsing (klein houden)

**PR 1 — feel + toggle + check** (`feat/speed-fx-core`)

- `Game.speed_fx` + load/save + settings checkbox
- FOV kick (uitgebreide `_apply_carry_fov`)
- Landing camera dip + eventuele wallrun tilt-tweeak
- `tools/check_speed_fx` (FOV + settings + constants; lines/shader asserts pas in PR2 of stub-preload skip)
- Geen shader/overlay nog nodig voor groen

**PR 2 — polish audiovisueel** (`feat/speed-fx-overlay`)

- `speed_lines.gdshader` + `SpeedLines` + Game hook
- Wind loop player
- Check uitbreiden met shader/wind preloads + intensity 0→1 mapping
- `ASSETS.md` regel voor wind asset indien nieuw

Beide: geen NET_VERSION, geen server binary, geen balance van `DIVE_BOOST` etc.

---

## Acceptance criteria

- [ ] Local sprint/surf/dive boven ~11.4: FOV wijdt soepel uit, terug bij afremmen; hip `Game.fov` blijft basis.
- [ ] Tijdens sniper/SMG ADS: geen speed-FOV, geen speed lines, wind stil (of sterk gedempt); noscope (hip) houdt kick.
- [ ] Wallrun: bestaande cam roll blijft; landing na flinke fall: korte cam dip, geen conflict met dive-roll flip.
- [ ] Speed lines alleen local, onder HUD, uit bij dood/menu/ADS/toggle off.
- [ ] Wind schaalt met snelheid; Effects-slider schaalt mee (SFX-bus); toggle off = stil.
- [ ] Settings 「Speed effects」 persist in `user://settings.cfg` (`access/speed_fx`); default true.
- [ ] Remote pawns / dedicated: geen extra nodes spam, geen errors.
- [ ] `tools/check_speed_fx` groen in CI; hele `tools/run_checks.sh` niet slechter dan main.
- [ ] PR merge **alleen** bij groene PR-CI. `##` docs op nieuwe API.
- [ ] Geen `NET_VERSION` change.

---

## Out of scope

- B1 polish, reload anim, UAV bots/score, CTF bugs, granaten→UAV.
- Net sync van effects, shake-reduce herwerken (mag wél `Game.shake_scale()` blijven gebruiken op wallroll zoals nu).
- Nieuwe movement speeds of dive nerf.

---

## Referentie-snippets (bestaand)

`CameraFeel` FOV compose (`scripts/camera_feel.gd`):

```gdscript
fov = lerpf(fov, _base_fov() + extra_fov, 1.0 - exp(-FOV_RECOVER * delta))
# _base_fov = ads_fov if ads else Game.fov
```

Huidige FOV-schrijver (`player.gd`):

```gdscript
func _apply_carry_fov() -> void:
	if weapon == null or camera == null:
		return
	if weapon.is_ads():
		camera.extra_fov = 0.0
		return
	var extra := SPRINT_FOV if is_sprinting else 0.0
	if _carry_t > 0.0:
		var speed := Vector2(velocity.x, velocity.z).length()
		extra += lerpf(CARRY_FOV_MIN, CARRY_FOV_MAX, clampf(speed / CARRY_MAX, 0.0, 1.0))
	camera.extra_fov = minf(extra, FOV_EXTRA_CAP)
```

Wallroll (`_tick_move_fx`):

```gdscript
roll_target = -signf(right.dot(_wall_n)) * WALLRUN_TILT * Game.shake_scale()
camera.move_roll = lerpf(camera.move_roll, roll_target, 1.0 - exp(-10.0 * delta))
```

FreezeGrade spawn (`game.gd` ~1797): `FreezeGrade.new()` → `add_child` op Game autoload.

---

## Klaar wanneer

PR1 + PR2 gemerged op groene CI, check OK, Gianni heeft in-game de hectiek/floaty feel bevestigd (FOV niet te wild, lines niet te druk). Daarna optioneel AGENTS.md 「Recent work」 regel — aparte micro-PR of meenemen in PR2.
