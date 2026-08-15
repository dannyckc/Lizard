## How far over the body is held — the attitude state, and the one place it
## changes (docs/V2_DESIGN.md §4.1, the revisit clause).
##
## v2's body had three dynamic degrees of freedom and one assigned vertical: the
## plan velocity and the turn rate integrate (Impetus, Travel), and the height of
## the trunk was a *measurement* of the legs (`Armature.fore_carry`) with
## `Gravity.Fall` carrying the one scalar clearance under it. Nothing anywhere
## owned how far over the animal was leaning, so a body could not be pushed down,
## could not sink on one side, and could not fall onto its flank at all:
## `Armature.collapse` dropped every node flat at its plan position, and
## belly-down was the only pose a downed creature had. `Clash` went as far as
## computing a true 3D contact point and then threw its height away, because
## there was nothing to hand it to.
##
## This file is that missing state, and deliberately only that: **roll** — how
## far the body is heeled over about its own fore-and-aft axis — with its rate
## and the torques that move it. Pitch and heave are the same idea about the
## other two axes and wait for their own phase; they touch the carry seam, where
## roll is purely additive because nothing owned roll at all.
##
## The bargain with the 2.5D decision is exact, and worth stating because it is
## what leaves the plan solver untouched: **the heel's geometry lives here and
## nowhere else.** Poise goes on measuring an upright body's weight against its
## upright feet; the arc that weight swings through as the body goes over is one
## line of statics below, never a re-projection of the chain. What the rest of
## the body does with the answer is *express* it — the Z channel heels the trunk
## and the limb sockets, the skin rolls its ring frames — and those expressions
## feed back honestly, because a socket lifted out of reach really does take its
## foot out of the support hull Poise measures next tick.
##
## Three terms, and every behaviour is one of them winning:
##
##   * **The weight, about the foot it is turning over.** The pivot is the
##     outermost planted foot on the side the body is going — not the hull's
##     nearest boundary and not the body's own spine, because a creature going
##     over turns about its feet. `M·g·(H·sin θ − e·cos θ)`: restoring while the
##     line is still inside that foot, overturning past `tan θ = e/H`, and
##     exactly zero at level with both sides down, which is why a standing body
##     has no attitude and needs none damped out of it.
##   * **The legs fighting to keep it there.** A trotting quadruped is on two
##     feet half the time and does not fall over, because the girdles hold the
##     trunk level. That is muscle, so it is written the way every other muscle
##     in v2 is (`Impetus.propel`): a *demand* off the error, **delivered only as
##     far as the body can press**, with the ceiling derived from the girdle's
##     own half-base and the census's engine and scaled by how many feet are
##     actually down. Nothing authors a threshold — the threshold is where the
##     demand stops fitting under the ceiling, which is what `strained` says, and
##     it moves on its own when the animal is chewed, tired-footed or airborne.
##   * **An impulse is an impulse.** A push that lands somewhere lands at a
##     height, and the angular half of it is `M·h·Δv` — the same shove seam
##     Impetus already owns, carrying the component the flat one discarded.
##
## All three divide by the same inertia, and *which* inertia is not a detail: a
## body standing on the ground turns about the ground, so the moment is the
## census's own about the centre plus `M·H²` (parallel axis, the other end of the
## same shift `Corpus.roll_inertia` already makes). A body in the air turns about
## its own centre and gets that number bare. It is the whole difference between a
## cat that takes half a second to go over and one that snaps flat in three
## frames.
##
## One attitude owner, beside the one pull (`Gravity.PULL` is read here;
## `Gravity.Fall` stays the only vertical integrator) and the one velocity
## (Impetus). Travel is the scribe, as it is for every other creature field.
class_name Keel
extends RefCounted

## Positive roll is the animal's own right side down — the same handedness the
## rest of v2 uses, where `Armature.perp` is the animal's right and `Contour`'s
## θ = π/2 sector is its right flank.
##
## Past this much heel a quadruped is not stumbling, it is going over: no rescue
## step widens a base far enough to bring this back, and the dynamics have long
## since run away by the time it is reached. Nothing is decided by the number —
## it is where the review stops waiting.
const DOWN: float = 0.96

## Where a body that has gone over comes to rest: on its flank.
const FLANK: float = PI * 0.5

## What the girdles can hold the trunk level against, in body weights at the
## stance's own half-base — so the righting a body has is a statement about how
## wide it stands and how much engine the census left it, and a creature bitten
## through one shoulder holds itself worse without anything being told.
const RIGHTING: float = 2.0

## How the righting demand is shaped: a spring back to level and the brace on
## its rate. Not a physics — this is the *ask*, and what is delivered is it
## clamped, exactly as a desired velocity is in Impetus. Near-critical, so a
## caught wobble settles rather than rings.
const STIFF: float = 60.0
const BRACE: float = 15.0

## What damps the roll with no muscle in it at all — tissue, not tone. The only
## term an airborne or dead body still has.
const SLACK: float = 0.6

## How fast a body that has gone over finishes arriving on its flank, per
## second. Not a torque: the animal is over, the roll is only running out its
## own arc, and a carcass settling is `Armature`'s tumble rather than this
## file's business.
const LIE: float = 7.0

## The most roll rate anything may hold, rad/s — a cap on the lever arithmetic
## (a contact point measured a hair off the surface must not be able to spin an
## animal), not a second physics. Well past a cat righting itself in mid-air.
const RATE_MAX: float = 8.0

## Below this the body is level and both sides are down; there is no side for a
## torque to act on and no heel for anything to express.
const LEVEL: float = 0.0005

## How far over a body has to be *going* when it goes down for it to finish on
## that flank. Under it the animal simply dropped where it stood — a stopped
## heart, a severed cord — and a heap with no lean in it lands on its belly, which
## is the pose every v2 carcass has had until now. Latched at the moment of the
## collapse and never re-read, so float noise on a level body cannot roll a corpse
## over half a second after it died.
const TIPPED: float = 0.10


## The heel, radians, right side down positive. The one owner.
var roll: float = 0.0
## ...and how fast it is changing, rad/s.
var rate: float = 0.0

## Baked off the census: what the body weighs and how hard it is to roll about
## its own centre. Re-read whenever the census moves, so a creature bitten
## hollow through one flank genuinely rolls easier.
var mass: float = 1.0
var inertia: float = 1.0

## Readouts of the last balance, for the review and the HUD, never inputs here.
## `side` is which way the body is going (+1 right, −1 left, 0 level), `pivot`
## the outermost planted foot on that side measured from the plumb line, `spill`
## how far the weight now hangs past it — positive is a body on its way over,
## and the px a rescue step has to find — and `strained` whether the legs asked
## for more righting than they had, which is the moment they have to step
## instead of press.
var side: float = 0.0
var pivot: float = 0.0
var spill: float = 0.0
var righting: float = 0.0
## ...and the most the girdles could have pressed if they had asked for
## everything. `strained` is only the sign of `righting` having hit it; the
## number itself is what says by how much the legs are outmatched, and it moves
## on its own as feet leave the ground.
var ceiling: float = 0.0
var strained: bool = false

var _derived_rev: int = -1
## Which flank the body committed to as it went down, latched once. Zero is a
## body that dropped level and stays belly-down.
var _down_side: float = 0.0
var _was_down: bool = false


## Re-reads the body off the census. Revision-keyed: an ordinary tick reads two
## cached numbers and leaves.
func derive(corpus: Corpus) -> void:
	if corpus == null or corpus.revision == _derived_rev:
		return
	_derived_rev = corpus.revision
	mass = maxf(corpus.mass(), Corpus.MIN_MASS)
	inertia = maxf(corpus.roll_inertia(), Corpus.MIN_MASS)


## What the body is turning about. `high` is how far the weight hangs above that
## axis — the ground it is standing on, so `M·H²` of the body's whole weight is
## in the swing — and zero for a body in the air, which turns about itself.
func swing(high: float) -> float:
	return inertia + mass * high * high


## An impulse that landed somewhere — the angular half of `Impetus.shove`.
##
## `lateral` is the component of the velocity change across the body, `lever` how
## far above the axis it landed, and `high` where the weight hangs above that
## same axis. A press high on the flank rolls the animal away from the hand; the
## same press at the knees takes its feet out from under it and rolls it *toward*
## the hand, and neither is a rule — it is one sign in one multiplication, which
## is exactly what the flattened seam could not say.
func strike(lateral: float, lever: float, high: float) -> void:
	if absf(lateral) < 0.0001:
		return
	rate = clampf(rate + mass * lever * lateral / swing(high), -RATE_MAX, RATE_MAX)


## One tick of the attitude.
##
## `support` is the outermost planted foot on each side of the plumb line, right
## in x and left in y (`Poise.flanks`) — the pivot the tip turns about. `high` is
## how far the weight hangs above the ground it is standing on, and 0 for a body
## in the air. `hold` is the share of its feet the animal actually has down and
## `base` its girdle half-base: together with `power` off the census they are
## what the legs have to fight with.
##
## Collapsed there is nothing left to balance: the roll runs out to the flank it
## went over on and stays there. A creature that died standing — a stopped heart,
## the lab's K key — has no roll to run out and flops belly-down, which is the
## honest difference between being killed and being knocked over.
func tick(delta: float, support: Vector2, high: float, hold: float, base: float,
		power: float, collapsed: bool) -> void:
	righting = 0.0
	ceiling = 0.0
	strained = false
	if collapsed:
		if not _was_down:
			_was_down = true
			_down_side = signf(roll) if absf(roll) > TIPPED else 0.0
		roll = lerpf(roll, FLANK * _down_side, 1.0 - exp(-LIE * delta))
		rate = 0.0
		side = _down_side
		pivot = 0.0
		spill = 0.0
		return
	_was_down = false

	# Which way the body has to go, if it has a way to go at all. Heeled, it is
	# already committed to a side. Level, it only has one if its weight is
	# already outside its own feet — which is exactly what being shoved off them
	# is, and it is how a plan-only push becomes a roll with no roll in it.
	side = signf(roll) if absf(roll) > LEVEL else 0.0
	if side == 0.0:
		if support.x < 0.0 and support.x <= support.y:
			side = 1.0
		elif support.y < 0.0:
			side = -1.0

	var about: float = swing(maxf(high, 0.0))
	pivot = 0.0
	spill = 0.0
	if side != 0.0:
		pivot = support.x if side > 0.0 else support.y
		# One line of statics: the weight rides up over the pivot as the body
		# heels and hangs further past it the further it has gone. Inside the
		# foot this is restoring and the body rocks back; past `tan θ = e/H`
		# it changes sign and nothing but a step will do.
		spill = maxf(high, 0.0) * sin(absf(roll)) - pivot * cos(roll)
		rate += side * mass * Gravity.PULL * spill / about * delta

	# The legs. Demand off the error, delivery clamped by what the girdles can
	# press — and the clamp is the whole mechanism: under it the animal holds
	# itself level through a two-footed beat without noticing, over it the muscle
	# is simply outmatched and the weight has its way.
	ceiling = RIGHTING * mass * Gravity.PULL * maxf(base, 0.0) \
		* maxf(power, 0.0) * clampf(hold, 0.0, 1.0) / about
	var demand: float = -(STIFF * roll + BRACE * rate)
	righting = clampf(demand, -ceiling, ceiling)
	# Strained means *outmatched*, which is a statement about muscle that was
	# there — a body with nothing on the ground is not losing a fight, it is not
	# in one, and calling that strain would have the legs churning through every
	# suspension phase of a gallop.
	strained = ceiling > 0.0 and absf(demand) > ceiling
	rate += righting * delta

	rate *= exp(-SLACK * delta)
	rate = clampf(rate, -RATE_MAX, RATE_MAX)
	roll = clampf(roll + rate * delta, -FLANK, FLANK)
	if absf(roll) < LEVEL and absf(rate) < LEVEL:
		roll = 0.0
		rate = 0.0


## Whether the body is past what its feet can pivot it back through.
func going_over() -> bool:
	return absf(roll) >= DOWN


func reset() -> void:
	roll = 0.0
	rate = 0.0
	side = 0.0
	pivot = 0.0
	spill = 0.0
	righting = 0.0
	ceiling = 0.0
	strained = false
	_down_side = 0.0
	_was_down = false
