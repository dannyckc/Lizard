## The unified Verlet chain graph — v2's entire physics skeleton.
##
## One rooted graph of sticks and joints (docs/V2_DESIGN.md §4): the trunk is
## the root chain, the neck (with the head node), the tail and the four limbs
## hang off its girdle stations. This file is the successor of Spine.gd's
## Verlet core, Fabrik.gd, the limb joint chains, Stature's neck arc and
## Ragdoll.gd — one graph, one solver, so the whole creature is solved by one
## geometric idea (circle projection) the way v1's spine and limbs already
## separately were.
##
## Dimensionality is 2.5D by decision (§4.1 B): nodes are Vector3 where XY is
## the plan and Z is height, but the constraint solver is plan-dominant —
## distance and angle constraints act on the plan projection exactly as v1's
## proven solver did, while Z is governed by a separate channel (stance
## heights, carry lines, droop, terrain, the fall). All of v1's gait
## mathematics is plan-view math, and it ports because the constraint space
## did not change under it.
##
## The vertical has one owner: `Gravity.PULL` is the pull and `Gravity.Fall`
## is the integrator, both from scripts/world/Gravity.gd, and nothing in this
## file introduces a second of either. What this file adds in Z is *statics* —
## a cantilevered neck or tail sagging below its carry line by the beam law,
## ported from v1's Droop — which is gravity read at a place, not integrated.
##
## Ragdoll is not a second solver, it is this one with the constraints
## loosened: no drive, no stance, limbs integrated instead of placed, and the
## same anatomical invariants — exact stick lengths, legal bends — holding
## whether the animal is alive or not.
##
## Nothing pose-derived is a build input. `build` reads the BodySpec (rest
## anatomy) only; the live pose only ever transforms what was built.
class_name Armature
extends RefCounted

## Below this much plan motion in one tick a point is asleep and gives up its
## implied velocity — Spine's rest pass, ported with its number. Without it,
## joints parked exactly on a bend limit trade a sub-micron correction back
## and forth forever and the residue ratchets the body across the world.
const REST_EPSILON: float = 0.005

## Section grading of the bend limits, from Spine: a vertebra's grip goes with
## the section it is cut from, so a joint at the thin end of a taper folds
## LIMBER_BEND times further than the stoutest station's limit, and no station
## may count as less than MIN_SECTION of the stoutest or the tip has no limit
## holding it at all.
const LIMBER_BEND: float = 1.5
const MIN_SECTION: float = 0.06

## Inertia the free chain keeps between ticks when nothing is driving the
## body — ground friction as heavy damping, from v1's dead solve.
const RAGDOLL_DAMPING: float = 0.5

## The dead-limb constants, ported from Ragdoll.gd with their reasons: heavy
## damping is ground friction, not softness; two bones and two limits settle
## in very few passes; and a limp joint closes much further than a walking one
## ever does because the limit is the joint itself, not the muscle around it.
const LIMB_DAMPING: float = 0.35
const LIMB_ITERATIONS: int = 4
const FOLD_MAX_DEG: float = 128.0

## The droop walk, ported from Droop.gd. DROOP_LIMBER is v1's LIMBER (0.02)
## times 4/π, because v1 accumulated width²·segment volume and this file
## accumulates the node masses themselves (mass = π·r²·segment, so the two
## differ by exactly that factor); the calibration is the same calibration.
## DEAD_HOLD is what survives when the muscle stops — a spine is not a rope.
## CARRIAGE is how much of the hold is the animal actively carrying the limb
## against simply being tissue; Phase 1 bodies stand still, so the standing
## share (1 − CARRIAGE) is what they hold with.
const DROOP_LIMBER: float = 0.02 * 4.0 / PI
const DROOP_MIN_WIDTH: float = 1.5
const DEAD_HOLD: float = 0.05
const CARRIAGE: float = 0.45

## FABRIK settings for placed limbs, from v1.
const FABRIK_ITERATIONS: int = 8
const FABRIK_TOLERANCE: float = 0.05


## One chain of the graph. Node and stick entries are indices into the flat
## body arrays; `nodes` is root-first and `sticks` attach-first, so stick j
## leads INTO node j (from the parent node for j = 0).
class Chain extends RefCounted:
	var name: StringName
	var kind: StringName
	var nodes: PackedInt32Array = PackedInt32Array()
	var sticks: PackedInt32Array = PackedInt32Array()
	var parent_node: int = -1
	var attach_hold: float = 1.0
	var carry_rad: float = 0.0
	var limb: bool = false
	var side: float = 0.0
	var foot_lead: float = 0.0
	## The three bone lengths of a limb (upper, lower, paw).
	var bones: PackedFloat32Array = PackedFloat32Array()
	## A limb's persistent sagittal solution (x along the body axis from the
	## socket, y absolute height). Kept between ticks because FABRIK stays on
	## whichever side of the root→target axis it starts on — this IS the pole.
	var sag: PackedVector2Array = PackedVector2Array()
	## Seed bend direction per interior joint, used to re-pole a limb that has
	## gone collinear (after a drop straightens it): fore elbows point back,
	## hind knees point forward, and a straight chain has forgotten which.
	var pole: PackedFloat32Array = PackedFloat32Array()
	## The plan direction the limb's own solve plane runs along — socket toward
	## foot, kept between ticks so a foot arriving directly beneath its socket
	## does not lose the plane it was being solved in.
	var plane: Vector2 = Vector2.RIGHT
	## Where the gait has put this foot, in three dimensions, and how high it is
	## holding its own corner of the body. Written by whatever owns the feet and
	## read by the placement; `foot_driven` is false until something does, and then
	## the limb stands in the rest stance the build was laid out in. Nothing owns
	## them at present — the movers are out for rewrite — so this is the whole of
	## what a v2 body does with its legs today.
	var foot_target: Vector3 = Vector3.ZERO
	var socket_rise: float = 0.0
	var foot_driven: bool = false
	## Whether this foot is bearing on something. Written by the gait, which is the
	## only thing that knows: a planted foot is not "a foot at height zero" once the
	## toe rolls the ankle up off the ground, and it is not on the ground at all on a
	## limb the animal is merely carrying.
	var grounded: bool = false
	## How far the free end hangs below its carry line — the droop readout.
	var tip_sag: float = 0.0


var spec: BodySpec

# Flat node arrays. XY is the plan, Z is height; `prev` is the Verlet history
# of the plan (its Z always mirrors pos, because Z is assigned, not
# integrated). `pinned` nodes are placed, not simulated — nothing moves them
# but their owner (the head under input from Phase 3 on).
var pos: PackedVector3Array = PackedVector3Array()
var prev: PackedVector3Array = PackedVector3Array()
var pinned: PackedByteArray = PackedByteArray()
var fwd: PackedVector2Array = PackedVector2Array()
var perp: PackedVector2Array = PackedVector2Array()

## Per-node mass and flesh radius — the census's numbers, baked here by
## Poise.bake so the Z channel has a weight and a beam width to hang off each
## station. The Corpus is the owner; this is the copy it drives the armature
## through, and an armature nobody has baked carries no weight (its chains
## ride their carry lines with no droop until the census arrives).
var mass: PackedFloat32Array = PackedFloat32Array()
var flesh_r: PackedFloat32Array = PackedFloat32Array()

# Stick arrays. `stick_bone` is the anatomical length; `stick_plan` is the
# foreshortened plan rest (bone × cos carry) the plan solver holds while the
# chain is carried — v1's neck pullback, generalised. A dead chain lies flat,
# so the dead solve holds the full bone length instead.
var stick_a: PackedInt32Array = PackedInt32Array()
var stick_b: PackedInt32Array = PackedInt32Array()
var stick_bone: PackedFloat32Array = PackedFloat32Array()
var stick_plan: PackedFloat32Array = PackedFloat32Array()
## The plan rests as built, so the back's own folding is applied to the build
## rather than to last tick's answer and cannot accumulate.
var stick_plan_rest: PackedFloat32Array = PackedFloat32Array()
var stick_radius: PackedFloat32Array = PackedFloat32Array()
## Compliance of the stick, 1.0 rigid. Only girdle attach sticks are below
## one — the muscle-slung scapula — and in Phase 1 those are satisfied by
## construction (sockets are placed); the compliance becomes load-bearing when
## contacts arrive in Phase 5.
var stick_hold: PackedFloat32Array = PackedFloat32Array()

## The axial polyline in solve order: tail tip → pelvis → withers → head.
## The whole axial body is one chain to the solver — that is what v1 proved
## stable — while the Chain objects keep the per-chain addressing the census
## and the features need.
var axial: PackedInt32Array = PackedInt32Array()
## Stick index between axial[k] and axial[k+1].
var axial_stick: PackedInt32Array = PackedInt32Array()
## Graded bend limit at interior vertex axial[k+1], radians — authored cone
## limit taken per chain (the junction takes the stricter neighbour), then
## graded by section exactly as Spine.bend_at: thin stations fold further.
var axial_bend: PackedFloat32Array = PackedFloat32Array()

var chains: Dictionary = {}
var limbs: Array[Chain] = []

## The body datum's height above the local surface — 0 standing on it. The
## world's one integrator; a drop, a collapse and a leap all live here.
var fall: Gravity.Fall = Gravity.Fall.new()
var collapsed: bool = false

## Whether something is driving the head. A driven body is solved head-first with
## every correction flowing away from the pin, which is what makes a chain follow
## where it is led; a free one is solved symmetrically, because there is no
## authoritative point on a carcass and keeping one would quietly make it the
## anchor the rest of the body hangs off.
var driven: bool = false

## What the legs are holding each girdle at, in world height. Written by the gait
## once it has measured its feet and standing at what the rest stance delivers
## until then — a body with no gait solved has no feet to be standing on. The Z
## channel reads these and nothing else decides the trunk's height.
var fore_carry: float = 0.0
var hind_carry: float = 0.0

## How far the body is heeled over about its own fore-and-aft axis, radians,
## positive with the animal's right side down.
##
## Assigned, never integrated — the same law the heights already live under, and
## for the same reason: `Keel` is the one attitude integrator and `Travel` writes
## its answer here once a tick, exactly as Footwork writes the carries above.
## What this file does with it is *express* it — the trunk heels about its own
## feet, the limb sockets on the low side drop and the high ones lift, and a body
## that has gone over lies on its flank instead of on its belly. `Contour` reads
## the same number for its ring frames, so the drawn animal and the solved one
## cannot disagree about which way up it is.
var roll: float = 0.0
## What it was when the limbs were last settled — the tumble's carry is the
## difference, and nothing else reads it.
var _rolled: float = 0.0

## Where the mouth is being carried this tick, world height — NAN when nothing
## is reaching and the neck rides its rest carry line. Written by the strike
## (a bite at the floor carries the head down to it, one at a tall flank
## carries it up), read by the Z channel as the neck's carry slope: the head
## moving to the flesh moves the drawn head, the jaw frame and the mouth's hit
## band, because they are all the same nodes. The droop still sags below
## whatever line this asks for — muscle carries the reach, tissue still hangs.
var head_reach_z: float = NAN

## Phase of the travelling lateral wave, and how far it has already displaced each
## node. The wave is kinematic: it moves the body, it never pushes it, so only the
## *difference* is applied and it is applied to the Verlet history as well — shift
## `pos` alone and the integrator takes the wave's per-tick displacement for real
## motion, carries it forward at the damping and re-injects it, and the chain
## resonates until the tail whips at tens of times the intended amplitude.
var wave_clock: float = 0.0
var wave_offset: PackedVector2Array = PackedVector2Array()

## How far the back is currently folded along its own length — see `bunch`.
var bunched: float = 0.0

var spawn_at: Vector2 = Vector2.ZERO
var spawn_heading: float = 0.0

# Cached derivations of the spec, set at build.
var body_length: float = 0.0
var fore_stance: float = 0.0
var hind_stance: float = 0.0
## How far each girdle carries its sockets out from the spine — the half-base a
## heel turns about, and the same number the sockets are placed at.
var fore_half: float = 0.0
var hind_half: float = 0.0
var _trunk: Chain
var _neck: Chain
var _tail: Chain


# ------------------------------------------------------------------ build ----

## Builds the graph from rest anatomy and lays it out standing at `at` facing
## `heading`. Everything here reads the spec; nothing here reads a pose.
func build(p_spec: BodySpec, at: Vector2, heading: float) -> void:
	spec = p_spec
	spawn_at = at
	spawn_heading = heading
	chains.clear()
	limbs.clear()

	var specs: Array[BodySpec.ChainSpec] = spec.chains()
	var total_nodes: int = 0
	for c in specs:
		total_nodes += c.node_count
	pos.resize(total_nodes)
	prev.resize(total_nodes)
	pinned.resize(total_nodes)
	pinned.fill(0)
	fwd.resize(total_nodes)
	perp.resize(total_nodes)
	mass.resize(total_nodes)
	flesh_r.resize(total_nodes)

	stick_a.clear()
	stick_b.clear()
	stick_bone.clear()
	stick_plan.clear()
	stick_plan_rest.clear()
	stick_radius.clear()
	stick_hold.clear()

	# First pass: allocate nodes and sticks chain by chain. The trunk must
	# come first so attached chains can name its stations.
	var next_node: int = 0
	for c in specs:
		var chain := Chain.new()
		chain.name = c.name
		chain.kind = c.kind
		chain.attach_hold = c.attach_hold
		chain.carry_rad = deg_to_rad(c.carry_deg)
		chain.limb = c.limb
		chain.side = c.side
		chain.foot_lead = c.foot_lead
		for i in c.node_count:
			chain.nodes.append(next_node)
			next_node += 1
		if c.attach_chain != &"":
			var parent: Chain = chains[c.attach_chain]
			chain.parent_node = parent.nodes[c.attach_index]
		var plan_share: float = cos(chain.carry_rad)
		for j in c.lengths.size():
			var a: int
			var b: int
			if c.attach_chain == &"":
				a = chain.nodes[j]
				b = chain.nodes[j + 1]
			else:
				a = chain.parent_node if j == 0 else chain.nodes[j - 1]
				b = chain.nodes[j]
			chain.sticks.append(stick_a.size())
			stick_a.append(a)
			stick_b.append(b)
			stick_bone.append(c.lengths[j])
			stick_plan.append(c.lengths[j] * plan_share)
			stick_radius.append(c.radii[j])
			stick_hold.append(c.attach_hold if (c.limb and j == 0) else 1.0)
		if c.limb:
			chain.bones = c.lengths.slice(1)
			limbs.append(chain)
		chains[c.name] = chain

	_trunk = chains[BodySchema.TRUNK]
	_neck = chains[BodySchema.NECK]
	_tail = chains[BodySchema.TAIL]

	# The weights arrive from the census: Poise.bake fills these from Corpus
	# after every build and every wound. Zero until then — see the field note.
	mass.fill(0.0)
	flesh_r.fill(0.0)

	stick_plan_rest = stick_plan.duplicate()
	_build_axial()
	fore_stance = spec.stance_height(true)
	hind_stance = spec.stance_height(false)
	fore_half = 0.0
	hind_half = 0.0
	for limb in limbs:
		var out: float = stick_bone[limb.sticks[0]]
		if limb.parent_node == _trunk.nodes[0]:
			hind_half = maxf(hind_half, out)
		else:
			fore_half = maxf(fore_half, out)
	fore_carry = fore_stance
	hind_carry = hind_stance
	wave_offset.resize(total_nodes)
	wave_offset.fill(Vector2.ZERO)
	body_length = 0.0
	for k in axial_stick.size():
		body_length += stick_bone[axial_stick[k]]

	_layout(at, heading)


## The axial solve order and its graded bend limits. The junction vertices
## (pelvis, withers) take the stricter of the two chains meeting there; every
## limit is then graded by the section it is cut from, so the tail folds
## further out where it is thin and nobody authored that.
func _build_axial() -> void:
	axial.clear()
	axial_stick.clear()
	axial_bend.clear()

	var tail_nodes: PackedInt32Array = _tail.nodes.duplicate()
	tail_nodes.reverse()
	axial.append_array(tail_nodes)
	axial.append_array(_trunk.nodes)
	axial.append_array(_neck.nodes)

	var tail_sticks: PackedInt32Array = _tail.sticks.duplicate()
	tail_sticks.reverse()
	axial_stick.append_array(tail_sticks)
	axial_stick.append_array(_trunk.sticks)
	axial_stick.append_array(_neck.sticks)

	# Base cone limit per stick = its owning chain's authored limit; a
	# vertex's base = the stricter of its two sticks. Uniform per chain today;
	# per-joint authoring can refine this without touching the solver.
	var stick_base: Dictionary = {}
	var specs: Array[BodySpec.ChainSpec] = spec.chains()
	for c in specs:
		if c.limb:
			continue
		var chain: Chain = chains[c.name]
		var base: float = c.bend_deg[0] if not c.bend_deg.is_empty() else 30.0
		for s in chain.sticks:
			stick_base[s] = deg_to_rad(base)

	var stoutest: float = 0.0
	for k in axial_stick.size():
		stoutest = maxf(stoutest, stick_radius[axial_stick[k]])
	for k in range(axial_stick.size() - 1):
		var incoming: int = axial_stick[k]
		var outgoing: int = axial_stick[k + 1]
		var base: float = minf(stick_base[incoming], stick_base[outgoing])
		var section: float = (stick_radius[incoming] + stick_radius[outgoing]) \
			* 0.5 / maxf(stoutest, 0.001)
		var hold: float = clampf(section * section * section, MIN_SECTION, 1.0)
		axial_bend.append(base * lerpf(LIMBER_BEND, 1.0, hold))


## Lays the body out standing: axial chain straight along the heading, limbs
## solved to their stance. Also the whole of `reset`.
func _layout(at: Vector2, heading: float) -> void:
	var dir: Vector2 = Vector2.RIGHT.rotated(heading)
	# Walk the axial line pelvis-first so the trunk sits over `at`.
	var pelvis: int = _trunk.nodes[0]
	var along: Dictionary = {pelvis: 0.0}
	var run: float = 0.0
	for j in range(1, _trunk.nodes.size()):
		run += stick_plan[_trunk.sticks[j - 1]]
		along[_trunk.nodes[j]] = run
	run = along[_trunk.nodes[_trunk.nodes.size() - 1]]
	for j in _neck.nodes.size():
		run += stick_plan[_neck.sticks[j]]
		along[_neck.nodes[j]] = run
	run = 0.0
	for j in _tail.nodes.size():
		run -= stick_plan[_tail.sticks[j]]
		along[_tail.nodes[j]] = run

	for node: int in along:
		var p: Vector2 = at + dir * along[node]
		pos[node] = Vector3(p.x, p.y, 0.0)
		prev[node] = pos[node]

	collapsed = false
	driven = false
	pinned.fill(0)
	roll = 0.0
	_rolled = 0.0
	fore_carry = fore_stance
	hind_carry = hind_stance
	head_reach_z = NAN
	wave_clock = 0.0
	wave_offset.fill(Vector2.ZERO)
	bunched = 0.0
	for s in _trunk.sticks:
		stick_plan[s] = stick_plan_rest[s]
	fall.rest_on(0.0)
	_compute_frames()
	_solve_heights(0.0)

	# Limbs: seed the sagittal pose bent the way that limb bends — elbows
	# back, knees forward — then let the placement solve stand them.
	for limb in limbs:
		var fore: bool = limb.parent_node != _trunk.nodes[0]
		limb.foot_driven = false
		limb.plane = dir
		limb.pole = PackedFloat32Array([-1.0, 1.0] if fore else [1.0, -1.0])
		limb.sag = PackedVector2Array()
		limb.sag.resize(4)
		var socket_z: float = pos[limb.parent_node].z
		limb.sag[0] = Vector2(0.0, socket_z)
		limb.sag[1] = Vector2(limb.pole[0] * 3.0, socket_z * 0.6)
		limb.sag[2] = Vector2(limb.pole[1] * 3.0, socket_z * 0.25)
		limb.sag[3] = Vector2(limb.foot_lead, 0.0)
	_place_limbs(0.0)
	_compute_frames()


func reset() -> void:
	_layout(spawn_at, spawn_heading)


# ------------------------------------------------------------------- step ----

## One whole tick, in the order the body is solved in: the chain settles, the
## heights are assigned, the limbs are placed. `surface` is what is under the
## animal, asked every time rather than kept, because the habitat has terrain.
##
## The three halves are also callable on their own, and the gait needs them to be:
## it reads the sockets the chain has just settled into, works out where the feet
## go and how high the feet are holding the body, and only then may the heights and
## the limbs be solved. Anything with no gait — a probe, a carcass — calls this and
## gets the whole tick in one line.
func step(delta: float, surface: float = 0.0) -> void:
	advance(delta)
	carry(surface)
	settle(delta, surface)


## The plan solve: inertia, the wave, relaxation, rest, frames. Everything that
## happens in the two horizontal dimensions — plus the one vertical integration,
## because the fall is advanced with the plan it is falling over. `floor` is the
## fall's floor *in the carried frame*: how much higher (or lower) the ground now
## under the body stands than the ground its feet took off from, so a leap comes
## down on the surface it is actually over. Grounded it is simply 0 — the feet
## are the frame, and the carries already quote them.
func advance(delta: float, fall_floor: float = 0.0, speed_norm: float = 0.0,
		wave_gain: float = 0.0) -> void:
	fall.advance(delta, fall_floor)
	var live: bool = not collapsed
	_integrate_plan(live)
	if live and wave_gain > 0.0:
		_wave(delta, speed_norm, wave_gain)
	if live and driven:
		_relax_driven()
	else:
		_relax_plan(live)
	_rest_plan()
	_compute_frames()


## The Z channel — see `_solve_heights`.
func carry(surface: float = 0.0) -> void:
	_solve_heights(surface)


## The limbs: placed where the gait put their feet while the body is alive, and
## integrated from their sockets when nothing is holding them out. The tumble is
## an integration and takes the tick it is integrating over.
func settle(delta: float, surface: float = 0.0) -> void:
	if collapsed:
		_tumble_limbs(delta, surface)
	else:
		_place_limbs(surface)
	# The heel this tick's limbs were solved at. A placed limb re-derives itself
	# from its socket every tick and does not care; a tumbled one is carried by
	# the *change*, and it has to be the change since it was last carried.
	_rolled = roll


## The travelling lateral wave. Kinematic and speed-locked: the phase advances with
## how fast the animal is going, the envelope is zero at both free ends, and the
## amplitude dies out at rest. What it is *for* is not the look — it is that a
## socket carried sideways by the body's own undulation has that much less of its
## disc left to stride with, which the gait is expected to measure off the socket
## rather than predict.
func _wave(delta: float, speed_norm: float, gain: float) -> void:
	wave_clock += delta * spec.wave_speed * (0.35 + 0.65 * clampf(speed_norm, 0.0, 1.0))
	var n: int = axial.size()
	for k in n:
		var i: int = axial[k]
		if pinned[i] != 0:
			continue
		var t: float = float(k) / float(maxi(n - 1, 1))
		var envelope: float = sin(t * PI)
		var phase: float = sin(wave_clock * TAU - t * spec.wave_frequency * TAU)
		var target: Vector2 = perp[i] * (phase * spec.body_wave * gain
			* clampf(speed_norm, 0.0, 1.0) * envelope)
		var shift: Vector2 = target - wave_offset[i]
		pos[i] = pos[i] + Vector3(shift.x, shift.y, 0.0)
		prev[i] = prev[i] + Vector3(shift.x, shift.y, 0.0)
		wave_offset[i] = target


## Verlet inertia on the axial plan. Storing prev before adding the velocity
## means next tick's implied velocity includes whatever the constraints did —
## the solver's corrections feed back as real motion, which is the soft feel.
func _integrate_plan(live: bool) -> void:
	var damping: float = spec.spine_damping if live else RAGDOLL_DAMPING
	for k in axial.size():
		var i: int = axial[k]
		if pinned[i] != 0:
			continue
		var vel: Vector2 = (_p2(i) - Vector2(prev[i].x, prev[i].y)) * damping
		prev[i] = pos[i]
		_set_p2(i, _p2(i) + vel)


## Relaxation over the axial chain — the ported free solve. No point on this
## body is authoritative in Phase 1 (nothing drives it), so both halves of
## every distance constraint move and the passes alternate direction so
## neither end accumulates the residue of the other. Full strength, every
## pass: the give that spine_stiffness buys is muscle tone against the body's
## own motion, and a standing or dead body has none to speak of. (The driven
## head-pin solve returns with locomotion in Phase 3.)
func _relax_plan(live: bool) -> void:
	var n: int = axial.size()
	var passes: int = maxi(spec.constraint_iterations, 1)
	for it in passes:
		if it % 2 == 0:
			for k in range(1, n):
				_solve_stick(k - 1, live)
				if k >= 2:
					_solve_bend(k - 2, k - 1, k)
		else:
			for k in range(n - 1, 0, -1):
				_solve_stick(k - 1, live)
				if k <= n - 3:
					_solve_bend(k, k + 1, k + 2)


## Relaxation over a chain something is leading.
##
## Not `_relax_plan` with a pin in it, and the difference is the whole reason it is
## a separate solve: here the head is authoritative, so every pass walks strictly
## from it and only ever moves the *child* of a joint — corrections flow away from
## the head and the head stays exactly where the drive put it. Distance is fixed
## first, then the bend limit rotates the child about its parent, which preserves
## the distance just fixed, so one pass settles both for a given joint.
##
## The soft passes remove only part of the error, so the chain reaches its shape
## gradually and reads as flexible rather than jointed. The last pass is always full
## strength, and that is not optional: partial correction on a long chain is only
## marginally stable — each joint re-injects roughly as much error into its child as
## it removes — so a soft-only solve lets a long spine visibly stretch. One
## full-strength sweep projects every point exactly onto its parent's circle, which
## makes stick lengths exact however low the stiffness is set.
func _relax_driven() -> void:
	var n: int = axial.size()
	var passes: int = maxi(spec.constraint_iterations, 1)
	for it in passes:
		var hold: float = 1.0 if it == passes - 1 else clampf(spec.spine_stiffness, 0.0, 1.0)
		for k in range(n - 1, 0, -1):
			var s: int = axial_stick[k - 1]
			_set_p2(axial[k - 1], _draw_to_circle(_p2(axial[k - 1]), _p2(axial[k]),
				stick_plan[s], hold))
			if k <= n - 2:
				_set_p2(axial[k - 1], _fold(_p2(axial[k + 1]), _p2(axial[k]),
					_p2(axial[k - 1]), axial_bend[k - 1]))


## Distance constraint between axial neighbours k and k+1, both ends moving
## by half the error each — Spine._solve_distance_symmetric, verbatim but for
## the pin weights. The rest length is the plan projection of the bone while
## the chain is carried; a dead chain lies flat and holds the full bone.
func _solve_stick(k: int, live: bool) -> void:
	var s: int = axial_stick[k]
	var ia: int = axial[k]
	var ib: int = axial[k + 1]
	var rest: float = stick_plan[s] if live else stick_bone[s]
	var wa: float = 0.0 if pinned[ia] != 0 else 1.0
	var wb: float = 0.0 if pinned[ib] != 0 else 1.0
	if wa + wb <= 0.0:
		return
	var delta: Vector2 = _p2(ib) - _p2(ia)
	var distance: float = delta.length()
	if distance < 0.00001:
		delta = Vector2.RIGHT
		distance = 1.0
	var correction: Vector2 = delta * ((distance - rest) / distance)
	_set_p2(ia, _p2(ia) + correction * (wa / (wa + wb)))
	_set_p2(ib, _p2(ib) - correction * (wb / (wa + wb)))


## Bend projection at the vertex axial[kb] — Spine._solve_angle_symmetric.
## Both outer particles share the angular correction and the triplet is
## translated back onto its centroid, so the joint reaches its limit without
## choosing an end or injecting net translation.
func _solve_bend(ka: int, kb: int, kc: int) -> void:
	var ia: int = axial[ka]
	var ib: int = axial[kb]
	var ic: int = axial[kc]
	var max_bend: float = axial_bend[kb - 1]
	var incoming: Vector2 = _p2(ib) - _p2(ia)
	var outgoing: Vector2 = _p2(ic) - _p2(ib)
	if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
		return
	var delta: float = wrapf(outgoing.angle() - incoming.angle(), -PI, PI)
	if absf(delta) <= max_bend:
		return
	var correction: float = clampf(delta, -max_bend, max_bend) - delta
	if pinned[ia] != 0 or pinned[ib] != 0 or pinned[ic] != 0:
		# A pinned point is placed by its owner; rotate only what is free,
		# the whole correction onto it, and skip the centroid restore that
		# would shove the pinned point.
		if pinned[ic] == 0:
			_set_p2(ic, _p2(ib) + outgoing.rotated(correction))
		elif pinned[ia] == 0:
			_set_p2(ia, _p2(ib) + incoming.rotated(-correction))
		return
	var centroid: Vector2 = (_p2(ia) + _p2(ib) + _p2(ic)) / 3.0
	_set_p2(ia, _p2(ib) + (_p2(ia) - _p2(ib)).rotated(-correction * 0.5))
	_set_p2(ic, _p2(ib) + (_p2(ic) - _p2(ib)).rotated(correction * 0.5))
	var shift: Vector2 = centroid - (_p2(ia) + _p2(ib) + _p2(ic)) / 3.0
	_set_p2(ia, _p2(ia) + shift)
	_set_p2(ib, _p2(ib) + shift)
	_set_p2(ic, _p2(ic) + shift)


## The rest pass — a point whose whole tick of motion is below perception
## gives its velocity up and is genuinely at rest.
func _rest_plan() -> void:
	for k in axial.size():
		var i: int = axial[k]
		if pinned[i] != 0:
			continue
		if _p2(i).distance_squared_to(Vector2(prev[i].x, prev[i].y)) \
				<= REST_EPSILON * REST_EPSILON:
			prev[i] = Vector3(pos[i].x, pos[i].y, prev[i].z)


## Plan frames along the axial line, pointing toward the head — the basis
## limb sockets and (from Phase 2) ring frames are placed in.
func _compute_frames() -> void:
	var n: int = axial.size()
	for k in n:
		var i: int = axial[k]
		var f: Vector2
		if k < n - 1:
			f = _p2(axial[k + 1]) - _p2(i)
		else:
			f = _p2(i) - _p2(axial[k - 1])
		if f.length_squared() < 0.000001:
			f = fwd[i] if fwd[i].length_squared() > 0.5 else Vector2.RIGHT
		else:
			f = f.normalized()
		fwd[i] = f
		perp[i] = Vector2(-f.y, f.x)


# -------------------------------------------------------------- Z channel ----

## Heights for the axial body. Alive: the trunk is held between its girdles at
## what the legs deliver, heeled over by whatever attitude the body is in, and
## everything past a girdle is a cantilever — the carry line rises at the chain's
## carry angle and the droop walk sags below it by the beam law. Dead: nothing is
## held, and the whole line lies on whichever of its surfaces it came down on
## (plus whatever the fall still owes). Z is assigned, never integrated — the one
## integrator in the vertical is `fall`, and the one in the attitude is `Keel`.
func _solve_heights(surface: float) -> void:
	var clearance: float = fall.height
	if collapsed:
		# A body that went over rests its spine one half-width off the floor,
		# because it is lying on its flank; one that simply stopped lies on its
		# belly at nothing. Same statement, and the heel is the whole of the
		# difference between being knocked down and being killed.
		var lie: float = absf(sin(roll))
		for k in axial.size():
			var i: int = axial[k]
			var down: float = surface + clearance + flesh_r[i] * lie
			pos[i] = Vector3(pos[i].x, pos[i].y, down)
			prev[i] = Vector3(prev[i].x, prev[i].y, down)
		# The droop readouts stay honest on a carcass: flat on the floor is
		# the whole of the sag the carry line implies.
		_neck.tip_sag = 0.0
		_tail.tip_sag = 0.0
		return

	# What the legs deliver, which is a measurement of the feet once there is a
	# gait to take it and the rest stance's own claim until then. Not `surface`
	# plus a stance: the carried heights are already quoted against whatever each
	# foot is standing on, so a body half on a ledge is held where its own legs
	# have it rather than being levelled onto the ground under its middle.
	#
	# ...taken through the heel, which is a rotation about the outermost foot on
	# the side the body is going rather than about its own spine: a tipping animal
	# turns over its feet, so the back rides *up* over the pivot as it starts to
	# go and comes down the far side of it. Level, both terms are the stance
	# exactly and not one number moves.
	var heel: float = cos(roll)
	var over: float = absf(sin(roll))
	var pelvis_z: float = clearance + hind_carry * heel + hind_half * over
	var withers_z: float = clearance + fore_carry * heel + fore_half * over
	var n_trunk: int = _trunk.nodes.size()
	for j in n_trunk:
		var z: float = lerpf(pelvis_z, withers_z, float(j) / float(n_trunk - 1))
		var i: int = _trunk.nodes[j]
		pos[i] = Vector3(pos[i].x, pos[i].y, z)
		prev[i] = Vector3(prev[i].x, prev[i].y, z)
	var tone: float = 1.0 - CARRIAGE
	_droop_chain(_neck, withers_z, surface, tone, head_reach_z)
	_droop_chain(_tail, pelvis_z, surface, tone)


## The droop walk, ported from Droop.update: one walk from the support to the
## free tip, no iteration, because a cantilever has no upstream. Each station
## can hold with the cube of its own width (the beam law) times the tone of
## the animal; what it is under is the weight still to come. The slope starts
## on the carry line and only ever falls away from it, and no station may
## push itself back up through the floor.
func _droop_chain(chain: Chain, start_z: float, floor_z: float, tone: float,
		tip_z: float = NAN) -> void:
	var count: int = chain.nodes.size()
	# Weight still to come at each station, tip-backward, the node's own
	# weight included — it hangs off the stick that leads into it.
	var beyond: PackedFloat32Array = PackedFloat32Array()
	beyond.resize(count)
	var running: float = 0.0
	for j in range(count - 1, -1, -1):
		running += mass[chain.nodes[j]]
		beyond[j] = running

	var carry: float = tan(chain.carry_rad)
	# A reach re-aims the carry line at where the tip is being taken — clamped
	# to a slope a neck can actually be held at, so an illegal ask degrades to
	# the nearest legal carry rather than folding the chain through itself.
	if not is_nan(tip_z):
		var length: float = 0.0
		for s in chain.sticks:
			length += stick_bone[s]
		carry = clampf((tip_z - start_z) / maxf(length, 0.001), -1.5, 1.5)
	var slope: float = carry
	var z: float = start_z
	var line: float = start_z
	for j in count:
		var seg: float = stick_bone[chain.sticks[j]]
		var i: int = chain.nodes[j]
		var w: float = maxf(2.0 * flesh_r[i], DROOP_MIN_WIDTH)
		var hold: float = w * w * w * tone
		slope -= DROOP_LIMBER * beyond[j] / maxf(hold, 0.0001) * (seg / body_length)
		z = maxf(z + slope * seg, floor_z)
		line += carry * seg
		pos[i] = Vector3(pos[i].x, pos[i].y, z)
		prev[i] = Vector3(prev[i].x, prev[i].y, z)
	chain.tip_sag = line - z


# ------------------------------------------------------------------ limbs ----

## Where a limb's socket is: the girdle station carried out to the shoulder or
## the hip, foreshortened across the plan by the body's heel and dropped — or
## lifted — by that same angle.
##
## The one statement of it. The placement below and the gait's own drift and
## tear-off measurements all read this, so they cannot come to disagree about
## where a leg hangs from, and the whole cascade a heel sets off runs through
## this one function: the low side's socket sinks toward the ground and its leg
## folds under it, the high side's lifts until the leg cannot reach its anchor
## any more, that foot is torn off its footing and steps, and the support the
## next tick measures is narrower on exactly the side the body is falling
## toward. Nothing had to be told about any of that.
func socket_of(limb: Chain) -> Vector3:
	var p: int = limb.parent_node
	var out: float = limb.side * stick_bone[limb.sticks[0]]
	var plan: Vector2 = _p2(p) + perp[p] * (out * cos(roll))
	return Vector3(plan.x, plan.y, pos[p].z - out * sin(roll))


## Places every limb: the socket rides its girdle, the foot reaches for the
## ground, and FABRIK folds the bones between the two in the limb's sagittal
## plane (x along the body axis from the socket, y absolute height). Bone
## lengths are exact in 3D by construction: every joint of one limb shares
## the same lateral offset, so sagittal distances are world distances.
## A walking limb is placed, not integrated — prev mirrors pos so a mode
## switch hands the ragdoll no phantom velocity.
func _place_limbs(surface: float) -> void:
	for limb in limbs:
		var p: int = limb.parent_node
		var seat: Vector3 = socket_of(limb)
		var socket_plan := Vector2(seat.x, seat.y)
		var socket_z: float = seat.z
		var target_plan: Vector2 = socket_plan + fwd[p] * limb.foot_lead
		var target_z: float = surface
		var axis: Vector2 = fwd[p]
		if limb.foot_driven:
			# The gait owns the foot and the corner this leg is holding up. The solve
			# plane is the vertical one containing the socket and the foot — which is
			# what makes a sprawled elbow fold across the floor and a columnar knee
			# fold through the air beneath the body without anything choosing between
			# them, because the plane tilts up as the limb does.
			socket_z = limb.socket_rise
			target_plan = Vector2(limb.foot_target.x, limb.foot_target.y)
			target_z = limb.foot_target.z
			var run: Vector2 = target_plan - socket_plan
			axis = run.normalized() if run.length_squared() > 0.000001 else limb.plane
		limb.plane = axis
		limb.sag[0] = Vector2(0.0, socket_z)
		var target := Vector2((target_plan - socket_plan).dot(axis), target_z)
		_repole(limb, signf(fwd[p].dot(axis)))
		limb.sag = _fabrik(limb.sag, limb.bones, limb.sag[0], target,
			FABRIK_ITERATIONS, FABRIK_TOLERANCE)
		for j in limb.nodes.size():
			var i: int = limb.nodes[j]
			var plan: Vector2 = socket_plan + axis * limb.sag[j].x
			pos[i] = Vector3(plan.x, plan.y, limb.sag[j].y)
			prev[i] = pos[i]


## Re-seeds a limb's bend direction if it has gone collinear — a leg straightened
## by a drop has forgotten which way its elbow points, and FABRIK keeps whatever
## side it starts on. `lead` is which way the body's own forward axis points in the
## solve plane, so an elbow folds backward along the animal however the foot has
## been placed.
func _repole(limb: Chain, lead: float) -> void:
	var root: Vector2 = limb.sag[0]
	var tip: Vector2 = limb.sag[3]
	var axis: Vector2 = tip - root
	if axis.length_squared() < 0.000001:
		return
	var n: Vector2 = Vector2(-axis.y, axis.x).normalized()
	var sense: float = lead if absf(lead) > 0.001 else 1.0
	for j in [1, 2]:
		var off: float = (limb.sag[j] - root).dot(n)
		if absf(off) < 0.25:
			limb.sag[j] += n * (limb.pole[j - 1] * sense * 1.5)


## One tick of every limb nothing is holding out — the ported Ragdoll step.
## The socket is the one part of a limb that is not limp: it goes exactly
## where the body puts it, and everything below hangs off it, keeps its bone
## lengths, folds no further than a limp joint folds, and is dragged wherever
## the body takes it. Solved flat on the plan: a dead limb is on the floor.
##
## What the heel adds is where "down" is. A creature on its right flank has its
## belly facing its own left, so its legs are out to the left — and they are
## there because the body took them there. A frame turning by `droll` carries
## everything hanging off it through that much of an arc, so the swing is a
## *displacement*, applied to position and Verlet history together: kinematic,
## exactly as the lateral wave is, and for the wave's reason. Shift `pos` alone
## and the integrator takes the carry for real motion and keeps it; make it an
## acceleration instead and the legs are still falling sideways long after the
## animal has finished rolling, which draws them rammed straight out. A body
## that has stopped going over has stopped moving its legs. Belly-down the term
## is exactly zero and this is the ported step unchanged.
func _tumble_limbs(delta: float, surface: float) -> void:
	var fold: float = deg_to_rad(FOLD_MAX_DEG)
	var floor_z: float = surface + fall.height
	# How far the ventral direction's own plan shadow moved this tick: a leg
	# hanging `along` px below its socket swings `along` times this across the
	# ground, which is the arc and nothing more.
	var sweep: float = sin(roll) - sin(_rolled)
	for limb in limbs:
		var p: int = limb.parent_node
		var socket: int = limb.nodes[0]
		var seat: Vector3 = socket_of(limb)
		pos[socket] = Vector3(seat.x, seat.y, floor_z)
		prev[socket] = pos[socket]
		var ventral: Vector2 = -perp[p] * sweep

		var along: float = 0.0
		for j in range(1, limb.nodes.size()):
			var i: int = limb.nodes[j]
			along += limb.bones[j - 1]
			var vel: Vector2 = (_p2(i) - Vector2(prev[i].x, prev[i].y)) * LIMB_DAMPING
			var carry: Vector2 = ventral * along
			prev[i] = Vector3(pos[i].x + carry.x, pos[i].y + carry.y, floor_z)
			_set_p2(i, _p2(i) + vel + carry)
			pos[i] = Vector3(pos[i].x, pos[i].y, floor_z)

		# Bones last — the fold limit is a projection that moves a joint, so
		# whichever constraint runs last is the one that actually holds, and
		# the length of a bone is not taste.
		for _it in LIMB_ITERATIONS:
			_set_p2(limb.nodes[2], _fold(
				_p2(limb.nodes[0]), _p2(limb.nodes[1]), _p2(limb.nodes[2]), fold))
			_set_p2(limb.nodes[3], _fold(
				_p2(limb.nodes[1]), _p2(limb.nodes[2]), _p2(limb.nodes[3]), fold))
			for j in range(1, limb.nodes.size()):
				_set_p2(limb.nodes[j], _project_to_circle(
					_p2(limb.nodes[j]), _p2(limb.nodes[j - 1]), limb.bones[j - 1]))


# ------------------------------------------------------------- transitions ----

## The body stops being held: the trunk falls from its stance, the limbs are
## adopted exactly where the pose left them (with no velocity, so they go
## limp rather than being kicked), and the same solver carries on with the
## constraints loosened.
func collapse() -> void:
	if collapsed:
		return
	collapsed = true
	release_head()
	head_reach_z = NAN
	var datum: float = maxf(
		(pos[_trunk.nodes[0]].z + pos[_trunk.nodes[_trunk.nodes.size() - 1]].z) * 0.5, 0.0)
	fall.start(datum)
	for limb in limbs:
		limb.foot_driven = false
		for i in limb.nodes:
			prev[i] = pos[i]


func revive() -> void:
	collapsed = false
	fall.rest_on(0.0)
	fore_carry = fore_stance
	hind_carry = hind_stance


## Puts the body datum in the air; alive it lands back on its feet, dead it
## lands as meat. The whole arc belongs to Gravity.Fall — one integrator.
func drop(height: float) -> void:
	fall.start(fall.height + maxf(height, 0.0))


## Throws the body upward at a speed. The take-off half of the same integrator: a
## leap is a drop that starts going the other way, and nothing about the arc after
## the feet leave the ground differs from a fall.
func launch(rate: float) -> void:
	fall.start(fall.height, maxf(rate, 0.0))


## Hands the head to whatever is driving the body: it is placed from here on, and
## the chain follows it. Nothing else may move a pinned node.
func take_head(plan: Vector2) -> void:
	driven = true
	var head: int = head_index()
	pinned[head] = 1
	pos[head] = Vector3(plan.x, plan.y, pos[head].z)
	prev[head] = pos[head]


## ...and gives it back, which is what a collapse does.
func release_head() -> void:
	driven = false
	pinned[head_index()] = 0


## Swings everything behind the head about a point, by a share of an angle.
##
## What the legs do to a body turning on the spot. A head-led chain that is only
## ever *towed* round drags itself sideways instead of turning — the followers have
## to be carried through some of the swing, and how much is the caller's business:
## none of it walking forward, where the head leading is the whole mechanism, and
## most of it at a standstill, where the legs are what walk the body around.
func rotate_followers(pivot: Vector2, angle: float) -> void:
	if absf(angle) < 0.000001:
		return
	var head: int = head_index()
	for k in axial.size():
		var i: int = axial[k]
		if i == head:
			continue
		var here: Vector2 = pivot + (_p2(i) - pivot).rotated(angle)
		var was: Vector2 = pivot + (Vector2(prev[i].x, prev[i].y) - pivot).rotated(angle)
		pos[i] = Vector3(here.x, here.y, pos[i].z)
		prev[i] = Vector3(was.x, was.y, prev[i].z)


## A point on the axial line `behind` px back from the head, measured along the
## chain rather than through it — a body bent into a turn has its hips somewhere
## off the straight line and the shortcut would report a shorter animal the harder
## it was turning.
func station_behind_head(behind: float) -> Vector2:
	var n: int = axial.size()
	var run: float = 0.0
	for k in range(n - 1, 0, -1):
		var a: Vector2 = _p2(axial[k])
		var b: Vector2 = _p2(axial[k - 1])
		var span: float = a.distance_to(b)
		if run + span >= behind:
			return a.lerp(b, clampf((behind - run) / maxf(span, 0.0001), 0.0, 1.0))
		run += span
	return _p2(axial[0])


## Folds and extends the back along its own length.
##
## The spine's whole share of a stride, and it needs no second term anywhere: a
## body shorter this tick than last has carried its own shoulders backward
## relative to its hips, the limb sockets ride on the chain, and the stride, the
## step timing and the landing prediction all follow from the gait measuring where
## the socket actually went. Applied to the trunk's plan rests only — the neck and
## the tail are carried, not gathered — and always against the built length, so
## nothing accumulates.
func bunch(share: float) -> void:
	var wanted: float = clampf(share, -0.5, 0.5)
	if is_equal_approx(wanted, bunched):
		return
	bunched = wanted
	for s in _trunk.sticks:
		stick_plan[s] = stick_plan_rest[s] * (1.0 - bunched)


## Translates the whole axial body — position and Verlet history together, the
## pinned head included — by a plan offset. The contact seam: a solid pressing
## the body out *moves* the body rather than re-solving it, so the shift is
## constraint-neutral and injects no velocity. The feet are deliberately not
## moved (a planted foot is a world-fixed anchor whatever happens to the body
## over it): the support drift that opens up is how the legs learn about the
## wall, and the limbs are re-placed from their sockets later the same tick.
func shift(offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	var off := Vector3(offset.x, offset.y, 0.0)
	for k in axial.size():
		var i: int = axial[k]
		pos[i] = pos[i] + off
		prev[i] = prev[i] + off


## Moves one node without giving it velocity — the positional tether every
## external pull goes through, from Spine.haul. Plan only; the Z channel owns
## every height.
func haul(i: int, offset: Vector2) -> void:
	if i < 0 or i >= pos.size() or offset == Vector2.ZERO:
		return
	pos[i] = pos[i] + Vector3(offset.x, offset.y, 0.0)
	prev[i] = prev[i] + Vector3(offset.x, offset.y, 0.0)


func haul_to(i: int, plan: Vector2) -> void:
	if i < 0 or i >= pos.size():
		return
	haul(i, plan - _p2(i))


# ---------------------------------------------------------------- readouts ----

func node_count() -> int:
	return pos.size()


func stick_count() -> int:
	return stick_a.size()


func head_index() -> int:
	return _neck.nodes[_neck.nodes.size() - 1]


func withers_index() -> int:
	return _trunk.nodes[_trunk.nodes.size() - 1]


func pelvis_index() -> int:
	return _trunk.nodes[0]


func centre() -> Vector2:
	var mid: Vector2 = (_p2(pelvis_index()) + _p2(withers_index())) * 0.5
	return mid


## Where a node is on the ground plane. The one reading everything outside this
## file takes of the chain: heights come off `pos[i].z`, and nothing may keep its
## own copy of either.
func plan(i: int) -> Vector2:
	return _p2(i)


## Worst axial stick error against the rest length the current mode holds —
## the invariant that makes a broken back a slack back, never a stretched one.
func worst_stick_error() -> float:
	var live: bool = not collapsed
	var worst: float = 0.0
	for k in axial_stick.size():
		var s: int = axial_stick[k]
		var rest: float = stick_plan[s] if live else stick_bone[s]
		worst = maxf(worst, absf(_p2(stick_b[s]).distance_to(_p2(stick_a[s])) - rest))
	return worst


## Worst plan bend past its graded limit over the axial vertices, radians.
func worst_bend_excess() -> float:
	var worst: float = 0.0
	for k in range(axial.size() - 2):
		var incoming: Vector2 = _p2(axial[k + 1]) - _p2(axial[k])
		var outgoing: Vector2 = _p2(axial[k + 2]) - _p2(axial[k + 1])
		if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
			continue
		var turn: float = absf(wrapf(outgoing.angle() - incoming.angle(), -PI, PI))
		worst = maxf(worst, turn - axial_bend[k])
	return worst


## Worst limb bone-length error. Alive the bones are exact in 3D (the limb is
## placed); dead they are exact on the plan (the limb lies flat).
func worst_bone_error() -> float:
	var worst: float = 0.0
	for limb in limbs:
		for j in range(1, limb.nodes.size()):
			var a: int = limb.nodes[j - 1]
			var b: int = limb.nodes[j]
			var length: float
			if collapsed:
				length = _p2(b).distance_to(_p2(a))
			else:
				length = pos[b].distance_to(pos[a])
			worst = maxf(worst, absf(length - limb.bones[j - 1]))
	return worst


## Worst limb fold past the limp limit, radians, on the plan — meaningful for
## a tumbled limb; a placed one is bounded by its own solve.
func worst_fold_excess() -> float:
	var fold: float = deg_to_rad(FOLD_MAX_DEG)
	var worst: float = 0.0
	for limb in limbs:
		for j in range(2, limb.nodes.size()):
			var incoming: Vector2 = _p2(limb.nodes[j - 1]) - _p2(limb.nodes[j - 2])
			var outgoing: Vector2 = _p2(limb.nodes[j]) - _p2(limb.nodes[j - 1])
			if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
				continue
			var turn: float = absf(wrapf(outgoing.angle() - incoming.angle(), -PI, PI))
			worst = maxf(worst, turn - fold)
	return worst


func chain(name: StringName) -> Chain:
	return chains.get(name)


func pick_node(world: Vector2, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius * radius
	for i in pos.size():
		var d: float = _p2(i).distance_squared_to(world)
		if d < best_d:
			best_d = d
			best = i
	return best


# ------------------------------------------------------- solver primitives ----
# Ported from Constraints.gd / Fabrik.gd so Phase 7 can delete v1 without
# reaching back into it. Same projections, same degenerate handling.

static func _project_to_circle(p: Vector2, center: Vector2, radius: float) -> Vector2:
	var d: Vector2 = p - center
	var l: float = d.length()
	if l < 0.00001:
		return center + Vector2.RIGHT * radius
	return center + d * (radius / l)


## The same projection taken only part of the way — the soft distance pass of the
## driven solve, from Constraints.solve_distance.
static func _draw_to_circle(p: Vector2, center: Vector2, radius: float,
		hold: float) -> Vector2:
	return p.lerp(_project_to_circle(p, center, radius), clampf(hold, 0.0, 1.0))


## Angle projection that rotates only the child — what a chain with a placed
## anchor wants (the tumbled limb's socket is placed by the body).
static func _fold(a: Vector2, b: Vector2, c: Vector2, max_bend: float) -> Vector2:
	var incoming: Vector2 = b - a
	var outgoing: Vector2 = c - b
	if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
		return c
	var delta: float = wrapf(outgoing.angle() - incoming.angle(), -PI, PI)
	if absf(delta) <= max_bend:
		return c
	var clamped: float = clampf(delta, -max_bend, max_bend)
	return b + outgoing.rotated(clamped - delta)


## FABRIK, ported verbatim: the same circle projection applied alternately
## from each end. The caller seeds the middle joints — the seed is the pole.
static func _fabrik(joints: PackedVector2Array, lengths: PackedFloat32Array,
		root: Vector2, target: Vector2, iterations: int = 6,
		tolerance: float = 0.05) -> PackedVector2Array:
	var out: PackedVector2Array = joints.duplicate()
	var n: int = out.size()
	if n < 2 or lengths.size() != n - 1:
		return out

	var total: float = 0.0
	for l in lengths:
		total += l

	# Unreachable: lay the chain out straight toward it — a clean "fully
	# extended" pose instead of an oscillating loop.
	if root.distance_to(target) >= total:
		var dir: Vector2 = target - root
		dir = dir.normalized() if dir.length_squared() > 0.000001 else Vector2.RIGHT
		out[0] = root
		for i in range(1, n):
			out[i] = out[i - 1] + dir * lengths[i - 1]
		return out

	for _it in range(maxi(iterations, 1)):
		out[n - 1] = target
		for i in range(n - 2, -1, -1):
			out[i] = _project_to_circle(out[i], out[i + 1], lengths[i])
		out[0] = root
		for i in range(1, n):
			out[i] = _project_to_circle(out[i], out[i - 1], lengths[i - 1])
		if out[n - 1].distance_to(target) < tolerance:
			break

	return out


# ------------------------------------------------------------------ helpers ----

func _p2(i: int) -> Vector2:
	return Vector2(pos[i].x, pos[i].y)


func _set_p2(i: int, p: Vector2) -> void:
	pos[i] = Vector3(p.x, p.y, pos[i].z)
