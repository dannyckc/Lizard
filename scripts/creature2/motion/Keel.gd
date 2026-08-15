## How far over the body is held — the attitude state, and the one place it
## changes (docs/V2_DESIGN.md §4.1, the revisit clause).
##
## v2's body had three dynamic degrees of freedom and one assigned vertical: the
## plan velocity and the turn rate integrate (Impetus, Travel), and the height of
## the trunk was a *measurement* of the legs (`Armature.fore_carry`) with
## `Gravity.Fall` carrying the one scalar clearance under it. Nothing anywhere
## owned how far over the animal was leaning, so a body could not be pushed down,
## could not sink on one side, and could not fall onto its flank at all.
##
## This file is that missing state: **roll** — how far the body is heeled over
## about its own fore-and-aft axis — and **pitch** — the same idea about the
## lateral axis, nose-down positive — each with its rate and the torques that
## move it. Heave still belongs to the carries and `Gravity.Fall`.
##
## The bargain with the 2.5D decision is exact, and worth stating because it is
## what leaves the plan solver untouched: **the attitude's geometry lives here
## and nowhere else.** Poise goes on measuring an upright body's weight against
## its upright feet; the arc that weight swings through as the body goes over is
## one line of statics below, never a re-projection of the chain. What the rest
## of the body does with the answer is *express* it — the Z channel heels and
## tilts the trunk and the limb sockets, the skin rolls its ring frames — and
## those expressions feed back honestly, because a socket lifted out of reach
## really does take its foot out of the support hull Poise measures next tick.
##
## Three terms per axis, and every behaviour is one of them winning:
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
##     own base and the census's engine and scaled by how many feet are
##     actually down. Nothing authors a threshold — the threshold is where the
##     demand stops fitting under the ceiling, which is what `strained` says, and
##     it moves on its own when the animal is chewed, tired-footed or airborne.
##     The pitch axis is the same law with a much longer base — the whole
##     spacing of the girdles — which is why quadrupeds nod and rarely
##     somersault, and nobody authored that either.
##   * **An impulse is an impulse.** A push that lands somewhere lands at a
##     height, and the angular half of it is `M·h·Δv` — the same shove seam
##     Impetus already owns, carrying the component the flat one discarded.
##     Its lateral part rolls the body and its fore-aft part pitches it, out
##     of one decomposition.
##
## All divide by the same census inertias, about the axis the body actually
## turns about: the ground it stands on (parallel-axis `M·H²` added) or, in the
## air, its own centre.
##
## **A downed body is not a scripted body.** The old collapse lerped the heel to
## the flank at an authored rate; now the roll it arrives with keeps integrating
## — the momentum of the topple carries it the rest of the way round, damped by
## tissue, settled by its own cross-section (belly-stable below the ridge of its
## own roundness, flank-stable past it) — and a live downed animal can be handed
## `right`: the limbs pressing the ground, delivered as far as the same muscle
## law allows, which is how a knocked-down creature rolls sternal to stand and a
## half-destroyed one genuinely cannot.
class_name Keel
extends RefCounted

## Positive roll is the animal's own right side down — the same handedness the
## rest of v2 uses. Positive pitch is nose-down.
##
## Past this much heel a quadruped is not stumbling, it is going over. A
## *backstop* on the review's own derived commitment (the step that could reach
## past the pivot no longer exists — Travel measures that), never the decider.
const DOWN: float = 0.96
const PITCH_DOWN: float = 1.1

## Where a body that has gone over comes to rest: on its flank.
const FLANK: float = PI * 0.5

## The heel of a downed body's own cross-section past which it is
## flank-stable rather than belly-stable — the ridge of its own roundness.
## APPROX: a cat's chest is deeper than wide; ~32° is where the section
## balances. A body arriving under it settles onto its belly, one carried past
## it rolls on to its flank, and the same statement run backwards is what a
## get-up's righting has to push over.
const RIDGE: float = 0.55

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

## What damps the attitude with no muscle in it at all — tissue, not tone. The
## only term an airborne or dead body still has.
const SLACK: float = 0.6

## The most rate anything may hold, rad/s — a cap on the lever arithmetic
## (a contact point measured a hair off the surface must not be able to spin an
## animal), not a second physics. Well past a cat righting itself in mid-air.
const RATE_MAX: float = 8.0

## Below this the body is level and both sides are down; there is no side for a
## torque to act on and no heel for anything to express.
const LEVEL: float = 0.0005


## The heel, radians, right side down positive. The one owner.
var roll: float = 0.0
## ...and how fast it is changing, rad/s.
var rate: float = 0.0

## The tilt, radians, nose-down positive, and its rate. The other axis of the
## same ownership: everything said of `roll` above holds, with the girdle
## spacing for a base and the census's pitch inertia under it.
var pitch: float = 0.0
var pitch_rate: float = 0.0

## Baked off the census: what the body weighs and how hard it is to turn about
## each of its own axes. Re-read whenever the census moves, so a creature
## bitten hollow through one flank genuinely rolls easier.
var mass: float = 1.0
var inertia: float = 1.0
var tilt_inertia: float = 1.0

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

## The same readouts for the pitch axis: which end is going down (+1 the nose),
## the foot it would turn over, how far the weight hangs past it, and whether
## the girdles are outmatched fore-aft.
var tilt_side: float = 0.0
var tilt_pivot: float = 0.0
var tilt_spill: float = 0.0
var tilt_strained: bool = false

var _derived_rev: int = -1


## Re-reads the body off the census. Revision-keyed: an ordinary tick reads
## cached numbers and leaves.
func derive(corpus: Corpus) -> void:
	if corpus == null or corpus.revision == _derived_rev:
		return
	_derived_rev = corpus.revision
	mass = maxf(corpus.mass(), Corpus.MIN_MASS)
	inertia = maxf(corpus.roll_inertia(), Corpus.MIN_MASS)
	tilt_inertia = maxf(corpus.pitch_inertia(), Corpus.MIN_MASS)


## What the body is turning about. `high` is how far the weight hangs above that
## axis — the ground it is standing on, so `M·H²` of the body's whole weight is
## in the swing — and zero for a body in the air, which turns about itself.
func swing(high: float) -> float:
	return inertia + mass * high * high


func tilt_swing(high: float) -> float:
	return tilt_inertia + mass * high * high


## An impulse that landed somewhere — the angular half of `Impetus.shove`.
##
## `lateral` is the component of the velocity change across the body, `along`
## the component down its own length, `lever` how far above the axis it landed,
## and `high` where the weight hangs above that same axis. A press high on the
## flank rolls the animal away from the hand; the same press at the knees takes
## its feet out from under it and rolls it *toward* the hand; and the fore-aft
## half of the same push nods or rears it. None of it is a rule — each is one
## sign in one multiplication, which is exactly what the flattened seam could
## not say.
func strike(lateral: float, lever: float, high: float, along: float = 0.0) -> void:
	if absf(lateral) >= 0.0001:
		rate = clampf(rate + mass * lever * lateral / swing(high),
			-RATE_MAX, RATE_MAX)
	if absf(along) >= 0.0001:
		pitch_rate = clampf(pitch_rate + mass * lever * along / tilt_swing(high),
			-RATE_MAX, RATE_MAX)


## One tick of the attitude.
##
## `support` is the outermost planted foot on each side of the plumb line, right
## in x and left in y (`Poise.flanks`); `saddle` the same measurement fore-aft
## along the heading (`Poise.saddles`), ahead in x and behind in y — the pivots
## each tip turns about. `high` is how far the weight hangs above the ground it
## is standing on, and 0 for a body in the air. `hold` is the share of its feet
## the animal actually has down, `base` its girdle half-base, `stride_base` half
## the spacing of its girdles: with `power` off the census they are what the
## legs have to fight with, about each axis.
##
## Collapsed there is no stance left to balance: the attitude the body arrived
## with keeps integrating — the topple's own momentum, damped by tissue and
## settled by the body's cross-section — so a creature knocked over finishes
## rolling onto the flank it was going toward and one that died standing has no
## rate to spend and lies belly-down, and neither is a latch. `right` is the
## limbs of a live downed body pressing the ground to roll it sternal, 0..1 of
## their soundness, delivered under the same clamped-muscle law as everything
## else — a body without enough limb left genuinely cannot get up.
func tick(delta: float, support: Vector2, saddle: Vector2, high: float,
		hold: float, base: float, stride_base: float, power: float,
		collapsed: bool, right: float = 0.0) -> void:
	righting = 0.0
	ceiling = 0.0
	strained = false
	tilt_strained = false
	if collapsed:
		_downed(delta, base, power, right)
		return

	_roll_axis(delta, support, high, hold, base, power)
	_pitch_axis(delta, saddle, high, hold, stride_base, power)


func _roll_axis(delta: float, support: Vector2, high: float, hold: float,
		base: float, power: float) -> void:
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


## The same three terms about the lateral axis. The base is the girdle spacing
## rather than a stance width, so the same law that lets a shove heel a cat over
## sideways barely nods it fore-and-aft — a quadruped is long — and what tips it
## nose-first anyway (a brink, both forefeet gone) does so because the pivot
## went, not because a threshold said falls happen at brinks.
func _pitch_axis(delta: float, saddle: Vector2, high: float, hold: float,
		stride_base: float, power: float) -> void:
	tilt_side = signf(pitch) if absf(pitch) > LEVEL else 0.0
	if tilt_side == 0.0:
		if saddle.x < 0.0 and saddle.x <= saddle.y:
			tilt_side = 1.0
		elif saddle.y < 0.0:
			tilt_side = -1.0

	var about: float = tilt_swing(maxf(high, 0.0))
	tilt_pivot = 0.0
	tilt_spill = 0.0
	if tilt_side != 0.0:
		tilt_pivot = saddle.x if tilt_side > 0.0 else saddle.y
		tilt_spill = maxf(high, 0.0) * sin(absf(pitch)) - tilt_pivot * cos(pitch)
		pitch_rate += tilt_side * mass * Gravity.PULL * tilt_spill / about * delta

	var top: float = RIGHTING * mass * Gravity.PULL * maxf(stride_base, 0.0) \
		* maxf(power, 0.0) * clampf(hold, 0.0, 1.0) / about
	var demand: float = -(STIFF * pitch + BRACE * pitch_rate)
	var held: float = clampf(demand, -top, top)
	tilt_strained = top > 0.0 and absf(demand) > top
	pitch_rate += held * delta

	pitch_rate *= exp(-SLACK * delta)
	pitch_rate = clampf(pitch_rate, -RATE_MAX, RATE_MAX)
	pitch = clampf(pitch + pitch_rate * delta, -PITCH_DOWN, PITCH_DOWN)
	if absf(pitch) < LEVEL and absf(pitch_rate) < LEVEL:
		pitch = 0.0
		pitch_rate = 0.0


## A body on the ground. The roll it arrived with runs itself out — momentum,
## tissue damping, and the settle of its own cross-section: belly-stable below
## the ridge, flank-stable past it, so a corpse dropped level stays on its
## belly and one knocked over finishes on the flank it was going toward, and
## no flank was ever latched. `right` is a live body's limbs pressing it back
## toward sternal, clamped exactly as standing muscle is.
func _downed(delta: float, base: float, power: float, right: float) -> void:
	var about: float = inertia + mass * base * base
	side = signf(roll) if absf(roll) > LEVEL else 0.0
	pivot = 0.0
	spill = 0.0
	if side != 0.0:
		# The cross-section's own statics, reduced: how far the heel stands
		# from the ridge decides which stable pose is pulling, and how hard
		# goes with the sine of the way there.
		var toward: float = clampf((absf(roll) - RIDGE) / (FLANK - RIDGE), -1.0, 1.0)
		rate += side * mass * Gravity.PULL * base * sin(toward * PI * 0.5) \
			/ about * delta
	if right > 0.0 and absf(roll) > LEVEL:
		# The get-up's first half: limbs against the ground, as far as what is
		# left of them can press. The ceiling has to beat the flank's own
		# settle to bring the body over the ridge, which is what makes rising
		# a question about the body rather than a cutscene.
		ceiling = RIGHTING * mass * Gravity.PULL * maxf(base, 0.0) \
			* maxf(power, 0.0) * clampf(right, 0.0, 1.0) / about
		var demand: float = -(STIFF * roll + BRACE * rate)
		righting = clampf(demand, -ceiling, ceiling)
		strained = ceiling > 0.0 and absf(demand) > ceiling
		rate += righting * delta
	rate *= exp(-SLACK * delta)
	rate = clampf(rate, -RATE_MAX, RATE_MAX)
	roll = clampf(roll + rate * delta, -FLANK, FLANK)
	if absf(roll) >= FLANK - 0.0001 and rate * signf(roll) > 0.0:
		# Arrived: the flank is on the floor and the floor takes what is left
		# of the turn. Without this the settle term goes on pumping rate into
		# a body the clamp has already stopped, and a downed animal reads as
		# forever mid-tumble to anything waiting for it to be still.
		rate = 0.0
	if absf(roll) < LEVEL and absf(rate) < LEVEL:
		roll = 0.0
		rate = 0.0
	# The tilt has nothing to stand on and nothing to settle onto but the
	# ground it is already lying on: it runs out as tissue.
	pitch_rate = 0.0
	pitch *= exp(-SLACK * 4.0 * delta)
	if absf(pitch) < LEVEL:
		pitch = 0.0
	tilt_side = 0.0
	tilt_pivot = 0.0
	tilt_spill = 0.0


## Whether the body is past what its feet can pivot it back through — the
## backstops. The review's own commitment is derived (the step that could
## re-capture the weight no longer exists); these are where it stops waiting
## however the arithmetic came out.
func going_over() -> bool:
	return absf(roll) >= DOWN


func pitching_over() -> bool:
	return absf(pitch) >= PITCH_DOWN


func reset() -> void:
	roll = 0.0
	rate = 0.0
	pitch = 0.0
	pitch_rate = 0.0
	side = 0.0
	pivot = 0.0
	spill = 0.0
	righting = 0.0
	ceiling = 0.0
	strained = false
	tilt_side = 0.0
	tilt_pivot = 0.0
	tilt_spill = 0.0
	tilt_strained = false
