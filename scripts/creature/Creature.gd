## Owns the creature's motion state and drives the four subsystems in order.
##
## Per physics tick:
##   1. integrate the head's position/heading from the movement command;
##   2. drag the spine after it (constraint solve);
##   3. rebuild the body shape from the solved spine;
##   4. run the gait, which reads the new body and solves the limb IK.
##
## The dependency chain is strictly one-way — input -> head -> spine -> body ->
## limbs — which is why the whole thing is stable without any global solver.
## All state is in world space and this node stays at the origin, so the view
## can draw the raw coordinates.
class_name Creature
extends Node2D

signal ate_food(total: int)
## Emitted at the apex of the lunge, not on the click — see _physics_process.
signal bite_started(center: Vector2, radius: float)
signal tissue_damaged(integrity: float)
## Chunks of skin and muscle a bite tore off, for the world to scatter.
signal tissue_shed(chunks: Array, origin: Vector2)

@export var params: CreatureParams
## Simulation-space spawn because this node intentionally remains at the world
## origin while its procedural points are stored directly in world space.
@export var spawn_position: Vector2 = Vector2.ZERO
@export var spawn_heading: float = 0.0

var spine: Spine
var body: BodyShape
var gait: Gait
var anatomy: AnatomyState = AnatomyState.new()

# --- motion state -----------------------------------------------------------
var head_pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var ang_vel: float = 0.0
var move_dir: Vector2 = Vector2.RIGHT
## Speed as a 0..1 fraction of top speed. Drives stride, step timing and sway.
var speed_norm: float = 0.0

var food_eaten: int = 0
## Uniform scale on the whole creature — body, limbs, stride, reach and bite all
## read off it. Growth has been taken out for now, so it is pinned at 1.0 and
## nothing writes to it; it is left in place as the single value a growth system
## will drive when one lands, rather than as a multiplier to be re-threaded
## through forty call sites later.
var size_scale: float = 1.0

# --- collision --------------------------------------------------------------
## Fraction of a contact each creature resolves on its own. Both parties run the
## same pass against each other, so a half each separates them exactly once —
## and no creature ever writes to another's state, which is what keeps this
## order-independent however many of them end up in one pile.
const CONTACT_SHARE: float = 0.5
## Ceiling on how far one tick may push a single body point. A deep overlap —
## two creatures spawned inside each other, or a segment count change that
## lengthens a body through its neighbour — then unwinds over several ticks
## instead of catapulting the chain apart in one. It has to stay comfortably
## above how far a creature travels in a tick (about 5 px at a sprint) or a
## body walks into another faster than the correction pushes it out.
const MAX_CONTACT_PUSH: float = 12.0

## Bounding circle around the whole body, refreshed with the pose. Only used to
## reject creature pairs before the per-point contact walk.
var bounds_center: Vector2 = Vector2.ZERO
var bounds_radius: float = 0.0

# --- bite state -------------------------------------------------------------
## The strike is an animation with a hit frame, not an instant event. A click
## starts a wind-up, the head is then thrown forward, and the bite resolves at
## full extension — so what gets bitten is whatever the jaws actually reached,
## and the lunge reads as the cause of the damage rather than as a flourish
## played after it.
const LUNGE_WINDUP: float = 0.07
const LUNGE_STRIKE: float = 0.08
const LUNGE_RECOVER: float = 0.18
const LUNGE_TOTAL: float = LUNGE_WINDUP + LUNGE_STRIKE + LUNGE_RECOVER
## How far the head rocks back during the wind-up, as a fraction of the throw.
const LUNGE_SETBACK: float = -0.22

var bite_cooldown_remaining: float = 0.0
var bite_connected: bool = false
## Seconds into the current strike, or -1 while not striking.
var bite_time: float = -1.0
## How far ahead of its resting position the lunge is currently holding the
## head, in world pixels. Applied to the spine, never to `head_pos`.
var lunge_offset: float = 0.0
var _bite_requested: bool = false
var _impact_done: bool = false

## Set by whoever is driving this creature, before the physics tick.
var command: MovementInput.Command = MovementInput.Command.new()


func _ready() -> void:
	if params == null:
		params = CreatureParams.new()
	head_pos = spawn_position
	heading = spawn_heading
	move_dir = Vector2.RIGHT.rotated(heading)
	add_to_group("creatures")
	rebuild()


## Rebuilds the structures that depend on segment count. Cheap enough to call
## from a slider callback.
func rebuild() -> void:
	spine = Spine.new()
	spine.rebuild(params.segment_count, params.segment_length * size_scale, head_pos, heading)
	body = BodyShape.new()
	gait = Gait.new()
	gait.setup()
	body.build(spine, params, size_scale)
	gait.update(0.0, body, move_dir, 0.0, params, size_scale)
	# Existing damage is kept — it lives in body space precisely so a structural
	# rebuild cannot wash it off — but its world geometry is now stale.
	anatomy.update(self)
	_update_bounds()


func reset(at: Vector2 = Vector2.ZERO, facing: float = 0.0) -> void:
	head_pos = at
	heading = facing
	speed = 0.0
	ang_vel = 0.0
	move_dir = Vector2.RIGHT.rotated(heading)
	food_eaten = 0
	command = MovementInput.Command.new()
	anatomy.reset()
	bite_cooldown_remaining = 0.0
	bite_connected = false
	bite_time = -1.0
	lunge_offset = 0.0
	_bite_requested = false
	_impact_done = false
	rebuild()


func _physics_process(delta: float) -> void:
	bite_cooldown_remaining = maxf(bite_cooldown_remaining - delta, 0.0)

	# Segment count is the only structural parameter; everything else is read
	# live each tick, so tuning sliders take effect immediately.
	if spine == null or spine.size() != params.segment_count:
		rebuild()

	if _bite_requested:
		_bite_requested = false
		bite_time = 0.0
		bite_connected = false
		_impact_done = false
		bite_cooldown_remaining = params.bite_cooldown
	_advance_lunge(delta)

	_integrate_motion(delta)
	# Between "where input put the head" and "where the body follows it to", so
	# the silhouette, the limbs and the tissue lattice are all built from the
	# corrected pose within this same tick rather than a tick behind it.
	_resolve_contacts()

	# The lunge is fed to the spine rather than to `head_pos`, which stays the
	# creature's honest position: the throw has to be something the body follows
	# through the constraint solve — that is what makes it whip — and it must
	# not accumulate into the motion integrator or a strike would teleport the
	# creature forward by its own reach.
	var seg_len: float = params.segment_length * size_scale
	spine.step(delta, head_pos + move_dir * lunge_offset, params, speed_norm, seg_len)
	body.build(spine, params, size_scale)
	gait.update(delta, body, move_dir, speed_norm, params, size_scale)
	anatomy.update(self)
	_update_bounds()

	# Resolve at full extension, once the pose above is the lunged one, so the
	# bite is tested against where the jaws have genuinely arrived. The clock is
	# clamped to the end of the animation rather than run past it, so this can
	# never be stepped over — one click is always exactly one hit frame, however
	# coarse the tick that carries it.
	if bite_time >= 0.0 and not _impact_done and bite_time >= LUNGE_WINDUP + LUNGE_STRIKE:
		_impact_done = true
		_strike()
	if bite_time >= LUNGE_TOTAL:
		bite_time = -1.0
		lunge_offset = 0.0


## Advances the strike clock and resolves it to a forward displacement.
##
## Three phases, shaped so the silhouette itself carries the timing: a soft
## rock backwards to load, a hard ease-out throw (all the distance covered in
## the first half of it, which is what makes it read as a snap rather than a
## lean), and a slow settle back. Nothing is fed back into the motion state, so
## a creature that never bites is bit-for-bit unaffected by any of this.
func _advance_lunge(delta: float) -> void:
	if bite_time < 0.0:
		lunge_offset = 0.0
		return
	# The clock never advances past the hit frame in a single step. A tick large
	# enough to span the whole animation would otherwise leave the head already
	# recovered on the frame the bite resolves, and it would strike from resting
	# reach — so "the bite is tested at full extension" would hold only at a
	# well-behaved tick rate. Stopping on the apex makes it unconditional; the
	# strike then releases the clamp and recovery runs on the following tick.
	var limit: float = LUNGE_TOTAL if _impact_done else LUNGE_WINDUP + LUNGE_STRIKE
	bite_time = minf(bite_time + delta, limit)

	var throw_distance: float = params.bite_reach * size_scale * 0.85
	var e: float
	if bite_time < LUNGE_WINDUP:
		e = LUNGE_SETBACK * smoothstep(0.0, 1.0, bite_time / LUNGE_WINDUP)
	elif bite_time < LUNGE_WINDUP + LUNGE_STRIKE:
		var x: float = (bite_time - LUNGE_WINDUP) / LUNGE_STRIKE
		e = lerpf(LUNGE_SETBACK, 1.0, 1.0 - (1.0 - x) * (1.0 - x))
	else:
		var x2: float = (bite_time - LUNGE_WINDUP - LUNGE_STRIKE) / LUNGE_RECOVER
		e = 1.0 - smoothstep(0.0, 1.0, x2)
	lunge_offset = e * throw_distance


## True while a strike is playing, at any phase.
func is_lunging() -> bool:
	return bite_time >= 0.0


func _integrate_motion(delta: float) -> void:
	var p: CreatureParams = params

	# Turn rate falls off with speed so the arc stays wider than the body. At a
	# standstill the full rate is available, which is what lets the creature
	# pivot on the spot (together with the pivot offset below).
	var turn_rate: float = deg_to_rad(p.turn_speed_deg) * (1.0 - p.turn_speed_falloff * speed_norm)
	# Angular velocity eases toward the commanded rate rather than snapping, so
	# the body has something to lag behind during a turn.
	var desired_ang_vel: float = command.turn * turn_rate
	ang_vel = lerpf(ang_vel, desired_ang_vel, 1.0 - exp(-p.turn_responsiveness * delta))

	# Turning swings the head around a pivot behind it instead of just spinning
	# it in place. Without this a stationary creature could rotate its heading
	# without the head ever moving, so the spine would never bend and the feet
	# would never trip their stride threshold — it would turn without walking.
	# The pivot shortens at speed so fast turns are wide arcs, not handbrakes.
	var pivot_dist: float = p.turn_pivot * size_scale * (1.0 - 0.6 * speed_norm)
	var pivot: Vector2 = head_pos - Vector2.RIGHT.rotated(heading) * pivot_dist
	heading = wrapf(heading + ang_vel * delta, -PI, PI)
	head_pos = pivot + Vector2.RIGHT.rotated(heading) * pivot_dist

	# Forward speed: accelerate toward the commanded speed, coast down faster
	# than we spin up so releasing the key feels responsive.
	var top_speed: float = p.move_speed * size_scale * (p.sprint_multiplier if command.sprint else 1.0)
	var desired_speed: float = command.throttle * top_speed
	var rate: float = p.acceleration * size_scale
	if absf(desired_speed) < absf(speed):
		rate *= 1.6
	speed = move_toward(speed, desired_speed, rate * delta)

	move_dir = Vector2.RIGHT.rotated(heading)
	head_pos += move_dir * (speed * delta)
	speed_norm = clampf(absf(speed) / maxf(p.move_speed * size_scale, 1.0), 0.0, 1.0)


# ------------------------------------------------------------- collision ----

## Pushes this creature out of any other creature it is standing inside.
##
## Each creature resolves its own half of every contact and never touches
## another's state, so the result does not depend on the order the group is
## ticked in — the same reason the rest of the chain is strictly one-way. The
## bodies tested against are the ones solved last tick; at 60 Hz that is a few
## pixels of staleness, and a positional correction is iterative anyway, so it
## costs nothing but buys back the whole ordering problem.
##
## Bodies collide, limbs do not. Legs here are kinematic — they neither carry
## weight nor receive it — so colliding them would only jam two creatures apart
## at arm's length while their bodies still read as clear of each other.
func _resolve_contacts() -> void:
	if spine == null or body == null or not is_inside_tree():
		return
	var last: int = mini(body.last_index, spine.size() - 1)
	# The single deepest contact anywhere on the body, kept unclamped so the
	# brake below can read how squarely it opposes travel.
	var deepest: Vector2 = Vector2.ZERO
	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.body == null or other.spine == null:
			continue
		# Both bounds are a tick old, so right at the boundary this can reject a
		# pair whose true overlap is a pixel or two. That contact is caught on
		# the next tick, which is the whole tolerance a positional correction
		# works to anyway.
		if bounds_center.distance_to(other.bounds_center) > bounds_radius + other.bounds_radius:
			continue
		for i in range(last + 1):
			# Both halves of a contact have to know about both sets of holes.
			# `push_out_of_body` narrows the body being walked into; this narrows
			# the body doing the walking, so a creature eaten open at the waist
			# can be closed over rather than held off at its old width.
			var solid: float = _solid_at(i, last)
			if solid <= 0.0:
				continue
			# Point 0 is the head, and the head is placed rather than simulated,
			# so its contact has to move `head_pos` — the spine's copy of it is
			# overwritten from there a few lines later.
			var at: Vector2 = head_pos if i == 0 else spine.points[i]
			var push: Vector2 = other.push_out_of_body(at, body.widths[i] * solid)
			if push == Vector2.ZERO:
				continue
			if push.length_squared() > deepest.length_squared():
				deepest = push
			push = push.limit_length(MAX_CONTACT_PUSH) * CONTACT_SHARE
			if i == 0:
				head_pos += push
			else:
				spine.displace(i, push)
	_brake_into(deepest)


## How much tissue is still standing around one spine point, as a fraction of
## the width the silhouette would have there. The probe is a circle about the
## axis, so it takes the wider of the two flanks — a body eaten open on one side
## is still as wide as the side that survived.
func _solid_at(i: int, last: int) -> float:
	var tissue: TissueGrid = anatomy.tissue
	if i == 0:
		return tissue.head_solid()
	var t: float = float(i) / float(maxi(last, 1))
	return maxf(tissue.body_solid(t, 1.0), tissue.body_solid(t, -1.0))


## Sheds the part of the forward speed that is driving into a contact.
##
## Position alone is not enough, and the difference is not subtle. Corrected
## only positionally, a creature walking into another keeps walking: it either
## grinds through, or — measured — shoves a stationary creature across the world
## ahead of it at its own full speed, with no resistance at all. Scaling `speed`
## by how squarely the contact opposes travel stops it dead head-on and leaves
## it entirely free to slide along a flank, which is the difference between
## another creature reading as solid and reading as sticky.
##
## Heading is deliberately untouched, so a creature pressed against another can
## always turn away and walk off. Nothing here has mass, so contact is symmetric
## and neither party can push the other.
func _brake_into(push: Vector2) -> void:
	if push == Vector2.ZERO or is_zero_approx(speed):
		return
	var into: float = -(move_dir * speed).normalized().dot(push.normalized())
	if into > 0.0:
		speed = move_toward(speed, 0.0, absf(speed) * into)


## The displacement that would just lift a circle of `radius` at `at` clear of
## this creature's body, or ZERO if it is already clear.
##
## Tested against the same chain of variable-radius capsules the view fills, so
## creatures collide with exactly the silhouette that is drawn. Only the deepest
## overlap is returned: consecutive capsules share their end caps, so summing
## them would push out by several times the actual penetration.
##
## Each capsule is narrowed to the tissue that is actually still there, per
## side, so a body eaten open is open: a flank chewed halfway in stops pushing
## at the new surface, and a station eaten clean through stops colliding at all
## and can be walked straight into. Without this the hole would be a hole you
## could see through and not one you could reach through, which is the same
## illusion as painting the ground colour over it.
func push_out_of_body(at: Vector2, radius: float) -> Vector2:
	if body == null or spine == null:
		return Vector2.ZERO
	var last: int = mini(body.last_index, spine.size() - 1)
	var tissue: TissueGrid = anatomy.tissue
	var deepest: float = 0.0
	var out: Vector2 = Vector2.ZERO
	for i in range(last):
		var a: Vector2 = spine.points[i]
		var b: Vector2 = spine.points[i + 1]
		var u: float = AnatomyState.segment_u(at, a, b)
		var axis: Vector2 = a.lerp(b, u)
		var delta: Vector2 = at - axis
		var distance: float = delta.length()
		var side: float = delta.dot(spine.perps[i])
		var solid: float = tissue.body_solid((float(i) + u) / float(maxi(last, 1)), side)
		if solid <= 0.0:
			continue
		var overlap: float = radius + lerpf(body.widths[i], body.widths[i + 1], u) * solid - distance
		if overlap <= deepest:
			continue
		deepest = overlap
		# Dead centre on the axis there is no direction to leave by, so fall back
		# to the flank normal — sideways is the shortest way out of a body that
		# is far longer than it is wide.
		out = (delta / distance if distance > 0.0001 else spine.perps[i]) * overlap
	return out


## Refreshes the broad-phase bounding circle from the pose just solved. Built
## from the body's own cross-sections rather than from arc length, so a coiled
## creature gets a tight bound instead of one sized for a straight one.
func _update_bounds() -> void:
	if spine == null or body == null:
		return
	var last: int = mini(body.last_index, spine.size() - 1)
	var lo: Vector2 = spine.points[0]
	var hi: Vector2 = lo
	for i in range(last + 1):
		var w: float = body.widths[i]
		var at: Vector2 = spine.points[i]
		lo = Vector2(minf(lo.x, at.x - w), minf(lo.y, at.y - w))
		hi = Vector2(maxf(hi.x, at.x + w), maxf(hi.y, at.y + w))
	bounds_center = (lo + hi) * 0.5
	bounds_radius = lo.distance_to(hi) * 0.5


## Head-first collision test used by the food field.
func mouth_radius() -> float:
	return (body.head_radius if body != null else 10.0) + 6.0


func body_length() -> float:
	return spine.arc_length() if spine != null else 100.0


func feed(amount: int = 1) -> void:
	food_eaten += amount
	ate_food.emit(food_eaten)


## Queues one bite for the next solved physics pose. Clicks during recovery are
## deliberately discarded rather than buffered, so one click always means at
## most one attack.
func request_bite(_aim_world: Vector2) -> bool:
	if bite_cooldown_remaining > 0.0 or _bite_requested:
		return false
	_bite_requested = true
	return true


func can_bite() -> bool:
	return bite_cooldown_remaining <= 0.0 and not _bite_requested


## Pure query used by the world combat resolver so only the closest creature is
## damaged when several procedural bodies overlap the same bite volume.
func query_bite(center: Vector2, radius: float) -> AnatomyState.Hit:
	return anatomy.hit_test(self, center, radius)


## Erodes this creature's tissue lattice wherever the bite circle covers it,
## and hands whatever came loose to the world.
func apply_bite(center: Vector2, radius: float, depth: float) -> float:
	var shed: Array = []
	var removed: float = anatomy.apply_bite(center, radius, depth, shed)
	if removed <= 0.0:
		return 0.0
	tissue_damaged.emit(anatomy.tissue.integrity())
	if not shed.is_empty():
		tissue_shed.emit(shed, center)
	return removed


## Called by the world after it has selected and damaged (or failed to find) a
## target, so the strike knows whether it connected.
func resolve_bite(connected: bool) -> void:
	bite_connected = connected


## The hit frame. Announces the jaw volume at full extension and lets the world
## resolve it against every creature in it.
func _strike() -> void:
	if body == null:
		return
	# The body is head-driven, so the truthful jaw direction is the solved head
	# frame; allowing the click vector to bypass it would make the creature bite
	# sideways before its visible head has reached the cursor.
	var radius: float = params.bite_radius * size_scale
	var center: Vector2 = body.head.pos + body.head.fwd * (body.head_radius + radius * 0.35)
	bite_started.emit(center, radius)
