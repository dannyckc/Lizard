## The height every part of a body occupies, and the height its jaws can reach.
##
## The companion to Physique, and built on exactly the same terms: not a set of
## sliders, but a reading taken off the body that is already being solved. The
## legs decide how far off the ground the torso is, the posture decides how deep
## that torso is for its width, the neck decides how much higher the head rides,
## and the gape decides how much further than the head the mouth gets. Nothing
## here is authored, which is why a creature rebuilt with longer legs is taller
## without anyone having said so, and why a chewed-down one is not.
##
## Bands are `Vector2(low, high)` in world pixels above the ground plane — the
## same unit as x and y, so a leap, a body and a wing are all drawn and measured
## to one scale. Everything is quoted absolutely, with the creature's current
## elevation already folded in, because every consumer wants the answer in the
## world rather than relative to a body they would then have to locate.
##
## The one rule the whole 2.5D layer rests on lives here as three lines:
## `overlaps`. An attack lands when its reach overlaps what it is aimed at; two
## bodies collide when their occupied heights overlap; a mouth eats what its
## band covers. Horizontal testing is untouched everywhere — this is a second
## question asked after it, never a replacement for it.
class_name Stature
extends RefCounted

## A band that overlaps everything. The default on anything that has not been
## given a height, so a caller that knows nothing about elevation behaves exactly
## as it did before this layer existed.
##
## Aliased from Volume rather than restated, along with `overlaps` at the bottom
## of this file. Volume owns what a height band *is* and what it means for two of
## them to touch; this file owns only which bands a body has. There must be
## exactly one description of the rule, or the day the two drift apart is the day
## a creature can bite something it cannot collide with.
const UNBOUNDED := Volume.UNBOUNDED

## How far above the resting head a bite reaches on top of the neck's own sweep,
## as a multiple of the gape. The jaws are the last link in the chain and they
## open upward as well as forward.
const GAPE_REACH: float = 1.0

## Belly height: the bottom of the torso.
var clearance: float = 0.0
## Vertical thickness of the torso — how deep the animal is, not how wide.
var depth: float = 0.0
## Height of the middle of the torso. The plane the view is registered to, so a
## grounded creature is drawn exactly where the simulation puts it and only the
## parts above and below it are displaced.
var reference: float = 0.0
## Centre height of the head.
var head_height: float = 0.0

## Occupied bands, absolute. `whole` is their union — what another body has to
## reach to touch this one anywhere.
var torso: Vector2 = Vector2.ZERO
var head: Vector2 = Vector2.ZERO
var limbs: Vector2 = Vector2.ZERO
var whole: Vector2 = Vector2.ZERO
## Torso and head together: the part of the animal the spine actually draws, and
## so the band the body-against-body contact walk is asking about. Kept apart
## from `whole` because `whole` reaches down the legs to the floor, and a band
## that always touches the ground is a band that always collides — which is a
## body you can never walk underneath however high it is held.
var trunk: Vector2 = Vector2.ZERO
## What these jaws can be brought to bear on.
var bite: Vector2 = Vector2.ZERO
## Where the ground plane sits for this creature right now — zero, unless it is
## off it.
var elevation: float = 0.0


## Re-derives every band from the pose, the posture and the current height.
##
## `gape` is the radius of the arc the teeth are set in, which is the last piece
## of reach between the head and what it bites. `body_length` sizes the neck,
## because a neck is a fraction of an animal rather than a fixed number of
## pixels.
## `standing` is whether anything is holding the body up. A carcass is not on its
## legs — it is lying on the ground with them splayed around it — so it keeps its
## thickness and loses its clearance, and everything that could only reach a live
## elephant's knees can reach a dead one's skull. Nothing else about it changes,
## which is the point: it is the same body, differently supported.
##
## `held` is the height the four feet are *actually* holding the body at, which is
## the posture's answer only while the animal is standing square. It is not a
## correction or a wobble laid over the top: a leg is a fixed length, so a foot
## further out is a body lower down, and reading the height off the feet rather
## than off the stance is what stops a walking creature floating above legs that
## cannot reach it. Left negative it falls back to what the posture asks for,
## which is what a body with no gait solved yet has to use.
func update(posture: Posture, body: BodyShape, p: CreatureParams, scale: float,
		body_length: float, height: float, gape: float, standing: bool = true,
		held: float = -1.0, extension: float = -1.0) -> void:
	elevation = maxf(height, 0.0)
	if posture == null or body == null or p == null or body.widths.is_empty():
		torso = Vector2(elevation, elevation)
		head = torso
		limbs = torso
		whole = torso
		bite = torso
		return

	# The legs hold the body up, so their projection out of the ground plane is
	# the animal's clearance. The longer pair, because a body sits at the height
	# of whatever is under its hips — a front pair that happens to be shorter tips
	# the animal forward rather than lowering the whole of it. Against the reach a
	# leg actually stands at rather than a locked-out one, for the reason Gait
	# gives at length: a standing animal's legs are bent.
	# `extension` is how extended the legs actually stand — the species' own
	# `stance_reach`, capped at what leaves the limb room to walk. Left out it
	# falls back to the uncapped trait, which is what a body with no locomotion
	# solved yet has to use.
	var reach: float = p.stance_reach if extension < 0.0 else extension
	clearance = posture.clearance(
		maxf(p.leg_length, p.arm_length) * scale * reach) if standing else 0.0
	if standing and held >= 0.0:
		clearance = held
	# Depth is read off the widest part of the trunk rather than off an average:
	# an animal is as tall through the chest as its chest is, and the taper fore
	# and aft of that is the silhouette's business rather than the height's.
	var widest: float = 0.0
	for i in mini(body.last_index + 1, body.widths.size()):
		widest = maxf(widest, body.widths[i])
	depth = widest * 2.0 * posture.depth_ratio
	reference = clearance + depth * 0.5

	# The head rides above the shoulder by whatever neck this species carries.
	# Quoted against body length so it means the same thing on any size of
	# animal, and so a long-necked browser is one number away. A neck holds a head
	# up; it does not hold one up off the floor, so a body that is not standing
	# has it laid down with the rest of itself.
	head_height = reference + (p.neck_lift * body_length if standing else 0.0)
	var head_half: float = maxf(body.head_radius, 0.5)

	torso = Vector2(clearance, clearance + depth) + Vector2(elevation, elevation)
	head = Vector2(head_height - head_half, head_height + head_half) \
		+ Vector2(elevation, elevation)
	# A limb runs from the foot on the ground to the socket on the flank, so it
	# is the one structure that spans the whole gap underneath the animal. That
	# is what makes a leg the only thing a low predator can reach on a tall one.
	limbs = Vector2(0.0, clearance + depth * 0.45) + Vector2(elevation, elevation)
	trunk = Vector2(minf(torso.x, head.x), maxf(torso.y, head.y))
	whole = Vector2(minf(trunk.x, limbs.x), maxf(trunk.y, limbs.y))

	# What the jaws reach. The neck sweeps them either side of where the head
	# rests, and the gape carries them a little further again.
	var sweep: float = posture.neck_reach * body_length + gape * GAPE_REACH
	var low: float = head_height - sweep
	var high: float = head_height + sweep
	# Standing on the ground, an animal can always put its mouth on it: it
	# crouches, it lowers its shoulder, it kneels. None of that is simulated and
	# none of it needs to be, because the interesting direction is upward — how
	# high a set of jaws reaches is what decides whether prey is out of reach,
	# and the floor is only ever the floor. Off the ground that stops being true
	# and the clamp goes with it, which is exactly why a flier has to come down
	# to something before it can bite it.
	if elevation <= 0.0:
		low = minf(low, 0.0)
	bite = Vector2(low, high) + Vector2(elevation, elevation)


## How tall the animal stands: the ground to the top of its back, ignoring
## whatever it is currently doing about height. The natural unit for anything
## quoted "per animal" — a leap, a step up, a thing it can see over.
func stand_height() -> float:
	return clearance + depth


## Whether two height bands touch at all. The whole vertical rule, and the only
## thing any consumer of this file is really asking for. See Volume, which owns
## it; this is here so the many callers that already hold a stature do not have
## to name a second class to ask the obvious question of it.
static func overlaps(a: Vector2, b: Vector2) -> bool:
	return Volume.overlaps(a, b)


## Screen offset for something at world height `h` on this body — see
## Posture.drop. The reference plane is a property of how tall the animal is, and
## every caller that needs one already has its stature.
func drop(h: float) -> Vector2:
	return Posture.drop(h, reference)
