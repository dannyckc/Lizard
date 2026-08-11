## Whether this body is standing on anything, and what happens when it stops.
##
## The last thing in the simulation that gravity was not allowed to decide. A
## creature went down when its brain stopped — `BodyState.collapsed`, read off
## consciousness — and that is one real way for an animal to fall over and not the
## common one. The common one is mechanical: the legs that were holding it up stop
## being able to. An animal with both hind legs bitten through is fully conscious
## and cannot stand, and until this file existed it stood there anyway.
##
## The measurement is a lever, and it is the same one an engineer takes of a beam
## on two supports. A body is carried at two places — the shoulder girdle and the
## hip girdle — and where its weight sits between them decides how much of it lands
## on each. That is all `need` is. Against it, `able` is how much leg is actually
## under each girdle: how many limbs, how much of each is still bone rather than
## hole, and how much of the muscle holding them extended is still answering its
## nerve. A girdle that must hold more than it can hold is a girdle that folds.
##
## Nothing here is a support polygon and nothing here is about the feet being in
## the right *place*, which was the first thing this file tried and the wrong one.
## A walking animal is out over the edge of its own feet several times a second —
## that is what walking is — and any measure honest enough to notice would condemn
## every gait in the game. What separates a stride from a fall is not geometry at
## an instant; it is whether there is enough limb under the animal to get back
## under it. So that is what is asked, and the clock below is what gives it time.
##
## Three things decide the answer, and they are exactly the three the design calls
## for. The **skeleton** is `Limb.carry`, which is already how much bone is left in
## that leg. The **muscle** is `BodyState.locomotion`, which is already how much of
## the drive still reaches it. And **contact with the ground** is `forelimbs_bear`,
## which is already whether that girdle's limbs reach the floor at all — a
## two-legged animal's forelimbs are not damaged, they simply do not come down, so
## everything they would have carried is carried by the hips and the back instead.
## Not one of the three is a new parameter. Every one of them is a number some
## other file was already measuring for some other reason, which is the whole
## reason this can be believed.
##
## What comes out is not a mode. `hold` is a fraction, and it is spent through the
## joints like every other load in the game — a body that is not being held up
## folds its legs, because the height it rides at is read off how extended they are
## — and only when it has been unable to get back under itself for longer than it
## takes to swing a leg into place does it go down.
class_name Balance
extends RefCounted

## How much of the whole animal one sound limb can hold.
##
## Over a quarter, and by a good margin, because legs are not sized to the edge of
## failure: an animal that sagged whenever it lifted a foot would be one that could
## not walk. Sized so a four-legged build stands comfortably on three, a two-legged
## one stands on the pair it has, and a single leg holds up half a body and no
## more. Those three consequences are the calibration; there is nothing else in the
## file to tune.
const LIMB_SHARE: float = 0.62

## Least hold a body can have and still count as standing on its legs. Below this
## it is going down; what it does on the way is fold, which is the same thing it
## does at any other value.
const STANDING_MIN: float = 0.55

## How many limb swings a creature may be unsupported before a stumble becomes a
## fall.
##
## Quoted in the animal's own swings rather than in seconds, because that is what
## it measures: recovering means getting a leg back under yourself, so the time
## available is the time this body's own leg takes to get there. A small quick
## animal is given a tenth of a second and an elephant most of one, and neither
## number is written down anywhere.
const RECOVERY_SWINGS: float = 1.8
## How much longer that takes a body whose limbs have stopped answering.
##
## The same statement Gait already makes about a spent limb — weakness is slowness
## as well as shortness, see Gait.SWING_SLOWEST — asked at the one other place that
## wants to know how long a leg takes to get somewhere. It belongs here explicitly
## because it used to arrive by accident: `Locomotion.swing_time` divided the free
## pendulum by the muscle available, so a creature with no muscle left was handed a
## swing nearly three times what gravity alone would have given it, and the
## recovery clock inherited the whole of that. A pendulum does not slow down
## because the animal is weak; getting a leg back underneath yourself very much
## does, and this is that, said once and on purpose.
const SPENT_RECOVERY: float = 2.1

## How much faster the recovery clock runs on a body being toppled as hard as a
## body can be toppled. See `_urgency` — a creature whose weight is still over
## its feet gets the whole window this file was calibrated with, and one that is
## already going over gets a fraction of it, which is the difference between a
## stumble and a fall and used to be no difference at all.
const TOPPLE_URGENCY: float = 3.0

## How much of a girdle's joint travel is spent folding under a body it cannot
## hold. All of it at total failure: legs going out from under an animal is
## exactly a joint arriving at its own stop.
const GIVE: float = 1.0


## How well this body is being held up, 0..1 — the worse of the two girdles,
## because a body has only one underside and the end that is failing is the end
## that decides.
var hold: float = 1.0
## What each girdle has to hold, as a share of the whole animal, and what it can.
## x is the fore girdle and y the hind, matching every other pair of girdle
## readings in the simulation.
var need: Vector2 = Vector2(0.5, 0.5)
var able: Vector2 = Vector2(1.0, 1.0)
## How long this body has been unable to hold itself up, in seconds, and how long
## it is allowed to be. A stumble is the first shorter than the second.
var unheld: float = 0.0
var grace: float = 0.25
## True the moment it has run out — read once by the creature, which owns what
## happens next. Nothing here calls a collapse: this file measures, and being
## measured to have failed is not the same as being told to fall over.
var failed: bool = false
## Where the weight actually is, on the ground plane. Kept for the debug overlay
## and for the tests, which have no other way to see a lever that is never drawn.
var centre: Vector2 = Vector2.ZERO


func reset() -> void:
	hold = 1.0
	need = Vector2(0.5, 0.5)
	able = Vector2(1.0, 1.0)
	unheld = 0.0
	failed = false


## Re-derives the whole thing from the body and the legs under it.
##
## Runs after the gait, because what a limb can bear is something the gait has just
## read, and after the physique, because where the weight is is a measurement of
## the drawn body. `airborne` switches the question off rather than answering it
## differently: a creature in the air is not failing to stand, it is not standing,
## and the clock does not run — which is what makes a leap safe to take.
func update(delta: float, limbs: Array[Limb], body: BodyShape, spine: Spine,
		plumb: Plumb, state: BodyState, loco: Locomotion,
		swing: float, airborne: bool, alive: bool) -> void:
	failed = false
	grace = maxf(swing, 0.05) * RECOVERY_SWINGS * lerpf(SPENT_RECOVERY, 1.0,
		clampf(state.locomotion, 0.0, 1.0) if state != null and state.impaired else 1.0)
	if not alive:
		return
	if airborne or body == null or spine == null or body.anchors.is_empty():
		# Nothing to stand on and nothing to be wrong about. The clock is wound back
		# rather than paused, because a creature that lands has its feet under it
		# again and a leap should not carry a debt into the next stride.
		unheld = 0.0
		hold = 1.0
		return

	need = _reactions(body, spine, plumb, loco)
	able = _capacity(limbs, state, loco)
	hold = minf(
		1.0 if need.x <= 0.0001 else clampf(able.x / need.x, 0.0, 1.0),
		1.0 if need.y <= 0.0001 else clampf(able.y / need.y, 0.0, 1.0))

	# The clock, and it is the only thing in the file with any memory. A body that
	# is momentarily short of support is mid-stride; one that has been short of it
	# for longer than it takes to put a leg out has nothing left to put out.
	if hold >= STANDING_MIN:
		unheld = 0.0
		return
	# How fast that clock runs is gravity's answer rather than a constant, and it
	# is the one thing the recovery window could never say for itself. An animal
	# whose weight is still very nearly over its feet has all the time its legs
	# need; one whose centre of gravity is right out past its own support is
	# already turning about the edge of it, and how quickly is a lever — the
	# overhang against the height it hangs at, which is exactly `Gravity.topple`.
	#
	# Never *slower* than the swing clock, because the swing clock is the real
	# limit on getting a leg back underneath yourself and no amount of being
	# nearly balanced buys extra time to do it in.
	unheld += delta * _urgency(plumb)
	failed = unheld >= grace


## How much faster than its own swing a body is running out of time.
##
## One at rest over its feet, and rising with the topple — the horizontal
## acceleration gravity is giving the centre of gravity about the edge of the
## support it has left. Quoted against the pull itself so the ratio means
## something: half of `PULL` is the hardest a body can ever be toppled, which is
## a centre of gravity as far out as it is high, and that is where this runs at
## its ceiling.
##
## Off `Plumb` entirely, so it is nothing at all on a body whose line is inside
## its feet — which is every walking animal on every ordinary stride, and the
## whole reason this can be added to the clock without shortening a single gait.
func _urgency(plumb: Plumb) -> float:
	if plumb == null or not plumb.posed or plumb.feet == 0 or plumb.clearance >= 0.0:
		return 1.0
	var over: float = Gravity.topple(plumb.overhang.length(), plumb.height)
	return 1.0 + (TOPPLE_URGENCY - 1.0) * clampf(over / (Gravity.PULL * 0.5), 0.0, 1.0)


## What each girdle has to carry, as a share of the whole animal.
##
## The lever rule on a beam over two supports: weight nearer the shoulders lands on
## the shoulders. Where the weight is is the animal's actual centre of gravity —
## see `Plumb`, which counts it off the same cells the scales weigh — so a long
## tail genuinely shifts the load onto the hips, a big head genuinely shifts it
## forward, a dense skull shifts it further than a light one of the same size, and
## a haunch bitten hollow stops counting the moment the flesh is gone. None of
## those needed saying.
##
## It was the middle of the drawn silhouette until this file had a centre of
## gravity to read, and the difference is not academic. An outline has no density,
## so bone and fat weighed the same; it has no legs, so a quarter of the animal was
## missing from a measurement of where the animal was; and it does not change when
## the creature is eaten, so a body chewed open behind the hips went on loading its
## hind legs with weight that was lying on the floor.
##
## A girdle whose limbs do not reach the ground carries nothing, and everything it
## would have carried goes to the other one. That is not a special case for
## two-legged animals; it is the same sentence `Gait` already says about where the
## shoulders of one are held — by the back — and it falls out of `forelimbs_bear`
## without this file knowing what a biped is.
func _reactions(body: BodyShape, spine: Spine, plumb: Plumb,
		loco: Locomotion) -> Vector2:
	var anchors: Dictionary = body.anchors
	if not anchors.has("FL") or not anchors.has("RL"):
		return Vector2(0.5, 0.5)
	var fore: Vector2 = (anchors["FL"].pos + anchors["FR"].pos) * 0.5
	var rear: Vector2 = (anchors["RL"].pos + anchors["RR"].pos) * 0.5
	# A body whose cells have not been posed yet has no world centre to read and
	# is not standing on anything either; the middle of the girdles is the honest
	# answer for that one tick, and it is the answer this file gave for every tick
	# before there was a lattice to ask.
	centre = plumb.centre if plumb != null and plumb.posed else (fore + rear) * 0.5
	if loco != null and not loco.forelimbs_bear:
		return Vector2(0.0, 1.0)
	var axis: Vector2 = fore - rear
	var span: float = axis.length_squared()
	if span < 0.0001:
		return Vector2(0.5, 0.5)
	# How far along the girdle line the weight sits, 0 at the hips and 1 at the
	# shoulders. Clamped, because a centre of mass out beyond a girdle is a real
	# thing — a browsing animal with its neck out — and what it means is that the
	# far girdle is carrying all of it, not that it is carrying more than all.
	var t: float = clampf((centre - rear).dot(axis) / span, 0.0, 1.0)
	return Vector2(t, 1.0 - t)


## And what each girdle can hold.
##
## Every limb that is still attached, still reaches the ground and still has bone
## in it, worth `LIMB_SHARE` of the animal apiece. A limb the gait has in the air
## counts: a leg mid-swing is not a leg that has gone, and an animal is not
## momentarily unable to stand because it is walking.
##
## Then narrowed by how much of the muscle is answering, because a leg that is
## present and unable to resist is a leg folding. Read off the functional state
## rather than the tissue, and the distinction is the one `Physique` already draws:
## a limb that is entirely there and simply not answering its nerve contributes its
## weight and none of its support.
func _capacity(limbs: Array[Limb], state: BodyState, loco: Locomotion) -> Vector2:
	var out := Vector2.ZERO
	var bears: bool = loco == null or loco.forelimbs_bear
	for limb in limbs:
		if limb.severed or limb.carried:
			continue
		if limb.pair == Limb.FRONT and not bears:
			continue
		out[0 if limb.pair == Limb.FRONT else 1] += clampf(limb.carry, 0.0, 1.0)
	out *= LIMB_SHARE
	if state != null and state.impaired:
		out *= clampf(state.locomotion, 0.0, 1.0)
	return out


## How much of its joint travel each girdle spends giving way, as the same signed
## pair `Jump` and the crouch are quoted in — positive folds.
##
## This is the whole of what losing your footing looks like, and there is no
## animation in it: a body that is not being held up sinks, because the height it
## rides at is read off how extended its legs are and this is what extends them
## less. Per girdle, so an animal that has lost its hind legs goes down at the back
## and stays up at the front — which is the shape of a real collapse and not
## something anybody had to pose.
##
## Zero on any girdle with enough leg under it, which on a sound animal is both of
## them. That is what keeps this out of every ordinary stride: a healthy body is
## not partly collapsing, it is standing.
func give() -> Vector2:
	return Vector2(_sag(0), _sag(1))


func _sag(girdle: int) -> float:
	if need[girdle] <= 0.0001:
		return 0.0
	return GIVE * (1.0 - clampf(able[girdle] / need[girdle], 0.0, 1.0))
