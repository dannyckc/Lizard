repo: dannyckc/Lizard
branch: main

## Last sync
date: 2026-08-10T22:57:00Z

### Updated in this project
- New `Body Plan Handoff.dc.html`: printable implementation handoff for the template body plan — authored CreatureParams schema (body), the BodyPlan lattice/skeleton, the Posture table + per-girdle articulation, the derived Footfall/Locomotion gait system with all constants, plus per-build spec sheets for the six PRESETS with their per-gait readouts.
- Copied `scripts/creature/CreatureParams.gd` into the project as reference source.

## Screen map
| Project screen | Repo files |
|---|---|
| Blood HUD.dc.html | scripts/world/BiteCue.gd (MARK / MARK_DEEP, bloom on fade), scripts/creature/BodyState.gd (WOUND_BLEED, VESSEL_BLEED, CLOT_THRESHOLD), scripts/world/ScentField.gd (BLOOD deposits) |
| Body Plan Handoff.dc.html | scripts/creature/CreatureParams.gd (schema + PRESETS), scripts/creature/BodyPlan.gd (lattice, skeleton, regions, organs, networks, fat), scripts/creature/Posture.gd (TABLE), scripts/creature/Locomotion.gd (constants + laws), scripts/creature/Footfall.gd (constants + describe()) |
| Gait HUD.dc.html | scripts/creature/Footfall.gd (girdle_lag / hind_split / fore_split, FROUDE_WALK, FROUDE_RUN, LAUNCH_MIN/FULL, lift limits, describe()), scripts/creature/Locomotion.gd (duty, duty_at, swing_time, BEARING_RATIO, bunch), scripts/creature/Posture.gd (TABLE tilt/joint/feet_down), scripts/creature/CreatureParams.gd (PRESETS — the six template creatures), scripts/creature/Creature.gd (STALK_SPEED, crouch) |

## Sync history
- 2026-08-10 (16:39) — Gait HUD from `Footfall.gd`, `Locomotion.gd`, `Posture.gd`, `CreatureParams.gd`; HUD panels trimmed to Blood + Gait.
- 2026-08-10 — Specimen HUD from `AnatomyLattice.gd`, `BodyPlan.gd`, `TissueGrid.gd`.
- 2026-08-09 — Blood HUD from `BiteCue.gd` / `BodyState.gd`; Anatomy HUD rebuilt against `BodyPlan.gd`, `TissueGrid.gd`, `AnatomyNetwork.gd`.
- 2026-08-08 — first anatomy tab, built from `TissueGrid.gd` + `AnatomyState.gd` before `BodyPlan.gd` was pushed.

## Notes
Gait panel numbers are read from the system, not invented: walk = lateral-sequence four-beat (caution pulls girdle_lag to 0.25); Lizard's run is a trot because sin(tilt 12°) starves `launch`; Elephant never crosses FROUDE_WALK so its run is an amble and its lay-low is nearly nothing (hind_fold_range 0.50); Cat and Cheetah collapse their splits into transverse/rotary gallops; T. rex and Kangaroo are bipedal purely by `BEARING_RATIO`, and the Kangaroo's hop is the same split collapse on two legs. The Kangaroo walk is drawn pentapedal (tail + arms as fifth limb) as a design recommendation — the sim currently does a plain alternating stride.
