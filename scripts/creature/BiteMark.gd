## The footprint one closing of a set of jaws leaves: where each tooth landed,
## how broad its contact patch was, and how deep it drove.
##
## This is the whole description of a bite that anything downstream is given.
## The tissue lattice erodes cells by asking the mark how deep it is over each
## of them, and the red impression the world draws is the same list of patches —
## so the shape stamped on the flesh is the shape that ate it. There is no
## second, cosmetic bite anywhere, and no way for the two to disagree.
##
## Deliberately free of any knowledge of teeth or jaws: Dentition decides what a
## mouthful of a particular animal looks like, and this only carries the answer.
class_name BiteMark
extends RefCounted

## Penetration profile across one contact patch, as an exponent on the distance
## in from its rim. Near zero is a flat face pressed in whole — a blunt cusp
## crushing — and above one is a point that collapses to its tip.
const BLUNT_PROFILE: float = 0.24
const KEEN_PROFILE: float = 1.55
## Profile of a torn-away mouthful. Not the flat face of a blunt cusp: flesh
## parting from a body gives most where the jaws hold it and least at the corners
## of the mouth, so the piece that comes away is rounded rather than punched.
const MOUTHFUL_PROFILE: float = 0.2


## One tooth's contact patch, in world space: an ellipse `half_along` down the
## jaw line by `half_across` over it, which is the difference between a shearing
## blade and a conical spike.
class Impression extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	## Unit vector along the jaw line at this tooth — the patch's long axis.
	var axis: Vector2 = Vector2.RIGHT
	var half_along: float = 1.0
	var half_across: float = 1.0
	## Peak penetration at the centre of the patch, in the lattice's hit points.
	var depth: float = 0.0
	## 0 a blunt cusp, 1 a needle. Sets how sharply penetration falls away from
	## the centre of the patch, not how much of it there is.
	var sharpness: float = 0.5
	var kind: int = 0
	var jaw: int = 0
	## True for the shallow broad patch the jaw itself bears with, false for the
	## puncture a tooth makes. Only the reason a patch exists differs — nothing
	## downstream treats the two differently, which is the point.
	var bearing: bool = false


var impressions: Array[Impression] = []
## Where the mark sits as a whole, and how far it reaches. This is what the
## world hit-tests, scores and deposits scent with — one bite is still one event
## landing in one place, however many teeth resolved it.
var center: Vector2 = Vector2.ZERO
var radius: float = 0.0
## Conservative world bounds, for rejecting a patch without a cell walk.
var lo: Vector2 = Vector2.ZERO
var hi: Vector2 = Vector2.ZERO


## The mark a mouthful parting from a body leaves, rather than one teeth closing
## on it. What comes away is the meat the jaws enclosed, so it is one rounded
## patch the width of the whole mouth, and whichever teeth happened to be in it
## had no say in its shape. Depth here is measured in flesh — see Creature's
## tearing constants — so nothing about the dentition prices it either.
static func mouthful(at: Vector2, forward: Vector2, radius: float, depth: float) -> BiteMark:
	var mark := BiteMark.new()
	var imp := Impression.new()
	imp.pos = at
	imp.axis = forward.normalized() if forward.length_squared() > 0.000001 else Vector2.RIGHT
	imp.half_along = maxf(radius, 0.001)
	imp.half_across = imp.half_along
	imp.depth = depth
	imp.sharpness = MOUTHFUL_PROFILE
	mark.add(imp)
	mark.close(at)
	return mark


func add(impression: Impression) -> void:
	impressions.append(impression)


func is_empty() -> bool:
	return impressions.is_empty()


## Re-derives the mark's own extent from the patches in it. Called once, after
## the last impression is added.
func close(at: Vector2) -> void:
	center = at
	radius = 0.0
	lo = at
	hi = at
	for imp in impressions:
		var reach: float = maxf(imp.half_along, imp.half_across)
		radius = maxf(radius, at.distance_to(imp.pos) + reach)
		lo = Vector2(minf(lo.x, imp.pos.x - reach), minf(lo.y, imp.pos.y - reach))
		hi = Vector2(maxf(hi.x, imp.pos.x + reach), maxf(hi.y, imp.pos.y + reach))


## How deep the mark is at one point — the deepest tooth over it, never their
## sum, because two teeth meeting over the same flesh are still one closing of
## one set of jaws.
func depth_at(at: Vector2) -> float:
	var deepest: float = 0.0
	for imp in impressions:
		deepest = maxf(deepest, _depth_of(imp, at))
	return deepest


## How deep the mark is over one cell of tissue.
##
## Sampling the cell's centre is the whole answer for any tooth broader than the
## flesh's own grain. It is not the answer for one finer than it: a needle
## landing inside a cell but away from its middle would read as having missed,
## which is exactly backwards — the finer the point, the deeper it goes, not the
## less likely it is to connect. So a patch whose centre falls within the cell
## marks it outright. The lattice cell is the smallest piece of flesh there is,
## and a puncture cannot destroy less than one.
##
## `corners` is the cell's four world corners, wound in order.
func depth_over(centre: Vector2, corners: PackedVector2Array) -> float:
	var deepest: float = 0.0
	for imp in impressions:
		var d: float = _depth_of(imp, centre)
		if d <= 0.0 and imp.depth > deepest and _contains(corners, imp.pos):
			d = imp.depth
		deepest = maxf(deepest, d)
	return deepest


func _depth_of(imp: Impression, at: Vector2) -> float:
	if imp.depth <= 0.0 or imp.half_along <= 0.0 or imp.half_across <= 0.0:
		return 0.0
	var local: Vector2 = at - imp.pos
	var along: float = local.dot(imp.axis) / imp.half_along
	var across: float = (local.y * imp.axis.x - local.x * imp.axis.y) / imp.half_across
	var q: float = along * along + across * across
	if q >= 1.0:
		return 0.0
	return imp.depth * pow(1.0 - sqrt(q),
		lerpf(BLUNT_PROFILE, KEEN_PROFILE, clampf(imp.sharpness, 0.0, 1.0)))


## Point-in-quad for a convex, consistently wound cell. Cells are quads by
## construction — see TissueGrid.Patch — so this needs no general polygon test.
static func _contains(corners: PackedVector2Array, at: Vector2) -> bool:
	if corners.size() < 4:
		return false
	var sign_seen: float = 0.0
	for i in 4:
		var a: Vector2 = corners[i]
		var edge: Vector2 = corners[(i + 1) % 4] - a
		var cross: float = edge.x * (at.y - a.y) - edge.y * (at.x - a.x)
		if absf(cross) < 0.000001:
			continue
		if sign_seen == 0.0:
			sign_seen = signf(cross)
		elif signf(cross) != sign_seen:
			return false
	return true
