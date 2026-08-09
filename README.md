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
| `W` `S` / up/down arrows | move forward / back up along the creature's orientation — reverse is a slower, deliberate retreat and never sprints |
| `A` `D` / left/right arrows | turn the body left/right; switching sides sheds the old swing at the brake rate, so the flip answers immediately |
| move mouse | shift and look the head toward the cursor; the mouse never steers the body |
| left click | bite (anatomical hit + cooldown) |
| hold left click | keep hold of what you bit — a creature, or a severed part; drag it, carry it off, or be dragged by it |
| click again while holding | chew: shut the same jaws on the same flesh once more. On a piece of meat this works it in, and swallows it once what is left will fit |
| `Space` | leave the ground — a leap from a standing start, and a climb for anything with wings. A creature with no leap in its legs stays put |
| `Ctrl` | come down: a controlled descent with wings out, a dive with them folded |
| `Shift` | sprint |
| `F1` | show/hide the tuning panel |
| `F2` | toggle debug draw |
| `F3` | switch between the **Field** and **Anatomy** views |
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
strength decides where the pair goes from there. Tissue a bite destroys falls into
the world as meat and can be eaten; a part that comes *off* — a leg, a tail, a head
— stays a part, and has to be bitten, carried off and chewed down before it will go
down. Bodies are solid, so the two creatures can be walked into rather than
through.

The world is still read from above, but it is no longer flat. Every body occupies
a range of *heights* as well as a place on the ground, and an attack connects only
where the two ranges overlap — so a leap clears a charge, a low animal on a tall
one can reach its legs and nothing above them, and forage over your head is not
food. How high an animal stands is not a setting either: it is its legs, times the
angle its **posture** carries them at. Three stances ship — sprawled, semi-upright
and columnar — and that one angle is the whole difference between them.

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
| [Dentition.gd](scripts/creature/Dentition.gd) | the teeth: how many, how long, how keen, and what type each one turns out to be |
| [BiteMark.gd](scripts/creature/BiteMark.gd) | the footprint one closing of the jaws leaves — the only description of a bite anything downstream gets |
| [TissueGrid.gd](scripts/creature/TissueGrid.gd) | the body-space cell lattice: skin over muscle over bone, and what a bite does to it |
| [ScrapField.gd](scripts/world/ScrapField.gd) | tissue knocked loose, as meat lying in the world |
| [CarrionField.gd](scripts/world/CarrionField.gd) | parts of animals lying in the world — still anatomy, until something bites them |
| [Mouthful.gd](scripts/creature/Mouthful.gd) | a piece of meat in a set of jaws: carrying it, working it in, and getting it down |
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
mass, so a Cat walking into an Elephant does nearly all of the moving and the
Elephant barely notices, while the Elephant walking into the Cat pushes it
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

### Height

The world is solved on one plane and always has been: x and y are the whole of
where a creature *is*, and the spine, the gait and the contact walk have no idea
this section exists. What 2.5D adds is one scalar per body — how far off that
plane it currently is — and one rule:

> Two things interact when the heights they occupy overlap.

That is the entire layer. It is not a third axis of movement; it is a second
question asked after the horizontal one that was already being asked, and every
consumer of it is a single `Stature.overlaps` call sat beside the test it already
had. Horizontal hit testing is untouched.

**Bands, not positions.** Nothing carries "a height". A body occupies a *range*,
`Vector2(low, high)` in world pixels — the same unit as x and y, so a leap is
drawn to the same scale as the animal taking it — and so does an attack. `Stature`
reads those off the pose that has just been solved, exactly the way `Physique`
reads mass off it, and for the same reason: a creature rebuilt with longer legs is
taller without anybody having said so, and a carcass is not standing on its legs
so it is not.

```
                          Elephant                    Lizard
 head    ████ 182–234                                 ████  4–30
 torso   ████ 126–206                                 ████  8–26
 legs    ████   0–162                                 ████  0–16
 jaws    ▓▓▓▓   0–293                                 ▓▓▓▓  0–52
```

Read the two columns against each other and most of the interesting behaviour is
already there without a rule having been written for any of it. A Lizard's jaws
top out at 52 px; an Elephant's belly starts at 126. The two bands that *do*
overlap are the jaws and the legs — because a leg is the one structure on an
animal that runs from the ground to the body — so a low predator on a tall animal
can take a leg and nothing else. It is not a rule about legs. It is where the
bands land.

**Four states, read rather than written.** `Elevation` owns the scalar. The state
is a function of it and of what the wings are doing, so nothing anywhere sets a
mode and nothing can disagree with the height it is supposed to describe:

| | |
|---|---|
| grounded | the scalar is zero |
| leaping | off the ground with nothing holding it up — falling, whether or not it is still going up |
| gliding | off the ground with wings carrying it, below the height they can sustain |
| high flight | the same, at or above it |

A creature with no wings can only ever be grounded or leaping, and nothing had to
forbid the other two: `wing_lift` is zero, so both branches are unreachable. A
flier that folds up mid-air is *leaping* again on the next tick, which is what a
stall is. Nothing in this is a state machine.

**What the layer buys, and what pays for it.** Every one of these is the overlap
rule landing somewhere that already existed:

- **Leaping over a charge.** Two things at different heights have no contact to
  resolve, so the pair is skipped in `_resolve_contacts` — the same exemption a
  grip already gets, one line above it. The leap has to clear the *back* of the
  other animal, so it is a contest rather than a dodge key. Measured: a sprinting
  Cat shoves a Lizard 11 px through it on the ground and 0 px over it.

  The question is asked of each pair of *parts* rather than of the two animals,
  and that is what makes it a mechanic rather than a jump button. The pass
  compares trunks with trunks, and the legs answer separately, because a leg
  spans the whole gap underneath an animal and the trunk it hangs off does not.
  So a Lizard fails the trunk test against an Elephant and walks under its belly,
  passes the leg test against the foot that is on the floor, and passes under the
  same foot once it is picked up high enough. None of that is a rule about
  elephants: it is two bands per part, asked in the order the parts are met. It is
  also why a Cat no longer bulldozes a Lizard — its belly clears a Lizard's back,
  so it steps over one with its feet either side, and only the legs catch.
- **Out of reach.** A bite carries the band its jaws cover, on the mark, next to
  the penetration it already carried. The world picks its victim through it, the
  anatomy query filters structures by it, and the lattice refuses cells outside
  it — so a flier is unreachable, and so is a grounded animal underneath one. A
  flier has to come down to something before it can bite it.
- **Attacking the legs**, above.
- **Browsing.** Forage grows at a height. There is no browse action and no second
  kind of food: some of it is simply over some animals' heads, and `neck_lift` is
  the one parameter that changes which.
- **Being carried.** A set of jaws is the only thing that physically joins two
  bodies, so it is the only thing that can hold one at a height it did not
  choose. The grip tethers the two elevations through the same mass share the
  horizontal correction uses — you cannot jump out of something's mouth.

**What is drawn, and what is true.** The simulation stays on the plane; only the
picture moves. A body is drawn lifted up the screen by its height, its shadow
stays on the ground, and the growing gap between them is how altitude reads. That
is not new — feet have been drawn at a fake `lift` above their gameplay position
since the gait was written — it is that same lie told about the whole animal.
`Posture.PERSPECTIVE` is the tilt, and it is the only constant in the game that is
presentation rather than simulation.

Not built, for want of a world rather than for want of the layer: pouncing from
trees needs trees, and burrowing needs terrain. Both are a height and a band away.

### Posture

Every creature used to be sprawled — flat on the floor with its legs out to the
sides. There are three stances now, and they are one trait:

> **the angle the limbs are carried out of the ground plane.**

Everything else follows from it as a projection, which is the reason there is no
stance-width dial and no per-stance code path. A leg of length *L* held at angle
*θ* puts its foot `L·cos θ` from the socket *seen from above* and holds the body
`L·sin θ` off the floor. Those are the same leg viewed twice, and between them
they are most of what a posture looks like:

| | tilt | plan reach | clearance | track | feet down | spine |
|---|---|---|---|---|---|---|
| sprawled | 12° | 98% of the leg | 20% | 96% | 2 | undulates fully |
| semi-upright | 50° | 64% | 77% | 41% | 2 | 30% |
| columnar | 72° | 31% | 95% | 10% | 3 | 8% |

A third projection decides how the limb *travels*, and it is the same cosine
taken out a second time. Coming up out of the ground plane and swinging round
underneath the body are one movement in a shoulder: a sprawled limb rows in the
frontal plane, so its foot is flung wide and the arc it sweeps is carried out
there with it, while an erect one pendulums parasagittally, directly beneath its
own shoulder. **Track** is what is left standing out to the side — 96% of the
plan reach sprawled, a tenth of it columnar — and the rest is spent walking. So a
Lizard's feet fall in two lines well outside its flanks, a Cat's just outside,
and an Elephant's *inside* its own silhouette.

- **Sprawled** — a Lizard. Belly near the floor, feet flung wide, the whole limb
  visible, and a spine that does part of the walking: a sprawled stride is
  lengthened by the lateral wave, which is why it is the one stance that keeps its
  undulation at full strength.
- **Semi-upright** — a Cat. Feet drawn in under the body and the socket drawn in
  with them, so the upper bone disappears beneath the torso. That occlusion is not
  a decision to stop drawing part of a leg; limbs are drawn *under* the body, so a
  shoulder inboard of the silhouette is a shoulder the animal is standing over.
  Strong acceleration and flat, quick turns.
- **Columnar** — an Elephant. Legs as pillars, the body held nearly a whole leg
  clear of the ground, three feet down at all times and the diagonal beat mostly
  gone — a heavy animal ambles, it does not trot. It carves rather than turns, and
  it cannot leave the ground at all: nothing forbids it, its `leap_height` is zero.

Two things do *not* come from the projection, and both would be wrong if they did.
Limb thickness is priced off the bone rather than off its plan view, or a columnar
animal would be drawn on four spindles. And the stride is capped at what the
projected envelope can actually sweep — a stride authored against the bone is one
a foreshortened foot can never reach, so the trigger never fires and the leg is
towed for as long as the animal walks. That cap is derived, not authored, because
the two numbers that decide it live in different places: the stride is a species
trait and the envelope is a consequence of the stance.

How upright a build may stand and how far the view is tilted turn out to be one
decision made twice. In a true plan view an animal standing on legs held
underneath itself has no legs at all: every part of every limb lands inside the
silhouette. `Posture.PERSPECTIVE` is the only thing that separates them, which is
why bringing the legs in under the body is what forced it up from 0.13 to 0.22 —
and why a sprawled animal is completely indifferent to it. It is bounded at the
other end by what the whole picture is registered to: a body is drawn where the
simulation puts it and its legs hang below that, so past a certain tilt a tall
animal's feet are drawn clear of its own silhouette — all four below it rather
than two either side — and there is nothing left to walk between. Lifting that
ceiling means registering every body to the ground rather than to itself, which
is a different picture and has not been done.

Posture also feeds the section above it. Clearance *is* how tall the animal is, so
the height bands, what its jaws can reach and what can reach its body are all
downstream of the same one angle.

### Gait

Purely reactive, no timeline. Each foot has an ideal position derived from the
body’s current pose; a planted foot stays nailed to the world until it drifts
further than `stride_distance` from that ideal, then arcs to a spot slightly
*ahead* and re-plants. Step frequency therefore falls out of speed for free, and
an idle creature is genuinely still.

#### A leg is solved from the foot up

A limb runs from a socket the body holds in the air down to a foot standing on
the floor, so its two bones span a real vertical gap. That gap is what is solved:
FABRIK runs inside the limb's *own plane* — the one containing the socket, the
foot and the body's fore-aft axis — with the bones at their true length. On a
sprawled animal that plane is very nearly the ground, so the elbow folds backward
across the floor; on a columnar one it is very nearly the sagittal plane, so the
knee folds forward through the air beneath the body. Nothing chooses between
them: the plane is spanned by where the foot is and which way the joint bends, so
it tilts up as the limb does. It is also why nothing has to guard against a knee
buckling through the torso any more — a joint folding fore-and-aft cannot.

So a limb has three parallel readings and only the first is authored:

* **`plan` and `heights`** — where each joint is on the ground plane and how far
  above it. This is the limb, and bone lengths are exact here.
* **`joints`** — where the picture puts it: `plan` displaced down the screen by
  the height it has lost. Drawn bones are foreshortened and their screen lengths
  change with every pose, which is what a projection does and what nothing may
  assert otherwise. `SimTest` measures rigidity through the air, not on screen.

#### The body stands on its feet

A leg is a fixed length, so a foot set down further from its socket is a socket
held lower. Nothing else decides how high a creature rides: `Gait` reads the
height off the feet that are actually down, per pair, and `Stature` takes it as
the body's clearance. Three things fall out of that one piece of arithmetic and
none of them is animated.

* **The bob.** A stance leg at constant length lifts the body as it comes
  underneath and lowers it as it passes. `VAULT_ABSORBED` is how much of that the
  animal takes up in its own joints — a stance limb is not a strut — and what is
  left is a rise and fall at exactly step frequency, largest on a sprawled build
  whose geometry is most sensitive to it and nearly absent on a columnar one.
* **Attitude.** Shoulders and hips are held by different bones, so an animal with
  shorter arms than legs stands nose-down without anything saying so.
* **No floating.** A body is never held higher than the legs under it can reach.
  Take away some of what they can extend to and it comes down.

Foot clearance during a step is derived on the same terms: a real height in world
pixels, sized as a share of how high the body is standing, with the authored
`step_height` kept as a floor. That is what lets an elephant step over what a
lizard walks around — and, because it is a height rather than a screen offset, it
is the number something small has to be shorter than to pass underneath.

#### Routing round obstacles

Each upper bone, lower bone and foot is also tested as a capsule against every
other creature's tissue-aware body, on the ground plane and carrying the band of
heights it occupies. A penetration shifts the foot target and
the two-bone chain is solved again, repeatedly over a small bounded pass. This
makes the knee fold and a planted foot slide around the obstacle while FABRIK
continues to guarantee exact bone lengths. The correction is written back to
the gait's world-space foot state, so it persists rather than snapping into the
obstacle again next tick. A destroyed limb or a hole in the obstacle stops
colliding, and so does anything at a height this piece of leg does not occupy.

Limbs remain kinematic against the body they route around — being walked into
does not shove the leg aside. The reverse is not true and cannot be: a leg is the
one structure that spans the whole gap underneath an animal, so it is the only
part of a tall one a low one can reach, and a body is pushed out of any leg whose
band it shares. That is the pass a lizard meets on its way past an elephant.

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
— and each cell is a stack of five tissues in *depth*, because top-down means
you are looking down through them: skin over fat over muscle over bone over
whatever organ lies beneath. A bite spends a penetration budget strictly
outside-in, so nothing under a layer can be touched until that layer is gone,
and the colour of a cell is simply whatever is now uppermost in it. Skin holds its dark surface as a continuous membrane until it
tears; exposed muscle darkens as it is depleted and carries close longitudinal
fibres so it reads as dense tissue rather than a coloured tile.

The lattice is not an overlay on the creature — it *is* the creature. The body
is drawn cell by cell rather than as a silhouette with the wounds painted over
it, which is the whole reason a wound can be a hole (see below).

Fat sits between the two outer layers and is the only one that is not simply
material to chew through: every hit point of it spends **1.5** of the incoming
penetration, so a padded animal is not merely carrying more tissue — the same
jaws arrive at its muscle *shallower*. That is the whole difference between fat
and thicker skin, and it means a heavy creature is protected by its build rather
than by a toughness number. `fat_reserve` scales it per species, over a profile
that is thickest at the trunk and thins toward the head, tail and feet, so it is
body shape as much as armour — and it is part of what the creature weighs.

Skin is a thin, stretchy rind and muscle is where the fight is. How far into
that stack one bite gets is not a property of the bite but of the mouth taking
it — see **Teeth, and the mark they leave** below. At the default `bite_damage`
and the default dentition, the jaw's own bearing strips skin across the whole
mouthful while the teeth punch several times deeper wherever they land, so a
bite always *opens* the body; grind the same mouth blunt and it stops breaking
through at all.

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
- **A bite selects cells by testing their solved world geometry against the
  mark.** The body-space mapping is curved, tapered and per-tick, and has no
  cheap inverse; the direct test is exact, needs no special case at the snout
  cap or the elbow, and lets one bite straddle several structures — jaws closing
  on a flank catch the leg over it, which a query routed through a single hit
  region could not express.

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

### Anatomy, and what a body can still do

The lattice above says what a creature is *made of*. This says what it can still
*do* with what is left, and the two are deliberately never the same question:

```
    anatomy   ->   functional body state   ->   procedural animation
    (cells)        (strength, control,          (gait, spine, IK)
                    stability, range,
                    load, perfusion)
```

The animator never learns what happened to the creature. There is no wound list
for it to consult and no injured-walk anywhere to switch into. It asks a limb how
strong it is and how well it is commanded, gets a number, and the ordinary gait
does the rest. **Limping, dragging, weakness, instability and collapse are not
implemented.** They are what the existing movement does when the numbers it reads
every tick stop all being 1.0.

The seam is also what makes two different injuries different. A leg whose muscle
has been eaten and a leg whose nerve has been cut are both weak; only this split
lets the second one be a leg that is undamaged, perfectly healthy, and does not
answer.

#### One description of the animal

[`BodyPlan`](scripts/creature/BodyPlan.gd) is the only file that names a body
part. It owns the lattice's dimensions, the skeleton's layout, the fat profile,
where the organs sit, which cells belong to which region, and how the two supply
networks are plumbed. Everything else is mechanism: erosion, connectivity,
consequence, animation — and none of it mentions a limb, a rib or a tail.

A creature with six legs, wings or no tail is a different plan and nothing else.

#### It is all cells

Skin, fat, muscle, bone, brain and heart are layers of the same depth stack, in
the same lattice, damaged by the same bite. Nerves and vessels are not a layer:
they are *runs through* cells, and their condition is read off the tissue they
pass through rather than stored. Nothing is ever flagged as injured. A bite
erodes cells; every consequence below is worked out afterwards, from the cells
that survived. That is what keeps the anatomy and the functional state from ever
disagreeing, including in cases nobody anticipated.

#### The organs are protected by being behind something

Bone stops a bite dead, because there is nothing behind it to reach — so an organ
laid *under* bone in the same stack can only be got at by grinding through the
bone first. That is the entire protection mechanism; nothing anywhere says an
organ is hard to hit.

The brain fills the back of the skull cap, inboard of the cheeks. The heart sits
in the chest on a **rib** column, not between two of them. Both are asserted, not
intended: `AnatomyTest` fails if any organ cell has no bone over it, and it
re-checks after every single bite that while any skull remains, the brain under
it is untouched.

#### Two networks, one shape, different failures

```
  nerves    brain  ->  head -> thorax -> lumbar -> pelvis -> tail
                                |                    |
                              FL FR                RL RR

  vessels   heart  ->  thorax -> head, lumbar -> pelvis -> tail
                          |                        |
                        FL FR                    RL RR
```

Same topology, and what a region receives is what its parent received times how
intact its own run is. That one line is the whole of connectivity: cut anywhere
and everything downstream goes dark, with no rule written about limbs or tails.

They differ in two ways, both the plan's business. They are **rooted
differently** — so a broken neck silences a body whose heart is fine, and an
opened chest starves a body whose brain is fine. And the spinal cord runs
*inside* the vertebrae while the great vessels run against them, so a wound over
the spine that stops at the bone opens the vessel and leaves the cord alone;
only breaking the vertebra cuts the cord. Two injuries in the same place with
entirely different consequences, and neither is a case in any switch.

#### The skeleton is the rig

The anatomical skeleton and the animation rig are the same thing now. Each joint
of the spine solve is handed the tone of the vertebra at that station: sound, it
runs exactly the code it always did; ground through, it stops being held to the
bend limit and goes slack *there and nowhere else*. The last constraint pass
stays full strength regardless, so a broken back is a slack back and never a
stretched one. A limb hangs off two skeletons — its own bones and the girdle it
is slung from — and losing either takes its load-bearing to nothing however
strong the muscle on it.

#### Force is three things multiplied

```
    strength = surviving fibre  x  what the nerve delivers  x  what the blood keeps alive
```

Take any one away and the limb is weak. Muscle groups are actuators across
specific joints, so a shoulder eaten out and a shank eaten out are different
injuries that walk differently. Range of motion pointedly does **not** read
control — a denervated limb has its full passive range and simply nothing to move
it with.

#### Blood is the slow one

Perfusion follows the vessels quickly; tissue viability follows perfusion
slowly, and fails faster than it recovers. So a limb whose artery is cut does not
switch off — it weakens over the following several seconds. That is the one
behaviour a damage-number model cannot produce at all, and it is asserted as a
shape over time rather than as a value.

Bleeding has two sources worth different amounts: any open wound seeps, and a
severed vessel pours. A body losing only the first seals and slowly makes it up;
one losing the second runs out. That is bleeding to death, with no timer and no
injury class anywhere.

#### Dying is a collapse now

A creature whose brain is destroyed stops instantly. One whose heart is destroyed
keeps going, and then goes out several seconds later because nothing is feeding
its brain — same ending, arrived at from the other side.

Either way the body is **not** rebuilt. `Ragdoll.adopt` takes the limbs exactly
where the gait left them and the free spine solver picks up from the pose the
creature was standing in, with its momentum intact. So an animal killed on its
feet folds up from its own last pose rather than being swapped for a corpse — the
real collapse the ragdoll had been waiting for.

#### Coming apart

A part comes off when every tissue between it and the body is gone, and that is
one flood fill rather than five rules. A cell with anything left in any layer
conducts; a cell with nothing left does not. So bone, muscle, fat and skin all
hold a piece on, and it stays on for as long as *some* run of tissue still
reaches it — grind a leg's bone through and it hangs by its meat, take the meat
and it hangs by its skin, take that and it is off.

The largest surviving piece is the animal and the rest has come away from it.
That is deliberately not a rule about where a body's centre is: with no
privileged cell to be the creature, nothing can make a body disown itself by
eating one lucky place in it.

Nothing in the walk knows what it is looking at, which is the whole return on
doing it this way. **A leg, a shin, a tail and a head all come off through the
same line**, because none of them was ever named — the cut decides how much
leaves, and it takes tissue the bite never touched along with it. What is left
behind is *empty*, and empty is a state everything already understands completely:
an empty cell is not drawn, does not collide, cannot be bitten and reports no
reach.

One piece per surviving component, not one per severance. A closing that takes a
leg off at the shoulder and knocks the end off a tail has parted the animal into
three, and the components the walk already found are what make those two separate
things on the ground rather than one impossible object.

#### What comes off is a leg, not meat

A part that has come away has had *nothing done to it*. It arrives with every hit
point it was standing with a tick earlier — skin over fat over muscle over bone,
in the same cells, in the same pose — because being severed is not damage. It is
the same tissue, somewhere else.

So it enters the world through `CarrionField` rather than `ScrapField`, and the
difference between those two is a difference in kind rather than in size. A scrap
is meat: tissue a bite already destroyed, with no structure left to lose, which is
why walking over one eats it. A part is anatomy lying on the ground — it is bitten,
eroded and shed through the *same* code the body it came off is, because the rule
for how flesh gives under a bite cannot depend on whose flesh it is. `erode_stack`
and `coalesce_shed` are shared verbatim between the two, and a severed leg is drawn
through the same colour read as the leg it was, so it is not restyled by having
come off.

The rule this buys is a rule about nothing: **a severed part is never converted
into anything**, and nobody anywhere has to remember not to convert it. It becomes
meat when a mouth makes it meat.

#### Picking it up, and dragging it

Jaws that close on a part take it. That is a `Mouthful` and deliberately not a
`Grip`: a grip is a contest between two animals with a winner to work out, and
meat does not pull back. What replaces all of that machinery is possession.

A held part is *placed* by the jaws, and a loose one is *integrated* by the field
— the same division the rig already makes between a limb the gait is striding and
a limb nothing is holding out. Whether being placed reads as carrying or as
dragging is one division: the creature's strength against the piece's weight, in
the same Lizard units every other mass in the simulation is quoted in. A piece it
can lift is back at its mouth within a tick and rides wherever the head goes; a
piece it cannot is always behind where it was asked to be, and being always behind
*is* being dragged. There is no threshold and no second path. The same weight goes
into `_haul_factor`, so towing an Elephant's thigh costs what towing an Elephant costs,
for the same reason and through the same line.

The pull is split between shifting the piece and turning it exactly as a rigid
body splits an impulse off its centre of mass — and not symmetrically. Along the
arm from the hold to the centre it is pure translation, because there is no way to
rotate a thing toward yourself; across the arm it mostly swings, and the further
out the jaws have hold the more mostly. **That asymmetry is where bite position
enters the animation without anything animating it.** A leg taken by the ankle is
hauled along its own length and slews freely across it, so it trails and swings
after the animal; the same leg taken across its middle has no lever and is carried
level. Neither is posed and neither is a case.

#### Attached and held up are different questions

A limb whose bone has been ground through is still **on** the animal — the flesh
around the break is holding it there — and nothing is holding it **out**. So the
two are read separately and composed: attachment says the leg is still there, and
skeletal continuity says it can no longer stand on itself.

What falls out is a limb that bears nothing, is never asked for a step, and
*dangles*. The gait stops placing it, because a stride and a plant are both
answers about where to put a limb and there is nothing left to put this one
anywhere — and `Ragdoll`, which already existed to move a chain nobody is posing,
takes it instead. A living animal with a broken leg and a carcass with four of
them run the identical code on the identical limbs. There is no dangle mode, no
second softer walk, and no new solver.

That case is also what turned up a real bug in the ragdoll: its fold and envelope
limits were being applied *after* the bone-length projection, so whichever ran
last was the one that held. A settled carcass never showed it, because a limb
already inside both limits is left alone by them. A limb hanging off a socket that
is walking away from it is outside them every tick, and was being left a couple of
pixels long every time. Bones are now the last thing applied — the fold and the
sprawl are taste, the length of a bone is not.

#### Eating is two numbers

Biting, chewing and swallowing are not three modes with transitions between them.
There is no state machine anywhere in `Mouthful`. They are three readings of the
same two numbers — **where the jaws have hold of the piece**, and **how far the
piece reaches from there**:

* The piece **props the jaws open** by however much of it will not fit inside
  them. `reach / gape`, clamped. That is what biting a thing too big for your
  mouth looks like, and it is a division rather than an animation.
* A chew that cannot swallow **works the piece in**: it goes out through the
  ordinary bite signal, so the world erodes the piece and scatters what came off
  with no idea it was chewing rather than biting, and then the jaws re-seat a step
  deeper into what survived. Repeat and a long piece is eaten end-first instead of
  being gnawed forever at the spot it was first grabbed.
* Once what is left reaches no further than the mouth is deep, the next closing
  **swallows** it, because there is nothing left to stop it going down.

So an Elephant bolts a Lizard's foot in one closing and a Cat gnaws at an
Elephant's thigh for a long time, and neither of those is written anywhere. Food
size, food shape, mouth size and bite position all arrive in that one comparison,
and none of them is named in it.

A swallow is visible in the body it passes down. The distension is written into
the width profile *before* the body is built, so it is not a lump drawn over a
silhouette: the lattice tessellates the swollen cross-sections, the collision
capsules widen, and the creature briefly weighs more because there is briefly more
of it. The swelling travels back with the piece and the tissue closes behind it.

Chewing a piece through divides it, on the same rule that made it in the first
place — cells still joined to each other by surviving tissue are one thing and
cells that are not are another. The jaws keep whichever half they were holding and
the rest falls where it was. Nothing there knows what it is cutting either: a leg
chewed through at the ankle drops its foot for the identical reason the animal
dropped the leg.

#### A healthy creature pays nothing

`BodyState.impaired` is false while every number is nominal, and every consumer
short-circuits on it — the gait, the spine tone, locomotion and steering all run
the identical code path they did before any of this existed. It is a promise more
than an optimisation, and `AnatomyTest` checks it: an undamaged creature must
report all four limbs unmodulated.

The structural half — the cell walks — only re-runs when the lattice says it
changed, so an animal nobody has bitten never floods a network to be told its
nerves are fine. What runs every tick is about a hundred float operations of
supply and decline, because those move continuously while the body does not.

#### Looking at it: the Anatomy tab

`F3`, or the **Anatomy** tab beside **Field** at the top left, swaps the HUD's
field furniture for a specimen drawer — `AnatomyPanel`, with `AnatomyView` on the
slab. The whole of it is a *reading* of a creature; there is no anatomy model
behind the panel.

The specimen is the creature's own `TissueGrid`. Every quad on it is a cell,
taken from the world-space corners the lattice re-derives each tick and put
through one rigid transform — a rotation, a scale and an offset:

```gdscript
func to_panel(world: Vector2) -> Vector2:
    return _origin + (world - _anchor).rotated(_rot) * _scale
```

That is the entire relationship between the drawer and the animal, and it is what
makes the picture true rather than merely similar. The silhouette is that
creature's silhouette because it is tessellated out of that creature's cells; the
bend is the bend its spine is holding right now; a Cat is small and quick and an
Elephant is broad and slab-sided without either being drawn; a flank chewed open
is chewed open here; a leg that has come off is missing from both views because
it is missing from the lattice they share. The rotation presents it snout-up by
turning the mean direction of its own spine onto the page — re-orienting the
animal without straightening it, so the pose survives the presentation.

The colours are not a second palette either. `CreatureView.tissue_color` is the
one static that decides what a depth stack looks like, and the specimen, the
creature in the field and the meat on the ground all call it. What the drawer
adds is a **mask**:

```gdscript
static func top_layer(hp: PackedFloat32Array, base: int, visible: int) -> int
```

Switching a layer off in the list lifts it off the specimen, and the colour that
comes up underneath is whatever a bite that deep would have exposed — the same
outside-in walk down the same stack, asked to skip what the viewer has peeled.
Grain follows it: skin that has been lifted stops drawing its tension lines and
the muscle beneath starts drawing its fibres, because both are answers to the
same question about the same cell. Turn everything off and the body is still
there in the faintest wash, so a specimen with no layer selected still reads as a
body rather than as nothing.

The rest is what the anatomy stack already computes, drawn where it happens:

* **Vessels and nerves** are laid along the cells their conduits actually pass
  through, in the inks the `F2` overlay uses. Width and alpha carry `delivery` —
  what *arrives* — so a sound run still fades out behind a cut upstream of it,
  and a run broken at a cell goes dashed from exactly the cell whose flesh was
  taken. Blood travels in beats and nerve traffic in quick dashes, phase-shifted
  by depth down the tree, so the two read as different systems rather than as two
  colours of the same line.
* **Heart and brain** are marked at the cells they occupy, on a leader clear of
  the body, ringed by how much of the organ is left. An organ destroyed and taken
  with the flesh around it is not marked at all, because there is nothing there
  to mark.
* **Holes** are drawn as the rim of the opening — an edge with surviving tissue on
  the far side of it — and never filled. Outlining every destroyed cell would draw
  the grid of the wound instead of its shape.
* **Hovering a cell** reads out its region and its stack, layer by layer, listing
  only the layers that cell was built with: `THORAX · SKN 100 FAT 62 MSC 41 BNE 100`.

The four vitals under the layer list are the functional layer's own numbers —
brain, heart, `BodyState.bleeding`, and how many of the eighteen conduit runs are
cut off — and the header quotes `tissue.integrity()` against the words the body
uses for itself, so a collapsed animal says *Collapsed* rather than a percentage.
The chips at the bottom right pick which body is on the slab; the world names
them, since which creature is whose is the world's business and not the HUD's.

### Teeth, and the mark they leave

A bite is not a circle of damage. It is a set of teeth closing, and what those
teeth are decides everything about the wound.

[`Dentition`](scripts/creature/Dentition.gd) grows a mouth from four numbers —
how many teeth per arch, how long, how keen, and how wide the gape is. Two
arches are set in an arc around the head, upper and lower. Seen from above they
are *nested* rather than opposed: the upper arch is the wider of the two, so the
lower row meshes into the gaps of the upper and a closing set of jaws prints two
concentric rows of punctures. The arc is an ellipse rather than a circle,
because a mouth reaches further forward than the skull is wide — that is what a
snout is — while its corners can never be outside the head they are cut into.

Everything else falls out of those four numbers:

- **Type** is read off where a tooth sits and how keen the species is. The front
  of the arc is incisors, the canine station carries a fang if the mouth is keen
  enough to have one, blades run back from there as far as keenness reaches, and
  the rest is crushing molars. A needle-mouthed animal is therefore fangs and
  blades nearly to the corners and a blunt one is cusps and millstones, without
  either being listed anywhere.
- **Contact patch** is the slot a tooth has to itself, narrowed by its own
  keenness and shaped by its type: a carnassial is a blade set edge-on and cuts
  a slit, a canine is round and punches a hole, a molar is nearly as thick as it
  is long and presses a bruise.
- **Penetration is force over that patch**, so it is not a parameter at all.
  `bite_damage` is what the jaws close with; the teeth decide what it is spent
  on. Five needles have a fraction of the contact area of twenty cusps, so the
  same jaws drive several times deeper into the flesh through them.

A closing produces a [`BiteMark`](scripts/creature/BiteMark.gd): a list of
contact patches with a world position, a size, an axis and a penetration apiece.
That is the *whole* description of a bite anything downstream is given. The
tissue lattice erodes cells by asking the mark how deep it is over each of them,
and the red print in the world is drawn from the same list of patches — so the
shape stamped on the flesh is the shape that ate it, and there is no way for the
two to disagree.

Both halves of what jaws do are in the mark. The teeth punch; the jaw then bears
on everything the arch encloses, shallow and broad, because a bite is a closing
rather than an impulse. Which half a species does its damage through is the same
keenness number again — a blunt mouth is nearly all bearing, a keen one nearly
all puncture. So a Cat's seven blades slit open flesh an Elephant's six molars
would only bruise, and it does it by having *less* tooth rather than more.

One consequence worth stating: a tooth's contact patch is finer than a lattice
cell, and that is not a rounding error to be smoothed away. A patch whose centre
falls inside a cell marks it outright — the cell is the smallest piece of flesh
there is, and a puncture cannot destroy less than one. Sampling cell centres
alone would have made the finest points *least* likely to connect, which is
exactly backwards.

### The lunge

A click does not resolve a bite. It starts an animation with a hit frame: a
0.07 s wind-up that rocks the head back and opens the jaws, a 0.08 s forward
throw, and a 0.18 s settle. The bite resolves at full extension, against the
pose the snout actually reached, and the jaws shut on that same frame.

**The bite lands where the mouth is.** There is no bite volume projected out in
front of the face any more: the mark is stamped around the head's own tooth arc,
so `bite_reach` is the distance the head is genuinely *thrown* and the whole of
what a creature gains by lunging rather than standing still. The jaws have to
arrive. The teeth are drawn while the mouth is open — the generated ones, at the
seats the arc puts them on — so what you count on screen is what is about to
bite; a shut mouth from directly above is still just a head.

That change needed one thing the contact solver was not doing: **an open mouth
is not a solid.** Jaws part *around* what they close on, so while the gape is
open the head cap reports itself as tissue that is not there, through the same
channel every bitten-out hole already uses. Without it a lunging creature would
shove its prey away with its own face and then bite the gap it had just opened.
The head is solid again on the frame the jaws shut, which is the frame the bite
resolves — so a miss is shouldered apart immediately, and a hit is held by the
tether instead.

Where the old world cue printed the word **Bite**, the impact now leaves the
mark itself: each tooth's contact patch in red, sized as it was sized and
darkened by how deep it drove, over the faint broad bruise of the jaw behind
them. A print over unbroken ground is a tooth that missed, and it should be —
that is the mouth being read, not the damage being illustrated.

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
| Cat | 0.81 | 1.39 | 0.79 |
| Lizard | 1.00 | 1.00 | 1.00 |
| Elephant | 23.44 | 10.65 | 20.00 |

Two consequences fall out of that shape and neither needed a rule of its own.

**Damage is not just cosmetic any more.** The integrity term is the same lattice
number the biomass readout shows, so a creature eaten half open is lighter, gets
shoved further in every contact, and is weaker at everything its strength buys.
Its jaws weaken too, on the surviving *head* tissue specifically — chew a
predator's skull open and its bite goes with it.

**Both derived quantities are areas, and mass is a volume.** Strength is
literally `mass^(2/3)`; bite force is the head's cross-section, which grows the
same way. So a big creature is stronger and bites harder outright while being
weaker *per kilo* — the square-cube law, and the whole reason a Cat latched
onto an Elephant can barely walk while the Elephant tows the Cat without
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
  out first, and that single comparison is the whole of why an Elephant strips
  meat off prey a Cat can only be shaken from. Past the yield point the pull
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
for the nearest surviving tissue. How far they can search is derived rather than
chosen: they have to clear the crater the last mouthful left, which is a gape
across either side of the bind, plus their own gape beyond that. Without the
re-seat a strong bite would lose its grip *faster* than a weak one, since the
better it works the sooner the cell it was bound to is gone; without the reach
being tied to the crater it would lose its grip *because* it chewed well.

The new hold is the nearest sound flesh, and the tether's rest length is capped
at the jaws' own gape rather than at however far the search went. A re-seat that
recorded the search distance would leave the hold a leash — one the next
mouthful would then be taken at the far end of, and the one after that further
out again. Re-seating is what turns a latch into
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
| Elephant on Cat | tows it 554 px | holds; it makes 27 px | holds |
| Elephant on Lizard | tows it 542 px | holds; it makes 29 px | holds |
| Cat on Lizard | tows it 486 px | holds; it makes 339 px | holds |
| Lizard on Lizard | tows it 333 px | towed 273 px along with it | holds |
| Cat on Elephant | *leg*; moves it 5 px | *leg*; dragged 336 px behind it | *leg*; holds |
| Lizard on Elephant | *leg*; moves it 3 px | *leg*; **torn off at 1.1 s** | *leg*; holds |

Read the diagonal: the same tether, the same three numbers, and an Elephant is
unshakeable while nothing lighter can move one at all.

Two rows are marked *leg*, and that is the vertical layer arriving in the middle
of the combat table. An Elephant's body stands 126 px off the ground and a Cat's
jaws reach 101 px, so head-on there is nothing there to bite: the only hold on
offer is a foreleg, because a leg is the one structure that runs all the way down
to the floor both animals are standing on. Nobody wrote a rule about legs — see
**Height** — and the row where the Elephant simply walks away is the reading
that follows: a hold at ankle height on something twenty-three times your weight
comes off when it decides to leave.

Note also that **dragging tears nothing** — towed prey travels *with* the jaws, so
the two never come apart and the load stays near zero. Tearing is bought with
struggle, by either party.

The last column is currently the flat one, and it is the open balance call in this
system rather than a claim: none of the three shipped bodies loads a set of jaws
hard enough by thrashing to part its own flesh. The mechanism is intact and
`CombatTest` measures it — the failure prints the peak pull against the yield
point it would have to beat — but the margin between the two is a number nobody
has settled yet. It is the one red check in the suite.

## Tuning

Press `F1` for live sliders (generated from `CreatureParams.SCHEMA` — add a
property plus one schema row and it appears automatically). Three presets ship in
the panel, one per posture: **Lizard** (sprawled), **Cat** (semi-upright) and
**Elephant** (columnar).
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
| Sprawled, semi-upright or columnar | `posture` — one trait; stance width, clearance, occlusion, undulation, support and turn character all follow |
| Sprawling vs. tucked legs *within* a stance | `stance_width`, `stance_reach`, `arm/leg_length` |
| Taller, or reaching higher | `leg_length` up (the body rides on it), `neck_lift` up (the jaws do) |
| Something that can jump | `leap_height` — a multiple of the animal's own standing height; 0 is a body that cannot leave the ground |
| Something that can fly | `wing_lift` up from 0 — the only thing separating gliding and high flight from a leap |
| Marching vs. loose legs | `diagonal_coupling` (1 = strict trot, 0 = independent) |
| Wider / tighter leg sweep | `limb_swing_deg`, `limb_max_reach` |
| Jaws that close harder | `bite_damage` up — force at the jaws, not depth in the flesh; the teeth decide what it becomes |
| Punctures instead of bruising | `tooth_sharpness` up and `tooth_count` down — less tooth on the flesh is more pressure through it |
| Crushing instead of cutting | `tooth_sharpness` down — a blunt mouth does its damage through the jaw's broad bearing rather than through its points |
| Fangs and blades further back | `tooth_sharpness` up; tooth *type* is read off it and off position, never set |
| A longer reach | `bite_reach` up — this is how far the head is thrown, and it has to arrive |
| A wider mouthful | `bite_radius` up (the gape's forward reach, capped against the skull) and `jaw_gape_deg` up |
| Heavier for the same silhouette | `density` up — and remember the width sliders already move mass |
| Strong for its size (drags more, is dragged less) | `muscle_power` up |
| Padded — heavier, and harder to reach the muscle of | `fat_reserve` up |
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
coverage in itself. The shaped glyph metrics are retained with the mark, and
every visible glyph sharing a font-atlas texture enters one triangle array; a
saturated read is a handful of atlas submissions rather than hundreds of
independent text draws. The layer sits above the sight treatment and below the
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

Fourteen headless checks cover controls, movement feel, simulation, rendering,
UI, combat, sight, smell, hearing, anatomy, feeding, the bodies in the habitat,
the vertical axis and the three stances:

```sh
godot --headless --path . --script tests/ControlsTest.gd # input/head-look isolation
godot --headless --path . --script tests/MovementFeelTest.gd # reverse/steering behaviour
godot --headless --path . --script tests/SimTest.gd      # simulation invariants
godot --headless --path . --script tests/RenderSmoke.gd  # every draw path
godot --headless --path . --script tests/UIInteractionTest.gd # HUD interactions, anatomy tab
godot --headless --path . --script tests/SightTest.gd    # perception/reset/render order
godot --headless --path . --script tests/SmellTest.gd    # scent persistence/trails/reads
godot --headless --path . --script tests/HearingTest.gd  # arrival/occlusion/events/reset
godot --headless --path . --script tests/CombatTest.gd    # bite/anatomy slice
godot --headless --path . --script tests/RagdollTest.gd   # the dead body
godot --headless --path . --script tests/AnatomyTest.gd   # structure -> function -> gait
godot --headless --path . --script tests/FeedingTest.gd   # severed parts, carrying, eating
godot --headless --path . --script tests/HeightTest.gd    # the vertical axis and what it gates
godot --headless --path . --script tests/PostureTest.gd   # the three stances, from one angle
godot --headless --path . --script tests/LocomotionTest.gd # legs solved from the foot up
```

`HeightTest` is weighted toward the seams rather than the arithmetic — the places
a second question is now asked after the horizontal one, and where getting it
wrong would either break the flat game or quietly do nothing at all. The four
states first, driven straight through `Elevation`, because they are read rather
than stored and a state machine reintroduced by accident would show up there: a
wingless body can only ever be grounded or leaping however hard the climb is
held, a winged one passes through low flight into high flight and cannot climb
past its own ceiling, and folding the wings mid-air puts it back to leaping. Then
the mechanics: a sprinting Cat that shoves a Lizard 46 px through it on the ground
shoves it 0 px over it; the identical bite that connects at point-blank range
finds nothing when its victim is 400 px up — while the purely horizontal query
still finds it, which is what proves the vertical gate rather than a drift between
the two; a Lizard's reach clears an Elephant's legs and stops below its belly, and
thirty bites at that height open no holes in the body while one bite at the right
height goes straight through it; and a short neck eats the forage at its feet and
not the forage over its head, until `neck_lift` is turned up. Last, the guarantee
the layer rests on: with everything on the ground and an unbounded reach, the same
bite removes the same tissue it always did.

`PostureTest` starts with the projection, since the rest is downstream of it: each
stance draws its feet in further and stands higher than the one before, and reach
and clearance are exact complements of one leg. Then that the trait alone is what
does it — the same animal with the same numbers and a different `posture` stands
three times higher on the same legs. Then the things a player would see: feet that
land outside the silhouette in every stance (a leg you cannot see is a leg the
animal does not appear to have) over a shoulder that is inside it wherever the
stance insets one; a columnar belly above a sprawled animal's entire body; sway
through the spine falling away as the legs take the stride back off it; two feet
up for the low stances and one for the columnar; and a columnar turning circle
more than twice a semi-upright one but still finite. Finally the two things it
would be easy to get wrong by taking the projection too literally: the same leg
held upright is exactly as thick and exactly as long a bone as it was, and every
shipped stance can still walk.

`FeedingTest` is weighted toward the seams rather than the parts. That a severed
limb enters the world with the tissue it was standing with to the hit point and
the scrap field stays empty; that it can lie there for four seconds and still be a
leg, and that one closing of a set of jaws is the whole difference; that the same
piece made sixty thousand times heavier answers the jaws a third as readily,
costs its carrier half its travel, and still cannot get further away than the mouth
can reach; that a piece too big props the jaws open and the same piece chewed down
lets them close; that chewing works the hold in so the reach falls; that what fits
goes down, feeds the animal by the tissue in it and stops being in the world; that
the throat distends around it, travels with it and closes behind it; that chewing
straight through the middle leaves two pieces with the jaws holding one; and that
meat is still your own meat after being severed, carried across the world by
somebody else and chewed into scraps there.

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

Food pellets and torn scraps are gathered into the scent field as cohorts. If
their deposits cross the trace ceiling, thinning and rebuilding the spatial bins
happens once after the cohort rather than once for every piece. Their world
presentation follows the same rule: pellets share one triangle array, as do the
disconnected muscle strands across all visible scraps.

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
the three of them and an Elephant is at least three times a Lizard; the heavier
creature is stronger outright but weaker per unit of mass, which is the only
thing that says the square-cube exponent is still in there; an Elephant's jaws are
in a different league from a Lizard's. Doubling a torso's width alone has to move
mass — otherwise mass is really a slider spelled differently — and chewing a
creature open has to take mass and strength back off it.

Then the grip, one assertion per outcome the three numbers are supposed to
produce. An Elephant holding a Cat that does nothing for three seconds leaves it
untouched, and then tows it without hurting it — those two are what say a hold is
a hold. The same jaws are not shaken off by a thrashing Cat, and the struggle is
supposed to tear meat out of it: integrity falls, scraps enter the world, and the
lattice is left with *holes*, since a tear is a discrete failure of the tissue and
not a uniform thinning. Those last two are the suite's one red pair — see the
tearing table above. Stop the thrashing and the wound stops growing.

Reversed, the vertical layer changes the question before any of that: a Cat cannot
reach an Elephant's body at all, so it takes the leg, and what it gets for that is
a hold it keeps and an animal it cannot move — it keeps a twentieth of its own top
speed trying, and never opens a hole anywhere but the leg it is on. Last, a bite
under load goes in shallower than the same bite when free. Weight gets its own
pair: two identical creatures still split a contact exactly down the middle, and
an Elephant shoves a Cat several times further than the reverse.

`AnatomyTest` is weighted toward the seam the whole system exists to create:
that *what happened* and *what it does* are two different questions. It checks
that the body is built out of the structures it claims to be — every cell skinned,
fatted and muscled, bone a frame rather than a plate, every region populated, fat
laid as a profile rather than a constant. That the organs are enclosed: no organ
cell may have anything but bone over it, and while any skull survives the brain
under it must be untouched, re-asserted after every bite rather than only at the
end.

Then the claims that are easy to write and hard to keep. Fat cushions — the same
bite leaves more muscle on a padded body than a lean one. The two networks fail
differently: a wound over the spine that stops at the bone opens the vessel and
leaves the cord alone, while grinding the vertebra through silences the hind legs
and leaves the forelegs talking. Cutting a limb's nerve leaves its muscle, bone
and passive range intact and its force at zero. Losing a blood supply is a
decline rather than a switch, so it is asserted as a shape over time: still strong
on the tick it is cut, most of the way down nine seconds later, with the limb
still taking orders the whole way. A broken bone costs load-bearing without
costing muscle.

And that all of it reaches the gait. The weak leg's foot moves through its swing
at under 80% of the sound leg's — a limp, measured as the asymmetry it actually
is rather than by looking for one. A limb with no nerve takes *zero* ticks of
steps across four seconds of walking, never lifts, and is still held inside the
envelope its own bones allow: dragged, not abandoned. Two dead hind legs cost
real ground. A destroyed brain collapses the body in place, within 30 px of where
it was standing. A destroyed heart does not kill on the same tick and does within
thirty seconds. A limb eaten off at the socket stops being solved, stops
occupying space, stops answering the bite query, and leaves meat behind.

The check that earns its place most is the dullest: an undamaged creature must
report itself entirely nominal, with all four limbs unmodulated. It is what
guarantees a healthy animal runs the same code it did before the anatomy existed —
and it is what caught the diagonal-coupling gate, where a dead limb was being
pulled into its partner's step and picking itself up on alternate beats.

`UIInteractionTest` covers the anatomy tab as a *view of a creature* rather than
as a widget, because the ways it can break are all ways of quietly stopping being
one. That it opens on the body the world handed it; that the specimen is framed,
snout-up, with every station of the animal on the page — the check that fails when
a creature changes size; that peeling the skin reaches the layer under it, read
through the same static the field draws with, so a panel that started inking its
own body is caught; that pointing it at the other creature moves both the specimen
and every readout; and that a body bitten open stops reading as intact. `RenderSmoke`
then holds the tab open over a target that has been chewed to the bone and had a
leg taken off, and fails if the specimen it drew had no holes in it — a clean run
over an intact body would exercise none of the paths worth smoke-testing.

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

- Creatures collide with each other, but nothing else does: no terrain and no
  ground to stand on other than the notional plane at height zero. Everything
  vertical is a scalar and a band — see **Height** — and it is drawn as a
  screen-space offset plus a widening shadow gap rather than rendered in three
  dimensions.
- Because of that, a body drawn at height is drawn away from where it is. The
  simulation stays on the plane, so a leaping creature's silhouette sits above its
  own hit position by `height × PERSPECTIVE`; aiming at a tall or airborne animal
  means aiming at its shadow. This is the same compromise the gait has always made
  with a foot's `lift`, applied to the whole animal, and it is the price of not
  having a third axis in the solver.
- The vertical layer has no world to act on yet. Pouncing from trees and burrowing
  beneath danger both fall out of the same scalar and the same overlap rule, but
  there are no trees and no terrain to do either with.
- Nothing flies. Gliding and high flight are implemented, tested and reachable
  from the tuning panel — `wing_lift` above zero is the whole of it — but no
  shipped species has wings, and no body plan draws a pair.
- Contacts have weight behind them but no momentum. Mass decides who yields and
  how much speed a contact sheds, so a heavy creature can shoulder a light one
  aside — but nothing is transferred: a creature that stops pushing stops moving
  whatever it was carrying, and there is no impact, recoil or knockback.
- A severed part is a rigid body, not an articulated one. It keeps the exact pose
  it was solved in on the tick it came away and moves as one piece from then on, so
  a leg torn off mid-stride stays bent at that knee forever. It has no rig to bend:
  the two-bone chain that posed it belongs to the animal, and the piece has left.
- A severed part does not collide with anything. It lies where it fell and
  creatures walk over it, exactly as scraps do. It can be bitten and carried, but
  it cannot be tripped over or shouldered aside.
- Nothing eats without being driven. A part lying in the world is picked up and
  chewed by working the same button a bite uses, so the whole feeding loop is the
  player's; the habitat's other body has no AI to want it. Scraps and pellets are
  still swallowed by proximity, which is the one thing that happens by itself.
- A swallowed part is worth its own tissue while a scrap is worth one, so a piece
  eaten whole feeds considerably more than the same piece chewed into scraps and
  picked up. That is a balance number rather than a mechanism, and the scrap side
  of it is the one that predates this.
- A part still hanging by soft tissue dangles from its socket rather than from the
  break itself, because the rig underneath it is a two-bone chain from the socket
  and has no joint where the bone actually parted. A limb broken at the shin
  therefore flops from the shoulder with a loose shin on the end of it, which reads
  correctly, rather than pivoting about the break. Splitting the chain at an
  arbitrary station is a rig change, not an anatomy one.
- Nothing in the habitat is alive. A body placed there is simulated as a carcass
  rather than parked as a living creature, which is honest about the missing AI
  but is still the absence of one: it never gets up, never reacts, and the only
  things that move it are other bodies and the jaws holding it.
- A body *placed* in the habitat still settles into its resting pose at build
  time rather than falling into it — it was never alive to fall. A creature that
  dies while running is a different path and does collapse properly, from its own
  last pose.
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
- The default gape is comparable to the body's half-width, so a mouthful near
  the midline tends to take the full width of the body and the jaw's bearing
  patch reads as a band. The teeth themselves stay localised on it whatever the
  gape is.
- The body fill is drawn as a strip of quads between spine cross-sections, so a
  very sharp bend can overlap slightly on the inside of the curve. It is
  invisible at opaque fill and avoids depending on concave polygon
  triangulation.
