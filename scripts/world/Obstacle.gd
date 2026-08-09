## One thing in the world that is not an animal, described in exactly the terms
## an animal already is.
##
## A body has a footprint on the ground plane and a band of heights it fills, and
## every interaction in this game is those two questions asked together. A rock
## is not a different kind of object: it is a footprint and a band, and that is
## the whole of why it collides with a walking creature, can be stood on, can be
## passed under when it is an overhang, and can be bitten. Nothing below knows
## what it is meant to represent — a boulder, a log, a ledge and a branch are four
## sets of three numbers.
##
## The three numbers are the ones Volume already speaks in, so an obstacle and a
## creature's shin are directly comparable without either being converted:
##
##   * `at` and `radius` — where it stands and how much ground it covers;
##   * `band` — absolute heights above the world's ground plane, low to high.
##
## A band starting at zero is something sitting on the floor. A band starting
## above it is something with room underneath, and that is the whole of an
## overhang: nobody wrote a doorway, there is simply a base a body can be shorter
## than.
class_name Obstacle
extends RefCounted

## How thin an object may be before there is nothing left of it to collide with.
const GONE: float = 0.001

var at: Vector2 = Vector2.ZERO
var radius: float = 20.0
## Absolute, in world pixels above the ground plane — the same unit as x and y,
## and the same unit a leg, a belly and a bite are measured in.
var band: Vector2 = Vector2(0.0, 20.0)
## How much of the footprint is still in the way, 0..1. The same fraction the
## tissue lattice reports for a chewed-open flank, and it is here for the same
## reason: something worn away should stop being solid where it is gone rather
## than staying a perfect cylinder until it vanishes.
var solid: float = 1.0
## Free-text, for the debug overlay and for test failures. Nothing branches on it.
var kind: String = "rock"


func _init(p_at: Vector2 = Vector2.ZERO, p_radius: float = 20.0,
		p_band: Vector2 = Vector2(0.0, 20.0), p_kind: String = "rock") -> void:
	at = p_at
	radius = maxf(p_radius, 0.0)
	band = Volume.between(p_band.x, p_band.y)
	kind = p_kind


## What is left of the footprint. Everything horizontal is measured against this
## rather than against `radius`, so wearing an object down narrows it.
func girth() -> float:
	return radius * clampf(solid, 0.0, 1.0)


func base() -> float:
	return band.x


func top() -> float:
	return band.y


func rise() -> float:
	return band.y - band.x


func gone() -> bool:
	return girth() <= GONE or rise() <= GONE


## How much room a foot of `foot_radius` has on top of this object at `where`.
##
## Positive is a foothold with that much margin around it; negative is a foot
## hanging off the edge by that much, and zero is a foot balanced exactly on the
## rim. It is a margin rather than a yes or no because a foot half off a ledge is
## a real situation and whoever is asking may have its own opinion about how much
## of a foot has to be on something before it counts as standing on it.
func foothold(where: Vector2, foot_radius: float) -> float:
	return girth() - where.distance_to(at) - foot_radius


## Whether a footprint of `disc_radius` at `where` overlaps this one at all,
## ignoring height. The horizontal half of every test below.
func covers(where: Vector2, disc_radius: float = 0.0) -> bool:
	var reach: float = girth() + disc_radius
	return where.distance_squared_to(at) <= reach * reach


## The displacement that would lift a disc at `where` clear of this object, or
## ZERO if it is already clear — horizontally *and* vertically. Both halves are
## needed and the second is what makes the object something a short animal walks
## under rather than into.
func push_disc(where: Vector2, disc_radius: float, disc_band: Vector2) -> Vector2:
	if gone() or not Volume.overlaps(band, disc_band):
		return Vector2.ZERO
	var delta: Vector2 = where - at
	var distance: float = delta.length()
	var overlap: float = girth() + disc_radius - distance
	if overlap <= 0.0:
		return Vector2.ZERO
	# Dead centre there is no direction to leave by. Any of them is as good as
	# any other and the choice has to be stable, so it is taken off the object
	# rather than off the thing being pushed — two bodies stacked on the same
	# pillar then leave it the same way instead of jittering against each other.
	if distance <= 0.0001:
		return Vector2.RIGHT.rotated(float(hash(at)) * 0.0001) * overlap
	return delta / distance * overlap


## The same, for something longer than it is wide: a limb bone, a stretch of
## spine, a set of jaws reaching across. Returns the push for the capsule.
func push_capsule(a: Vector2, b: Vector2, capsule_radius: float,
		capsule_band: Vector2) -> Vector2:
	if gone() or not Volume.overlaps(band, capsule_band):
		return Vector2.ZERO
	return push_disc(a.lerp(b, AnatomyState.segment_u(at, a, b)), capsule_radius,
		capsule_band)


## Whether a straight line from `from` to `to`, at the heights in `line_band`,
## runs into this object. What "obstructed" means for a set of jaws reaching for
## something on the far side of a rock — and it is the same two questions again,
## which is why there is no separate line-of-sight geometry anywhere.
func blocks(from: Vector2, to: Vector2, line_band: Vector2) -> bool:
	if gone() or not Volume.overlaps(band, line_band):
		return false
	var u: float = AnatomyState.segment_u(at, from, to)
	# Only genuinely between the two ends. An object behind the mouth or beyond
	# the target is not in the way of anything.
	if u <= 0.0001 or u >= 0.9999:
		return false
	return from.lerp(to, u).distance_to(at) < girth()


## Where this object is drawn: its footprint carried up the screen by however
## high the point being drawn is. World objects are registered to the world's own
## ground plane rather than to any animal's, which is what keeps a rock still
## while a creature walks past it.
func drawn(height: float) -> Vector2:
	return at + Posture.drop(height, 0.0)


func describe() -> String:
	return "%s r%.0f %s" % [kind, girth(), Volume.describe(band)]
