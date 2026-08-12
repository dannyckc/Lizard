## The locomotion loop, stated once — v2's mover.
##
## One cycle, run every tick, each stage owned by one file:
##
##   intent (here) → desired velocity → desired acceleration → delivered
##   acceleration and the real velocity (Impetus) → the body and its weight
##   shift (here: the head is carried, the lean is set) → the legs support
##   and rebalance (Footwork, coordinated by Rhythm, on ground Outlook has
##   already looked at) → the physical result (the armature solves, Poise
##   measures the weight against the feet) → the review (here: rescue steps,
##   or the fall nothing could rescue) → repeat.
##
## Nothing in the cycle is an animation and nothing overrides physics: the
## body travels because its velocity was integrated, the velocity changed
## because the feet had press to spend, and the feet moved because the body's
## own motion used up the support they were giving. A shove enters as what it
## is — a velocity the body did not ask for — and the same loop that walks
## recovers from it, or fails to and falls.
##
## This file owns what is left over when the stages are taken out: reading
## the command into an ask, the turn, the jump's charge-and-spend, the crouch,
## the balance review, and writing the seam Creature2 publishes (`speed`,
## `speed_norm`, `ang_vel`, `head_pos`, `move_dir`). It is deliberately the
## only file that touches the creature's fields — the loop has one scribe.
class_name Travel
extends RefCounted

## Share of cruise below which turning is the legs walking the body round
## rather than the head leading it round an arc.
const STANDSTILL: float = 0.30

## How much of the true pendulum lean (thrust over gravity, at the weight's
## own height) the support is asked to express. Under one because the legs
## also brace — a body that leaned the whole term would be forever stepping.
const LEAN_SHARE: float = 0.6
const LEAN_MAX: float = 5.0

## The jump: held is a charge sunk into the crouch, released is spent through
## the hind girdle. Peak is priced at power one and full charge, px.
const CHARGE_TIME: float = 0.35
const JUMP_PEAK: float = 26.0
## Plan speed a full charge adds along the facing when the ask is forward.
const JUMP_RUN: float = 55.0

## Landing absorb: the crouch a landing sinks into, priced off the impact.
const ABSORB_SCALE: float = 400.0
const ABSORB_RATE: float = 3.0

## The review's patience: how long the weight may hang past what the legs
## can reach before the body is falling rather than stumbling.
const FALL_SHARE: float = 0.9
const FALL_PATIENCE: float = 0.35

## What the review calls a real deficit: a walking body is out over its own
## edge several times a second (Poise's old law), so rescue asks for the line
## a share of the support past the boundary, held for longer than a beat.
const WOBBLE_SHARE: float = 0.10
const WOBBLE_PATIENCE: float = 0.08


var creature: Creature2
var impetus: Impetus = Impetus.new()
var outlook: Outlook = Outlook.new()
var rhythm: Rhythm = Rhythm.new()
var footwork: Footwork = Footwork.new()

## The current home-shift the acceleration asks of the support, world px.
var lean: Vector2 = Vector2.ZERO
## How sunk the body is carried, 0..1 — the charge and the landing absorb.
var crouch: float = 0.0

var _charge: float = 0.0
var _charging: bool = false
var _absorb: float = 0.0
var _debt: float = 0.0
var _wobble: float = 0.0


func build(p_creature: Creature2) -> void:
	creature = p_creature
	outlook.attach(creature.terrain)
	impetus.derive(creature.corpus)
	footwork.build(creature, outlook, rhythm)
	reset()


## Puts the mover back to a standstill wherever the body is — a spawn, a
## reset, a revival. The feet re-adopt the stance the armature is standing in.
func reset() -> void:
	impetus.halt()
	lean = Vector2.ZERO
	crouch = 0.0
	_charge = 0.0
	_charging = false
	_absorb = 0.0
	_debt = 0.0
	_wobble = 0.0
	if creature != null and not creature.armature.collapsed:
		footwork.build(creature, outlook, rhythm)


# ---------------------------------------------------------------- the loop ----

## Intent through body shift: the command becomes an ask, the ask a desired
## velocity, Impetus answers with the real one, and the head — the chain's
## one driven point — is carried by it. Runs before the armature's plan
## solve, which is what makes the body follow this tick's motion.
func steer(delta: float, ground: float) -> void:
	var a: Armature = creature.armature
	impetus.derive(creature.corpus)
	if a.collapsed:
		impetus.halt()
		_publish(Vector2.RIGHT.rotated(creature.heading))
		return

	var spec: BodySpec = creature.body
	var cmd: Creature2.Command = creature.command
	var airborne: bool = a.fall.is_airborne()

	_jump(delta, a, spec, cmd, airborne)

	# The intent: what is being asked, throttled by what the path ahead
	# permits — a wall is approached the way an obstacle is, not driven into.
	var throttle: float = clampf(cmd.throttle, -1.0, 1.0)
	var request: float = spec.move_speed \
		* (spec.sprint_multiplier if cmd.sprint else 1.0)
	var ask: float = throttle * request \
		* (spec.reverse_speed_factor if throttle < 0.0 else 1.0)
	var motion: Vector2 = impetus.velocity * Outlook.HORIZON
	ask *= outlook.headroom(a.centre(), motion, ground, spec.hind_leg_length)

	# The turn: a rate the anatomy and the pace gate, eased at the body's own
	# responsiveness. Airborne there is nothing to turn against.
	var falloff: float = lerpf(1.0, spec.turn_speed_falloff,
		clampf(creature.speed_norm, 0.0, 1.0))
	var want: float = 0.0
	if not airborne:
		want = clampf(cmd.turn, -1.0, 1.0) * deg_to_rad(spec.turn_speed_deg) \
			* creature.attitude.active.agility * falloff
	creature.ang_vel = lerpf(creature.ang_vel, want,
		1.0 - exp(-spec.turn_responsiveness * delta))
	var dtheta: float = creature.ang_vel * delta
	creature.heading = wrapf(creature.heading + dtheta, -PI, PI)
	var dir: Vector2 = Vector2.RIGHT.rotated(creature.heading)

	# The middle of the loop: desire → demand → delivery → the real velocity.
	impetus.propel(delta, dir * ask, dir, creature.attitude.active.drive,
		footwork.grip, airborne)

	# The body shift. The head is swung by the turn and carried by the actual
	# velocity; at a standstill the followers are walked round too, because
	# there the legs are what turn the body, not the head leading an arc — and
	# the pivot slides back to the body's own middle as the speed drains, since
	# an animal turning on the spot turns about itself, not about its shoulders.
	var stand_share: float = 1.0 - clampf(impetus.speed()
		/ maxf(STANDSTILL * creature.cruise_speed(), 1.0), 0.0, 1.0)
	var mid: float = spec.neck_length + spec.head_offset + spec.trunk_length * 0.5
	var pivot: Vector2 = a.station_behind_head(
		lerpf(spec.turn_pivot, mid, stand_share))
	creature.head_pos = pivot + (creature.head_pos - pivot).rotated(dtheta) \
		+ impetus.velocity * delta
	a.rotate_followers(pivot, dtheta * stand_share)

	# ...and the lean the support will be asked to express: the true pendulum
	# term — delivered thrust over gravity at the weight's own height — with
	# the sign that puts the feet behind the push.
	var high: float = creature.poise.height if creature.poise.posed else 30.0
	lean = (-impetus.thrust / Gravity.PULL * high * LEAN_SHARE) \
		.limit_length(LEAN_MAX)

	_publish(dir)


## The support: after the plan solve has moved the sockets, the feet answer.
func support(delta: float, _ground: float) -> void:
	var a: Armature = creature.armature
	if a.collapsed:
		return
	if a.fall.landed:
		footwork.touchdown()
		_absorb = maxf(_absorb, clampf(a.fall.impact / ABSORB_SCALE, 0.0, 0.8))
	footwork.tick(delta, creature, impetus.velocity, lean, crouch,
		creature.speed_norm, a.fall.is_airborne())


## The sockets have just been carried — hand each limb the height the body is
## actually holding it at, so the leg solves from the solved trunk.
func perch() -> void:
	if not creature.armature.collapsed:
		footwork.perch(creature.armature)


## The review: the physical result against the feet. A weight going over its
## edge demands rescue steps; a weight past what any leg can reach, for
## longer than a stumble lasts, is a fall — and the fall is real: the same
## collapse a death is, because the ground does not care why a body arrives.
func review(delta: float) -> void:
	var a: Armature = creature.armature
	if a.collapsed or a.fall.is_airborne():
		_debt = 0.0
		_wobble = 0.0
		return
	var p: Poise = creature.poise
	var deficit: bool = p.posed and p.feet > 0 \
		and p.clearance < -WOBBLE_SHARE * maxf(p.span, 1.0)
	if deficit:
		# Held for a beat before it is believed: a mid-stride body is out over
		# its own edge as a matter of course, and rescuing every wobble was the
		# churn that ate the support it was rescuing.
		_wobble += delta
		if _wobble >= WOBBLE_PATIENCE:
			footwork.rescue(p.centre, p.overhang)
		var reachable: float = creature.attitude.active.plan_reach(
			creature.body.hind_leg_length)
		if p.overhang.length() > reachable * FALL_SHARE:
			_debt += delta
			if _debt > FALL_PATIENCE:
				a.collapse()
				creature.alive = false
				impetus.halt()
			return
	else:
		_wobble = 0.0
		footwork.calm()
	_debt = maxf(_debt - 2.0 * delta, 0.0)


# -------------------------------------------------------------- the pieces ----

## The jump: held is a charge (the crouch deepens — the body genuinely sinks,
## because the carries read the crouch), released is spent as a launch through
## the world's one integrator, plus a forward share when the body was asked
## forward. Airborne it all keeps: the arc belongs to Gravity.Fall.
func _jump(delta: float, a: Armature, spec: BodySpec, cmd: Creature2.Command,
		airborne: bool) -> void:
	if cmd.jump and not airborne:
		_charging = true
		_charge = minf(_charge + delta / CHARGE_TIME, 1.0)
	elif _charging:
		_charging = false
		if not airborne:
			var hind: float = creature.corpus.girdle_soundness(false)
			var spent: float = (0.35 + 0.65 * _charge) * impetus.power * hind
			a.launch(Gravity.launch_rate(JUMP_PEAK * spent))
			var forward: float = maxf(clampf(cmd.throttle, -1.0, 1.0), 0.0)
			impetus.shove(Vector2.RIGHT.rotated(creature.heading)
				* (JUMP_RUN * spent * forward))
		_charge = 0.0
	_absorb = maxf(_absorb - ABSORB_RATE * delta, 0.0)
	crouch = maxf(_charge * 0.8, _absorb)


## The seam, written in one place: what the rest of the game reads of the
## mover. `move_dir` is where the body is actually going when it is going
## anywhere, and its facing when it is not.
func _publish(dir: Vector2) -> void:
	creature.speed = impetus.speed()
	creature.speed_norm = creature.speed / creature.cruise_speed()
	if creature.armature.collapsed:
		creature.ang_vel = 0.0
		creature.speed = 0.0
		creature.speed_norm = 0.0
	creature.move_dir = impetus.velocity / creature.speed \
		if creature.speed > 5.0 else dir
