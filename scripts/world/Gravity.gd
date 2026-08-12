## The pull everything in this world is under, and the one place it is applied.
##
## The vertical axis was built one consumer at a time. A creature got a height
## because a leap needed somewhere to go; a leg got one because a bite had to be
## able to miss over the top of it; a piece of meat got a band at zero because the
## jaws had to be able to reach it lying there. Each of those is right on its own,
## and together they said something false: that the only thing in the habitat
## which falls is an animal that jumped, and that everything else is simply
## *already* on the floor and always was.
##
## So this file owns the pull, and it owns it for everything. Not as a service
## anything calls into — a body is not pulled downward by a manager — but as the
## one statement of how fast a thing gains speed when nothing is holding it up,
## and the one integrator that turns that into a height. `Elevation` is a creature
## under it with wings in the way; `Fall` below is everything else, which is to
## say a lump of anatomy with nothing in the way at all.
##
## Two rules, and every consequence in the game comes out of them:
##
##   * **Nothing is exempt by being unimportant.** A severed leg falls from the
##     shoulder it came off, at the same acceleration the animal it left would
##     have fallen at. It was at a height because the lattice said so, and the
##     lattice is not a decoration.
##   * **Support is a claim that has to be true.** A thing stops falling when it
##     arrives at something — the floor, a surface, the top of an obstacle — and
##     not when it reaches the number zero. `floor_height` is that surface, and it
##     is asked for on every integration rather than assumed, because the habitat
##     has terrain in it.
##   * **The pull acts at a place.** For a lump of meat that is a distinction
##     without a difference — a falling thing falls, and where the middle of it is
##     changes nothing. For a body standing on something it is the whole
##     difference between staying up and going over, because a supported body is
##     not free to fall and *is* free to turn about the edge of its support. Where
##     the weight of an animal is is `Plumb`; what the pull does to it from there
##     is `topple` below.
##
## Nothing here stores a mass. Weight decides how hard a thing is to *move* — that
## is `Physique`, and the contact solver already divides by it — but it does not
## decide how fast it falls, and a simulation in which a heavy part sank faster
## than a light one would be wrong about the one thing everybody can check. That
## holds for the topple too, and for the same arithmetic: the mass is on both
## sides of it and cancels.
class_name Gravity
extends RefCounted

## Pull toward the ground plane, in pixels per second squared.
##
## Sized against the habitat rather than against Earth: bodies here are drawn a
## couple of hundred pixels long, and a leap has to be over inside a second or it
## reads as the creature being thrown rather than jumping. Lived on `Elevation`
## until there was more than one thing falling; it is here now because the day two
## files each keep their own is the day a dropped leg and the animal that dropped
## it disagree about what a fall is.
const PULL: float = 1500.0

## Below this a thing is resting on whatever is under it. Well under a pixel, so
## nothing can hover imperceptibly and no arrival can be missed.
const TOUCHDOWN: float = 0.05

## Share of its arrival speed a loose body keeps as a bounce. Low, and it is meat
## rather than rubber: what this buys is the half-beat of settling that stops a
## dropped limb looking pasted to the floor, and it is gone within a few tenths of
## a second whatever it lands from.
const RESTITUTION: float = 0.18
## Below this a bounce is not worth having and the thing is simply down. Quoted as
## a speed rather than as a count of bounces, so a part dropped from a great height
## bounces a few times and one rolled off a kerb does not bounce at all.
const BOUNCE_FLOOR: float = 60.0


## How fast something has to leave the ground to peak at `peak` pixels.
##
## The ballistic solution and nothing else. Here rather than at the three call
## sites that had it because it is the same physics each time and they were
## already drifting: a jump reads it to work out how hard the legs threw the body,
## the body reads it again to work out how much of that went forward, and the
## flight phase reads it a third time to normalise a tuck against the launch.
static func launch_rate(peak: float) -> float:
	return sqrt(2.0 * PULL * maxf(peak, 0.0))


## The other way round: how high something that is going this fast will get.
static func peak_of(rate: float) -> float:
	return rate * rate / (2.0 * PULL)


## How hard a body is being tipped over, in px/s² sideways at its own centre of
## gravity.
##
## The one thing the pull could not say for itself. Everything above treats a
## body as a height with a speed, which is the whole truth about a thing falling
## through open air and not quite the truth about one standing on something: a
## creature on its feet is not free to fall, it is free to *turn* about the edge
## of whatever is holding it up, and whether it does is a question about where
## its weight is rather than about how high it is.
##
## So this is gravity asked at a point. `over` is how far the centre of gravity
## hangs past the edge it is pivoting on and `high` is how far above that edge it
## hangs; the pull acts at the centre, the edge takes the reaction, and what comes
## out is one line of statics — torque `g·over` against a moment of inertia
## `over² + high²`, resolved back to the horizontal at the centre itself.
##
## Two consequences are worth stating because they are the whole reason a body
## reads as heavy. A centre exactly over the edge is not tipped at all however
## high it is, which is why a balanced animal can stand on very little. And the
## hardest anything can ever be tipped is half the pull, at a centre as far out as
## it is high — past that the body is not toppling, it is on its way to lying
## down. Nothing here integrates: what a topple *does* belongs to whatever is
## being tipped, and there is exactly one thing in the game that is. See Balance.
##
## No mass, for the same reason nothing else here has one: it cancels out of both
## sides of the same equation, and a heavy animal does not fall over faster than a
## light one of the same shape.
static func topple(over: float, high: float) -> float:
	var lever: float = maxf(high, 0.0)
	var arm: float = maxf(over, 0.0)
	var span: float = arm * arm + lever * lever
	if span < 0.0001:
		return 0.0
	return PULL * arm * lever / span


## How long until a body at `height` moving at `rate` reaches `floor_height`, in
## seconds. Positive `rate` is upward, so this covers the whole arc — a thing
## still rising gets the time to the top *and* the time back down, in one root.
static func fall_time(height: float, rate: float, floor_height: float = 0.0) -> float:
	var drop: float = maxf(height - floor_height, 0.0)
	return (rate + sqrt(maxf(rate * rate + 2.0 * PULL * drop, 0.0))) / PULL


## A height with nothing holding it up.
##
## The whole of what it means to be a physical object in the vertical axis, for
## everything that is not a creature: a place above the ground, a speed it is
## going there at, and the pull. A creature has `Elevation` instead, and the
## difference between the two files is exactly the difference between a body with
## wings, legs and a ceiling and a body with none of those — not a difference of
## opinion about gravity, which is why the constant is above both of them.
##
## Deliberately a *thing that falls* rather than a thing that is simulated. It has
## no mass, no drag and no shape, because a bag of meat tumbling to the floor has
## nothing interesting to say about any of the three, and because the moment it did
## the habitat would need a solver instead of an integrator.
class Fall extends RefCounted:
	## Height above the ground plane, in world pixels — the same unit as x and y.
	var height: float = 0.0
	## Rate of change of that, in pixels per second. Positive is upward.
	var rate: float = 0.0
	## The surface currently underneath. Not always zero: the habitat has terrain,
	## and a leg dropped on a rock lies on the rock.
	var floor_height: float = 0.0
	## True on the tick it arrived, with the speed it arrived at. The pair is read
	## the same way `Elevation` reads its own — a landing is over the instant it
	## happens, so what it was worth has to be kept.
	var landed: bool = false
	var impact: float = 0.0
	## Whether it has come to rest. A thing at rest costs nothing per tick, which is
	## what makes it safe for the habitat to have a floor covered in parts.
	var resting: bool = true

	## Puts a body at a height with a speed, and wakes it up.
	##
	## What `receive` calls when a part comes off an animal, and the whole of why a
	## severed leg falls from the shoulder rather than appearing at the feet: the
	## height it starts at is the height the tissue was standing at, which the
	## lattice already knew.
	func start(from_height: float, from_rate: float = 0.0, surface: float = 0.0) -> void:
		floor_height = surface
		height = maxf(from_height, surface)
		rate = from_rate
		landed = false
		impact = 0.0
		resting = height <= surface + Gravity.TOUCHDOWN and from_rate <= 0.0

	## One tick of it.
	##
	## `surface` is what is underneath *now*, asked every time rather than kept,
	## because a part sliding across the habitat passes over ground that changes
	## height under it. A part that is resting and whose floor has not moved does no
	## work at all — the first two lines are the whole cost of a settled world.
	##
	## `pull_scale` is for the one caller that needs a different pull rather than a
	## different gravity: a flier folding up and diving is being pulled harder than
	## it is falling, because it is also pointing itself down. Everything else
	## leaves it alone.
	func advance(delta: float, surface: float = 0.0, pull_scale: float = 1.0) -> void:
		landed = false
		floor_height = surface
		if resting:
			# Something moved the ground out from under it — walked off a ledge, or
			# the obstacle it was lying on was removed. It is falling again, and
			# nothing had to notice: being at rest is a statement about the surface
			# rather than a state anything set.
			if height <= surface + Gravity.TOUCHDOWN:
				height = surface
				return
			resting = false

		rate -= Gravity.PULL * maxf(pull_scale, 0.0) * delta
		height += rate * delta
		if height > surface:
			return

		# Arrived. What it was going when it got there is kept, because the world
		# prices a landing off the speed — a part dropped from a shoulder makes a
		# sound worth hearing and one nudged off a stone does not.
		impact = absf(rate)
		height = surface
		landed = true
		if impact >= Gravity.BOUNCE_FLOOR:
			rate = impact * Gravity.RESTITUTION
			height = surface + Gravity.TOUCHDOWN
			return
		rate = 0.0
		resting = true

	## A landing whose remainder something else absorbs: comes to rest exactly as
	## `rest_on` does, but the tick's own landing record (`landed`, `impact`) is
	## left standing for whoever reads it after — the landing happened, the body
	## that caught itself on its legs is simply declining the bounce.
	func absorb_landing(surface: float) -> void:
		floor_height = surface
		height = surface
		rate = 0.0
		resting = true

	## Puts a body down wherever it is, immediately. What happens when whatever was
	## holding it up stops holding it and there is nothing to fall through — a
	## collapse rather than a landing.
	func rest_on(surface: float) -> void:
		floor_height = surface
		height = surface
		rate = 0.0
		landed = false
		resting = true

	func is_airborne() -> bool:
		return height > floor_height + Gravity.TOUCHDOWN
