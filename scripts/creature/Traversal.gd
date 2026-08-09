## Whether a body can get past the thing in front of it, and by which of the
## three ways there are.
##
## This is the file the vertical layer was missing. Height already decided
## whether two things were in each other's way; nothing decided what a creature
## could *do* about one that was. The answer has to be procedural or it is worth
## nothing: the moment "a lizard climbs over a body part" is written down as a
## rule about lizards, a cat rears up over another cat the instant they touch and
## an elephant scrambles onto a boulder it should have walked around.
##
## So nothing below names a species, a posture or a behaviour. There are four
## verdicts and they are read off six measurements of the animal asking — how
## high it holds its belly, how tall it stands, how high its shoulder is carried,
## what one leg can span, how high a step already lifts its foot, and how wide it
## stands — against three of the obstacle: where its underside is, where its top
## is, and how much room there is up there for a foot.
##
##   * **UNDER** — the whole animal fits beneath. It is the rule the collision
##     pass already applies, stated as an intention rather than as an absence:
##     two things at different heights are not in each other's way.
##   * **OVER** — the creature crosses it without its gait noticing, either
##     because the foot already comes up higher than this on an ordinary step, or
##     because the thing is narrower than the animal's own stance and its feet
##     simply fall either side of it. Kerbs, posts, pellets, a planted foot.
##   * **MOUNT** — the top is a surface this animal can put a foot on and carry
##     itself onto. Three things have to be true at once, and they are the three
##     that make a lizard and an elephant answer differently about the same rock.
##   * **BLOCKED** — none of the above. The creature meets it and is stopped,
##     which is what a wall is.
##
## The three conditions on a mount are worth stating plainly, because between
## them they are the whole mechanic:
##
##   1. **A foot cannot be raised above the joint that swings it.** A quadruped
##      that stays on four legs reaches the top of something with its foot, and
##      its foot goes as high as its shoulder and no higher. This is what stops a
##      cat rising over another cat: a cat's back is twice the height its own
##      shoulder is carried at, so there is nothing there it can reach with a
##      foot. It is also why a lizard *can* get over a low body part: another
##      animal's planted foot sits below its shoulder, so it goes over that.
##   2. **A leg must still reach the ground it is leaving.** Half way up, the
##      animal is straddling: the front feet are on the surface and the rest are
##      still on the floor, so the back pitches and every socket between the two
##      ends is carried part of the way up. The leg hanging off it has to span
##      that as well as the height it was already holding — and how much leg is
##      left over is the difference between an animal that steps up and one that
##      is standing at its own limit already.
##   3. **There has to be somewhere to put the feet.** A surface narrower than
##      the animal's own track is a surface it would be balancing on a line on,
##      and a creature does not balance on a line — the same argument
##      `Locomotion.STANCE_FLOOR` makes about a stance squeezed too narrow.
##
## Every one of the three is a sentence about anatomy. None of them is a sentence
## about what kind of animal it is.
class_name Traversal
extends RefCounted

const BLOCKED: int = 0
## Nothing in the way: the obstacle's top is at or below the ground being walked.
const CLEAR: int = 1
const UNDER: int = 2
const OVER: int = 3
const MOUNT: int = 4

const NAMES: Array[String] = ["blocked", "clear", "under", "over", "mount"]

## Headroom an animal keeps when it goes beneath something, as a share of how
## tall it stands. A body that fits underneath by nothing at all is one whose
## back brushes the underside every time its gait bobs it, and the bob is a real
## excursion — see `Locomotion.STRIDE_SINK`, which is the same fraction of the
## same height from the other side.
const HEADROOM: float = 0.08

## How much of its own track an animal has to get onto a surface before it counts
## as somewhere it could stand. Half, because that is one side's pair of feet:
## less than this and the far pair has nothing under it and the animal is
## balancing rather than standing.
const FOOTING_SHARE: float = 0.5

## How much of a climb the trailing sockets are carried up by while the animal is
## half on and half off. Half, because a quadruped straddling a step pitches about
## its own middle: the shoulders are up on the surface, the hips are still on the
## floor, and the sockets between them are somewhere in between. It is what turns
## the second mount condition from a statement about the belly into one about the
## leg that is actually being asked to stretch.
const STRADDLE_SHARE: float = 0.5


## Everything one body brings to the question, and it is all measured rather than
## set. Built by `of()` off a creature that has already been solved this tick, so
## a damaged animal — shorter reach, a leg that will not take weight, a body held
## lower than its posture asks for — answers with the body it currently has.
class Body extends RefCounted:
	## Belly height: what an obstacle has to be under for the animal to walk over
	## it without touching it.
	var clearance: float = 0.0
	## Ground to the top of the back. What has to fit beneath an overhang.
	var stand: float = 0.0
	## How high the limb sockets are carried. The lower pair, because that is the
	## shoulder a foot has to be got above, and the lower of the two binds first.
	var socket: float = 0.0
	## What one leg can span at its outright limit, through the air. The shorter
	## pair again, and for the same reason.
	var span: float = 0.0
	## How high an ordinary step already picks the foot up. Anything under this is
	## crossed by the gait the animal already has, with nothing adapted at all.
	var lift: float = 0.0
	## The foot's own radius: how much of a ledge one has to land on, and how far
	## above a surface the ankle sits when it is standing on it.
	var foot: float = 1.0
	## How far apart the feet stand across the body — the width of the base the
	## animal balances on.
	var track: float = 1.0

	func describe() -> String:
		return "clearance %.0f stand %.0f socket %.0f span %.0f lift %.0f track %.0f" \
			% [clearance, stand, socket, span, lift, track]


## Reads one off a creature. Everything here already exists on the animal for
## other reasons — this only gathers it, and gathers the *binding* half of each
## pair rather than an average: a body is stopped by its shortest leg.
static func of(creature: Node) -> Body:
	var b := Body.new()
	if creature == null:
		return b
	var stature: Stature = creature.stature
	var posture: Posture = creature.posture
	var p: CreatureParams = creature.params
	if stature == null or posture == null or p == null:
		return b
	var scale: float = creature.size_scale
	var arm: float = p.arm_length * scale
	var leg: float = p.leg_length * scale
	var shortest: float = minf(arm, leg)
	b.clearance = stature.clearance
	b.stand = stature.stand_height()
	b.span = shortest * p.limb_max_reach
	# Off the gait when it has measured one, because that is the height the feet
	# are actually holding the sockets at rather than the height the stance would
	# like them to be. A crouching animal really can reach less far up.
	var gait: Gait = creature.gait
	if gait != null and gait.measured:
		b.socket = minf(gait.shoulder_height, gait.hip_height)
	else:
		b.socket = posture.clearance(shortest * creature.locomotion.extension)
	if gait != null and not gait.limbs.is_empty():
		var limb: Limb = gait.limbs[0]
		b.foot = limb.foot_radius(scale)
		b.lift = creature.locomotion.lift(b.socket, limb.anatomical_length) \
			* posture.step_height_gain
		# Measured between the two feet themselves rather than off one limb's
		# stance, and the difference is not small. A columnar animal's foot rests
		# almost directly beneath its own socket — that is what the stance *is* —
		# but the sockets are out on the flanks of a very broad body, so the base it
		# actually balances on is most of its own width and none of that width is
		# in the limb's own offset. Read off the stance alone an elephant appears to
		# stand on a line a couple of feet wide, and would then decline to walk over
		# anything narrower than a dinner plate.
		b.track = maxf(_foot_track(gait), b.foot * 2.0)
	else:
		b.foot = maxf(shortest * 0.10, 3.0 * scale)
		b.lift = creature.locomotion.lift(b.socket, shortest) * posture.step_height_gain
		b.track = maxf(posture.track(shortest) * 2.0, b.foot * 2.0)
	return b


## How far apart this body's feet actually stand, taken across the widest pair
## that is on the ground. A measurement of the four feet, like everything else
## about how a body is being held up.
static func _foot_track(gait: Gait) -> float:
	var widest: float = 0.0
	for limb in gait.limbs:
		if limb.severed or limb.carried:
			continue
		for other in gait.limbs:
			if other.pair != limb.pair or other.side == limb.side \
					or other.severed or other.carried:
				continue
			widest = maxf(widest, limb.plan[2].distance_to(other.plan[2]))
	return widest


## The verdict. `base` and `top` are the obstacle's own band, `breadth` is how
## much ground it covers, and `ground` is the height the animal is currently
## standing at — zero on the floor, and whatever it has already climbed onto
## otherwise, so a stack of two ledges is two ordinary crossings rather than a
## special case.
static func assess(b: Body, base: float, top: float, breadth: float,
		ground: float = 0.0) -> int:
	if b == null:
		return CLEAR
	var rise: float = top - ground
	if rise <= 0.0:
		return CLEAR
	# Room underneath first, because it costs one comparison and it is the answer
	# whenever it is true — an animal that fits beneath something never had a
	# crossing to consider. The headroom is the bob its own walk puts in it.
	if base - ground >= b.stand * (1.0 + HEADROOM):
		return UNDER
	# Then the crossings it already makes without noticing, of which there are two
	# and both leave the gait completely untouched.
	#
	# A foot that comes up this high anyway clears the thing on the step it was
	# going to take, and a belly that rides above it never meets it. That is one.
	if rise + b.foot <= b.lift and rise < b.clearance:
		return OVER
	# And the other is the one a foot never touches at all: something narrower than
	# the animal's own stance is something its feet fall either side of, so it does
	# not have to be stepped *on* however high a step this body takes — only walked
	# over, which anything with its belly above it does for nothing. It is the same
	# width test the mount makes, read the other way round: too narrow to stand on
	# is also too narrow to be in the way.
	if rise < b.clearance and breadth * 2.0 <= b.track * FOOTING_SHARE:
		return OVER
	# And then the climb. All three conditions, and any one of them failing is a
	# wall — see the header for what each of them is a sentence about.
	if rise > b.socket + b.foot:
		return BLOCKED
	if b.span < b.socket + rise * STRADDLE_SHARE:
		return BLOCKED
	if breadth * 2.0 < b.track * FOOTING_SHARE:
		return BLOCKED
	return MOUNT


## Whether the animal gets past at all. The one thing the contact pass wants to
## know: something it can cross is not something to be pushed out of.
static func passable(verdict: int) -> bool:
	return verdict != BLOCKED


static func name_of(verdict: int) -> String:
	return NAMES[clampi(verdict, 0, NAMES.size() - 1)]
