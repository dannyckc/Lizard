## The v2 creature as it stands in the lab: one armature, one census, one weight —
## and, from Phase 3, one gait carrying it about.
##
## Deliberately thin. The corpus owns the anatomy, the armature owns the physics,
## poise carries the one into the other (baked node masses in, posed centre of mass
## out), the locomotor says what the body can do about moving itself and the tread
## decides where its feet go. What this file owns is the ordering — the sequence
## below is the whole of it, and it is the sequence rather than any one line that
## makes a leg reach instead of skid:
##
##   census → stance → what the legs can do → what the jump is doing → the drive →
##   the chain settles → the feet are placed → the body comes down onto them → the
##   limbs are solved → the weight is posed and checked against the feet.
##
## Speed is a *request*: the animal asks for `move_speed`, the legs answer with
## whatever stride over cycle they can deliver, and the lower of the two is what the
## body travels at. The push behind it fades as the speed spends the muscle, so the
## top speed is an arrival rather than an assignment — there is no acceleration
## parameter anywhere in the v2 body.
##
## The flesh is drawn by `Likeness`, a child node reading `contour` — the skin,
## posed at the end of the tick once every bone has been placed. What *this* node
## draws is the solved skeleton itself, and only when `debug` is set: sticks at
## their bone radii, feet where they are planted, a shadow under whatever is off
## the ground, and the plumb line against the support the feet actually make. A
## debug view, but an honest one — every mark is state the systems put somewhere.
class_name Creature2
extends Node2D

const INK := Color(0.16, 0.15, 0.13)
const LIMB_INK := Color(0.35, 0.33, 0.30)
const SHADOW := Color(0.0, 0.0, 0.0, 0.10)
const FOOT := Color(0.72, 0.34, 0.18)
const STEP := Color(0.72, 0.34, 0.18, 0.45)
const PLUMB := Color(0.18, 0.42, 0.65)
const SUPPORT := Color(0.18, 0.42, 0.65, 0.25)
## How much a node's height lightens its ink — enough to read a carried neck
## against a dropped tail without pretending the top-down view has a horizon.
const HEIGHT_LIFT: float = 0.006

## Braking is stronger than getting going, and exempt from the speed fade: muscle
## resisting stretch holds more than muscle shortening ever delivers.
const BRAKE_MULTIPLIER: float = 2.0
## How much of a standing turn the legs carry the body through. Short of the whole,
## because the remainder is what the head leads the turn by — at 1.0 the body would
## rotate rigidly and the chain would never bend into the corner.
const STANDING_TURN_ASSIST: float = 0.6
const PIVOT_FADE_START: float = 0.08
const PIVOT_FADE_END: float = 0.45
## Least radius a travelling body carves its turn on, in its own body lengths.
const MIN_TURN_ARC: float = 1.15
## How much of its steering and acceleration a body keeps with nothing under its
## feet — small but not zero, and the whole reason a leap is a commitment.
const AIR_CONTROL: float = 0.14


## What is being asked of the animal this tick. The lab writes it from the
## keyboard; nothing in the body cares where it came from.
class Command extends RefCounted:
	var throttle: float = 0.0
	var turn: float = 0.0
	var sprint: bool = false
	var jump: bool = false


@export var body: BodySpec
## Draws the skeleton over the flesh — the state, rather than the animal.
@export var debug: bool = false

var armature: Armature = Armature.new()
var corpus: Corpus = Corpus.new()
var contour: Contour = Contour.new()
var poise: Poise = Poise.new()
var attitude: Attitude = Attitude.new()
var locomotor: Locomotor = Locomotor.new()
var tread: Tread = Tread.new()
var bound: Bound = Bound.new()
var footing: Footing = Footing.new()
var command: Command = Command.new()

## Where the head is being led, and on what bearing. The body follows it: the head
## is the one point on the chain that is placed rather than solved.
var head_pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var move_dir: Vector2 = Vector2.RIGHT
var speed: float = 0.0
var speed_norm: float = 0.0
var ang_vel: float = 0.0
var alive: bool = true

var terrain: Terrain


func _ready() -> void:
	if body == null:
		body = load("res://scripts/creature2/CatBody.tres")
	terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	build(Vector2.ZERO, 0.0)


## Builds every structure in the one order they may be built in: the stance first
## (the census reads the stance the animal is *built* in), then the chain, then the
## census, then the reductions that read it.
func build(at: Vector2, p_heading: float) -> void:
	attitude.rebuild(body)
	armature.build(body, at, p_heading)
	corpus.build(body)
	poise.bake(corpus, armature)
	attitude.derive(poise)
	tread.setup(armature)
	contour.build(corpus, armature)
	contour.pose()
	locomotor.update(attitude.active, corpus, poise, body, attitude)
	head_pos = armature.plan(armature.head_index())
	heading = p_heading
	move_dir = Vector2.RIGHT.rotated(heading)
	speed = 0.0
	speed_norm = 0.0
	ang_vel = 0.0
	armature.take_head(head_pos)


func _physics_process(delta: float) -> void:
	# The bake is revision-keyed: an ordinary tick bakes nothing, a wound re-bakes
	# once and the weight genuinely moves.
	poise.bake(corpus, armature)

	var airborne: bool = armature.fall.is_airborne()
	attitude.tick(delta, speed_norm, command.sprint, airborne)
	locomotor.update(attitude.active, corpus, poise, body, attitude)
	bound.update(attitude.active, locomotor, corpus, poise, body, tread.support)
	tread.set_launch(bound.launch)
	bound.tick(delta, command.jump and alive, armature)

	var ground: float = _ground_under(armature.centre(), body.trunk_length * 0.25)
	_integrate_motion(delta, airborne)

	# The chain follows its head, and then the gait reads the sockets it has just
	# been left with. Nothing about the feet may be decided before this: a foot is
	# placed relative to a socket, and the socket has just moved.
	armature.take_head(head_pos)
	armature.advance(delta, ground, speed_norm, attitude.active.wave_gain)
	# What the joints are being asked for: the jump's own crouch and push, plus
	# whatever a girdle short of support is giving way by. Both are the same signed
	# pair and they add, because a creature crouching to spring on legs that cannot
	# hold it is doing both things to one joint.
	var load: Vector2 = (bound.load + footing.give()).clampf(-1.0, 1.0)
	tread.update(delta, armature, locomotor, attitude.active, body, corpus,
		move_dir, speed_norm, airborne, _surface_query(), load, bound.drive)
	# ...and only now the vertical, because how high the body is held is a
	# measurement of the feet the gait has just placed.
	armature.carry(ground)
	armature.settle(ground)
	# What the back is doing about the stride: nothing at all under any alternating
	# gait, where the limbs of a pair are half a cycle apart and their offsets
	# cancel, and a real fold and extension twice a stride under a bound or a
	# gallop. Nothing had to detect a gallop for the spine to flex in one.
	armature.bunch(locomotor.bunch(tread.gather, tread.cadence.aerial))

	poise.pose(armature)
	poise.stand(armature)
	# ...and last of all the skin, over bones that have finished moving. Nothing
	# reads back from it, which is why it can be last: the flesh is a consequence
	# of the tick, never a term in it.
	contour.pose()
	footing.update(delta, tread, poise, corpus, locomotor,
		tread.cycle_length(), airborne, alive)
	# A body that has been unable to get a leg back underneath itself for longer
	# than it takes to swing one there goes down. Nothing here decides that it
	# should — the measurement is the decision, and what it measures is legs.
	if footing.failed and alive:
		toggle_collapsed()
	queue_redraw()


## Where the animal goes, and how fast it gets there.
##
## Turning is two ceilings and the more generous wins, because they are alternatives
## rather than costs: a body at a standstill is not carving an arc, and one at speed
## is not stepping its feet round in a circle. Thrust is one law — push over mass,
## fading with the speed already spent — and it is never multiplied by the feet the
## gait happens to have down this tick: the head takes part in the gait solve, so a
## thrust gated on the solved feet would let a glance perturb a straight run. The
## feet's share is priced where it is already a law of the body, in the duty factor
## inside `leg_speed`.
func _integrate_motion(delta: float, airborne: bool) -> void:
	var purchase: float = AIR_CONTROL if airborne else 1.0

	var turn_rate: float = locomotor.turn_rate \
		* (1.0 - body.turn_speed_falloff * speed_norm)
	var walked: float = 0.0
	if tread.pivot_speed > 0.0:
		walked = locomotor.walked_turn(tread.pivot_speed,
			head_pos.distance_to(armature.plan(armature.pelvis_index())))
	if walked > 0.0 and not airborne:
		turn_rate = minf(turn_rate, maxf(walked * (1.0 - speed_norm),
			absf(speed) / maxf(armature.body_length * MIN_TURN_ARC
				/ maxf(attitude.active.agility, 0.1), 1.0)))
	turn_rate *= purchase
	var desired_ang: float = clampf(command.turn, -1.0, 1.0) * turn_rate
	var response: float = body.turn_responsiveness
	if not is_zero_approx(ang_vel) and signf(desired_ang) != signf(ang_vel):
		response *= BRAKE_MULTIPLIER
	ang_vel = lerpf(ang_vel, desired_ang, 1.0 - exp(-response * delta))

	# Turning swings the head around a station on the body, so the chain and the feet
	# visibly take part rather than the heading simply being rewritten. How much of
	# that swing the body is carried through rather than towed into fades out as
	# travel takes over the arc: none of it walking forward, where the head leading is
	# the whole mechanism, and most of it on the spot, where the legs are what walk a
	# standing body around.
	var turn_delta: float = ang_vel * delta
	var swing: float = 1.0 - smoothstep(PIVOT_FADE_START, PIVOT_FADE_END, speed_norm)
	var pivot: Vector2 = armature.station_behind_head(body.turn_pivot)
	heading = wrapf(heading + turn_delta, -PI, PI)
	head_pos = pivot + (head_pos - pivot).rotated(turn_delta)
	if swing > 0.0:
		armature.rotate_followers(pivot, turn_delta * STANDING_TURN_ASSIST * swing)

	# What the species asks for, and then what the legs will honour. `move_speed` is
	# a request rather than a promise, and so is sprint: an animal already cycling its
	# legs as fast as they can be thrown has nothing left to spend on going quicker,
	# and the honest thing for it to do is not go quicker.
	var sprint: float = body.sprint_multiplier if command.sprint \
		and command.throttle > 0.0 else 1.0
	var asked: float = body.move_speed * sprint
	var legs: float = tread.leg_speed
	var top_speed: float = minf(asked, legs) if legs > 0.0 else asked
	if command.throttle < 0.0:
		top_speed *= body.reverse_speed_factor
	var desired: float = clampf(command.throttle, -1.0, 1.0) * top_speed

	var rate: float = locomotor.accel * purchase
	var reversing: bool = not is_zero_approx(speed) and not is_zero_approx(desired) \
		and signf(speed) != signf(desired)
	if reversing:
		speed = move_toward(speed, 0.0, rate * BRAKE_MULTIPLIER * delta)
	elif absf(desired) < absf(speed):
		# Pulling up: stronger than getting going and exempt from the fade below,
		# because that is what braking is.
		speed = move_toward(speed, desired, rate * BRAKE_MULTIPLIER * delta)
	else:
		# Getting going. The push fades as the speed spends the muscle — steep off the
		# mark, flattening through the middle, earning the last tenth over seconds —
		# and it is quoted against everything this animal will ever ask of itself, so
		# there is nothing left at all at flat out.
		rate *= locomotor.push_left(speed, flat_out())
		speed = move_toward(speed, desired, rate * delta)

	move_dir = Vector2.RIGHT.rotated(heading)
	head_pos += move_dir * (speed * delta)
	speed_norm = clampf(absf(speed) / cruise_speed(), 0.0, 1.0)


## The speed this creature walks at flat out without sprinting — the lower of what
## it asks for and what its legs will give, and the denominator every pace in the
## game is quoted against.
func cruise_speed() -> float:
	var legs: float = tread.leg_speed
	return maxf(minf(body.move_speed, legs) if legs > 0.0 else body.move_speed, 1.0)


## The speed it would travel at with everything open — deliberately the request
## alone, where `cruise_speed` takes the lower of the two. Effort has to mean the
## same thing from one tick to the next, and the leg ceiling moves with the footfall
## pattern: a body committing to a gallop is handed a higher ceiling for it, which
## would read as easing off at the moment it stopped easing off.
func flat_out() -> float:
	return maxf(body.move_speed * body.sprint_multiplier, 1.0)


func centre() -> Vector2:
	return armature.centre()


func reset() -> void:
	armature.reset()
	tread.setup(armature)
	tread.measured = false
	footing.reset()
	head_pos = armature.plan(armature.head_index())
	heading = armature.spawn_heading
	move_dir = Vector2.RIGHT.rotated(heading)
	speed = 0.0
	speed_norm = 0.0
	ang_vel = 0.0
	if not armature.collapsed:
		armature.take_head(head_pos)
	contour.pose()


func toggle_collapsed() -> void:
	if armature.collapsed:
		armature.revive()
		tread.measured = false
		head_pos = armature.plan(armature.head_index())
		armature.take_head(head_pos)
	else:
		armature.collapse()
	alive = not armature.collapsed


func drop(height: float) -> void:
	armature.drop(height)


func pick_node(world: Vector2, radius: float) -> int:
	return armature.pick_node(to_local(world), radius)


func haul_node(i: int, world: Vector2) -> void:
	armature.haul_to(i, to_local(world))


# ---------------------------------------------------------------- the ground ----

## What is under a foot put down here: the terrain's answer, or a flat floor in a
## habitat that has none. Handed to the gait as a callable so nothing in the body
## has to know what a rock is.
func _surface_query() -> Callable:
	if terrain == null:
		return Callable()
	return func(at: Vector2, foot: float, ceiling: float) -> Vector2:
		return terrain.surface(at, foot, ceiling)


func _ground_under(at: Vector2, radius: float) -> float:
	if terrain == null:
		return 0.0
	return terrain.surface(at, radius, INF).x


# ------------------------------------------------------------------ the view ----

func _draw() -> void:
	if not debug:
		return
	var a: Armature = armature
	# Shadows first: a soft line under any stick carried off the ground, so height
	# reads in a view that has no vertical axis.
	for s in a.stick_count():
		var pa: Vector3 = a.pos[a.stick_a[s]]
		var pb: Vector3 = a.pos[a.stick_b[s]]
		if maxf(pa.z, pb.z) > 1.0:
			draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y),
				SHADOW, a.stick_radius[s] * 2.0)
	for s in a.stick_count():
		var pa: Vector3 = a.pos[a.stick_a[s]]
		var pb: Vector3 = a.pos[a.stick_b[s]]
		var limb_stick: bool = a.stick_hold[s] < 1.0 or _is_limb_stick(s)
		var ink: Color = LIMB_INK if limb_stick else INK
		ink = ink.lightened(clampf((pa.z + pb.z) * 0.5 * HEIGHT_LIFT, 0.0, 0.35))
		draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y),
			ink, maxf(a.stick_radius[s] * 2.0, 1.5))
	# Feet: where they are planted, and where a swinging one is aimed.
	for foot in tread.feet:
		if foot.stepping:
			draw_line(foot.ground, foot.step_to, STEP, 1.0)
			draw_circle(foot.ground, 1.8, STEP)
		else:
			draw_circle(foot.planted, 2.4, FOOT)
	# The head, so the animal has a front.
	var head: Vector3 = a.pos[a.head_index()]
	draw_circle(Vector2(head.x, head.y), a.spec.skull_radius,
		INK.lightened(clampf(head.z * HEIGHT_LIFT, 0.0, 0.35)))
	# The weight: where the plumb line comes down, against the support the planted
	# feet make. Both are live readouts — if the mark drifts outside the feet the
	# body genuinely is out over its own edge.
	if poise.posed:
		if poise.feet >= 2:
			for i in poise._prints.size():
				draw_line(poise._prints[i],
					poise._prints[(i + 1) % poise._prints.size()], SUPPORT, 1.2)
		draw_circle(poise.centre, 2.0, PLUMB)
		draw_arc(poise.centre, 4.0, 0.0, TAU, 24, PLUMB, 1.0)


func _is_limb_stick(s: int) -> bool:
	for limb in armature.limbs:
		if s in limb.sticks:
			return true
	return false
