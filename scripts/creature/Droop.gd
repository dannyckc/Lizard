## What the back does about its own weight where nothing is holding it up.
##
## Every height in this simulation so far has been a height something is *holding*.
## The legs hold the shoulders and the hips, and `Gait` measures that off the feet;
## the neck holds the head, and `Stature` reads that off the species' neck; the
## whole body is held off the ground by the four corners underneath it. Each of
## those is a support, and between two supports a back is level because a back
## between two supports *is* level.
##
## Past the last one it is not, and that is the gap this file closes. A tail is a
## cantilever: it is joined to the animal at the hips and joined to nothing at all
## after that, so what happens along its length is a competition between the weight
## hanging off each station and what the vertebrae and the muscle at that station
## can hold against it. Nothing else. There is no tail-droop parameter, no rest
## pose and no idle animation, because none of those could ever be contradicted by
## the animal — and being contradictable by the animal is the whole point:
##
##   * a heavy tail on a slight animal sags, and a light one does not;
##   * a tail sags most at the tip, because the tip is the thinnest section
##     carrying the longest lever of everything behind it — which is why the curve
##     comes out as a curve and not as a droop angle;
##   * a back broken at the pelvis drops the tail *there* and nowhere else, because
##     the vertebra that was holding it is what has gone;
##   * an animal that has stopped driving itself lays its tail on the floor, and it
##     does not need to be told to, because the muscle holding it up has stopped;
##   * and a creature in the air trails its tail below itself, because the ground
##     that was catching it is no longer under it.
##
## Three things hold a tail up, and the file reads all three rather than choosing
## between them — see `_tone`. The skeleton is what makes holding it up *possible*,
## the muscle is what does the holding, and moving is what makes an animal do it:
## a tail is a balance organ, so a creature that is running is using it and a
## creature standing still is letting it hang. Take any one of the three away and
## the other two still answer.
##
## Two conventions worth stating, because both are load-bearing elsewhere:
##
##   * The profile is **absolute** world height, in the same pixels as x and y, with
##     the creature's elevation already in it. Everything that reads a height in
##     this game is quoted that way, and a profile that was relative to the back
##     would be one more frame for a consumer to get wrong.
##   * It is sampled **by fraction along the clipped spine**, the same 0-to-1 the
##     girdles, the body plan and the region lookup are all addressed in. The
##     lattice, the silhouette and the spine all have different numbers of stations
##     and they must not each get a different answer.
class_name Droop
extends RefCounted

## How far a back bends for what is hanging off it.
##
## The one calibration constant in the file, and it is a property of vertebrate
## backs rather than of any species here: everything else on the right-hand side is
## a length, a volume or a fraction the body already reports.
##
## What it is sized against is the spread the existing builds already have, and the
## spread is the argument for it. At this value a Lizard — long-tailed, low-backed,
## barely off the floor to begin with — trails its tail tip about halfway to the
## ground, and a Cat and an Elephant, both of which carry short thick tails on high
## backs, droop a couple of pixels and no more. Nothing was said about any of them.
## The same number over the same expression produced all three, because a tail's
## own weight against its own section is what the difference between those animals
## actually is.
##
## Note that it never needs re-tuning for scale: the load on a station goes as the
## cube of the body and the section resisting it goes as the cube of the body, so a
## creature drawn twice the size sags twice as far in pixels and exactly as far as
## a fraction of itself. See `update`.
const LIMBER: float = 0.02

## Least section a station is allowed to be treated as having, in world pixels.
## A tail tapers to a point, and a point has no strength at all — without a floor
## the last station divides by nothing and the tip goes to infinity.
const MIN_SECTION: float = 1.5

## How much of a station's hold survives when the muscle behind it has stopped
## entirely. Not zero: a dead animal's tail is limp, but its vertebrae are still
## vertebrae and a spine is not a rope. What this buys is a carcass whose tail lies
## in a slack curve rather than folding at the hips.
##
## Low enough that an ordinary tail actually reaches the floor, because that is
## what a limp one does and reaching it is the visible half of dying. It cannot
## overshoot: every station is clamped to the surface as the walk passes it, so a
## tail limper than it needs to be simply touches down sooner and trails from
## there — which is the shape a carcass's tail has.
const DEAD_HOLD: float = 0.05

## How much of the hold is the animal actively using its tail, against how much is
## simply the tissue being there. A moving creature carries its tail; a still one
## lets it hang, and the difference between those two is this term.
const CARRIAGE: float = 0.45

## Height of the axial line at each station of the clipped spine, absolute. One
## entry per spine point up to `last_index`, so it is indexed exactly as the
## silhouette's own arrays are.
var heights: PackedFloat32Array = PackedFloat32Array()
## How far the tip has fallen below the back it hangs off. Nothing in the solve
## needs it; it is what a test, a HUD or a species readout asks, and it is the one
## number that says at a glance whether this animal carries its tail.
var tip_sag: float = 0.0
## Where along the spine the last thing holding the body up is — the hip socket,
## as a fraction. Everything before it is held; everything after it hangs.
##
## The socket rather than the back of the pelvis, and the distinction is worth
## stating because `BodyPlan.tail_t` answers a neighbouring question differently.
## That one is where the *tail* begins as a structure, which is behind the pelvic
## block; this is where the last upward force on the body is applied, which is the
## joint the leg pushes through. How much of the pelvis behind it bends is then
## not declared at all — it is the thickest section on the back half of the animal
## and `hold` below cubes it, so the block comes out rigid because it is stout
## rather than because anything said so.
var anchor: float = 0.0


## Re-derives the whole profile from the pose, the tissue and what the animal is
## doing.
##
## Runs after the stature, because the height it hangs from is the height the legs
## have measured, and before the lattice, because the lattice stamps these heights
## onto the cells. `held` is that height — the back the tail is joined to — and
## `surface` is what is under the animal, so a tail that reaches the ground lies on
## it rather than continuing through it.
##
## The whole solve is one walk from the hind girdle to the tail tip, carrying two
## running totals: how much body is still to come, and how far the back has turned
## by the time it gets here. There is no iteration and no second pass, because a
## cantilever has no upstream — nothing behind a station can change what the
## stations in front of it are doing.
func update(body: BodyShape, spine: Spine, p: CreatureParams, state: BodyState,
		held: float, surface: float, speed_norm: float, standing: bool) -> void:
	var last: int = mini(body.last_index, spine.size() - 1)
	if heights.size() != last + 1:
		heights.resize(last + 1)
	tip_sag = 0.0
	anchor = clampf(p.rear_limb_t, 0.0, 1.0)
	if last < 1 or body.widths.size() <= last:
		heights.fill(held)
		return

	# Everything from the snout to the hind girdle is held by something else and is
	# not this file's business — the legs carry the trunk and the neck carries the
	# head, and both have already answered. Filling them with the back's own height
	# is not a claim about them; it is this file declining to make one.
	var hip: int = clampi(int(round(anchor * float(last))), 0, last)
	for i in range(hip + 1):
		heights[i] = held

	# How much body lies beyond each station: the same chain of discs the mass is
	# measured off, accumulated from the tip backward so each station knows exactly
	# what it is carrying. A tail switched off has no stations to walk and this loop
	# does not run — which is right, and is also why nothing needs to ask whether
	# the creature has one.
	var beyond: PackedFloat32Array = PackedFloat32Array()
	beyond.resize(last + 1)
	beyond[last] = 0.0
	for i in range(last - 1, hip - 1, -1):
		var w: float = (body.widths[i] + body.widths[i + 1]) * 0.5
		var seg: float = spine.points[i].distance_to(spine.points[i + 1])
		beyond[i] = beyond[i + 1] + w * w * seg

	# ...and then the walk. `slope` is the gradient of the back at this station, in
	# world height per world pixel — the same unit `Gait.pitch` is quoted in, and
	# for the same reason: a body's attitude is a gradient rather than an angle.
	var slope: float = 0.0
	var span: float = float(maxi(last, 1))
	var body_length: float = maxf(spine.points[0].distance_to(spine.points[last]), 1.0)
	for i in range(hip, last):
		var seg: float = spine.points[i].distance_to(spine.points[i + 1])
		var w: float = maxf(body.widths[i], MIN_SECTION)
		# What this station can hold, and it is a *section* rather than a strength
		# parameter: bending resistance goes as the cube of the depth of the beam, so
		# a thick-based tail is enormously stiffer at the root than at the tip and the
		# curve falls out of that alone. Scaled by how much of the vertebra and the
		# muscle around it is still there and still answering.
		var hold: float = w * w * w * _tone(state, float(i) / span, speed_norm, standing)
		# The moment this station is under: the weight still to come, on the lever of
		# how far there is left to come on. Normalised by the animal's own length so
		# a spine cut into more segments bends by the same total amount — the sag is a
		# property of the body, not of how finely it happens to be strung.
		slope += LIMBER * beyond[i] / maxf(hold, 0.0001) * (seg / body_length)
		# A tail cannot push itself back up through the floor. The clamp is what makes
		# a heavy tail *lie* on the ground and drag rather than pass through it, and
		# it is applied per station so a tail can touch down partway along and trail
		# from there — which is what a long one does.
		heights[i + 1] = maxf(heights[i] - slope * seg, surface)
	tip_sag = maxf(held - heights[last], 0.0)


## How much of this station is holding anything, 0..1.
##
## The three answers the file header names, multiplied out rather than chosen
## between, because they are three different ways for a tail to end up on the
## floor and an animal can be suffering any combination of them:
##
##   * **skeletal structure** — the vertebrae at this station. A back ground
##     through has nothing to hold a moment with, whatever the muscle wants.
##   * **muscle force** — the epaxial muscle and the nerve reaching it. This is
##     what makes death read the way it does: the animal stops driving itself and
##     the tail comes down, in the same second, with nothing in the collapse path
##     mentioning tails.
##   * **active movement** — a tail is a balance organ, so an animal using it is
##     holding it up. A creature standing still lets it hang a little lower, which
##     is the difference between a lizard at rest and one running.
##
## An animal with no functional state at all reads as sound, because a creature
## that has not been hurt has nothing to look up.
func _tone(state: BodyState, t: float, speed_norm: float, standing: bool) -> float:
	var tissue: float = 1.0
	if state != null:
		var region: BodyState.Region = state.axial_at(t)
		if region != null:
			# Bone decides how much the joint can be held; muscle and nerve decide how
			# much is holding it. Exactly the reading the spine solver takes at the
			# same station — see Creature._axial_tone — because a back that has gone
			# slack for the walk has gone slack for its own weight too.
			tissue = clampf(minf(region.stability,
				region.muscle * region.control), 0.0, 1.0)
	# Nothing driving the body means nothing holding the tail out, and what is left
	# is the skeleton alone.
	if not standing:
		return maxf(tissue * DEAD_HOLD, 0.0001)
	var carried: float = lerpf(1.0 - CARRIAGE, 1.0, clampf(speed_norm, 0.0, 1.0))
	return maxf(tissue * carried, 0.0001)


## The height of the axial line at a fraction along the clipped spine.
##
## The one way anything outside this file reads it. Interpolated rather than
## rounded, because the lattice samples the body at its own station count and a
## stepped profile would come out as a stepped tail.
func at(t: float) -> float:
	var n: int = heights.size()
	if n == 0:
		return 0.0
	if n == 1:
		return heights[0]
	var s: float = clampf(t, 0.0, 1.0) * float(n - 1)
	var i: int = clampi(int(s), 0, n - 2)
	return lerpf(heights[i], heights[i + 1], s - float(i))
