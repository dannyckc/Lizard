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
class_name Spine
extends RefCounted

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


func size() -> int:
	return points.size()


## Advances the spine one tick. `head_pos` is where the head is being dragged to.
func step(delta: float, head_pos: Vector2, p: CreatureParams, speed_norm: float, seg_len: float) -> void:
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
		var target: Vector2 = perps[i] * (phase * p.body_wave * speed_norm * envelope)
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
	for it in range(passes):
		var stiffness: float = 1.0 if it == passes - 1 else p.spine_stiffness
		for i in range(1, n):
			points[i] = Constraints.solve_distance(points[i - 1], points[i], seg_len, stiffness)
			if i >= 2:
				points[i] = Constraints.solve_angle(points[i - 2], points[i - 1], points[i], max_bend)

	_compute_frames()


## Moves one body point without giving it velocity.
##
## `prev` is shifted by the same amount for exactly the reason step 2 above
## does it: Verlet reads velocity as `points - prev`, so an external correction
## applied to `points` alone is handed to the integrator as real motion, carried
## forward at `spine_damping` and re-injected next tick. A creature resting
## against another would push itself off it and oscillate. Point 0 is refused
## because it is placed, not simulated — the head is corrected at its source.
func displace(i: int, offset: Vector2) -> void:
	if i <= 0 or i >= points.size():
		return
	points[i] += offset
	prev[i] += offset


## Local forward/perpendicular basis at every spine point. The body shape and
## the limb anchors are built entirely out of these, which is what keeps the
## silhouette readable while the chain bends.
func _compute_frames() -> void:
	var n: int = points.size()
	for i in n:
		var f: Vector2
		if i == 0:
			f = points[0] - points[1]
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


## Total length of the chain, for camera framing and debug readouts.
func arc_length() -> float:
	var total: float = 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total
