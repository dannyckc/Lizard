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
signal bite_started(center: Vector2, radius: float)
signal tissue_damaged(region_id: String, remaining: float)

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
var bite_cooldown_remaining: float = 0.0
var bite_feedback_remaining: float = 0.0
var bite_feedback_center: Vector2 = Vector2.ZERO
var bite_feedback_radius: float = 1.0
var bite_connected: bool = false
var _bite_requested: bool = false

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
	bite_feedback_remaining = 0.0
	bite_connected = false
	_bite_requested = false
	rebuild()


func _physics_process(delta: float) -> void:
	bite_cooldown_remaining = maxf(bite_cooldown_remaining - delta, 0.0)
	bite_feedback_remaining = maxf(bite_feedback_remaining - delta, 0.0)

	# Segment count is the only structural parameter; everything else is read
	# live each tick, so tuning sliders take effect immediately.
	if spine == null or spine.size() != params.segment_count:
		rebuild()

	_integrate_motion(delta)

	var seg_len: float = params.segment_length * size_scale
	spine.step(delta, head_pos, params, speed_norm, seg_len)
	body.build(spine, params, size_scale)
	gait.update(delta, body, move_dir, speed_norm, params, size_scale)

	if _bite_requested:
		_perform_bite()

	# Grow smoothly toward the size earned by eating, so the body has time to
	# settle into new segment lengths instead of snapping.
	var target_scale: float = clampf(1.0 + float(food_eaten) * params.growth_per_food, 1.0, params.max_scale)
	size_scale = lerpf(size_scale, target_scale, 1.0 - exp(-2.0 * delta))


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


func apply_bite_hit(hit: AnatomyState.Hit, damage: float, wound_radius: float) -> float:
	var applied: float = anatomy.apply_bite(hit, damage, wound_radius, size_scale)
	if applied > 0.0:
		tissue_damaged.emit(hit.region_id, anatomy.health_of(hit.region_id))
	return applied


## Called by the world after it has selected and damaged (or failed to find) a
## target. The view uses this to distinguish a landed rust-coloured bite from a
## quiet miss indicator.
func resolve_bite(connected: bool) -> void:
	bite_connected = connected


func _perform_bite() -> void:
	_bite_requested = false
	if body == null:
		return
	# The current body is head-driven, so the truthful jaw direction is the
	# solved head frame; allowing the click vector to bypass it would make the
	# creature bite sideways before its visible head has reached the cursor.
	var reach: float = params.bite_reach * size_scale
	bite_feedback_radius = params.bite_radius * size_scale
	bite_feedback_center = body.head.pos + body.head.fwd * (body.head_radius + reach * 0.5)
	bite_feedback_remaining = 0.14
	bite_connected = false
	bite_cooldown_remaining = params.bite_cooldown
	bite_started.emit(bite_feedback_center, bite_feedback_radius)
