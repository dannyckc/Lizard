## The two positional constraints every other system is built out of.
##
## Both are "projection" style: they take a point that has drifted into an
## illegal configuration and move it to the nearest legal one. Nothing here
## knows about time or velocity — the caller runs them repeatedly (relaxation)
## until the whole chain is consistent.
class_name Constraints
extends RefCounted


## Pushes `p` onto the circle of radius `radius` centred on `center`.
## This is the whole of the distance constraint: a point that must stay a fixed
## distance from an anchor can only ever live on that circle, so we snap it to
## the closest spot on it, which is along the anchor->point ray.
static func project_to_circle(p: Vector2, center: Vector2, radius: float) -> Vector2:
	var d: Vector2 = p - center
	var l: float = d.length()
	if l < 0.00001:
		# Degenerate: the point sits exactly on the anchor and has no direction
		# to be pushed along. Pick an arbitrary one so the chain never collapses.
		return center + Vector2.RIGHT * radius
	return center + d * (radius / l)


## Distance constraint with a softness term.
##
## `anchor` is treated as immovable and only `p` is corrected, which is what we
## want for a head-driven chain: corrections always flow from the head backwards
## and never shove the head around.
##
## `stiffness` is the fraction of the error removed per call. 1.0 satisfies the
## constraint immediately (rigid); lower values leave residual error that later
## relaxation passes eat away, which reads as a soft, slightly stretchy body.
static func solve_distance(anchor: Vector2, p: Vector2, rest_length: float, stiffness: float) -> Vector2:
	var goal: Vector2 = project_to_circle(p, anchor, rest_length)
	return p.lerp(goal, clampf(stiffness, 0.0, 1.0))


## Angle constraint over three consecutive points a -> b -> c.
##
## Measures the turn between the incoming segment (a->b) and the outgoing one
## (b->c) and, if it exceeds `max_bend` radians, rotates `c` about `b` until it
## is exactly at the limit. This is what stops the spine folding back on itself,
## reversing direction in a single joint, or collapsing to a point.
##
## Crucially the correction is a *rotation about b*, so |c - b| is unchanged:
## fixing the angle can never break a distance constraint that was already
## satisfied for the same pair. That is why one front-to-back pass which
## interleaves distance-then-angle per joint is enough to satisfy both.
static func solve_angle(a: Vector2, b: Vector2, c: Vector2, max_bend: float) -> Vector2:
	var incoming: Vector2 = b - a
	var outgoing: Vector2 = c - b
	if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
		return c
	var delta: float = wrapf(outgoing.angle() - incoming.angle(), -PI, PI)
	if absf(delta) <= max_bend:
		return c
	var clamped: float = clampf(delta, -max_bend, max_bend)
	return b + outgoing.rotated(clamped - delta)
