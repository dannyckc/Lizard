# Evolution — procedurally animated soft-body lizard

A playable top-down Godot 4 prototype. The creature has no rig, no skeleton and
no animation clips: the head is dragged around by player input and *everything
else* — spine curve, body silhouette, limb poses, footfalls — falls out of
positional constraints and inverse kinematics solved fresh every physics tick.

## Setup

Requires **Godot 4.2 or newer** (developed and verified on 4.7.1). No addons, no
build step, no external assets.

1. Open Godot, **Import** → pick `project.godot` in this folder.
2. Press **F5** (or run `scenes/Main.tscn`).

From the command line:

```sh
godot --path .            # run it
godot --path . --editor   # open the editor
```

### Controls

| | |
|---|---|
| `W` `A` `S` `D` / arrows | move and turn |
| hold left mouse | steer the head toward the cursor |
| `Shift` | sprint |
| `F1` | show/hide the tuning panel |
| `F2` | toggle debug draw |
| `R` | reset |
| mouse wheel | zoom |

Eating the amber pellets grows the creature; every system scales off a single
`size_scale`, so the body, limbs and stride all grow together.

## How it works

Five systems run in a strict one-way chain each tick. That ordering is the whole
reason the thing is stable without a global solver — nothing downstream can ever
invalidate something upstream.

```
input ──▶ head position ──▶ spine ──▶ body shape ──▶ limbs
```

| File | Responsibility |
|---|---|
| [MovementInput.gd](scripts/MovementInput.gd) | devices → an abstract `{throttle, turn, sprint}` command |
| [Creature.gd](scripts/creature/Creature.gd) | motion integration; drives the four systems below in order |
| [Constraints.gd](scripts/creature/Constraints.gd) | the two projection primitives everything is built from |
| [Spine.gd](scripts/creature/Spine.gd) | the particle chain and its relaxation solve |
| [BodyShape.gd](scripts/creature/BodyShape.gd) | outline, head, eyes, limb sockets, tail — all derived from the spine |
| [Fabrik.gd](scripts/creature/Fabrik.gd) | generic FABRIK chain solver |
| [Limb.gd](scripts/creature/Limb.gd) | one arm/leg: bones + step-cycle state |
| [Gait.gd](scripts/creature/Gait.gd) | where feet want to be, when they pick up, where they land |
| [CreatureView.gd](scripts/creature/CreatureView.gd) | all drawing, including the debug overlay |
| [CreatureParams.gd](scripts/creature/CreatureParams.gd) | every tunable number, plus the schema the UI is generated from |

### Constraint-solving order, and why

Inside [`Spine.step()`](scripts/creature/Spine.gd) each tick:

1. **Inertia.** Verlet integration gives body points momentum, so the body
   trails and whips instead of rigidly tracking the head.
2. **Undulation.** A travelling lateral wave is added *before* the solver, as a
   bounded offset (the difference from last tick's displacement, not a fresh
   push each tick — pushing repeatedly feeds the integrator a force it carries
   as momentum, and the chain resonates to several times the intended
   amplitude).
3. **Pin the head.** Point 0 is authoritative, placed directly from input.
4. **Relaxation.** Distance then angle, per joint, strictly front-to-back,
   repeated `constraint_iterations` times.

Step 4's ordering matters twice over. Only the *child* is ever moved, so
corrections flow away from the head and the head stays where input put it. And
the angle constraint corrects by *rotating the child about its parent*, which
preserves the length just fixed — so one pass settles both constraints for a
given joint rather than the two fighting each other.

`spine_stiffness` makes each pass remove only part of the error, which reads as
flexibility. The **last pass always runs at full strength**, because partial
correction on a long chain is only marginally stable — each joint re-injects
roughly as much error into its child as it removes, and a soft-only solve lets a
20-segment spine visibly stretch. A single full-strength sweep projects every
point exactly onto its parent's circle, so segment lengths come out exact no
matter how low stiffness is set.

For limbs, [`Fabrik.solve()`](scripts/creature/Fabrik.gd) alternates the same
circle projection from each end of the chain. The elbow/knee is seeded toward a
pole before solving — FABRIK stays on whichever side of the root→target axis it
starts on, so the seed is what stops joints popping between mirror solutions.

### Gait

Purely reactive, no timeline. Each foot has an ideal position derived from the
body's current pose; a planted foot stays nailed to the world until it drifts
further than `stride_distance` from that ideal, then arcs to a spot slightly
*ahead* and re-plants. Step frequency therefore falls out of speed for free, and
an idle creature is genuinely still.

Diagonal pairs (front-left + rear-right, front-right + rear-left) share a beat,
and a foot may never lift while the opposite diagonal is airborne — that is what
keeps two feet down at all times. Candidates are sorted **most-overdue-first**,
which is what keeps it fair: the gate only lets one pair through at a time, so
with a fixed order the same pair wins every contest and the other pair gets
dragged along the ground indefinitely.

## Tuning

Press `F1` for live sliders (generated from `CreatureParams.SCHEMA` — add a
property plus one schema row and it appears automatically). Four presets ship in
the panel: **Lizard**, **Gecko**, **Salamander**, **Komodo**.

The parameters worth reaching for first:

| Want | Change |
|---|---|
| Longer / snakier body | `segment_count`, `segment_length` |
| Floppier, more organic | `spine_damping` up, `spine_stiffness` down |
| Stop it bending too far | `max_bend_deg` down (hard limit; 15–25° reads best) |
| More / less body sway | `body_wave` (peak sway in px), `wave_frequency`, `wave_speed` |
| Silhouette | `head/chest/waist/hip/tail_tip_width`, `body_width` |
| Longer stride, fewer steps | `stride_distance` up |
| Snappier footfalls | `step_duration` down, `step_height` up |
| Sprawling vs. tucked legs | `stance_width`, `stance_reach`, `arm/leg_length` |
| Marching vs. loose legs | `diagonal_coupling` (1 = strict trot, 0 = independent) |

Three couplings are easy to trip over:

- **`body_wave` must stay well under `stride_distance`.** Sway wider than a
  stride makes the feet chase the wobble instead of the direction of travel; the
  legs on one diagonal end up permanently over threshold and starve the other
  pair.
- **Turn radius is `move_speed / turn_rate`, and wants to exceed body length**
  (`segment_count * segment_length`). Otherwise the creature carves a circle
  tighter than itself and coils into a hook. `turn_speed_falloff` is what buys
  this back: full turn rate at a standstill for pivoting on the spot, reduced at
  speed for wide arcs.
- **`stance_reach` should stay below ~0.85**, or the IK chain sits locked
  straight and the legs stop looking like legs.

`constraint_iterations` and `fabrik_iterations` are cost/quality dials; the
defaults (6 and 6) are already past the point of visible improvement.

## Tests

Two headless checks, both worth re-running after retuning:

```sh
godot --headless --path . --script tests/SimTest.gd      # simulation invariants
godot --headless --path . --script tests/RenderSmoke.gd  # every draw path
```

`SimTest` drives each preset through idle → walk → turn → pivot → idle and
asserts that segment lengths hold, bends stay inside the limit, IK bones keep
their length, the gait never lifts both diagonals at once, a resting creature's
feet don't creep, and every schema row round-trips through `Object.set()`.

## Known limitations

Deliberate, in the interest of a stable and readable prototype:

- No collision, no terrain, no physical ground contact — "lift" is faked as a
  screen-space offset plus a shadow gap, since top-down has no vertical axis.
- Feet are placed kinematically; they don't push the body. The body leads and
  the legs follow, not the other way round.
- The body fill is drawn as a strip of quads between spine cross-sections, so a
  very sharp bend can overlap slightly on the inside of the curve. It is
  invisible at opaque fill and avoids depending on concave polygon
  triangulation.
