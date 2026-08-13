## The legs supporting and rebalancing the body — the support half of the
## locomotion loop.
##
## Nothing in this file drives the creature forward. The body has already
## moved (Impetus integrated the velocity, the chain followed its head), and
## what is left is the leg's whole job: keep the weight held up from wherever
## the feet actually are, and reorganise the feet when the body's motion has
## used up the support they were giving. So each foot is one of two things:
##
##   * **planted** — a world-fixed anchor. It does not move, whatever the body
##     does over it; that is what a foot on the ground is, and it is why
##     planted feet can never creep. What changes is the *relationship*: the
##     socket travels with the body, the foot's comfortable spot (its "home")
##     travels with the socket, and the drift between home and anchor is the
##     measurement everything else reads.
##   * **swinging** — an arc from where it lifted to a landing predicted from
##     the body's own velocity: where the home will be when the swing ends,
##     plus the stride lead, on whatever surface Outlook says is actually
##     there. The prediction is re-taken every tick, so a turning body lands
##     its feet where it is now going, not where it was going when they lifted.
##
## Steps are *triggered by need* — drift past a share of the limb's own
## fore-aft excursion (Carriage's projection, so anatomy is the constraint),
## the ground gone from under an anchor, or a balance rescue — and *granted by
## Rhythm*, which owns coordination and nothing else. Which is the design's
## split: need is shared physics, company is the gait.
##
## The girdle carries are measured here, off the planted anchors: each girdle
## rides at its own feet's ground plus the stance clearance, so a foot set
## down on a ledge raises that end of the body with no ledge-case anywhere.
## And the press the feet have left — `grip` — is measured here and read by
## Impetus, so propulsion and support cannot be two opinions about the feet.
class_name Footwork
extends RefCounted

## Share of a limb's fore-aft excursion the drift may spend before the foot
## must ask to step. What is left past the trigger is the margin desperate
## steps and prediction error live in.
##
## This is one of the two numbers a stride length is made of and the only one
## that is not anatomy. A foot lifts about `TRIGGER` of its excursion behind its
## home and lands at the far edge of that same excursion, so a step covers about
## `(1 + TRIGGER)` of the disc — and how often the animal takes one is that
## divided into how fast it is going. At 0.60 the cat covered the ground of a
## walk in the steps of a trot; the extra fifth here is a longer, more deliberate
## step for exactly the same ground, which is the difference between a body
## walking and a body scurrying. It is not free — what is left over is the room a
## desperate step and a mispredicted landing have to live in — so it stops well
## short of the 1.0 that would leave the leg trailing at full stretch with
## nothing in reserve at all.
const TRIGGER: float = 0.78

## Swing speed, in limb lengths per second at the twitch datum. The one
## tempo scale: a longer leg swings a longer arc in the same time, a
## fast-twitch body sweeps quicker, and the tendon lever gears it (a tendon
## inserted close to the joint trades press for sweep — Carriage.Joint.gear).
##
## 5.5 was a leg sweeping five and a half of its own lengths every second, which
## is faster than any of these legs ever has to move: priced against the strides
## this anatomy actually takes it made every swing come out under the floor
## below, so the scale decided nothing, the *clamp* decided everything, and every
## step of every gait was the same 100 ms flick — a foot that teleports and a
## body that reads as sped-up film. At 2.4 the arithmetic is live again: a stroll
## swings in about three tenths of a second, a sprint in a fifth, and the
## difference between them is the pace rather than a constant.
##
## It is also the floor of what the legs can be asked to keep up with. A swing is
## time a foot is not supporting anything, so the duty factor is what is left of
## the cycle after it — set the sweep much slower than this and a sprinting body
## has three feet in the air at once, no grip to press with, and comes to a dead
## stop while its legs windmill. The cat's fore leg is the binding one: it is
## shorter than the hind and geared level with the reference tendon, so it sweeps
## the same stride the slowest, and this is the rate at which *it* still lands in
## time.
const SWING_RATE: float = 2.4
const TWITCH_FLOOR: float = 0.6
const TWITCH_SPAN: float = 0.8

## A swing is never over before or after these, seconds — the floor is the
## fast-twitch law's old truth (limbs stop blurring), the ceiling is a limp
## being a limp rather than a step.
const SWING_MIN: float = 0.14
const SWING_MAX: float = 0.50

## Step clearance at a walk, px, scaled by the stance's own step-height
## leaning and by pace. A climb adds its own rise on top.
const STEP_H: float = 3.0

## How far ahead of its landing home a foot is set down, as a share of the
## stride it is about to be walked over (spec.foot_lead scales it).
## The landing prediction, not a drive: the body travels over the foot.
const RETARGET: float = 10.0

## Share of the excursion a rescue step spends reaching toward the spill.
const RESCUE_REACH: float = 0.9

## The lateral-sequence seed, per foot in armature order (FL, FR, HL, HR):
## how far behind its own rhythm each anchor starts, as a phase. Only read at
## adoption — the walk keeps its own time from the first stride on.
const SEED_PHASE: Array[float] = [0.25, 0.75, 0.0, 0.5]
const SEED_SHARE: float = 0.35

## How far the surface under a planted anchor may move from what the foot
## stood down on before the foot must re-find its footing — the world changing
## under a foot is an emergency the gait may not deny, because the support the
## body is counting on is no longer the support that is there.
const GROUND_SHIFT: float = 2.0

## The anticipation: how much of a measured rise on the strip a girdle is about
## to cross its carry pre-lifts by, and the most it may pre-lift — the body
## starts carrying itself higher *before* the feet get there, so a step is
## approached on a smooth trajectory rather than hit as a jolt. Capped well
## inside the legs' extension margin: an anticipating body must still reach
## the ground it is actually standing on.
const ANTICIPATE: float = 0.45
const ANTICIPATE_CAP: float = 4.0


## One foot: the world anchor, the swing, and the measurements between.
class Foot extends RefCounted:
	var limb: Armature.Chain
	var index: int = 0
	var fore: bool = true
	## World plan point the foot is standing on; meaningless while swinging.
	var anchor: Vector2 = Vector2.ZERO
	var anchor_z: float = 0.0
	## The surface height the foot stood down onto — what `anchor_z` is checked
	## against so a world moving under a planted foot is noticed.
	var stood_z: float = 0.0
	var swinging: bool = false
	## Seconds into the current swing, against its length.
	var swing: float = 0.0
	var swing_time: float = 0.2
	var lift: Vector3 = Vector3.ZERO
	var land: Vector3 = Vector3.ZERO
	## Seconds since it last landed.
	var since: float = 10.0
	## Drift in trigger units — ≥ 1.0 is a request to step.
	var urgency: float = 0.0
	## A standing balance demand: where the next step must land, or INF for
	## none. Set by `rescue`, spent by the next lift.
	var rescue_at: Vector2 = Vector2.INF


## Per-girdle geometry re-measured each tick off the active carriage — the
## anatomy the steps are constrained by.
class Span extends RefCounted:
	## Fore-aft excursion radius of the pair's foot, px.
	var excursion: float = 10.0
	## What the pair holds its girdle at above its feet, px.
	var clearance: float = 20.0
	## Swing speed, px/s.
	var sweep: float = 200.0
	## The pair's share of the body's press, per foot.
	var press: float = 0.25


var feet: Array[Foot] = []
## How much press the planted feet have left, 0..1 — Impetus's ground term.
## 1.0 standing square and fresh; 0 airborne or with everything trailing.
var grip: float = 1.0

var _fore: Span = Span.new()
var _hind: Span = Span.new()
## Last ground each girdle's feet were known to stand on — carries hold this
## through moments with the whole pair in the air.
var _fore_ground: float = 0.0
var _hind_ground: float = 0.0

var _outlook: Outlook
var _rhythm: Rhythm


## Adopts the armature's limbs, planted exactly where the layout stood them,
## with the lateral-sequence seed staggering their rhythm.
func build(creature: Creature2, outlook: Outlook, rhythm: Rhythm) -> void:
	_outlook = outlook
	_rhythm = rhythm
	feet.clear()
	var a: Armature = creature.armature
	var dir: Vector2 = creature.move_dir
	_measure(creature)
	for i in a.limbs.size():
		var limb: Armature.Chain = a.limbs[i]
		var f := Foot.new()
		f.limb = limb
		f.index = i
		f.fore = limb.parent_node != a.pelvis_index()
		var toe: Vector3 = a.pos[limb.nodes[limb.nodes.size() - 1]]
		var reach: Span = _fore if f.fore else _hind
		var phase: float = SEED_PHASE[i] if i < SEED_PHASE.size() else 0.0
		f.anchor = Vector2(toe.x, toe.y) \
			+ dir * ((phase - 0.5) * SEED_SHARE * reach.excursion)
		f.anchor_z = _outlook.surface(f.anchor)
		f.stood_z = f.anchor_z
		f.swinging = false
		f.since = 10.0
		feet.append(f)
	grip = 1.0
	_fore_ground = 0.0
	_hind_ground = 0.0
	_write(creature)
	# The carries are a measurement of the feet from the moment the feet are
	# adopted — a body standing on a table is standing on the table on its
	# first tick, not after one, or the contact stage would find its trunk
	# inside the solid it is standing on and press it off.
	_carry(creature, 0.0, Vector2.ZERO, false)


## One tick of support: measure every drift, ask Rhythm who may step, swing
## what is swinging, and hand the armature its feet and its carries.
##
## `lean` is the body-shift term — the homes are displaced by it, so an
## accelerating body's support genuinely trails its weight and the animal
## leans into its own thrust. `crouch` sinks the carries (a charge, a landing
## absorb). Order matters and is the loop's: the body has already moved this
## tick; the feet are answering it.
func tick(delta: float, creature: Creature2, velocity: Vector2, lean: Vector2,
		crouch: float, pace: float, airborne: bool) -> void:
	var a: Armature = creature.armature
	_measure(creature)

	for f in feet:
		f.since += delta

	if airborne:
		_float_feet(creature, velocity)
		grip = 0.0
		_write(creature)
		_carry(creature, crouch, velocity, true)
		return

	# The measurements: where each planted foot stands against where its body
	# now wants it.
	var urgency := PackedFloat32Array()
	var swinging := PackedByteArray()
	var since := PackedFloat32Array()
	var travel_dir: Vector2 = velocity.normalized() \
		if velocity.length_squared() > 4.0 else Vector2.ZERO
	for f in feet:
		var reach: Span = _fore if f.fore else _hind
		if not f.swinging:
			f.anchor_z = _outlook.surface(f.anchor)
			# Torn off: a body dragged past what the limb can span from socket
			# to anchor has pulled the foot off its footing — the anchor is no
			# longer support, whatever the foot would prefer, and saying so is
			# what lets the review see a body going over an edge as one losing
			# its feet rather than as one mysteriously still standing.
			var seat: Vector3 = a.socket_of(f.limb)
			var span: Vector2 = f.anchor - Vector2(seat.x, seat.y)
			var rise: float = seat.z - f.anchor_z
			var held: float = sqrt(span.length_squared() + rise * rise)
			if held > creature.body.limb_length(f.fore) * 1.05:
				f.urgency = Rhythm.DESPERATE
				_lift(a, f, velocity, lean, pace)
		if f.swinging:
			f.urgency = 0.0
		else:
			var drift: Vector2 = _home(a, f, lean) - f.anchor
			# Support is only being used up where the home is leaving the anchor
			# behind — along the travel, or sideways out of the disc. A foot
			# standing *ahead* of its home is support the body is about to walk
			# over, and asking it to step is what turned a walk into a scramble.
			var need: float = drift.length()
			if travel_dir != Vector2.ZERO:
				var along: float = maxf(drift.dot(travel_dir), 0.0)
				var lat: float = drift.dot(Vector2(-travel_dir.y, travel_dir.x))
				need = Vector2(along, lat).length()
			f.urgency = need / maxf(TRIGGER * reach.excursion, 0.001)
			if absf(f.anchor_z - f.stood_z) > GROUND_SHIFT:
				# The world moved under the anchor — the ground gone from under a
				# foot (or risen through it) is a step nothing may deny.
				f.urgency = maxf(f.urgency, Rhythm.DESPERATE)
			if f.rescue_at.x < INF:
				f.urgency = maxf(f.urgency, Rhythm.DESPERATE)
		urgency.append(f.urgency)
		swinging.append(1 if f.swinging else 0)
		since.append(f.since)

	# The gait: who steps, in what company.
	var granted: PackedInt32Array = _rhythm.choose(urgency, swinging, since,
		pace, creature.body.beat_coupling)
	for i in granted:
		_lift(a, feet[i], velocity, lean, pace)

	# The swings, each re-aimed at where its landing has moved to.
	for f in feet:
		if not f.swinging:
			continue
		f.swing += delta
		var fresh: Vector3 = _predict(a, f, velocity, lean,
			maxf(f.swing_time - f.swing, 0.0))
		f.land = f.land.lerp(fresh, 1.0 - exp(-RETARGET * delta))
		if f.swing >= f.swing_time:
			_plant(f)

	_press(creature)
	_write(creature)
	_carry(creature, crouch, velocity, false)


## The armature has just been carried — copy each socket's solved height onto
## its limb, so the leg is solved from where the body actually holds it. The
## socket's own height, not the girdle's: on a heeled body they are not the same
## number, and it is the difference between them that folds one leg up and
## stretches the other off the ground.
func perch(a: Armature) -> void:
	for f in feet:
		f.limb.socket_rise = a.socket_of(f.limb).z


## A balance demand from the review: the weight is going over the edge in
## `overhang`'s direction, and the support has to follow it.
##
## If feet are already in the air, the nearest swing is *steered* toward the
## spill — lifting more support to save the support is how a stumble was
## making its own emergency worse. Only a body with its feet down answers by
## lifting one: the planted foot nearest the spill, marked as a request
## nothing may deny (the step itself still goes through Rhythm).
func rescue(centre: Vector2, overhang: Vector2) -> void:
	if overhang.length_squared() < 0.0001:
		return
	var dir: Vector2 = overhang.normalized()
	var best: Foot = null
	var best_side: float = -INF
	var airborne_feet: int = 0
	for f in feet:
		if f.swinging:
			airborne_feet += 1
	var steer: bool = airborne_feet >= 1
	for f in feet:
		if f.swinging != steer or f.rescue_at.x < INF:
			continue
		var side: float = (f.anchor - centre).dot(dir) if not steer \
			else (Vector2(f.land.x, f.land.y) - centre).dot(dir)
		if side > best_side:
			best_side = side
			best = f
	if best == null:
		return
	var reach: Span = _fore if best.fore else _hind
	best.rescue_at = centre + dir * (overhang.length()
		+ RESCUE_REACH * reach.excursion * 0.5)


## The balance has recovered — standing demands not yet spent are dropped, so
## a stale emergency cannot keep churning feet the body no longer needs moved.
func calm() -> void:
	for f in feet:
		if not f.swinging:
			f.rescue_at = Vector2.INF


## Every swinging foot comes down where it was aimed — what a landing body
## does with the legs it was holding ready.
func touchdown() -> void:
	for f in feet:
		if f.swinging:
			_plant(f)


func planted() -> int:
	var count: int = 0
	for f in feet:
		if not f.swinging:
			count += 1
	return count


# ------------------------------------------------------------- the stages ----

## A foot leaves the ground: remember where it was, aim it at where its
## support will be needed, and price the swing off the limb's own tempo.
func _lift(a: Armature, f: Foot, velocity: Vector2, lean: Vector2,
		pace: float) -> void:
	var reach: Span = _fore if f.fore else _hind
	f.swinging = true
	f.swing = 0.0
	f.lift = Vector3(f.anchor.x, f.anchor.y, f.anchor_z)

	# First guess at the swing time from the drift it has to cover; the arc is
	# re-priced once the landing is known.
	var guess: float = clampf(f.urgency * TRIGGER * reach.excursion / reach.sweep,
		SWING_MIN, SWING_MAX)
	f.land = _predict(a, f, velocity, lean, guess)
	var arc: float = Vector2(f.land.x - f.lift.x, f.land.y - f.lift.y).length() \
		+ absf(f.land.z - f.lift.z)
	# A quicker beat at pace — the same leg sweeps the same arc harder — but
	# never under the twitch's own floor: limbs do not blur.
	var haste: float = 1.0 + 0.6 * clampf(pace, 0.0, 1.5)
	f.swing_time = clampf(arc / maxf(reach.sweep * haste, 1.0),
		SWING_MIN, SWING_MAX)


## Where this foot should land: its home carried forward by the body's own
## velocity over the rest of the swing, led by the stride share, capped to
## the limb's reach, and placed on the surface that is actually there.
func _predict(a: Armature, f: Foot, velocity: Vector2, lean: Vector2,
		left: float) -> Vector3:
	var reach: Span = _fore if f.fore else _hind
	var socket: Vector2 = _socket(a, f)
	var home_then: Vector2 = _home(a, f, lean) + velocity * left
	var spec: BodySpec = a.spec
	var lead: float = spec.foot_lead * 2.0 * TRIGGER * reach.excursion
	var dir: Vector2 = velocity.normalized() if velocity.length_squared() > 1.0 \
		else Vector2.ZERO
	var plan: Vector2 = home_then + dir * lead
	if f.rescue_at.x < INF:
		plan = f.rescue_at
	# Anatomy last: a foot cannot land past its own excursion.
	var socket_then: Vector2 = socket + velocity * left
	var out: Vector2 = plan - socket_then
	if out.length() > reach.excursion:
		plan = socket_then + out.normalized() * reach.excursion
	# ...and the world answers with the surface the landing is actually on.
	var leg: float = spec.limb_length(f.fore)
	return _outlook.reach_along(Vector2(f.lift.x, f.lift.y), plan, f.lift.z, leg)


func _plant(f: Foot) -> void:
	f.swinging = false
	f.anchor = Vector2(f.land.x, f.land.y)
	f.anchor_z = _outlook.surface(f.anchor)
	f.stood_z = f.anchor_z
	f.since = 0.0
	f.rescue_at = Vector2.INF


## Airborne, the legs gather toward where the body will need them — swings
## aimed at the landing homes, never planted until the body is down.
func _float_feet(creature: Creature2, velocity: Vector2) -> void:
	var a: Armature = creature.armature
	var t_air: float = maxf(Gravity.fall_time(a.fall.height, a.fall.rate,
		a.fall.floor_height), 0.05)
	for f in feet:
		if not f.swinging:
			f.swinging = true
			f.swing = 0.0
			var from: Vector3 = a.pos[f.limb.nodes[f.limb.nodes.size() - 1]]
			f.lift = from
		f.swing = minf(f.swing, f.swing_time * 0.6)
		var plan: Vector2 = _home(a, f, Vector2.ZERO) + velocity * t_air
		f.land = Vector3(plan.x, plan.y, _outlook.surface(plan))
		f.swing_time = maxf(t_air, 0.15)


# ------------------------------------------------------- the measurements ----

## The pair geometry off the active carriage: what the anatomy currently
## constrains a step to. Re-taken every tick because the stance blends.
func _measure(creature: Creature2) -> void:
	var spec: BodySpec = creature.body
	var carriage: Carriage = creature.attitude.active
	var c: Dictionary = creature.corpus.compartments()
	var fore_pair: float = float(c.get(&"fore_girdle", 1.0)) \
		* carriage.fore.advantage
	var hind_pair: float = float(c.get(&"hind_girdle", 1.0)) \
		* carriage.hind.advantage
	var total: float = maxf(fore_pair + hind_pair, 0.0001)
	for fore in [true, false]:
		var reach: Span = _fore if fore else _hind
		var joint: Carriage.Joint = carriage.of(fore)
		var leg: float = spec.limb_length(fore)
		reach.excursion = maxf(carriage.fore_aft_reach(leg, joint.stand,
			spec.stance_width), 2.0)
		reach.clearance = carriage.stance_clearance(leg, joint.stand,
			spec.stance_width,
			spec.front_foot_bias if fore else spec.rear_foot_bias)
		reach.sweep = SWING_RATE * leg \
			* (TWITCH_FLOOR + TWITCH_SPAN * spec.fast_twitch) * joint.gear
		reach.press = (fore_pair if fore else hind_pair) / total


## Where the foot's socket is on the plan — the armature's own answer, not a
## second copy of the arithmetic, so a heeled body's shortened plan offset is
## here the moment it is there.
func _socket(a: Armature, f: Foot) -> Vector2:
	var seat: Vector3 = a.socket_of(f.limb)
	return Vector2(seat.x, seat.y)


## The foot's comfortable spot: out from its socket by the rest lead, shifted
## by the body's lean. Everything is measured against this point.
func _home(a: Armature, f: Foot, lean: Vector2) -> Vector2:
	var p: int = f.limb.parent_node
	return _socket(a, f) + a.fwd[p] * f.limb.foot_lead + lean


## How much press the planted feet have left, for Impetus: each foot counts
## its girdle's share, faded by how far it is already trailing its home (a
## leg near full extension behind has nothing left to push with) and by how
## much of its muscle is still answering.
func _press(creature: Creature2) -> void:
	var corpus: Corpus = creature.corpus
	var sum: float = 0.0
	for f in feet:
		if f.swinging:
			continue
		var reach: Span = _fore if f.fore else _hind
		var left: float = clampf(1.0 - maxf(f.urgency, 0.0) * TRIGGER, 0.0, 1.0)
		# Soundness is the muscle still answering; numbness is the nerve still
		# asking. A leg with either gone presses with that much less — a cut
		# sciatic takes its leg out of the engine without touching the flesh.
		sum += reach.press * left * corpus.soundness(f.limb.name) \
			* creature.vitals.numbness(f.limb.name)
	# Standing square and fresh, the four feet sum to two pair-shares — that
	# is the datum grip 1.0 is quoted against.
	grip = clampf(sum / 2.0, 0.0, 1.0)


## Hands the armature its feet: the world points, and whether each is
## bearing. The one writer of the limb seam.
func _write(creature: Creature2) -> void:
	var collapsed: bool = creature.armature.collapsed
	for f in feet:
		var limb: Armature.Chain = f.limb
		if collapsed:
			limb.foot_driven = false
			limb.grounded = false
			continue
		limb.foot_driven = true
		if f.swinging:
			var t: float = clampf(f.swing / maxf(f.swing_time, 0.001), 0.0, 1.0)
			var s: float = smoothstep(0.0, 1.0, t)
			var reach: Span = _fore if f.fore else _hind
			var carriage: Carriage = creature.attitude.active
			var rise: float = STEP_H * carriage.step_height_gain \
				* (0.6 + 0.8 * clampf(creature.speed_norm, 0.0, 1.5)) \
				+ maxf(f.land.z - f.lift.z, 0.0) * 0.35
			var plan: Vector2 = Vector2(f.lift.x, f.lift.y).lerp(
				Vector2(f.land.x, f.land.y), s)
			var z: float = lerpf(f.lift.z, f.land.z, s) + sin(t * PI) * rise
			limb.foot_target = Vector3(plan.x, plan.y, z)
			limb.grounded = false
		else:
			limb.foot_target = Vector3(f.anchor.x, f.anchor.y, f.anchor_z)
			limb.grounded = true


## The carries: each girdle rides at its own feet's ground plus the stance
## clearance, sunk by the crouch and pre-lifted toward whatever rise its own
## strip of path is about to cross — the body's trajectory anticipates the
## step instead of being jolted by it, and the feet then land on ground the
## body is already carrying itself toward. A pair entirely in the air keeps
## the last ground it stood on — the body does not guess at a floor its feet
## have not touched.
func _carry(creature: Creature2, crouch: float, velocity: Vector2,
		airborne: bool) -> void:
	var a: Armature = creature.armature
	for fore in [true, false]:
		var reach: Span = _fore if fore else _hind
		var ground: float = 0.0
		var down: int = 0
		for f in feet:
			if f.fore != fore or f.swinging:
				continue
			ground += f.anchor_z
			down += 1
		if down > 0:
			ground /= float(down)
			if fore:
				_fore_ground = ground
			else:
				_hind_ground = ground
		else:
			ground = _fore_ground if fore else _hind_ground
		var carry: float = ground + reach.clearance * (1.0 - 0.4 * clampf(crouch, 0.0, 1.0))
		if not airborne:
			# The anticipation, measured from the girdle itself: what rises on
			# the strip *this* end of the body is about to cross, so the fore
			# quarters lift for a step the hind quarters have not reached yet.
			var girdle: Vector2 = a.plan(a.withers_index() if fore else a.pelvis_index())
			var coming: float = _outlook.rise_ahead(girdle,
				velocity * Outlook.HORIZON, ground)
			carry += clampf(coming * ANTICIPATE, 0.0, ANTICIPATE_CAP)
		if fore:
			a.fore_carry = carry
		else:
			a.hind_carry = carry


## The ground frame the carries are quoting: what the planted (or last
## planted) feet are standing on, averaged over the girdles. The fall's floor
## is measured against this while the body is airborne — the difference
## between the ground now under the body and the ground it took off from.
func frame_ground() -> float:
	return (_fore_ground + _hind_ground) * 0.5
