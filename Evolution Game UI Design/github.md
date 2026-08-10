repo: dannyckc/Lizard
branch: main

## Last sync
date: 2026-08-10T08:26:19Z

### Updated in this project
- New `Specimen HUD.dc.html`: the creature in 3D as a low-poly mesh, built off the pushed `AnatomyLattice.gd` — one tissue per cell (skin, fat, muscle, bone, organ, nerve, vessel), the lattice carved in canonical body space at a constant cell edge.
- The mesh is skinned from the lattice rather than authored: rings of rays leave the body axis and stop at the outermost cell still standing and still shown, so peeling a tissue drops the surface to the layer physically under it and a bite dents the surface into the crater it took.
- Damage is retained per cell — `gone` / `bitten` / cut faces mirror the ledger rule (outermost first, bone resists), craters expose raw tissue, and a ring the teeth cut through is sealed flat as a severed stump instead of a taper.
- Sagittal and cross sections draw the cut itself out of the lattice cells standing in the plane: spinal cord, vertebrae, aorta and heart read directly.
- Census panel quotes the lattice: cells standing and taken per tissue, density-weighted mass, volume in cell units.

## Screen map
| Project screen | Repo files |
|---|---|
| Evolution HUD.dc.html | README.md (controls table, parameter schema, presets, gait/spine behaviour) |
| Blood HUD.dc.html | scripts/world/BiteCue.gd (MARK / MARK_DEEP, bloom on fade), scripts/creature/BodyState.gd (WOUND_BLEED, VESSEL_BLEED, CLOT_THRESHOLD), scripts/world/ScentField.gd (BLOOD deposits) |
| Anatomy HUD.dc.html | scripts/creature/BodyPlan.gd, scripts/creature/TissueGrid.gd, scripts/creature/AnatomyNetwork.gd, scripts/creature/BodyState.gd |
| Specimen HUD.dc.html | scripts/creature/AnatomyLattice.gd (tissues, parts, layer shares, BURY, hull-is-skin rule, outside-in ranks, damage mirror), scripts/creature/BodyPlan.gd, scripts/creature/TissueGrid.gd |

## Sync history
- 2026-08-09 — Blood HUD from `BiteCue.gd` / `BodyState.gd`; Anatomy HUD rebuilt against `BodyPlan.gd`, `TissueGrid.gd`, `AnatomyNetwork.gd`.
- 2026-08-08 — first anatomy tab, built from `TissueGrid.gd` + `AnatomyState.gd` before `BodyPlan.gd` was pushed.

## Notes
The specimen's lattice is a UI-side port of `AnatomyLattice._carve_body` / `_carve_limb` at a coarser cell edge (6 / 7.5 / 10 px against the game's 2.5), with the pixel floors quoted as fractions of a cell so the composition holds at any resolution. Two deliberate HUD-side deviations from the current `BodyShape` profile, for silhouette only: a neck pinch ahead of the chest and a tapering tail beyond the torso.
Damage is still a demo erosion (Intact / Skirmish / Mauled) applied as bite spheres with the ledger's outside-in rule — swap it for live `Creature.anatomy` + `TissueGrid` state when the HUD is wired into the game.
