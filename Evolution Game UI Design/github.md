repo: dannyckc/Lizard
branch: main

## Last sync
date: 2026-08-07T09:47:00Z

### Updated in this project
- Designed a monochrome UI language for the prototype (bone-white field, ink creature, hairline panels).
- Rebuilt the play HUD, control legend, species tabs and F1 tuning panel from `CreatureParams.SCHEMA` as documented in the README.
- Tuning rows mirror the README's SPINE / BODY / LIMBS / GAIT groups and the four shipped presets.

## Screen map
| Project screen | Repo files |
|---|---|
| Evolution HUD.dc.html | README.md (controls table, parameter schema, presets, gait/spine behaviour) |

## Notes
Only `README.md` and `.gitignore` are pushed to `main` — the Godot source (`scripts/`, `scenes/`) is not in the
repository yet, so the UI was designed against the README's documented schema rather than `CreatureParams.gd`.
Push the source to sync the tuning panel against the real schema rows.
