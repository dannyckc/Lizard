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
## The rules, each a statement about support rather than about style:
##
##   * **Count** — how many feet may swing at once grows with pace, because a
##     slow body needs its support continuous and a fast one gets it back
##     quicker than it loses it. This is where walk becomes trot: not a mode
##     switch, a second seat opening.
##   * **Girdle lockout** — a pair does not lift together while there is any
##     choice, because a girdle with both feet in the air is a girdle sitting
##     on nothing. Desperation overrides it (a stumbling body takes the step
##     it needs), and at a hard run the override is what a gallop's paired
##     beats are made of.
##   * **Diagonal coupling** — when a foot is released at pace, its diagonal
##     partner is invited onto the same beat if its own drift has it most of
##     the way to asking. The invitation strength is the spec's
##     `beat_coupling`; this is the one place a body says how much of a
##     trotter it is.
##
## Emergencies (a rescue step, ground gone from under an anchor) bypass all
## three: survival is not a style.
class_name Rhythm
extends RefCounted

## Pace below which support is reorganised one foot at a time. Above it a
## second seat opens and the diagonal coupling starts pairing beats.
const WALK_EDGE: float = 0.40

## Pace above which a desperate girdle pair (both feet past their limit) is
## let go together — the gallop's gathered beat, priced as the emergency it
## anatomically is.
const RUN_EDGE: float = 0.80

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

## Diagonal partner per foot, in Footwork's order (FL, FR, HL, HR).
const DIAGONAL: Array[int] = [3, 2, 1, 0]
## Same-girdle partner per foot.
const PAIR: Array[int] = [1, 0, 3, 2]


## Decides which of the asking feet may lift this tick.
##
## `urgency` is per-foot drift in trigger units (≥ 1.0 is a request, 0 for a
## foot already swinging), `swinging` which feet are already up, `since`
## seconds since each foot last landed. Returns the indices to release, most
## urgent first. Pure — the caller owns all state — so a probe can ask it
## hypotheticals.
func choose(urgency: PackedFloat32Array, swinging: PackedByteArray,
		since: PackedFloat32Array, pace: float, coupling: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var up: int = 0
	for i in swinging.size():
		if swinging[i] != 0:
			up += 1
	var seats: int = 1 if pace < WALK_EDGE else 2
	# The absolute ceiling even desperation honours: a body reorganising all
	# its support at once has none, and a stumble that lifted a third foot at
	# a walk was making its own emergency worse.
	var most: int = 2 if pace < RUN_EDGE else 3

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
		if partner_up and not (desperate and pace >= RUN_EDGE):
			# The girdle keeps a foot down while there is any choice; at a run a
			# desperate pair goes anyway, and that is the gathered beat.
			continue
		if up >= seats and not desperate:
			continue
		out.append(i)
		up += 1

		# The diagonal invitation: at pace, the partner most of the way to its
		# own ask joins the beat — subject to its own girdle and cooldown.
		if pace < WALK_EDGE or coupling <= 0.0:
			continue
		var d: int = DIAGONAL[i]
		if swinging[d] != 0 or (d in out) or since[d] < COOLDOWN:
			continue
		var invite: float = lerpf(1.0, COUPLE_FLOOR, clampf(coupling, 0.0, 1.0))
		if urgency[d] < invite:
			continue
		if swinging[PAIR[d]] != 0 or (PAIR[d] in out):
			continue
		if up >= most or (up >= seats and urgency[d] < DESPERATE):
			continue
		out.append(d)
		up += 1

	return out
