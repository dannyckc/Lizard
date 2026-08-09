## The creature's spine: a chain of particles solved with positional constraints.
##
## Simulation order per physics tick, and why:
##   1. Inertia      — Verlet integration gives every body point momentum, which
##                     is what makes the body trail and whip instead of rigidly
##                     tracking the head.
##   2. Undulation   — a travelling lateral wave is *added as a force*, before
##                     the solver, so the constraints absorb it into a smooth
##                     serpentine curve rather than tearing the body apart.
##   3. Pin the head — point 0 is authoritative and driven by player input.
##   4. Relaxation   — distance + angle constraints, front to back, repeated.
##
## Constraints run last because they are the invariants: whatever the forces
## did, the body must still have the right segment lengths and legal bends by
## the time anything else looks at it.
##
## A body that nobody is driving has no head to pin, so `step_free` below solves
## the same chain with no authoritative point at all. See its comment for why
## that cannot simply be `step` with the pin removed.
class_name Spine
extends RefCounted

## How much of the anatomical bend limit a slumped layout may use up at one
## joint. Kept short of the whole so the pose the carcass starts in is already
## legal and the first constraint pass has nothing to unpick.
const SLUMP_BEND_FRACTION: float = 0.55
## Per-joint wander in a slumped layout, as a fraction of that same budget. The
## slow arc alone reads as a body bent deliberately; this is what makes it read
## as flesh that is not uniform.
const SLUMP_WANDER: float = 0.35
## Shortest the neck may be drawn during the wind-up of a strike, as a fraction
## of its rest length. A species with a long reach and a short spine could
## otherwise rock its head back through its own shoulders.
const MIN_NECK: float = 0.4
## Below this much motion in one tick a point is asleep and gives up its implied
## velocity — see step()'s rest pass. 0.005 px at 60 Hz is 0.3 px/s, far under
## perception; a body actually travelling moves hundreds of times this per tick.
const REST_EPSILON: float = 0.005
## What a joint with nothing left holding it corrects at during the soft passes.
## Well under any tuneable stiffness, so a broken station reads as the body going
## slack there rather than as a slightly looser body everywhere.
const SLACK_STIFFNESS: float = 0.10
## How far past the anatomical bend limit a joint whose vertebra has been ground
## through will fold. Over one, because that limit is the vertebra: with the bone
## gone what is left is soft tissue, and soft tissue folds much further. Short of
## doubling, so a broken back still reads as a back and not as a rope.
const BROKEN_BEND: float = 1.85

## Position/orientation sampled at a fractional point along the chain.
class Frame extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var fwd: Vector2 = Vector2.RIGHT   ## unit vector pointing toward the head
	var perp: Vector2 = Vector2.UP     ## fwd rotated +90 degrees

var points: PackedVector2Array = PackedVector2Array()
var prev: PackedVector2Array = PackedVector2Array()
var forwards: PackedVector2Array = PackedVector2Array()
var perps: PackedVector2Array = PackedVector2Array()
## Lateral displacement the undulation currently owns, per point. Tracked so the
## wave can be applied as a bounded offset instead of an accumulating force.
var wave_offsets: PackedVector2Array = PackedVector2Array()

var wave_clock: float = 0.0


## Lays the chain out straight, trailing backwards from `origin`.
func rebuild(count: int, seg_len: float, origin: Vector2, heading: float) -> void:
	count = maxi(count, 3)
	points.resize(count)
	prev.resize(count)
	forwards.resize(count)
	perps.resize(count)
	wave_offsets.resize(count)
	var back: Vector2 = Vector2.RIGHT.rotated(heading + PI)
	for i in count:
		var p: Vector2 = origin + back * (float(i) * seg_len)
		points[i] = p
		prev[i] = p
		wave_offsets[i] = Vector2.ZERO
	_compute_frames()


## Lays the chain out as a body that has come to rest rather than one standing to
## attention.
##
## `rebuild` produces a dead-straight chain, which is the right start for a
## creature about to be dragged around by its head and exactly the wrong one for
## a carcass. Nothing downstream ever bends a spine with no head driving it: the
## constraints are satisfied by a straight chain, so a straight one stays straight
## forever and reads as a plank. The curve has to be there from the start.
##
## It is drawn once, from a seeded generator, and `step_free` then simply holds
## it — a dead thing has no posture system, it has the shape it came to rest in.
## Two components, because either alone is unconvincing: one slow arc over the
## whole length, which is the body having folded as it went down, and a small
## per-joint wander on top of it.
func rebuild_slumped(count: int, seg_len: float, origin: Vector2, heading: float,
		max_bend: float, rng: RandomNumberGenerator) -> void:
	rebuild(count, seg_len, origin, heading)
	var n: int = points.size()
	var limit: float = max_bend * SLUMP_BEND_FRACTION
	var arc: float = rng.randf_range(-1.0, 1.0)
	var direction: Vector2 = Vector2.RIGHT.rotated(heading + PI)
	var at: Vector2 = origin
	for i in range(1, n):
		# The arc is weighted through the trunk and eases off toward both ends, so
		# the body folds where a body folds rather than coiling evenly end to end.
		var t: float = float(i) / float(n - 1)
		var turn: float = limit * (arc * sin(t * PI) + rng.randf_range(-SLUMP_WANDER, SLUMP_WANDER))
		direction = direction.rotated(clampf(turn, -limit, limit))
		at += direction * seg_len
		points[i] = at
		prev[i] = at
	_compute_frames()


func size() -> int:
	return points.size()


## Advances the spine one tick. `head_pos` is where the head is being dragged to.
##
## `tone` is the anatomy speaking, one entry per point, 1.0 sound and 0.0 broken.
## It is the whole of how a damaged skeleton reaches the rig: a joint whose
## vertebra has been ground through stops being held to the bend limit and stops
## being stiffened toward it, so the body folds *there*. Left empty — which is the
## case for any creature nobody has bitten — every line below reads exactly the
## parameters it always did.
## `wave_gain` is how much of the authored undulation this animal's stance
## actually uses. A sprawled body lengthens its stride by throwing the spine side
## to side and keeps all of it; an upright one has taken that job back into the
## legs and keeps almost none. Left at one, the wave is exactly what `body_wave`
## says it is, which is what it has always been.
func step(delta: float, head_pos: Vector2, p: CreatureParams, speed_norm: float,
		seg_len: float, tone: PackedFloat32Array = PackedFloat32Array(),
		wave_gain: float = 1.0) -> void:
	var n: int = points.size()
	if n < 3:
		return

	# 1. Verlet inertia. Storing prev *before* adding the velocity means next
	#    tick's implied velocity includes whatever the constraints did, so the
	#    solver's corrections feed back as real motion (that's the "soft" feel).
	for i in range(1, n):
		var vel: Vector2 = (points[i] - prev[i]) * p.spine_damping
		prev[i] = points[i]
		points[i] = points[i] + vel

	# 2. Travelling lateral wave. Phase advances with speed so undulation is
	#    locked to how fast the creature is actually going, and dies out at rest.
	#
	#    The wave is *kinematic*: it displaces the body, it does not push it. We
	#    remember how far it has already moved each point and apply only the
	#    difference, so `body_wave` means exactly what it says — peak sway in
	#    pixels — instead of accumulating.
	#
	#    Applying that difference to `prev` as well is the other half of the same
	#    idea, and it is not optional. Verlet infers velocity from `points -
	#    prev`, so shifting only `points` hands the integrator the wave's per-tick
	#    displacement as though it were real motion; it then carries it forward at
	#    `spine_damping` and re-injects it next tick. The chain resonates, and the
	#    energy pools at the free end where nothing but the tip's own parent
	#    restrains it — the tail whips at tens of times the intended amplitude
	#    even though the envelope holds the wave itself to zero there. That whip
	#    travels up into the hips, so the rear limb sockets tear around far faster
	#    than the creature is actually moving and the hind feet can never plant.
	#    Shifting both leaves the implied velocity untouched: the wave becomes
	#    pure displacement, and only the constraint solver feeds the integrator.
	wave_clock += delta * p.wave_speed * (0.35 + 0.65 * speed_norm)
	for i in range(1, n):
		var t: float = float(i) / float(n - 1)
		var envelope: float = sin(t * PI)  # no sway at the neck or the very tip
		var phase: float = sin(wave_clock * TAU - t * p.wave_frequency * TAU)
		var target: Vector2 = perps[i] * (phase * p.body_wave * wave_gain * speed_norm * envelope)
		var shift: Vector2 = target - wave_offsets[i]
		points[i] += shift
		prev[i] += shift
		wave_offsets[i] = target

	# 3. The head is not simulated — it is placed. Everything else follows it.
	points[0] = head_pos
	prev[0] = head_pos

	# 4. Relaxation. Each pass walks strictly front-to-back and only ever moves
	#    the child, so the head stays put. Distance is fixed first, then the
	#    angle limit rotates the child *about its parent*, which preserves the
	#    distance we just fixed — so one pass settles both for a given joint.
	#
	#    The soft passes use `spine_stiffness`, removing only part of the error
	#    so the chain reaches its final shape gradually and reads as flexible
	#    rather than jointed. The LAST pass is always full strength. This is not
	#    optional: partial correction on a long chain is only marginally stable
	#    (each joint re-injects roughly as much error into its child as it
	#    removes), so a soft-only solve lets a 20+ segment spine visibly stretch.
	#    Because a full-strength pass projects every point exactly onto its
	#    parent's circle in one sweep, finishing with one guarantees segment
	#    lengths are exact no matter how low stiffness is set.
	var max_bend: float = deg_to_rad(p.max_bend_deg)
	var passes: int = maxi(p.constraint_iterations, 1)
	var damaged: bool = tone.size() == n
	for it in range(passes):
		var stiffness: float = 1.0 if it == passes - 1 else p.spine_stiffness
		for i in range(1, n):
			# The last pass stays full strength whatever the anatomy says. That is
			# not tone, it is the invariant that makes segment lengths exact — a
			# broken back is a slack back, never a stretched one.
			var hold: float = stiffness
			var bend: float = max_bend
			if damaged:
				if it < passes - 1:
					hold = lerpf(SLACK_STIFFNESS, stiffness, tone[i])
				bend = max_bend * lerpf(BROKEN_BEND, 1.0, tone[i])
			points[i] = Constraints.solve_distance(points[i - 1], points[i], seg_len, hold)
			if i >= 2:
				points[i] = Constraints.solve_angle(points[i - 2], points[i - 1], points[i], bend)

	# 5. Rest. Step 1 turns every correction the solver just made into next
	#    tick's velocity — that feedback is the "soft" feel — but it also means
	#    the chain has no fixed point to settle into: joints parked exactly on
	#    the bend limit trade a sub-micron correction back and forth forever,
	#    and the residue is directional, so an idle body ratchets its rear end
	#    across the world at a fraction of a pixel per second. A point whose
	#    whole tick of motion is below perception gives that velocity up here
	#    and is genuinely at rest; anything actually moving is orders of
	#    magnitude above the threshold and never notices.
	for i in range(1, n):
		if points[i].distance_squared_to(prev[i]) <= REST_EPSILON * REST_EPSILON:
			prev[i] = points[i]

	_compute_frames()


## Advances the spine of a body with nothing driving it.
##
## This is not `step` with the pin taken out, and the difference is the whole
## reason it is a separate solve. `step` is built for a chain whose head is placed
## by input: point 0 is authoritative, every pass walks strictly front to back,
## and only ever the *child* of a joint is moved — so corrections flow away from
## the head and the head stays exactly where input put it. None of that applies
## here. There is no authoritative point on a carcass, and a solve that kept one
## would quietly make it the anchor the rest of the body hangs off: pulled by the
## tail, such a body swings about its own snout instead of following. So both
## halves of every distance constraint move, and the passes alternate direction so
## neither end of the chain accumulates the residue of the other.
##
## What is gone is what a live creature does and a dead one does not: the
## undulation, and the head pose. What is left is inertia, ground friction as
## heavy `damping`, and the same two anatomical invariants — segment length and
## bend limit — which hold whether the animal is alive or not.
func step_free(p: CreatureParams, seg_len: float, damping: float) -> void:
	var n: int = points.size()
	if n < 3:
		return

	for i in n:
		var vel: Vector2 = (points[i] - prev[i]) * damping
		prev[i] = points[i]
		points[i] = points[i] + vel

	var max_bend: float = deg_to_rad(p.max_bend_deg)
	var passes: int = maxi(p.constraint_iterations, 1)
	for it in range(passes):
		if it % 2 == 0:
			for i in range(1, n):
				_solve_distance_symmetric(i - 1, i, seg_len)
				if i >= 2:
					_solve_angle_symmetric(i - 2, i - 1, i, max_bend)
		else:
			for i in range(n - 1, 0, -1):
				_solve_distance_symmetric(i - 1, i, seg_len)
				if i <= n - 3:
					_solve_angle_symmetric(i, i + 1, i + 2, max_bend)

	_compute_frames()


## Distance constraint that moves both ends by half the error each.
##
## `Constraints.solve_distance` treats its anchor as immovable, which is exactly
## what a head-driven chain wants and exactly what a free one must not have — see
## `step_free`. Full strength rather than `spine_stiffness`, because the give that
## parameter buys is muscle tone holding a body together against its own motion,
## and a carcass has neither the tone nor the motion.
func _solve_distance_symmetric(a: int, b: int, rest: float) -> void:
	var delta: Vector2 = points[b] - points[a]
	var distance: float = delta.length()
	if distance < 0.00001:
		delta = Vector2.RIGHT
		distance = 1.0
	var correction: Vector2 = delta * ((distance - rest) / distance * 0.5)
	points[a] += correction
	points[b] -= correction


## Bend projection for a chain with no pinned end. The live solver rotates only
## the child because its correction must flow away from the authoritative head.
## Doing that from alternating ends of a free chain gives the two sweeps opposite
## authorities: after a local shove they can chase the same bend error around the
## body forever, producing a constant rigid rotation even with zero stored
## velocity. Here both outer particles share the angular correction and the
## triplet is translated back onto its original centroid. The joint reaches the
## same anatomical limit without choosing an end or injecting net translation.
func _solve_angle_symmetric(a: int, b: int, c: int, max_bend: float) -> void:
	var incoming: Vector2 = points[b] - points[a]
	var outgoing: Vector2 = points[c] - points[b]
	if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
		return
	var delta: float = wrapf(outgoing.angle() - incoming.angle(), -PI, PI)
	if absf(delta) <= max_bend:
		return
	var correction: float = clampf(delta, -max_bend, max_bend) - delta
	var centroid: Vector2 = (points[a] + points[b] + points[c]) / 3.0
	points[a] = points[b] + (points[a] - points[b]).rotated(-correction * 0.5)
	points[c] = points[b] + (points[c] - points[b]).rotated(correction * 0.5)
	var shift: Vector2 = centroid - (points[a] + points[b] + points[c]) / 3.0
	points[a] += shift
	points[b] += shift
	points[c] += shift


## Moves one body point without giving it velocity.
##
## `prev` is shifted by the same amount for exactly the reason step 2 above
## does it: Verlet reads velocity as `points - prev`, so an external correction
## applied to `points` alone is handed to the integrator as real motion, carried
## forward at `spine_damping` and re-injected next tick. A creature resting
## against another would push itself off it and oscillate. Point 0 is refused
## because it is placed, not simulated — the head is corrected at its source.
func displace(i: int, offset: Vector2) -> void:
	if i <= 0:
		return
	haul(i, offset)


## The same move, with the head allowed.
##
## `displace` refuses point 0 because on a driven creature the head is placed
## rather than simulated, and correcting it anywhere but at its source would be
## undone by the pin on the very next tick. A carcass has no such source — every
## point of it is simulated — so a pull on one may land anywhere along the chain,
## snout included.
func haul(i: int, offset: Vector2) -> void:
	if i < 0 or i >= points.size():
		return
	points[i] += offset
	prev[i] += offset


## Translates the complete chain without adding Verlet velocity.
##
## Contact resolution uses this instead of pushing individual particles. A
## collision is an external change to the creature's world position, not a
## force that should kink its spine; moving `points` and `prev` together keeps
## both the solved shape and its existing momentum intact.
func translate(offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	for i in points.size():
		points[i] += offset
		prev[i] += offset


## Carries the simulated body with a head that is walking backward.
##
## Forward locomotion can drag this chain from point 0 because the head is in
## front of everything it is pulling. In reverse the same operation drives the
## head into point 1 and makes the constraint solver turn the torso inside-out
## before the tail starts moving. Carrying only the followers by the reverse
## displacement keeps their existing shape and Verlet velocity while point 0
## remains owned by the normal head pin in `step`.
func translate_followers(offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	for i in range(1, points.size()):
		points[i] += offset
		prev[i] += offset


## Swings the simulated body about a point, without giving it velocity.
##
## The rotational half of `translate_followers`, and it is here for the same
## reason that one is. A chain dragged from its head can only ever be *towed*
## into a turn, which is right while the head is leading: the lag is the body
## following. It is wrong in the two cases where the head is not what is moving
## the creature. Backing up, the head is the trailing end — swung on its own it
## winds the front of the body around the pivot while the tail, which is the end
## actually going somewhere, stays put, and the chain coils into itself. Turning
## on the spot there is no travel to follow at all: the feet are planted and the
## legs are walking the body around, so a body that could only be towed would
## drag itself sideways across the ground instead of turning.
##
## `prev` is rotated about the same point so the implied velocity turns with the
## body rather than being left pointing where the body used to be going.
func rotate_followers(pivot: Vector2, angle: float) -> void:
	if is_zero_approx(angle):
		return
	for i in range(1, points.size()):
		points[i] = pivot + (points[i] - pivot).rotated(angle)
		prev[i] = pivot + (prev[i] - pivot).rotated(angle)


## Articulates only the head around the solved neck. Locomotion pins and solves
## the complete chain first; applying look afterwards means cursor aim cannot
## tow the torso, alter the authoritative movement heading, or leak momentum
## into the next tick.
##
## `reach` is how far past its rest length the neck is currently thrown — a
## strike, and nothing else writes to it. It lives here for the same reason look
## does: a lunge is the head leaving the body behind, so it has to be applied
## where the body can no longer be dragged by it. The neck may extend freely and
## is only stopped from being compressed into the chest by the wind-up, which is
## the one direction the reach runs negative in.
func pose_head(forward: Vector2, seg_len: float, reach: float = 0.0) -> void:
	if points.size() < 2:
		return
	var direction: Vector2 = forward.normalized() \
		if forward.length_squared() > 0.000001 else forwards[0]
	points[0] = points[1] + direction * maxf(seg_len + reach, seg_len * MIN_NECK)
	prev[0] = points[0]
	_compute_frames()


## Local forward/perpendicular basis at every spine point. The body shape and
## the limb anchors are built entirely out of these, which is what keeps the
## silhouette readable while the chain bends.
func _compute_frames() -> void:
	var n: int = points.size()
	for i in n:
		var f: Vector2
		if i == 0:
			f = points[0] - points[1]
		elif i == 1 and n > 2:
			# Point 0 is an independently articulated head. The neck/torso frame
			# must follow its own axis so looking cannot rotate downstream frames.
			f = points[1] - points[2]
		else:
			f = points[i - 1] - points[i]
		if f.length_squared() < 0.000001:
			f = forwards[i] if forwards[i].length_squared() > 0.5 else Vector2.RIGHT
		else:
			f = f.normalized()
		forwards[i] = f
		perps[i] = Vector2(-f.y, f.x)


## Interpolated frame at `t` in 0..1 along the chain (0 = head, 1 = tail tip).
func sample(t: float) -> Frame:
	var n: int = points.size()
	var frame: Frame = Frame.new()
	if n < 2:
		return frame
	var s: float = clampf(t, 0.0, 1.0) * float(n - 1)
	var i: int = clampi(int(floor(s)), 0, n - 2)
	var f: float = s - float(i)
	frame.pos = points[i].lerp(points[i + 1], f)
	var fwd: Vector2 = forwards[i].lerp(forwards[i + 1], f)
	frame.fwd = fwd.normalized() if fwd.length_squared() > 0.000001 else forwards[i]
	frame.perp = Vector2(-frame.fwd.y, frame.fwd.x)
	return frame


## The point on the chain `distance` pixels back from the head, measured along
## the body rather than through it.
##
## Walked segment by segment instead of divided out of a rest length, because the
## two disagree exactly when it matters: the caller wants a station on the flesh —
## the shoulders, the hips — and on a body curled into a turn the straight-line
## distance to those is well short of the arc. Past the tail it clamps to the tip.
func station_behind_head(distance: float) -> Vector2:
	var n: int = points.size()
	if n < 2 or distance <= 0.0:
		return points[0] if n > 0 else Vector2.ZERO
	var travelled: float = 0.0
	for i in range(1, n):
		var span: float = points[i - 1].distance_to(points[i])
		if travelled + span >= distance:
			var f: float = (distance - travelled) / maxf(span, 0.00001)
			return points[i - 1].lerp(points[i], f)
		travelled += span
	return points[n - 1]


## Total length of the chain, for camera framing and debug readouts.
func arc_length() -> float:
	var total: float = 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total
