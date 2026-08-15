## Which feet may leave the ground together — the gait, as a policy and
## nothing else.
##
## In the v2 locomotion the *need* to step is never decided here: a foot asks
## to step because its support has drifted out from under its body
## (Footwork's measurement), and this file only answers in what order and in
## what company. That split is the design's whole claim about gait
## (docs/V2_DESIGN.md §Phase 3): the acceleration, the body movement and the
## balance are one shared system, and an animal's gait is the coordination
## policy laid over it. A cat and a horse differ *here*, in three rules,
## not in three movers.
##
## Where the policy changes is not authored per body and not quoted against the
## authored ask: the regimes are Froude numbers — speed squared over gravity
## times the animal's own standing hip height, the pendulum term every legged
## body walks inside — pinned once at the reference cat's tuned transitions and
## then true of whatever body is asking. A taller animal crosses into its trot
## at a higher absolute speed because its legs are longer pendulums, and nobody
## told it to; the authored `move_speed` decides only what is *asked*, never
## where the coordination changes. The rest height is deliberately the stance
## the body is built in (the v1 Froude lesson: a crouch must not inflate the
## regime).
##
## The rules, each a statement about support rather than about style:
##
##   * **Count** — how many feet may swing at once grows with the regime,
##     because a slow body needs its support continuous and a fast one gets it
##     back quicker than it loses it. This is where walk becomes trot: not a
##     mode switch, a second seat opening.
##   * **Girdle lockout** — a pair does not lift together while there is any
##     choice, because a girdle with both feet in the air is a girdle sitting
##     on nothing. Desperation overrides it (a stumbling body takes the step
##     it needs) — and past the run regime the lockout *inverts*: the pair is
##     invited onto one beat, which is what a gallop's gathered beats are.
##   * **Diagonal coupling** — when a foot is released at pace, its diagonal
##     partner is invited onto the same beat if its own drift has it most of
##     the way to asking. The invitation strength is the spec's
##     `beat_coupling`, and it fades as the bound takes over: a gallop is not
##     a fast trot, and the two couplings trade rather than stack.
##   * **The gathered beat** — at the bound, a released foot pulls its own
##     girdle partner onto the beat. How hard is not authored per gait: it is
##     the girdle's own `attach_hold` — the cat's hind girdle is bone on bone
##     (1.0) and beats as a pair, its scapula floats in muscle (0.55) and the
##     fore feet land staggered — times how much spine the body has to gallop
##     with (`spine_freedom`): a stiff-backed animal never bounds at all, it
##     just trots faster, which is what a stiff back *is*.
##
## Emergencies (a rescue step, ground gone from under an anchor) bypass all
## of it: survival is not a style.
class_name Rhythm
extends RefCounted

## The walk→trot Froude number: v²/(g·h) at which a second seat opens, pinned
## at the reference cat's tuned transition (21.6 px/s on a 36.7421 px standing
## hip — the speed the old pace-share boundary sat at). Quoted against the
## *rest* stance height, so a crouch cannot inflate the regime.
const FROUDE_TROT: float = 0.008466

## The trot→run Froude number, pinned at the reference cat's tuned third-seat
## speed (43.2 px/s on the same hip): past it the trot gets airy — a third
## foot may be off the ground at once, which the old pace-share boundary
## already allowed — but the beats are still a trot's.
const FROUDE_RUN: float = 0.033862

## The run→bound Froude number, pinned at 60 px/s on the same hip — 2.8× the
## trot onset, which is where the feline literature puts the gallop against
## the trot (a cat trots from ~0.9 m/s and gallops from ~2.2–2.5). The
## reference cat's full unsprinted cruise (54 px/s) sits deliberately under
## it: W alone is a fast working trot, and the bound is what the sprint buys.
const FROUDE_BOUND: float = 0.065316

## How many more FROUDE_BOUNDs of regime the bound takes to develop fully —
## the canter-to-gallop ramp. At the reference cat this has the gathered beat
## developing from 60 px/s and a sprint (100 px/s) bounding at ~0.9 before the
## spine's own freedom takes its share.
const BOUND_SPAN: float = 2.0

## Least a foot rests between steps, seconds. A rhythm floor, not a physics
## one: it stops a marginal trigger fluttering a foot on and off the ground.
const COOLDOWN: float = 0.10

## Urgency at which a request stops being deniable. Quoted in trigger units
## (1.0 = the foot just crossed its own step trigger).
const DESPERATE: float = 1.6

## How much of the way to its own trigger a diagonal partner must be for the
## coupling to pull it onto the beat, at full `beat_coupling`. The spec's
## coupling scales the reach of the invitation, not this floor.
const COUPLE_FLOOR: float = 0.55

## The same floor for the gathered beat's girdle partner, at full bound and a
## rigid girdle. Lower than the diagonal's because a bounding pair works as one
## limb and the second foot is pulled onto the beat early — the pair lands
## together or it is not a pair.
const PAIR_FLOOR: float = 0.45

## Diagonal partner per foot, in Footwork's order (FL, FR, HL, HR).
const DIAGONAL: Array[int] = [3, 2, 1, 0]
## Same-girdle partner per foot.
const PAIR: Array[int] = [1, 0, 3, 2]

## The regimes, in the order the Froude ladder climbs them.
const WALK: int = 0
const TROT: int = 1
const RUN: int = 2
const BOUND: int = 3


## How many feet the last decision would seat, and the ceiling even desperation
## honoured. Readouts of the policy — the gait, as a number, for anything
## watching the loop; nothing here reads them back.
var seats: int = 1
var most: int = 2
## Which regime the last decision was made in, and how developed the bound is,
## 0..1 — readouts on the same terms.
var regime: int = WALK
var bound: float = 0.0


## Where a forward speed sits on this body's own Froude ladder. `rest_hip` is
## the standing hip height of the stance the body is *built* in.
func regime_of(speed_along: float, rest_hip: float) -> int:
	var froude: float = froude_of(speed_along, rest_hip)
	if froude < FROUDE_TROT:
		return WALK
	if froude < FROUDE_RUN:
		return TROT
	if froude < FROUDE_BOUND:
		return RUN
	return BOUND


func froude_of(speed_along: float, rest_hip: float) -> float:
	return speed_along * speed_along / (Gravity.PULL * maxf(rest_hip, 1.0))


## Decides which of the asking feet may lift this tick.
##
## `urgency` is per-foot drift in trigger units (≥ 1.0 is a request, 0 for a
## foot already swinging), `swinging` which feet are already up, `since`
## seconds since each foot last landed. `speed_along` is the body's forward
## travel (a shove sideways is not a gait), `rest_hip` its built standing hip
## height, `coupling` the spec's diagonal invitation, `pair_hold` each
## girdle's attach hold (fore in x, hind in y), `freedom` the spine the body
## has to bound with. Returns the indices to release, most urgent first.
## Pure — the caller owns all state — so a probe can ask it hypotheticals.
func choose(urgency: PackedFloat32Array, swinging: PackedByteArray,
		since: PackedFloat32Array, speed_along: float, rest_hip: float,
		coupling: float, pair_hold: Vector2, freedom: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var up: int = 0
	for i in swinging.size():
		if swinging[i] != 0:
			up += 1

	var froude: float = froude_of(speed_along, rest_hip)
	regime = regime_of(speed_along, rest_hip)
	# How far into the bound the body is: 0 at the run's ceiling, 1 a span of
	# regimes past it — scaled by the spine, because the gathered beat is a
	# spine movement and an animal without one cannot make it.
	bound = 0.0
	if regime == BOUND:
		bound = clampf((froude - FROUDE_BOUND) / (FROUDE_BOUND * BOUND_SPAN),
			0.0, 1.0) * clampf(freedom, 0.0, 1.0)

	seats = 1 if regime == WALK else 2
	# The absolute ceiling even desperation honours. At a walk or a trot a body
	# reorganising more than two feet at once has no support left and a stumble
	# that lifted a third was making its own emergency worse. A run's airier
	# cycle earns a third; at the bound the ceiling is everything — the pairs
	# overlap, and the moment all four are up is not a failure of support, it
	# is the suspension the gait is made of.
	most = 2 if regime < RUN else (3 if regime < BOUND else 4)

	# Requests, most urgent first. Insertion sort on four entries.
	var order := PackedInt32Array()
	for i in urgency.size():
		if swinging[i] != 0 or urgency[i] < 1.0:
			continue
		var at: int = order.size()
		for j in order.size():
			if urgency[i] > urgency[order[j]]:
				at = j
				break
		order.insert(at, i)

	for i in order:
		if up >= most:
			break
		var desperate: bool = urgency[i] >= DESPERATE
		if since[i] < COOLDOWN and not desperate:
			continue
		var partner_up: bool = swinging[PAIR[i]] != 0 or (PAIR[i] in out)
		if partner_up and not (desperate and regime >= RUN) \
				and not (bound > 0.0 and urgency[PAIR[i]] == 0.0):
			# The girdle keeps a foot down while there is any choice; at the
			# bound a desperate pair goes anyway, and a pair whose partner is
			# already through its beat follows it.
			continue
		if up >= seats and not desperate and bound <= 0.0:
			continue
		out.append(i)
		up += 1

		# The gathered beat: at the bound, the released foot pulls its own
		# girdle partner onto the same beat — as hard as the girdle is actually
		# joined. The hind pair beats as one because bone is, the fore lands
		# staggered because muscle is not, and neither was authored per gait.
		if bound > 0.0:
			var p: int = PAIR[i]
			var hold: float = pair_hold.x if i < 2 else pair_hold.y
			var pull: float = bound * clampf(hold, 0.0, 1.0)
			if pull > 0.0 and swinging[p] == 0 and not (p in out) \
					and since[p] >= COOLDOWN and up < most:
				var gather: float = lerpf(1.0, PAIR_FLOOR, pull)
				if urgency[p] >= gather:
					out.append(p)
					up += 1

		# The diagonal invitation: at pace, the partner most of the way to its
		# own ask joins the beat — subject to its own girdle and cooldown. It
		# fades as the bound develops: the two couplings trade, they do not
		# stack, which is exactly a trot dissolving into a gallop.
		var diag: float = coupling * (1.0 - bound)
		if regime == WALK or diag <= 0.0:
			continue
		var d: int = DIAGONAL[i]
		if swinging[d] != 0 or (d in out) or since[d] < COOLDOWN:
			continue
		var invite: float = lerpf(1.0, COUPLE_FLOOR, clampf(diag, 0.0, 1.0))
		if urgency[d] < invite:
			continue
		if swinging[PAIR[d]] != 0 or (PAIR[d] in out):
			continue
		if up >= most or (up >= seats and urgency[d] < DESPERATE and bound <= 0.0):
			continue
		out.append(d)
		up += 1

	return out
