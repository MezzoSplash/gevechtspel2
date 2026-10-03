# Credits

## Sounds

All third-party sounds below are **CC0 1.0 (public domain)**. No attribution is required; we credit them anyway.
They were trimmed, mixed to mono, faded and normalized with `tools/build_sfx.py`.

| File in `assets/sounds/` | Source | Author | License |
| --- | --- | --- | --- |
| `rifle_fire.wav` | The Free Firearm Sound Library, *AR-15* `D_32P.wav` (near) | Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney | CC0 |
| `pistol_fire.wav` | The Free Firearm Sound Library, *Walther PPQ* `X_39P.wav` (near) | same | CC0 |
| `shotgun_fire.wav` | The Free Firearm Sound Library, *Benelli Nova* `O_21P.wav` (near), with a bass shelf, plus Kenney *Sci-fi Sounds* `lowFrequency_explosion_000.ogg` as tail rumble, a synthesized sub thump and noise crack (own work), saturated together | same + Kenney | CC0 |
| `sniper_fire.wav` | The Free Firearm Sound Library, *Tikka T3* `W_29P.wav` (near) | same | CC0 |
| `step.wav`, `step_1.wav` … `step_4.wav` | Kenney *Impact Sounds* `footstep_concrete_000…004.ogg` | Kenney (kenney.nl) | CC0 |
| `hurt.wav` | Kenney *Impact Sounds* `impactPunch_medium_000.ogg` | Kenney | CC0 |
| `grenade_boom.wav` | Kenney *Sci-fi Sounds* `explosionCrunch_001.ogg` + `lowFrequency_explosion_000.ogg` | Kenney | CC0 |
| `melee_hit.wav` | Kenney *Impact Sounds* `impactPunch_heavy_001.ogg` + `impactPlate_light_002.ogg` | Kenney | CC0 |
| `melee_swing.wav` | Synthesized in `tools/build_sfx.py` (band-passed noise whoosh) | this project | CC0 |
| `radar_friendly.wav`, `radar_enemy.wav` | "Friendly radar online." / "Enemy radar online." spoken by the [Piper](https://github.com/rhasspy/piper) TTS, voice `en_US-ljspeech-high`, then radio-filtered in `tools/build_sfx.py` | voice: Bryce Beattie, trained on the LJ Speech dataset (Keith Ito, Linda Johnson) | voice model MIT, training data public domain; we release the clips as CC0 |

- The Free Firearm Sound Library: <https://opengameart.org/content/the-free-firearm-sound-library> ("Prepared SFX Library")
- Kenney Impact Sounds: <https://kenney.nl/assets/impact-sounds>
- Kenney Sci-fi Sounds: <https://kenney.nl/assets/sci-fi-sounds>
- Piper voice `en_US-ljspeech-high`: <https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/ljspeech/high> (repository license MIT; model card: dataset license public domain)
- LJ Speech dataset: <https://keithito.com/LJ-Speech-Dataset/> (public domain)

## Icons

`assets/ui/icon_melee.svg` (kill feed) is drawn for this project, like the other `icon_*.svg` files.

The other files in `assets/sounds/` (hit, headshot, kill, empty click, land, slide, reload, the older announcer lines `radar_online` / `radar_standby` / `round_starting`, round music) are not from these packs; the gun clicks and ticks come from `tools/gen_sounds.py`.
