repo: dannyckc/Lizard
branch: main

## Last sync
date: 2026-08-14T13:50:00Z

### Updated in this project
- New `Physics HUD.dc.html`: live physics/debug HUD for the v2 locomotion loop — sagittal + plan panes over one simulation (Impetus demand/delivery, Footwork anchors/drift/landing prediction, Rhythm seats, Poise support polygon + COM plumb, Keel roll/righting), a footfall/delivery/poise timeline, nine scenarios and a TELLS panel that flags where the motion reads stiff.
- Copied `docs/V2_DESIGN.md` into the project as the reference source for v2 (the `scripts/creature*/` GDScript is no longer in the repo tree).

## Screen map
| Project screen | Repo files |
|---|---|
| Blood HUD.dc.html | scripts/world/BiteCue.gd (MARK / MARK_DEEP, bloom on fade), scripts/creature/BodyState.gd (WOUND_BLEED, VESSEL_BLEED, CLOT_THRESHOLD), scripts/world/ScentField.gd (BLOOD deposits) |
| Body Plan Handoff.dc.html | scripts/creature/CreatureParams.gd (schema + PRESETS), scripts/creature/BodyPlan.gd (lattice, skeleton, regions, organs, networks, fat), scripts/creature/Posture.gd (TABLE), scripts/creature/Locomotion.gd (constants + laws), scripts/creature/Footfall.gd (constants + describe()) |
| Gait HUD.dc.html | scripts/creature/Footfall.gd, scripts/creature/Locomotion.gd, scripts/creature/Posture.gd, scripts/creature/CreatureParams.gd (PRESETS), scripts/creature/Creature.gd (STALK_SPEED, crouch) |
| Physics HUD.dc.html | docs/V2_DESIGN.md — §4.1 2.5D Z channel, §4.1a `motion/Keel.gd` (roll, ground axis, girdle-clamped righting), §4.2 armature graph (trunk 8 / neck 4+head / tail 6 / limbs 4, socket at withers−1 and pelvis), §7.2 `Poise.gd` (posed COM, support polygon), Phase 3 loop (`Travel`, `Impetus` demand/push, `Footwork` anchors/drift/tear-off, `Rhythm` company + beat_coupling, `Outlook` headroom/rise_ahead/reach_along, the balance review), MotionProbe gate numbers (518 px/s² at power 1.000, 163 px/s sprint, feet-down 3.67/2.87/2.28, 90 °/s turn, ledge +10 anticipated, 60 px brink balked, 300 px/s shove) |

## Sync history
- 2026-08-10 (22:57) — Body Plan Handoff from `CreatureParams.gd`, `BodyPlan.gd`, `Posture.gd`, `Locomotion.gd`, `Footfall.gd`.
- 2026-08-10 (16:39) — Gait HUD from `Footfall.gd`, `Locomotion.gd`, `Posture.gd`, `CreatureParams.gd`; HUD panels trimmed to Blood + Gait.
- 2026-08-10 — Specimen HUD from `AnatomyLattice.gd`, `BodyPlan.gd`, `TissueGrid.gd`.
- 2026-08-09 — Blood HUD from `BiteCue.gd` / `BodyState.gd`; Anatomy HUD rebuilt against `BodyPlan.gd`, `TissueGrid.gd`, `AnatomyNetwork.gd`.
- 2026-08-08 — first anatomy tab, built from `TissueGrid.gd` + `AnatomyState.gd` before `BodyPlan.gd` was pushed.

## Notes
Gait HUD numbers come from the v1 gait player (patterns, duty tables). The Physics HUD is deliberately the other thing: v2's locomotion is a control loop, so the HUD shows demand vs. delivery, drift vs. step trigger, seats granted by Rhythm, and the weight measured against the feet — no duty table anywhere. Where the doc pins a number it is used verbatim (push 518 px/s², sprint 163 px/s, turn 90 °/s, response 0.12 s); everything else (stride length, feet down, duty) is emergent and reported rather than authored, so the HUD's own reference cat can be compared against MotionProbe's figures.

The reference model in the HUD is not the game's solver — it is a legible restatement of it (plan-dominant chain by eased stick angles, girdle heights from the planted anchors' own geometry, 2-bone IK per limb). Its `window.__physicsHud` handle exposes the live loop state for console probing.
