## A piece of meat in a set of jaws, and everything about eating it.
##
## Deliberately not a `Grip`. A grip is a contest — two animals, two masses, flesh
## with a tensile strength and jaws that can be pulled off it — and every number in
## it exists to decide which of the two gives out first. This is possession. Meat
## does not pull back, nothing here can be lost by being overpowered, and there is
## no winner to work out. What varies instead is the one thing a grip never has to
## ask: whether the thing in the mouth will go down, and what has to happen to it
## first.
##
## There is no state machine and no phases. Biting, chewing and swallowing are not
## three modes this steps between; they are three readings of two numbers — where
## the jaws have hold of the piece, and how far the piece reaches from there.
##
##   * The piece **props the jaws open** by however much of it will not fit inside
##     them. That is what biting a thing too big for your mouth looks like, and it
##     is a division rather than an animation.
##   * A chew that cannot swallow **works the piece in**: it erodes what is in the
##     jaws and then re-seats them deeper, so what is left reaches less far than it
##     did. Repeat and a leg is eaten from the end.
##   * Once the piece reaches no further than the mouth is deep, the next closing
##     **swallows** it, because there is nothing left to stop it going down.
##
## So a Cat gnaws at an Elephant's thigh for a long time and an Elephant takes a
## Cat's whole leg in one, and neither of those is written anywhere. Both are
## `reach` against `gape`.
class_name Mouthful
extends RefCounted

## How far into the mouth a piece has to fit before it will pass, as a multiple of
## the gape. Over one because a mouth is a throat as well as an opening — what has
## to clear is the arch of teeth, and a little past it is still inside the animal.
const SWALLOW_SPAN: float = 1.15
## How far the jaws re-seat on the piece per chew, as a fraction of their own
## reach. Under one, so working a piece in is a progression rather than a jump to
## the far end of it.
const WORK_IN: float = 0.6
## Seconds a swallow takes from the jaws closing to the piece being gone.
const SWALLOW_TIME: float = 0.42
## How far back down the throat a swallowed piece travels, as a multiple of the
## head's own radius. Far enough to be genuinely inside the animal rather than
## parked behind its face.
const THROAT_DEPTH: float = 2.4
## How hard a chew jolts what is in the jaws, as a fraction of the mouth's reach.
## Applied along the mouth axis, so the piece is visibly worked rather than merely
## losing tissue.
const CHEW_JOLT: float = 0.22
## Seconds a jolt takes to die away.
const CHEW_SETTLE: float = 0.18


var part: CarrionField.Part = null
## Where on the piece the jaws closed, in the piece's own frame. The bite position,
## kept because nearly everything below is measured from it: what props the mouth
## open, what reaches too far to swallow, and where the next chew lands.
var hold: Vector2 = Vector2.ZERO
## Seconds since the last chew, or large while none is playing.
var worked: float = 99.0
## Seconds into a swallow, or -1 while the piece is still in the mouth.
var going_down: float = -1.0


func is_holding() -> bool:
	return part != null


## How far the piece reaches from the jaws' hold on it, in world pixels.
func reach() -> float:
	return part.reach_from(hold) if part != null else 0.0


## Whether what is left will pass a mouth of this reach.
func fits(gape: float) -> bool:
	return part != null and reach() <= gape * SWALLOW_SPAN


## How far this mouthful holds the jaws open, 0 to 1.
##
## A read, not a pose. The piece is as wide as it is and the mouth is as wide as it
## is; what the animal can do about that is nothing, which is why a mouth with
## something too big in it stays open around it. Saturating at the full gape rather
## than beyond, because a mouth cannot open further than it opens — past that the
## meat simply sticks out of it.
func props_open(gape: float) -> float:
	if part == null or gape <= 0.0:
		return 0.0
	if going_down >= 0.0:
		# The piece is on its way down and the jaws close after it.
		return clampf(1.0 - going_down / SWALLOW_TIME, 0.0, 1.0)
	# Damped by the chew, so the jaws visibly bear down on what they are holding
	# instead of hanging slack around it.
	return clampf(reach() / gape, 0.0, 1.0) * (1.0 - 0.55 * _chew_curve())


## Where the jaws should be holding the piece, relative to the jaw point, along the
## mouth's forward axis. Zero at the teeth, negative back into the throat.
##
## This is the whole of the swallow's motion: the hold is drawn back past the teeth
## and into the head, and because the head is drawn over the world the piece is
## simply gone by the end of it. Nothing scales, fades or is hidden.
func draw_in(head_radius: float) -> float:
	if going_down < 0.0:
		# A chew shoves the mouthful back and lets it come forward again — the
		# working motion, in the one direction a mouth has.
		return -head_radius * CHEW_JOLT * _chew_curve()
	var t: float = clampf(going_down / SWALLOW_TIME, 0.0, 1.0)
	return -head_radius * THROAT_DEPTH * smoothstep(0.0, 1.0, t)


## How far down the throat a swallow has got, 0 to 1, or 0 while nothing is going
## down. What the body reads to distend around it.
func gullet() -> float:
	if going_down < 0.0:
		return 0.0
	return clampf(going_down / SWALLOW_TIME, 0.0, 1.0)


func advance(delta: float) -> void:
	worked += delta
	if going_down >= 0.0:
		going_down += delta


## True once a swallow has finished and the piece is inside the animal.
func is_down() -> bool:
	return going_down >= 0.0 and going_down >= SWALLOW_TIME


## The jaws close on what they are holding.
func chew() -> void:
	worked = 0.0


## The jaws close on something that will go down.
func begin_swallow() -> void:
	going_down = 0.0
	worked = 0.0


## Re-seats the jaws deeper into the piece after a chew has taken what was in them.
##
## Toward the tissue that is left, by a step of the mouth's own reach. Two things
## fall out of that and both are wanted: the hold walks up a long piece so it is
## eaten end-first, and it re-centres on whatever survives, so a piece chewed into
## an odd shape is still held somewhere there is meat rather than over the hole the
## last mouthful left.
func work_in(gape: float) -> void:
	if part == null:
		return
	var centre := Vector2.ZERO
	var standing: float = 0.0
	for cell in part.cells:
		if part.gone[cell] != 0:
			continue
		centre += part.local_centre_of(cell)
		standing += 1.0
	if standing <= 0.0:
		return
	centre /= standing
	hold += (centre - hold).limit_length(gape * WORK_IN)


## Follows the hold onto a piece that has come apart under the jaws, so what they
## are left holding is a place on the piece they kept rather than a point in the
## air where the rest of it used to be.
func reseat() -> void:
	if part == null:
		return
	var best := Vector2.ZERO
	var best_distance: float = INF
	var found: bool = false
	for cell in part.cells:
		if part.gone[cell] != 0:
			continue
		var at: Vector2 = part.local_centre_of(cell)
		var d: float = hold.distance_squared_to(at)
		if d < best_distance:
			best_distance = d
			best = at
			found = true
	if found:
		hold = best


## Rise and fall of one chew. Peaks immediately and dies away, because a jaw
## closing is fast and its recovery is not.
func _chew_curve() -> float:
	if worked >= CHEW_SETTLE:
		return 0.0
	var t: float = worked / CHEW_SETTLE
	return (1.0 - t) * (1.0 - t)
