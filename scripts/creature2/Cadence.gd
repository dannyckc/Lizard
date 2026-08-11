## Which foot goes next, how many may be off the ground at once, and how far apart
## in the cycle the four of them are held — Footfall's successor, ported whole.
##
## A footfall pattern is three numbers, and every terrestrial gait is a point in
## that space:
##
##   * `girdle_lag` — how far after the hind girdle the fore girdle follows. 0 is a
##     pace (the legs on one side move together), ¼ the lateral-sequence walk nearly
##     every heavy quadruped uses, ½ a trot.
##   * `hind_split` and `fore_split` — how far apart the two limbs *within* a girdle
##     are. ½ is alternating, which is what standing on your legs one at a time
##     means; 0 is the pair working as one, which is a bound, a hop or a pronk
##     depending on what the other girdle is doing.
##
## A trot, a pace, an amble, a lateral-sequence walk, a transverse gallop, a rotary
## gallop, a bound, a half-bound, a two-legged stride, a hop and a tail-propped
## pentapedal crawl are all read off those three, so none of them is a mode, a
## preset or a name anything checks for. And the three are derived, not authored:
##
##   * **Froude number.** v²/g·h, the one dimensionless statement of how fast an
##     animal is going *for its size*. A leg is a pendulum over a hip and this is
##     the ratio of the body's kinetic energy to the work of vaulting over it, so
##     it — and nothing else — says whether a creature is walking or running. It is
##     why a heavy animal cannot gallop however hard it tries, and nothing had to
##     forbid it.
##   * **Whether the girdles can throw the body.** Two limbs working as one pair is
##     a launch, and a launch needs legs that point along the animal, a back that
##     folds, and the ability to leave the ground at all.
##   * **Whether the feet on one side would collide.** A hind foot swinging forward
##     past a planted forefoot on the same side is a real problem for long legs on a
##     short trunk, and moving that pair together is the way out — which is the whole
##     reason a camel paces, measured rather than named.
class_name Cadence
extends RefCounted

## Froude number at which a body stops being able to stand still inside its own
## gait. Below it the animal vaults over a stiff leg and has to keep enough feet on
## the floor to be caught standing at any instant; above it the fall between beats
## is short enough to be run out of.
##
## Quoted against these bodies rather than against Earth, and that is a correction
## rather than a fudge: the textbook transitions are measured on animals whose feet
## swing about as far under them as their hips are high, and these are drawn with
## feet that travel around four tenths of that — so the fastest any of them can move
## its legs lands about a quarter of the way to the Earth figure. Left at a half the
## threshold is simply unreachable and every creature sits permanently in the
## walking regime.
const FROUDE_WALK: float = 0.12
## And where a symmetrical gait runs out. Past this the two limbs of a girdle gain
## nothing by alternating and a great deal by pushing together.
const FROUDE_RUN: float = 0.85

## Least launch a build needs before an asymmetric gait is available at all, and
## the launch at which it commits completely. Between the two is a half-bound —
## hind pair together, forelimbs still alternating — which is what a heavy or
## stiff-backed runner does instead of a full gallop.
const LAUNCH_MIN: float = 0.15
const LAUNCH_FULL: float = 0.45

## How much of a girdle's alternation survives at the top of the asymmetric regime.
## Never quite zero: even a bound has a trailing limb, and a pair landing on exactly
## the same tick reads as a mechanism rather than an animal.
const SPLIT_FLOOR: float = 0.06
## Widest the lead/trail offset within a girdle opens under a turn, as a share of
## the cycle — signed by which way the animal is coming round, because a running
## animal leads with the limb on the inside of its turn.
const LEAD_SPREAD: float = 0.16

## How far past a trot the fore girdle is thrown at a full gallop. Over half,
## because the forelimbs of a galloping animal land *late* — the hind pair has
## gathered and launched by the time they arrive, and that gap is the suspension.
const GALLOP_LAG: float = 0.60

## When a galloping build rotates its leads. A back that is itself a working part of
## the stride lands its fore pair in the *opposite* order to the hind, which is the
## rotary gallop of the dorsomobile runners; a stiffer-backed galloper keeps the
## transverse order however fast it goes.
const ROTARY_SPINE: float = 0.85
const ROTARY_AT: float = 0.70

## Most feet a build will ever have off the ground at once, and the two steps on the
## way there. One is an animal that must be standing on three; two is any ordinary
## symmetrical gait; four is a suspension, and only a body that can genuinely throw
## itself gets one.
const LIFT_CAREFUL: int = 1
const LIFT_SYMMETRIC: int = 2
const LIFT_SUSPENDED: int = 4
const SUSPENSION_AT: float = 0.55

## Closest two limbs may be in the cycle and still count as separate footfalls.
## Half the spacing of an evenly spread four-beat gait. A threshold on the
## *pattern* and deliberately not on the swing window: two limbs may perfectly well
## both be in the air without belonging to the same beat — that is what a gallop is.
const BEAT_WINDOW: float = 0.12

## How much same-side interference a build can carry before it starts moving the
## pair together, and how much settles the matter. The span is deliberately narrow:
## the thing described is a build either having room for its own feet or not.
const INTERFERENCE_FREE: float = 0.20
const INTERFERENCE_FULL: float = 0.55

const FL := &"FL"
const FR := &"FR"
const HL := &"HL"
const HR := &"HR"

## Phase by which the fore girdle follows the hind, as a share of one cycle.
var girdle_lag: float = 0.5
## Phase between the two limbs of a girdle. Half a cycle is alternating.
var hind_split: float = 0.5
var fore_split: float = 0.5

## Speed², over gravity times hip height. The regime everything below reads.
var froude: float = 0.0
## How completely this build can work a girdle as a single pair.
var launch: float = 0.0
## How far into the asymmetric regime the animal actually is — the regime and the
## ability to use it, multiplied. 0 is a symmetrical gait, 1 a full gallop or hop.
var aerial: float = 0.0
## How much the animal still needs to be standing at every instant.
var caution: float = 1.0
var interference: float = 0.0
## Most feet that may be off the ground at once...
var lift_limit: int = LIFT_SYMMETRIC
## ...and the most this body would ever lift, caution set aside. Only the top speed
## reads it, and it needs exactly this: pricing a ceiling off a limit that is low
## *because the animal is going slowly* would hold every creature at the speed that
## made it careful.
var lift_ceiling: int = LIFT_SYMMETRIC
## Share of a cycle one limb spends in the air.
var swing_share: float = 0.5
var forelimbs_bear: bool = true
## How much of the walking gait is stood on the tail, 0..1 — the pentapedal crawl,
## and the product of two readings that cannot both be large anywhere else: a tail
## the body can genuinely prop on, and the caution of the walking regime.
var crawl: float = 0.0

var _phase: Dictionary = {HL: 0.0, HR: 0.5, FL: 0.5, FR: 0.0}


## Re-derives the pattern from the body that has just been solved.
##
## `hip` is the height the hips are carried at, `speed` how fast the body is going,
## `reach` the fore-and-aft travel the fore and hind feet have and `gap` the
## distance between the girdles along the animal. `lead` is which way it is turning,
## measured off the two hind sockets rather than asked for. `spring` is how
## completely the build can throw itself off the ground and `prop` how much of a
## standing strut the tail is — only a biped's walk reads the second.
func update(carriage: Carriage, loco: Locomotor, spec: BodySpec,
		hip: float, speed: float, reach: Vector2, gap: float,
		lead: float, bearing: bool, spring: float = 0.0,
		prop: float = 0.0) -> void:
	if carriage == null or loco == null or spec == null:
		return
	forelimbs_bear = bearing
	swing_share = clampf(1.0 - loco.duty, 0.05, 0.6)

	# --- the regime ---------------------------------------------------------
	# The only place speed enters the pattern at all. A leg is a pendulum over a
	# hip, so how fast an animal is going only means anything against how long that
	# pendulum is: a heavy animal at its top speed and a small one ambling are at
	# the same point in their own gaits, and this is what says so.
	froude = speed * speed / maxf(Gravity.PULL * maxf(hip, 1.0), 0.0001)
	# Around the transition rather than up to it, and the sharpness is the point:
	# the walk-run change is a bifurcation in a real animal, and a slow ramp to it
	# produces a non-gait with two long gaps and two short ones that nothing can
	# hold to.
	caution = 1.0 - smoothstep(FROUDE_WALK * 0.4, FROUDE_WALK * 1.6, froude)

	# --- can this body work a girdle as one pair? ---------------------------
	# Three separate abilities, and the launch needs all of them, which is why they
	# multiply: how much of the limb is available fore-and-aft rather than spent
	# standing out to the side, how far the back folds, and whether the animal can
	# leave the ground at all.
	var drive_axis: float = clampf(sin(carriage.tilt), 0.0, 1.0)
	launch = drive_axis * lerpf(0.35, 1.0, loco.spine_freedom) \
		* clampf(spring, 0.0, 1.0)

	# ...and how much of it the animal is currently using. Not multiplied into the
	# launch, and the distinction matters: *whether* a body has an asymmetric gait
	# is a property of the build, *how far into one* it is is a property of how fast
	# it is going. A creature barely capable of bounding trots until the speed is
	# there and then commits, which is what animals do.
	var regime: float = clampf((froude - FROUDE_WALK) / (FROUDE_RUN - FROUDE_WALK),
		0.0, 1.0)
	aerial = regime * smoothstep(LAUNCH_MIN, LAUNCH_FULL, launch)

	# --- would the feet on one side collide? --------------------------------
	interference = clampf((reach.x + reach.y - gap) / maxf(reach.x + reach.y, 1.0),
		0.0, 1.0)

	# --- and so, the three numbers ------------------------------------------
	# The fore girdle's lag runs across the whole symmetrical family. A trot is the
	# default: two legs down, diagonally opposed, is the cheapest way to stand while
	# moving. Caution pulls it toward the four-beat walk, interference the other way
	# toward a pace — both pulls on one number rather than three cases.
	var symmetric: float = lerpf(0.5, 0.25, caution)
	# Interference is not a preference and does not blend like one: either a hind
	# foot swinging forward arrives where the forefoot is standing or it does not,
	# and an animal with the problem commits to the way out.
	symmetric = lerpf(symmetric, 0.0,
		smoothstep(INTERFERENCE_FREE, INTERFERENCE_FULL, interference))
	# Past the symmetrical family the fore girdle falls behind instead.
	girdle_lag = lerpf(symmetric, GALLOP_LAG, aerial)

	# The two splits collapse from alternating to together as the animal goes
	# asymmetric, and the hind pair goes first — which is a half-bound, and is what
	# most animals do on the way to a full gallop rather than an intermediate
	# anybody designed. A turn opens them again, and the *sign* of that offset on
	# the fore girdle against the hind is the difference between a rotary and a
	# transverse gallop.
	var gathered: float = clampf(aerial, 0.0, 1.0)
	hind_split = lerpf(0.5, SPLIT_FLOOR, gathered)
	fore_split = lerpf(0.5, SPLIT_FLOOR, gathered * gathered)
	var turn: float = clampf(lead, -1.0, 1.0) * LEAD_SPREAD * gathered
	hind_split += turn
	fore_split -= turn

	# The dorsomobile runner's lead change: reversing the fore split lands that pair
	# trail-limb-first against the hind pair's order, which is the rotary cycle. A
	# commitment rather than a blend, because a lead is an order and there is no
	# halfway order between two. Wrapped so the number still reads as a phase.
	if loco.spine_freedom >= ROTARY_SPINE and gathered >= ROTARY_AT:
		fore_split = fposmod(-fore_split, 1.0)

	# A two-legged body has no fore girdle to be out of phase with. Both numbers are
	# still solved — the arms are carried, and something has to say where they are —
	# but nothing weight-bearing reads them.
	crawl = 0.0
	if not forelimbs_bear:
		girdle_lag = 0.5
		# The pentapedal crawl. A careful biped's split sits at a half because
		# alternating is what standing on your legs one at a time means — but a biped
		# with a strut under its pelvis is standing on the strut, and the pair is free
		# to swing forward together exactly as it does in the hop. The same collapse
		# the asymmetric regime buys with speed, the prop buys with caution.
		crawl = clampf(prop, 0.0, 1.0) * caution
		hind_split = lerpf(hind_split, SPLIT_FLOOR, crawl)
		fore_split = hind_split

	_phase[HL] = 0.0
	_phase[HR] = fposmod(hind_split, 1.0)
	_phase[FL] = fposmod(girdle_lag, 1.0)
	_phase[FR] = fposmod(girdle_lag + fore_split, 1.0)

	# --- how many feet may be off the floor ---------------------------------
	# Three tiers, and they are the three regimes above restated as a count. The
	# careful tier asks whether the body would still be standing with the foot up,
	# and a tail prop changes the answer: a crawling biped with both hind feet
	# swinging is on its tail, not on nothing.
	lift_limit = LIFT_SYMMETRIC
	if caution > 0.55 and crawl < 0.5 \
			or carriage.feet_down >= 3 and aerial <= 0.0:
		lift_limit = LIFT_CAREFUL
	if aerial >= SUSPENSION_AT:
		lift_limit = LIFT_SUSPENDED
	# The same three lines with caution taken out. A stance that prefers three feet
	# down keeps them down — that is anatomy, not hesitation — but a body that is
	# merely going slowly is not held to a walk it has no other reason for.
	lift_ceiling = LIFT_SYMMETRIC
	if carriage.feet_down >= 3 and aerial <= 0.0:
		lift_ceiling = LIFT_CAREFUL
	if aerial >= SUSPENSION_AT:
		lift_ceiling = LIFT_SUSPENDED


## Where in the cycle this limb's step belongs, 0..1.
func phase(key: StringName) -> float:
	return _phase.get(key, 0.0)


## How far after `from` the limb `to` is due, as a share of a cycle. Always
## forward: a beat that has passed comes round again.
func gap_between(from: StringName, to: StringName) -> float:
	return fposmod(phase(to) - phase(from), 1.0)


## Whether these two limbs are one footfall rather than two. This is the whole of
## what used to be a hard-wired diagonal pairing: in a trot the partner is the
## diagonal, in a pace the leg on the same side, in a bound the other limb of the
## same girdle, in a pronk all three, and in a four-beat walk or a gallop there is
## no partner at all.
func shares_beat(a: StringName, b: StringName) -> bool:
	return _apart(a, b) < BEAT_WINDOW


## Whether these two may be off the ground at the same time — a different question
## from sharing a beat, and asked of a different number: a limb is in the air for
## `swing_share` of its cycle, so two limbs closer than that overlap whether anybody
## meant them to or not.
func may_overlap(a: StringName, b: StringName) -> bool:
	return _apart(a, b) < swing_share


func _apart(a: StringName, b: StringName) -> float:
	var gap: float = gap_between(a, b)
	return minf(gap, 1.0 - gap)


## How well a limb lifting now would fit the pattern, given which limb last left the
## ground and how far through the cycle that was. Zero is exactly on the beat and
## one is as far off it as a limb can be. Because a limb has to be *due* before it
## is ever scored, the reactive rule underneath is untouched: nothing here makes a
## foot step, it only decides which of the feet already asking goes first.
func off_beat(key: StringName, since: StringName, elapsed: float) -> float:
	var wanted: float = gap_between(since, key)
	var apart: float = fposmod(elapsed - wanted, 1.0)
	return minf(apart, 1.0 - apart) * 2.0


## What a person would call the current pattern. Never read by the simulation — it
## exists so the lab and the probes can say what came out.
func describe() -> String:
	if not forelimbs_bear:
		if hind_split < 0.2:
			return "pentapedal crawl" if crawl > 0.5 else "hop"
		return "two-legged stride"
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
