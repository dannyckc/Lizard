## What this body can keep doing, as opposed to what it can do once.
##
## The sixth derived descriptor, and it is read off the same body every other one
## is. `Physique` counts how much animal there is and how much of it is the
## engine; `BodyState` says what the heart is putting out and how much of that is
## arriving where the work is being done. This is those two divided into each
## other, and there is no stamina stat anywhere for a preset to disagree with.
##
## Two quantities, and keeping them apart is the whole model:
##
##   * **`capacity`** is the share of its own top speed this animal can hold *for
##     ever* — its aerobic ceiling. It is oxygen arriving at muscle, so it is the
##     heart, the blood and the vessels that carry it, against the muscle asking
##     for it and the weight that muscle has to move.
##   * **`reserve`** is what is left of the store that pays for anything above
##     that ceiling — the anaerobic half, 0..1, and the only thing on the HUD.
##     Sprinting is borrowing from it; walking pays it back.
##
## Effort is what the animal is travelling at over what it can travel at flat out,
## so it runs from its own walking share — a little under a half on a build with a
## long sprint in it, three quarters on one with barely any — up to exactly one at
## full pelt, on every creature in the file. That uniformity is the point: a body
## going flat out is trying as hard as it can whatever species it is, so what
## separates two animals is not how hard they are trying but how much of it their
## blood covers, which is the whole reading this file exists to produce.
##
## Nothing tires inside its own ceiling and everything tires above it, so a walk is
## free and a sprint is timed. Free by construction rather than by luck: the
## ceiling is floored at the animal's own walking share, because a species'
## travelling speed is a speed it travels at, and a creature that tired while
## walking would be one that could not get anywhere. How long the sprint lasts is
## not written down anywhere either — it is the depth of the store over how far
## past the ceiling the animal is going, and the builds that can hold a chase are
## the ones with the muscle and the heart to do it.
##
## What is deliberately absent is a size term. Mass-specific aerobic supply falls
## as an animal gets larger — the reason an elephant is not a mile runner — but so
## does the mass-specific cost of carrying it along, and quoting effort as a share
## of what *this animal's own* legs deliver already carries the second. A size
## exponent here would be pricing one law at both ends of the same creature.
##
## Refreshed once per tick from the physique and the functional state solved
## beside it, with the same deliberate one-tick lag those are read with.
class_name Stamina
extends RefCounted

## Locomotor muscle cells per unit of body weight on the default build, so
## `engine` reads exactly 1.0 there and every other creature is a ratio against
## it. A constant rather than a measured baseline for the same reason Physique's
## census rulers are: it has to mean the same thing after the creation menu has
## rebuilt the body underneath it. Re-measure with tests/StaminaProbe.gd if the
## default build or the carve rules change — its first row is the default build
## and must read engine 1.000 exactly. Last moved with the cord claim floor
## (AnatomyLattice, `cord_reach`) and the census re-pin that followed it.
const REFERENCE_ENGINE: float = 863.0

## The share of flat out the reference build holds indefinitely, with a sound heart
## and ordinary fibre. Comfortably over the two thirds a Lizard walks at and well
## under the whole of what it sprints at, which is the calibration: an animal that
## could not sustain its own walk would tire standing up, and one that could
## sustain its own sprint would never have a bar worth drawing.
const AEROBIC_EFFORT: float = 0.72

## How strongly the engine ratio moves that ceiling — a fourth root, and the
## exponent is an argument rather than a taste. Sustained power is limited by the
## oxygen arriving at the muscle and not by how much muscle is there to burn it:
## twice the leg on the same heart is nothing like twice the endurance, and the
## three-fold spread of `engine` across the file would otherwise decide the whole
## reading on its own. So the muscle share enters under a root while the heart
## enters whole, which is what "primarily cardiovascular" means here.
const ENGINE_ROOT: float = 0.25

## What composition is worth at the two ends of the fibre axis. Slow fibre is
## built to keep going and fast fibre is built to spend, so the same muscle tilts
## the aerobic ceiling one way and the anaerobic store the other. Both are exactly
## no-ops at `fast_twitch` 0.5, which is where every preset stands — see
## CreatureParams.fast_twitch, and Locomotion.swing_time for the other half of
## what that parameter buys.
const FIBRE_TILT: float = 0.35
const STORE_TILT: float = 0.30

## How much dearer travel gets as the effort rises. Over one, because the cost of
## going faster is not linear in the speed: a body near its limit is paying for
## the legs it is throwing as well as for the ground it is covering. It is applied
## to the ceiling and to the demand alike — they are the same currency measured at
## two speeds — so what it changes is the *gap* between them, which is the only
## thing the store ever sees.
const EXERTION_EXPONENT: float = 2.0

## What hauling something costs, as exertion on top of travel. `Creature`'s haul
## factor is what survives the load, so its shortfall is the load — an animal
## dragging a carcass is working, and working is the one thing this file prices.
const HAUL_EXERTION: float = 0.6

## Seconds of unit overdraft the reference build's store covers. A unit overdraft
## is the whole cost of going flat out with nothing covered, which no sound animal
## is ever at — what the number comes to in practice is a Lizard holding a sprint
## for about a quarter of a minute. Deeper stores are deeper because there is more
## muscle per unit of weight to hold them, not because a number says so.
const STORE_SECONDS: float = 10.0

## Seconds a resting reference animal takes to fill an empty store, with a sound
## heart. Recovery is cardiovascular and nothing else: a good heart pays the debt
## back sooner, a failing one never quite does.
const RECOVER_SECONDS: float = 24.0

## How fast the store sags to what the circulation can actually hold. Slow — this
## is tissue giving up a reserve it can no longer supply, not a tap being turned
## off — and it is the whole of why a bleeding animal's stamina falls without
## anything having been spent.
const SUPPLY_FADE: float = 0.35

## Share of the store below which being out of breath starts to tell. Above it an
## animal is spending and shows nothing for it, which is right: what a reserve is
## for is being spent.
const WINDED: float = 0.35

## What a completely blown animal can still throw into one maximal effort. Not
## zero — a spent creature can still jump, it simply cannot jump like a fresh one.
const SPENT_PUSH: float = 0.55

## What one maximal push takes out of the store. A leap is the most anaerobic
## thing a body does and the only one that happens in an instant, so it is charged
## as an instant rather than accumulated as a rate.
const LEAP_COST: float = 0.06


## Locomotor muscle per unit of body weight, against the reference build. The
## ratio the whole model turns on, and the one the creation menu can move in both
## directions: laying muscle on the girdles raises it, and laying anything else on
## the animal — fat, a longer tail, a heavier skull — lowers it, because it is all
## weight the same legs have to carry.
var engine: float = 1.0
## What the cardiovascular system is delivering to that muscle: the species' own
## heart, times what the organ is actually putting out through the blood it has
## left, times how much of it is arriving where the work is done.
var cardio: float = 1.0
## The share of flat out this body holds indefinitely. 1.0 would be an animal that
## can sprint for ever; a bit under three quarters is an ordinary one.
var capacity: float = AEROBIC_EFFORT
## How hard it is working right now, as the same share.
var effort: float = 0.0
## What that costs per second, and what the blood is covering of it. The gap
## between the two is the whole of what empties the store.
var demand: float = 0.0
var sustained: float = 0.0
## Seconds of unit overdraft this animal's store covers.
var depth: float = STORE_SECONDS
## What is left of that store, 0..1. The number on the HUD.
var reserve: float = 1.0
## What the circulation can hold the store up to. An animal that has bled cannot
## keep a full one however long it stands still.
var ceiling: float = 1.0
## How much of that store is left against the share of it being out of breath
## begins at — 1.0 with anything in hand, 0.0 blown. What both consequences below
## are drawn off.
var breath: float = 1.0
## What one maximal effort is worth now, 0..1. The jump reads this.
var push: float = 1.0
## Out of breath: the reserve is low enough that the two readings above have
## started to bite. False on any animal that has not spent one, which is what
## keeps a body nobody has run behaving exactly as it did before this existed.
var winded: bool = false


## Puts the store back to full, with the rest of the body's reset.
func reset() -> void:
	engine = 1.0
	cardio = 1.0
	capacity = AEROBIC_EFFORT
	effort = 0.0
	demand = 0.0
	sustained = 0.0
	depth = STORE_SECONDS
	reserve = 1.0
	ceiling = 1.0
	breath = 1.0
	push = 1.0
	winded = false


## Re-derives the ceiling and moves the store one tick.
##
## `working` is how hard the body is being worked: what it is actually travelling
## at over what it could travel at flat out — see Creature.flat_out. Measured
## rather than commanded, so a creature holding sprint against a rock is not
## tiring itself out. `haul` is what survives whatever it is dragging; see
## Creature._haul_factor.
func update(physique: Physique, state: BodyState, p: CreatureParams,
		working: float, haul: float, delta: float) -> void:
	if physique == null or p == null:
		return
	_read_capacity(physique, state, p)
	_advance(working, haul, delta)
	_derive_output()


## Charges one instant of maximal effort against the store — a push-off, spent in
## a tenth of a second and paid for out of the same reserve a chase is.
func spend(share: float) -> void:
	reserve = clampf(reserve - maxf(share, 0.0), 0.0, 1.0)


## What of a speed request this animal still has the breath for, in the px/s the
## request is made in. `top` is what it travels at flat out, because the ceiling
## is a share of exactly that.
##
## A fresh body asks for whatever its species asks for. A blown one is held to the
## speed its own blood can supply — which is above its walk on every sound build,
## so what running out of breath takes away is the sprint and never the legs.
func hold(asked: float, top: float) -> float:
	if not winded or top <= 0.0:
		return asked
	return minf(asked, lerpf(capacity * top, asked, breath))


## How long this animal could keep up what it is doing, in seconds. Nothing in the
## simulation reads it; it is what the probe prints and what a readout would say
## if it said anything more than a length.
func window() -> float:
	if demand <= sustained:
		return INF
	return reserve * depth / (demand - sustained)


# --------------------------------------------------------------- the ceiling ----

## The two halves of what can be sustained, and the store that pays for the rest.
##
## Both are read off tissue that has already been counted this tick: the engine is
## the muscle standing behind the two girdles against what the animal weighs, and
## the cardio term is the heart's output and the vessels' delivery. So a bitten
## hip, a torn heart, a cut artery and a body that has simply been fattened all
## arrive here as the same kind of number, and none of them is a stamina penalty
## anybody wrote.
func _read_capacity(physique: Physique, state: BodyState, p: CreatureParams) -> void:
	var locomotor: float = physique.girdle_muscle.x + physique.girdle_muscle.y
	engine = locomotor / maxf(physique.mass, 0.0001) / REFERENCE_ENGINE
	var fibre: float = lerpf(1.0 + FIBRE_TILT, 1.0 - FIBRE_TILT, p.fast_twitch)
	var store: float = lerpf(1.0 - STORE_TILT, 1.0 + STORE_TILT, p.fast_twitch)

	# What the heart is putting out, and how much of it is arriving at the legs.
	# `circulation` already carries the organ and the blood left to move; the
	# delivery term is the vessel tree, so a limb whose artery is cut stops
	# counting toward what the animal can sustain long before it stops working.
	var delivered: float = _delivered(state) if state != null else 1.0
	cardio = p.heart_power * delivered
	# ...and never under this animal's own walk, which is what `sprint_multiplier`
	# is the reciprocal of. A species' travelling speed is a speed it travels at:
	# the floor is what makes "a walk is free" a property of the model rather than
	# something the tuning has to keep being careful about, and it is the same line
	# that guarantees a blown creature is held to something above walking pace.
	capacity = clampf(
		AEROBIC_EFFORT * cardio * pow(maxf(engine * fibre, 0.0), ENGINE_ROOT),
		1.0 / maxf(p.sprint_multiplier, 1.0), 1.0)
	depth = STORE_SECONDS * store * pow(maxf(engine, 0.0), ENGINE_ROOT)
	# The store is held in the muscle, so what can be held is what is being
	# supplied — and pointedly not the species' own heart, which is why a strong
	# heart fills the store faster and a large one does not make it deeper. An
	# animal that has bled sits at a fraction of a reserve however long it rests,
	# and one whose heart has stopped holds nothing at all.
	ceiling = clampf(delivered, 0.0, 1.0)


## Blood arriving where the walking is done, times the heart driving it.
##
## The girdles and the limbs hanging off them, because that is where the engine
## is — an animal with a starved tail is not short of breath. Vitality rather than
## perfusion: what matters to sustained work is whether the tissue has kept up
## with its supply, not what arrived in the last half second.
static func _delivered(state: BodyState) -> float:
	var total: float = 0.0
	var counted: int = 0
	for index in [BodyPlan.THORAX, BodyPlan.PELVIS]:
		var region: BodyState.Region = state.region(index)
		if region != null:
			total += region.vitality
			counted += 1
	for index in BodyPlan.LIMB_REGIONS:
		var limb: BodyState.Region = state.region(index)
		if limb == null or limb.severed:
			continue
		total += limb.vitality
		counted += 1
	return state.circulation * (total / float(counted) if counted > 0 else 1.0)


# ----------------------------------------------------------------- the store ----

## One tick of the reserve: burnt above the ceiling, paid back below it, and
## never held above what the blood can supply.
##
## The three cases are one arithmetic and they are in that order because that is
## the order they happen in: an animal spends first, sags to its supply second,
## and only recovers with whatever is left over.
func _advance(working: float, haul: float, delta: float) -> void:
	effort = clampf(working, 0.0, 1.0)
	# What travel costs, plus what is being dragged. The haul factor is what
	# survives the load, so one minus it is the load — an animal towing something
	# its own size is working half again as hard as one walking.
	demand = pow(effort, EXERTION_EXPONENT) \
		+ HAUL_EXERTION * clampf(1.0 - haul, 0.0, 1.0)
	sustained = pow(capacity, EXERTION_EXPONENT)
	if delta <= 0.0:
		return
	if demand > sustained:
		reserve = maxf(reserve - (demand - sustained) * delta / maxf(depth, 0.001), 0.0)
	if reserve > ceiling:
		reserve = lerpf(reserve, ceiling, 1.0 - exp(-SUPPLY_FADE * delta))
	elif demand < sustained:
		# Recovery is cardiovascular, and it is what is left of the heart after the
		# work in hand has been paid for: an animal standing still pays the whole
		# debt back at its own rate, and one still trotting pays it back out of
		# whatever aerobic headroom the trot has left it.
		var headroom: float = clampf(
			(sustained - demand) / maxf(sustained, 0.0001), 0.0, 1.0)
		reserve = minf(
			reserve + cardio * headroom * delta / RECOVER_SECONDS, ceiling)


## What being out of breath costs, and the two things it costs it to.
##
## Both come off the same curve and both are exactly nothing above `WINDED`,
## which is the point: a reserve that made an animal slower the instant it was
## touched would not be a reserve, it would be a second speed limit.
func _derive_output() -> void:
	breath = clampf(reserve / WINDED, 0.0, 1.0)
	winded = breath < 1.0
	push = lerpf(SPENT_PUSH, 1.0, breath)
