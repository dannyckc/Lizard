## Whether these jaws can be got onto that, and what the body has to do about it.
##
## The counterpart of `Traversal`, and built on the same terms: a question about
## one specific place in the world, answered out of the animal's own dimensions
## and nothing else. Traversal asks whether a body can get *past* something.
## This asks whether a mouth can get *onto* something, which is the same kind of
## question — a reach, a height, a set of joint limits — pointed at the front end
## of the animal instead of at its legs.
##
## What comes back is not a yes or a no. It is a yes or a no *and the movement
## that makes it a yes*, because in a real animal those are the same answer:
## a creature does not discover it can reach the ground and then play a reaching
## animation. It lowers its head as far as the neck goes, folds its legs by
## however much they have left, and leans in by as much of a lunge as it has —
## and whether the mouth arrives is whether that was enough.
##
## So the adjustments below are outputs rather than inputs, and each of them is a
## length the body already has. The head coming down off the neck's rest height is
## the first thing spent and costs nothing — a neck that lifts a head can lower one
## — so it is already inside the band `Stature` reports and does not appear here.
## What is left is the two that the body has to move for:
##
##   * `crouch` — the legs folding, as a share of the fold `Stature` measured.
##     This is the one that shows: the whole animal comes down, its stance draws
##     in, and its bands come with it, because the crouch is fed back into the
##     gait as a shorter leg rather than drawn over the top of a standing one.
##   * `lean` — the lunge's own throw, as the share of it this reach needs. It
##     is the animal moving, literally: a neck cannot get longer, so everything
##     the mouth gains ahead of where it rests is the body driving itself
##     forward off its feet. See `Creature.lunge_throw`, which is how far this
##     particular body can do that without going over.
##
## Nothing here names a species and nothing here names a target. An elephant
## feeding at its feet, a lizard taking a pellet off the floor and a cat trying
## for a throat above it are one function with three sets of numbers.
class_name Reach
extends RefCounted

## How far off the mouth's own axis a target may be and still be bitten without
## turning the body. The head's articulation plus what the gape spreads either
## side of it — a mouth is an arc rather than a point, so a bite covers rather
## more than the direction the skull is pointing.
const OFF_AXIS: float = deg_to_rad(96.0)

## Whether the jaws can be brought onto the target at all, once the body has done
## everything it can about it.
var possible: bool = false
## Why not, when not. Empty on a reach that works, and one of the four below
## otherwise — kept as text because it is read by the debug overlay and by test
## failures, and nothing branches on it.
var refusal: String = ""

## What the two adjustments have to be. Zero on a target the animal can already
## reach standing as it is.
var crouch: float = 0.0
var lean: float = 0.0

## How far the jaws are from the target on the ground plane, and how far short of
## it they fall vertically once everything has been spent. `gap` is zero on a
## reach that works and the shortfall in pixels on one that does not, so a caller
## that wants to know *how badly* out of reach something is has it.
var distance: float = 0.0
var gap: float = 0.0
## Where the mouth would have to come to, in the one axis the picture does not
## have. What the head look and the crouch are both aiming at.
var height: float = 0.0
## Something solid between the mouth and the target. A bite may not reach through
## a boulder, and this is the only place that is asked.
var obstructed: bool = false


## Works out all of the above for one creature reaching for one place.
##
## `at` is on the ground plane and `target_band` is the heights the thing
## occupies — the same pair every other interaction in the game is described by,
## so a body part, a pellet, a piece of meat and the top of a rock all arrive here
## in the same shape and are answered by the same arithmetic.
static func solve(creature: Node, at: Vector2, target_band: Vector2,
		terrain: Terrain = null) -> Reach:
	var r := Reach.new()
	if creature == null or creature.stature == null or creature.params == null:
		r.refusal = "no body"
		return r
	var stature: Stature = creature.stature
	# From the *rest* pose, deliberately, in both axes. The mouth may already be
	# swept toward something — this very target, most ticks — and a reach solved
	# from a pose that is itself a response to the last answer would chase its
	# own tail: dipping toward a target must not make the target harder to
	# reach. What the dip really costs is charged below, off the target's own
	# height, so the answer is the same on every tick of the approach.
	var mouth: Vector2 = creature.jaw_rest_point()
	r.distance = mouth.distance_to(at)

	# --- vertically: the band, and the three ways of moving it -----------------
	# First, because the horizontal question below is priced *at a height* — the
	# neck's arc trades plan reach for the sweep that gets the mouth there — and
	# a height the body cannot arrive at by any spending is not a price, it is a
	# refusal. Charging the arm for an impossible sweep would report a target
	# above the animal as merely far away.
	r.height = meeting(creature, target_band)
	if not Volume.overlaps(stature.bite, target_band):
		r.gap = maxf(target_band.x - stature.bite.y, stature.bite.x - target_band.y)
		r.refusal = "above" if target_band.x > stature.bite.y else "below"
		return r

	# What it costs. `bite` already has the fold in it — that is what makes the
	# overlap above true for a tall animal reaching its own feet — so what is
	# worked out here is how much of that fold this particular target is actually
	# spending, and the rest stays in hand.
	var rest_low: float = _rest_low(creature)
	if r.height < rest_low:
		var below: float = rest_low - r.height
		r.crouch = clampf(below / maxf(stature.fold, 0.001), 0.0, 1.0)

	# --- horizontally: the gape, plus as much of the lunge as it takes ---------
	# The throw is the whole of what a creature gains by striking rather than by
	# standing there — and since the neck stopped stretching, all of it is the
	# body moving: see `Creature._advance_lunge`. So the lean is that throw priced
	# in the units it is spent in, and it saturates at all of it.
	#
	# The two axes are one purse now, and the neck's arc is the exchange rate:
	# sweeping the mouth to the meeting height rotates part of the neck out of
	# the ground plane, and whatever plan reach that projection loses — or gains,
	# on a perched head coming down through level — moves through the same lean.
	# See `Stature.neck_pullback`. A target at the edge of the arm *and* the edge
	# of the sweep is genuinely out of reach, which two independent tests would
	# never have said.
	#
	# Saturated at what the posed chain can actually express — the same minf
	# where Creature poses the head — because the drawn primitives are what the
	# strike is then hit-tested against: an arm priced off the full arc would
	# promise less than the picture delivers, and one priced off none of it
	# would promise more.
	var pullback: float = minf(_neck_slack(creature), stature.neck_pullback(
		r.height - creature.jaw_rest_height()))
	var gape: float = creature.gape_radius()
	var throw: float = creature.lunge_throw()
	r.lean = clampf((r.distance - gape + pullback) / maxf(throw, 0.001), 0.0, 1.0)
	var arm: float = span(creature) - pullback
	if r.distance > arm:
		r.refusal = "too far"
		r.gap = r.distance - arm
		return r

	# ...and pointing the right way. A head swings on a neck rather than a swivel,
	# and the jaws spread either side of where it points; past that the animal has
	# to turn its body, which is a different action and not this one's business.
	var facing: Vector2 = creature.head_look_dir
	if r.distance > 0.001 and facing.length_squared() > 0.0001:
		var off: float = absf(facing.angle_to((at - mouth) / r.distance))
		if off > OFF_AXIS:
			r.refusal = "behind"
			return r
	r.possible = true

	# --- and nothing in between ------------------------------------------------
	# The same band test the collision pass runs, asked along the line the jaws
	# travel. A mouth may not close on something on the far side of a rock, and
	# this is the only place in the game that is checked — because it is the only
	# place it comes up.
	if terrain != null:
		var line: Vector2 = Volume.union(target_band, Vector2(r.height, r.height))
		var blocker: Obstacle = terrain.obstruction(mouth, at, line)
		if blocker != null:
			r.obstructed = true
			r.possible = false
			r.refusal = "obstructed by %s" % blocker.kind
	return r


## How far across the ground these jaws get: what the gape already covers, plus
## the whole of the lunge behind it — on something at the mouth's own level.
## The level-ground figure, before the neck's arc has been asked to carry the
## mouth anywhere; see `span_onto` for the same number pointed at a height.
##
## The lunge is `Creature.lunge_throw` rather than the species' parameter,
## because the throw is the *body* moving now — the neck has stopped stretching
## — and a body throws itself only as far as what it is standing on will let it
## get away with. So an animal on four square feet is offered its whole reach, one
## on two is offered less, and one in mid-air is offered the counter-poise. One
## number for what is offered, what is drawn and what is delivered.
static func span(creature: Node) -> float:
	return creature.gape_radius() + creature.lunge_throw()


## The same arm, brought onto something occupying `band`: the level span less
## the plan reach the neck gives up sweeping the mouth to that height,
## saturated — exactly as the pose is — at the head link's own slack.
##
## Stated once and used twice — the refusal in `solve` above prices the arm the
## same way, and the point a marker aimed past it is brought in to, in
## `Reticle.resolve`, is placed with this. They have to be the same number or
## the reticle would offer the player a place the body then declines to reach.
static func span_onto(creature: Node, band: Vector2) -> float:
	var pullback: float = minf(_neck_slack(creature),
		creature.stature.neck_pullback(
			meeting(creature, band) - creature.jaw_rest_height()))
	return span(creature) - pullback


## How much of the arc's projection the plan chain can actually express: a
## spine of fixed segment lengths retracts its head only as far as the head
## link compresses — see Spine.MIN_NECK, which is where the posed neck stops.
## Both the arm above and the posed head saturate here, which is what keeps
## the offered reach and the drawn reach one number.
static func _neck_slack(creature: Node) -> float:
	return creature.segment_rest() * (1.0 - Spine.MIN_NECK)


## The height on a target's band the jaws will actually meet.
##
## The part of it nearest where the mouth already rides. Aiming at the middle
## would refuse a tall thing whose lower half is perfectly reachable, and a
## mouth does not stoop below flesh it is already level with — so a band the
## resting mouth is inside is met without the head moving at all, one below it
## is met at its top edge and one above it at its bottom edge. It is also the
## height the *marker* belongs at, which is why this is named rather than
## inlined: a bite, the movement that delivers it and the ring drawn where it
## will land must agree about where that is.
static func meeting(creature: Node, band: Vector2) -> float:
	return clampf(creature.jaw_rest_height(), band.x, band.y)


## The lowest the jaws get without folding a single joint of leg: the head down
## off its neck, the neck swept as far under as it goes, and the animal still
## standing exactly as tall as it was. Everything below this is bought with the
## crouch.
static func _rest_low(creature: Node) -> float:
	var stature: Stature = creature.stature
	return stature.bite.x + stature.fold


## A one-line summary, for the debug overlay and for test failures.
func describe() -> String:
	if possible:
		return "reachable at %.0f (crouch %.0f%%, lean %.0f%%)" \
			% [height, crouch * 100.0, lean * 100.0]
	return "out of reach (%s, short by %.0f)" % [refusal, gap]
