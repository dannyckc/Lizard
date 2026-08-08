repo: dannyckc/Lizard
branch: main

## Last sync
date: 2026-08-09T00:00:00Z

### Updated in this project
- Rebuilt `Anatomy HUD.dc.html` against the pushed anatomy stack (`BodyPlan.gd`, `TissueGrid.gd`, `AnatomyNetwork.gd`).
- Compact card in the tuning-panel idiom: upright creature, multi-select layer overlays, one vitals strip, no side rail.
- Five-layer depth stack with the real costs — skin 0.4, fat 0.5 × reserve × profile, muscle 5.5, bone 6.0 (yield 0.5), organ 2.0 — plus `BodyPlan.FAT_ALONG` / `FAT_MIDLINE` / `FAT_LIMB` / `FAT_FOOT` and the brain and heart cell blocks.
- Nerves and vessels are `AnatomyNetwork` rebuilt in the UI: same conduit tree, nerve root at HEAD with a shielded axial run, vessel root at THORAX unshielded, delivery propagated parent-first. Circulation pulses and nerve spikes are animated along each run and stop at the cut.

## Screen map
| Project screen | Repo files |
|---|---|
| Evolution HUD.dc.html | README.md (controls table, parameter schema, presets, gait/spine behaviour) |
| Anatomy HUD.dc.html | scripts/creature/BodyPlan.gd, scripts/creature/TissueGrid.gd, scripts/creature/AnatomyNetwork.gd, scripts/creature/BodyState.gd |

## Sync history
- 2026-08-08 — first anatomy tab, built from `TissueGrid.gd` + `AnatomyState.gd` before `BodyPlan.gd` was pushed.

## Notes
Bleed uses `BodyState.WOUND_BLEED` 0.055 and `VESSEL_BLEED` 0.34; cut-off regions use `AnatomyNetwork.CUTOFF` 0.05.
Damage in the card is a demo erosion (Intact / Skirmish / Mauled) applied with the same outside-in rule as
`TissueGrid.bite` — swap it for live `Creature.anatomy` state when the HUD is wired into the game.
