# Wapens in het spel zetten

Deze handleiding is voor artists die een wapen maken of vervangen: model, muzzle flash, animaties en
geluid. De code zoekt je bestanden zelf op aan de hand van hun naam. Je hoeft dus geen code aan te
passen en ook niet te vragen of iemand het "erin stopt". Voor kleur, materiaal en vorm blijft de
[art guide](index.html) leidend.

## Kort gezegd

1. Maak een map `assets/weapons/<id>/`, met als naam de id van het wapen (zie de tabel).
2. Zet daarin `<id>.tscn` (je scene) of alleen `<id>.glb` (alleen het model). Zet je geluiden er ook in:
   `fire.ogg`, `reload.ogg`, `draw.ogg` en `dry.ogg`.
3. Open `tools/weapon_lab.tscn` in Godot en druk op **F6**. Je staat dan in het spel met elk wapen in
   je hand. Staat er iets niet goed, dan zie je dat meteen in beeld.

Een startpunt staat klaar in `assets/weapons/_template/`. Kopieer die map en hernoem de map en de
scene naar de id van je wapen. Een map die met `_` begint, ziet het spel niet als wapen.

## De ids

| id | wapen | stijl van herladen (de code) |
|---|---|---|
| `rifle` | geweer | magazijn |
| `pistol` | pistool | magazijn |
| `shotgun` | shotgun | patronen een voor een |
| `sniper` | sniper | grendel |
| `smg` | SMG (staat al in een map: kijk daar hoe het eruitziet) | magazijn |
| `revolver` | revolver | cilinder |
| `lmg` | LMG | magazijn met klep |
| `slug` | slug shotgun | patronen een voor een |
| `knife` | werpmes, ook het mes van de Shank-class | geen |

Gebruik een andere mapnaam, dan meldt de check dat de map bij geen wapen hoort. Een **nieuw** wapen
(een id die er nog niet is) heeft ook schade, vuursnelheid en een plek in de classes nodig. Dat is
gameplay: vraag dat aan ons, dan zetten wij de id klaar. Daarna werkt het voor jou hetzelfde.

## Het model

- GLB, Y omhoog, in meters.
- De loop ligt langs **+X** en de monding wijst naar **+X**. De oorsprong ligt bij de greep. Het mes
  ligt met het lemmet langs +X.
- Houd de echte verhoudingen aan. De code schaalt het wapen zelf naar zijn lengte in beeld
  (pistool 0,30 m, SMG 0,40 m, geweer 0,42 m, shotgun 0,50 m, slug 0,54 m, sniper 0,58 m,
  LMG 0,62 m, mes 0,25 m) en zet het rechtsonder in beeld. Over schaal en positie hoef je dus niets
  te doen.
- Materiaal en kleur: zie de art guide (donker staal, één oranje accent, geen merknamen).

Heb je alleen een model zonder flash of animaties, dan is `<id>.glb` in de map genoeg. Het spel
gebruikt dan de standaard muzzle flash en de herlaadbeweging uit de code.

## De scene (`<id>.tscn`)

Bouw de scene zoals het voor jou handig is. De code zoekt alleen op deze **namen** en de rest laat
hij met rust:

```
revolver                (Node3D, de root; de naam maakt niet uit)
├── revolver            je model: de .glb erin gesleept, of losse meshes
├── Muzzle              Marker3D op het eind van de loop        ← verplicht
│   ├── sparks          GPUParticles3D / CPUParticles3D          } alles onder Muzzle
│   ├── flash_planes    MeshInstance3D / Sprite3D                } is de muzzle flash
│   └── light           OmniLight3D                              }
├── Sight               Marker3D boven op het vizier             ← optioneel
└── AnimationPlayer     clips "fire", "reload", "draw"           ← optioneel
```

**Muzzle.** Dit is een Marker3D (of een gewone Node3D) met precies de naam `Muzzle`. Zet hem op het
eind van de loop. Daar beginnen de kogelsporen, en alles eronder is de muzzle flash:

- **Particles** (GPU of CPU) starten bij elk schot opnieuw voor één burst. Of je ze als loop of als
  one-shot bouwt maakt niet uit, dat zet de code goed. Ze bewegen mee met het wapen.
- **Meshes, sprites en lichten** gaan bij elk schot even aan, zo lang als de `flash_time` van het
  wapen (ongeveer 0,05 s). In de editor mag je ze gewoon zichtbaar laten. Het spel zet ze uit tot er
  geschoten wordt.
- Zit er een **licht** in je flash, dan gebruikt het spel dat licht in plaats van het eigen licht.
  Zit er geen in, dan blijft het standaard flitslicht aan.
- Zonder Muzzle pakt het spel de voorkant van het model, maar de check meldt het. Bij de SMG heet de
  muzzle nog `muzzle_flash`. Die oude naam werkt ook.

De flash telt niet mee voor de grootte van het wapen. Een grote vlam onder Muzzle maakt het wapen
in beeld dus niet kleiner.

**Sight**, optioneel. Een Marker3D boven op het vizier. Bij richten (rechtermuisknop) komt dat punt
net onder het oog. Zonder Sight richt het wapen op een vaste hoogte.

**AnimationPlayer**, optioneel. De code kijkt naar drie clips:

| clip | wanneer | lengte |
|---|---|---|
| `fire` | elk schot | kort. Bij snelle wapens versnelt de code de clip, zodat elk schot één keer de hele clip speelt |
| `reload` | herladen (R) | de code rekt of krimpt hem tot de herlaadtijd van het wapen |
| `draw` | wapen pakken | zoals je hem maakt |

- De clip mag in een library zitten (`weapons/fire`). Een naam die eindigt op `_fire`, `_reload` of
  `_draw` werkt ook (zo heet die van de SMG `weapon_smg_fire`). `RESET` mag erbij staan.
- Clips worden nooit geloopt, ook als ze zo geëxporteerd zijn.
- Heeft een wapen een eigen `reload`-clip, dan laat de code zijn eigen herlaadbeweging weg: geen
  kantelen en geen los magazijn. Jouw clip beweegt dan het wapen. De zwevende linkerhand volgt
  nog wel de beweging van de code voor die herlaadstijl.
- Andere clips (bijvoorbeeld `idle`) doen niets, en de check meldt ze. Wil je er iets mee, vraag
  het ons.

Als de map ook textures, losse meshes, VFX-scenes of animatiebestanden bevat: laat ze gewoon in de
map staan. Alleen de scene en de geluiden worden op naam gezocht.

## Geluiden

| bestand | wanneer |
|---|---|
| `fire.ogg` | elk schot. Meerdere varianten (`fire_1.ogg`, `fire_2.ogg`, ...) mogen: per schot kiest het spel er een |
| `reload.ogg` | herladen. Het spel past de toonhoogte aan zodat het geluid binnen de herlaadtijd valt |
| `draw.ogg` | wapen pakken |
| `dry.ogg` | trekker overhalen met een leeg magazijn |

- `.ogg`, `.wav` en `.mp3` werken allemaal. Het liefst `.ogg`, dat houdt de repo klein.
- Lees op het begin van de naam: `fire_heavy.ogg` is een schot, `reload_full.wav` een reload,
  `equip.ogg` telt als draw, `empty.ogg` als dry. Een geluid met een andere naam meldt de check.
- Schoten in mono (ze klinken in 3D vanaf het wapen), met een piek rond −1 dBFS en een korte staart.
- Heeft een wapen geen eigen `fire.ogg`, dan houdt het zijn huidige geluid. Je kunt dus eerst alleen
  het model doen en het geluid later.

## Testen

**In de weapon lab.** Open `tools/weapon_lab.tscn` en druk op F6. Of vanaf de command line:
`./run.sh res://tools/weapon_lab.tscn`. Je staat in een lege Townhouses zonder bots, met elk wapen.
Je kunt niet doodgaan en de klok staat stil.

| toets | wat |
|---|---|
| 1–9, Q | wapen kiezen |
| linkermuisknop | schieten |
| R | herladen |
| F | mes gooien |
| L | alle wapenbestanden opnieuw inlezen (nadat je iets hebt opgeslagen) |

Rechts in beeld zie je per wapen uit welk bestand het komt: `map` (een map volgens deze handleiding)
of `oud` (een los bestand van vroeger). Onder ⚠ staat wat er niet klopt aan een map.

**De check.** `tools/run_checks.sh` draait bij elke push. Alleen jouw wapens checken kan ook:

```
godot --headless --path . res://tools/check_weapon_kits.tscn
```

Die controleert elke map:
- hoort de map bij een wapen-id;
- ligt het model langs +X;
- staat Muzzle aan de +X-kant;
- zijn de clip- en geluidsnamen bekend.

Faalt hij, dan staat erbij wat er mis is.

## Wat je niet hoeft te doen

De volgende dingen doet de code:
- schaal en positie in beeld;
- rekyl en het zwaaien van het wapen;
- kogelsporen, inslagen en hulzen;
- de zwevende handen;
- het wapen in de killcam (die gebruikt dezelfde scene, flash en geluiden).

Wil je de positie in beeld anders, of een wapen dat langer of korter in beeld staat? Zeg het ons,
dat zijn getallen in de code.

## Credits

Zet in de PR (of in een berichtje) wat van wie is en onder welke licentie. Wij zetten het dan in
`CREDITS.md` en `ASSETS.md`.
