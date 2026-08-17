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
## The ladder answers two questions, and they are one fact at two grains:
##
##   * **`flow`** — how many feet, on average, a body at this regime carries in
##     the air. This is the duty factor read the other way round (walk 0.75,
##     trot 0.5, gallop toward 0.3 — the quantity every gait study measures),
##     and it is what makes the beat *continuous*: Footwork prices the stride
##     so the swings tile the cycle at exactly this occupancy, and the grant
##     below keeps the seats filled. A gait whose seats sit empty between
##     steps is a body pausing mid-walk, which is not a rhythm at all.
##   * **`choose`** — which feet take those seats, in what company. The rules,
##     each a statement about support rather than about style:
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
##   * **Diagonal company** — at pace, the seat beside a swinging foot belongs
##     to its diagonal partner, because two diagonal feet carry the trunk
##     across its own middle and two lateral feet ask the body to balance on
##     one side of itself. So the grant *prefers* the diagonal of whatever is
##     already up — it may take the seat a little before its own drift is due,
##     as hard as the spec's `beat_coupling` prefers it — and the preference
##     fades as the bound takes over: a gallop is not a fast trot, and the two
##     couplings trade rather than stack.
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

## The occupancy ladder — how many feet, on average, each regime carries in
## the air. These are the duty factors of the gait literature written as
## airborne feet (mean up = 4·(1 − duty)): a slow walk keeps three feet and a
## bit down (duty toward 0.75), a trot swings its diagonal pairs for half the
## cycle (duty 0.5), and a developed gallop is airborne more than it is not
## (duty toward 0.3). Pinned once, like the Froude boundaries they sit on,
## and then true of whatever body is asking — the *cycle length* that delivers
## the occupancy comes from each body's own swing times, never from here.
const SEAT_WALK_GAIN: float = 0.4
const SEAT_TROT: float = 1.4
const SEAT_RUN: float = 1.8
const SEAT_TOP: float = 2.2
const SEAT_BOUND: float = 2.8

## Least a foot rests between steps, seconds. A rhythm floor, not a physics
## one: it stops a marginal trigger fluttering a foot on and off the ground.
const COOLDOWN: float = 0.10

## Urgency at which a request stops being deniable. Quoted in trigger units
## (1.0 = the foot just crossed its own step trigger).
const DESPERATE: float = 1.6

## How much of the way to its own trigger a foot must be for the flow to take
## it early — the handover. A flowing gait hands support over continuously,
## so when the regime's seats are not all taken, the most-ready planted foot
## is released a little before its own drift is due rather than leaving the
## beat with a hole in it. The stride it gives up is bounded by this floor,
## and a body that is not travelling never hands anything over at all.
const EAGER: float = 0.8

## The same floor for the *diagonal* of a foot already in the air, at full
## `beat_coupling` — deliberately deeper than EAGER, because this is the one
## early release that reorganises a gait: taking the diagonal partner onto
## the beat ahead of a more-urgent lateral neighbour is exactly a walk's
## four-beat dissolving into a trot's two, and the one short stride it costs
## is the shuffle-step every animal takes changing gait. The spec's coupling
## scales how deep the preference reaches, not this floor.
const COUPLE_FLOOR: float = 0.45

## How much the diagonal preference outranks plain urgency in the queue, at
## full coupling — enough to take the seat from a lateral neighbour that is
## merely a little more overdue, never enough to outrank an emergency.
const AFFINITY: float = 0.35

## The speed below which nothing flows, px/s — the same gate Footwork's
## travel measurement uses. A standing body's steps are tidy-ups and
## rescues; keeping seats warm on a body going nowhere would be a march on
## the spot.
const FLOWING: float = 2.0

## The eager floor for the gathered beat's girdle partner, at full bound and a
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
## Which regime the last decision was made in, how developed the bound is
## (0..1), and the occupancy the flow owes — readouts on the same terms.
var regime: int = WALK
var bound: float = 0.0
var flow_seats: float = 1.0


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


## How many feet, on average, this regime carries in the air — the occupancy
## the flow owes, continuous along the whole ladder so an accelerating body's
## gait *develops* rather than switching. Footwork divides the body's four
## swing times by this to get the stride cycle, which is the one seam through
## which the duty factor becomes a beat. Pure, like `regime_of`.
func flow(speed_along: float, rest_hip: float) -> float:
	var fr: float = froude_of(speed_along, rest_hip)
	if fr < FROUDE_TROT:
		# Within the walk the occupancy creeps up from one — a slow walk rests
		# between steps, a brisk one is about to need its second seat.
		var x: float = fr / FROUDE_TROT
		return 1.0 + SEAT_WALK_GAIN * x * x
	if fr < FROUDE_RUN:
		return lerpf(SEAT_TROT, SEAT_RUN,
			(fr - FROUDE_TROT) / (FROUDE_RUN - FROUDE_TROT))
	if fr < FROUDE_BOUND:
		return lerpf(SEAT_RUN, SEAT_TOP,
			(fr - FROUDE_RUN) / (FROUDE_BOUND - FROUDE_RUN))
	return lerpf(SEAT_TOP, SEAT_BOUND,
		clampf((fr - FROUDE_BOUND) / (FROUDE_BOUND * BOUND_SPAN), 0.0, 1.0))


## Decides which of the asking feet may lift this tick.
##
## `urgency` is per-foot drift in trigger units (≥ 1.0 is a request, 0 for a
## foot already swinging), `swinging` which feet are already up, `since`
## seconds since each foot last landed. `speed_along` is the body's forward
## travel (a shove sideways is not a gait), `rest_hip` its built standing hip
## height, `coupling` the spec's diagonal preference, `pair_hold` each
## girdle's attach hold (fore in x, hind in y), `freedom` the spine the body
## has to bound with. Returns the indices to release, best company first.
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
	flow_seats = flow(speed_along, rest_hip)

	seats = 1 if regime == WALK else 2
	# The absolute ceiling even desperation honours. At a walk or a trot a body
	# reorganising more than two feet at once has no support left and a stumble
	# that lifted a third was making its own emergency worse. A run's airier
	# cycle earns a third; at the bound the ceiling is everything — the pairs
	# overlap, and the moment all four are up is not a failure of support, it
	# is the suspension the gait is made of.
	most = 2 if regime < RUN else (3 if regime < BOUND else 4)
	# ...and how many the flow actually keeps occupied — the handover's target,
	# never past what desperation itself would honour. The handover belongs to
	# the tiling gaits: a bound's air comes from its own suspension, and an
	# eager third foot lifted under a galloping body was support taken from
	# the one gait that can least spare it.
	var fill: int = clampi(roundi(flow_seats), 1, most if bound <= 0.0 else 2)
	var flowing: bool = speed_along > FLOWING

	# The diagonal preference: alive at pace, gone at a walk (whose four-beat
	# order is the sequence, not the diagonal), and traded away as the bound's
	# own coupling takes over.
	var diag: float = 0.0
	if regime != WALK:
		diag = clampf(coupling, 0.0, 1.0) * (1.0 - bound)

	# The queue: every planted foot that is due — or near enough due for the
	# company to take it — scored by urgency plus the company the regime
	# prefers, best first. Insertion sort on four entries.
	var order := PackedInt32Array()
	var score := PackedFloat32Array()
	for i in urgency.size():
		if swinging[i] != 0:
			continue
		var floor_i: float = 1.0
		var boost: float = 0.0
		if flowing:
			floor_i = EAGER
			if diag > 0.0 and swinging[DIAGONAL[i]] != 0:
				# The seat beside a swinging foot belongs to its diagonal.
				floor_i = lerpf(EAGER, COUPLE_FLOOR, diag)
				boost = diag * AFFINITY
		if urgency[i] < floor_i:
			continue
		var s: float = urgency[i] + boost
		var at: int = order.size()
		for j in order.size():
			if s > score[j]:
				at = j
				break
		order.insert(at, i)
		score.insert(at, s)

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
		if urgency[i] >= 1.0:
			# A due request takes a seat on the old terms.
			if up >= seats and not desperate and bound <= 0.0:
				continue
		else:
			# An early release is the flow's, and only fills the seats the
			# flow actually owes.
			if up >= fill or (up >= seats and bound <= 0.0):
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

	return out
