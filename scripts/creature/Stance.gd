## Which of its own stances this body is actually in.
##
## A stance is two facts, and the game already had both — it had simply never
## been made to say them together. How the limbs are carried out of the ground
## plane is the *posture*, an anatomical category with a table of its own (see
## Posture: sprawled, semi-upright, erect, columnar). How many of them the body
## is walking on is the *locomotor mode*, and it was a measurement scattered
## through Locomotion as `forelimbs_bear`: an arm too short to reach the floor is
## an arm that is carried, and a body with two of those is bipedal. This file is
## where the two axes meet, and it exists because their combination is not
## constant per animal:
##
##   * a crocodile travels in a **high walk** — the same four legs rotated in
##     under the body, a sprawled build spending a while in the next stance up
##     the table — and drops back to its sprawl to rest;
##   * a basilisk at a flat sprint lifts a working pair of forelimbs off the
##     ground and runs on its hinds — the same sprawled posture in the other
##     locomotor mode;
##   * a kangaroo hops on two legs and crawls on two legs, a tail and its
##     forepaws — which the footfall already delivers (see Footfall.crawl)
##     and this file only has to be honest about.
##
## So a creature carries a *set* of supported stances and is *in* exactly one of
## them, and the two are different kinds of fact. What is supported is a
## property of the build, derived at rebuild from the same measurements
## everything else is — the arms against the legs, the weight against the hips,
## the girdles' own range — and never from a species name. Which is active is a
## property of the gait, re-asked every tick off how fast the body is going and
## what is being asked of it, with hysteresis so a body near a threshold does
## not flicker between two ways of standing.
##
## Two Posture objects come out, and the split is the one rule everything here
## is built around:
##
##   * `rest` is the stance the animal is *built* in. The flesh census, the
##     lattice carve and the physique read this one and only this one, because
##     an animal re-carrying its limbs does not re-grow its tissue — and because
##     anything pose-derived in the carve's signature re-carves the whole
##     lattice mid-gait, which is exactly the failure ScenarioProbe watches for.
##   * `active` is the stance it is currently in, blended continuously through
##     transitions. It is the creature's own `posture` object, mutated in place,
##     so the articulation, the locomotion, the gait, the stature and the drawn
##     body all follow a stance change without one of them being told — they
##     were already reading this object every tick.
##
## The supported set is grown by RULES, a table rather than code paths, so a new
## facultative stance is a new row: what it shifts (posture up the table, or the
## locomotor mode), what the build must measure to have it, and what the gait
## must be doing to be in it. Nothing in the table names a species, and the two
## rows it ships with are the two the reference animals demonstrate.
class_name Stance
extends RefCounted

## The locomotor mode axis: how many limbs are carrying the animal. A separate
## axis from the posture on purpose — an erect quadruped is a cat and an erect
## biped is a tyrannosaur, and the posture row is the same for both. Ordered by
## the count it takes away, so extending the axis (a brachiator, a serpentine
## build with no bearing limbs at all) is appending, not renumbering.
const QUADRUPEDAL: int = 0
const BIPEDAL: int = 1
const MODE_COUNT: int = 2

const MODE_NAMES: Array[String] = ["quadrupedal", "bipedal"]

## Least the hind pair must out-measure the fore for a quadruped to have a
## bipedal sprint in it at all. The same kind of line BEARING_RATIO is, drawn
## from the same beasts: a monitor lizard's hind limb is about 1.3 of its fore
## and it trots flat out on all four; a basilisk's is over 1.6 and it rears.
## Comfortably above the first and below the second, so the default Lizard keeps
## the gait it was calibrated with and a build has to be genuinely hind-driven
## before the offer appears.
const SPRINT_DOMINANCE: float = 1.35

## Steepest a facultative biped will rear its trunk to get its weight over its
## hips, in degrees. A kangaroo *carries* 55 as a trait; a quadruped rearing
## past somewhere near that on the run is not sprinting, it is standing up —
## and a build whose balance demands more than this has a centre of gravity so
## far ahead of its hips that two legs were never going to hold it.
const SPRINT_CARRIAGE_MAX: float = 60.0

## How long a body stays in a stance before it may be talked out of it, in
## seconds. Hysteresis in time beside the hysteresis in pace: the enter and
## exit thresholds keep a body cruising near a boundary honest, and this keeps
## one *accelerating through* it from changing its mind twice in a stride.
const HOLD_TIME: float = 0.5

## The facultative stances, and everything about them is a row here rather than
## a branch anywhere. Each is an offer the build may or may not measure up to:
##
##   * `modes` — which locomotor modes the offer is made from.
##   * `posture_shift` / `mode` — what it changes: postures up the table, and/or
##     the mode arrived in (-1 keeps the current one). Both axes in one row is
##     legal; nothing ships needing it.
##   * `range_cost` — how much of the build's `stance_range` the posture shift
##     spends. A girdle that can re-carry its limbs a stance away from rest is
##     an anatomical fact about the socket (a crocodile's can, a true sprawler's
##     cannot), which is why it is a parameter and not free.
##   * `dominance` — hind pair against fore, for an offer that takes the
##     forelimbs off the ground. Zero asks nothing.
##   * `carriage_max_deg` — most the trunk may need to rear in the offered
##     stance, measured off the build's own centre of gravity (see
##     Plumb.carriage_deg). The balance gate: an offer the weight cannot be
##     stood up under is not supported, however the proportions measure.
##   * `enter` / `exit` — the pace band, as the same 0..1 the whole gait is
##     quoted in, with the gap between them the hysteresis. `sprint` asks that
##     the animal genuinely be asked for everything, not merely travelling fast.
##   * `blend` — how long the movement between the stances takes, in seconds.
const RULES: Array[Dictionary] = [
	{
		# The crocodilian high walk: the same quadruped, limbs rotated in under
		# the body for travel. Enters at a travelling walk and stays through any
		# speed above it — the real animal's gallop is run from the high
		# carriage, not the sprawl — and settles back down when the body does.
		"name": "high walk",
		"modes": [QUADRUPEDAL],
		"posture_shift": 1,
		"mode": -1,
		"range_cost": 1,
		"dominance": 0.0,
		"carriage_max_deg": 0.0,
		"enter": 0.30,
		"exit": 0.15,
		"sprint": false,
		"blend": 0.55,
	},
	{
		# The basilisk sprint: a hind-driven quadruped at everything it has
		# lifts its forelimbs and runs on the pair that was doing the driving
		# anyway. Same posture, other mode — and it is only ever a sprint,
		# which is why the balance it runs on is allowed to be dynamic: the
		# trunk rears to what the hips demand (see Locomotion.carried_deg) and
		# the pace keeps the fall ahead of the feet.
		"name": "bipedal sprint",
		"modes": [QUADRUPEDAL],
		"posture_shift": 0,
		"mode": BIPEDAL,
		"range_cost": 0,
		"dominance": SPRINT_DOMINANCE,
		"carriage_max_deg": SPRINT_CARRIAGE_MAX,
		"enter": 0.85,
		"exit": 0.55,
		"sprint": true,
		"blend": 0.35,
	},
]


## The stance the animal is built in. What the census, the carve and the
## physique read — see the header for why they may read nothing else.
var rest: Posture = Posture.new()
## The stance it is currently in, blended through transitions. This is the
## object the creature hands to everything live, mutated in place.
var active: Posture = Posture.new()
## The build's own combination: (posture, mode). Where every transition starts
## and ends, and the whole answer on the great majority of bodies.
var base: Vector2i = Vector2i.ZERO
## Every combination this build can use, base first. Grown at `derive`, read by
## the creation menu and the tests; the tick below never leaves it.
var supported: Array[Vector2i] = []
## The combination the body is currently in or moving into...
var current: Vector2i = Vector2i.ZERO
## ...and how far through the movement it is: where it started, how much of the
## way it has gone, and how long the whole movement takes.
var _from: Vector2i = Vector2i.ZERO
var _blend: float = 1.0
var _blend_time: float = 0.4
## Which rule owns `current`, -1 for the base stance.
var _rule: int = -1
## The offers `derive` found: {"combo": Vector2i, "rule": int}, in table order.
var _offers: Array[Dictionary] = []
## How long the body has been in (or moving into) `current`.
var _held: float = 0.0
## Whether the active posture's numbers moved this tick. The creature re-reads
## the articulation off it when they did and skips the work when they did not.
var changed: bool = false


## Puts the classification back to the build's own stance. The cheap half of
## derivation, run first thing in a rebuild — before the plumb has been counted
## — so the posture object every other structure is configured from exists from
## the first line. See `derive` for the other half.
func rebuild(p: CreatureParams) -> void:
	rest = Posture.new(p.posture)
	active = Posture.new(p.posture)
	base = Vector2i(p.posture,
		QUADRUPEDAL if Locomotion.bears_on_forelimbs(p) else BIPEDAL)
	current = base
	_from = base
	_blend = 1.0
	_rule = -1
	_held = 0.0
	changed = false
	supported = [base]
	_offers = []


## Grows the supported set from the build's measurements. After the census —
## the balance gate reads the build's own centre of gravity, and a constraint
## on what an animal can stand up in has to be a statement about the intact
## build rather than about whatever has been bitten off it since (see
## Plumb.built_along, which is kept for exactly this).
func derive(p: CreatureParams, plumb: Plumb, articulation: Articulation,
		scale: float) -> void:
	supported = [base]
	_offers = []
	if p == null:
		return
	for index in RULES.size():
		var rule: Dictionary = RULES[index]
		if not (base.y in (rule["modes"] as Array)):
			continue
		var offered := Vector2i(base.x + int(rule["posture_shift"]),
			base.y if int(rule["mode"]) < 0 else int(rule["mode"]))
		if offered.x < 0 or offered.x >= Posture.COUNT or offered == base:
			continue
		# The girdle has to be able to carry its limbs there. A posture shift is
		# a rotation at the socket, and how far a socket can re-carry its limb
		# out of the stance it is built at is an anatomical trait — see
		# CreatureParams.stance_range. Free when the offer shifts nothing.
		if int(rule["range_cost"]) > p.stance_range:
			continue
		# An offer that takes the forelimbs off the ground needs the hind pair
		# to have been doing the work already...
		if float(rule["dominance"]) > 0.0 \
				and p.leg_length < p.arm_length * float(rule["dominance"]):
			continue
		# ...and needs the weight to be somewhere two legs can be got under. The
		# same beam-over-a-fulcrum the obligate biped stands by, asked of the
		# offered stance before anything is allowed to enter it: how steeply
		# would this trunk have to rear, given where the build's weight actually
		# is and how far its hind feet reach. See Plumb.carriage_deg.
		if float(rule["carriage_max_deg"]) > 0.0 and plumb != null:
			var offer := Posture.new(offered.x)
			var stand: float = articulation.hind.stand if articulation != null else 0.78
			var length: float = p.segment_length * float(maxi(p.segment_count, 2) - 1) \
				* scale * BodyPlan.clip_t(p)
			var reach: float = Locomotion.fore_aft_reach(offer, p, scale,
				Limb.REAR, stand)
			if plumb.carriage_deg(p.rear_limb_t, length, reach) \
					> float(rule["carriage_max_deg"]):
				continue
		supported.append(offered)
		_offers.append({"combo": offered, "rule": index})


## Re-asks which supported stance the gait puts the body in, and carries the
## active posture toward it. Once per tick, before the locomotion that reads
## it; `pace` is the same 0..1 of the body's own cruise everything else in the
## gait is quoted against, and `sprinting` is whether everything is being asked.
##
## A body in the air changes nothing: a stance is a way of standing on the
## ground, and a leap resumes whatever it left.
func tick(delta: float, pace: float, sprinting: bool, airborne: bool) -> void:
	changed = false
	if airborne:
		return

	# Which stance the gait is asking for. The current facultative stance keeps
	# the body until its exit is crossed — that gap is the hysteresis — and the
	# base stance offers whichever qualifying rule asks for the most, so a body
	# that qualifies for two offers commits to the one its speed has earned.
	var target: Vector2i = base
	var rule_of: int = -1
	if _rule >= 0 and _keeps(RULES[_rule], pace, sprinting):
		target = current
		rule_of = _rule
	else:
		var best: float = -1.0
		for offer in _offers:
			var rule: Dictionary = RULES[int(offer["rule"])]
			if _enters(rule, pace, sprinting) and float(rule["enter"]) > best:
				best = float(rule["enter"])
				target = offer["combo"]
				rule_of = int(offer["rule"])

	_held += delta
	if target != current and _held >= HOLD_TIME:
		# The pace of the movement belongs to whichever facultative stance is
		# being entered or, on the way back down, left — settled before `_rule`
		# is overwritten, because the way back down is the one case where the
		# stance that knows the tempo is the one being abandoned.
		var tempo: int = rule_of if rule_of >= 0 else _rule
		if target == _from and _blend < 1.0:
			# The movement reversing is the same movement run backward — a body
			# halfway up settles from halfway up, it does not snap to the top
			# to come down.
			_from = current
			_blend = 1.0 - _blend
		elif _blend < 1.0:
			# A third stance interrupting a movement starts from whichever end
			# the body is nearer. The one discontinuity in the file, at most
			# half a row wide, and unreachable from the rules that ship — it
			# would take two facultative stances contested mid-blend.
			_from = Vector2i(posture_kind(), mode())
			_blend = 0.0
		else:
			_from = current
			_blend = 0.0
		current = target
		_rule = rule_of
		_blend_time = maxf(float(RULES[tempo]["blend"]) if tempo >= 0 else 0.4, 0.05)
		_held = 0.0

	if _blend >= 1.0:
		return
	_blend = minf(_blend + delta / _blend_time, 1.0)
	# Eased, so the body leaves one stance and arrives in the other gently —
	# the middle of the movement is where the limbs are genuinely swinging
	# through, and a linear ramp starts and stops like a mechanism.
	active.mix(_from.x, current.x, smoothstep(0.0, 1.0, _blend))
	# The one number that is flesh rather than carriage. See Posture.mix.
	active.depth_ratio = rest.depth_ratio
	changed = true


## Whether the gait is asking hard enough to enter this stance...
func _enters(rule: Dictionary, pace: float, sprinting: bool) -> bool:
	return (not bool(rule["sprint"]) or sprinting) and pace >= float(rule["enter"])


## ...and whether a body already in it has slowed out of it. The gap between
## the two thresholds is the hysteresis, so a body cruising at the boundary
## stays in whichever stance it arrived in.
func _keeps(rule: Dictionary, pace: float, sprinting: bool) -> bool:
	return (not bool(rule["sprint"]) or sprinting) and pace >= float(rule["exit"])


## Whether the forelimbs are on the ground: the measurement, and then the mode.
## An arm that cannot reach the floor is carried whatever the stance says, and
## an arm the stance has lifted is carried however well it could reach — the
## first is Locomotion's old answer and the second is the axis this file added.
func forelimbs_bear(p: CreatureParams) -> bool:
	return Locomotion.bears_on_forelimbs(p) and mode() == QUADRUPEDAL


## The locomotor mode the body is in. Discrete — feet are on the ground or off
## it — so a transition changes mode at its midpoint, where the posture blend
## is already carrying everything continuous.
func mode() -> int:
	return current.y if _blend >= 0.5 else _from.y


## The posture the body is in, by the same rule. The blended angles live on
## `active`; this is only which row they are nearer.
func posture_kind() -> int:
	return current.x if _blend >= 0.5 else _from.x


## Whether this build can use the combination at all.
func supports(p_posture: int, p_mode: int) -> bool:
	return Vector2i(p_posture, p_mode) in supported


## Whether the body is mid-movement between two stances.
func transitioning() -> bool:
	return _blend < 1.0


## What a person would call the stance. Never read by the simulation.
func describe() -> String:
	var name: String = "%s %s" % [Posture.NAMES[posture_kind()],
		MODE_NAMES[mode()]]
	if transitioning():
		name += " (shifting)"
	return name
