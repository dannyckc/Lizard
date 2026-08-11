## Which of its own stances this body is actually in — Stance's successor.
##
## A stance is two facts and the game already had both: how the limbs are carried
## out of the ground plane is the *carriage* (a table, see Carriage), and how many
## of them the body is walking on is the *locomotor mode* — an arm too short to
## reach the floor from a shoulder the hind legs are holding up is an arm that is
## carried, and a body with two of those is bipedal. This is where the two axes
## meet, and it exists because their combination is not constant per animal:
##
##   * a crocodile travels in a **high walk** — the same four legs rotated in
##     under the body — and drops back to its sprawl to rest;
##   * a basilisk at a flat sprint lifts a working pair of forelimbs and runs on
##     its hinds, the same sprawled carriage in the other locomotor mode.
##
## So a creature carries a *set* of supported stances and is in exactly one of
## them. What is supported is a property of the build, derived at rebuild from the
## same measurements everything else is — the limbs against each other, the weight
## against the hips, the girdles' own range — and never from a species name. Which
## is active is a property of the gait, re-asked every tick with hysteresis so a
## body near a threshold does not flicker between two ways of standing.
##
## Two Carriage objects come out, and the split is the one rule this file is built
## around (the v1 law, carried over exactly):
##
##   * `rest` is the stance the animal is *built* in. The census reads this one
##     and only this one, because an animal re-carrying its limbs does not re-grow
##     its tissue — and because anything pose-derived in the compile's inputs
##     re-compiles the body mid-gait.
##   * `active` is the stance it is currently in, blended continuously through
##     transitions and mutated in place, so the locomotion, the gait and the
##     drawn body follow a stance change without one of them being told.
class_name Attitude
extends RefCounted

## The locomotor mode axis: how many limbs are carrying the animal. Ordered by
## the count it takes away, so extending the axis is appending, not renumbering.
const QUADRUPEDAL: int = 0
const BIPEDAL: int = 1
const MODE_COUNT: int = 2

const MODE_NAMES: Array[String] = ["quadrupedal", "bipedal"]

## Least a forelimb may be, against the hind leg it stands beside, and still
## reach the ground the hips are holding the body over. This is the whole of what
## being two-legged is, and it is a measurement rather than a category.
const BEARING_RATIO: float = 0.46

## Least the hind pair must out-measure the fore for a quadruped to have a
## bipedal sprint in it at all — drawn from the beasts: a monitor's hind limb is
## about 1.3 of its fore and it trots flat out on all four; a basilisk's is over
## 1.6 and it rears.
const SPRINT_DOMINANCE: float = 1.35

## Steepest a facultative biped will rear its trunk to get its weight over its
## hips, degrees. A build whose balance demands more has a centre of gravity so
## far ahead of its hips that two legs were never going to hold it.
const SPRINT_CARRIAGE_MAX: float = 60.0

## How long a body stays in a stance before it may be talked out of it, seconds.
## Hysteresis in time beside the hysteresis in pace.
const HOLD_TIME: float = 0.5

## The facultative stances. Each is an offer the build may or may not measure up
## to: `posture_shift`/`mode` are what it changes, `range_cost` how much of the
## girdles' own re-carrying range it spends, `dominance` the hind-over-fore
## measurement an offer that lifts the forelimbs asks for, `carriage_max_deg` the
## balance gate (an offer the weight cannot be stood up under is not supported),
## `enter`/`exit` the pace band with the gap between them the hysteresis, and
## `blend` how long the movement between the two stances takes.
const RULES: Array[Dictionary] = [
	{
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


var spec: BodySpec
## The stance the animal is built in — what the census reads.
var rest: Carriage
## The stance it is currently in, blended through transitions.
var active: Carriage
## The build's own combination, where every transition starts and ends.
var base: Vector2i = Vector2i.ZERO
var supported: Array[Vector2i] = []
var current: Vector2i = Vector2i.ZERO

var _from: Vector2i = Vector2i.ZERO
var _blend: float = 1.0
var _blend_time: float = 0.4
var _rule: int = -1
var _offers: Array[Dictionary] = []
var _held: float = 0.0
## Whether the active carriage's numbers moved this tick.
var changed: bool = false


## Puts the classification back to the build's own stance. The cheap half of
## derivation, run first thing in a rebuild — before the census has been counted
## — so the carriage every other structure is configured from exists from the
## first line.
func rebuild(p_spec: BodySpec) -> void:
	spec = p_spec
	rest = Carriage.new(spec, spec.posture)
	active = Carriage.new(spec, spec.posture)
	base = Vector2i(spec.posture,
		QUADRUPEDAL if bears_on_forelimbs(spec) else BIPEDAL)
	current = base
	_from = base
	_blend = 1.0
	_rule = -1
	_held = 0.0
	changed = false
	supported = [base]
	_offers = []


## Grows the supported set from the build's measurements. After the census: the
## balance gate reads the build's own centre of gravity, and a constraint on what
## an animal can stand up in has to be a statement about the intact build rather
## than about whatever has been bitten off it since.
func derive(poise: Poise) -> void:
	supported = [base]
	_offers = []
	if spec == null:
		return
	for index in RULES.size():
		var rule: Dictionary = RULES[index]
		if not (base.y in (rule["modes"] as Array)):
			continue
		var offered := Vector2i(base.x + int(rule["posture_shift"]),
			base.y if int(rule["mode"]) < 0 else int(rule["mode"]))
		if offered.x < 0 or offered.x >= Carriage.COUNT or offered == base:
			continue
		# The girdle has to be able to carry its limbs there: a posture shift is a
		# rotation at the socket, and how far a socket can re-carry its limb out of
		# the stance it is built at is an anatomical trait.
		if int(rule["range_cost"]) > spec.stance_range:
			continue
		# An offer that takes the forelimbs off the ground needs the hind pair to
		# have been doing the work already...
		if float(rule["dominance"]) > 0.0 \
				and spec.hind_leg_length < spec.fore_leg_length * float(rule["dominance"]):
			continue
		# ...and needs the weight to be somewhere two legs can be got under. The
		# same beam over a fulcrum an obligate biped stands by, asked of the
		# offered stance before anything is allowed to enter it.
		if float(rule["carriage_max_deg"]) > 0.0 and poise != null:
			var offer := Carriage.new(spec, offered.x)
			var reach: float = offer.fore_aft_reach(spec.hind_leg_length,
				offer.hind.stand, spec.stance_width)
			if poise.carriage_deg(reach) > float(rule["carriage_max_deg"]):
				continue
		supported.append(offered)
		_offers.append({"combo": offered, "rule": index})


## Re-asks which supported stance the gait puts the body in, and carries the
## active carriage toward it. Once per tick, before the locomotion that reads it;
## `pace` is the same 0..1 of the body's own cruise everything else in the gait is
## quoted against. A body in the air changes nothing: a stance is a way of
## standing on the ground, and a leap resumes whatever it left.
func tick(delta: float, pace: float, sprinting: bool, airborne: bool) -> void:
	changed = false
	if airborne:
		return

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
		# being entered or, on the way back down, left — settled before `_rule` is
		# overwritten, because the way down is the one case where the stance that
		# knows the tempo is the one being abandoned.
		var tempo: int = rule_of if rule_of >= 0 else _rule
		if target == _from and _blend < 1.0:
			# A movement reversing is the same movement run backward: a body
			# halfway up settles from halfway up.
			_from = current
			_blend = 1.0 - _blend
		elif _blend < 1.0:
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
	# Eased, so the body leaves one stance and arrives in the other gently — the
	# middle of the movement is where the limbs are genuinely swinging through.
	active.mix(_from.x, current.x, smoothstep(0.0, 1.0, _blend))
	# The one number that is flesh rather than carriage.
	active.depth_ratio = rest.depth_ratio
	changed = true


func _enters(rule: Dictionary, pace: float, sprinting: bool) -> bool:
	return (not bool(rule["sprint"]) or sprinting) and pace >= float(rule["enter"])


func _keeps(rule: Dictionary, pace: float, sprinting: bool) -> bool:
	return (not bool(rule["sprint"]) or sprinting) and pace >= float(rule["exit"])


## Whether the forelimbs are on the ground: the measurement, and then the mode.
## An arm that cannot reach the floor is carried whatever the stance says, and an
## arm the stance has lifted is carried however well it could reach.
func forelimbs_bear() -> bool:
	return bears_on_forelimbs(spec) and mode() == QUADRUPEDAL


## Whether a body of these proportions walks on its forelimbs at all. Static
## because it is a question about a *build* — the creation menu can ask it of an
## animal nobody has grown yet and get the answer the simulation will.
static func bears_on_forelimbs(p_spec: BodySpec) -> bool:
	return p_spec != null \
		and p_spec.fore_leg_length >= p_spec.hind_leg_length * BEARING_RATIO


## The locomotor mode the body is in. Discrete — feet are on the ground or off it
## — so a transition changes mode at its midpoint, where the carriage blend is
## already carrying everything continuous.
func mode() -> int:
	return current.y if _blend >= 0.5 else _from.y


func posture_kind() -> int:
	return current.x if _blend >= 0.5 else _from.x


func supports(p_posture: int, p_mode: int) -> bool:
	return Vector2i(p_posture, p_mode) in supported


func transitioning() -> bool:
	return _blend < 1.0


## What a person would call the stance. Never read by the simulation.
func describe() -> String:
	var out: String = "%s %s" % [Carriage.NAMES[posture_kind()], MODE_NAMES[mode()]]
	if transitioning():
		out += " (shifting)"
	return out
