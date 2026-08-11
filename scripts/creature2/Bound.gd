## Whether this body can throw itself off the ground, how far, and what it does
## while it is doing so — the successor of v1's Leap and Jump in one file, because
## the capability and the arc are the same arithmetic read at two moments.
##
## Five laws do the whole of the capability, and every number is one of them
## applied to the body the census has just counted:
##
##   * **A jump is work against weight.** The apex is the work put in over what the
##     body weighs, and work is force times distance. The force is the muscle's per
##     unit of weight — `Locomotor.power`, the same ratio that makes a heavy animal
##     slow off the mark. The distance is how far the joints extend through. There
##     is no third term and no gain.
##   * **A body has to hold itself up first.** Of every unit of force the legs
##     produce, one body weight is spent standing there; what is left over
##     accelerates the animal upward. A build whose legs cannot push harder than it
##     weighs does not jump badly — it does not jump, and nothing had to say so.
##   * **Muscle is weaker the faster it shortens.** A leg thrown open in a tenth of
##     a second develops a fraction of what it could hold.
##   * **A store is only as good as the joint that spends it.** A limb with nowhere
##     to go returns nothing however much it holds, which is the quieter reason a
##     columnar animal stays on the floor. (v2 has no elastic store in the
##     authoring file yet; when tendon capacity is authored it is added here, and
##     nothing else changes.)
##   * **A push is taken about a pivot.** To drive with a girdle an animal has to
##     get its weight over it, and how far it can shift is set by what there is on
##     the other side to balance against — which is why the hind limbs propel,
##     rather than because of a rule about quadrupeds.
##
## The arc is three phases and one integrator. The legs gather, extend, and the
## body leaves the ground on `Armature.fall` — the world's only vertical
## integrator, exactly as a drop does. What the gait sees of it is a *load* on the
## joints, signed: positive folds toward a crouch, negative extends toward a push.
## That is the whole of why a take-off is visible before there is any elevation —
## the animal genuinely stands up on its legs first, as it would have to.
class_name Bound
extends RefCounted

## How many times its own weight a girdle of unit power pushes the ground with,
## through the whole of its extension. The one calibration constant in the file,
## and the only place the census's muscle is turned into a real acceleration:
## `power` is quoted against the reference build rather than in newtons, so
## something has to say what the reference build's legs can do. Sized on the
## default cat, whose power is 1.0 by construction — it clears about a hundred
## pixels from a full crouch, which is what the v1 oracle's cat cleared with its
## elastic store included. v2 has no store yet, so this stands in for it; when
## tendon capacity is authored, this comes back down and the store makes up the
## difference.
const PUSH_WEIGHTS: float = 13.1

## How much of that force survives being asked for quickly. A muscle shortening
## fast develops a fraction of what it develops holding still, and a push-off is the
## fastest thing a leg ever does.
const FAST_MUSCLE: float = 0.55

## What a girdle with half the body behind it to balance against is worth, so the
## share is a multiplier around one rather than a raw fraction of a body.
const BALANCE_GAIN: float = 2.0

## How long the animal takes to wind up, in swings of the limb doing the winding. A
## crouch is the same limb the gait swings, moved the same way by the same muscle
## against the same weight, so how long it takes is the pendulum arithmetic
## `Locomotor.swing_time` already does. There is no charge-rate parameter and there
## cannot be one.
const LOAD_SWINGS: float = 1.6
## And the weight shift ahead of it, and the extension itself. The last is the
## shortest of the three and still has to be long enough for the body to come up on
## the legs opening underneath it — a push-off is a creature standing up very fast.
const GATHER_SWINGS: float = 0.55
const THRUST_SWINGS: float = 0.80

## Least a body may push with and still be said to jump, as a share of the height it
## picks one foot up by. A comparison rather than a threshold anybody chose: if the
## whole animal cannot throw itself higher than it lifts a single foot to walk, what
## it has is not a jump, it is a step.
const JUMP_OVER_STEP: float = 1.0

## Least of a limb's fold that counts as working against the ground when it catches
## a landing — even a sprawled animal takes *something* out of an arrival.
const CATCH_FLOOR: float = 0.25

## Most any body of muscle gets out of one contraction, in pixels of apex. The one
## flat ceiling in the file and the least arbitrary thing in it: muscle does a
## roughly fixed amount of work per unit of its own mass, so work per unit of *body*
## weight — which is what an apex is — has a limit that does not care how large the
## animal is. Applied as a saturation rather than a clamp, because it is a property
## of the tissue: a body far under it is unaffected, one approaching it gets
## progressively less for each further unit of travel, and nothing is cut off.
const SPECIFIC_WORK: float = 320.0

## The phases of one jump.
enum { IDLE, GATHER, CHARGE, THRUST, FLIGHT }

# --- what this body can do about leaving the ground --------------------------

## Whether there is a jump here at all.
var capable: bool = false
## What each girdle contributes to the push, as shares summing to one.
var share: Vector2 = Vector2(0.0, 1.0)
## Apex of a fully charged standing jump, px — the headline number.
var full: float = 0.0
## The same before anything is wound: what a standing start with no crouch gets.
var bare: float = 0.0
var charge_time: float = 0.4
var gather_time: float = 0.15
var thrust_time: float = 0.1
## Fastest arrival each girdle can take out of a landing without being driven to its
## stops, px/s.
var absorb: Vector2 = Vector2(200.0, 200.0)
## How completely this build can throw itself, 0..1 — the reading Cadence needs to
## know whether an asymmetric gait is available at all. Saturating, because that
## question wants "can it leave the ground", not "how far".
var launch: float = 0.0

# --- and what it is doing about it right now ---------------------------------

var phase: int = IDLE
## How much of its store is wound, 0..1.
var charge: float = 0.0
## What the joints are being asked for, per girdle: positive folds toward a crouch,
## negative extends toward the lock. The gait spends this through the stance, which
## is the whole of how a crouch and a push-off reach the picture.
var load: Vector2 = Vector2.ZERO
## How fast whatever has hold of the legs is moving them, in response per second.
## Zero on a walking animal, which is the guarantee that nothing in the gait behaves
## differently for the existence of the jump.
var drive: float = 0.0
## The apex the take-off was actually taken at, kept for the readouts.
var took_off: float = 0.0

var _elapsed: float = 0.0
var _carriage: Carriage
var _loco: Locomotor
var _spec: BodySpec
var _vertical: float = 0.0
var _balance: Vector2 = Vector2(0.3, 0.6)


## Re-derives the capability from the body that has just been counted.
func update(carriage: Carriage, loco: Locomotor, corpus: Corpus, poise: Poise,
		spec: BodySpec, stand_height: float) -> void:
	if carriage == null or loco == null or corpus == null or spec == null:
		return
	_carriage = carriage
	_loco = loco
	_spec = spec

	# How much of a leg's extension goes upward. The stance again, taken straight: a
	# limb stacked under the shoulder pushes the body away from the floor and a limb
	# rowing out sideways pushes it along one. The same sine the clearance, the
	# stride and the footfall pattern are read off, so no part of the animal can
	# disagree with another about how it is standing.
	_vertical = clampf(sin(carriage.tilt), 0.0, 1.0)
	_balance = corpus.balance(poise.girdle_x.x, poise.girdle_x.y) * BALANCE_GAIN \
		if poise != null else Vector2(0.3, 0.6)

	var fore: float = _girdle(true, 1.0) if loco.forelimbs_bear else 0.0
	var hind: float = _girdle(false, 1.0)
	var total: float = fore + hind
	share = Vector2(fore, hind) / total if total > 0.0 else Vector2(0.0, 1.0)

	full = _ceiling(total)
	bare = _ceiling((_girdle(true, 0.0) if loco.forelimbs_bear else 0.0)
		+ _girdle(false, 0.0))

	var tall: float = maxf(stand_height, spec.hind_leg_length * 0.5)
	# Whether that is a jump: a body that cannot throw the whole of itself higher
	# than it picks up one foot has a step, and it already has one of those.
	capable = full > loco.lift(tall, maxf(spec.fore_leg_length,
		spec.hind_leg_length)) * JUMP_OVER_STEP

	# How long the whole of it takes. Every one of the three is the same pendulum
	# the gait swings a leg with, because that is what is happening: the limb that
	# folds to gather, holds to charge and opens to push is the limb the gait picks
	# up and puts down — through the same lever, which is why the gear rides along.
	var driving: bool = share.y < share.x
	var swing: float = loco.swing_time(
		spec.fore_leg_length if driving else spec.hind_leg_length,
		loco.joint(driving).gear)
	charge_time = maxf(swing * LOAD_SWINGS, 0.05)
	gather_time = maxf(swing * GATHER_SWINGS, 0.03)
	thrust_time = maxf(swing * THRUST_SWINGS, 0.02)

	# What a landing may be worth: the same arithmetic backwards. A limb takes work
	# out of a falling body over the distance it folds, at the force its muscle can
	# hold — which is why a joint that cannot fold cannot catch anything.
	absorb = Vector2(_catch(true), _catch(false))

	# And the saturating reading of the same fact, for the pattern.
	var tall_in: float = full / maxf(tall, 1.0) if capable else 0.0
	launch = tall_in / (tall_in + 1.0)


## What one girdle is worth at a given charge, in pixels of apex. The laws of the
## header in three lines: force per unit weight is the animal's own power, one
## weight of it is spent standing there, and what is left acts over however far the
## joint has to extend — then through however much of its own weight this girdle can
## get over itself to push with.
func _girdle(fore: bool, at_charge: float) -> float:
	var stroke: float = _stroke(fore, at_charge)
	if stroke <= 0.0:
		return 0.0
	var net: float = maxf(PUSH_WEIGHTS * _loco.power * FAST_MUSCLE - 1.0, 0.0)
	return net * stroke * _vertical * (_balance.x if fore else _balance.y)


## What a body of muscle actually gets away with — a saturation rather than a cap,
## so the ordering of every build is preserved while the difference between them
## narrows exactly where real muscle stops keeping up.
func _ceiling(raw: float) -> float:
	return raw / (1.0 + maxf(raw, 0.0) / SPECIFIC_WORK)


## How far this girdle's joints extend through, px, at a given charge. The distance
## in "force times distance", and the whole reason a jump is a question about
## articulation: the limb pushes from where it stands to where it locks out, and
## crouching first moves the near end down toward its own fold. Charge is not a
## power setting — it is literally how much travel the animal has bought itself.
func _stroke(fore: bool, at_charge: float) -> float:
	var joint: Carriage.Joint = _carriage.of(fore)
	var from: float = lerpf(joint.stand, joint.fold, clampf(at_charge, 0.0, 1.0))
	var bone: float = _spec.fore_leg_length if fore else _spec.hind_leg_length
	return maxf(joint.lock - from, 0.0) * bone


## How fast a body this girdle can catch, px/s. Work again: the force the limb holds
## against the floor over the distance it folds through is the energy it takes out of
## an arriving body. Quoted at the muscle's holding force rather than its shortening
## one, because a limb absorbing a landing is being *lengthened* under load, which is
## the one thing muscle does better than anything else.
func _catch(fore: bool) -> float:
	var joint: Carriage.Joint = _carriage.of(fore)
	var bone: float = _spec.fore_leg_length if fore else _spec.hind_leg_length
	var along: float = maxf(_vertical, CATCH_FLOOR)
	var fold: float = maxf(joint.stand - joint.fold, 0.0) * bone
	return sqrt(maxf(2.0 * PUSH_WEIGHTS * _loco.power * Gravity.PULL
		* along * fold * along, 0.0))


## Apex of a jump taken at this much charge, px. Interpolated between the two ends
## the update measured, because the ends are the expensive part and this is asked
## several times a tick by things that are not solving a body.
func peak(at_charge: float) -> float:
	if not capable:
		return 0.0
	return maxf(lerpf(bare, full, clampf(at_charge, 0.0, 1.0)), 0.0)


## How fast the body leaves the ground at that charge, px/s.
func takeoff(at_charge: float) -> float:
	return sqrt(2.0 * Gravity.PULL * peak(at_charge))


# ------------------------------------------------------------------- the arc ----

## One tick of whatever the animal is doing about leaving the ground.
##
## `held` is whether the jump key is down. The phases are gather (the propulsive
## feet come under the body), charge (the crouch deepens and the store winds),
## thrust (the joints open and the body genuinely stands up on them) and flight —
## which is not simulated here at all: the take-off hands its speed to
## `Armature.fall`, the world's one vertical integrator, and the body comes down the
## same way a dropped one does.
func tick(delta: float, held: bool, armature: Armature) -> void:
	load = Vector2.ZERO
	drive = 0.0
	if armature == null:
		return
	if phase == FLIGHT:
		# Nothing to spend: the legs are reaching for a floor that is not there yet,
		# which the gait already does with an airborne body. The phase ends when the
		# fall does.
		if not armature.fall.is_airborne():
			phase = IDLE
			charge = 0.0
		return
	if not capable:
		phase = IDLE
		charge = 0.0
		return

	# The clock runs whatever the key is doing: an extension the animal has already
	# committed to finishes on its own, and a jump that had to be held to complete
	# would be a jump you could take back halfway through the push.
	_elapsed += delta
	if held:
		match phase:
			IDLE:
				phase = GATHER
				_elapsed = 0.0
				charge = 0.0
			GATHER:
				if _elapsed >= gather_time:
					phase = CHARGE
					_elapsed = 0.0
			CHARGE:
				charge = clampf(_elapsed / maxf(charge_time, 0.001), 0.0, 1.0)
	elif phase == GATHER or phase == CHARGE:
		phase = THRUST
		_elapsed = 0.0
	elif phase != THRUST:
		phase = IDLE
		charge = 0.0

	match phase:
		GATHER:
			# The weight shift. The driving girdle folds a little; the other holds.
			var into: float = clampf(_elapsed / maxf(gather_time, 0.001), 0.0, 1.0)
			load = Vector2(share.x, share.y) * 0.35 * into
			drive = 1.0 / maxf(gather_time, 0.05)
		CHARGE:
			# The crouch proper: each girdle folds by its own share of the push.
			load = Vector2(share.x, share.y) * charge
			drive = 1.0 / maxf(charge_time, 0.05)
		THRUST:
			var through: float = clampf(_elapsed / maxf(thrust_time, 0.001), 0.0, 1.0)
			# Extension: the load reverses, which is the legs opening. The body is
			# standing up on them, and that is visible before any elevation exists.
			load = -Vector2(share.x, share.y) * through
			drive = 1.0 / maxf(thrust_time, 0.05)
			if through >= 1.0:
				took_off = peak(charge)
				armature.launch(takeoff(charge))
				phase = FLIGHT
				_elapsed = 0.0


## Whether the body is in the air on this file's account.
func airborne() -> bool:
	return phase == FLIGHT


## What the whole of it comes to in the animal's own heights — the only unit a leap
## means anything in.
func heights(stand_height: float) -> float:
	return full / maxf(stand_height, 1.0)
