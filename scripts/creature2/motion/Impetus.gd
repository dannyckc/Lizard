## What the body is physically doing on the plan, and the one place that changes.
##
## The middle of the locomotion loop (docs/V2_DESIGN.md §Phase 3): a desired
## velocity comes in from the intent, the difference between it and the actual
## velocity is a demanded acceleration, and what is *delivered* is that demand
## clamped to what the planted feet can currently press against the ground. The
## velocity integrated from the delivered acceleration is the body's real state —
## there is no speed anybody sets, only this integral.
##
## Three laws hold here and everything else follows from them:
##
##   * **No acceleration parameter.** The ceiling is derived: locomotor muscle
##     over body mass, off the census, quoted against the reference cat's own
##     ratio so the default build is exactly power 1.000 — re-pin, never retune.
##     A chewed haunch weakens the push because the compartments shrank, not
##     because anything was told.
##   * **The ground is the engine.** Every term of delivery is multiplied by
##     `grip` — Footwork's measurement of how much press the planted feet have
##     left — and an airborne body delivers nothing at all: a leap is ballistic
##     on the plan because there is nothing to press against, not because a rule
##     says leaps go straight.
##   * **Physics is not overridden.** `shove` changes the actual velocity and
##     nothing else; recovery is the same loop noticing the actual velocity no
##     longer matches the desired one and demanding the difference back, subject
##     to the same grip. Being pushed and setting off are one mechanism.
class_name Impetus
extends RefCounted

## The reference cat's locomotor muscle (fore + hind + epaxial compartments)
## over its body mass — the datum `power` divides by, pinned beside
## CorpusProbe's constants so the default build is exactly 1.000.
const SPECIFIC_REF: float = 0.332711077

## What power-one legs press at, standing square with everything fresh, px/s².
## The one propulsion scale in v2: every other term is a derived multiplier on
## it (power off the census, drive off the stance, grip off the feet).
const PUSH: float = 360.0

## Legs stop a body better than they start one — braking presses into the
## stride instead of against it.
const BRAKE: float = 1.35

## How quickly desire becomes demand, seconds. Not an acceleration: however
## short this is, delivery is still capped by the push. It exists so a small
## velocity error asks for a small correction rather than for everything.
const RESPONSE: float = 0.12

## How fast sideways slip dies while the feet are planted, per second. Claws
## and pads: a shoved body is carried sideways and then *held* by its own
## stance, which is the half of recovery that is grip rather than stepping.
const GRIP_SIDE: float = 9.0

## How fast all motion dies when nothing is being asked for, per second — a
## standing animal is parked on its feet, not coasting on ice.
const HOLD: float = 6.0

## Below this ask, the body is being asked to stand, px/s.
const STAND_ASK: float = 1.0


## The actual plan velocity, world px/s. The one owner.
var velocity: Vector2 = Vector2.ZERO

## Locomotor muscle over mass, against the reference cat. Re-derived whenever
## the census changes, so wounds genuinely weaken the engine.
var power: float = 1.0

## What was delivered this tick, px/s² — a readout of the clamp, for leaning
## the body into it and for the HUD. Never an input to anything upstream.
var thrust: Vector2 = Vector2.ZERO

var _derived_rev: int = -1


## Re-reads the engine off the census. Revision-keyed: an ordinary tick reads
## two cached numbers and leaves.
func derive(corpus: Corpus) -> void:
	if corpus == null or corpus.revision == _derived_rev:
		return
	_derived_rev = corpus.revision
	var c: Dictionary = corpus.compartments()
	var locomotor: float = float(c.get(&"fore_girdle", 0.0)) \
		+ float(c.get(&"hind_girdle", 0.0)) + float(c.get(&"epaxial", 0.0))
	power = (locomotor / maxf(corpus.mass(), 0.0001)) / SPECIFIC_REF


## One tick of the middle of the loop: desired velocity in, actual velocity
## moved as far toward it as the feet allow. `along` is the body's facing, for
## the grip's sense of sideways; `drive` is the stance's leaning
## (Carriage.drive); `grip` is Footwork's press measurement, 0..1.
func propel(delta: float, desired_v: Vector2, along: Vector2, drive: float,
		grip: float, airborne: bool) -> void:
	if airborne:
		# Ballistic: the plan velocity is whatever the take-off left, until the
		# ground is back under the feet. The vertical belongs to Gravity.Fall.
		thrust = Vector2.ZERO
		return

	var press: float = clampf(grip, 0.0, 1.0)
	var ceiling: float = PUSH * power * maxf(drive, 0.0) * press
	var want: Vector2 = (desired_v - velocity) / maxf(RESPONSE, delta)
	# Braking is any demand that takes speed out of the body.
	if want.dot(velocity) < 0.0:
		ceiling *= BRAKE
	thrust = want.limit_length(ceiling)
	velocity += thrust * delta

	# Grip: the stance eats sideways slip, and eats everything when the body is
	# being asked to stand. Exponential, so a hard shove is shed over a few
	# tenths rather than annulled — physics changed the state and the state
	# recovers, it is not reset.
	var side := Vector2(-along.y, along.x)
	var slip: float = velocity.dot(side)
	velocity += side * (slip * (exp(-GRIP_SIDE * press * delta) - 1.0))
	if desired_v.length() < STAND_ASK:
		velocity *= exp(-HOLD * press * delta)


## An external force, arriving as the velocity change it caused. The whole of
## the seam contacts and charges push through: the state moves, the loop
## notices, the body recovers or fails to.
func shove(dv: Vector2) -> void:
	velocity += dv


## A solid refusing part of the motion: the component of the velocity going
## *into* the surface (`normal` points out of the solid) is taken away, and
## what was taken is returned — the impact the body actually felt. Meat, not
## rubber: nothing bounces, the tangent keeps, which is what sliding along a
## wall is. Recovery from a hard stop is the same loop noticing the state no
## longer matches the ask — a wall and a shove are one mechanism.
func deflect(normal: Vector2) -> float:
	var into: float = velocity.dot(normal)
	if into >= 0.0:
		return 0.0
	velocity -= normal * into
	return -into


func speed() -> float:
	return velocity.length()


func halt() -> void:
	velocity = Vector2.ZERO
	thrust = Vector2.ZERO
