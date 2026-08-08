## The limbs of a body with nothing driving them.
##
## Every limb pose in a live creature is the answer to a question about
## locomotion: `Gait` decides where a foot wants to be, when it is overdue, and
## where it should land, and `Fabrik` puts the bones there. A carcass asks none of
## those questions. Its limbs are two-bone chains hanging off the sockets, carried
## wherever the body is carried and settling under friction wherever that leaves
## them — no ideal position, no stride threshold, no step, no lift.
##
## Three things are deliberately kept from the live solve rather than replaced,
## because each of them is anatomy and not gait: the bones keep their exact
## lengths, the joint folds the way that joint folds, and the foot stays inside
## the fan the limb can physically reach. A dead leg is limp. It is not detached,
## it is not double-jointed, and it does not lie through its own ribcage.
##
## Gravity, in a view that has no vertical axis, is these two facts together: the
## limb has no lift, and it has no tone. `Limb.lift` is held at zero — a dead foot
## is on the ground and its shadow is tight under it — and nothing anywhere here
## holds a limb out, so what is drawn is only ever what the constraints and the
## friction left.
class_name Ragdoll
extends RefCounted

## Inertia a dead limb keeps between ticks. Far below `spine_damping`, because
## what it stands for is not softness but ground friction: a limb dragged out of
## place trails behind and then stops, rather than swinging.
const LIMB_DAMPING: float = 0.35
## Relaxation passes over one limb. Two bones and two limits settle in very few.
const LIMB_ITERATIONS: int = 4
## Widest fan a settled foot may sit in, measured from the limb's rest stance.
## Wider than the gait's `limb_swing_deg`, because sprawling is exactly what a
## dead limb does — that parameter is a constraint on walking. The hard
## anatomical limits inside `clamp_to_envelope` still bind first.
const SPRAWL_DEG: float = 88.0
## How far from straight out to the side a settled foot may come to rest.
const SPRAWL_BEARING_DEG: float = 26.0
## Range a dead limb reaches over, as a fraction of its length. A limp chain is a
## folded one; a leg lying at full stretch reads as one still being held out.
const SPRAWL_REACH_MIN: float = 0.52
const SPRAWL_REACH_MAX: float = 0.74
## Hardest a dead joint may fold. The limit is the joint itself rather than the
## muscle around it, so it is generous — a limp knee closes much further than a
## walking one ever does.
const FOLD_MAX_DEG: float = 128.0
## Passes over one limb's contacts, and the correction below which it is clear.
const CONTACT_ITERATIONS: int = 4
const CONTACT_SLOP: float = 0.35

## Previous positions of [elbow, foot] per limb key — the Verlet history the
## limbs are integrated from. Held here rather than on `Limb` because it is state
## only a dead limb has; a walking one is placed, not integrated.
var _prev: Dictionary = {}


## Places every limb where it would have come to rest, with no velocity.
##
## Called when the body is built rather than per tick, and that is the whole of
## why a body in the habitat is found already lying down instead of collapsing in
## front of whoever happens to be watching at the moment it spawns.
func settle(body: BodyShape, limbs: Array[Limb], p: CreatureParams, scale: float,
		rng: RandomNumberGenerator) -> void:
	_prev.clear()
	if body.anchors.is_empty():
		return
	var sprawl: float = deg_to_rad(SPRAWL_DEG)
	for limb in limbs:
		var a: Spine.Frame = body.anchors[limb.key]
		limb.set_lengths((p.arm_length if limb.pair == Limb.FRONT else p.leg_length) * scale)
		limb.set_rest_dir(a, p)

		# Straight out to the side, wandered fore or aft, at a slack reach. Then
		# through the same envelope projection the gait uses, so a sprawl can
		# never start outside what the limb could actually have reached.
		var phi: float = deg_to_rad(SPRAWL_BEARING_DEG) * rng.randf_range(-1.0, 1.0)
		var reach: float = limb.total_length * rng.randf_range(SPRAWL_REACH_MIN, SPRAWL_REACH_MAX)
		var out: Vector2 = a.perp * limb.side
		limb.joints[0] = a.pos
		limb.joints[2] = limb.clamp_to_envelope(
			a, a.pos + (out * cos(phi) + a.fwd * sin(phi)) * reach, p.limb_max_reach, sprawl)
		limb.seed_joint(a, limb.joints[2])
		limb.joints = Fabrik.solve(
			limb.joints, limb.lengths, a.pos, limb.joints[2], p.fabrik_iterations, 0.05)

		_prev[limb.key] = PackedVector2Array([limb.joints[1], limb.joints[2]])
		limb.initialised = true
		_publish(limb)


## One tick of four limp limbs. Runs where `Gait.update` runs in the live tick,
## for the same reason and against the same rebuilt body.
func step(delta: float, body: BodyShape, limbs: Array[Limb], p: CreatureParams,
		scale: float, collision_query: Callable = Callable()) -> void:
	if body.anchors.is_empty():
		return
	var fold: float = deg_to_rad(FOLD_MAX_DEG)
	var sprawl: float = deg_to_rad(SPRAWL_DEG)
	for limb in limbs:
		var a: Spine.Frame = body.anchors[limb.key]
		limb.set_lengths((p.arm_length if limb.pair == Limb.FRONT else p.leg_length) * scale)
		limb.set_rest_dir(a, p)
		limb.track_socket(a.pos, delta, a.fwd)
		if not _prev.has(limb.key):
			_prev[limb.key] = PackedVector2Array([limb.joints[1], limb.joints[2]])

		# The socket is the one part of a limb that is not limp: it is where the
		# limb is attached, so it goes exactly where the body puts it, and
		# everything below hangs off it. This is also the only thing that ever
		# moves a settled limb by itself — the body deforming under it.
		limb.joints[0] = a.pos

		var prev: PackedVector2Array = _prev[limb.key]
		var elbow: Vector2 = limb.joints[1] + (limb.joints[1] - prev[0]) * LIMB_DAMPING
		var foot: Vector2 = limb.joints[2] + (limb.joints[2] - prev[1]) * LIMB_DAMPING
		prev[0] = limb.joints[1]
		prev[1] = limb.joints[2]
		limb.joints[1] = elbow
		limb.joints[2] = foot

		for _iteration in LIMB_ITERATIONS:
			_hold_bones(limb)
			limb.joints[2] = Constraints.solve_angle(
				limb.joints[0], limb.joints[1], limb.joints[2], fold)
			limb.joints[2] = limb.clamp_to_envelope(
				a, limb.joints[2], p.limb_max_reach, sprawl)

		if collision_query.is_valid():
			_push_clear(limb, collision_query, scale)

		# Storing `prev` from *before* the constraints ran is what makes the flop
		# real: whatever the solve had to correct is handed back as velocity next
		# tick, and `LIMB_DAMPING` is what then bleeds it away instead of letting
		# the limb swing. Same bargain as the spine's Verlet step.
		_prev[limb.key] = prev
		_publish(limb)


## Carries the limbs along with a body that has been translated as one piece,
## without handing them the translation as velocity. Exactly the reasoning behind
## `Spine.translate`: a shove is a change of position, not a swing of the leg, and
## limbs left behind by one would be snapped back by the length constraints on the
## following tick.
func translate(limbs: Array[Limb], offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	for limb in limbs:
		limb.joints[1] += offset
		limb.joints[2] += offset
		if not _prev.has(limb.key):
			continue
		var prev: PackedVector2Array = _prev[limb.key]
		prev[0] += offset
		prev[1] += offset
		_prev[limb.key] = prev


## Applies a pull to the movable particles of one limb at the anatomical point
## the jaws actually hold. The socket's share is returned to the owner because
## it belongs to the spine, not to this solver. Moving the Verlet history with
## the particles makes this a positional tether correction rather than an
## artificial kick; motion comes from the body continuing to pull on it.
func haul(limbs: Array[Limb], key: String, segment: int, u: float,
		offset: Vector2) -> Vector2:
	var limb: Limb = _find_limb(limbs, key)
	if limb == null or offset == Vector2.ZERO:
		return Vector2.ZERO
	var socket_share := Vector2.ZERO
	var elbow_share := Vector2.ZERO
	var foot_share := Vector2.ZERO
	match segment:
		0:
			socket_share = offset * (1.0 - u)
			elbow_share = offset * u
		1:
			elbow_share = offset * (1.0 - u)
			foot_share = offset * u
		_:
			foot_share = offset

	limb.joints[1] += elbow_share
	limb.joints[2] += foot_share
	if not _prev.has(limb.key):
		_prev[limb.key] = PackedVector2Array([limb.joints[1], limb.joints[2]])
	else:
		var prev: PackedVector2Array = _prev[limb.key]
		prev[0] += elbow_share
		prev[1] += foot_share
		_prev[limb.key] = prev
	return socket_share


func _find_limb(limbs: Array[Limb], key: String) -> Limb:
	for limb in limbs:
		if limb.key == key:
			return limb
	return null


## Projects each bone back onto its exact length, outward from the socket. The
## bones of a dead animal are the same bones; nothing about being limp lets them
## stretch.
func _hold_bones(limb: Limb) -> void:
	limb.joints[1] = Constraints.project_to_circle(
		limb.joints[1], limb.joints[0], limb.lengths[0])
	limb.joints[2] = Constraints.project_to_circle(
		limb.joints[2], limb.joints[1], limb.lengths[1])


## Shoves a dead limb out of anything it is lying inside.
##
## The same query the gait uses, applied to the bones themselves rather than to a
## foot target. A walking limb is routed around an obstacle by asking for a
## different footfall and re-solving to it; a limp one has no footfall to ask for.
## It is simply pushed, and the length constraints put the bones back together
## around wherever that leaves it.
func _push_clear(limb: Limb, query: Callable, scale: float) -> void:
	var upper_radius: float = maxf(limb.total_length * 0.16, 2.5 * scale) * 0.5
	var lower_radius: float = upper_radius * 0.72
	var foot_radius: float = maxf(limb.total_length * 0.10, 3.0 * scale)
	var cap: float = maxf(limb.total_length * 0.22, 4.0 * scale)
	for _iteration in CONTACT_ITERATIONS:
		var upper: Vector2 = query.call(limb.key, 0, limb.joints[0], limb.joints[1], upper_radius)
		var lower: Vector2 = query.call(limb.key, 1, limb.joints[1], limb.joints[2], lower_radius)
		var foot: Vector2 = query.call(limb.key, 2, limb.joints[2], limb.joints[2], foot_radius)
		if upper.length_squared() + lower.length_squared() + foot.length_squared() \
				<= CONTACT_SLOP * CONTACT_SLOP:
			return
		# The socket is pinned to the body, so an upper-bone contact can only be
		# answered by the elbow. A lower-bone one acts on both ends of that bone.
		limb.joints[1] += (upper + lower * 0.5).limit_length(cap)
		limb.joints[2] += (foot + lower * 0.5).limit_length(cap)
		_hold_bones(limb)


## Writes the gait-facing state of a limb that is not walking.
##
## Everything downstream reads these — the tissue lattice poses the limb's cells
## from `joints`, the view puts a shadow under `ground` and sizes its gap from
## `lift`, the debug overlay draws `ideal` and `stride`. A dead limb reporting a
## stride it is overdue on, or a height it is not at, would be the drawing telling
## a story about a gait that is not running.
func _publish(limb: Limb) -> void:
	limb.stepping = false
	limb.step_t = 0.0
	limb.lift = 0.0
	limb.pace = 0.0
	limb.error = 0.0
	limb.ground = limb.joints[2]
	limb.visual = limb.joints[2]
	limb.planted = limb.joints[2]
	limb.ideal = limb.joints[2]
	limb.step_from = limb.joints[2]
	limb.step_to = limb.joints[2]
	limb.stride = maxf(limb.total_length * 0.5, 1.0)
