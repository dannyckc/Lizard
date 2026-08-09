## Whether this body can throw itself off the ground, and how far.
##
## The fifth derived descriptor, and it is built on exactly the terms of the
## other four. `Physique` reads how much animal there is and how hard it pulls;
## `Articulation` reads what its joints do; `Spring` reads what in it stores work;
## `Locomotion` reads how it walks off all three. This reads how it *leaves*, and
## like the rest of them it is arithmetic on a body that has already been solved
## rather than a number typed into a preset.
##
## That replacement is the whole point of the file. A jump used to be
## `leap_height`, a per-species multiple of the animal's own height, and a
## parameter of that shape can only ever be a promise: it said an Elephant could
## not jump because somebody wrote a zero, and it would have said a creature with
## no legs at all could clear three of itself if somebody had written a three.
## Nothing about the body was consulted and nothing about the body could
## contradict it.
##
## Five laws do the whole of it, and every number below is one of them applied to
## the animal that has just been solved:
##
##   * **A jump is work against weight.** The apex of a leap is the work put into
##     it divided by what the body weighs, and work is force times distance. The
##     force is the muscle's, per unit of weight — which is `Locomotion.power`,
##     the same ratio that makes a heavy animal slow off the mark. The distance is
##     how far the joints extend through. There is no third term and no gain.
##   * **A body has to hold itself up first.** Of every unit of force the legs
##     produce, one body weight is spent standing there. What is left over is what
##     accelerates the animal upward — so a build whose legs cannot push harder
##     than it weighs does not jump badly, it does not jump, and nothing had to
##     say so. This is where an Elephant stops, and it stops on an inequality
##     rather than on a category.
##   * **Muscle is weaker the faster it shortens.** A leg thrown open in a tenth
##     of a second develops a fraction of what it could hold. That is why an
##     elastic store is worth having at all — see `Spring`: it is wound slowly at
##     something near the muscle's full force and returned at whatever rate the
##     joint or the catch allows.
##   * **A store is only as good as the joint that spends it.** Elastic tissue
##     gives its work back by pushing something open, so a limb with nowhere to go
##     returns almost nothing however much it holds. Which is the second, quieter
##     reason a columnar animal stays on the floor, and the reason a very small
##     one needs a catch instead of a longer leg.
##   * **A push is taken about a pivot.** To drive with a girdle an animal has to
##     get its weight over it, and how far it can shift is set by what there is on
##     the other side to balance against — see `Physique.balance`. That, and not a
##     rule about quadrupeds, is why the hind limbs do the propelling: rearing back
##     over the hips is something every four-legged animal can do, and getting the
##     trunk and the tail up over the shoulders is something none of them can.
##
## Refreshed once per tick from the previous tick's physique and stature, ahead of
## everything that reads it. The same deliberate one-tick lag `Locomotion` is
## refreshed with, and harmless for the same reason: what an animal weighs and how
## tall it stands are properties of a body being eaten over seconds, not of this
## frame.
class_name Leap
extends RefCounted

## How many times its own weight a girdle of unit power pushes the ground with,
## through the whole of its extension. The one calibration constant in the file
## and the only place the game's force currency is converted into a real
## acceleration — `Physique.strength` is quoted against a reference build rather
## than in newtons, so something has to say what a reference build's legs can do,
## and this is it.
##
## Around three body weights of gross vertical force at the reference build's
## power, which is what a real standing jump measures on a force plate. Note what
## it is *not*: it is not how high anything jumps. The height falls out of this
## against the animal's own power, its own joint travel and its own weight, and
## the same constant produces a Cat clearing twice its height and an Elephant
## clearing nothing.
const PUSH_WEIGHTS: float = 6.5

## How much of that force survives being asked for quickly.
##
## A muscle shortening fast develops a fraction of what it develops holding still,
## and a push-off is the fastest thing a leg ever does — so the work the muscle
## puts in *during* the extension is worth about half of what the same muscle
## could hold against a spring while the animal crouched. It is the reason a store
## is worth carrying and it is the difference between a jumper and a strong
## animal: the store's half of `_girdle` carries no such term, because a spring
## does not care how fast it is let go.
const FAST_MUSCLE: float = 0.55

## What one pixel of wound elastic returns, per unit of the power that wound it.
## The spring's counterpart to PUSH_WEIGHTS, and lower than it for a reason that
## is not tuning: a store has already paid the body's weight once on the way in —
## the muscle that wound it was holding the animal up at the same time — so what
## comes back out is the work itself with nothing further taken off it.
const SPRING_RETURN: float = 2.0

## How long the animal takes to wind its store, in swings of the limb doing the
## winding. A crouch is the same limb the gait swings, moved the same way by the
## same muscle against the same weight, so how long it takes is the pendulum
## arithmetic `Locomotion.swing_time` already does — which is why a mouse is ready
## in a tenth of a second and a heavy animal is still settling when the mouse has
## landed. There is no charge-rate parameter and there cannot be one.
const LOAD_SWINGS: float = 1.6
## And how long the weight shift ahead of it takes, in the same unit. Short: it is
## the propulsive feet coming under the body, which is a step rather than a
## crouch.
const GATHER_SWINGS: float = 0.55
## And how long the extension itself takes. The shortest of the three, and it has
## to be long enough for the body to actually come up on the legs that are opening
## underneath it — a push-off is a creature standing up very fast, and one spread
## over less time than its own legs take to lift it is an impulse with a pose
## played over the top.
const THRUST_SWINGS: float = 0.80

## Least a body may push with and still be said to jump, as a share of the height
## it picks one foot up by.
##
## The capability test, and it is a comparison rather than a threshold anybody
## chose: if the whole animal cannot throw itself higher than it lifts a single
## foot to walk, then what it has is not a jump, it is a step. Everything that
## makes an animal unable to leave the ground already shows up on the left of it —
## a joint that will not fold, a limb with no travel, muscle that cannot beat the
## body's own weight — so nothing here has to know which of those went wrong.
const JUMP_OVER_STEP: float = 1.0

## What a girdle with half the body behind it to balance against is worth, so the
## share is a multiplier around one rather than a raw fraction of a body. See
## `Physique.balance`, which is the measurement; this is only its scale.
const BALANCE_GAIN: float = 2.0

## Least of a limb's fold that counts as working against the ground when it
## catches a landing — see `_catch`. A floor on the projection rather than on the
## absorption: a sprawled animal meeting the floor still takes something out of it
## by splaying, and it is not much.
const CATCH_FLOOR: float = 0.25

## Most any body of muscle gets out of one contraction, in pixels of apex.
##
## The one flat ceiling in the file and the least arbitrary thing in it: muscle
## does a roughly fixed amount of work per unit of its own mass, and only so much
## of any animal is muscle, so the work per unit of *body* weight — which is
## exactly what an apex is — has a limit that does not care how large the animal
## is. It is the reason a flea and a horse jump to within a factor of two of the
## same absolute height while differing by seven orders of magnitude in weight,
## and it is the standard result the whole literature on jumping is organised
## around.
##
## Applied as a saturation rather than a clamp, because it is a property of the
## tissue rather than a rule about the animal: a body a long way under it is
## unaffected, one approaching it gets progressively less for each further unit
## of muscle or joint travel, and nothing is ever cut off at a line. Which is why
## a Cheetah, whose numbers ask for a great deal more than a Cat's, comes out
## better than a Cat rather than three times a Cat.
const SPECIFIC_WORK: float = 320.0

## How much of the takeoff may be aimed along the ground rather than up it. A
## jump is a push against the floor and the floor is beneath the animal, so most
## of it is vertical whatever the creature intended; what is left is the lean, and
## it is what makes a running jump carry.
const DIRECTION_SHARE: float = 0.55


# --- what this body can do about leaving the ground --------------------------
# All of it read out rather than set, and none of it is a mode. A creature that
# cannot jump is one whose numbers below came out small, and it is refused by the
# same line that would have let it through.

## Whether there is a jump here at all — see JUMP_OVER_STEP.
var capable: bool = false
## What each girdle contributes to the push, as shares summing to one. A cat is
## nearly all hind; a build with matched girdles pushes with both; a two-legged
## animal has only one, and that falls out of `Locomotion.forelimbs_bear` rather
## than out of a rule about bipeds.
var share: Vector2 = Vector2(0.0, 1.0)
## Apex of a fully charged standing jump, in world pixels. The headline number,
## and every other reading here is it seen from somewhere.
var full: float = 0.0
## The same, before anything is wound: what this body gets from a standing start
## with no crouch at all. The floor a tapped key lands on.
var bare: float = 0.0
## Seconds to wind the store from standing. Past it nothing further accumulates —
## see `Jump`, which holds the pose rather than the energy.
var charge_time: float = 0.4
## Seconds of weight shift before the winding starts, and seconds the extension
## itself takes.
var gather_time: float = 0.15
var thrust_time: float = 0.1
## Fastest arrival each girdle can take out of a landing without being driven to
## its stops, in pixels per second. Read by the landing, which folds the joints by
## how much of it the impact actually used.
var absorb: Vector2 = Vector2(200.0, 200.0)
## How completely this build can throw itself, 0..1 — the reading `Footfall` needs
## to know whether an asymmetric gait is available at all. Saturating, because
## what that question wants is "can it leave the ground", not "how far".
var launch: float = 0.0

## What the arithmetic above was done on, kept because the jump itself needs the
## same lengths and there is no sense measuring them twice.
var _bone: Vector2 = Vector2(30.0, 40.0)
var _vertical: float = 0.0
var _articulation: Articulation = Articulation.new()
var _spring: Spring = Spring.new()
var _power: float = 1.0
var _balance: Vector2 = Vector2(0.3, 0.6)


## Re-derives everything from the body that has just been solved.
##
## `stand_height` is how tall the animal stands, which is only used to decide
## whether what came out counts as a jump and to quote the result in the one unit
## a leap means anything in. `scale` is the creature's drawn size, for the same
## reason every other length carries it.
func update(posture: Posture, loco: Locomotion, physique: Physique,
		spring: Spring, p: CreatureParams, scale: float,
		stand_height: float) -> void:
	if posture == null or loco == null or physique == null or spring == null or p == null:
		return
	_articulation = loco.articulation
	_spring = spring
	_power = loco.power
	_bone = Vector2(p.arm_length * scale, p.leg_length * scale)

	# How much of a leg's extension goes upward. The posture again, and taken
	# straight: a limb stacked under the shoulder pushes the body away from the
	# floor and a limb rowing out sideways pushes it along one. That single
	# projection is why an upright build leaves the ground and a sprawled one of
	# the same weight and the same muscle scrabbles — and it is the same sine the
	# clearance, the stride and the footfall pattern are all read off, so no part
	# of the animal can disagree with another about how it is standing.
	_vertical = clampf(sin(posture.tilt), 0.0, 1.0)

	# What each girdle is worth, on its own, at full charge. Both are asked and
	# neither is assumed: which end of an animal drives a jump is a question about
	# which end has the muscle, the travel and the spring, and on nearly every
	# quadruped the answer is emphatically the hind pair — but it is an answer
	# rather than a rule, so a build with matched girdles pushes with both and one
	# whose forelimbs never reach the floor pushes with what it has.
	_balance = physique.balance * BALANCE_GAIN
	var fore: float = _girdle(Limb.FRONT, 1.0) if loco.forelimbs_bear else 0.0
	var hind: float = _girdle(Limb.REAR, 1.0)
	var total: float = fore + hind
	share = Vector2(fore, hind) / total if total > 0.0 else Vector2(0.0, 1.0)

	full = _ceiling(total)
	bare = _ceiling((_girdle(Limb.FRONT, 0.0) if loco.forelimbs_bear else 0.0)
		+ _girdle(Limb.REAR, 0.0))

	# How tall the animal stands. Measured off the feet by the time anything asks,
	# and before a gait has ever run there is nothing to read — so a body of these
	# bones falls back on the bones, which is the same fallback every other height
	# in the simulation takes on its first tick.
	var tall: float = maxf(stand_height, _bone.y * 0.5)

	# ...and whether that is a jump. A body that cannot throw the whole of itself
	# higher than it picks up one foot has not got a leap; it has got a step, and
	# it already has one of those.
	var lift: float = loco.lift(tall, maxf(_bone.x, _bone.y))
	capable = full > lift * JUMP_OVER_STEP

	# How long the whole of it takes. Every one of the three is the same pendulum
	# `Locomotion` swings a leg with, because that is what is happening: the limb
	# that folds to gather, holds to charge and opens to push is the limb the gait
	# picks up and puts down, moved by the same muscle against the same weight.
	# The maximum charge is therefore anatomical outright — there is no clock here
	# that is not a measurement of this animal's own leg.
	var swing: float = loco.swing_time(_bone.y if share.y >= share.x else _bone.x)
	charge_time = maxf(swing * LOAD_SWINGS, 0.05)
	gather_time = maxf(swing * GATHER_SWINGS, 0.03)
	thrust_time = maxf(swing * THRUST_SWINGS, 0.02)

	# What a landing may be worth. The same arithmetic run backwards: a limb takes
	# work out of a falling body over the distance it folds, at the force its
	# muscle can hold, and how fast a body may arrive and still be caught is what
	# that comes to. A joint that cannot fold cannot catch anything, which is why a
	# heavy columnar animal has no business off the ground in the first place.
	absorb = Vector2(_catch(Limb.FRONT), _catch(Limb.REAR))

	# And the saturating reading of the same fact, for the gait. What `Footfall`
	# is asking is whether this body can push itself into the air at all — a girdle
	# working as a single pair is a launch — so it wants the leap quoted against
	# the animal rather than in pixels, and it wants it bounded.
	var tall_in: float = full / maxf(tall, 1.0) if capable else 0.0
	launch = tall_in / (tall_in + 1.0)


## What one girdle is worth at a given charge, in pixels of apex.
##
## The four laws of the header, in four lines. Force per unit weight is the
## animal's own power; one weight of it is spent standing there; what is left
## acts over however far the joint has to extend; and whatever the spring is
## holding is added on top, less whatever the joint cannot pay out.
func _girdle(pair: int, charge: float) -> float:
	var stroke: float = _stroke(pair, charge)
	if stroke <= 0.0:
		return 0.0
	# The muscle's own contribution, at the force it can develop while shortening
	# as fast as a push-off asks. Never negative: a leg that cannot push harder
	# than the body weighs does not pull the animal into the ground, it simply
	# fails to lift it.
	var net: float = maxf(PUSH_WEIGHTS * _power * FAST_MUSCLE - 1.0, 0.0)
	var work: float = net * stroke * _vertical
	# ...and the store, which is not subject to either qualification. It was wound
	# at the muscle's holding force while the animal was standing on the same legs,
	# and it comes back at whatever rate the joint or the catch allows.
	var store: Spring.Store = _spring.of(pair)
	var bone: float = _bone.x if pair == Limb.FRONT else _bone.y
	work += SPRING_RETURN * _power * store.capacity * _vertical \
		* clampf(charge, 0.0, 1.0) * store.payout(stroke, bone)
	# ...and how much of its weight this girdle can actually get over itself to
	# push with. Everything above is what the limb could do standing under the
	# animal's middle; this is the animal arranging to be there, and it is the
	# whole of why a jump comes out of the hind legs without anything having been
	# told that it should.
	return work * (_balance.x if pair == Limb.FRONT else _balance.y)


## What a body of muscle actually gets away with — see SPECIFIC_WORK.
##
## A saturation rather than a cap: at a tenth of the ceiling it takes off
## essentially nothing, at the ceiling it halves, and it never quite arrives. So
## the ordering of every build is preserved — a body with better numbers always
## jumps further than one with worse — while the difference between them narrows
## exactly where real muscle stops keeping up.
func _ceiling(raw: float) -> float:
	return raw / (1.0 + maxf(raw, 0.0) / SPECIFIC_WORK)


## How far this girdle's joints extend through, in world pixels, at a given
## charge.
##
## The distance in "force times distance", and the whole reason a jump is a
## question about articulation rather than about muscle. A limb pushes from
## wherever it is standing to wherever it locks out; crouching first moves the
## near end of that down toward the joint's own fold, and the further it folds the
## further there is to push through. So charge is not a power setting — it is
## literally how much travel the animal has bought itself, and an animal whose
## knee does not close buys nothing by holding the key down.
func _stroke(pair: int, charge: float) -> float:
	var joint: Articulation.Joint = _articulation.of(pair)
	var from: float = lerpf(joint.stand, maxf(joint.fold, Limb.REACH_MIN),
		clampf(charge, 0.0, 1.0))
	var bone: float = _bone.x if pair == Limb.FRONT else _bone.y
	return maxf(joint.lock - from, 0.0) * bone


## How fast a body this girdle can catch, in pixels per second.
##
## Work again, and the same two terms: the force the limb can hold against the
## floor, over the distance it has to fold through, is the energy it can take out
## of an arriving body — and the speed that corresponds to is the square root of
## twice it. Quoted at the muscle's holding force rather than its shortening one,
## because a limb absorbing a landing is being *lengthened* under load, which is
## the one thing muscle does better than anything else.
## Both the force and the distance are taken through the same projection the push
## is, and for the same reason: a limb rowing out sideways neither pushes a body
## up nor catches one coming down. Floored well clear of zero, because even a
## sprawled animal meeting the floor takes *something* out of the arrival, and a
## girdle credited with catching nothing would report every landing as maximal.
func _catch(pair: int) -> float:
	var joint: Articulation.Joint = _articulation.of(pair)
	var bone: float = _bone.x if pair == Limb.FRONT else _bone.y
	var along: float = maxf(_vertical, CATCH_FLOOR)
	var fold: float = maxf(joint.stand - maxf(joint.fold, Limb.REACH_MIN), 0.0) * bone
	var brake: float = PUSH_WEIGHTS * _power * Elevation.GRAVITY
	return sqrt(maxf(2.0 * brake * along * fold * along, 0.0))


## Apex of a jump taken at this much charge, in world pixels.
##
## Interpolated between the two ends the update measured rather than re-derived,
## because it is asked several times a tick by things that are not solving a body
## — the HUD, the creation menu, the jump itself — and the two ends are the
## expensive part.
func peak(charge: float) -> float:
	if not capable:
		return 0.0
	return maxf(lerpf(bare, full, clampf(charge, 0.0, 1.0)), 0.0)


## How fast the body leaves the ground at that charge, in pixels per second.
## The apex read the other way round, and the number `Elevation` actually wants.
func takeoff(charge: float) -> float:
	return sqrt(2.0 * Elevation.GRAVITY * peak(charge))


## How far a jump of this charge carries, given how fast the body is already
## travelling. Ballistic and nothing else: the flight lasts twice the time the
## climb takes, and the animal covers ground at whatever speed it took off with.
func span(charge: float, speed: float) -> float:
	return absf(speed) * 2.0 * takeoff(charge) / Elevation.GRAVITY


## Which girdle takes the landing.
##
## The forelimbs when there are any under the animal, and it is not a preference:
## a body coming down out of a ballistic arc is travelling forward and nose-first,
## and what reaches the ground first is whatever is at the front of it. A creature
## with nothing there lands on the same pair it left with — which is a hop, and is
## why a two-legged animal's legs have to be both the engine and the suspension.
func brace(forelimbs_bear: bool) -> int:
	return Limb.FRONT if forelimbs_bear else Limb.REAR


## The girdle that drives, for the handful of readings that want one answer rather
## than two shares — which foot the gather brings under the body, chiefly.
func driver() -> int:
	return Limb.REAR if share.y >= share.x else Limb.FRONT


## What the whole of it comes to, in the animal's own heights. The only unit a
## leap means anything in, and the one the creation menu quotes.
func heights(stand_height: float) -> float:
	return full / maxf(stand_height, 1.0)
