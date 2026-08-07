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
| move mouse | aim the head toward the cursor |
| left click | bite (anatomical hit + cooldown) |
| `Shift` | sprint |
| `F1` | show/hide the tuning panel |
| `F2` | toggle debug draw |
| `R` | reset |
| mouse wheel | zoom |

Eating the amber pellets counts toward `food_eaten` and nothing else for now —
growth has been taken out until there is a real system for it. `size_scale` is
still threaded through every system, pinned at 1.0, as the single value that
system will drive when it lands.

A stationary second creature starts ahead of the player as the first combat
slice. A click throws the head forward in a lunge and the bite resolves at full
extension, eating into a lattice of body cells layered skin over muscle over
bone. Tissue that comes off falls into the world as meat and can be eaten.
Bodies are solid, so the two creatures can be walked into rather than through.

## How it works

Five systems run in a strict one-way chain each tick. That ordering is the whole
reason the thing is stable without a global solver — nothing downstream can ever
invalidate something upstream.

```
input ──▶ head position ──▶ contacts ──▶ spine ──▶ body shape ──▶ limbs
```

| File | Responsibility |
|---|---|
| [MovementInput.gd](scripts/MovementInput.gd) | devices → an abstract `{throttle, turn, sprint}` command |
| [Creature.gd](scripts/creature/Creature.gd) | motion integration and body-vs-body contacts; drives the four systems below in order |
| [Constraints.gd](scripts/creature/Constraints.gd) | the two projection primitives everything is built from |
| [Spine.gd](scripts/creature/Spine.gd) | the particle chain and its relaxation solve |
| [BodyShape.gd](scripts/creature/BodyShape.gd) | outline, head, eyes, limb sockets, tail — all derived from the spine |
| [AnatomyState.gd](scripts/creature/AnatomyState.gd) | anatomical hit-testing — which creature, and which structure of it |
| [TissueGrid.gd](scripts/creature/TissueGrid.gd) | the body-space cell lattice: skin over muscle over bone, and what a bite does to it |
| [ScrapField.gd](scripts/world/ScrapField.gd) | tissue knocked loose, as meat lying in the world |
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
   bounded offset — the difference from last tick's displacement, not a fresh
   push each tick.
3. **Pin the head.** Point 0 is authoritative, placed directly from input.
4. **Relaxation.** Distance then angle, per joint, strictly front-to-back,
   repeated `constraint_iterations` times.

Step 2 shifts `prev` by the same delta as `points`, and that is the load-bearing
detail. Verlet reads velocity as `points - prev`, so moving only `points` hands
the integrator the wave's per-tick displacement as though it were real motion;
it carries that forward at `spine_damping` and re-injects it next tick. The
chain resonates, and because a free end has nothing but its own parent
restraining it the energy pools in the tail, which whips at *tens* of times the
intended amplitude even though the envelope holds the wave itself to zero there.
On defaults that measured 116 px of sway from a `body_wave` of 6 — wider than a
whole stride, which is precisely the coupling hazard described under Tuning
below, triggered by the engine rather than by anyone's settings. Shifting both
leaves the implied velocity untouched, so the wave is pure displacement and only
the constraint solver ever feeds the integrator.

Sway still runs somewhat above `body_wave` — up to about 3x — because each
point inherits its parent's lateral offset as well as its own, and that
accumulates down a head-pinned chain. That part is bounded and stable; it is the
shape of the wave, not a feedback loop.

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
circle projection from each end of the chain. FABRIK stays on whichever side of
the root→target axis it starts on, so the seeded elbow/knee position is what
stops joints popping between mirror solutions. For two bones that position is
just where the circles around each end meet, so it is seeded there *exactly*
rather than nudged toward an approximate pole. That matters because of where the
reach limit below leaves the foot: hard against the limit, chain nearly straight
— and near-straight is exactly where FABRIK crawls. From a partial seed, six
passes get the joint about seven eighths of the way out and leave the foot
overshooting its target, which reads as the leg locking out rigid precisely when
the creature is working hardest.

### Bodies are solid

Creatures collide with each other, against the same chain of variable-radius
capsules the view fills — so what you cannot walk through is exactly what is
drawn. Limbs are excluded: legs here are kinematic, they neither carry weight
nor receive it, and colliding them would only jam two creatures apart at arm's
length while their bodies still read as clear.

Two decisions make it fit the one-way tick chain rather than fight it:

- **Each creature resolves its own half of every contact and never writes to
  another's state.** Both parties run the same pass, so a half each separates
  them exactly once and the result cannot depend on the order the group is
  ticked in. The bodies tested against are the ones solved last tick — a few
  pixels of staleness at 60 Hz, and a positional correction is iterative anyway.
- **Corrections are applied between the motion integration and the spine
  solve**, so the silhouette, the limbs and the tissue lattice are all built
  from the corrected pose within the same tick instead of a tick behind it. A
  push on the head moves `head_pos`; a push on a body point shifts `points` and
  `prev` together, which keeps it pure displacement for exactly the Verlet
  reason the undulation does the same.

Position alone is not enough, and the difference is not subtle. Corrected only
positionally, a creature walking into another keeps walking: measured, it shoved
a stationary creature 800 px across the world ahead of it at its own full speed,
with no resistance at all — the correction simply could not outrun the
throttle. So a contact also sheds the part of `speed` that is driving into it,
scaled by how squarely it opposes travel. Head-on that stops the creature dead;
along a flank it is nearly zero, so bodies slide past each other freely. Heading
is deliberately untouched, so a creature pressed against another can always turn
away and leave.

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

#### Every limb keeps its own clock

Stride length, step duration and how far ahead a foot aims are all sized off how
fast *that limb's socket* is travelling, not off the body's linear speed. The
two are not interchangeable: in a turn the hips sweep a far wider arc than the
shoulders, and in a pivot on the spot the body's linear speed is zero while the
hips are moving as fast as they ever do. Sized off one shared speed the rear
legs take short, slow steps while their sockets race away, so they sit
permanently over threshold and get towed — which reads as the creature swinging
about its planted front feet.

Two things follow from using the socket's own velocity:

- **A foot lands where its socket *will* be.** Aiming at the present ideal
  guarantees the foot is already overdue on touchdown and spends its whole
  stance being dragged. The landing spot leads by `socket_vel × flight time`,
  plus a stride fraction as the margin it then has to be dragged back through.
- **A fast socket gets a quick step.** Step duration is capped at
  `stride / socket_speed` — the time the socket takes to run a full stride away.
  A step slower than that can never catch up.

#### Feet cannot leave the working envelope

Feet are placed in world space and the body then walks out from under them, so
nothing in the reactive rule above stops one ending up behind the far shoulder —
and FABRIK will happily solve to it, drawing the leg through the torso. Every
foot is therefore projected into the region its limb can actually reach, and a
foot the body has outrun **skids along that boundary** rather than staying
nailed down and dislocating the leg. Four limits, the angular three applied
weakest-first so the hard anatomical ones always win:

| Limit | Why |
|---|---|
| `limb_max_reach` from the socket | past it the chain is pulled straight and stops reading as a leg |
| `limb_swing_deg` either side of the rest stance | taste: how wide a fan the leg sweeps |
| 78° either side of straight-out | a foot may never come round to the body's midline |
| the bearing at which the knee turns inboard | see below |

The last one is easy to miss. Given the socket, the foot and two fixed bones
there are only *two* possible knee positions, so once the foot is placed the
knee cannot be moved out of the way — it has to be prevented by limiting the
foot. The joint folds toward `bend_sign`, and as the foot swings that same way
the two converge until the knee's outward offset passes through zero and the leg
buckles into the body. Before this limit existed, knees sat up to 0.23
limb-lengths *inside* the torso.

All of it is computed in the socket's own (outward, forward) frame, so the
limits mean the same thing on both flanks and at any heading.

### Tissue

Damage lives in a lattice of body cells — 26 x 7 over the body, 8 x 3 per limb
— and each cell is a stack of three tissues in *depth*, because top-down means
you are looking down through them: skin over muscle over bone. A bite spends a
penetration budget strictly outside-in, so nothing under a layer can be touched
until that layer is gone, and the colour of a cell is simply whatever is now
uppermost in it. Each layer also darkens toward the one beneath as it thins, so
a bite that has not broken through still shows how far it got.

Skin is a rind and muscle is where the fight is: at the default `bite_damage`
one bite strips skin across nearly the full width of the jaws, three tear
through the muscle under the middle of them, and seven get through bone. So a
bite always *opens* the body, and a kill is always either repeated bites or a
deeper one.

#### The skeleton is a frame

Bone is not just thicker, and it does not lie under the whole body. It exists
only where there is an actual skeleton, laid out in body space:

```
......#.......#...........   ← only the girdles reach the flank
####..#.#.#.#.#...........
####..#.#.#.#.#...........
##########################   ← vertebrae, one cell wide, snout to tail tip
####..#.#.#.#.#...........
####..#.#.#.#.#...........
......#.......#...........
^--^  ^-------^  ^-------^
skull  ribcage   loin + tail
```

A skull filling the head cap but not the cheeks; a vertebral column one cell
wide running the whole length; a full-width girdle under each pair of limb
sockets; three ribs between them on alternating columns; a core down each limb.
That is 36% of the body's cells, and the sparseness is the point. Bone yields at
half the incoming depth and then *stops the bite*, since there is nothing behind
it to reach — so wherever it runs, a wound bottoms out on a pale bar, and
wherever it does not, flesh is all there is and eating through it **opens a hole
clean to the ground**. Both states have to exist for either to read: if bone sat
under most of the body every wound would end on the same surface and you could
not tell a skeleton from a hole. The alternation is what makes the ribcage a
cage rather than a shell — a bite landing between two ribs reaches the muscle
they do not cover, and one landing on a rib does not.

The layout is fixed in body space for the same reason the grid dimensions are:
it has to name the same cells after the tuning panel has restructured the spine
underneath it. The girdle columns therefore mirror the *default* `front_limb_t`
and `rear_limb_t` rather than tracking them live.

Two decisions carry the rest of it:

- **Cells are addressed in body space, and the lattice's dimensions are
  constants.** The pose is rebuilt from the spine every tick, so world-space
  damage is impossible; only the cell *corners* are re-derived each tick. Making
  the dimensions constants rather than functions of `segment_count` is what
  stops the tuning panel silently remapping existing damage when it restructures
  the spine underneath it.
- **A bite selects cells by testing their solved world centres.** The body-space
  mapping is curved, tapered and per-tick, and has no cheap inverse; the direct
  test is exact, needs no special case at the snout cap or the elbow, and lets
  one bite straddle several structures — jaws closing on a flank catch the leg
  over it, which a query routed through a single hit region could not express.

Destroyed skin and muscle come off as chunks, which fly, settle, and stay as
meat until something eats them. A creature never eats its own: without that
rule, jaws closing on a victim's head shed straight into the victim's own mouth
volume, and being bitten feeds you.

#### Keeping it cheap

Per tick the lattice only re-derives cross-sections — about sixty for a whole
creature — and everything priced per *cell* is deferred to the rare ticks a bite
lands on. Intact skin is already on screen as the body fill, so the lattice
draws purely as an overlay of what has been lost: cost tracks the damage, not
the ~180 cells, and an untouched creature costs one early return per patch.

The cells that do draw, and the loose chunks, go out as single indexed triangle
arrays rather than a polygon apiece. That one is worth stating with numbers,
because it is not a micro-optimisation: Godot issues one canvas command per
`draw_colored_polygon`, and a badly chewed pair of creatures with a saturated
scrap field reaches a few hundred a frame. Measured in a 1280x760 window, that
alone cost **5.5 ms/frame** and took the scene from 120 to 72 fps. Batched, the
same worst case costs **0.29 ms** — under 2% of a 60 fps budget, a 19x
reduction. The interior cell seams are one `draw_multiline` for the same reason.

### The lunge

A click does not resolve a bite. It starts an animation with a hit frame: a
0.07 s wind-up that rocks the head back and opens the jaws, a 0.08 s throw, and
a 0.18 s settle — and the bite resolves at full extension, against the pose the
jaws actually arrived at. The gape snaps shut on that same frame, so the
animation states exactly when the damage happened.

The throw is fed to **the spine's head point, not to `head_pos`**. That is the
load-bearing detail, twice over. The body has to follow it through the
constraint solve — that is what makes it whip rather than slide — and it must
never accumulate into the motion integrator, or every strike would walk the
creature forward by its own reach. `head_pos` stays the creature's honest
position throughout, which is also what keeps the camera still while the body
lunges.

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
| More / less body sway | `body_wave`, `wave_frequency`, `wave_speed` |
| Silhouette | `head/chest/waist/hip/tail_tip_width`, `body_width` |
| Longer stride, fewer steps | `stride_distance` up |
| Snappier footfalls | `step_duration` down, `step_height` up |
| Sprawling vs. tucked legs | `stance_width`, `stance_reach`, `arm/leg_length` |
| Marching vs. loose legs | `diagonal_coupling` (1 = strict trot, 0 = independent) |
| Wider / tighter leg sweep | `limb_swing_deg`, `limb_max_reach` |
| Bites that bite deeper | `bite_damage` up (hit points of penetration: skin is 0.4, muscle 5.5, bone 6.0 at half rate) |
| Crisper, more legible wounds | `bite_radius` down |

Four couplings are easy to trip over:

- **`body_wave` must stay well under `stride_distance`.** Sway wider than a
  stride makes the feet chase the wobble instead of the direction of travel; the
  legs on one diagonal end up permanently over threshold and starve the other
  pair. Budget for peak sway landing a little under 3x `body_wave`, for the
  accumulation reason described above.
- **Turn radius is `move_speed / turn_rate`, and wants to exceed body length**
  (`segment_count * segment_length`). Otherwise the creature carves a circle
  tighter than itself and coils into a hook. `turn_speed_falloff` is what buys
  this back: full turn rate at a standstill for pivoting on the spot, reduced at
  speed for wide arcs.
- **`stance_reach` should stay below ~0.85**, or the IK chain sits locked
  straight and the legs stop looking like legs. Keep it below `limb_max_reach`
  too, or the rest pose is already against the envelope boundary.
- **`turn_pivot` places the turn centre**, measured back from the head. At the
  defaults it lands close to the shoulder station, so a spot pivot rotates the
  creature roughly about its front feet and the hips sweep the wide arc. The
  gait copes with that now, but moving the pivot back toward the midpoint of the
  two limb girdles turns it about its centre instead, which is both what a real
  quadruped does and much less work for the hind legs.

`constraint_iterations` and `fabrik_iterations` are cost/quality dials; the
defaults (6 and 6) are already past the point of visible improvement.

## Tests

Four headless checks cover simulation, rendering, UI and combat:

```sh
godot --headless --path . --script tests/SimTest.gd      # simulation invariants
godot --headless --path . --script tests/RenderSmoke.gd  # every draw path
godot --headless --path . --script tests/UIInteractionTest.gd # HUD interactions
godot --headless --path . --script tests/CombatTest.gd    # bite/anatomy slice
```

`CombatTest` covers the tissue rules that are easy to regress: bites eat
outside-in and never touch a layer through an intact one; they damage only where
they land; bone survives several times longer than the flesh beside it; damage
outlives both a procedural rebuild *and* a change of segment count; and the
lunge extends, resolves at its apex, snaps its jaws shut, and leaves the
creature standing exactly where it started.

It also asserts the skeleton is still a *frame* — bone under less than half the
body, at least three free-standing crossbars over the torso with flesh either
side, nothing but vertebrae behind the hips — and that flesh with no bone under
it is eaten clean through rather than bottoming out. Those are shape claims, not
totals, so they catch a skeleton that has quietly spread into a plate.

And it covers contacts: a creature driven at another for four seconds at full
throttle ends up stopped against it rather than through it and with its speed
collapsed; two creatures started deeply inside each other separate without
either spine stretching; and a creature with nobody near it is not displaced at
all. Each fails loudly if the contact pass is removed.

`SimTest` drives each preset through idle → walk → turn → pivot → idle and
asserts that segment lengths hold, bends stay inside the limit, IK bones keep
their length, the gait never lifts both diagonals at once, a resting creature's
feet don't creep, and every schema row round-trips through `Object.set()`.

It also checks the grounding invariants, which is where the interesting failures
live. No part of a limb may end up inboard of its own socket (a leg drawn
through the torso); no foot may exceed `limb_max_reach` (a leg pulled straight);
no foot may fall more than 3.5 strides behind its ideal (a leg being towed
rather than walked); and straight-line sway must stay within 5x `body_wave` (the
spine resonating). Each one catches a distinct failure the others let through —
the limb envelope holds even while the spine is resonating, so the sway check is
the only thing that sees that cause.

## Known limitations

Deliberate, in the interest of a stable and readable prototype:

- Creatures collide with each other, but nothing else does: no terrain, no
  physical ground contact — "lift" is faked as a screen-space offset plus a
  shadow gap, since top-down has no vertical axis.
- Contacts have no mass behind them. Both parties resolve an equal half, so
  nothing can shove anything: leaning on another creature nudges it at about
  4 px/s, which is the accelerate-then-brake cycle leaking through rather than a
  modelled push.
- Growth is gone for now. Food is still eaten and counted, `size_scale` is still
  threaded through every system, but nothing writes to it — it is left as the
  hook a real growth system will drive rather than a multiplier to be
  re-threaded through forty call sites later.
- Feet are placed kinematically; they don't push the body. The body leads and
  the legs follow, not the other way round.
- Because of that, a body moving faster than its legs can step is resolved by
  letting the foot **skid** along the edge of its envelope. Nothing slows the
  creature down to keep its feet under it, so at extreme turn rates the plant is
  approximate — but the limb stays inside a plausible pose while it happens.
- Shed meat is edible by any creature — consumption is resolved over the whole
  `creatures` group — but nothing seeks it out, because the second creature has
  no AI. In practice only the player eats.
- Tissue never heals and cells never regrow, so damage is strictly cumulative.
- A bite's penetration budget is spent per cell and any remainder is discarded;
  it does not spill into neighbours. Bone therefore blocks depth but never
  deflects it sideways.
- The default `bite_radius` is comparable to the body's half-width, so a bite
  near the midline tends to take the full width of the body and wounds read as
  bands. Narrower jaws make the cell structure more legible.
- The body fill is drawn as a strip of quads between spine cross-sections, so a
  very sharp bend can overlap slightly on the inside of the curve. It is
  invisible at opaque fill and avoids depending on concave polygon
  triangulation.
