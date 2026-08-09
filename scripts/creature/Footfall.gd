## Which foot goes next, how many may be off the ground at once, and how far
## apart in the cycle the four of them are held.
##
## The fourth derived descriptor, and the one that was missing. `Physique` reads
## how much animal there is, `Stature` how tall it stands, `Locomotion` how far
## and how fast it can move a leg — and every one of those was already a
## consequence of the body rather than a setting. What none of them answered is
## the question that actually separates one animal's walk from another's: *in
## what order do the feet come down*. Without it every creature in the game trotted:
## the diagonal pairs were wired into the limb at construction and the only thing
## a posture could change was how far and how fast each of the four moved. An
## Elephant was a Lizard with longer legs and a slower beat, which is exactly what
## it looked like.
##
## A footfall pattern is three numbers, and every terrestrial gait is a point in
## that space:
##
##   * `girdle_lag` — how far after the hind girdle the fore girdle follows.
##     0 is a pace (the legs on one side move together), ¼ is the lateral-sequence
##     walk nearly every heavy quadruped uses, ½ is a trot.
##   * `hind_split` and `fore_split` — how far apart the two limbs *within* a
##     girdle are. ½ is alternating, which is what standing on your legs one at a
##     time means; 0 is the pair working as one, which is a bound, a hop or a
##     pronk depending on what the other girdle is doing.
##
## That is the whole vocabulary. A trot, a pace, an amble, a lateral-sequence
## walk, a transverse gallop, a rotary gallop, a bound, a half-bound, a two-legged
## stride and a two-legged hop are all read off the same three numbers, so none of
## them is a mode, a preset or a name anything checks for.
##
## And the three are derived, not authored. What sets them:
##
##   * **Froude number.** `v² / g·h`, the one dimensionless statement of how fast
##     an animal is going *for its size*. A leg is a pendulum over a hip and this
##     is the ratio of the body's kinetic energy to the work of vaulting over that
##     leg, so it — and nothing else — is what says whether a creature is walking,
##     running or beyond either. Small values keep an animal statically supported;
##     large ones let it be caught mid-fall. It is why an Elephant cannot gallop
##     however hard it tries: its hip is a whole leg off the ground, so at the top
##     speed its own mass allows it never leaves the walking regime, and nothing
##     had to forbid it.
##   * **Whether the girdles can throw the body.** Two limbs working as one pair
##     is a launch, and a launch needs three things this body may or may not have:
##     legs that point along the animal rather than out beside it, a back that
##     folds, and the ability to leave the ground at all. A sprawled animal fails
##     the first — its limbs row sideways — which is why a Lizard trots flat out
##     instead of bounding, without any rule saying a sprawled creature may not.
##   * **Whether the feet on one side would collide.** A hind foot swinging
##     forward past a planted forefoot on the same side is a real problem for an
##     animal with long legs on a short trunk, and moving that pair together is
##     the way out of it. That is the whole reason a camel and a giraffe pace, and
##     it is measured off the limbs rather than named.
class_name Footfall
extends RefCounted

## Froude number at which a body stops being able to stand still inside its own
## gait. Below it the animal is vaulting over a stiff leg and has to keep enough
## feet on the floor to be caught standing at any instant; above it the fall
## between beats is short enough to be run out of. Around ½ in the literature and
## for the same reason it is here: it is where the centripetal demand of vaulting
## over a leg reaches what gravity can supply.
const FROUDE_WALK: float = 0.5
## And where a symmetrical gait runs out. Past this the two limbs of a girdle
## gain nothing by alternating and a great deal by pushing together, which is a
## bound, a gallop or a hop. Real animals change over between two and three.
const FROUDE_RUN: float = 2.4

## Least launch a build needs before an asymmetric gait is available to it at
## all, and the launch at which it commits to one completely. Between the two is
## a half-bound: hind pair together, forelimbs still alternating, which is what a
## heavy or a stiff-backed runner does instead of a full gallop.
const LAUNCH_MIN: float = 0.15
const LAUNCH_FULL: float = 0.45

## How much of a girdle's alternation survives at the very top of the asymmetric
## regime. Never quite zero: even a bound has a trailing limb, and a pair landing
## on exactly the same tick reads as a mechanism rather than an animal.
const SPLIT_FLOOR: float = 0.06
## Widest the lead/trail offset within a girdle opens under a turn, as a share of
## the cycle. This is what makes a gallop rotary or transverse rather than
## symmetrical, and it is signed by which way the animal is coming round — a
## running animal leads with the limb on the inside of its turn.
const LEAD_SPREAD: float = 0.16

## How far past a trot the fore girdle is thrown at a full gallop. Over half,
## because the forelimbs of a galloping animal land *late* — the hind pair has
## already gathered underneath and launched by the time they arrive, and that
## gap is the suspended phase.
const GALLOP_LAG: float = 0.60

## Most feet a build will ever have off the ground at once, and the two steps on
## the way there. One is an animal that must be standing on three; two is any
## ordinary symmetrical gait; four is a suspension, and only a body that can
## genuinely throw itself gets one.
const LIFT_CAREFUL: int = 1
const LIFT_SYMMETRIC: int = 2
const LIFT_SUSPENDED: int = 4
## How much of the asymmetric regime a body has to be in before it is allowed to
## have every foot off the floor at once.
const SUSPENSION_AT: float = 0.55

## Closest two limbs may be in the cycle and still count as separate footfalls.
## Half the spacing of an evenly spread four-beat gait, so a walk's quarter-cycle
## gaps are four distinct beats and a bounding girdle's near-zero one is a single
## landing. It is a threshold on the *pattern* and deliberately not on the swing
## window: two limbs may perfectly well both be in the air without belonging to
## the same beat — that is what a gallop is — and conflating the two was what
## collapsed every pattern back into a trot.
const BEAT_WINDOW: float = 0.12

## How much same-side interference a build can carry before it starts moving the
## pair together, and how much of it settles the matter. Both are shares of the
## two legs' combined travel — see `interference` — and the span between them is
## deliberately narrow, because the thing being described is a build either having
## room for its own feet or not having it.
const INTERFERENCE_FREE: float = 0.20
const INTERFERENCE_FULL: float = 0.55


# --- what the pattern currently is -------------------------------------------
# All three are read out rather than set. Between them they are the footfall
# pattern, and there is no fourth number and no name.

## Phase by which the fore girdle follows the hind, as a share of one cycle.
var girdle_lag: float = 0.5
## Phase between the two limbs of a girdle. Half a cycle is alternating.
var hind_split: float = 0.5
var fore_split: float = 0.5

# --- and what decided it ------------------------------------------------------

## Speed², over gravity times hip height. The regime everything below reads.
var froude: float = 0.0
## How completely this build can work a girdle as a single pair: legs that point
## along the body, a back that folds, and somewhere to push to. Zero on anything
## that cannot leave the ground.
var launch: float = 0.0
## How far into the asymmetric regime the animal actually is — the Froude regime
## and the ability to use it, multiplied. 0 is a symmetrical gait; 1 is a full
## gallop, bound or hop.
var aerial: float = 0.0
## How much the animal still needs to be standing on its feet at every instant.
## One is a body that must always be supported; zero is one that can be caught.
var caution: float = 1.0
## How much of the same-side interference problem this build has. One is an
## animal whose hind foot would land where its forefoot is standing.
var interference: float = 0.0
## Most feet that may be off the ground at once.
var lift_limit: int = LIFT_SYMMETRIC
## Share of a cycle one limb spends in the air. Two limbs closer together in
## phase than this belong to the same beat and may be aloft together; anything
## further apart may not.
var swing_share: float = 0.5
## Whether the forelimbs are carrying any of the body. False leaves the hind pair
## to walk alone — which is what being two-legged is, and it is a measurement of
## the arms rather than a category anything selects.
var forelimbs_bear: bool = true

var _phase: Dictionary = {"RL": 0.0, "RR": 0.5, "FL": 0.5, "FR": 0.0}


## Re-derives the pattern from the body that has just been solved.
##
## `hip` is how high the hips are actually being carried, `speed` how fast the
## body is going, `reach` the fore-and-aft travel the fore and hind feet have and
## `gap` the distance between the two girdles along the animal. `lead` is which
## way it is turning, measured off the two hind sockets rather than asked for:
## the outside one of a turn travels further, and a running animal leads with the
## inside limb.
## `spring` is how completely this build can throw itself off the ground — see
## Leap.launch, which works it out from the same joints, muscle and elastic tissue
## a jump is taken with.
func update(posture: Posture, loco: Locomotion, p: CreatureParams,
		hip: float, speed: float, reach: Vector2, gap: float,
		lead: float, bearing: bool, spring: float = 0.0) -> void:
	if posture == null or loco == null or p == null:
		return
	forelimbs_bear = bearing
	swing_share = clampf(1.0 - loco.duty, 0.05, 0.6)

	# --- the regime -----------------------------------------------------------
	# One number, and it is the only place speed enters the pattern at all. A leg
	# is a pendulum over a hip, so how fast an animal is going only means anything
	# against how long that pendulum is: an Elephant at its top speed and a Lizard
	# ambling are at the same point in their own gaits, and this is what says so.
	froude = speed * speed / maxf(Elevation.GRAVITY * maxf(hip, 1.0), 0.0001)
	# Around the transition rather than up to it, and the sharpness is the point.
	# The walk-run change is a bifurcation in a real animal — there is no gait
	# halfway between them that anything actually uses — and a slow ramp from
	# standing to the transition speed produces exactly that non-gait: a footfall
	# pattern with two long gaps and two short ones, which nothing can hold to
	# because the feet themselves come due evenly. Sharpened, a walking animal gets
	# an even four-beat walk and a running one a clean two-beat, and the changeover
	# is somewhere to watch rather than something to sit in the middle of.
	caution = 1.0 - smoothstep(FROUDE_WALK * 0.4, FROUDE_WALK * 1.6, froude)

	# --- can this body work a girdle as one pair? -----------------------------
	# Three separate abilities and the launch needs all of them, which is why they
	# multiply rather than average. A sprawled animal has the back and the legs and
	# points them the wrong way; a columnar one has the legs pointing the right way
	# and nothing to push with.
	#
	#   * how much of the limb is available fore-and-aft rather than spent
	#     standing out to the side. The swing plane rotates with the limb, so the
	#     sideways share of the plan-view reach is the cosine of the tilt and what
	#     is left to drive along the body with is the sine of it — a fifth of the
	#     reach on a sprawled build and three quarters of it on an upright one.
	#   * how far the back folds, which is what carries a hind foot up underneath
	#     the shoulders and lets the pair land together.
	#   * whether the animal can leave the ground at all. That used to be
	#     `leap_height`, a species parameter that said so; it is now `Leap`, which
	#     works it out from the joint travel, the muscle and the store — so an
	#     Elephant does not gallop for the same reason it does not jump, which is
	#     that its knees do not open far enough to push against anything, and
	#     nothing anywhere had to say either.
	var drive_axis: float = clampf(sin(posture.tilt), 0.0, 1.0)
	launch = drive_axis * lerpf(0.35, 1.0, loco.spine_freedom) \
		* clampf(spring, 0.0, 1.0)

	# ...and how much of that it is currently using. The two are not multiplied,
	# and the distinction matters: *whether* an animal has an asymmetric gait is a
	# property of its build, and *how far into one* it is is a property of how fast
	# it is going. A creature barely capable of bounding does not spend its life
	# quarter-bounding — it trots until the speed is there and then commits, which
	# is what animals do. A build in between the two thresholds gets a half-bound,
	# which is a real gait rather than an averaging artefact.
	var regime: float = clampf((froude - FROUDE_WALK) / (FROUDE_RUN - FROUDE_WALK), 0.0, 1.0)
	aerial = regime * smoothstep(LAUNCH_MIN, LAUNCH_FULL, launch)

	# --- would the feet on one side collide? ----------------------------------
	# The hind foot swings forward and the forefoot on the same side is standing
	# somewhere ahead of it. They are separated by the gap between the girdles, and
	# each of them has its own fore-and-aft travel to spend closing it. Long legs
	# on a short trunk run out of room, and a pair that moves together never has
	# the problem — which is the whole of why a camel paces, measured rather than
	# named.
	interference = clampf((reach.x + reach.y - gap) / maxf(reach.x + reach.y, 1.0), 0.0, 1.0)

	# --- and so, the three numbers --------------------------------------------
	# The fore girdle's lag runs across the whole symmetrical family. A trot is the
	# default: two legs down, diagonally opposed, is the cheapest way to stand
	# while moving. Caution pulls it toward the four-beat walk, because an animal
	# that must be supported at every instant cannot afford to put two feet down at
	# once and then have nothing for half a cycle; interference pulls it the other
	# way toward a pace. Both are pulls on one number rather than three cases.
	var symmetric: float = lerpf(0.5, 0.25, caution)
	# Interference is not a preference and does not blend like one. Either a hind
	# foot swinging forward arrives where the forefoot on the same side is standing
	# or it does not, and an animal with the problem commits to the way out rather
	# than going part of the way toward it — which is why a camel paces and does not
	# spend its life half-pacing. Blended linearly the same 0.6 of a problem came
	# out as 0.6 of a solution: a lag too large for the two legs to be one footfall,
	# so they were never coupled, and what the animal actually did was trot with a
	# pattern politely asking for something else.
	symmetric = lerpf(symmetric, 0.0,
		smoothstep(INTERFERENCE_FREE, INTERFERENCE_FULL, interference))
	# Past the symmetrical family the fore girdle falls behind instead: the hind
	# pair gathers, launches, and the forelimbs land late into the next stride.
	girdle_lag = lerpf(symmetric, GALLOP_LAG, aerial)

	# The two splits collapse from alternating to together as the animal goes
	# asymmetric, and the hind pair goes first — which is a half-bound, and is what
	# most animals do on the way to a full gallop rather than an intermediate
	# anybody designed. A turn opens them again by the lead offset, and the *sign*
	# of that offset on the fore girdle against the hind is the difference between
	# a rotary and a transverse gallop.
	var gathered: float = clampf(aerial, 0.0, 1.0)
	hind_split = lerpf(0.5, SPLIT_FLOOR, gathered)
	fore_split = lerpf(0.5, SPLIT_FLOOR, gathered * gathered)
	var turn: float = clampf(lead, -1.0, 1.0) * LEAD_SPREAD * gathered
	hind_split += turn
	fore_split -= turn

	# A two-legged body has no fore girdle to be out of phase with. Both numbers
	# still exist and are still solved — the arms are carried, and something has to
	# say where they are in the cycle — but nothing weight-bearing reads them.
	if not forelimbs_bear:
		girdle_lag = 0.5
		fore_split = hind_split

	_phase["RL"] = 0.0
	_phase["RR"] = fposmod(hind_split, 1.0)
	_phase["FL"] = fposmod(girdle_lag, 1.0)
	_phase["FR"] = fposmod(girdle_lag + fore_split, 1.0)

	# --- how many feet may be off the floor -----------------------------------
	# Three tiers and they are the three regimes above, restated as a count. A body
	# that must be statically supported picks one foot up at a time; an ordinary
	# symmetrical gait has a pair off the ground; and a suspension — every foot
	# clear at once — is only ever available to a body that can genuinely throw
	# itself, which is what `aerial` already measures.
	lift_limit = LIFT_SYMMETRIC
	if caution > 0.55 or posture.feet_down >= 3 and aerial <= 0.0:
		lift_limit = LIFT_CAREFUL
	if aerial >= SUSPENSION_AT:
		lift_limit = LIFT_SUSPENDED


## Where in the cycle this limb's step belongs, 0..1.
func phase(key: String) -> float:
	return _phase.get(key, 0.0)


## How far after `from` the limb `to` is due, as a share of a cycle. Always
## forward: a beat that has passed comes round again.
func gap_between(from: String, to: String) -> float:
	return fposmod(phase(to) - phase(from), 1.0)


## Whether these two limbs are one footfall rather than two — close enough in the
## cycle that they land as a pair.
##
## This is the whole of what used to be the hard-wired diagonal pairing, and it is
## now a consequence of the three numbers above rather than of which corner of the
## animal a leg is on. In a trot the partner is the diagonal, in a pace the leg on
## the same side, in a bound the other limb of the same girdle, in a pronk all
## three of them, and in a four-beat walk or a gallop there is no partner at all.
func shares_beat(a: String, b: String) -> bool:
	return _apart(a, b) < BEAT_WINDOW


## Whether these two may be off the ground at the same time.
##
## A different question from sharing a beat and it is asked of a different number:
## a limb is in the air for `swing_share` of its cycle, so two limbs whose phases
## are closer than that overlap whether anybody meant them to or not. It is what
## keeps at least one leg of every opposed pair on the floor — the job the
## diagonal gate used to do — and it is what lets a galloping animal have three
## feet in the air at once without those three being a single beat.
func may_overlap(a: String, b: String) -> bool:
	return _apart(a, b) < swing_share


## How far apart two limbs are in the cycle, the short way round: 0 is together
## and ½ is as far apart as two phases can be.
func _apart(a: String, b: String) -> float:
	var gap: float = gap_between(a, b)
	return minf(gap, 1.0 - gap)


## How well a limb lifting now would fit the pattern, given which limb last left
## the ground and how far through the cycle that was.
##
## Zero is exactly on the beat and one is as far off it as a limb can be. The gait
## picks the best-fitting of the feet that are actually due, which is what turns
## three numbers into an order — and because a limb has to be due before it is
## ever scored, the reactive rule underneath is untouched: nothing here makes a
## foot step, it only decides which of the feet already asking goes first.
func off_beat(key: String, since: String, elapsed: float) -> float:
	var wanted: float = gap_between(since, key)
	var apart: float = fposmod(elapsed - wanted, 1.0)
	return minf(apart, 1.0 - apart) * 2.0


## What a person would call the current pattern. Never read by the simulation —
## it exists so the creation menu and the tests can say what came out.
func describe() -> String:
	if not forelimbs_bear:
		return "hop" if hind_split < 0.2 else "two-legged stride"
	if hind_split < 0.2 and fore_split < 0.2:
		return "pronk" if absf(girdle_lag) < 0.12 or girdle_lag > 0.88 else "bound"
	if aerial > 0.25:
		return "rotary gallop" if (fore_split - 0.5) * (hind_split - 0.5) < 0.0 \
			else "transverse gallop"
	if girdle_lag < 0.12 or girdle_lag > 0.88:
		return "pace"
	if girdle_lag > 0.38:
		return "trot"
	return "lateral-sequence walk"
