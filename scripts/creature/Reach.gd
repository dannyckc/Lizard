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
##   * `lean` — the lunge's own throw, as the share of it this reach needs.
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
	var p: CreatureParams = creature.params
	var mouth: Vector2 = creature.jaw_point()
	r.distance = mouth.distance_to(at)

	# --- horizontally: the gape, plus as much of the lunge as it takes ---------
	# The throw is the whole of what a creature gains by striking rather than by
	# standing there — see `Creature._advance_lunge` — so the lean is that throw
	# priced in the units it is spent in, and it saturates at all of it.
	var gape: float = creature.gape_radius()
	var throw: float = p.bite_reach * creature.size_scale
	r.lean = clampf((r.distance - gape) / maxf(throw, 0.001), 0.0, 1.0)
	if r.distance > gape + throw:
		r.refusal = "too far"
		r.gap = r.distance - gape - throw
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

	# --- vertically: the band, and the three ways of moving it -----------------
	# The part of the target nearest what the jaws already cover. Aiming at the
	# middle of it would refuse a tall thing whose lower half is perfectly
	# reachable, and aiming at the near edge is what a mouth actually does.
	r.height = clampf(_rest_low(creature), target_band.x, target_band.y)
	if Volume.overlaps(stature.bite, target_band):
		r.possible = true
	else:
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
