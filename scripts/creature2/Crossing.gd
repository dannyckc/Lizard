## Whether a body can get past the thing in front of it, and by which of the three
## ways there are — Traversal's successor, reading the v2 gait.
##
## Nothing below names a species, a stance or a behaviour. There are four verdicts,
## read off six measurements of the animal asking — how high it holds its belly, how
## tall it stands, how high its shoulder is carried, what one leg can span, how high
## a step already lifts its foot, and how wide it stands — against three of the
## obstacle: where its underside is, where its top is, and how much ground it covers.
##
##   * **UNDER** — the whole animal fits beneath. The rule the contact pass already
##     applies, stated as an intention rather than as an absence.
##   * **OVER** — it crosses without its gait noticing, either because the foot
##     already comes up higher than this on an ordinary step, or because the thing is
##     narrower than its own stance and its feet fall either side of it.
##   * **MOUNT** — the top is a surface this animal can put a foot on and carry
##     itself onto. Three things have to be true at once:
##       1. **a foot cannot be raised above the joint that swings it** — which is
##          what stops a cat rising over another cat, and lets it get over a low
##          planted foot;
##       2. **a leg must still reach the ground it is leaving** — half way up the
##          animal is straddling, and the leg hanging off the trailing girdle has to
##          span the climb as well as the height it was already holding;
##       3. **there has to be somewhere to put the feet** — a surface narrower than
##          the animal's own track is one it would be balancing on a line on.
##   * **BLOCKED** — none of the above, which is what a wall is.
class_name Crossing
extends RefCounted

const BLOCKED: int = 0
## Nothing in the way: the top is at or below the ground being walked.
const CLEAR: int = 1
const UNDER: int = 2
const OVER: int = 3
const MOUNT: int = 4

const NAMES: Array[String] = ["blocked", "clear", "under", "over", "mount"]

## Headroom an animal keeps when it goes beneath something, as a share of how tall
## it stands. A body that fits by nothing at all is one whose back brushes the
## underside every time its gait bobs it, and the bob is a real excursion.
const HEADROOM: float = 0.08

## How much of its own track an animal has to get onto a surface before it counts as
## somewhere it could stand. Half, because that is one side's pair of feet.
const FOOTING_SHARE: float = 0.5

## How much of a climb the trailing sockets are carried up by while the animal is
## half on and half off. Half, because a quadruped straddling a step pitches about
## its own middle.
const STRADDLE_SHARE: float = 0.5


## Everything one body brings to the question, all of it measured rather than set.
class Body extends RefCounted:
	## Belly height: what an obstacle has to be under to be walked over untouched.
	var clearance: float = 0.0
	## Ground to the top of the back — what has to fit beneath an overhang.
	var stand: float = 0.0
	## How high the limb sockets are carried. The lower pair, because that is the
	## shoulder a foot has to be got above and the lower of the two binds first.
	var socket: float = 0.0
	## What one leg can span at its outright limit, through the air.
	var span: float = 0.0
	## How high an ordinary step already picks the foot up.
	var lift: float = 0.0
	var foot: float = 1.0
	## How far apart the feet stand across the body.
	var track: float = 1.0
	## How much the animal can lower its own sockets by folding its legs — what it
	## has to spend on a straddle, and why a build with pillars for legs climbs
	## differently from one with springs.
	var fold: float = 0.0

	func describe() -> String:
		return "clearance %.0f stand %.0f socket %.0f span %.0f lift %.0f track %.0f" \
			% [clearance, stand, socket, span, lift, track]


## Reads one off a solved v2 creature. Everything here already exists on the animal
## for other reasons — this only gathers it, and gathers the *binding* half of each
## pair rather than an average: a body is stopped by its shortest leg.
static func of(tread: Tread, loco: Locomotor, carriage: Carriage,
		spec: BodySpec, corpus: Corpus) -> Body:
	var b := Body.new()
	if tread == null or loco == null or carriage == null or spec == null:
		return b
	var fore: bool = spec.fore_leg_length <= spec.hind_leg_length
	var shortest: float = spec.limb_length(fore)
	var bind: Carriage.Joint = carriage.of(fore)
	b.span = shortest * bind.lock
	b.fold = shortest * maxf(bind.stand - bind.fold, 0.0)
	# Off the gait when it has measured one, because that is the height the feet are
	# actually holding the sockets at rather than the height the stance would like.
	# A crouching animal really can reach less far up.
	if tread.measured:
		b.socket = minf(tread.shoulder_height, tread.hip_height)
		b.stand = maxf(tread.shoulder_height, tread.hip_height)
	else:
		b.socket = carriage.stance_clearance(shortest, bind.stand, spec.stance_width,
			loco.foot_bias.x if fore else loco.foot_bias.y)
		b.stand = b.socket
	# The belly is the trunk's own flesh hanging under the girdle line — the census
	# knows how deep it is, so nothing here has to guess.
	var belly: float = corpus.girth(BodySchema.TRUNK,
		BodySchema.STATIONS[BodySchema.TRUNK] / 2) if corpus != null else 0.0
	b.clearance = maxf(b.socket - belly, 0.0)
	b.stand += belly
	var probe: Tread.Foot = tread.feet[0] if not tread.feet.is_empty() else null
	b.foot = probe.foot_size if probe != null else maxf(shortest * 0.10, 3.0)
	b.lift = loco.lift(b.socket, shortest) * carriage.step_height_gain
	# Measured between the two feet themselves rather than off one limb's stance,
	# and the difference is not small: a columnar animal's foot rests almost directly
	# beneath its own socket — that is what the stance *is* — but the sockets are out
	# on the flanks of a very broad body, so the base it balances on is most of its
	# own width and none of that width is in the limb's own offset.
	b.track = maxf(_foot_track(tread), b.foot * 2.0)
	return b


## How far apart this body's feet actually stand, across the widest pair that is on
## the ground. A measurement of the four feet, like everything else about how a body
## is being held up.
static func _foot_track(tread: Tread) -> float:
	var widest: float = 0.0
	for foot in tread.feet:
		for other in tread.feet:
			if other.fore != foot.fore or other.side == foot.side:
				continue
			widest = maxf(widest, foot.ground.distance_to(other.ground))
	return widest


## The verdict. `base` and `top` are the obstacle's own band, `breadth` how much
## ground it covers, and `ground` the height the animal is currently standing at — so
## a stack of two ledges is two ordinary crossings rather than a special case.
static func assess(b: Body, base: float, top: float, breadth: float,
		ground: float = 0.0) -> int:
	if b == null:
		return CLEAR
	var rise: float = top - ground
	if rise <= 0.0:
		return CLEAR
	# Room underneath first: it costs one comparison and it is the answer whenever it
	# is true. The headroom is the bob the animal's own walk puts in it.
	if base - ground >= b.stand * (1.0 + HEADROOM):
		return UNDER
	# Then the two crossings it already makes without noticing. A foot that comes up
	# this high anyway clears the thing on the step it was going to take...
	if rise + b.foot <= b.lift and rise < b.clearance:
		return OVER
	# ...and something narrower than the animal's own stance is something its feet
	# fall either side of, so it never has to be stepped *on*. The same width test the
	# mount makes, read the other way round.
	if rise < b.clearance and breadth * 2.0 <= b.track * FOOTING_SHARE:
		return OVER
	# And then the climb — all three conditions, and any one failing is a wall.
	if rise > b.socket + b.foot:
		return BLOCKED
	# ...less whatever the animal takes out of its own legs on the way. An animal
	# climbing lowers itself, which is not a trick: it is the fold the stance already
	# has, spent on the one thing it is for. Without it the condition says a body on
	# straight legs may never step onto anything, which is a true sentence about a leg
	# that cannot bend and the wrong one about an animal.
	if b.span < b.socket - b.fold + rise * STRADDLE_SHARE:
		return BLOCKED
	if breadth * 2.0 < b.track * FOOTING_SHARE:
		return BLOCKED
	return MOUNT


## Whether the animal gets past at all — the one thing a contact pass wants to know:
## something it can cross is not something to be pushed out of.
static func passable(verdict: int) -> bool:
	return verdict != BLOCKED


static func name_of(verdict: int) -> String:
	return NAMES[clampi(verdict, 0, NAMES.size() - 1)]
