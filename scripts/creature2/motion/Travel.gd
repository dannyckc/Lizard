## The locomotion loop, stated once — v2's mover.
##
## One cycle, run every tick, each stage owned by one file:
##
##   intent (here) → desired velocity → desired acceleration → delivered
##   acceleration and the real velocity (Impetus) → the body and its weight
##   shift (here: the head is carried, the lean is set) → the attitude (here:
##   `tip`, Keel's heel against the feet) → the legs support and rebalance
##   (Footwork, coordinated by Rhythm, on ground Outlook has already looked
##   at) → the physical result (the armature solves, Poise measures the weight
##   against the feet) → the review (here: rescue steps, or the fall nothing
##   could rescue) → repeat.
##
## Nothing in the cycle is an animation and nothing overrides physics: the
## body travels because its velocity was integrated, the velocity changed
## because the feet had press to spend, and the feet moved because the body's
## own motion used up the support they were giving. A shove enters as what it
## is — a velocity the body did not ask for, at a place, so a press high on the
## flank also heels the animal over — and the same loop that walks recovers from
## it, or fails to and goes down on the side it was pushed toward. A wall enters
## the same way: the contact stage (`collide`) measures the trunk into the solid
## and changes the real state — position, velocity, turn rate, attitude — and the
## loop reacts to that.
##
## This file owns what is left over when the stages are taken out: reading
## the command into an ask, the turn, the jump's charge-and-spend, the crouch,
## the contact, the balance review, and writing the seam Creature2 publishes
## (`speed`, `speed_norm`, `ang_vel`, `head_pos`, `move_dir`). It is
## deliberately the only file that touches the creature's fields — the loop
## has one scribe.
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

## The most turn rate a glancing contact may put into the body in one tick,
## rad/s — a cap on the lever arithmetic, not a second physics.
const GLANCE_MAX: float = 2.0

## What the review calls a real deficit: a walking body is out over its own
## edge several times a second (Poise's old law), so rescue asks for the line
## a share of the support past the boundary, held for longer than a beat.
const WOBBLE_SHARE: float = 0.10
const WOBBLE_PATIENCE: float = 0.08


var creature: Creature2
var impetus: Impetus = Impetus.new()
var keel: Keel = Keel.new()
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
	keel.reset()
	lean = Vector2.ZERO
	crouch = 0.0
	_charge = 0.0
	_charging = false
	_absorb = 0.0
	_debt = 0.0
	_wobble = 0.0
	if creature != null:
		creature.armature.roll = 0.0
		if not creature.armature.collapsed:
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
	# The watched strip is the coming travel, but never shorter than half the
	# body: an animal does not stop watching the ground because it slowed
	# down, and it is this floor that lets it stand *at* a brink instead of
	# creeping over one it can no longer see.
	var throttle: float = clampf(cmd.throttle, -1.0, 1.0)
	var request: float = spec.move_speed \
		* (spec.sprint_multiplier if cmd.sprint else 1.0)
	var ask: float = throttle * request \
		* (spec.reverse_speed_factor if throttle < 0.0 else 1.0)
	var motion: Vector2 = impetus.velocity * Outlook.HORIZON
	var least: float = spec.trunk_length * 0.5
	if absf(ask) >= 1.0 and motion.length() < least:
		motion = Vector2.RIGHT.rotated(creature.heading) * least * signf(throttle)
	# ...watched from the girdle that will arrive first, because the standoff a
	# hazard deserves is measured to the body's leading feet, not to its middle:
	# a body that watched from its centre would hang its whole fore quarter
	# over a brink before the ask died.
	var lead: int = a.withers_index() if throttle >= 0.0 else a.pelvis_index()
	ask *= outlook.headroom(a.plan(lead), motion, ground, spec.hind_leg_length)

	# The turn: a rate the anatomy and the pace gate, eased at the body's own
	# responsiveness. Airborne there is nothing to turn against.
	#
	# Two inputs, and the hand has the last word: the head is asked for only as
	# much of the turn as the player is not already taking by hand, so A and D
	# still mean exactly what they meant and an animal walking forward with
	# nothing held goes where it is looking. See `Gaze.lead`, which is where the
	# whole of that is decided and bounded.
	var falloff: float = lerpf(1.0, spec.turn_speed_falloff,
		clampf(creature.speed_norm, 0.0, 1.0))
	var by_hand: float = clampf(cmd.turn, -1.0, 1.0)
	var demand: float = clampf(by_hand
		+ creature.gaze.lead() * (1.0 - absf(by_hand)), -1.0, 1.0)
	var want: float = 0.0
	if not airborne:
		want = demand * deg_to_rad(spec.turn_speed_deg) \
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


## The world's solid half pressing back — the contact stage of the loop. Runs
## after the plan solve has placed the body and before the feet answer, so a
## correction shows up as support drift the same tick. Nothing here is a rule
## about walls: the trunk is measured into whatever solid it occupies, at the
## body's own height band (so a leap clears what a walk is refused by, and an
## overhang above the back is walked under), and what an intrusion changes is
## the *state* —
##
##   * the body is pressed out positionally: the armature is shifted, never
##     re-solved, and the planted feet stay where they are, so the drift the
##     shift opens is how the legs learn about the wall;
##   * the velocity into the face is taken away and the slide along it keeps,
##     which is what bracing against a wall and skirting along one both are;
##   * a hard stop sinks the body by its impact — the same absorb a landing
##     spends — a press at one end swings the body about its own middle, eased
##     back out by the same easing that serves the intent, and the same press
##     heels it over about the height it landed at: a post caught at the knees
##     takes the legs out from under the animal, which is a different accident
##     from one caught at the shoulder.
##
## Everything after that is the ordinary loop reacting to the new state.
func collide() -> void:
	var a: Armature = creature.armature
	if a.collapsed:
		return
	var pel: Vector2 = a.plan(a.pelvis_index())
	var wit: Vector2 = a.plan(a.withers_index())
	var trunk: Armature.Chain = a.chain(BodySchema.TRUNK)
	var r: float = 2.0
	for i in trunk.nodes:
		r = maxf(r, a.flesh_r[i])
	var clearance: float = a.fall.height
	var band := Vector2(
		clearance + minf(a.fore_carry, a.hind_carry) - r,
		clearance + maxf(a.fore_carry, a.hind_carry) + r)
	var push: Vector2 = outlook.intrusion(pel, wit, r, band)
	if push == Vector2.ZERO:
		return
	a.shift(push)
	creature.head_pos += push
	var n: Vector2 = push.normalized()
	var impact: float = impetus.deflect(n)
	if impact <= 0.0:
		return
	_absorb = maxf(_absorb, clampf(impact / ABSORB_SCALE, 0.0, 0.6))
	var wd: Vector2 = outlook.intrusion_at(wit, r, band)
	var pd: Vector2 = outlook.intrusion_at(pel, r, band)
	var deep: int = a.withers_index() if wd.length_squared() >= pd.length_squared() \
		else a.pelvis_index()
	var at: Vector2 = a.plan(deep)
	var lever: Vector2 = at - a.centre()
	var torque: float = lever.x * n.y - lever.y * n.x
	creature.ang_vel += clampf(torque * impact / maxf(lever.length_squared(), 1.0),
		-GLANCE_MAX, GLANCE_MAX)
	# ...and the same press taken at the height it happened, which is the half
	# the yaw lever above has never been able to say.
	twist(n * impact, a.pos[deep])


## The attitude stage: what the body's own weight, and whatever has just hit it,
## are doing to how far over it is being held.
##
## Runs after both contact stages have landed their impulses and before the
## vertical is solved, so this tick's heel is what the carries, the limbs and the
## skin all express. The support it balances against is last tick's measurement —
## the loop's one frame of lag, and exactly the lag the feet already answer the
## body's own motion with, because a control loop measures the result of the last
## thing it did.
func tip(delta: float) -> void:
	var a: Armature = creature.armature
	keel.derive(creature.corpus)
	var p: Poise = creature.poise
	# A body in the air turns about its own centre and has nothing at all to
	# press against; one on its feet turns about the ground and holds itself
	# level with them. The distinction has to be made here rather than left to
	# the numbers, because the support Poise hands over is last tick's: a body
	# that has just left the ground would otherwise balance against feet it no
	# longer has, and about the free-body inertia, which is a very large torque
	# on an animal that is simply in the air.
	var footed: bool = not a.fall.is_airborne() and not a.collapsed and p.posed
	var count: int = maxi(footwork.feet.size(), 1)
	keel.tick(delta,
		p.flanks(_lateral()) if footed else Vector2.ZERO,
		p.height if footed else 0.0,
		_stance_hold(footwork.planted(), count) if footed else 0.0,
		(a.fore_half + a.hind_half) * 0.5, impetus.power, a.collapsed)
	a.roll = keel.roll


## How much of its righting a body has with `down` of its `all` feet on the
## ground. Not the plain share: one planted leg is a whole lever and the girdle
## behind it is what presses, so a galloping animal on a single forefoot is not a
## twentieth as able to hold itself level as it was standing square. The floor is
## what a leg is worth on its own, and the rest is company.
func _stance_hold(down: int, all: int) -> float:
	if down <= 0:
		return 0.0
	return clampf(0.55 + 0.45 * float(down) / float(maxi(all, 1)), 0.0, 1.0)


## The support: after the plan solve has moved the sockets, the feet answer.
func support(delta: float, _ground: float) -> void:
	var a: Armature = creature.armature
	if a.collapsed:
		return
	if a.fall.landed:
		footwork.touchdown()
		_absorb = maxf(_absorb, clampf(a.fall.impact / ABSORB_SCALE, 0.0, 0.8))
		# The feet have the body again: from here the carries quote them, so
		# the fall's frame is spent — the arc is over, whatever ground it ended
		# on, and the legs absorb the rest. Also why a body never bounces: it
		# is meat with knees, not rubber.
		a.fall.absorb_landing(0.0)
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
##
## The attitude is reviewed on the same terms and answered with the same step. A
## heel that has taken the weight past the foot it is pivoting on is a deficit
## the plan cannot see — the plumb line is still inside the hull, the body is
## still going over — and what saves it is the one thing that ever saves a topple:
## a foot put down further out, which moves the pivot. Past the angle no step can
## reach around, the body has gone, and it goes *the way it was going*.
func review(delta: float) -> void:
	var a: Armature = creature.armature
	if a.collapsed or a.fall.is_airborne():
		_debt = 0.0
		_wobble = 0.0
		return
	var p: Poise = creature.poise
	# A grounded body with no planted feet at all is not "free of deficit" —
	# it is a body whose every foot has been torn off its footing (a cliff
	# edge, a floor that vanished), and it gets the fall's own patience, not
	# the wobble's benefit of the doubt.
	if p.posed and p.feet == 0:
		_debt += delta
		if _debt > FALL_PATIENCE:
			_fell(a)
		return
	if keel.going_over():
		_fell(a)
		return
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
				_fell(a)
			return
	elif not keel.strained:
		_wobble = 0.0
		footwork.calm()
	# The heel's own demand, and it is not held for a beat: a body whose legs
	# have run out of press to hold it level has no beats to spare, and what it
	# is asking for is a foot out past where the weight is going rather than
	# under where it is. `strained` and not `spill` is deliberately the trigger:
	# a walking animal is over its own lateral edge every other stride and holds
	# itself there without noticing, and rescuing that was the churn that ate
	# the support it was rescuing. The step is asked for when the muscle is
	# beaten, which is the honest moment a leg has to move instead of press.
	if keel.strained and keel.side != 0.0 and p.posed:
		footwork.rescue(p.centre,
			_lateral() * (keel.side * maxf(keel.spill, p.pad)))
	_debt = maxf(_debt - 2.0 * delta, 0.0)


## The body goes down, however it got there — the same collapse a death is. Keel
## keeps whatever heel it arrived with, so a creature knocked over lands on that
## flank and one whose heart stopped lands on its belly.
func _fell(a: Armature) -> void:
	a.collapse()
	creature.vitals.arrested = true
	creature.alive = false
	impetus.halt()


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


## An external twist, arriving as the turn rate it caused — the rotational
## half of Impetus.shove, for charges and glancing blows. The same easing that
## serves the intent brings the rate back to the ask: recovery from a spin is
## the loop noticing the body is turning faster than anything asked.
func spin(dw: float) -> void:
	creature.ang_vel += dw


## An external force, as the velocity change it caused and the place it landed —
## the whole of the seam contacts, charges and knocks push through.
##
## The place is what the old flat seam threw away. A push is three numbers and a
## point, and the point's *height* is what rolls an animal: press a standing cat
## high on the flank and it goes over away from the hand; press exactly as hard
## at its knees and it goes over toward you, because the lever changed sign. Both
## come out of one multiplication in `Keel.strike`, and neither is a rule about
## pushes. `at` may be left out where the caller genuinely has no place to give
## — a body throwing itself forward off its own hind legs pushes through its own
## weight — and then the shove is what it always was.
func shove(dv: Vector2, at: Vector3 = Vector3.INF) -> void:
	impetus.shove(dv)
	twist(dv, at)


## The angular half on its own, for the contact stages: they take the velocity
## out of the body themselves (`Impetus.deflect`), and what is left to account
## for is the twist that came with it.
func twist(dv: Vector2, at: Vector3) -> void:
	if at.x >= INF or not creature.poise.posed or creature.armature.collapsed:
		return
	# The lever is measured from the axis the body will actually turn about, and
	# which axis that is changes what a low press does. A standing animal turns
	# about the ground its feet are on: every press above the floor tips it the
	# same way, harder the higher it lands, and one at the toes hardly tips it
	# at all — you cannot take a body's legs out from under it by pressing
	# *above* where they meet the ground. A body in the air turns about its own
	# weight, and there a press below the centre genuinely rolls it the other
	# way. One subtraction, and it is the whole difference.
	var footed: bool = not creature.armature.fall.is_airborne()
	var high: float = creature.poise.height if footed else 0.0
	var axis: float = 0.0 if footed else creature.poise.height
	keel.strike(dv.dot(_lateral()), at.z - axis, high)


## Across the body, on the plan — the axis a heel is measured about, and the
## same right-hand side `Armature.perp` and the census's flank sectors mean.
func _lateral() -> Vector2:
	var dir: Vector2 = Vector2.RIGHT.rotated(creature.heading)
	return Vector2(-dir.y, dir.x)


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
