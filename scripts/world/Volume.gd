## Where a thing is in the one direction the picture does not have, and the one
## rule that makes that direction matter.
##
## Everything in this world already has an x and a y. This file adds the z — not
## as a third direction to *move* in, which is Elevation's business, but as a
## third question every interaction is asked before it is allowed to happen. Two
## things touch when their footprints overlap on the ground plane *and* the
## heights they occupy overlap. Miss either half and they are simply not in each
## other's way: one passes over the other, or under it, and neither ever knew.
##
## A z is a `Vector2(low, high)` in world pixels above the ground plane — the
## same unit as x and y, so a leap, a leg, a bite and a body are all measured to
## one scale and none of them needs converting. It is a *range* rather than a
## point because nothing in a body is infinitely thin: a belly is at a height, a
## leg spans one, and "is the foot above the lizard" is a question about two
## thicknesses rather than two altitudes.
##
## The whole of the volumetric layer is `overlaps`, three lines below. Everything
## else here is that same test with the horizontal half attached, or the small
## algebra needed to build a range out of the geometry that was already solved.
## Nothing stores a z: every band in the game is derived each tick from the pose,
## for the same reason no creature stores its own height — a stored one can
## disagree with the body it is supposed to describe.
##
## Two conventions, and they are worth stating because breaking either one is
## silent:
##
##   * Bands are absolute. A creature ten pixels off the ground has all of its
##     bands ten pixels higher, so a caller never has to know whose body a band
##     came off before comparing it with another.
##   * `UNBOUNDED` overlaps everything. It is the default anywhere a band is
##     optional, so a caller that knows nothing about height gets exactly the
##     flat-world behaviour that existed before this axis did. That is what makes
##     the layer additive rather than a rewrite: every gate is a second `and`,
##     never a replacement.
class_name Volume
extends RefCounted

## The band of something with no height — everything reaches it and it reaches
## everything. Chosen finite rather than infinite so it survives arithmetic:
## `grow`, `lift` and `union` on an infinity would produce a NaN somewhere
## downstream and the gate would start failing open at random.
const UNBOUNDED := Vector2(-1.0e9, 1.0e9)
## The identity for `union` — a band so inverted it contains nothing. Start an
## accumulation here and the first real band replaces it outright.
const NOWHERE := Vector2(1.0e9, -1.0e9)

## Thin enough to be a plane for every purpose except the one that matters: a
## thing lying *on* the ground still has to be reachable by jaws that come down
## to the ground, and two exactly-equal edges are a fragile way to arrange that.
const GROUND_THICKNESS: float = 6.0


## A band of `half` either side of `centre`. The usual way one is built, because
## almost everything in a body is described by where its middle is and how thick
## it is there.
static func span(centre: float, half: float) -> Vector2:
	var h: float = absf(half)
	return Vector2(centre - h, centre + h)


## A band running between two heights, whichever way round they came.
static func between(a: float, b: float) -> Vector2:
	return Vector2(minf(a, b), maxf(a, b))


## Whether two bands touch at all.
##
## This is the entire vertical rule. Every "it passed under me", "my jaws could
## not reach that", "the leg went over it" in the game is this function returning
## false. Inclusive at the edges, so something resting exactly on a surface is
## touching it rather than hovering a nothing above it.
static func overlaps(a: Vector2, b: Vector2) -> bool:
	return a.x <= b.y and b.x <= a.y


## Whether a single height falls inside a band.
static func contains(a: Vector2, z: float) -> bool:
	return z >= a.x and z <= a.y


## The smallest band containing both. How a structure's band is assembled out of
## its parts — a body's out of its cells, a limb's out of its bones.
static func union(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(minf(a.x, b.x), maxf(a.y, b.y))


## The band both occupy, inverted if they do not meet.
static func common(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(maxf(a.x, b.x), minf(a.y, b.y))


## Thickened by `by` in both directions. What turns the centre-line of a bone
## into the height range the bone actually fills.
static func grow(a: Vector2, by: float) -> Vector2:
	return Vector2(a.x - by, a.y + by)


## Moved bodily up. The one operation an airborne body needs: everything about
## how a creature is put together is quoted against its own ground, and getting
## off the ground moves all of it at once.
static func lift(a: Vector2, by: float) -> Vector2:
	return Vector2(a.x + by, a.y + by)


## How deeply two bands share height, negative by the size of the gap when they
## do not. The graded form of `overlaps`, for the places that want to know how
## squarely something was met rather than merely whether it was — a glancing
## contact at the very top of a leg is not the same event as a body walking into
## the middle of it.
static func shared(a: Vector2, b: Vector2) -> float:
	return minf(a.y, b.y) - maxf(a.x, b.x)


## How much room there is beneath `over` for something standing in `under` to get
## through. Negative when it does not fit, which is the same number `shared`
## reports positive — kept as its own name because the reading is the interesting
## one: this is the question "can I walk under that".
static func clearance(under: Vector2, over: Vector2) -> float:
	return over.x - under.y


## The full three-axis test between two upright discs: two footprints on the
## ground plane, each with a height range.
##
## The horizontal half first, because it rejects far more often and costs less —
## and squared, so a test that answers "no" never takes a square root. This is
## the shape almost everything in the world actually is: a pellet, a foot, a
## head, a chunk of meat. Anything longer than it is wide is a capsule and does
## its own horizontal work, then asks `overlaps` for the rest.
static func meet(a_at: Vector2, a_radius: float, a_band: Vector2,
		b_at: Vector2, b_radius: float, b_band: Vector2) -> bool:
	var reach: float = a_radius + b_radius
	if a_at.distance_squared_to(b_at) > reach * reach:
		return false
	return overlaps(a_band, b_band)


## The same, against something small enough to have no width of its own.
static func reaches(at: Vector2, radius: float, band: Vector2,
		point: Vector2, point_band: Vector2) -> bool:
	if at.distance_squared_to(point) > radius * radius:
		return false
	return overlaps(band, point_band)


## The band something lying on the floor occupies. One description, so a scrap, a
## carcass and a pellet are all reachable by exactly the jaws that can reach the
## ground.
static func ground() -> Vector2:
	return Vector2(0.0, GROUND_THICKNESS)


## Readable form, for test failures and the debug overlay.
static func describe(a: Vector2) -> String:
	if a == UNBOUNDED:
		return "unbounded"
	return "%.1f..%.1f" % [a.x, a.y]
