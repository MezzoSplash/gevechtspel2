# Credits

## Discord

Rich Presence uses [discord-rich-presence-godot](https://github.com/SlayHorizon/discord-rich-presence-godot) by SlayHorizon, MIT, in `addons/discord_rich_presence/`. On Linux without `nc` or `ncat`, that copy relays the local socket through `python3` instead.

## Sounds

All third-party sounds below are **CC0 1.0 (public domain)**. No attribution is required; we credit them anyway.
They were trimmed, mixed to mono, faded and normalized with `tools/build_sfx.py`.

| File in `assets/sounds/` | Source | Author | License |
| --- | --- | --- | --- |
| `rifle_fire.wav` | The Free Firearm Sound Library, *AR-15* `D_32P.wav` (near) | Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney | CC0 |
| `pistol_fire.wav` | The Free Firearm Sound Library, *Walther PPQ* `X_39P.wav` (near) | same | CC0 |
| `shotgun_fire.wav` | The Free Firearm Sound Library, *Benelli Nova* `O_21P.wav` (near), with a bass shelf, plus Kenney *Sci-fi Sounds* `lowFrequency_explosion_000.ogg` as tail rumble, a synthesized sub thump and noise crack (own work), saturated together | same + Kenney | CC0 |
| `sniper_fire.wav` | The Free Firearm Sound Library, *Tikka T3* `W_29P.wav` (near) | same | CC0 |
| `smg_fire.wav` | The Free Firearm Sound Library, *PPSh-41* `P_22P.wav` (near), short cut for the 1200 rpm loop | same | CC0 |
| `revolver_fire.wav` | The Free Firearm Sound Library, *Ruger Single Six* `S_11P.wav` (near) | same | CC0 |
| `knife_hit.wav` | Kenney *Impact Sounds* `impactMetal_light_002.ogg` + `impactWood_light_001.ogg` | Kenney | CC0 |
| `knife_throw.wav` | Synthesized in `tools/build_sfx.py` (band-passed noise whoosh with a spin flutter) | this project | CC0 |
| `step.wav`, `step_1.wav` … `step_4.wav` | Kenney *Impact Sounds* `footstep_concrete_000…004.ogg` | Kenney (kenney.nl) | CC0 |
| `hurt.wav` | Kenney *Impact Sounds* `impactPunch_medium_000.ogg` | Kenney | CC0 |
| `grenade_boom.wav` | Kenney *Sci-fi Sounds* `explosionCrunch_001.ogg` + `lowFrequency_explosion_000.ogg` | Kenney | CC0 |
| `melee_hit.wav` | Kenney *Impact Sounds* `impactPunch_heavy_001.ogg` + `impactPlate_light_002.ogg` | Kenney | CC0 |
| `trickshot.wav` | Kenney *Interface Sounds* `maximize_005.ogg` (rising sweep) + `confirmation_002.ogg` (chime, plus an octave-up copy), mixed and saturated in `tools/build_sfx.py` | Kenney | CC0 |
| `melee_swing.wav` | Synthesized in `tools/build_sfx.py` (band-passed noise whoosh) | this project | CC0 |
| `radar_friendly.wav`, `radar_enemy.wav` | "Friendly radar online." / "Enemy radar online." spoken by the [Piper](https://github.com/rhasspy/piper) TTS, voice `en_US-ljspeech-high`, then radio-filtered in `tools/build_sfx.py` | voice: Bryce Beattie, trained on the LJ Speech dataset (Keith Ito, Linda Johnson) | voice model MIT, training data public domain; we release the clips as CC0 |

- The Free Firearm Sound Library: <https://opengameart.org/content/the-free-firearm-sound-library> ("Prepared SFX Library")
- Kenney Impact Sounds: <https://kenney.nl/assets/impact-sounds>
- Kenney Sci-fi Sounds: <https://kenney.nl/assets/sci-fi-sounds>
- Kenney Interface Sounds: <https://kenney.nl/assets/interface-sounds>
- Piper voice `en_US-ljspeech-high`: <https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/ljspeech/high> (repository license MIT; model card: dataset license public domain)
- LJ Speech dataset: <https://keithito.com/LJ-Speech-Dataset/> (public domain)

## Icons and models

`assets/ui/icon_melee.svg`, `icon_smg.svg`, `icon_revolver.svg` and `icon_knife.svg` (kill feed) are drawn for this project, like the other `icon_*.svg` files.

The SMG, revolver and throwing-knife models (`assets/weapons/smg.tscn`, `revolver.tscn`, `knife.tscn`) are low-poly boxes and cylinders built for this project by `tools/build_lowpoly_weapons.py` (CC0).

The other files in `assets/sounds/` (hit, headshot, kill, empty click, land, slide, reload, the older announcer lines `radar_online` / `radar_standby` / `round_starting`, round music) are not from these packs; the gun clicks and ticks come from `tools/gen_sounds.py`.
