# Evolution v2 — Unified Body Design & Implementation Plan

**Status:** Draft for review · **Reference animal:** domestic cat · **Scope:** replaces AnatomyLattice + TissueGrid + the three partial skeletons with one unified body model; keeps the UI shell and the locomotion behaviour.

---

## 1. Goals

1. **One model.** What is hit is exactly what is displayed. Physics, damage, mass, and rendering all read the same structure; there is no translation or mirroring step anywhere.
2. **Simpler physics.** One chain system (spine + neck + tail + limbs), one gravity, one centre of mass, one integrator.
3. **Performance.** Cost scales with *segments and rings*, never with *volume in cells*. Damage is written once in body space; posing never re-carves anything.
4. **Elegance.** Biology is data, physics is process. A creature is one resource file; every physical behaviour (mass, power, compliance, wound response) is *derived* from that file, never authored twice.

### Laws carried over from v1 (learned the hard way, non-negotiable)

- **One owner per quantity.** One gravity/integrator, one centre of mass, one mass census. If two systems disagree about a number, the design is wrong, not the tuning.
- **Fix the mechanism, not the look.** "Looks off" means the rendering is lying about the state.
- **Nothing pose-derived in build inputs.** The body model is built from rest-pose data only; the live pose only *transforms* it. (This is what made carving re-fire 16 ms mid-gait in v1 — in v2 it is impossible by construction, keep it that way.)
- **Requests vs. delivery.** Speed is what the legs deliver; thrust derives from push and fades with effort. No hidden acceleration parameters, no reading solved-gait state to compute drive.
- **Tests state claims, not constants.** Calibrated numbers are re-pinned per body; the claim ("Froude quotes stance height", "stride ≤ plan reach") is what's ported.

---

## 2. Architecture overview

Three layers, strictly one-directional reads:

```mermaid
flowchart TD
    A["ARMATURE — unified Verlet chain graph\n(sticks, joints, constraints, gravity, contacts)"]
    C["CORPUS — layered body model in bone space\n(rings: bone/muscle/fat/skin per station+sector,\norgans/vessels/nerves as features,\nHP lives here — the one census)"]
    S["SHELL — everything that reads\n(SpecimenMesh skinning, panels via BodyReadout,\nhit tests, senses)"]
    C -- "derives mass, COM, strength,\ncompliance → drives" --> A
    A -- "pose transforms rings\n(never rebuilds them)" --> S
    C -- "tissue state at (chain,t,θ,d)" --> S
```

- **Armature** replaces: Spine.gd's Verlet core + Limb joint chains + Stature's neck arc + Ragdoll — one graph of sticks and joints.
- **Corpus** replaces: AnatomyLattice + TissueGrid + TissueForm + BodyShape + the census halves of Physique/Plumb. It is *the* census: mass, damage, and shape are the same numbers.
- **Shell** keeps: SpecimenMesh's ring-skinning approach (now reading Corpus directly), the HUD dock and drawers, CreatureView draw order. Panels are ported onto a small `BodyReadout` interface (§8).

The key structural change from v1: **the census moves from world space to body space.** v1's lattice was cartesian cells in the posed world, so posing moved flesh, carving was pose-sensitive, and damage had to be mirrored between two grids. v2's census is polar cells (station × sector × layer) attached to chain segments. Cells never move in body space; posing is just placing ring frames along the posed chain. Carving happens once, at build. Damage writes into the same cells that mass and rendering read.

---

## 3. What "schema" means, concretely

The schema is the answer to: *what fields, at what resolution, in what coordinate system, are the authoritative description of a creature's body?* Everything else in the game is either a process that updates those fields (physics, damage) or a view that reads them (mesh, panels, senses). Getting it right first matters because every phase of the rebuild reads it; changing it later means re-touching every phase.

It has five parts, each specified below with options where there is a real choice:

1. The **chain graph** — which chains exist, how many nodes each has, how they attach (§4).
2. The **ring model** — how cross-sections and tissue layers are represented along each chain (§5).
3. The **feature set** — organs, vessels, nerves as coordinates in body space (§6).
4. The **derivations** — how mass, COM, strength, compliance fall out of 1–3 (§7).
5. The **authoring format** — the single file a creature is tuned from (§7.5).

---

## 4. Schema part 1 — the chain graph

### 4.1 Dimensionality — DECISION

The v1 spine is a 2D plan-view chain (`PackedVector2Array`) with heights carried per-cell, and all the gait mathematics (stride discs, plan reach, sway budget, Froude) is plan-view math.

- **Option A — full 3D Verlet.** Nodes are `Vector3`, constraints solve in 3D. Cleanest on paper; but every piece of ported locomotion math (stride/stance/sway share one plan disc, posture-tilt foreshortening, plan-limit caps) must be re-derived, and 3D chain stability under ground contact is a research project of its own.
- **Option B — 2.5D (recommended).** Nodes are `Vector3` where XY is the plan and Z is height, but constraint solving is plan-dominant: distance/angle constraints act on the plan projection exactly as v1's solver does, while Z is governed by the stature/terrain channel (stance height, clearance, terrain, leaps, head carry). This is what v1 already converged on ("posture and height are one angle", "heights live on cells") — v2 just makes the Z channel a first-class per-node value on the chain instead of a per-cell afterthought.

**Recommendation: Option B.** All bite/combat addressing is still fully 3D (§9) because ring frames are 3D; only the *constraint solver* stays plan-dominant. Revisit full 3D only if a future feature (climbing, swimming rolls) demands it.

#### 4.1a The revisit, exercised — attitude as a body frame, not a 3D solver (2026-08-12)

The clause above was taken up for exactly the reason it names, and answered *without* Option A. The complaint was real: a v2 body had three dynamic degrees of freedom (plan XY and yaw) and one assigned vertical, so it could not be pushed down, could not sink on one side, and could not fall onto its flank — `collapse` dropped every node flat at its plan position, and `Clash` computed a true 3D contact point and then discarded its height, because there was nothing to hand it to.

The answer is that **rolling a body is not a property of its constraint solver.** The plan-dominant chain solves the body's *shape*; what was missing is dynamics on the body's *frame*. So a third state joins the two the mover already integrates:

- **`motion/Keel.gd` — one attitude owner**, holding `roll` with its rate and torques, beside the one pull (`Gravity.PULL`/`Gravity.Fall`), the one velocity (Impetus) and the one scribe (Travel). Pitch and heave are the same idea about the other two axes and are held back for their own phase, because they touch the carry seam where roll is purely additive.
- **The heel's geometry lives in Keel and nowhere else.** Poise goes on measuring an upright body's weight over its upright feet; the arc the weight swings through as the body goes over is one line of statics, never a re-projection of the chain. This is the whole bargain that leaves the solver, the gait math, the census and combat addressing untouched.
- **Everything else only expresses it.** `Armature.roll` is assigned, never integrated — the same law the heights already live under — and the Z channel heels the trunk about its own feet, `Armature.socket_of` becomes the one statement of where a leg hangs from, and `Contour` turns each ring frame in its own cross-section. The cascade then runs through seams that already existed: the low side's socket sinks and its leg folds, the high side's lifts until Footwork's tear-off check fires, that foot steps, and the hull Poise measures narrows on exactly the side the body is going.

Two things had to be added that the original sketch did not have, and both are load-bearing:

1. **The body turns about the ground, not about its own centre.** A standing animal is pinned at its feet, so every torque divides by `I_com + M·H²` (parallel axis — the other end of the same shift `Corpus.roll_inertia` already makes). With the bare centre-axis moment a cat snaps flat in three frames; with the ground axis it takes about half a second, which is what an animal does. A body in the air gets the bare moment, because there it really does turn about itself — and that one difference is why a press below the weight rolls an airborne body the other way while a press at a standing animal's toes barely moves it.
2. **The legs fight to keep the body over its feet.** A trotting quadruped is on two feet half the time and does not fall over. That is muscle, so it is written the way every other muscle in v2 is: a *demand* off the roll error, **delivered only as far as the girdles can press**, with the ceiling derived from the stance's own half-base and the census's engine. Nothing authors a threshold — the threshold is where the demand stops fitting under the ceiling, and it moves on its own with the body's wounds and how many feet are down. Without this term the model is not wrong so much as incomplete, and it fells a walking cat on the first beat where the gait puts both feet of one side in the air.

Gate: `tests/TippingProbe.gd` (§11.2, below). Not taken: full 3D constraint solving, any second gravity or second integrator, and any change to the plan solver, the gait math, the census or combat addressing.

#### 4.1b The rig — anatomy as a layer, not a solver (2026-08-15)

The second complaint the revisit clause anticipated was the skeleton itself: the graph had explicit points and rigid sticks, but no *joints* — a live limb was three bones folded by free FABRIK between a socket and a foot (no angular limits at all, a seeded pole its only anatomy, and a left leg standing unlike the right because FABRIK keeps history), the spine's cones were one authored number graded by stick radius (so the thin tail folded further, but nothing knew where a back actually bends), the scapula did not exist, and the body's heel was one scalar over the whole animal.

The answer keeps the bargain of 4.1a: **anatomy is a layer over the same solver, not a new solver.** `rig/Rig.gd` is the erect-quadrupedal class's anatomy — cat-referenced, literature-cited, every number tagged FACT or APPROX — consulted at three seams and nowhere else:

- **`axial_limits`** replaces the radius grading: per-station lateral cones by spinal region (lumbosacral largest, cranial thorax stiffest, tail limbering toward its tip, the atlanto-axial region the neck's biggest mover), scaled by the chains' authored scalars so `BodySpec` stays the single authoring seam. Sweep totals are held within a few percent of the tuned build, so the turn and gaze behaviours never noticed.
- **`solve_limb`** replaces the limb FABRIK: a closed-form solve in the limb's own vertical plane — deterministic and left/right symmetric, digitigrade by the authored pastern angles, elbow/stifle placed on their own anatomical side (a property of the joint, not a seed), and stopped at goniometric range-of-motion tables. A planted toe is exact (support is not negotiable); full stretch is the extension *stop*, never a straight rod; beyond total reach the chain arrives short and the tear-off owns the honesty. The elbow and stifle stand a little out of the sagittal plane (the bow), with in-plane lengths pre-shrunk so bone lengths stay exact in 3D.
- **Expression constants** for the Z channel: the scapular glide (`socket_of` — no clavicle, the glenoid follows the working foot fore-aft; `girdle_of` stays the gait's unmoved datum), the sagittal arch profile (the crouch rounds the back over the loins, girdles pinned at what the legs deliver), and the head-righting grade (`node_roll` — the neck carries the head back toward level while the trunk heels; `Contour` turns each ring by its own station's heel).

One transition also became physical: at `collapse`, a leg's height under its socket flops into ventral plan reach, scaled by the heel — before this, the tumble flattened Z wholesale and the length projections re-invented the missing reach in whatever direction the crumpled pose leaned, which could unfold a leg dorsally out of a body lying on its flank.

Gate: `tests/RigProbe.gd` (census named, symmetry, ROM under load, planted exactness, scapula alive and datum-true, righting, gather) and `tests/RigShot.gd` (front/side/plan views of the skeleton standing, striding and gathering). Not taken: per-vertebra stations, a second census, joint *dynamics* (the rig bounds poses; the motion layer still asks for them), and pitch/heave (still Keel's future phase).

### 4.2 The graph for the cat reference

One rooted graph, six chains. Node counts are **functional stations, not vertebrae** — see 4.3.

| Chain | Nodes | Attaches at | Notes |
|---|---|---|---|
| `trunk` | 8 | — (root chain) | pelvis → sacrum → lumbar ×2 → thoracic ×3 → withers. Carries both girdle frames. |
| `neck` | 4 + head node | trunk[withers] | cervical arc; head node carries the jaw frame (bite origin). Successor of Stature's neck arc — the carry projection becomes ordinary chain posing. |
| `tail` | 6 | trunk[pelvis] | free Verlet follower; graded bend limit (v1 lesson: grade the bend, don't damp per-station, or the tail pumps the undulation). |
| `limb FL/FR` | 4 | trunk[withers − 1] | scapula-pivot → elbow → wrist → toe. Cats are digitigrade: the 4th node is the metacarpus/paw, which is what actually makes cat legs read right. |
| `limb HL/HR` | 4 | trunk[pelvis] | hip → knee → hock → toe. Hock (ankle) sits high — this is the cat's "backwards knee". |

Total: **~32 nodes / ~28 sticks**. That is the entire physics skeleton.

Per **node**: `pos: Vector3`, `prev: Vector3` (Verlet), `frame` (forward/perp/up, computed).
Per **stick**: `rest_length`, `bone_radius` (the rigid core the rings wrap, §5), `bone_break_hp` (optional, late).
Per **joint** (node with ≥2 sticks): cone limit (min/max bend in plan, as v1's `_solve_angle_symmetric`), stiffness, and for limb joints the FABRIK role. The tendon-insertion gearing (swing vs. push trade at 0.30 no-op) ports as a joint property.

Girdle attachment gets one extra scalar worth keeping from cat anatomy: the forelimb girdle is **muscle-slung** (cats have no functional clavicle — the scapula floats). Model as attachment compliance: hind girdle rigid to trunk, fore girdle a stiff spring. This is one number, it is what makes a cat's front end absorb landings, and it feeds soft-landing behaviour for free.

### 4.3 Station density — DECISION

- **Option A — per-vertebra** (7C + 13T + 7L + 3S + ~21Cd ≈ 50 spine nodes): anatomically flattering, but triples solver cost for no behavioural gain; v1's whole gait repertoire runs on far fewer stations.
- **Option B — functional stations (recommended):** the ~32-node graph above for *physics*, with **render rings interpolated** between stations (Catmull-Rom along the posed chain, exactly how `Spine.sample(t)` already yields frames at arbitrary t). Physics cost stays fixed while visual smoothness is a free dial (`RINGS_PER_STICK`, start at 3).

**Recommendation: Option B.** The chain is a *controller*, not a vertebral census; smoothness belongs to the sampler.

---

## 5. Schema part 2 — the ring model (the census)

This is the heart of v2 and the direct replacement for both grids.

### 5.1 Coordinates

Every point in a creature's flesh has a **body address**:

```
(chain, t, θ, d)
  chain : which chain            t : arc position along it [0..1]
  θ     : angle around the axis  d : depth from the surface inward
```

Body addresses are stable under animation — a wound on the left flank stays on the left flank through every gait cycle, because the address is in bone-local frame. Converting a world-space contact point to a body address is: nearest point on posed chain (capsule test, as v1 `hit_test`/`aim_contact` already do) → two dot products and an `atan2`. This is the coordinate attacks target in 3D.

### 5.2 Discretization

The census quantizes body addresses into **polar cells**:

```
cell = (chain, station, sector, layer)
  station : fixed subdivisions along each chain   (trunk 16, neck 6, tail 8, limbs 6 each)
  sector  : fixed angular wedges around the axis  (trunk/neck 10, tail 6, limbs 6)
  layer   : BONE=0, MUSCLE=1, FAT=2, SKIN=3       (radial order, per the cat: muscle
            is bound to the skeleton and drives it; fat wraps muscle; skin wraps fat)
```

Cat total: 16·10 + 6·10 + 8·6 + 4·6·6 = **412 columns × 4 layers ≈ 1 650 cells.** Compare thousands of dense cartesian cells in v1, most of them interior filler. Every v2 cell is *meaningful* — it is a wedge of a specific tissue at a specific place.

Per cell, two numbers:

- `thickness` — radial extent of that tissue in that wedge, **at build** (rest anatomy).
- `hp` — current integrity ∈ [0..1]. **This is the entire damage state.** TissueGrid's ledger role collapses into the census; the damage translation step ceases to exist. Effective thickness = `thickness × hp` (a chewed-away wedge is thinner, so the mesh dents, the mass drops, and the next bite lands deeper — all automatically, because they all read this cell).

The surface radius of column (station, sector) is `bone_radius + Σ thickness·hp` over layers. Rings for rendering, capsules for contact, and depth for wound resolution are all this one sum.

### 5.3 Authoring representation — DECISION

Nobody should hand-author 412 columns. The question is what the *tuning* representation is, compiled into cells at build:

- **Option A — raw cells.** Author the full arrays. Maximum control, unmaintainable, and every physique tweak is a 400-number diff. Reject.
- **Option B — elliptical layers per station.** Per station, per layer: `(rx, rz, ventral_offset)`. Compact (~16 numbers/station), smooth, and captures the real asymmetries (deep chest = ventral offset at thoracic stations; belly fat hangs low = fat layer ventral offset). Wounds still live per-sector on top.
- **Option C — knot profiles (recommended, = v1's proven pattern).** Author sparse **knots** along each chain — exactly the `tail_base/tail_length/neck_width/trunk_lift` pattern the silhouette system already uses, extended per layer: e.g. muscle knots at shoulder/loin/thigh, fat knots at scruff/belly/inguinal, skin near-uniform with a scruff bump. Knots → interpolated per-station elliptical layers (Option B's form) → quantized into sector cells. Three levels: **knots (authored) → stations (compiled) → cells (census)**.

**Recommendation: Option C compiled through B.** Authoring stays at ~10 numbers per tissue per chain; the census stays uniform for the machine. The compile step is the successor of the carve — but it runs in microseconds, from rest-pose data only, exactly once per physique change.

### 5.4 The cat layout (initial knot set)

Values are proportions of trunk length / local bone radius; exact numbers get pinned by the Phase-2 probe.

- **Bone:** thin sheath everywhere except: skull (head node bulge), ribcage (thoracic stations get a `rib_cage` flag — bone layer spans the whole sector ring, which is why flank wounds there stop at bone), pelvis, scapula plate on the fore-girdle station.
- **Muscle** (the mover — its volume is what strength derives from, §7): epaxial ridge along dorsal trunk sectors; **hindquarters dominant** (thigh columns are the deepest muscle on the body — cats are rear-engined, matching v1's girdle-share model); shoulder/triceps mass on fore-limb upper stations; masseter/temporalis at the head node (bite force); tail and distal limbs nearly muscle-free (tendon-operated — which is *why* legs are light and swing fast; fast-twitch swing-time coupling survives).
- **Fat:** subcutaneous wash (thin, everywhere), inguinal/belly pad (ventral lumbar stations), scruff pad (dorsal neck). Leanness is one multiplier on the fat knot set.
- **Skin:** near-uniform thin; thicker + looser at scruff and dorsal neck (bite there grips skin before muscle — pre-modelled by the thicker skin+fat wedge).
- **Whiskers/claws/teeth:** not census tissue; features (§6) and Dentition port.

### 5.5 Thin parts

v1 lesson: parts under ~4 cells across have no interior — "sheathe, don't rewrite the census." The polar census obeys this natively: a thin part is simply columns whose muscle/fat thickness → 0, leaving bone + skin. No special case, no grid-parity floor. The v1 "thin conduits need a grid floor" rule dies here; conduits are features (§6) with their own radius, not census tissue.

---

## 6. Schema part 3 — features (organs, vessels, nerves)

Features are **not cells** — they are geometry in body coordinates, checked only when a wound reaches them:

```
Organ   : { name, chain, t_range, θ_centre, θ_spread, depth_band, hp, effect }
Vessel  : polyline of (chain, t, θ, d) + radius + flow_rate      (bleed on breach)
Nerve   : polyline + region_served                               (function loss on cut)
```

Cat placement (all on `trunk`/`neck`, t as fraction from pelvis→withers):

- **Heart** — thoracic t≈0.80–0.88, ventral, deep (inside rib bone layer). Successor of the `BodyState.arrested` organ; *death is a stopped heart* carries over verbatim.
- **Lungs** — thoracic t≈0.72–0.95, lateral pair, deep. Feed the aerobic ceiling (stamina = blood over engine).
- **Liver** t≈0.62–0.72 ventral-right; **stomach/gut** lumbar t≈0.35–0.60 ventral; **kidneys** t≈0.45–0.55 dorsal pair.
- **Aorta/vena cava** — ventral to the spine bone layer, full trunk run; **carotid/jugular** — neck, ventral-lateral, *shallow* (this is why throat bites kill — the schema encodes it as geometry, no special case); **femoral** — inner thigh proximal stations.
- **Spinal cord** — dorsal, *inside* the bone layer (protected until vertebra breached).

Wound resolution: bite resolves depth `d` through the column's layers (skin→fat→muscle→bone, subtracting `thickness×hp` in order, damaging each) → surviving depth intersects features in that (t, θ) neighbourhood → vessel breach starts bleed, organ hit applies its effect. The vessel/nerve *overlays* in the anatomy view render these polylines directly — same data, no TissueForm re-derivation.

---

## 7. Schema part 4 — derivations (biology → physics)

All read-only functions of the census; each has exactly one owner.

1. **Mass** — Σ over cells: wedge-shell volume (closed-form frustum sector between inner and outer radius, along the stick) × tissue density (bone 1.9, muscle 1.06, fat 0.92, skin 1.1 rel.) × hp. Owner: `Corpus.mass()`. Per-node masses feed the solver so a heavy head actually droops the neck chain.
2. **Centre of mass** — same summation, position-weighted, in body space; posed through ring frames per tick (cheap: 32 node masses, not 1 650 cells — cells bake to per-node mass + offset at compile). Owner: Plumb's successor `Poise`. Support polygon/stability logic ports as-is.
3. **Strength** — muscle cells only, grouped into **compartments** — DECISION:
   - *Option A — per-joint muscle accounting.* Anatomically pure, but v1 already proved the per-girdle abstraction carries the whole gait repertoire.
   - *Option B — compartments (recommended):* `fore_girdle`, `hind_girdle`, `epaxial` (spine power — leaps, gallop flex), `neck`, `jaw`. Each = Σ muscle volume of its stations. Girdle-share, drive, bite force, spine power all fall out. Maps 1:1 onto v1's `girdle_muscle`/`girdle_drive`, so Locomotion ports with a renamed input.
4. **Load & girth** — supported mass per limb from COM position (v1 logic); girth per station = mean surface radius, feeding the load^0.4 relation and silhouette width.
5. **Compliance (the soft-body feel)** — per column: `fat/(muscle+bone)` thickness ratio → contact stiffness + damage attenuation. A fat flank dents (visual ring deformation, §10) and cushions; a bony shin is stiff and fragile. **This is the whole soft-body system** — no soft-body dynamics, softness is a material property of contacts (see §9.1).
6. **Stamina** — aerobic ceiling from heart size (organ), lung capacity (organ), and locomotor muscle mass; v1's blood-over-engine model unchanged, inputs now from Corpus.

### 7.5 Schema part 5 — the authoring file

One `.tres` resource per creature (successor of CreatureParams' physique half):

```
CatBody.tres
├─ chains        : node counts, stick lengths, bone radii, joint limits, girdle compliance
├─ tissue knots  : per chain × layer, the §5.3 knot lists
├─ features      : organ/vessel/nerve table (§6)
├─ fibre         : fast_twitch, tendon insertions, spine_freedom  (behavioural scalars kept from v1)
└─ posture       : stance datum, tilt, stance_range               (Stance/Posture inputs)
```

"Properties adjustable from a single location" = this file. The Creature Creator's sliders write knot multipliers here (leaner ↓fat knots, bulkier ↑muscle knots, longer-limbed ↑stick lengths) and everything downstream re-derives. **Pin the default build exactly:** the compiled default cat's mass/strength/COM go into reference constants at 6+ decimals, with a probe asserting the fixed point (v1's 0.3%-drift lesson).

---

## 8. The `BodyReadout` interface (what "keep the UI" means)

The HUD shell survives untouched: HudDock, drawers, camera-focus-pays-for-drawers, MinimalSlider, PipMeter, InkToggle, F3 cycle. The content panels currently read the lattice; they get ported one drawer at a time onto one read-only interface:

```gdscript
class_name BodyReadout   # implemented by the v2 creature; panels depend only on this
func mass() / strength(compartment) / stamina_state() / gait_state()   # GaitPanel
func surface_radius(chain, station, sector) -> float                   # SpecimenMesh rings
func tissue_at(chain, t, theta) -> Array   # [(layer, thickness, hp), …] AnatomyView probe
func features_in(chain, t_range) -> Array  # organ/vessel overlays
func wounds() -> Array                     # damage listing, BiteMark visuals
func vitals() -> Dictionary                # heart/lungs state — "death is a stopped heart"
```

Panel-by-panel: **GaitPanel** stays a live view quoting measured gait state — same fields, new provider. **AnatomyView/AnatomyPanel** lose their lattice-walking code (the bulk of AnatomyView's 2 752 lines) and instead render rings + feature overlays — a substantial internal rewrite behind an unchanged visual design; the .dc.html mocks remain the layout spec (take the layout, take the numbers from the live systems). **CreatureCreator** sliders write the authoring file. **SpecimenMesh** is the big winner: its ring/band machinery stops *deriving* rings from a cell census and reads them directly — bands, sectors, gap-fill logic simplify or vanish.

---

## 9. Combat, damage, contacts

### 9.1 Contacts
Creature–creature and creature–world contact = **capsule vs. capsule on posed sticks** (radius = mean surface radius of the stick's stations). ~28 capsules/creature, broad-phase by chain AABBs — the v1 "bound the overlap first" lesson, now with no per-cell lookups at all behind it. Contact response: positional correction into the Verlet nodes, stiffness scaled by local compliance (§7.5). Softness = the flank *gives* (nodes displace, rings dent visually) instead of bouncing.

### 9.2 Bites and targeted attacks
The v1 bite pipeline survives structurally — one 3D contact point, hover-preview → click-commits, lunge as rigid body shift capped by support, reach measured from rest pose, verticals gate before horizontals, underbody bites anchored at the jaws. What changes is the *addressing*: `hit_test` resolves to a body address `(chain, t, θ)`; wound application is §6's depth walk. Reticle and TargetMark come across as `combat/Quarry.gd` and `ui/AimMark.gd`, both reading the posed rings rather than a reconstruction of them — so the thing the pointer selects, the thing the mark traces and the thing the bite wounds are one address by construction. Mouthful/Dentition port with tooth depth mapping straight onto layer thickness.

### 9.3 Wounds
A wound is *only* hp reduction on cells (+ feature effects). No separate wound object for physics — BiteMark keeps cosmetic state (tooth pattern) but reads geometry from the census. Bleed = flow_rate accumulation on breached vessels into BodyState's blood pool (stamina and death already hang off blood/heart — unchanged).

---

## 10. Rendering

- **SpecimenMesh v2:** for each render ring (interpolated station, §4.3), place the ring frame on the posed chain, radius per sector from the census, skin adjacent rings into tube quads; limb tubes off limb chains (limb flesh lives on the drawn chain — already true in v1). Band by axis where sticks bend sharply (v1 lesson). Wounds render as *the same rings, thinner* — dents appear because the data got thinner, plus a BiteMark material decal for the surface look.
- **Layer peel** (anatomy view): render rings at bone-only, +muscle, +fat, +skin radii — the peel view is four evaluations of the same sum, no second geometry system.
- **Contact dent:** transient sector-radius offsets decaying over ~0.3 s, driven by contact impulses × compliance — purely visual, never written to the census.
- Draw-cost lessons carry: bank shades per (layer, hp bucket), hoist packed arrays, cull before working.

---

## 11. Implementation strategy

### 11.1 Ground rules

- **Build alongside, never in place.** `scripts/creature2/` + `scenes/V2Lab.tscn` (minimal Main: camera, terrain, input pump, one v2 creature). v1 keeps running as the executable spec/oracle for gait feel, silhouettes, and bite behaviour.
- **Do not strip v1 first.** Deletion is one commit at the end (Phase 7), an afternoon; stripping first is a month of working blind with the reference destroyed.
- **Port claims, not constants.** Every v1 test that survives is re-expressed against the cat body with freshly pinned numbers.
- **Harness lore still applies:** new `class_name`s need `--import` before headless tests see them (and the errors point at the wrong files); failing script tests hang — never pipe to `tail`; RenderSmoke draw counts are not a signal; profiling needs manual ticks (PerfProbe pattern); UI screenshots need a windowed SceneTree script.

### 11.2 Phases

Each phase has a **gate** — a probe or test that must pass before the next phase starts. Rough sizing assumes v1's actual line counts as the porting base.

**Phase 0 — Scaffold (small). ✅ COMPLETE (2026-08-11)**
`scripts/creature2/`, `V2Lab.tscn`, `CatBody.tres` stub, schema constants file (station/sector counts, layer enum, densities). Gate: lab scene opens, headless import clean.
*Done as: `BodySchema.gd` (layers, densities, station/sector counts, ring dial), `BodySpec.gd` (authoring resource — class defaults are the reference cat, so `CatBody.tres` is a plain instance overriding nothing), `scenes/V2Lab.tscn` + `V2Lab.gd` (camera, terrain, input pump: zoom/reset/collapse/drop/node-drag). Gate passed: import registers all creature2 classes clean, scene opens headless exit 0.*

**Phase 1 — Armature (the skeleton core). ✅ COMPLETE (2026-08-11)**
`Armature.gd`: node/stick/joint graph, Verlet step, plan-dominant constraint solver (port `_solve_distance_symmetric` / `_solve_angle_symmetric` from Spine.gd — they are chain-agnostic already), Z channel, Gravity as sole integrator, FABRIK for limb chains (port Fabrik.gd), ragdoll = constraints-loosened mode (replaces Ragdoll.gd).
Gate: `ArmatureProbe` — cat graph stands under gravity, joint limits hold, drop test settles, per-node mass droop visible on neck/tail. Claims from GravityTest/RagdollTest.
*Done as: `Armature.gd` (35 nodes / 34 sticks in six chains; the whole axial body — tail→trunk→neck→head — is one relaxation sequence to the solver while Chain objects keep per-chain addressing; symmetric solvers and FABRIK ported verbatim; live limbs placed by sagittal-plane FABRIK so bone lengths are exact in 3D; Z channel = stance heights + carry lines + the Droop beam-law walk reading provisional per-node masses that Corpus takes over in Phase 2; `Gravity.Fall` is the only vertical integrator) and `Creature2.gd` (lab node, honest debug draw). Gate passed — `tests/ArmatureProbe.gd`: stands at what the legs deliver (pelvis 30.8 / withers 25.1 px), 160 px drop lands in 0.47 s per the world's closed form and stands back up, bends legal under a hard tail-haul with sticks exact to 0.0004 px on release and the body towed by the pull, tail sags 4.98 px in a tip-steepening curve clear of the floor, a 1.4× skull deepens neck sag 0.473→0.732 px, collapse lies flat with anatomy intact and rests drift-free. v1 oracles GravityTest/RagdollTest still green alongside.*

**Phase 2 — Corpus (the census). ✅ COMPLETE (2026-08-11)**
Knot compiler (knots → station ellipses → sector cells), `Corpus.gd` cell arrays + surface-radius/mass/COM/compartment derivations, `Poise.gd` (Plumb successor: bake cells → per-node mass+offset, posed COM, support polygon — port hull/stability math), feature table, `CatBody.tres` fully authored per §5.4/§6.
Gate: `CorpusProbe` — prints mass, COM, compartment strengths, per-station girth for the default cat; values pinned to 6 decimals as the reference constants. Claims from PlumbTest/VolumeTest/AnatomyTest. *(The pins below are Phase 2's; the trunk and neck knots were thickened at Phase 4 when the silhouette was first measured, and everything off the cells was re-pinned — see that phase's note.)*
*Done as: `Corpus.gd` (the one census — §5.3 C compile, knots → per-station ellipses with a ventral-hang term → 412 columns × 4 layers ≈ 1 650 cells; surface radius = core + Σ thickness·hp so ring, capsule and wound depth are one sum; mass/COM/five compartments/girth/compliance derived in one revision-keyed walk that also leaves per-station moments for the bake; `gouge` is the outside-in tissue depth-walk, feature intersection deferred to Phase 5; `features_in` serves the §6 table), `Poise.gd` (census → per-node mass/rise/lean/beam-width, split linearly between bracketing nodes so the first moment is exact; hands `Armature.mass`/`flesh_r` their numbers — the provisional flesh-scale derivation is deleted; posed COM is one weighted mean per tick; support hull/clearance/steadiness ported from Plumb verbatim), tissue knots + organ/vessel/nerve table authored as `BodySpec` class defaults (`CatBody.tres` still overrides nothing). Gate passed — `tests/CorpusProbe.gd`: fixed point pinned to 6 decimals (mass 30523.043797, COM x 30.110855 / z 25.734169, along 0.485659, compartments fore 1119.39 / hind 2242.16 / epaxial 4540.99 / neck 814.08 / jaw 395.97, mean trunk girth 7.596613); a heavy tail moves the weight 0.087 aft on a fixed ruler and a 1.8× skull moves it fore; dorsal muscle lifts the centre off the chain line; paw and tail tip are sheath over bone with no grid floor; hindquarters out-muscle the fore girdle 2:1; ribcage wraps the heart, skull wraps the brain, carotids shallow over a deep aorta; a gouge dents the surface by exactly the flesh it took; the standing armature poses its weight 9.7 px inside its own four feet with posed and built centres agreeing; and a chewed haunch re-bakes once — lighter, weight fore and to the other side, pelvis node lighter — with no carve and no mirror anywhere. ArmatureProbe still green on census-baked masses; v1 oracles PlumbTest/VolumeTest/AnatomyTest green alongside.*

**Phase 3 — Locomotion (the loop). ✅ COMPLETE, redesigned from the ground up (2026-08-12).**

> The first attempt (`c4a3b7c`) ported v1's gait machinery whole — patterns, duty tables, retarget — and was taken back out of `main` the same day, parked on **`v2-locomotion`**. The rewrite below shares no code and no architecture with it: v2's locomotion is not a gait player, it is a control loop. What survived the reopening because it is stance geometry rather than a mover — `Carriage`, `Attitude`, the armature's head-pinned solve and lateral wave, `Corpus.soundness`, Poise's balance constraints — is what the loop now stands on.

**The loop.** One cycle, every tick, one owner per stage (`scripts/creature2/motion/`):

```
intent → desired velocity → desired acceleration → delivered acceleration
   → the body and its weight shift → the legs support and rebalance
   → the physical result → review → repeat
```

- **`Travel.gd` — the loop itself.** Reads the command into an ask (throttled by what the path ahead permits), owns the turn, the jump's charge-and-spend, the lean, the crouch, the contact stage and the balance review, and is the only writer of the seam Creature2 publishes (`speed`, `speed_norm`, `ang_vel`, `heading`, `head_pos`, `move_dir`). Turning slides its pivot from `turn_pivot` back to the body's own middle as speed drains, so a standstill turn is the legs walking the body round its centre.
- **`Impetus.gd` — the physical truth.** The plan velocity is a state, integrated from *delivered* acceleration: demand is `(desired v − actual v)/response`, delivery is demand clamped to the push — locomotor muscle over mass off the census, quoted against the reference cat's own ratio (`SPECIFIC_REF = 0.332711077`, so the default build is exactly power 1.000), × the stance's drive × `grip`, Footwork's measurement of what the planted feet have left. No acceleration parameter anywhere; airborne delivers nothing because there is nothing to press against. External forces enter through `shove(dv)`, and solids through `deflect(normal)` — the component into the face dies, the tangent keeps (sliding along a wall), and recovery from either is the same loop noticing the mismatch.
- **`Footwork.gd` — support and rebalance.** A planted foot is a world-fixed anchor (creep is impossible by construction); its *home* travels with the socket, displaced by the body's lean (girdle-weighted by each pair's press share, so the driving girdle trails and the catching one stays under the mass), and the drift between them — measured signed, so a foot the body is about to walk over is never "urgent" — is the one trigger to step. What the trigger *is* is the flow law (2026-08-17 rewrite): a leg's swing takes what a driven pendulum takes (√length, driven by twitch, gear and engine), so at any speed there is one stride cycle at which the four swings tile continuously at the occupancy the regime owes (`Rhythm.flow`), and the drift a foot may spend is priced from that — clamped to the anatomy's wall, floored at a step worth taking, handed back to the wall as the bound develops. Stride length and cadence both derive; the beat is arithmetic, never a clock, and a body that stops drifting stops stepping. Excursions, clearances and sweep speeds are Carriage projections re-measured off the active stance each tick, so anatomy is the constraint. Swings aim at a landing predicted from the body's own velocity, re-aimed every tick, placed on whatever surface Outlook says is actually there. The girdle carries are measured off the planted anchors (foot on a ledge = that end of the body rises, no ledge-case) *from the moment the feet are adopted* — a body built standing on a table is standing on the table on its first tick — and each carry pre-lifts toward the rise its own strip of path is about to cross (`rise_ahead` × `ANTICIPATE`, capped inside the legs' extension margin), which is the brief's "adjust the CG trajectory before the feet get there". Three honesty rules keep the support true: the surface moving under a planted anchor by more than `GROUND_SHIFT` is a desperate step nothing may deny; a body dragged past what a limb can span from socket to anchor **tears the foot off its footing** — it stops being support rather than stretching to a fiction; and `grip` — per-girdle press share × how much each planted foot has left × soundness — is read back by Impetus, so propulsion and support cannot disagree about the feet.
- **`Rhythm.gd` — the gait, as policy and nothing else.** Need is shared physics; *company* is the animal: how many feet may swing at once grows with pace (walk → trot is a second seat opening, not a mode), a girdle keeps one foot down while there is any choice (its desperate override at a run is the gallop's gathered beat), and at pace the seat beside a swinging foot belongs to its *diagonal* partner at the spec's `beat_coupling` — the grant prefers it over a more-urgent lateral neighbour, because diagonal feet carry the trunk across its own middle. The ladder also quotes `flow`, the mean airborne feet each regime owes (duty factor read the other way: walk 0.75 → trot 0.5 → bound toward 0.3, pinned on the same Froude boundaries), and the grant keeps those seats occupied — the handover — so the beat never pauses with the body parked four-square. A different animal is a different policy over the same loop.
- **`Outlook.gd` — the environment, continuously.** The short-term prediction of the immediate path, all of it measurements: what is under a point (`surface`), whether a height change is a step or a wall (`in_stride` — a rise past `CLIMB_SHARE` of the leg, or a drop past `DESCEND_SHARE`, is not a step), how much of an ask the path permits (`headroom`), where a foot can actually land (`reach_along` — a climbable ledge answers with its top, a wall or a brink pulls the landing short to its edge), what rises before the feet arrive (`rise_ahead`), and how deep the trunk currently is inside something solid (`intrusion`, height-gated on the body's own band). Slopes, moving surfaces and other creatures arrive later as more things it knows about — no consumer changes.
- **The review.** After Poise measures the weight against the feet: a real deficit (a share of the support past the boundary, held longer than a beat — a walking body is out over its edge as a matter of course) demands rescue: an existing swing is *steered* toward the spill, or the nearest planted foot is granted a step nothing may deny. A weight past what any leg can reach, for longer than a stumble lasts, collapses — and a grounded body with *no* planted feet at all (every foot torn off at a cliff edge) gets the fall's patience, not the wobble's benefit of the doubt. The same collapse a death is, because the ground does not care why a body arrives.

**World interaction and physics (second pass, same day).** The brief's law is that the world is continuous and physics is never overridden, and it is held by two additions to the cycle rather than by cases:

- *The watched path.* The ask is throttled by `headroom` probed along the coming travel but never less than half a body ahead (an animal does not stop watching the ground because it slowed down), and probed **from the leading girdle**, not the centre — a body that watched from its middle would hang its whole fore quarter over a brink before the ask died. This is what makes a wall something braked for and a 60 px brink something balked at, standing, with the fore feet crowded at the rim; the same numbers make a 10 px ledge an ordinary climb.
- *The contact stage.* `Travel.collide`, between the plan solve and the feet: the trunk capsule (pelvis→withers at its own flesh radius) is measured into the terrain's solids at the body's own height band — so a leap clears what a walk is refused by, and an overhang above the back is walked under. An intrusion changes the state and nothing else: the armature is `shift`ed out whole (position and Verlet history, constraint-neutral, feet not moved — the support drift is how the legs learn about the wall), the velocity into the face dies through `deflect` while the slide keeps, a hard stop sinks the body by its impact through the landing's own absorb, and a press at one end swings the body about its middle through `ang_vel` — recovered by the same easing that serves the intent. `Creature2.shove`/`spin` are the identical seam for forces that are not walls, which is where creature–creature charges plug in at Phase 5.
- *The vertical frame.* While airborne, the fall's floor is the ground now under the body minus the ground the feet took off from (`Footwork.frame_ground`), so a leap comes down on the surface it is actually over; at touchdown `Gravity.Fall.absorb_landing` re-zeroes the frame — the carries quote the feet from there — while leaving the tick's landing record standing for whoever reads it. Walking off an unfootable drop is impossible for the *feet* (`reach_along` refuses), so a body carried past a brink loses its support honestly: feet torn off, review out of patience, and the collapse falls on `Gravity.Fall` to the ground below.

Wounds weaken all of it with no dedicated code: a chewed haunch shrinks the compartments, which drops `power`, and its limb's soundness, which drops `grip`.

Gate: **`tests/MotionProbe.gd`** — behaviours, not constants. Passed: stands on 4 feet with 0.000 px drift and no steps; half cruise in 0.10 s and nine tenths in 0.28 s off a derived 440 px/s² (0.29 g) at power 1.000, never outrunning its own ask; planted feet creep 0.0000 px a tick at cruise; the pattern comes out of the speed — 3.67 feet down strolling, 2.87 at cruise with 100 % of paired swings diagonal, 2.28 sprinting at 163 px/s; turns 2.94 rad on the spot in 2 s through 35 steps with 6.2 px of wander; a 10 px ledge is *anticipated* — the fore carry rises 4 px before any fore foot reaches the step — then climbed fore-girdle-first and both carries end +10 px with no ledge-case in the mover; a wall stops the walk braced at the face at 3 px/s and a 420 px/s shove cannot put the body inside it; a 60 px brink is balked at 37 px short, standing, and the same body shoved over it falls for real and arrives below at z 0; a 300 px/s shove on open ground is caught in 8 recovery steps and stood back up at steadiness 0.33; a charged running leap peaks 23.7 px ballistic on `Gravity.Fall`, keeps its speed, and lands on its feet; a running leap over a 12 px table comes down *on the table* and is carried there; a chewed thigh drops power to 0.974 and standing grip to 0.74; and after all of it every stick, bend and bone is exact (0.0001 px / 0.0000 rad / 0.0000 px). ArmatureProbe, CorpusProbe, SkinProbe and the world's GravityTest green alongside.

**Phase 3a — the physics HUD (the loop, while it runs). ✅ COMPLETE (2026-08-15).** Built from `Evolution Game UI Design/Physics HUD.dc.html`, which is the layout spec and — as always — *not* the source of any number: the mock runs its own JavaScript restatement of the loop, and every reading here is taken from the live systems instead.

Two things about a walking animal cannot be seen by watching it walk: why a foot stepped when it did, and where the stiffness in the picture comes from. Both are decisions the loop takes several times a second and throws away, so this panel is those decisions drawn at the moment they are taken.

- **The seam is one object.** `motion/MotionReadout.gd`, held by `Travel` and reached through `Creature2.motion_readout()` — the `BodyReadout` extension §8 asked for. `Travel.observe` fills it at the end of the tick, after `Poise` has measured the result. Two halves: **this tick** (the intent, the demand against the delivery against the ceiling, one `Step` per foot carrying `Footwork`'s anchor/home/drift/urgency/landing, `Poise`'s weight and support, `Keel`'s heel and righting, `Outlook`'s rise and headroom) and **the last 4.5 s**, a fixed ring written on the physics tick — sized once, allocating nothing per tick, and inert until something calls `watch(true)`. The eight *tells* are reductions of that ring and live here, not in the panel; the *bands* they are judged against are the panel's, because a natural band is a judgement about an animal rather than a measurement of one.
- **What had to be newly published, each from its own owner** (nothing is re-derived in the panel): `Impetus.demand`/`ceiling` (the clamp's two ends — the *difference* is the body having mass), `Keel.ceiling` (what the girdles could press if they spent everything), `Rhythm.seats`/`most` (the gait as a number), `Footwork.Foot.home`/`drift`/`torn` + `fore_rise`/`hind_rise` + `excursion()`/`clearance()`/`sweep()`, `Travel.ask_speed`/`headroom`, `Poise.support_shape()` (the prints in hull order — the polygon its own clearance was measured against), and `Armature.joint_slack(i)`/`joints_at_cap()` (an axial vertex against its graded cone; a placed limb against being straight, which is the only cap a FABRIK leg can reach).
- **The panel.** `creature2/ui/MotionDrawer.gd` + `MotionStage.gd` — the third F3 stop in `LabHUD`, in the shared dock at 540 px, camera paying for it exactly as the other two. Three panes are three projections of the **one** posed armature (sagittal along the heading, plan in the world's own XY, frontal head-on — the only view in which the heel, the lateral base and the righting are legible at all), plus the timeline ribbon: a row per foot run-length drawn (planted solid, swinging hollow, desperate full-height), feet-down, demand over delivery, poise with its spill marks. It holds the clock while it is open — pause (`P`), frame-step (`.`, one tick driven by hand, because a rendered frame is however many ticks the accumulator had in it) and slow motion 0.10×–1.50× — and gives it back when it is closed.
- **The screen (2026-08-15).** The handoff draws this panel *full screen*, and that is what `scenes/PhysicsHud.tscn` is: `creature2/ui/PhysicsHud.gd` over `PhysicsBench.gd` — one animal, one floor, no field view and no camera, because on this page the diagram is the picture. Layout is the mock's to the pixel (250 px rail left, 176 px right, the three-view canvas between them at 302/230, the timeline in the canvas's own bottom band, the 14 px inset hairline, the vignette and the grain); the arithmetic is still the seam's. The drawer stays as the version you read *while playing*, and what the two share — the eight bands, the six marks, the timeline — moved into `creature2/ui/MotionRead.gd`, so there is one opinion about what a natural sway is rather than one per window.
- **The nine scenarios are commands** (`creature2/motion/MotionScenario.gd`), which is the only way they could be ported: the bench does not animate an accelerating cat, it asks for full throttle from a standstill and lets the loop deliver what the feet can press. Ledge and brink are `Terrain.add` (a +10 pad and a 60 px plateau to walk off), the shove is `Creature2.shove` at the weight's own height, the collapse is the collapse a death is. Where the mock quotes a number in its own world's units it is re-taken from this animal: 300 px/s against a 163 px/s sprint is 1.84× flat out, and measured, anything past ~1.4× rolls this cat straight over — which would make the shove scenario a second collapse — so the blow is 1.15× (a ~12 px stagger, ~13° of heel, caught by rescue steps).
- Gate: **`tests/MotionHudProbe.gd`** — the panel reads and never invents. Passed: every drawn foot is `Footwork`'s own anchor/home/lift/landing/socket to 0.000000 px; the weight is `Poise`'s to 1e-9 and the support polygon's vertices are the posed toes themselves (within 0.04 px of the anchors they were planted at); 300 walked ticks of timeline match what the feet were doing tick for tick; delivery never passes the ceiling it is drawn against and the ceiling falls with feet lifted; a leg at full stretch reads clamped and a folded one does not; the travel tells stay blank on a standing animal and read on a walking one; the rise and the carry both move before a fore foot is on a 10 px ledge; the trace is bit-identical watched and unwatched (0.000000000 px over 240 ticks); the recording costs ~0.07 ms of a 0.75 ms tick, and only while the panel is open; and the drawer borrows the clock and gives it back (0.25× slow, paused, one tick stepped, released on closing). The drawing is not measurable headless — `tests/MotionShot.gd` is the windowed look at it.
- Gate: **`tests/PhysicsHudProbe.gd`** — the screen's own half, that the scenarios are commands the loop genuinely answers. Passed: a drive at 0.50 asks the loop for exactly half flat out and shutting it stops the animal; the standing start reaches 99.9 px/s with the demand clamped on the way (the body feeling its own mass); the brake takes 92 px/s to nothing; the standstill turn comes 2.97 rad round inside 6.5 px of wander and the cruising turn 1.22 rad at 60.8 px/s; the +10 ledge is built and ends up underfoot; the −60 brink is balked at and the body stops 38 px short of the rim; the 115 px/s shove puts it 10.9 px across its own line and 9.9° over, caught by rescue steps and still standing; the collapse puts it down and the loop says `COLLAPSED`; a 7 s scenario loops back to its spawn; every reading on the left rail is the seam formatted (10 checked); and the clock is borrowed and given back. `tests/PhysicsShot.gd` is the windowed look at the page.
- **What it immediately found, left standing as findings rather than tuned away:** COM bob 0.2–0.8 px against a 3.5–10 px band (`FLAT` — the legs are not spending their fold), lateral sway 0.4–1.1 px against 2.2–9 (`RIGID` — the weight never shifts over the supporting side), tail trail under 1° walking straight (`STIFF`), delivery ~1.00 (`WEIGHTLESS` — the demand is never clamped at a cruise), stride/reach ~1.0 against 0.40–0.86 (`OVERREACH`), and `grip` draining to 0.00 for a few ticks of each walk cycle, which leaves the animal with nothing to press against exactly when it is reorganising its support.

**Phase 4 — Skinning. ✅ COMPLETE (2026-08-12)**
`SpecimenMesh2`: rings from census via interpolated stations; CreatureView port (draw order, shading banks); silhouette check against the Gait HUD .dc.html geo blocks (still the spec).
Gate: screenshot probe — standing/walking cat silhouette matches v1/mock within tolerance; RenderBenchmark comparison (expect a large win; don't trust single runs).
*Done as two files. `Contour.gd` is SpecimenMesh2 under a name that says what it turned out to be: not a mesh for the specimen panel but **the** geometry, the census's flesh placed on the solved chain, and every view is a projection of it rather than a second surface. Rings are laid `BodySchema.RINGS_PER_STICK` to a stick — 97 of them, splined through the armature's nodes on the axial line and straight along a limb's bones, because a back is a curve between its stations and an elbow is a corner — and each ring's sector radii are `Corpus.surface_radius` interpolated between the two stations bracketing it. Three resolutions meet and stay distinct: ~35 physics nodes, the census's fixed stations where damage is bookkept, and the rings, which are the sampler's business and cost the simulation nothing. The frame is the honest part: the lateral comes off the armature's own plan frames (a leg hanging straight down has no plan direction of its own) and dorsal is completed per chain, so a wound on the right of the tail is drawn on the right of the tail. Radii are re-read only when `Corpus.revision` moves; a tick poses frames and evaluates surface points and touches no cell. `Corpus.layer_radius` is new and `surface_radius` now calls it — the peel is four evaluations of one sum (§10), with no second geometry under the skin.*
*`Likeness.gd` is CreatureView's port: v1's draw order (limbs, body over them, paws over that), its palette and its batching lesson (four triangle arrays, shades banked per layer and wear, buffers allocated once, the ink re-read only on a wound). Two things are gone rather than ported. The attitude shear is gone — v1 drew the body as one flat sheet at one height and had to tip the sheet to say a leg was holding a corner lower, where every v2 vertex carries its own height and the projection is one line, `y − z · PERSPECTIVE`. And the wound is gone as a thing to draw: a chewed wedge is thinner and a different colour because the census says so, so the picture cannot disagree with what was bitten. Within a ring the sectors are painted ventral-first, since from almost overhead a ring projects to a sliver and both its sides land on the same pixels; shadows are cast from the plan silhouette between the flank sectors rather than from the tube, because overlapping sectors stack their ink.*
*The gate found something, which is what a gate is for. Every stance proportion was already exact — shoulder 0.61 and hip 0.69 of the girdle gap against the mock's 0.64/0.68 — but the drawn animal was 0.27 of its own gap across the trunk where the Gait HUD mock says 0.38 and v1's Cat preset says 0.47: a third too thin, and it read as a weasel. That is Phase-2 authoring rather than skinning, and nothing had measured it before, because a census is self-consistent whatever the knots say. So the trunk and neck knots were thickened until the drawn cat sat inside the reference band (girth 0.40, head 0.33), the tail tip's width moved from mover into skin to keep the thin-part claim true, and everything counted off the cells was re-pinned in the same commit: mass 30523.043797 → 46128.100637, COM (31.98, 0, 33.47), along 0.516, epaxial 11985.78, and `Locomotor.REFERENCE_MASS`/`REFERENCE_MUSCLE` with them — after which the reference cat is exactly power 1.000 again and PushProbe prints the same 518 px/s² (0.345 g) it did before. The limbs and the tail were measuring right and were left alone.*
*Gate passed — `tests/SkinProbe.gd`: 97 rings and 724 facets cover all 412 census columns with no station undrawn; the sampler matches the census to 1e-6 px at every station centre and every surface point sits on its own radius; the peel never takes the body outward and its fourth evaluation is the surface exactly; 300 walked ticks move no cell, re-read no radius and leave no ring more than 0.33 px off its stick; a 3.5 px bite dents the drawn ring by exactly 3.5 px and the wedge is drawn as meat; the mesh is the same 724 facets whole or chewed. `tests/SkinBench.gd` is the RenderBenchmark comparison (RenderBenchmark itself measures the whole game scene and cannot see v2 until Phase 7): v1's view rebuilds and recolours 344 quads every frame at ~685 µs, v2 poses, projects and shades 724 facets at ~240 µs, and the scaling claim is the real win — v1's census is 3 274 cells for a cat and 49 088 for an elephant, where v2's is 1 648 for either, because the resolution is a statement about the surface rather than about the volume behind it. `tests/SkinShot.gd` is the eyeball half, windowed: standing, walking, sprinting and collapsed. ArmatureProbe, CorpusProbe, GaitProbe and PushProbe re-run green on the re-pinned body.*

**Phase 5 — Damage & combat. ✅ COMPLETE (2026-08-12)**
Capsule contacts + compliance response; body-address `hit_test`; wound depth-walk; features (bleed, organ effects, arrest); Mouthful/Dentition/BiteMark port; lunge/strike pipeline rewired (TargetMark, Reticle, BiteCue keep their roles); Grip/feeding.
Gate: CombatTest/BiteReachTest/FeedingTest claims re-expressed — bite anchors at jaws, wound depth matches tooth/layer math, throat bite bleeds, heart hit arrests, "what is hit is what is displayed" verified by biting a flank and diffing the rendered ring against the census.

*Done as `scripts/creature2/combat/` — four files — plus the seams the rest of the body already had waiting. Everything is fully 2.5D off the posed XYZ anatomy: the hit test, the capsules, the teeth and the reach all carry heights, and nothing anywhere compares flat silhouettes.*

*The addressing is `Contour.locate` / `Contour.place`: world point → nearest posed ring capsule → two dot products and an atan2 → body address `(chain, t, θ, d)`, and the inverse for holds. It reads the same ring arrays the painter draws, so "what is hit is what is displayed" is a property of the code — the probe's round-trip is exact to 0.000 px, and the same plan point that is flesh at flank height is air 30 px over the back. `Corpus.wound` is §6's resolution: the existing `gouge` depth-walk (skin → fat → muscle → bone, each soaking what its effective thickness can) followed by feature intersection against a per-creature deep copy of the feature table. The wound front is quoted as a fraction of the **built** column, which is the coordinate the depth bands are authored in — so a second bite starts where the first stopped, the ribs protect the heart until they are gone, and none of that is a rule.*

*`Vitals` is BodyState's successor: one blood pool drained by breached vessels (flow decaying as clotting — a torn carotid costs ~0.83 of the pool before it seals, a nicked femoral ~0.6 and survivable), organ effects by the table's own words, nerve cuts as function loss (`numbness` multiplies into Footwork's press beside `soundness`), and **death is a stopped heart**, verbatim: `arrested` is the one death readout, a drained pool arrests exactly as a heart wound does, the review's unrescuable falls arrest too, and an arrested heart collapses the body on the next tick. `Fangs` is Dentition's port — four authored numbers (the BodySpec dentition block), types/patches/pressure all derived, `REFERENCE_CONTACT = 0.174349` measured off the default build (v1's own 0.1743, because it is the same formula) — with the force re-derived: bite depth = `REF_DEPTH 2.6 px × (jaw compartment / JAW_REF 416.954952) × pressure()`. No bite-damage number is authored anywhere; a chewed masseter closes softer because the census says so.*

*`Maw` is the strike pipeline, structurally v1's: hover-preview (`aim`) commits nothing; verticals gate before horizontals (a flank on a 70 px perch is refused as "height" at close plan range, never chased); the neck is an arc rooted at the withers, so the purse is one 3D radius — arm + support-capped throw + gape grab — and the same 61.8 px gap that connects at mouth level is refused onto the floor. The lunge is the body moving: a rigid `Armature.shift` capped by the support (`poise.clearance` spent as throw — a teetering body throws short), with the head carried to the contact's height through a new Z-channel term (`head_reach_z` re-aims the neck's carry line; drawn head, jaw frame and hit band are one set of nodes, so they cannot disagree). The throw is re-aimed at the target's actual flesh every tick — a target that walks, turns, or is shoved along by the arriving body itself is met where it is — and the jaws close early the moment the teeth are on it. Each tooth is its own 3D contact: placed on the arc at the jaw's height, located on the target's posed rings, driven its own depth less the air in front of it, so one closing wounds several columns and the mark is a mouth. A latched hold keeps a body **address**, not a point: it follows the flesh through every pose, tows the lighter body by mass share, re-seats after every chew (v1's work-in — which is why the hold survives eating its own wedge hollow), tears free through flesh when hauled past what flesh holds, and feeds the belly by exactly the census mass the carcass lost — only a stopped heart is meat.*

*`Clash` is §9.1: capsule against capsule on all ~34 posed sticks per body at the census's baked flesh radii, broad-phased on body length, 3D segment distance — so a leaping body sails 80 px over a carcass its plan overlaps with 0.00 px of push, while its dangling toe honestly grazes a back it passes just above — and plan-dominant response through the same seams walls use: the armature is shifted whole (feet not moved — support drift is how the legs learn), the velocity into the other body dies through `deflect` while the slide keeps, the impact arrives in the other body as `shove`, a press off the middle turns through `spin`, and the correction is scaled by the compliance of the flesh actually touched. Each creature takes its own mass share of the separation on its own tick, so a pair parts symmetrically without anyone owning both bodies. Two standing trunks built 11 px into each other resolve to zero overlap in under two seconds, both bodies moving. Contacts and the maw run in the loop's contact stage, between the world's solids and the feet.*

*Wounds weaken everything downstream with no dedicated code, as designed: compartments → power, soundness × numbness → grip, lungs → wind, blood → arrest. The lab drives it with B (bite at the mouse) and G (latch: tow, and feed on a carcass); the proving ground's resident and carcass now press back against whatever walks into them.*

*Gate passed — `tests/CombatProbe.gd`: hit-test round-trip exact and air-above-air; 11.1 px of built-in trunk overlap pressed to −3.3 with both bodies moving; airborne clears what plan overlaps (0.00 px push) and is pressed apart on landing (6.1 → 42.5 px); a jaw carried 2.9 px inside the envelope anchors at the near flesh (far flank 17.7 px away); tall back refused as height, 61.8 px connects level (purse 64.1) and is refused onto the floor; a 23.6 px throw carries the pelvis 16.3 px with the neck exact to 0.00 px and flesh taken; a 1.47 px wound is skin + half the fat exactly, dents the drawn ring by 1.473 px, and the second bite hits muscle; one closing wounds 2 columns and the drawn radius equals the census radius over each; a throat bite breaches the carotid by geometry and bleeds out to arrest in 25 s; the heart survives bite 1 behind the ribs and stops on bite 2 through the breach; a cut sciatic drops standing grip 0.91 → 0.65; a latched hold ate 148.33 census mass (= exactly what the carcass lost), towed it 15.5 px, and tore free; anatomy exact throughout (0.0000 px / 0.0000 rad) on both bodies. ArmatureProbe, CorpusProbe, MotionProbe, SkinProbe and ProvingProbe re-run green (one honest fix surfaced: a lab `reset` now restarts the heart, since the review's falls genuinely kill); v1 oracles GravityTest/CombatTest/BiteReachTest/FeedingTest green alongside.*

*Known limits, stated rather than hidden: other creatures are not walkable surfaces (Outlook's ground reads terrain only, so feet plant under a carcass and the clash presses the legs off it); the §10 transient contact dent is deferred to the rendering pass of Phase 6; TargetMark/Reticle/BiteCue are UI and arrive with Phase 6's drawers — the maw's `aim` is written as their provider.*

**Phase 5a — Attitude: roll. ✅ COMPLETE (2026-08-12)**
The §4.1a revisit, built. `motion/Keel.gd` (the one attitude owner: roll, its rate, the weight's torque about the foot it is pivoting on, the girdles' clamped righting, and the flank a downed body finishes on); `Corpus.roll_inertia` (one more accumulator in the census's single walk — the second moment to `com`'s first, parallel-axis shifted once at the end) baked through `Poise` beside the node masses; `Poise.flanks` (the outermost planted foot each side of the plumb line — the pivot a heel turns about, deliberately not the hull's nearest boundary); `Armature.roll` + `socket_of` + a heeled Z channel and a directional collapse; `Contour` rings turned by the same number; `Travel.tip` as a new loop stage between the contacts and the vertical, `Travel.shove(dv, at)`/`twist` as the seam with a place in it, and the review answering a strained heel with the rescue step it already had. `Clash` stops flattening its contact: the height it measured now reaches both bodies' attitudes.

*Two bugs surfaced that were not about roll and are fixed here. `Creature2.reset`/`build`/`toggle_collapsed` never re-measured Poise, so the first tick after a reset read the previous body's feet — invisible while nothing consumed the support measurement dynamically, fatal the moment something did (`_measure` now runs wherever the body jumps outside a tick, the way `contour.pose()` already did). And `Armature.settle` was an integration that had never been given its tick; it takes `delta` now.*

*One thing the drawing caught that no assertion would have: a downed body's legs are carried over by the heel **kinematically** — position and Verlet history together, as the lateral wave already is — and not pulled by a plan-projected gravity. Written as a force the legs are still falling sideways long after the animal has stopped rolling, and they draw rammed straight out; written as the arc the frame swept, they stop when the body stops. A leg hanging `along` px below its socket swings `along × Δsin(roll)` across the ground and no further, which is the geometry and not a tuning.*

*Gate passed — `tests/TippingProbe.gd`: a level body heels 0.00° standing and 0.90° over three seconds of walking, on four feet, and nothing falls; the ladder at the back's own height (z 45.5) reads 60→5° · 100→17° · 120→30° · 130 over · 160 over, crossing between standing and falling exactly once, with the heel growing monotonically over the rungs survived; the 120 px/s push is caught in 5 rescue steps and settles back to 0.08° alive; standing, the twist a press hands the body goes as 22.7× for 22.7× the height off the floor, and airborne a 40 px/s press 14 px over the weight twists +5.48 rad/s against −5.48 for one 14 px under it; pushed either way the body goes down that way, coming to rest at 90° with its spine 11.72 px up on its own 11.72 px half-width, the drawn back turned to (−0.01, 1.00, 0.00) and all four feet carried across toward the belly (mean 12.0 px — the pair that flops clear travels most of a leg, the pair it came down on hardly moves relative to the spine now over it); a body killed standing still flops belly-down at 0.00° and stands back up; a 20° lean lifts two sockets and drops two, and a body going over is down to three feet before it lands; roll inertia is pinned at 4 715 675 on the default cat (its weight 10.11 px off its own axis) and drops to 4 100 499 with one flank chewed away; a charge heels the body it hits by 9.7°; anatomy exact throughout (0.0000 px / 0.0000 rad). MotionProbe, ArmatureProbe, CorpusProbe, SkinProbe, ProvingProbe and CombatProbe re-run green — one constant re-pinned with its claim intact, since a body shoved over a brink now lands on its flank and rests a body-radius off the floor rather than flat on it; v1 oracles GravityTest/CombatTest/BiteReachTest/FeedingTest green alongside.*

*Known limits, stated rather than hidden: pitch and heave are not modelled, so a body is still level fore-and-aft however it is hit, and the "brace" that resists a heel is a girdle-wide moment rather than per-leg accounting — a press that would realistically be caught by one shoulder is caught by the animal. The righting demand always points back to level, where the unilateral rule would have a body past its own edge unable to push at all; the ceiling is what makes that case lose, not the direction. A charge between two cats of equal height shoves rather than rolls, which is right, so the lever's sign is gated on the direct seam where the contact height is exact rather than on the clash. `Poise.centre` remains the upright body's plan measurement by design (§4.1a) — the debug plumb mark does not swing out as a body goes over.*

**Phase 5b — The controls: the cursor look, and the bite hung off it. ✅ COMPLETE (2026-08-12)**
v1's hand, ported onto the v2 body. `motion/Gaze.gd` (v1's head look with its numbers — 82° cap, response 14, a 36 px² deadzone, a 30° lead band): one bearing doing the two jobs it did in v1, carrying the head round to whatever the pointer is on and handing the ordinary steering a signed demand so a walking animal goes where it is looking, with the hand still outranking the head. `Armature.look` + `_aim_neck` express it: v1 articulated one head node off the last joint because that was all the chain it had above the shoulders, and v2 shares the demand out along the real cervical run, each joint taking what its own graded bend limit will give — so how far an animal can look round is anatomy rather than a number, and the joint at the withers is deliberately left out so the girdle's frame (and the fore sockets on it) cannot swing with the head. `combat/Quarry.gd` is v1's Reticle re-expressed: the pick is made **in the picture** (`Contour.locate_seen` — the same posed rings the painter draws, read through the one projection it draws them with), scored in one currency across bodies and bare ground, then answered a second time for the animal about to act on it — reachable, or a mark brought in along the aim line to the purse with what was wanted kept on `beyond`. `ui/AimMark.gd` is TargetMark: the ring in the picture, the tick on the ground plane and the drop between them, the traced ring the bite would take, and the purse drawn as the arc it is. The lab's LMB is now the animal's (press = strike, held = the jaws keep what they close on, released = let go on the frame, release observed even over the HUD and on focus loss); node-dragging moved to RMB.

*Two things the wiring taught, both written into the files. **A look must be invisible to the solver.** A driven chain is solved head-first, so a neck swept in front of the relaxation tows the whole animal along behind its own gaze — 64 px of body for a 24 px lunge. The sweep is taken off at the top of the tick and put back after the solve (`look_offset`, the same kinematic discipline the lateral wave is under, and rotated by `rotate_followers` so it comes off along the bearing it went on). **And a lunge stays the body moving.** Aiming the head at the contact *during the throw* let the jaws arrive somewhere the animal never went and let go of it again as the sweep came home — a hold formed a pixel closer to its own tear threshold, which the first chew then spent. So the strike is thrown along whatever the look was already doing, and a latched mouth looks at nothing at all: the hold is a geometry the tether already owns, and pointing the same head at the same flesh is two mechanisms on one bone.*

*Gate passed — `tests/AimProbe.gd`: the head turns 79° off its shoulders for a cursor at right angles (the neck's own joints would give 166°, the cap is what stopped it) and comes home to 0.0° with nothing to look at, at a cost to the standing body of 0.00 px and 0.0° of heading and 0.0° of shoulder; walking, the body comes round 43° onto the look and finishes 2.6° off it, where the same look standing steers 0.0°; asked hard right with the cursor hard left the body goes 239° right; a cursor on a drawn flank names trunk t 0.52 at z 35 where open floor is ground, and the same flesh from two body lengths off stops at the purse on the aim line with what was wanted kept behind it; a click takes 21.2 px of throw, carries the body 15.2 px and opens the prey; a snap at bare floor is still thrown and carries the body 24.2 px; held jaws close and keep, released let go on the frame, and an unheld bite takes flesh and comes away with nothing; anatomy exact throughout (0.0000 px / 0.0000 rad). CombatProbe, MotionProbe, ArmatureProbe, CorpusProbe, SkinProbe, TippingProbe and ProvingProbe re-run green.*

**Phase 5c — The controls, made to feel like a body. ✅ COMPLETE (2026-08-13)**
Four things wrong with 5b's hand, each fixed at the mechanism rather than at the look.

**The aiming view would not hold still.** `Maw.plan_reach` is what `AimMark` draws its arc at and what the strike is priced against, and it was reading `throw_cap` off `Poise.clearance` — the plumb line's margin inside the polygon its planted toes make. That polygon collapses to a *line* every time the gait has two feet off the ground, which is most of a walk, so the margin swung through zero at the stride's own frequency and the drawn purse pulsed better than two to one, twice a second, while nothing about the animal's ability to lunge had changed. The throw is now priced off a capability: the ground the legs can still catch it on (`Attitude.plan_reach`, the same number `Travel.review` measures a fall against), less how far the weight has *been* hanging out past its feet, low-passed over the time a strike takes to gather. A teetering body stays out for longer than the window and still throws short; a walking one passes through and does not.

**The head strained after cursors it could not see.** The look was clamped to the neck's range, which means a head pinned at the limit still *following* — and a pointer crossing the line dead astern flips the sign of the ask and whips the head from one shoulder to the other for a pixel of mouse movement. `Gaze.radius` is now a real boundary: inside it the pointer drives the head; outside it the pointer has nothing to say about the head at all and the neck keeps the bearing it was left on, which is also the truthful pose, because an animal that cannot see a thing is not looking at it. A `SWEEP_RATE` ceiling under the ease turns the one legitimately large swing — the cursor crossing from shoulder to shoulder — from a cut into a fast head turn. The *body* still answers what the head cannot: `lead` keeps steering on the side the head let go on, so a walking animal turns to bring the thing back into its own field and the head takes it up again with nothing having to notice.

**A and D rotated the animal instead of steering it.** The standstill turn was a rigid pirouette — the front, middle and hind of the body at exactly the same bearing, every tick, spine lag 0.00°. `Armature.steer_front` shares an angle out over the joints of the back, hips first, each swinging what is ahead of it about itself, so every stick keeps the length the solve just gave it and what the body ends up in is a bend rather than a spin; `Travel` holds that bend into the turn as a **posture** (a lead proportional to how hard the animal is turning, capped at a share of `back_sweep` scaled by the species' `spine_freedom`) rather than spending a share of the turn rate on it. The two failed alternatives are written into the file: spent as a rate the bend is an integral, and since a back gives most of a circle before the anatomy complains, the animal folds double and falls over inside a second; held to an exact angle it fights every other thing that bends a spine, and a walking turn that had been a wide arc becomes the animal knotting up on the spot. Add-only fixes both, and is why nothing there has to know how fast the animal is going.

**Backward turned the animal round before moving it.** The head is the pinned point of a head-driven solve, so reversing was driving the pin *into* its own chain: the trunk had to go somewhere, went sideways, and the creature ended up facing back the way it came without one degree of it reaching `heading`. A body going backwards is *pushed*, not pulled — nothing is out in front of it to follow — so the whole animal is now carried by `Armature.shift` (feet staying put, the drift being how the legs learn) and the head rides on it, and a pushed body turns as one piece.

*Gate passed — `tests/AimProbe.gd`, three new claims alongside the eight: the field is 82° either way and the head tracks inside it, lets go at 78° and then holds a bearing to 0.0° while the body stands, with a worst single-tick swing of 1.9° through a cursor swept two hundred degrees round the animal; walking, an animal pointed at something dead astern comes 208° round to it and its head takes the cursor back up after 0.55 s; the drawn purse measures 52.7 px standing and 52.6–52.7 px through a walk — 0 % ripple, against the 94 % it swung before. `tests/MotionProbe.gd`, two: the standstill turn still swings 2.94 rad in 2 s on 36 steps but wanders 3.5 px rather than 6.2 and leads with 37° of back rather than 0°; and 2.5 s of reverse carries the body 127 px backwards and 0.3 px aside, on 17 steps, with the heading held to 0.0° and the back 0° off the way it set out facing. Anatomy exact throughout on both (0.0000 px / 0.0000 rad). CombatProbe, ArmatureProbe, CorpusProbe, SkinProbe, TippingProbe, ProvingProbe, ScenarioProbe, SprintProbe, PlumbProbe and SilhouetteProbe re-run green.*

*Known limit, stated rather than hidden: `heading` is still an open-loop integral and a hard turn at cruise leaves it ~45° ahead of the back it is supposed to describe (it was ~64° before this pass, so the steer improved it, but did not close it). Every bound tried here deadlocked instead — the body's only way round **is** the ask, so throttling the ask freezes the pair — and closing it honestly means giving the body a way to come round that does not run through `ang_vel`. Left alone deliberately.* **Closed in 5d, from the other end — see below.**

**Phase 5d — One hand on the body, one eye on the world. ✅ COMPLETE (2026-08-13)**
Two complaints, and the second of them turned out to be the answer to 5c's known limit.

**The bite zone was drawing a promise the animal could not keep.** `AimMark` swept its arc at `Maw.ADDRESS_CONE` — the frontal cone, 100° either side of the heading — while the thing that actually has to deliver a bite is the neck, which on this cat gives 82°. Eighteen degrees a side of arc that was never reachable, and drawn from the *heading* rather than from the shoulders the neck is rooted on, so mid-turn the whole region sat somewhere the animal was not. `Maw.window` is now the one authority: the intersection of the neck's own available rotation (`Gaze.radius` — the cervical joints' sum, so the field a short-necked animal aims in and the field it bites in are one number) with the cone a body can face, carried into the shoulders' frame where the neck's half is centred. It goes honestly lopsided when the heading runs ahead of the back, because an animal mid-turn really can reach further round the inside of its turn than the outside. `plan_reach` returns the radius — arm plus lunge plus gape, less what the height costs — and now returns **zero** outside the band the mouth can be carried through, because a plan view cannot draw the vertical gate and leaving it silently out was the last way the arc could lie. `aim` refuses on those same two numbers, measured from the same root, so the drawing is not a picture *of* the reach test, it is the reach test's own arithmetic.

**A target you cannot bite is not a target.** `Quarry.resolve` used to bring the marker in to the edge of the purse and keep what had been pointed at hanging off it on `beyond`, with a dotted line between the two — the correct fact ("that is what you wanted, this is as far as you get") offered in the shape of a selection. It was not one: the strike does not go to that flesh, and the highlight was tracing rings on a body the jaws could not touch. Outside the zone the target is now dropped where it stands — no creature, no address, so no highlight and nothing for a line to join — and what is left is a position and `Pick.outside`, which the mark draws as a refusal on the spot the player is pointing at. `beyond`, `selected()`, `_short_of` and `CLAMP_MARGIN` are gone with it. The click is not swallowed: a body that has committed to a lunge lunges, and `Maw.strike` sends it along the head's own bearing when the point is one the neck could never have been brought round onto — which is both where the jaws were always going to arrive from and the one direction the player can see, because the head is drawn.

**Mouse look and body steering are now completely separate.** `Gaze.lead` is deleted. It was a good idea about animals — a walking creature turns to follow its gaze — and a bad one about controls: two things wanted `heading`, the player had authority over only one of them, and every glance across the lab quietly re-aimed the walk. A and D are the sole writers of the heading now, and the probe sweeps a cursor right round a walking animal to prove it.

**A and D turn a third as fast, and the body keeps up.** `turn_speed_deg` 210 → **90**. On the crouched carriage this animal stands in (agility 1.30) the old number came out at **264 °/s** on the spot — three quarters of a revolution a second from one key — and, worse, it outran the body it was describing: `heading` is an integral and the trunk follows only as fast as the feet will walk it round, so at cruise the two ended up 49° apart and every contact, gait and aim in the game was quoting a direction the drawn creature was not pointing. 90 is chosen as the rate at which *that* stops, which is why it is 90 and not merely something slower. `turn_responsiveness` 14 → **6**, so the rate builds and decays over about a sixth of a second instead of switching.

*Which broke the wall, and the break was worth the file it is now documented in.* `turn_responsiveness` was easing two different things through one line: the animal taking up a turn it chose, and the animal shedding a yaw a rock had just put into its shoulder. Weighted enough to feel like a body, the second one stops working — the glancing torque off a round obstacle never died, and an animal that used to brace against it walked round it at full cruise instead. They are separate quantities and they now add: `Travel._asked` eases onto the hand's demand at the species' own responsiveness, `Travel._spin` takes every external twist and sheds it at `BRACE` times that, and `ang_vel` is their sum and is written nowhere else. Bracing came out *better* than it was before the change (peak unasked spin 0.10 rad/s against 0.10, heading held to 8°).

*Gate passed — `tests/AimProbe.gd`, restructured around the separation: a cursor swept a full 360° round a **walking** animal moves the heading **0.0°**, and held dead astern of a standing one costs it 0.0° and 0.0 px; the bite zone measures 82° a side off an 82° neck and 62.6 px of arm + lunge + gape, and across 96 places swept round the animal at four rings — bearing by bearing, inside the boundary and out — **0 were drawn reachable and then refused, and 0 the jaws would take were drawn outside**; flesh at the jaws is a target, floor half a reach astern is refused for being astern, flesh two body lengths off is no target at all (no address, nothing for a line to reach) and the click still throws 22.7 px along the head; the standing turn runs at 108 °/s with the back within 26° of the heading and the walking turn at 54 °/s within 16°, both of those with the sign of the **steer** — the front of the animal ahead of the back of it — rather than of a heading running away from its own body; worst rate ramp 668 °/s² standing, and a released key coasts out rather than stopping dead. `tests/MotionProbe.gd`: the standstill turn now takes 20 steps and 1.3 px of wander where it took 36 and 3.5, still leading with 37° of back, and the wall still stops the walk at 4.3 px/s. Anatomy exact on both (0.0000 px / 0.0000 rad). CombatProbe, ArmatureProbe, CorpusProbe, SkinProbe, TippingProbe, ProvingProbe, ScenarioProbe, SprintProbe, PlumbProbe and SilhouetteProbe re-run green; `tests/AimShot.gd` re-rendered.*

*5c's known limit is closed as a side effect and should be read as retired: the heading no longer runs ahead of the back at all. What is left between them (−16° at cruise, −26° standing) is the steer's own lead, which is the body doing the right thing. It was never a bound that was needed — it was a rate that was wrong.*

**Phase 6 — UI port.**
`BodyReadout` implemented on the v2 creature; drawers ported one at a time (suggested order: GaitPanel → SpecimenMesh view → AnatomyView/AnatomyPanel → CreatureCreator → EvolutionHUD vitals). Shell untouched.
Gate: F3 cycle fully working against v2 in the lab; UIInteractionTest claims (note: the sphere-drag checks were already red on clean v1 main — do not chase them as regressions).

**Phase 7 — Cutover & deletion.**
Main spawns the v2 creature; senses/world hooks (ScentField, CarrionField, SoundField read positions/masses — thin adapters); one commit deletes `scripts/creature/` v1 files + lattice-era tests; remaining tests re-pinned; memory/docs updated.
Gate: full game session parity — spawn, walk, hunt, bite, feed, die.

### 11.3 Sequencing notes & risks

- **Phases 1–2 are deliberately small and gate everything.** If the schema needs a change, it must happen before Phase 3 starts consuming it.
- **Phase 3 is the schedule risk** (biggest port, subtlest behaviour). Mitigation: the v1 oracle running side-by-side, and porting Gait's tables verbatim before touching its inputs.
- **Two creatures of code coexist for the whole rebuild.** Class-name collisions are the practical annoyance — suffix v2 classes (`Armature`, `Corpus`, `Poise`, `SpecimenMesh2`…) and never reuse a v1 class_name until Phase 7's deletion.
- **Scope discipline:** no new features during the rebuild (no climbing, no new senses, no extra species beyond the cat). Second species (retune knots, re-pin probe) is the *first post-v2 task* and the proof the authoring layer works.

---

## 12. Decisions taken in this draft (override here, before Phase 0)

| # | Decision | Chosen | Rejected |
|---|---|---|---|
| 1 | Chain dimensionality | 2.5D — Vector3 nodes, plan-dominant solving (§4.1 B) | full 3D solver |
| 2 | Station density | ~32 functional nodes; render rings interpolated (§4.3 B) | per-vertebra |
| 3 | Census structure | body-space polar cells (station × sector × layer), hp on cells (§5.2) | any world-space grid |
| 4 | Authoring | knots → station ellipses → cells (§5.3 C) | raw cells; ellipses only |
| 5 | Strength mapping | 5 muscle compartments (§7.3 B) | per-joint accounting |
| 6 | Soft body | material compliance on capsule contacts + visual dents (§7.5, §9.1) | soft-body dynamics |
| 7 | Rebuild mode | alongside in-repo, v1 as oracle, delete last (§11.1) | in-place; strip-first; fork |
| 8 | Attitude (the §4.1 revisit) | dynamics on the body *frame* — one roll state in `Keel`, turning about the ground, with the legs' righting clamped by the census (§4.1a) | full 3D Verlet; rolling the plan solve; a second gravity |
