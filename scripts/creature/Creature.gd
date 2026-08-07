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

# --- growth (the evolution hook) --------------------------------------------
var food_eaten: int = 0
var size_scale: float = 1.0

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


func reset(at: Vector2 = Vector2.ZERO, facing: float = 0.0) -> void:
	head_pos = at
	heading = facing
	speed = 0.0
	ang_vel = 0.0
	move_dir = Vector2.RIGHT.rotated(heading)
	food_eaten = 0
	size_scale = 1.0
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

	# Grow smoothly toward the size earned by eating, so the body has time to
	# settle into new segment lengths instead of snapping.
	var target_scale: float = clampf(1.0 + float(food_eaten) * params.growth_per_food, 1.0, params.max_scale)
	size_scale = lerpf(size_scale, target_scale, 1.0 - exp(-2.0 * delta))


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


## How wide the jaws are gaping, 0..1. They open through the wind-up, hold
## through the throw, and snap shut on the hit frame — so the animation states
## exactly when the damage happened.
func jaw_open() -> float:
	if bite_time < 0.0 or _impact_done:
		return 0.0
	if bite_time < LUNGE_WINDUP:
		return smoothstep(0.0, 1.0, bite_time / LUNGE_WINDUP)
	return 1.0


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
