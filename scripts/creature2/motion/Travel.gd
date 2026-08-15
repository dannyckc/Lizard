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

## How much of the give in a back a turn steers with, before the species' own
## `spine_freedom` takes its share of that.
##
## A and D are a steer: the front of the animal goes first and the rest follows
## it, so the back is held bent into the turn for as long as the turn lasts —
## the fore girdle leads, the sockets hanging off it lead with it, the hips come
## after. That lead is what makes the input read as a body changing direction
## rather than as a sprite being rotated, and it is the whole of the difference.
##
## A *share* of what the back will physically give, and a small one, because
## those are two different numbers: `Armature.back_sweep` is what the joints
## allow before the anatomy is violated — a carcass folding double, most of a
## circle on this build — and this is the working range a muscle steers inside.
## Asked for the whole of it, the animal whips its own forehand out from under
## its weight and falls over, which is exactly what it did.
##
## A fifth of it was still too much, and what it looked like was the diagnosis:
## 37° of the animal's own back held folded for as long as a key was down is a
## trunk doing the turning, and a trunk that turns is a snake. A cat's back is
## dorsomobile — it flexes and extends far more freely than it bends sideways —
## so the lateral lead a real one carries into a turn is a fraction of what its
## joints would physically permit. At 0.09 the lead comes out near 17°: plainly
## visible as the front of the animal going first, well short of the fold that
## made the picture serpentine, and it costs the turn rate nothing at all (see
## `steer_front`) — what actually brings the hindquarters round is the hind feet
## stepping, which is where a cat's turn has always come from.
const STEER_BEND: float = 0.09

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

## The friction under a downed body, as the share of gravity a flank on dirt
## decelerates at — Coulomb, not viscous, and the distinction is load-bearing
## twice over. A knocked-over animal keeps the momentum it fell with and
## genuinely slides out on it (1.4× flat-out arrives ~11 px from where it
## went down), because a constant deceleration spends a real velocity over a
## real distance. And the same constant *zeroes* the sub-pixel velocities the
## contact seams drip into a lying body every tick — a carcass being leaned
## on by another animal is pressed, not set adrift, where an exponential
## decay left every drip alive and a held carcass crawled across the floor
## under its own bite.
const SLIDE_GRIP: float = 0.6

## The get-up. `REGATHER` is the beat a downed animal takes before it starts
## working — a breath, not a stopwatch on physics — and `RISE_RATE` prices the
## push-up at power one: the actual rise is it times the census's own
## power and what is left of the limbs, so a heavy, weak or chewed body
## genuinely takes longer to stand and one without enough limb never does.
const REGATHER: float = 0.45
const RISE_RATE: float = 1.5
## Sternal enough to start pushing up, radians of remaining heel.
const STERNAL: float = 0.12

## The bound's flight is only taken off the gait when the gathered beat is
## developed enough to mean it — under this the four-off moment is a stumble,
## not a suspension.
const BOUND_FLOOR: float = 0.25
## The stride hop's muscle cap, as a share of a full standing jump's peak: the
## legs at a gallop spend their extension through the stride, not gathered
## under a charge.
const BOUND_PEAK_SHARE: float = 0.25

## How quickly the spine's stride share follows the measured gait, per second —
## an easing on a measurement, so the back rounds through the stride instead of
## snapping between poses.
const SPINE_EASE: float = 10.0
## What a full gather folds and a full drive extends the back by, as `bunch`
## shares of the trunk's plan rests. The flexion is the bigger half — a
## galloping cat's lumbar spine rounds far more than it hollows.
const BUNCH_FLEX: float = 0.18
const BUNCH_EXT: float = 0.08

## The most turn rate a glancing contact may put into the body in one tick,
## rad/s — a cap on the lever arithmetic, not a second physics.
const GLANCE_MAX: float = 2.0

## How much harder a body sheds a turn nobody asked for than it takes one up, as
## a multiple of the species' own `turn_responsiveness`.
##
## The two are one muscle and emphatically not one act, and this whole constant
## exists because they were written as one line and it was wrong. Taking up a
## turn is deliberate: the animal decides to change direction, and the weight in
## how gradually the rate arrives is the good half of what A and D should feel
## like. Shedding a spin a rock put into your shoulder is not deliberate at all —
## it is bracing, and an animal braces as hard as it has legs to brace with.
##
## Eased at one rate, the two trade off against each other and there is no
## setting that serves both: quick enough to stay pointed at what hit you and the
## controls are a switch; weighted enough to feel like a body and a glancing
## contact sends the animal round an obstacle it was walking into, still at full
## cruise, because the yaw the contact opened never died. That was a real
## regression and this is what it cost — one number, and the admission that the
## body's own turning and the turning done to it are separate quantities that
## add (`_asked` and `_spin`).
const BRACE: float = 2.5

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

## What the loop is being asked for this tick, px/s along the facing, and how
## much of that ask the ground ahead permitted — 1 on open ground, 0 where
## `Outlook` has refused it (the balk). Readouts of the intent, written here
## because this is where the intent is read; nothing downstream consumes them.
var ask_speed: float = 0.0
var headroom: float = 1.0

## The loop's own record of itself, for whoever is watching it — see
## `MotionReadout`. Inert and allocation-free until something switches it on.
var readout: MotionReadout = MotionReadout.new()

## The current home-shift the acceleration asks of the support, world px.
var lean: Vector2 = Vector2.ZERO
## How sunk the body is carried, 0..1 — the charge and the landing absorb.
var crouch: float = 0.0

## The two halves of `creature.ang_vel`, which is their sum and is written from
## nowhere else: the turn the animal is taking (eased onto the hand's ask at the
## body's own `turn_responsiveness`) and the turn the world has put into it (a
## contact, a charge, a blow — shed at `BRACE` times that). Separate because they
## are separate acts; see `BRACE`.
var _asked: float = 0.0
var _spin: float = 0.0

var _charge: float = 0.0
var _charging: bool = false
var _absorb: float = 0.0
var _debt: float = 0.0
var _wobble: float = 0.0

## Whether the body is in a stride's own flight — the gallop's suspension, as
## distinct from a leap: the swings that were already going keep going, and the
## first foot to arrive catches the body.
var _stride_flight: bool = false

## The spine's stride share, eased off the measured gait: how gathered the back
## is (the hind pair swinging under the body) and how hard it is driving (the
## delivered thrust against its own ceiling). Both are measurements of the
## loop, never clocks.
var _gather: float = 0.0
var _drive: float = 0.0

## Where a downed body is in coming back: still toppling, settled, rolling
## sternal, or pushing up. UP is a body that is not down.
enum Down {UP, TOPPLING, SETTLED, RIGHTING, RISING}
var _down: int = Down.UP
var _down_wait: float = 0.0
## The push-up's progress, 0..1 — what scales the carries and the press
## through `Footwork.rise`.
var _rise: float = 0.0


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
	_asked = 0.0
	_spin = 0.0
	_charge = 0.0
	_charging = false
	_absorb = 0.0
	_debt = 0.0
	_wobble = 0.0
	_stride_flight = false
	_gather = 0.0
	_drive = 0.0
	_down = Down.UP
	_down_wait = 0.0
	_rise = 0.0
	footwork.rise = 1.0
	# Whatever was recorded happened to a body that is no longer standing where
	# this one is — see MotionReadout.clear.
	readout.clear()
	if creature != null:
		creature.armature.roll = 0.0
		creature.armature.pitch = 0.0
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
		# A downed body is not parked by fiat: whatever plan momentum it fell
		# with is kept, spent as a slide, and shed by the ground the way a
		# flank on dirt sheds it — a constant friction off the one pull, so a
		# hard topple slides out over real distance and a small press dies
		# where it lands. The whole chain goes with it; the feet went with the
		# body the moment it stopped being a stance.
		var slide: float = impetus.velocity.length()
		var shed: float = SLIDE_GRIP * Gravity.PULL * delta
		if slide > shed:
			impetus.velocity *= (slide - shed) / slide
			a.shift(impetus.velocity * delta)
		else:
			impetus.halt()
		ask_speed = 0.0
		headroom = 1.0
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
	headroom = outlook.headroom(a.plan(lead), motion, ground, spec.hind_leg_length)
	ask *= headroom
	ask_speed = ask

	# The turn: a rate the anatomy and the pace gate, eased at the body's own
	# responsiveness. Airborne there is nothing to turn against.
	#
	# One input, and it is the hand. A and D are the only thing in the game that
	# writes `heading`, so where the body is pointed is somewhere the player put
	# it and nothing else can quietly move it — the look does not steer (see
	# `Gaze`), and neither does anything the cursor is resting on.
	var falloff: float = lerpf(1.0, spec.turn_speed_falloff,
		clampf(creature.speed_norm, 0.0, 1.0))
	var demand: float = clampf(cmd.turn, -1.0, 1.0)
	# The rate the animal's own legs turn it at — the ceiling on the heading and
	# the ruler the steer's bend is quoted against.
	var rate: float = 0.0
	if not airborne:
		rate = deg_to_rad(spec.turn_speed_deg) \
			* creature.attitude.active.agility * falloff
	# The animal's own turn, eased on and eased off at the weight the species
	# carries — and the world's contribution shed under it, faster, because
	# holding your line against a knock is not the same act as choosing to turn.
	# They add, and their sum is the only thing anything else ever reads.
	_asked = lerpf(_asked, demand * rate, 1.0 - exp(-spec.turn_responsiveness * delta))
	_spin *= exp(-spec.turn_responsiveness * BRACE * delta)
	creature.ang_vel = _asked + _spin
	creature.heading = wrapf(creature.heading + creature.ang_vel * delta, -PI, PI)
	var dir: Vector2 = Vector2.RIGHT.rotated(creature.heading)

	# The middle of the loop: desire → demand → delivery → the real velocity.
	impetus.propel(delta, dir * ask, dir, creature.attitude.active.drive,
		footwork.grip, airborne)

	var dtheta: float = creature.ang_vel * delta
	# Which end is leading. A body going forward is *pulled*: the head is the
	# pinned point, the chain follows it, and that is the whole of a head-driven
	# solve. A body going backwards is *pushed* — there is nothing out in front
	# of it to follow — so the animal is carried bodily and the head rides on it
	# rather than being towed back through its own neck. Towing it was what
	# jack-knifed a reversing animal: the pin was being driven into the chain, the
	# trunk had to go somewhere, and it went sideways until the creature had spun
	# itself round without one degree of it reaching the heading.
	var pushed: float = clampf(-impetus.velocity.dot(dir)
		/ maxf(STANDSTILL * creature.cruise_speed(), 1.0), 0.0, 1.0)

	# The steer, first, because it changes the shape everything below is measured
	# on: the back held bent into the turn, front ahead of hips, for as long as
	# the animal is turning. This is what A and D *are* — the thing that moves
	# first is the front of the body and the hindquarters come after it — and the
	# rotation below is only how far round the animal has got.
	#
	# A posture, and that is the whole of why it works. Spending a share of every
	# tick's turn on the bend instead makes the bend an integral: it deepens for
	# as long as the key is down, and a back gives a great deal (`back_sweep` is
	# most of a circle) before the anatomy complains — so what that gave was an
	# animal folded double with its forehand swung out from under its own weight,
	# on the floor inside a second. Held to a lead instead it builds as the turn
	# starts, holds while it lasts, comes out as it ends, and costs the turn rate
	# nothing at all: the body still comes round exactly as fast as it ever did.
	#
	# Suppressed while the body is being pushed, because a body going backwards
	# is not being steered from the front — it turns as one piece.
	#
	# And it only ever bends the back *into* the turn, never out of one — it
	# supplies the lead the body has not already got, and takes none away. A spine
	# is bent by a dozen things that are not this: the arc it is travelling, its
	# own lateral wave, a wall it was pressed by. Written as "hold the back at
	# exactly this angle" the steer spends every tick undoing them, and that
	# version was worse than no steer at all — a walking turn that had been a wide
	# arc became the animal knotting itself up on the spot, because the fold was
	# fighting the very bend the turn was producing. It is also why nothing here
	# has to know how fast the animal is going: a body already carving an arc is
	# bent past the lead by the arc, and the steer quietly has nothing to add.
	# Coming out of a bend needs nobody's help either; the solve straightens a
	# driven body on its own.
	var bend: float = wrapf(a.fwd[a.withers_index()].angle()
		- a.fwd[a.pelvis_index()].angle(), -PI, PI)
	var into: float = _steer_lead(a) * (1.0 - pushed) \
		* clampf(creature.ang_vel / maxf(rate, 0.0001), -1.0, 1.0)
	var add: float = 0.0
	if absf(into) > 0.0001 and (bend * into <= 0.0 or absf(bend) < absf(into)):
		add = clampf(into - bend, -rate * delta, rate * delta)
	var head_was: Vector2 = a.plan(a.head_index())
	a.steer_front(add)
	# What the steer did to the head, which the drive has to keep: the head is
	# re-placed from `head_pos` a few lines below and would otherwise be dragged
	# straight back off the bend the neck and shoulders have just taken, leaving
	# the chain solving against a head that disagrees with its own body. Added to
	# `head_pos` rather than read off the node, because the node also carries
	# whatever `Gaze` swept the neck to last tick and a look is not a movement.
	var swung: Vector2 = a.plan(a.head_index()) - head_was

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
	var carry: Vector2 = impetus.velocity * delta
	creature.head_pos = pivot \
		+ (creature.head_pos + swung - pivot).rotated(dtheta) + carry
	a.rotate_followers(pivot, dtheta * maxf(stand_share, pushed))
	# ...and going backwards the whole animal goes with it.
	if pushed > 0.0:
		a.shift(carry * pushed)

	# ...and the lean the support will be asked to express: the true pendulum
	# term — delivered thrust over gravity at the weight's own height — with
	# the sign that puts the feet behind the push.
	var high: float = creature.poise.height if creature.poise.posed else 30.0
	lean = (-impetus.thrust / Gravity.PULL * high * LEAN_SHARE) \
		.limit_length(LEAN_MAX)

	# The spine's share of the stride, measured off the gait it is carrying:
	# the back rounds as the hind pair swings under the body (the gather) and
	# extends as the planted hinds drive (the thrust against its own ceiling),
	# scaled by how developed the bound is — a walking back stays quiet. Set
	# here, before the plan solve, so the rests the solver satisfies this tick
	# are the rests the body is claiming this tick; the measurements are last
	# tick's feet and press, which is the loop's ordinary one-frame lag. The
	# crouch keeps its own claim on the arch: a charge and a landing still
	# sink and round the same body.
	var gather_now: float = footwork.gather_of(false) * rhythm.bound
	var drive_now: float = 0.0
	if impetus.ceiling > 1.0:
		drive_now = clampf(impetus.thrust.length() / impetus.ceiling, 0.0, 1.0) \
			* rhythm.bound * (1.0 - gather_now)
	_gather = lerpf(_gather, gather_now, 1.0 - exp(-SPINE_EASE * delta))
	_drive = lerpf(_drive, drive_now, 1.0 - exp(-SPINE_EASE * delta))
	a.arch = maxf(crouch, _gather)
	a.bunch(BUNCH_FLEX * _gather - BUNCH_EXT * _drive)
	# ...and the tail streams out with the pace instead of hanging at its rest
	# droop — the counterweight carried, not a pose.
	a.tail_stream = clampf(creature.speed_norm * 0.7 + rhythm.bound * 0.3,
		0.0, 1.0)

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
	creature.press_out(push)
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
	spin(clampf(torque * impact / maxf(lever.length_squared(), 1.0),
		-GLANCE_MAX, GLANCE_MAX))
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
	# The pitch axis balances against the same feet measured the other way, and
	# fights back with the girdles' own spacing for a base — which is why a
	# quadruped nods where it would have rolled, and nothing was told.
	var stride_base: float = maxf(p.girdle_x.x - p.girdle_x.y, 1.0) * 0.5
	# A live downed body gets its limbs handed to the keel as righting: what is
	# left of them pressing the ground, under the same clamped-muscle law as
	# standing balance. A corpse hands over nothing and lies as it fell.
	var right: float = 0.0
	if a.collapsed and creature.alive and _down == Down.RIGHTING:
		right = _limb_press()
	keel.tick(delta,
		p.flanks(_lateral()) if footed else Vector2.ZERO,
		p.saddles(Vector2.RIGHT.rotated(creature.heading)) if footed else Vector2.ZERO,
		p.height if footed else 0.0,
		_stance_hold(footwork.planted(), count) if footed else 0.0,
		(a.fore_half + a.hind_half) * 0.5, stride_base,
		impetus.power, a.collapsed, right)
	a.roll = keel.roll
	a.pitch = keel.pitch


## The most the front of this animal may be steered ahead of its own hips,
## radians — the working range of the back, which is a share of what the joints
## would physically allow (`STEER_BEND`) scaled by how much of its turning this
## species does with its spine at all. A stiff-backed animal steers with its
## feet, a supple one folds into the turn, and neither number was authored for
## the species.
func _steer_lead(a: Armature) -> float:
	return maxf(a.back_sweep() * STEER_BEND * creature.body.spine_freedom, 0.0001)


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
		# A leap's feet were gathered toward the landing and all arrive with
		# the body; a stride flight's are each on their own beat, and only the
		# ones far enough through come down — the gallop lands staggered.
		footwork.touchdown(0.5 if _stride_flight else 0.0)
		_absorb = maxf(_absorb, clampf(a.fall.impact / ABSORB_SCALE, 0.0, 0.8))
		# The feet have the body again: from here the carries quote them, so
		# the fall's frame is spent — the arc is over, whatever ground it ended
		# on, and the legs absorb the rest. Also why a body never bounces: it
		# is meat with knees, not rubber.
		a.fall.absorb_landing(0.0)
		_stride_flight = false
	footwork.tick(delta, creature, impetus.velocity, lean, crouch,
		creature.speed_norm, a.fall.is_airborne(), _stride_flight)

	# A swing that completed mid-flight has caught the body: the suspension is
	# over the moment a foot is under the weight again, not when the arc says —
	# the forefoot catching the gallop is exactly this line.
	if _stride_flight and footwork.stride_landed:
		_absorb = maxf(_absorb, clampf(absf(a.fall.rate) / ABSORB_SCALE, 0.0, 0.5))
		a.fall.absorb_landing(0.0)
		_stride_flight = false

	# The bound's take-off. At the gathered beat the last foot leaves while
	# others are still mid-swing, and a body whose whole support is in the air
	# is in the air: it is committed to a flight exactly as long as its own
	# next landing — a measured time, the first swing to arrive — and the hop
	# that spans it is priced by ballistics and capped by what the hind girdle
	# has left. Below the bound this never fires, and a walk's stumble stays a
	# stumble on the ground.
	if not a.fall.is_airborne() and not _stride_flight \
			and footwork.planted() == 0 and rhythm.bound > BOUND_FLOOR:
		var t_need: float = footwork.first_landing_in()
		if t_need > 0.02 and t_need < 0.6:
			var hind: float = creature.corpus.girdle_soundness(false)
			var rate: float = minf(0.5 * Gravity.PULL * t_need,
				Gravity.launch_rate(JUMP_PEAK * BOUND_PEAK_SHARE
					* impetus.power * hind))
			a.launch(rate)
			_stride_flight = true



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
	if a.collapsed:
		_debt = 0.0
		_wobble = 0.0
		_recover(delta)
		return
	if a.fall.is_airborne():
		_debt = 0.0
		_wobble = 0.0
		return
	var p: Poise = creature.poise

	# A body still pushing itself up is not reviewed as a stance: its carries
	# are wherever the rise has them and its legs are folded under it. The
	# push-up itself is priced here — the census's engine and what is left of
	# the limbs, so a heavy or half-chewed body genuinely takes longer — and a
	# shove mid-rise meets a body with almost nothing in hand, which is what a
	# get-up being a vulnerable moment means.
	if _down == Down.RISING:
		_rise = minf(_rise + delta * RISE_RATE
			* clampf(impetus.power * _limb_press(), 0.1, 2.0), 1.0)
		footwork.rise = _rise
		if _rise >= 1.0:
			_down = Down.UP
		elif _rise < 0.6:
			return

	# A grounded body with no planted feet at all is not "free of deficit" —
	# it is a body whose every foot has been torn off its footing (a cliff
	# edge, a floor that vanished), and it gets the fall's own patience, not
	# the wobble's benefit of the doubt.
	if p.posed and p.feet == 0:
		_debt += delta
		if _debt > FALL_PATIENCE:
			_fell(a)
		return

	# The commitment, derived, per axis: a body is past saving when the pivot
	# a rescue step could still build — the farthest print the legs can reach,
	# plus the base the body already stands on — can no longer stand under the
	# weight at this angle, and the muscle holding it is already outmatched and
	# still losing. `tan θ` of the un-heeled weight height against that reach
	# is the whole test; nobody authors the angle, and it moves with the body's
	# own legs, stance and wounds. Keel's caps are only the backstops.
	var reachable: float = creature.attitude.active.plan_reach(
		creature.body.hind_leg_length)
	var half_base: float = (a.fore_half + a.hind_half) * 0.5
	var stride_base: float = maxf(p.girdle_x.x - p.girdle_x.y, 1.0) * 0.5
	var h0: float = p.height / maxf(cos(keel.roll), 0.2)
	var gone_roll: bool = keel.strained and keel.spill > 0.0 \
		and keel.rate * keel.side > 0.0 \
		and tan(absf(keel.roll)) > (reachable + half_base) / maxf(h0, 1.0)
	var h0p: float = p.height / maxf(cos(keel.pitch), 0.2)
	var gone_pitch: bool = keel.tilt_strained and keel.tilt_spill > 0.0 \
		and keel.pitch_rate * keel.tilt_side > 0.0 \
		and tan(absf(keel.pitch)) > (reachable + stride_base) / maxf(h0p, 1.0)
	if gone_roll or gone_pitch or keel.going_over() or keel.pitching_over():
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
		if p.overhang.length() > reachable * FALL_SHARE:
			_debt += delta
			if _debt > FALL_PATIENCE:
				_fell(a)
			return
	elif not keel.strained and not keel.tilt_strained:
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
	# The two axes ask as one: the weight is only ever going over in one
	# combined direction, and two rescues marking two different feet in the
	# same tick was a body lifting the support it was rescuing. The heel's
	# share is across the body, the nod's along it, and the step goes where
	# their sum says.
	var spill_out: Vector2 = Vector2.ZERO
	if keel.strained and keel.side != 0.0:
		spill_out += _lateral() * (keel.side * maxf(keel.spill, p.pad))
	if keel.tilt_strained and keel.tilt_side != 0.0:
		spill_out += Vector2.RIGHT.rotated(creature.heading) \
			* (keel.tilt_side * maxf(keel.tilt_spill, p.pad))
	if spill_out != Vector2.ZERO and p.posed:
		footwork.rescue(p.centre, spill_out)
	_debt = maxf(_debt - 2.0 * delta, 0.0)


## What is left of the limbs, as a share — the census's soundness times the
## nerves still asking, averaged over the four. What a get-up pushes with.
func _limb_press() -> float:
	var a: Armature = creature.armature
	var sum: float = 0.0
	for limb in a.limbs:
		sum += creature.corpus.soundness(limb.name) \
			* creature.vitals.numbness(limb.name)
	return sum / maxf(float(a.limbs.size()), 1.0)


## A downed body coming back — or not. The topple runs itself out on Keel's own
## physics, the body takes a beat, rolls sternal on what its limbs can press
## (`tip` hands the keel that strength while the state says RIGHTING), and
## pushes up through `RISING`. A corpse never leaves TOPPLING: recovery is a
## property of being alive, not of the pose.
func _recover(delta: float) -> void:
	if not creature.alive:
		_down = Down.TOPPLING
		_rise = 0.0
		return
	match _down:
		Down.UP:
			# Downed from outside the review — a scenario's K, a probe: adopt it.
			_down = Down.TOPPLING
		Down.TOPPLING:
			# Settled means the whole tumble is over: the heel has stopped
			# running out *and* the drop underneath it has finished arriving —
			# a body knocked off a ledge does not start gathering itself in
			# mid-air.
			if absf(keel.rate) < 0.15 and not creature.armature.fall.is_airborne():
				_down = Down.SETTLED
				_down_wait = REGATHER
		Down.SETTLED:
			_down_wait -= delta
			if _down_wait <= 0.0:
				_down = Down.RIGHTING
		Down.RIGHTING:
			# Keel is being handed the limbs' press (see `tip`); the body is
			# sternal when the heel is nearly out, and only then can legs be
			# legs again. A body whose righting cannot beat its own flank's
			# settle simply stays here, working — which is what a downed animal
			# that cannot rise looks like.
			if absf(keel.roll) < STERNAL:
				_arise()
		Down.RISING:
			# Handled in the grounded review; reaching here means the body
			# collapsed again mid-rise and starts over.
			_down = Down.TOPPLING
			_rise = 0.0


## Sternal to standing: the armature is un-collapsed where it lies, the feet
## re-adopt under the body, and the push-up begins — the carries travel from
## chest height to stance height through `Footwork.rise`, not by teleport. The
## body stands up facing the way its shoulders actually lie: the fall owned the
## heading while it was down.
func _arise() -> void:
	var a: Armature = creature.armature
	a.revive()
	_rise = 0.0
	footwork.rise = 0.0
	creature.heading = a.fwd[a.withers_index()].angle()
	_asked = 0.0
	_spin = 0.0
	creature.ang_vel = 0.0
	footwork.build(creature, outlook, rhythm)
	creature.head_pos = a.plan(a.head_index())
	a.take_head(creature.head_pos)
	_down = Down.RISING


## The loop, written down — the last thing the tick does, and the only thing in
## this file that changes nothing.
##
## One seam and one assembler, for the reason every other publication in v2 has
## one: a panel that reached into `Footwork` for a drift and `Keel` for a heel
## would be holding four opinions about a body that has one, and the first of
## them to be re-derived a tick late would be the one that looked like a bug in
## the mover. `Travel` already writes the motion seam the game reads; this is the
## same seam asked for everything the loop decided rather than only for what it
## delivered. Free while nothing is watching — see `MotionReadout.watching`.
func observe(delta: float) -> void:
	if not readout.watching:
		return
	readout.gather(delta, creature, self, _state_word())


## What the loop is doing, in one word, from the loop's own state. The order is a
## precedence: what has happened to the body outranks what it was trying to do.
func _state_word() -> StringName:
	var a: Armature = creature.armature
	if a.collapsed:
		if not creature.alive:
			return &"COLLAPSED"
		return &"RIGHTING" if _down == Down.RIGHTING else &"DOWNED"
	if _down == Down.RISING:
		return &"RISING"
	if a.fall.is_airborne():
		return &"BOUNDING" if _stride_flight else &"AIRBORNE"
	if creature.poise.posed and creature.poise.feet == 0:
		return &"FALLING"
	if _wobble >= WOBBLE_PATIENCE or keel.strained or keel.tilt_strained:
		return &"RESCUE"
	if headroom <= 0.0 and absf(creature.command.throttle) > 0.01:
		return &"BALKED"
	if footwork.planted() < footwork.feet.size():
		return &"STEPPING"
	return &"STANDING"


## The body goes down, however it got there. The same *pose* a death is — limp
## limbs, the trunk dropped, the constraints loosened — and emphatically not a
## death: falling over is something that happens to a living animal, and the
## review picks the body back up through `_recover`. Keel keeps whatever heel
## and rate it arrived with and integrates them out, so a creature knocked over
## finishes rolling onto that flank with the momentum it was given, and the
## plan momentum it fell with slides out through the ground (`steer`). Nothing
## is halted and nothing is killed: the ground does not care why a body
## arrives, and the body does not stop being alive by arriving.
func _fell(a: Armature) -> void:
	a.collapse()
	_down = Down.TOPPLING
	_rise = 0.0
	footwork.rise = 1.0


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


## An external twist, arriving as the turn rate it caused — the rotational half
## of Impetus.shove, for charges and glancing blows.
##
## Booked against `_spin` rather than against the animal's own turn, so the body
## sheds it at the brace rate while whatever the hand is asking for goes on being
## asked for underneath. Added to the published rate on the spot, because the
## contact stages run after the heading has been integrated and a blow that
## waited a tick to be felt would be a blow the body walked through.
func spin(dw: float) -> void:
	_spin += dw
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
	# One decomposition: the across-the-body half of the push rolls the animal
	# and the down-its-length half pitches it, each about the same axis with
	# the same lever. A ram taken square on the chest rears the body exactly as
	# the flattened seam could not say.
	keel.strike(dv.dot(_lateral()), at.z - axis, high,
		dv.dot(Vector2.RIGHT.rotated(creature.heading)))


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
		_asked = 0.0
		_spin = 0.0
		creature.ang_vel = 0.0
		creature.speed = 0.0
		creature.speed_norm = 0.0
	creature.move_dir = impetus.velocity / creature.speed \
		if creature.speed > 5.0 else dir
