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

@export var params: CreatureParams

var spine: Spine
var body: BodyShape
var gait: Gait

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

## Set by whoever is driving this creature, before the physics tick.
var command: MovementInput.Command = MovementInput.Command.new()


func _ready() -> void:
	if params == null:
		params = CreatureParams.new()
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


func reset(at: Vector2 = Vector2.ZERO) -> void:
	head_pos = at
	heading = 0.0
	speed = 0.0
	ang_vel = 0.0
	food_eaten = 0
	size_scale = 1.0
	rebuild()


func _physics_process(delta: float) -> void:
	# Segment count is the only structural parameter; everything else is read
	# live each tick, so tuning sliders take effect immediately.
	if spine == null or spine.size() != params.segment_count:
		rebuild()

	_integrate_motion(delta)

	var seg_len: float = params.segment_length * size_scale
	spine.step(delta, head_pos, params, speed_norm, seg_len)
	body.build(spine, params, size_scale)
	gait.update(delta, body, move_dir, speed_norm, params, size_scale)

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
