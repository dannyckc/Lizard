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

## How much of the neck an animal carries is available *downward*, against what it
## is worth upward. Under one because a raised head has open air above it and the
## creature's own chest beneath it: a neck stoops under the body less far than it
## rears over it.
const NECK_STOOP: float = 0.5

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
## How much further this animal could still fold its legs — the difference
## between the height it is standing at and the height it would be at with the
## limbs drawn up as tight as the IK will solve them.
##
## It is the crouch, quoted as a distance rather than as an action, and it is the
## whole of why the downward half of `bite` is no longer clamped to the floor. An
## animal reaching for something below itself bends its legs; how far it gets is
## how much leg it has to bend, which is a fact about the body rather than a
## concession made on its behalf. A sprawled creature has almost none and needs
## almost none — its belly is already on the floor. A columnar one has a great
## deal, and spends every bit of it getting its mouth down to the ground.
var fold: float = 0.0
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
## `held` is the height the feet are *actually* holding the two girdles at —
## shoulders in x, hips in y. It is not a correction or a wobble laid over the
## top: a leg is a fixed length, so a foot further out is a socket lower down, and
## reading the height off the feet rather than off the stance is what stops a
## walking creature floating above legs that cannot reach it. Both ends are given
## rather than an average because a body's underside has to be below both of them
## — see `socket_hang`. Left negative it falls back to what the posture asks for,
## which is what a body with no gait solved yet has to use.
##
## Note that these are *socket* heights and not the belly. A shoulder is a joint
## on the flank of a round body, and the flesh inboard of it hangs lower.
##
## `loco` is what this body's joints can do; left out, the sprawled defaults
## answer, which is what a body with no locomotion solved yet has to use.
func update(posture: Posture, body: BodyShape, p: CreatureParams, scale: float,
		body_length: float, height: float, gape: float, standing: bool = true,
		held: Vector2 = Vector2(-1.0, -1.0), loco: Locomotion = null) -> void:
	elevation = maxf(height, 0.0)
	if posture == null or body == null or p == null or body.widths.is_empty():
		torso = Vector2(elevation, elevation)
		head = torso
		limbs = torso
		whole = torso
		bite = torso
		return

	# How high the sockets are being carried: what the feet have measured if they
	# have, and what the stance asks for if nothing has stood on them yet. It is
	# how extended the legs stand at the joint that decides the second one — see
	# Articulation — so a build whose limbs are pillars is held nearly a whole leg
	# up and one whose limbs are folded is not.
	var reach: float = loco.mean_extension() if loco != null else 0.78
	var bone: float = maxf(p.leg_length, p.arm_length) * scale
	var socket: float = posture.clearance(bone * reach) if standing else 0.0
	if standing and held.x >= 0.0:
		socket = (held.x + held.y) * 0.5
	# How much of that height the animal could still take out of its own legs —
	# and it is the joint's own fold rather than a floor every creature in the
	# game shares, which is the whole of why a heavy columnar build can no longer
	# put its mouth on the floor. Nothing forbids it: its knees do not close that
	# far. Nothing to fold when the body is not standing on its legs either — a
	# carcass is already down, and an animal in the air is not pushing against
	# anything, so bending its knees moves nothing but its knees.
	var tightest: float = loco.articulation.hind.fold if loco != null else Limb.REACH_MIN
	fold = maxf(socket - posture.clearance(bone * tightest), 0.0) \
		if standing and elevation <= 0.0 else 0.0
	# Depth is read off the widest part of the trunk rather than off an average:
	# an animal is as tall through the chest as its chest is, and the taper fore
	# and aft of that is the silhouette's business rather than the height's.
	var widest: float = 0.0
	for i in mini(body.last_index + 1, body.widths.size()):
		widest = maxf(widest, body.widths[i])
	depth = widest * 2.0 * posture.depth_ratio
	# ...and the belly hangs below the sockets, because a shoulder is a joint on
	# the flank of a round body rather than the lowest point of one.
	clearance = maxf(socket - socket_hang(body, posture, widest), 0.0)
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
	# The neck the *animal* carries, not only the one its stance implies. A neck is
	# a real length and it reaches both ways off it — the file has said so all
	# along, and then quoted the sweep off the posture alone, which is a browser
	# that can raise its head much higher than a lizard and cannot lower it any
	# further.
	#
	# Only part of it downward, though, and the asymmetry is the animal itself
	# being in the way: a neck raised off the shoulder has clear air above it and
	# its own chest below, so what it can swing under itself is a good deal less
	# than what it can lift. See NECK_STOOP. It is what lets a build whose legs are
	# pillars still get its mouth most of the way to the floor and then need the
	# last of its fold to arrive — which is exactly the animal that has almost no
	# fold, so it is the one this has to be right about.
	var sweep: float = (posture.neck_reach + p.neck_lift * NECK_STOOP) * body_length \
		+ gape * GAPE_REACH
	var high: float = head_height + sweep
	# Downward is three movements rather than one, and it used to be a clamp: an
	# animal standing on the ground was simply granted the ground, on the grounds
	# that the interesting direction was upward. It is not, and the clamp was
	# hiding the most legible height mechanic in the game — a tall animal reaching
	# for something at its feet.
	#
	# So the three, each of them a length this body already has:
	#
	#   * the head comes off its perch. A neck that holds a head above the
	#     shoulder can also bring it back down to one, and that descent is free —
	#     which is why the sweep is measured from the *back* rather than from the
	#     raised head, and why a long neck helps in both directions.
	#   * the neck sweeps below that, by its own reach and the gape.
	#   * and the legs fold, by however much of themselves they have left to give.
	#
	# A sprawled animal gets to the floor on the second alone and never notices;
	# a columnar one needs all three and only just manages; and an animal built
	# tall on a short neck genuinely cannot reach its own feet, which is a real
	# answer rather than a bug. Off the ground the legs stop counting — see
	# `fold` — which is exactly why a flier has to come down to something before it
	# can bite it.
	var low: float = reference - sweep - fold
	bite = Vector2(low, high) + Vector2(elevation, elevation)


## How far below the limb sockets the belly hangs.
##
## A shoulder is not the lowest point of a body. It is a joint out on the flank,
## a good way up the side of a round trunk, and what hangs lowest is the flesh
## inboard of it — so the two are a fixed distance apart, and the distance is a
## fact about the cross-section rather than about the legs: the depth the body
## has at its deepest, less how much of that depth is still there at the socket's
## own lateral offset. The cross-section is an ellipse, so that second term is the
## same `sqrt(1 - u²)` the lattice tapers every cell with, and neither of them
## gets to choose otherwise.
##
## Which is the whole of why a limb no longer floats under its own body. Before
## this the two were the same number: a body was drawn with its underside at the
## height its legs were holding, and every socket was then placed out on the flank
## at that same height — which is *below* the ellipse, in the air, a good part of
## a depth beneath the tissue the limb was supposed to be joined to. Nothing
## looked wrong from directly overhead, because the torso is drawn over the legs;
## everything was wrong in the volume, and the lattice's limb cells, the skeleton
## through them and the nerve and vessel beside it all began in mid-air.
##
## Taken over both girdles and the deepest of them wins, because both have to be
## attached and the body has only one underside.
func socket_hang(body: BodyShape, posture: Posture, widest: float) -> float:
	var deepest: float = 0.0
	for pair in 2:
		var key: String = "FL" if pair == 0 else "RL"
		var half: float = float(body.socket_half.get(key, 0.0))
		if half <= 0.0:
			continue
		# How far out along its own cross-section this socket sits, as a fraction
		# of the half-width there — which is what the ellipse is asked about.
		var u: float = clampf(float(body.socket_out.get(key, 0.0)) / half, 0.0, 1.0)
		var here: float = half * posture.depth_ratio * sqrt(maxf(1.0 - u * u, 0.0))
		deepest = maxf(deepest, widest * posture.depth_ratio - here)
	return deepest


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
