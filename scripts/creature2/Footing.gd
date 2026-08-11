## Whether this body is standing on anything, and what happens when it stops —
## Balance's successor, reading the census for what a limb still has in it.
##
## The measurement is a lever, and it is the same one an engineer takes of a beam
## on two supports. A body is carried at two places — the shoulder girdle and the
## hip girdle — and where its weight sits between them decides how much of it lands
## on each. That is all `need` is. Against it, `able` is how much leg is actually
## under each girdle: how many limbs, and how much of each is still muscle rather
## than hole. A girdle that must hold more than it can hold is a girdle that folds.
##
## Nothing here is a support polygon and nothing here is about the feet being in
## the right *place* — a walking animal is out over the edge of its own feet several
## times a second, and any measure honest enough to notice would condemn every gait
## in the game. What separates a stride from a fall is not geometry at an instant;
## it is whether there is enough limb under the animal to get back under it. So that
## is what is asked, and the clock is what gives it time.
##
## What comes out is not a mode. `hold` is a fraction spent through the joints like
## every other load — a body that is not being held up folds its legs, because the
## height it rides at is read off how extended they are — and only when it has been
## unable to get back under itself for longer than it takes to swing a leg into
## place does it go down.
class_name Footing
extends RefCounted

## How much of the whole animal one sound limb can hold. Over a quarter by a good
## margin, because legs are not sized to the edge of failure: an animal that sagged
## whenever it lifted a foot could not walk. Sized so a four-legged build stands
## comfortably on three, a two-legged one stands on the pair it has, and a single
## leg holds up half a body and no more.
const LIMB_SHARE: float = 0.62

## Least hold a body can have and still count as standing on its legs.
const STANDING_MIN: float = 0.55

## How many limb swings a creature may be unsupported before a stumble becomes a
## fall. Quoted in the animal's own swings rather than in seconds, because that is
## what it measures: recovering means getting a leg back under yourself, so the time
## available is the time this body's own leg takes to get there.
const RECOVERY_SWINGS: float = 1.8
## How much longer that takes a body whose limbs have stopped answering. A pendulum
## does not slow down because the animal is weak; getting a leg back underneath
## yourself very much does, and this is that said once and on purpose.
const SPENT_RECOVERY: float = 2.1

## How much faster the recovery clock runs on a body being toppled as hard as a body
## can be toppled — the difference between a stumble and a fall.
const TOPPLE_URGENCY: float = 3.0

## How much of a girdle's joint travel is spent folding under a body it cannot hold.
## All of it at total failure: legs going out from under an animal is exactly a joint
## arriving at its own stop.
const GIVE: float = 1.0


## How well this body is being held up, 0..1 — the worse of the two girdles, because
## a body has only one underside and the end that is failing decides.
var hold: float = 1.0
## What each girdle has to hold as a share of the whole animal, and what it can.
var need: Vector2 = Vector2(0.5, 0.5)
var able: Vector2 = Vector2(1.0, 1.0)
## How long this body has been unable to hold itself up, and how long it is allowed
## to be. A stumble is the first shorter than the second.
var unheld: float = 0.0
var grace: float = 0.25
## True the moment it has run out — read once by the creature, which owns what
## happens next. Nothing here calls a collapse: this file measures, and being
## measured to have failed is not the same as being told to fall over.
var failed: bool = false


func reset() -> void:
	hold = 1.0
	need = Vector2(0.5, 0.5)
	able = Vector2(1.0, 1.0)
	unheld = 0.0
	failed = false


## Re-derives the whole thing from the body and the legs under it. After the gait,
## because what a limb can bear is something the gait has just read, and after the
## census, because where the weight is is a measurement of the counted body.
## `airborne` switches the question off rather than answering it differently: a
## creature in the air is not failing to stand, it is not standing, and the clock
## does not run — which is what makes a leap safe to take.
func update(delta: float, tread: Tread, poise: Poise, corpus: Corpus,
		loco: Locomotor, swing: float, airborne: bool, alive: bool) -> void:
	failed = false
	var answering: float = minf(loco.girdle_drive.x, loco.girdle_drive.y) \
		if loco != null else 1.0
	grace = maxf(swing, 0.05) * RECOVERY_SWINGS \
		* lerpf(SPENT_RECOVERY, 1.0, clampf(answering, 0.0, 1.0))
	if not alive:
		return
	if airborne or tread == null or not tread.measured:
		# Nothing to stand on and nothing to be wrong about. The clock is wound back
		# rather than paused, because a creature that lands has its feet under it
		# again and a leap should not carry a debt into the next stride.
		unheld = 0.0
		hold = 1.0
		return

	need = _reactions(tread, poise, loco)
	able = _capacity(tread, corpus, loco)
	hold = minf(
		1.0 if need.x <= 0.0001 else clampf(able.x / need.x, 0.0, 1.0),
		1.0 if need.y <= 0.0001 else clampf(able.y / need.y, 0.0, 1.0))

	# The clock, and the only thing here with any memory: a body momentarily short
	# of support is mid-stride; one short of it for longer than it takes to put a leg
	# out has nothing left to put out.
	if hold >= STANDING_MIN:
		unheld = 0.0
		return
	# How fast that clock runs is gravity's answer rather than a constant. An animal
	# whose weight is still nearly over its feet has all the time its legs need; one
	# whose centre is out past its own support is already turning about the edge of
	# it, and how quickly is a lever — the overhang against the height it hangs at.
	unheld += delta * _urgency(poise)
	failed = unheld >= grace


## How much faster than its own swing a body is running out of time. One at rest
## over its feet and rising with the topple, quoted against the pull itself so the
## ratio means something: half of PULL is the hardest a body can ever be toppled.
## Nothing at all on a body whose line is inside its feet — which is every walking
## animal on every ordinary stride, and the whole reason this can be added to the
## clock without shortening a single gait.
func _urgency(poise: Poise) -> float:
	if poise == null or not poise.posed or poise.feet == 0 or poise.clearance >= 0.0:
		return 1.0
	var over: float = Gravity.topple(poise.overhang.length(), poise.height)
	return 1.0 + (TOPPLE_URGENCY - 1.0) * clampf(over / (Gravity.PULL * 0.5), 0.0, 1.0)


## What each girdle has to carry, as a share of the whole animal: the lever rule on
## a beam over two supports, with the weight where the census says it is — so a long
## tail genuinely shifts the load onto the hips, a big head genuinely shifts it
## forward, and a haunch bitten hollow stops counting the moment the flesh is gone.
## A girdle whose limbs do not reach the ground carries nothing and everything it
## would have carried goes to the other one, which is not a special case for
## two-legged animals but the same sentence the gait already says about where the
## shoulders of one are held.
func _reactions(tread: Tread, poise: Poise, loco: Locomotor) -> Vector2:
	if loco != null and not loco.forelimbs_bear:
		return Vector2(0.0, 1.0)
	var fore := Vector2.ZERO
	var rear := Vector2.ZERO
	var counted := Vector2.ZERO
	for foot in tread.feet:
		if foot.fore:
			fore += foot.socket
			counted.x += 1.0
		else:
			rear += foot.socket
			counted.y += 1.0
	if counted.x <= 0.0 or counted.y <= 0.0:
		return Vector2(0.5, 0.5)
	fore /= counted.x
	rear /= counted.y
	var centre: Vector2 = poise.centre if poise != null and poise.posed \
		else (fore + rear) * 0.5
	var axis: Vector2 = fore - rear
	var span: float = axis.length_squared()
	if span < 0.0001:
		return Vector2(0.5, 0.5)
	# How far along the girdle line the weight sits, 0 at the hips and 1 at the
	# shoulders. Clamped, because a centre out beyond a girdle is a real thing — a
	# browsing animal with its neck out — and what it means is that the far girdle
	# carries all of it, not that it carries more than all.
	var t: float = clampf((centre - rear).dot(axis) / span, 0.0, 1.0)
	return Vector2(t, 1.0 - t)


## And what each girdle can hold: every limb that still reaches the ground and still
## has muscle in it, worth LIMB_SHARE of the animal apiece. A limb the gait has in
## the air counts — a leg mid-swing is not a leg that has gone, and an animal is not
## momentarily unable to stand because it is walking.
func _capacity(tread: Tread, corpus: Corpus, loco: Locomotor) -> Vector2:
	var out := Vector2.ZERO
	var bears: bool = loco == null or loco.forelimbs_bear
	for foot in tread.feet:
		if foot.fore and not bears:
			continue
		var sound: float = corpus.soundness(foot.key) if corpus != null else 1.0
		out[0 if foot.fore else 1] += clampf(sound, 0.0, 1.0)
	return out * LIMB_SHARE


## How much of its joint travel each girdle spends giving way, as the same signed
## pair the crouch and the jump are quoted in — positive folds. The whole of what
## losing your footing looks like, and there is no animation in it: a body that is
## not being held up sinks, because the height it rides at is read off how extended
## its legs are and this is what extends them less. Per girdle, so an animal that
## has lost its hind legs goes down at the back and stays up at the front.
func give() -> Vector2:
	return Vector2(_sag(0), _sag(1))


func _sag(girdle: int) -> float:
	if need[girdle] <= 0.0001:
		return 0.0
	return GIVE * (1.0 - clampf(able[girdle] / need[girdle], 0.0, 1.0))
