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
| `W` `S` / up/down arrows | move forward/backward along the creature's orientation |
| `A` `D` / left/right arrows | turn the body left/right |
| move mouse | shift and look the head toward the cursor; the mouse never steers the body |
| left click | bite (anatomical hit + cooldown) |
| hold left click | keep hold of what you bit — drag it, or be dragged by it |
| click again while holding | chew: shut the same jaws on the same flesh once more |
| `Shift` | sprint |
| `F1` | show/hide the tuning panel |
| `F2` | toggle debug draw |
| `R` | reset |
| mouse wheel | zoom |

Eating the amber pellets counts toward `food_eaten` and nothing else for now —
growth has been taken out until there is a real system for it. `size_scale` is
still threaded through every system, pinned at 1.0, as the single value that
system will drive when it lands.

A second body lies ahead of the player as the first combat slice. Nothing drives
it: until there is an AI, everything placed in the habitat is a **carcass**, and
it is simulated as one rather than parked as a living creature with its hands in
its pockets — see **Bodies in the habitat** below. It can still be walked into,
bitten, held, towed and eaten. A click throws the head forward in a lunge and the bite resolves at full
extension, eating into a lattice of body cells layered skin over muscle over
bone. If the button remains held when the bite connects, the jaws *keep hold*:
the two creatures are joined at that point and whoever has the weight and the
strength decides where the pair goes from there. Tissue that comes off falls
into the world as meat and can be eaten. Bodies are solid, so the two creatures
can be walked into rather than through.

## How it works

Five systems run in a strict one-way chain each tick. That ordering is the whole
reason the thing is stable without a global solver — nothing downstream can ever
invalidate something upstream.

```
input ──▶ head position ──▶ contacts + grip ──▶ spine ──▶ body shape ──▶ limbs
```

| File | Responsibility |
|---|---|
| [MovementInput.gd](scripts/MovementInput.gd) | devices → an abstract `{throttle, turn, sprint, aim}` command |
| [Creature.gd](scripts/creature/Creature.gd) | motion integration, body/limb contact and grip resolution; drives the systems below in order |
| [Constraints.gd](scripts/creature/Constraints.gd) | the two projection primitives everything is built from |
| [Spine.gd](scripts/creature/Spine.gd) | the particle chain and its relaxation solve |
| [BodyShape.gd](scripts/creature/BodyShape.gd) | outline, head, eyes, limb sockets, tail — all derived from the spine |
| [Physique.gd](scripts/creature/Physique.gd) | mass, strength and bite force, read off the drawn body and the surviving tissue |
| [Grip.gd](scripts/creature/Grip.gd) | one set of jaws holding onto another creature, as a tether in its body space |
| [AnatomyState.gd](scripts/creature/AnatomyState.gd) | anatomical hit-testing — which creature, and which structure of it |
| [TissueGrid.gd](scripts/creature/TissueGrid.gd) | the body-space cell lattice: skin over muscle over bone, and what a bite does to it |
| [ScrapField.gd](scripts/world/ScrapField.gd) | tissue knocked loose, as meat lying in the world |
| [Fabrik.gd](scripts/creature/Fabrik.gd) | generic FABRIK chain solver |
| [Limb.gd](scripts/creature/Limb.gd) | one arm/leg: bones + step-cycle state |
| [Gait.gd](scripts/creature/Gait.gd) | where feet want to be, when they pick up, where they land |
| [Ragdoll.gd](scripts/creature/Ragdoll.gd) | the limbs of a body nobody is driving — Gait's opposite number |
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
drawn. Body contacts translate the bodies themselves; limb contacts are handled
inside the procedural IK and therefore bend or move the limb without holding two
creatures apart at arm's length.

Three decisions make it fit the one-way tick chain rather than fight it:

- **Each creature resolves its own share of every contact and never writes to
  another's state.** Both parties run the same pass and compute the same split,
  so exactly one full correction is applied between them without either creature
  reaching into the other's simulation state.
- **The narrow phase compares capsule pairs, not spine points.** This catches a
  narrow body crossing halfway along a long segment, where no endpoint lies
  inside the other silhouette and a point-probe solver reports a false clear.
- **Corrections are applied between the motion integration and the spine
  solve**, so the silhouette, the limbs and the tissue lattice are all built
  from the corrected pose within the same tick instead of a tick behind it. The
  complete creature is translated as one rigid correction, with every `point`
  and `prev` shifted equally. Collision therefore cannot kink the spine and set
  up a correction/constraint tug-of-war.

Position alone is not enough, and the difference is not subtle. Corrected only
positionally, a creature walking into another keeps walking: measured, it shoved
a stationary creature 800 px across the world ahead of it at its own full speed,
with no resistance at all — the correction simply could not outrun the
throttle. So a contact also sheds the part of `speed` that is driving into it,
scaled by how squarely it opposes travel. Head-on that stops the creature dead;
along a flank it is nearly zero, so bodies slide past each other freely. Heading
is deliberately untouched, so a creature pressed against another can always turn
away and leave.

#### ...and weight decides who yields

The share is not half any more. It is the *other* body's fraction of the pair's
mass, so a Gecko walking into a Crocodile does nearly all of the moving and the
Crocodile barely notices, while the Crocodile walking into the Gecko pushes it
across the world ahead of itself. The same number scales the speed a contact
sheds, which is what stops a heavy creature being brought to a halt by something
it should be able to shoulder aside.

Two properties are what make this a change of one line's meaning rather than a
new system. The two shares are `m_other / (m_a + m_b)` computed independently by
each party, so they still sum to exactly one — the separation stays complete and
symmetric with no cross-creature writes. And equal masses give 0.5 each, which is
the constant this replaced, so two creatures of the same build behave precisely
as they did before mass existed.

### Bodies in the habitat

Until an AI lands, a body placed in the world is a **dead** body, and `alive` on
the creature is what says so. It is a property of the body rather than of who
happens to be steering it, so the day something does drive one the only change is
that the flag becomes true.

A carcass is not a special case bolted onto the side. It runs *the same chain*,
starting further down it:

```
live      input ──▶ head ──▶ contacts + grip ──▶ spine ──▶ body ──▶ limbs
carcass                     contacts + grip ──▶ spine ──▶ body ──▶ limbs
```

Nothing is reordered and nothing downstream is skipped, which is precisely why a
carcass is still a body in the world: the silhouette, the tissue lattice, the
physique and the bounds are all rebuilt from this tick's pose exactly as they are
for a living creature, so it can be collided with, bitten, held, towed and eaten
through the machinery that already existed.

**Weight needed no code at all.** `Physique` is read off the drawn body and the
surviving tissue whether or not anything is driving it, and the contact and grip
passes already split every correction by mass — so a heavy carcass is shouldered
aside less and towed more slowly for exactly the reason a heavy creature is,
through exactly the same line.

Three things did need writing, and each replaces a system whose entire job was
being alive.

#### A free spine, not a pinned one

[`Spine.step()`](scripts/creature/Spine.gd) is built for a chain whose head is
placed by input: point 0 is authoritative, every pass walks strictly front to
back, and only ever the *child* of a joint is moved. `step_free()` is not that
with the pin taken out, and the difference is the whole reason it is a separate
solve. There is no authoritative point on a carcass, and a solve that kept one
would quietly make it the anchor the rest of the body hangs off — pulled by the
tail, such a body swings about its own snout instead of following. So both halves
of every distance constraint move, and the passes alternate direction so neither
end accumulates the residue of the other.

The bend projection is symmetric too. Rotating only the child works for the live
head-to-tail solve, but alternating that rule on a free chain gives each sweep a
different authority. After a shove, the two passes can chase a bend correction
around the body forever as a steady spin. The free solve instead shares the
rotation between both outer particles and preserves the triplet's centroid, so
the anatomical limit cannot manufacture angular motion.

What is gone is what a live creature does and a dead one does not: the
undulation, and the head pose. What is left is inertia, ground friction as heavy
damping, and the same two anatomical invariants — segment length and bend
limit — which hold whether the animal is alive or not.

#### It arrives lying down

`rebuild()` lays a spine out dead straight, and that is the correct start for a
creature about to be dragged around by its head. It is exactly the wrong one
here, and not for cosmetic reasons: **a straight chain already satisfies every
constraint**, and nothing bends a spine with no head driving it, so a carcass
that spawned straight would stay a plank forever. The curve has to be there from
the beginning.

`rebuild_slumped()` draws one, once, from a generator seeded off where the body
actually is — so a given body lies the same way every run while two bodies
anywhere apart lie differently, without anyone authoring either pose. Two
components, because either alone is unconvincing: one slow arc over the whole
length weighted through the trunk, which is the body having folded as it went
down, and a small per-joint wander on top of it. Every turn is kept inside
`max_bend`, so the pose a carcass starts in is already legal and the first
constraint pass has nothing to unpick.

Settling at build time rather than collapsing on the first tick is a deliberate
trade. A collapse is only ever seen by someone already watching the moment a body
spawns; a player who walks up a minute later has to find something that reads as
having been dead the whole time.

#### Limbs that are limp, not just still

Every limb pose in a live creature is the answer to a question about locomotion:
`Gait` decides where a foot wants to be, when it is overdue and where it should
land, and `Fabrik` puts the bones there. [`Ragdoll`](scripts/creature/Ragdoll.gd)
is its opposite number and asks none of them. Its limbs are two-bone chains
hanging off the sockets, carried wherever the body is carried and settling under
friction wherever that leaves them — no ideal position, no stride threshold, no
step, no lift.

Three things are kept from the live solve rather than replaced, because each is
anatomy and not gait: the bones keep their exact lengths, the joint folds the way
that joint folds ([`Limb.seed_joint`](scripts/creature/Limb.gd), now shared with
the gait rather than duplicated in it), and the foot stays inside the fan the
limb can physically reach. A dead leg is limp. It is not detached, it is not
double-jointed, and it does not lie through its own ribcage.

Gravity, in a view with no vertical axis, is two facts together: the limb has no
lift, and it has no tone. `lift` is held at zero — a dead foot is on the ground
and its shadow is tight under it — and nothing anywhere holds a limb out, so what
is drawn is only ever what the constraints and the friction left. Measured, that
leaves a limb resting at about half its length from its socket, against the
`stance_reach` of 0.78 a walking one holds itself at.

#### A towed carcass trails

The one behaviour that could not be had by leaving the live correction alone.
`_translate_contact` moves a whole body rigidly, and that is not a stylistic
choice: a living creature's head is placed by input and re-pinned every tick, so
a correction applied halfway down its spine is unpicked by the very next solve
and the disagreement comes back out as flailing. Nothing re-pins this one, so the
honest thing is also the available one. `_drag_at` applies the pull where the
pull acts — feathered over the neighbouring stations, so it enters the chain as a
haul on a region of flesh rather than a tug on one particle — and the free chain
carries it the rest of the way. The station the jaws are on takes the whole
correction, because that is the one the tether measures its slack from; the rest
of the body is brought along by the constraint solve over the ticks that follow,
and **that lag is the trailing**.

Living-body contacts stay rigid because their driven head would immediately
unpick a local correction. A carcass has no such pin, so its share is split
between centre-of-mass translation and a correction at the spine station the
narrow phase actually found, feathered into its neighbours. The same mass split
and no-cross-creature-write rule still decide how far it yields. The blend lets
it bend around a shoulder or jaws pressing into it without merely folding in
place when it should also be shoved aside.

A grip also retains the structure named by the anatomy hit. Torso holds remain
bound into spine/body coordinates. A hold on an upper leg, lower leg or foot is
reconstructed from that limb's live joints and pulls those particles first. Once
the limb reaches its anatomical extension, the socket passes the remaining pull
into the free spine, so the leg flops and straightens before the body trails after
it.

### Gait

Purely reactive, no timeline. Each foot has an ideal position derived from the
body’s current pose; a planted foot stays nailed to the world until it drifts
further than `stride_distance` from that ideal, then arcs to a spot slightly
*ahead* and re-plants. Step frequency therefore falls out of speed for free, and
an idle creature is genuinely still.

Each upper bone, lower bone and foot is also tested as a capsule against every
other creature's tissue-aware body. A penetration shifts the foot target and
the two-bone chain is solved again, repeatedly over a small bounded pass. This
makes the knee fold and a planted foot slide around the obstacle while FABRIK
continues to guarantee exact bone lengths. The correction is written back to
the gait's world-space foot state, so it persists rather than snapping into the
obstacle again next tick. Limbs remain kinematic—they react to a body but do not
push that body—and a destroyed limb or a hole in the obstacle stops colliding.

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

Damage lives in a lattice of body cells — 32 x 7 over the body, 10 x 3 per limb
— and each cell is a stack of three tissues in *depth*, because top-down means
you are looking down through them: skin over muscle over bone. A bite spends a
penetration budget strictly outside-in, so nothing under a layer can be touched
until that layer is gone, and the colour of a cell is simply whatever is now
uppermost in it. Skin holds its dark surface as a continuous membrane until it
tears; exposed muscle darkens as it is depleted and carries close longitudinal
fibres so it reads as dense tissue rather than a coloured tile.

The lattice is not an overlay on the creature — it *is* the creature. The body
is drawn cell by cell rather than as a silhouette with the wounds painted over
it, which is the whole reason a wound can be a hole (see below).

Skin is a thin, stretchy rind and muscle is where the fight is: at the default `bite_damage`
one bite strips skin across nearly the full width of the jaws, three tear
through the muscle under the middle of them, and seven get through bone. So a
bite always *opens* the body, and a kill is always either repeated bites or a
deeper one.

#### The skeleton is a frame

Bone is not just thicker, and it does not lie under the whole body. It exists
only where there is an actual skeleton, laid out in body space:

```
...........#.....#..............   ← only the girdles reach the flank
########...#.#.#.#..............
########...#.#.#.#..............
################################   ← vertebrae, one cell wide, snout to tail tip
########...#.#.#.#..............
########...#.#.#.#..............
...........#.....#..............
^------^   ^ ^-^ ^  ^-----------^
  skull    girdles    loin + tail
             ribs
```

A skull filling the head cap but not the cheeks; a vertebral column one cell
wide running the whole length; a full-width girdle under each pair of limb
sockets; two ribs between them on alternating columns; a core down each limb.
That is 38% of the body's cells, and the sparseness is the point. Bone yields at
half the incoming depth and then *stops the bite*, since there is nothing behind
it to reach — so wherever it runs, a wound bottoms out on a pale bar, and
wherever it does not, flesh is all there is and eating through it **opens a hole
clean through the creature**. Both states have to exist for either to read: if
bone sat under most of the body every wound would end on the same surface and
you could not tell a skeleton from a hole. The alternation is what makes the
ribcage a cage rather than a shell — a bite landing between two ribs reaches the
muscle they do not cover and one landing on a rib does not; a rib is never laid
against a girdle, because two adjacent crossbars are one wide bar with no gap
left to bite into.

The layout is fixed in body space for the same reason the grid dimensions are:
it has to name the same cells after the tuning panel has restructured the spine
underneath it. The girdle columns therefore mirror the *default* `front_limb_t`
and `rear_limb_t` rather than tracking them live.

**The frame has to be one connected piece**, and it is asserted as one — a flood
fill from the snout has to reach every bone cell, and every limb socket has to
sit in one. Flesh is what a bite takes first, so a skeleton whose parts meet
only through muscle comes apart into floating fragments at exactly the moment
the skeleton is the whole of what is left to look at. It is also why each girdle
sits in the column its socket is *in* rather than the one beside it: a limb bone
rooted over flesh is a limb attached to the creature by meat alone.

#### A hole is a hole

A cell with nothing left in any layer is not drawn, not collided with and not
hit-tested. The obvious alternative — leave the silhouette solid and stamp
destroyed cells in the ground colour — looks nearly right and is wrong in every
way that matters. Ground-coloured ink is still ink: it hides whatever is behind
the creature instead of showing it, it stops lining up the moment a wound sits
over a second creature or a scrap, and, worst, nothing downstream knows the
tissue has gone. A creature could be eaten hollow and still be a wall.

So the void is carried all the way through. The capsules the body is collided
and hit-tested with are narrowed, per side, to the tissue still standing at each
station: chew halfway into a flank and contact stops at the new surface, chew a
station clean through and it stops colliding at all and can be walked straight
into. Jaws closing on an opening find nothing to bite. That surviving reach is
recomputed when a cell is destroyed rather than per frame, so an undamaged
creature pays nothing for any of it.

Drawing the body from its cells has one cost worth naming: the lattice is the
outline now, so the snout and tail caps need enough columns to read as round
without a `draw_circle` under them. The lattice remains simulation data rather
than surface texture: visible grid seams are omitted, skin gets uninterrupted
tension lines, and muscle gets its own denser grain.

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

Destroyed skin and muscle come off as chunks. Adjacent destroyed cells from one
tear are joined by layer and anatomical patch before they enter the world, so a
bite produces a few cohesive pieces rather than a spray of lattice cells. Their
area becomes inertia: broad pieces move less, tumble slowly, settle close to the
wound, retain their tissue grain, and stay as meat until something eats them. A
creature never eats its own: without that rule, a victim's shed tissue would
land in its own mouth volume and being bitten would feed it.

#### Keeping it cheap

Per tick the lattice only re-derives cross-sections — about seventy for a whole
creature — and everything priced per *cell* outside of drawing is deferred to
the rare ticks a bite lands on: erosion, the shed chunks, and the per-column
surviving reach the collision queries read.

Drawing does have to walk the whole lattice, since the lattice is the body. What
keeps that honest is that the walk happens **once per structure per frame, not
once per pass**: the mesh built for the torso is reused by all three of its
offset shadows, which Godot will fill from a single-entry colour array, so the
shadows cost three draw calls and no geometry at all. A whole creature — torso,
four limbs, every shadow — is **0.29 ms** of mesh building, and it gets cheaper
as the creature is eaten because destroyed cells are skipped.

The cells, and the loose organic chunks, go out as single indexed triangle arrays rather
than a polygon apiece. That one is worth stating with numbers, because it is not
a micro-optimisation: Godot issues one canvas command per `draw_colored_polygon`,
and a chewed pair of creatures with a saturated scrap field reached a few hundred
a frame. Measured in a 1280x760 window, that alone cost **5.5 ms/frame** and took
the scene from 120 to 72 fps. Drawn as cells the whole creature is about twenty
commands, shadows included. Skin tension and muscle fibres are each one
`draw_multiline` for the same reason.

### The lunge

A click does not resolve a bite. It starts an animation with a hit frame: a
0.07 s wind-up that rocks the head back, a 0.08 s forward throw, and a 0.18 s
settle. The bite resolves at full extension, against the pose the snout actually
reached. There is no sideways mouth wedge in the top-down silhouette; a brief
world-space **Bite** cue marks the exact impact point instead.

If that hit connects while the button is still held, the strike clock stays on
its apex and the jaws stay shut — and the two creatures are now physically joined
at the point the bite landed. See **Holding on** below. Misses recover normally,
and holding a miss never manufactures a grip.

The throw is fed to **the spine's head point, not to `head_pos`**. That is the
load-bearing detail, twice over. The body has to follow it through the
constraint solve — that is what makes it whip rather than slide — and it must
never accumulate into the motion integrator, or every strike would walk the
creature forward by its own reach. `head_pos` stays the creature's honest
position throughout, which is also what keeps the camera still while the body
lunges.

Cursor look is applied after that body solve by rotating only the head point
around the solved neck, within the configured bend limit. The rest of the spine
is therefore identical regardless of cursor position during ordinary movement:
W/S own translation and A/D own body heading, while the mouse owns only the
final head pose and the direction of a bite lunge. While the jaws have hold of
something, the head is aimed by *that* instead of by the cursor — the pair keeps
moving relative to each other, so the drawn head has to keep tracking the flesh
it is holding or it would slide off the place the physics is anchored to.

### Weight, strength and bite force

Three physical quantities, and **not one of them is a slider**. They are read off
the creature that is already being solved every tick:

```
mass       = density × silhouette volume × tissue integrity
strength   = muscle_power × mass^(2/3)
bite force = jaw_power × (head radius / 13)² × surviving head tissue
```

Volume is the drawn body: a chain of discs, one per cross-section, along the
lengths the spine actually holds, with a round cap at each end and the tail
clipped exactly where the silhouette clips it. So the thing you can see is the
thing it weighs, and widening a body in the tuning panel makes it heavier without
a second slider to remember. Off the shipped presets that lands at:

| | mass | strength | bite force |
|---|---|---|---|
| Gecko | 0.46 | 0.74 | 0.47 |
| Salamander | 0.94 | 0.77 | 0.36 |
| Lizard | 1.00 | 1.00 | 1.00 |
| Komodo | 5.62 | 3.48 | 4.60 |
| Crocodile | 11.19 | 5.75 | 21.48 |

Two consequences fall out of that shape and neither needed a rule of its own.

**Damage is not just cosmetic any more.** The integrity term is the same lattice
number the biomass readout shows, so a creature eaten half open is lighter, gets
shoved further in every contact, and is weaker at everything its strength buys.
Its jaws weaken too, on the surviving *head* tissue specifically — chew a
predator's skull open and its bite goes with it.

**Both derived quantities are areas, and mass is a volume.** Strength is
literally `mass^(2/3)`; bite force is the head's cross-section, which grows the
same way. So a big creature is stronger and bites harder outright while being
weaker *per kilo* — the square-cube law, and the whole reason a Gecko latched
onto a Crocodile can barely walk while the Crocodile tows the Gecko without
slowing down. One exponent, rather than a table of who-beats-whom.

Bite force is sized off the head rather than off the body because the head is the
part that does the biting and the part you can see doing it: a broad skull reads
as a hard bite before any number is involved.

### Holding on

A latched bite used to be a static hold — the biter's speed was zeroed and the
victim was never even told. It is now **one inextensible tether** between the
biter's jaw point and a point bound into the victim's *body space*, resolved by
exactly the machinery body contacts already use: a rigid translation of each
complete creature, in shares set by their masses, in the same phase of the tick.

That is the whole mechanism. Everything the interaction reads as is what it does
under different numbers:

| | what actually happens |
|---|---|
| **latching** | the tether exists; the pair is joined at one point |
| **dragging** | uneven masses — the light body takes nearly the whole correction and is towed behind jaws that barely move |
| **being dragged** | the same tether, seen from the other end |
| **struggling** | both creatures pulling; the tether's slack is the measured disagreement |
| **losing your grip** | that disagreement, as a force, exceeding the jaws' bite force |
| **stretching** | that same force past the *tissue's* yield point; the tether lengthens as the flesh draws out of the body |
| **tearing meat off** | it staying there long enough for the flesh to part — the mouthful comes away and the jaws re-seat |
| **chewing** | the player working the button; the jaws shut on their bind again, at whatever depth their force has left over |

The bind is stored in body space for the same reason tissue damage is: the pose
is rebuilt from scratch every tick and a hold recorded in world coordinates would
be a hold on nothing by the next one. Load is measured as `√(reduced mass) ×
separation speed` — the root because a set of jaws gets a proportionally bigger
hold of a bigger body at the same time as the body becomes harder to hold.

Four details carry the rest of it:

- **The tether only pulls.** Pushing is the contact pass's job. A rope that could
  also push would spend its life fighting it.
- **A gripping pair does not collide.** Two constraints acting on the same pair,
  at the same point, in opposite directions is not a tuning problem — jaws that
  have hold of something are *inside* it, which is exactly the state the contact
  pass exists to forbid. Measured, the pair buzzed and the stretch the load is
  read from ran away to fifteen times what the two were actually doing. So while
  a hold is in force these two have one rule between them and it is the jaws'.
  Both parties reach that conclusion from the same grip, so neither ever stops
  colliding with the other while the other does not, and everything else in the
  world still collides with both.
- **A load slows locomotion but never turning.** Speed and acceleration are
  scaled by `strength / (strength + towed mass)`; heading is untouched, exactly
  as it is under a body contact. That is deliberate and it is what makes the
  fight legible: however overmatched a creature is, thrashing stays available —
  and thrashing is precisely what loads a set of jaws, because the load is
  measured from how fast the two are coming apart. **Turning is the escape.**
- **A hold never bites by itself.** Holding the button is holding on and nothing
  else: jaws clamped on a victim that is not being pulled against leave it
  exactly as the strike left it, however long they stay shut. The two things that
  damage a held creature are an action and a force, and neither is the button
  being down. *Chewing* is the button being worked — release and press again and
  the same jaws shut once more on the same bind, at whatever depth their force
  has left over after holding on (`strain`, so a struggling victim is bitten
  shallower than a still one). *Tearing* is below.

  Jaws part rather than spring open, so a press inside a 0.25 s window is a chew
  and not a release. That is the whole of what it costs to make chewing a
  repeated action on one button: hold to hold, work it to chew, let it go to let
  go. `chew_interval` is now a floor on how fast a species can work its jaws
  rather than a rate they work at on their own.

- **Flesh has a tensile strength, and it is measured against the same load the
  jaws are.** A hold has two ways to fail and they are compared directly:

  ```
  load > bite_force               → the jaws come off a body still in one piece
  load > tissue strength, for long enough → the flesh parts and the meat comes away
  ```

  Tissue strength is read, not set: the surviving hit points inside the jaws' own
  footprint — so a mouthful backed by bone resists about twice one over an open
  cavity, and a wound already chewed through gives at once — times the victim's
  cross-section by the same `mass^(2/3)` the rest of the physique uses.

  Which failure happens is therefore never chosen anywhere. It is whichever gives
  out first, and that single comparison is the whole of why a Crocodile strips
  meat off prey a Gecko can only be shaken from. Past the yield point the pull
  first *draws the flesh out* — the tether visibly lengthens by up to 7 px as it
  stretches — and only parts it once enough force has been sustained for long
  enough. Stop struggling and the stretch recovers; the wound stops growing.

A chew, a tear, and the mouthful a grip takes with it when it is pulled off all
go through the same world resolver as the opening bite, so all four shed meat,
pick their target and can report a miss by one path. Only their depth differs,
and a tear's is measured in flesh rather than in bite force: enough to clear skin
and muscle at the centre of the jaws, with bone still stopping it at the
skeleton. That is why a limb can be stripped but a ribcage only bared.

Jaws that empty the flesh they were holding — by chewing it away or by tearing it
off — **take hold of the next** rather than opening, searching the victim's body
for the nearest surviving tissue within their gape. Without that a strong bite
would lose its grip *faster* than a weak one, since the better it works the
sooner the cell it was bound to is gone. Re-seating is what turns a latch into
chewing *in*: the wound deepens under jaws that stay shut, and the hold ends only
when the load pulls them off, the jaws are given long enough to open, or there is
nothing left within them to hold.

A bind counts as empty when *either* the body no longer reaches that far or the
cell the jaws are on has nothing in it. The second condition is the ordinary
aftermath of a tear, and without it a set of jaws would go on pulling against
flesh already in them and part it again every tick.

Jaws pulled off take a mouthful with them, and cannot silently take hold again
until the button is released — one press is one hold, the same way it is already
one lunge and one cooldown.

Which of those outcomes you get is decided by the three numbers and nothing else.
Measured, across the shipped presets:

Victim displacement over five seconds, or when the jaws came off:

| | biter drags it away | victim runs | victim thrashes on the spot |
|---|---|---|---|
| Crocodile on Gecko | tows it 524 px | holds; it makes 17 px | holds; strips 62% of it |
| Komodo on Lizard | tows it 457 px | holds; it makes 44 px | holds; strips 24% of it |
| Lizard on Lizard | tows it 282 px | towed 352 px along with it | **torn off at 2.9 s** |
| Lizard on Komodo | moves it 17 px | dragged 478 px behind it | **torn off at 0.7 s** |
| Gecko on Crocodile | moves it 1 px | **torn off at 1.1 s** | **torn off at 0.6 s** |

Read the diagonal: the same tether, the same three numbers, and a Crocodile is
unshakeable while a Gecko cannot keep hold of anything it did not already
outweigh.

Read the last column on its own and you have the tearing rule in one line. Every
one of those five victims is doing exactly the same thing — spinning on the spot,
loading the jaws as hard as it can. Three of them shake the jaws off. Two of them
cannot, and being unable to is precisely what gets them eaten: the load has to go
somewhere, and if the jaws will not give then the flesh does. Nothing in that
column is a rule about crocodiles. Note also that **dragging tears nothing** —
towed prey travels *with* the jaws, so the two never come apart and the load
stays near zero. Tearing is bought with struggle, by either party.

## Tuning

Press `F1` for live sliders (generated from `CreatureParams.SCHEMA` — add a
property plus one schema row and it appears automatically). Five presets ship in
the panel: **Lizard**, **Gecko**, **Salamander**, **Komodo**, **Crocodile**.
Mass is not among the sliders — it is on the HUD readout instead, because it is
something the creature *has* rather than something you set.

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
| Heavier for the same silhouette | `density` up — and remember the width sliders already move mass |
| Strong for its size (drags more, is dragged less) | `muscle_power` up |
| Jaws that will not be shaken off | `jaw_power` up — this is grip, not penetration |
| How fast the jaws can be worked while latched | `chew_interval` down / up — a floor on player-driven chewing, not a rate |
| How readily held flesh tears | `Grip.FLESH_TENSILE` / `Creature.TEAR_YIELD` / `TEAR_WORK` — global properties of meat, not per-species |

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
- **`turn_pivot` places the low-speed turn centre**, measured back from the head.
  At the defaults it lands close to the shoulder station, so a spot pivot
  rotates the creature roughly about its front feet. The offset fades away once
  the creature is moving, where ordinary travel already supplies the arc and a
  second pivot displacement would only widen direction changes.

Two more couplings arrive with the physique, and both are the same trap in
different clothes: **the silhouette is an input to combat now.** Widening the body
raises mass, which raises strength and every contact share that reads it; widening
the head raises bite force by the *square* of the change. So retuning a creature's
look retunes what it can hold and what can hold it, and `density`, `muscle_power`
and `jaw_power` are corrections on top of that rather than the whole of it.

`constraint_iterations` and `fabrik_iterations` are cost/quality dials; the
defaults (6 and 6) are already past the point of visible improvement.

## SENSES: sight

The player creature owns a `CreatureSenses` child. Each sense registers as an
independent perception layer; sight and smell exist now and neither depends on
the other, so hearing can be added beside them the same way — construct it in
`CreatureSenses._ready`, hand it to `register_layer`, and give it a `reset()` if
it holds state and an `advance()` if it needs a clock. `SightSense` provides the
gameplay-facing head pose and continuous `clarity_at()` query, while
`SightRenderer` consumes that state only for presentation.

The default `SightProfile` defines a clear near/forward field and a broader
peripheral field. Its world distances and visual treatment are resource
properties ready to be replaced per species. Species selection and full reset
both reset the component through the same hook. The renderer samples the habitat
below the player, leaving the controlled creature and HUD sharp; unresolved space
is kept paper-bright, softly blurred, desaturated and low contrast rather than
darkened or clipped by a hard visibility mask.

## SENSES: smell

Smell is split in two, and the split is the design: **the world holds the scent,
the creature holds the read.**

`ScentField` is the world half and draws nothing at all. A pellet, a carcass, a
scrap and a walking animal look exactly as they did before it existed; what they
gain is a `Trace` — *something of this kind was at this place, this recently*.
Five kinds smell distinctly (`FORAGE`, `QUARRY`, `CARRION`, `BLOOD`, `SCRAP`),
and sources are *read* off the habitat on a slow tick rather than notifying
anything, so no object in the world knows the field exists.

One mechanism gives persistence, trails and decay together. A source still
present renews the trace under it every tick, so it stays fresh while it exists
and starts dying the moment it stops — eat a pellet and its smell hangs about
after it. A source that has moved further than the merge radius renews nothing
and lays a new trace instead, so what is left behind it is the path it walked,
ageing from the tail forward. Take the source away and the chain simply runs out.
Blood arrives both ways: a spill at the point of a connecting bite, unowned
because it is on the ground now, and a slow drip from a wound scaled by how badly
the creature is hurt. Kinds differ in how long they last and in `CARRY`, how far
they announce themselves as a multiple of the smeller's reach — a carcass travels,
a seed has to be underfoot — rather than in being muffled up close. You always
know what is under your own nose.

`SmellSense` is the creature half, and it is **perception, not emission**.
Nothing leaves the source. The sense works in beats: each one resolves the
strongest reads in range and leaves marks in the air *around* what it found,
which tighten while the read holds and dissolve when it lapses. Confidence is the
creature's — distance, freshness, and a little for having the muzzle turned
toward the thing — so weak reads are sparse and scattered and sure ones cluster.
A creature never reads its own trail, or it would spend its life following itself
home. Gameplay asks `confidence_at()`, the counterpart of sight's `clarity_at()`,
and gets a field rather than a detector.

`SmellRenderer` draws the marks and only the marks. A mark carries how sure the
read was and a fixed seed; the renderer derives its glyph, size and hue from that
seed, so typography stays out of the sense and a mark never changes character
while it is on the paper. Marks are painted in screen pixels on a fixed reading
lattice — they belong to the observer, not to the habitat — and multiplied into
the page as pigment rather than laid over it as light, which is why
`shaders/smell.gdshader` exists: `CanvasItemMaterial`'s multiply mode has no use
for a glyph's coverage and would stamp solid blocks, so the blend folds the
coverage in itself. The layer sits above the sight treatment and below the
controlled creature, which is the argument for it: what the eyes could not
resolve, the nose still annotates.

`SmellProfile` carries the tunable half of both — reach, beat, spread, lives,
drift and the palette — and swaps per species through the same hook sight uses.

## SENSES: hearing

Hearing follows the same world/read/presentation split without borrowing either
Sight's pixels or Smell's traces. `SoundField` owns short-lived physical events:
their source, kind, amplitude, travel radius and the habitat geometry between two
points. Movement, bites and eating announce `STEP`, `BITE` and `FEED` events to
that field. No emitter knows which creature may hear it or how it will be drawn.

`HearingSense` is the creature half. A sound is resolved only when its expanding
wavefront reaches the solved head, then distance, the creature's sensitivity and
each intervening solid body attenuate the read. The resulting direction,
strength, kind and occluded flag are gameplay-facing state with bounded memory,
ready for AI without a graphics backend. `strength_at()` supplies the continuous
query alongside Sight's `clarity_at()` and Smell's `confidence_at()`.

`HearingRenderer` presents the same travelling events as the design's thin rings
of near-even, sub-pixel ink dots. All dots in one sound share one radius; they
quietly drop out as the circumference grows. A route that reaches solved creature
geometry stops at the boundary and dissolves there, leaving a clean acoustic
shadow rather than continuing through the body. The layer prints above Sight and
below Smell and the controlled creature, so sound remains legible outside the
visual field without becoming a bright overlay.

`HearingProfile` carries the per-creature reach, sensitivity, threshold,
occlusion response and memory separately from the dot density, line softness,
fade and ink treatment. It swaps and resets through the same component seam as
the other senses.

## Tests

Ten headless checks cover controls, movement feel, simulation, rendering, UI,
combat, sight, smell, hearing and the bodies in the habitat:

```sh
godot --headless --path . --script tests/ControlsTest.gd # input/head-look isolation
godot --headless --path . --script tests/MovementFeelTest.gd # reverse/steering behaviour
godot --headless --path . --script tests/SimTest.gd      # simulation invariants
godot --headless --path . --script tests/RenderSmoke.gd  # every draw path
godot --headless --path . --script tests/UIInteractionTest.gd # HUD interactions
godot --headless --path . --script tests/SightTest.gd    # perception/reset/render order
godot --headless --path . --script tests/SmellTest.gd    # scent persistence/trails/reads
godot --headless --path . --script tests/HearingTest.gd  # arrival/occlusion/events/reset
godot --headless --path . --script tests/CombatTest.gd    # bite/anatomy slice
godot --headless --path . --script tests/RagdollTest.gd   # the dead body
```

`SmellTest` checks the two halves separately and then the seam. On the world
side: a deposit leaves one trace, a source renewing in place stays one smell
rather than multiplying, two kinds in one place stay two, scent weakens and then
disappears on its own clock, and a source moving away leaves a chain that is
freshest at its head and laid along the path actually walked. On the creature
side: reads resolve with distance and favour the muzzle, kinds carry different
distances while anything under the nose is read for certain, and a creature gets
nothing at all from its own trail.

Then the claims the design rests on, which are the ones easy to regress into a
particle system. No mark is ever spawned *on* its source, the marks occupy the
air around it, and none of them stream further than the read's own spread — so
nothing appears to pour out of anything. The sense goes on making marks with
nothing in range. Marks dissolve. Neither the read nor the field can grow without
bound under a saturated habitat. Gathering scent changes nothing about the
habitat it read — same pellets, same scraps, same integrity — while the bodies
already standing in it do smell, of the right things. And the layer is where it
claims to be: over the sight treatment, under the controlled creature, multiplied
into the paper with the glyph coverage folded into the blend, which is the one
way this layer can fail while still drawing.

`HearingTest` checks the same separation from both sides. It holds a wave before
and after arrival, verifies range, direction, distance falloff, profile swapping
and bounded world/memory state, then places the real carcass body across the path
and asserts both gameplay attenuation and the renderer's stopping distance. It
also exercises movement, combat and food event seams, the Sight/Hearing/Smell
layer order, camera zoom, species changes and full reset.

`RagdollTest` asserts the four things a carcass claims to be. That it is *found*
at rest and not standing to attention: a slumped spine, limbs sprawled short of
the walking stance, and no foot at any height. That being limp costs it none of
its anatomy — exact segment lengths, exact bone lengths, no bend past the limit,
held over thousands of ticks of a solver with no pinned point in it, which is
where a free chain would otherwise stretch. That it is still a body in the world:
weighed, walked into rather than through, and shoved by its mass-weighted share.
And that pushes and torso towing deform it instead of sliding it rigidly, while a
post-impact angular check ensures the free solver cannot turn constraint error
into perpetual spinning. A limb case additionally verifies that a bite on a foot
stays on the foot, articulates the leg, and transmits a taut pull through the
socket into the spine.

Its determinism check earns its place: it caught the resting pose being seeded
off `spawn_position`, which `reset` never touches — so a body moved anywhere at
runtime went on wearing the pose it was built with at its old address.

`CombatTest` covers the tissue rules that are easy to regress: bites eat
outside-in and never touch a layer through an intact one; they damage only where
they land; bone survives several times longer than the flesh beside it; damage
outlives both a procedural rebuild *and* a change of segment count; and the
lunge extends, resolves at its apex, shows its Bite cue only on impact, and
leaves the creature standing exactly where it started. It also checks that shed
tissue is aggregated into weighty pieces rather than cell-sized particles.

The hold/chew contract gets its own set, because the distinction between the two
is the easiest thing here to regress into a grinder. Jaws clamped on a motionless
victim for a full second must leave its integrity *exactly* where the strike left
it. A release followed by a press inside the parting window must bite and must
keep the hold, without re-running the strike animation. Mashing the button must
not beat `chew_interval`. And a release held past the window must actually open
the jaws, and then finish the original lunge's recovery.

It also asserts the skeleton is still a *frame* — bone under less than half the
body, at least three free-standing crossbars over the torso with flesh either
side, nothing but vertebrae behind the hips — and that flesh with no bone under
it is eaten clean through rather than bottoming out. Those are shape claims, not
totals, so they catch a skeleton that has quietly spread into a plate. Two more
say the frame is a single connected piece: a flood fill from the snout has to
reach every bone cell, and every limb socket has to sit over a girdle rather
than over flesh.

Then it checks that a hole is genuinely a hole, which needs three things to
agree. Cells stripped of every layer are retired; eating one flank narrows the
body on that side and *only* that side; and a station eaten clean through stops
colliding and stops answering the bite query, while the rest of the creature
goes on doing both. Painting destroyed cells the colour of the ground passes
none of the last four.

And it covers contacts: a creature driven at another for four seconds at full
throttle ends up stopped against it rather than through it and with its speed
collapsed; deep separation translates every spine particle rigidly; sparse
capsules crossing between their endpoints are still detected and untangled; a
foreleg placed through another torso bends clear without changing either bone's
length; and a creature with nobody near it is not displaced at all. Each fails
loudly if the contact pass is removed.

The physique checks are all *relational*, because the numbers themselves are
derived and will move whenever the presets are retuned. Mass follows build across
the five of them and a Komodo is at least three times a Lizard; the heavier
creature is stronger outright but weaker per unit of mass, which is the only
thing that says the square-cube exponent is still in there; a Crocodile's jaws are
in a different league from a Komodo's. Doubling a torso's width alone has to move
mass — otherwise mass is really a slider spelled differently — and chewing a
creature open has to take mass and strength back off it.

Then the grip, one assertion per outcome the three numbers are supposed to
produce. A Crocodile holding a Gecko that does nothing for three seconds leaves it
untouched, and then tows it without hurting it — those two are what say a hold is
a hold. The same jaws are not shaken off by a thrashing Gecko, and the struggle
tears meat out of it: integrity falls, scraps enter the world, and the lattice is
left with *holes*, since a tear is a discrete failure of the tissue and not a
uniform thinning. Stop the thrashing and the wound stops growing. Reversed, a
Gecko moves a Crocodile almost nowhere and keeps little of its own top speed while
trying; and a Gecko is torn off a thrashing Crocodile, is left holding nothing
while still holding the button — and leaves that Crocodile with no hole in it at
all, which is the assertion that says which of the two failures fired. Last, a
bite under load goes in shallower than the same bite when free. Weight gets its
own pair: two identical creatures still split a contact exactly down the middle,
and a Crocodile shoves a Gecko several times further than the reverse.

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
- Contacts have weight behind them but no momentum. Mass decides who yields and
  how much speed a contact sheds, so a heavy creature can shoulder a light one
  aside — but nothing is transferred: a creature that stops pushing stops moving
  whatever it was carrying, and there is no impact, recoil or knockback.
- Nothing in the habitat is alive. A body placed there is simulated as a carcass
  rather than parked as a living creature, which is honest about the missing AI
  but is still the absence of one: it never gets up, never reacts, and the only
  things that move it are other bodies and the jaws holding it.
- A carcass settles into its resting pose at build time rather than falling into
  it, so a body cannot be watched dying. When something can actually be killed,
  that is the moment this has to become a real collapse.
- A creature can only be held by one set of jaws at a time. A second grip on the
  same victim is formed and resolved, but only the first one found decides how
  much locomotion that victim keeps.
- A grip binds to the torso axis even when the jaws close on a limb, because
  limbs are kinematic and cannot transmit a pull to the body they hang off. Biting
  a leg therefore holds the animal, on a longer tether, rather than holding the
  leg.
- While a grip is in force the two creatures do not collide with each other, so a
  biter driving hard into its victim can overlap it. Nothing else stops
  colliding, in either direction.
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
  bands. Narrower bites produce more localised wounds.
- The body fill is drawn as a strip of quads between spine cross-sections, so a
  very sharp bend can overlap slightly on the inside of the curve. It is
  invisible at opaque fill and avoids depending on concave polygon
  triangulation.
