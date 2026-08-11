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
## world's one integrator; a drop, a collapse and (later) a leap all live here.
var fall: Gravity.Fall = Gravity.Fall.new()
var collapsed: bool = false

var spawn_at: Vector2 = Vector2.ZERO
var spawn_heading: float = 0.0

# Cached derivations of the spec, set at build.
var body_length: float = 0.0
var fore_stance: float = 0.0
var hind_stance: float = 0.0
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

	_build_axial()
	fore_stance = spec.stance_height(true)
	hind_stance = spec.stance_height(false)
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
	fall.rest_on(0.0)
	_compute_frames()
	_solve_heights(0.0)

	# Limbs: seed the sagittal pose bent the way that limb bends — elbows
	# back, knees forward — then let the placement solve stand them.
	for limb in limbs:
		var fore: bool = limb.parent_node != _trunk.nodes[0]
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

## One tick. `surface` is what is under the animal, asked every time rather
## than kept — the habitat has terrain in it (flat 0 until Phase 3 hooks it).
func step(delta: float, surface: float = 0.0) -> void:
	fall.advance(delta, 0.0)
	var live: bool = not collapsed
	_integrate_plan(live)
	_relax_plan(live)
	_rest_plan()
	_compute_frames()
	_solve_heights(surface)
	if live:
		_place_limbs(surface)
	else:
		_tumble_limbs(surface)


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
## what the legs deliver, and everything past a girdle is a cantilever — the
## carry line rises at the chain's carry angle and the droop walk sags below
## it by the beam law. Dead: nothing is held, and the whole line lies on the
## surface (plus whatever the fall still owes). Z is assigned, never
## integrated — the one integrator in the vertical is `fall`.
func _solve_heights(surface: float) -> void:
	var clearance: float = fall.height
	if collapsed:
		for k in axial.size():
			var i: int = axial[k]
			pos[i] = Vector3(pos[i].x, pos[i].y, surface + clearance)
			prev[i] = Vector3(prev[i].x, prev[i].y, surface + clearance)
		# The droop readouts stay honest on a carcass: flat on the floor is
		# the whole of the sag the carry line implies.
		_neck.tip_sag = 0.0
		_tail.tip_sag = 0.0
		return

	var pelvis_z: float = surface + clearance + hind_stance
	var withers_z: float = surface + clearance + fore_stance
	var n_trunk: int = _trunk.nodes.size()
	for j in n_trunk:
		var z: float = lerpf(pelvis_z, withers_z, float(j) / float(n_trunk - 1))
		var i: int = _trunk.nodes[j]
		pos[i] = Vector3(pos[i].x, pos[i].y, z)
		prev[i] = Vector3(prev[i].x, prev[i].y, z)
	var tone: float = 1.0 - CARRIAGE
	_droop_chain(_neck, withers_z, surface, tone)
	_droop_chain(_tail, pelvis_z, surface, tone)


## The droop walk, ported from Droop.update: one walk from the support to the
## free tip, no iteration, because a cantilever has no upstream. Each station
## can hold with the cube of its own width (the beam law) times the tone of
## the animal; what it is under is the weight still to come. The slope starts
## on the carry line and only ever falls away from it, and no station may
## push itself back up through the floor.
func _droop_chain(chain: Chain, start_z: float, floor_z: float, tone: float) -> void:
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
		var socket_plan: Vector2 = _p2(p) + perp[p] * (limb.side * stick_bone[limb.sticks[0]])
		var socket_z: float = pos[p].z
		limb.sag[0] = Vector2(0.0, socket_z)
		var target := Vector2(limb.foot_lead, surface)
		_repole(limb)
		limb.sag = _fabrik(limb.sag, limb.bones, limb.sag[0], target,
			FABRIK_ITERATIONS, FABRIK_TOLERANCE)
		for j in limb.nodes.size():
			var i: int = limb.nodes[j]
			var plan: Vector2 = socket_plan + fwd[p] * limb.sag[j].x
			pos[i] = Vector3(plan.x, plan.y, limb.sag[j].y)
			prev[i] = pos[i]


## Re-seeds a limb's bend direction if it has gone collinear — a leg
## straightened by a drop has forgotten which way its elbow points, and
## FABRIK keeps whatever side it starts on.
func _repole(limb: Chain) -> void:
	var root: Vector2 = limb.sag[0]
	var tip: Vector2 = limb.sag[3]
	var axis: Vector2 = tip - root
	if axis.length_squared() < 0.000001:
		return
	var n: Vector2 = Vector2(-axis.y, axis.x).normalized()
	for j in [1, 2]:
		var off: float = (limb.sag[j] - root).dot(n)
		if absf(off) < 0.25:
			limb.sag[j] += n * (limb.pole[j - 1] * 1.5)


## One tick of every limb nothing is holding out — the ported Ragdoll step.
## The socket is the one part of a limb that is not limp: it goes exactly
## where the body puts it, and everything below hangs off it, keeps its bone
## lengths, folds no further than a limp joint folds, and is dragged wherever
## the body takes it. Solved flat on the plan: a dead limb is on the floor.
func _tumble_limbs(surface: float) -> void:
	var fold: float = deg_to_rad(FOLD_MAX_DEG)
	var floor_z: float = surface + fall.height
	for limb in limbs:
		var p: int = limb.parent_node
		var socket: int = limb.nodes[0]
		var socket_plan: Vector2 = _p2(p) + perp[p] * (limb.side * stick_bone[limb.sticks[0]])
		pos[socket] = Vector3(socket_plan.x, socket_plan.y, floor_z)
		prev[socket] = pos[socket]

		for j in range(1, limb.nodes.size()):
			var i: int = limb.nodes[j]
			var vel: Vector2 = (_p2(i) - Vector2(prev[i].x, prev[i].y)) * LIMB_DAMPING
			prev[i] = Vector3(pos[i].x, pos[i].y, floor_z)
			_set_p2(i, _p2(i) + vel)
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
	var datum: float = maxf(
		(pos[_trunk.nodes[0]].z + pos[_trunk.nodes[_trunk.nodes.size() - 1]].z) * 0.5, 0.0)
	fall.start(datum)
	for limb in limbs:
		for i in limb.nodes:
			prev[i] = pos[i]


func revive() -> void:
	collapsed = false
	fall.rest_on(0.0)


## Puts the body datum in the air; alive it lands back on its feet, dead it
## lands as meat. The whole arc belongs to Gravity.Fall — one integrator.
func drop(height: float) -> void:
	fall.start(fall.height + maxf(height, 0.0))


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
