## Headless check that a gait is a consequence of a body — see Footfall.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/FootfallTest.gd
##
## Every creature in the game used to trot. The diagonal pairs were wired into the
## limb at construction, the only thing a posture could change was how far and how
## fast each of the four moved, and the result was that an Elephant was a Lizard
## with longer legs and a slower beat — which is exactly what it looked like.
##
## So this file asks the one question none of the others do: *in what order do the
## feet come down*, and does that order come from the animal?
##
## Footfall patterns are measured here the way they are measured in life, by
## Hildebrand's two numbers: the duty factor, and the **diagonality** — the phase
## by which a forefoot follows the hindfoot on its own side, as a share of one
## stride. Half is a trot, a quarter is the four-beat lateral-sequence walk nearly
## every heavy quadruped uses, nothing is a pace, and a girdle whose two limbs
## land together at all is one of the asymmetric gaits.
##
## Nothing anywhere in the simulation stores those names. They are what a phase
## measurement is called afterwards.
extends SceneTree

const TICK: float = 1.0 / 60.0
const SETTLE: int = 180
const SAMPLE: int = 900

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var player: Creature = main.creature
	_check(player != null, "the habitat did not build a body")
	if player == null:
		_finish()
		return false
	# An empty, flat paddock. Every measurement below is of a body walking on its
	# own legs; an obstacle to climb or an animal to walk into would make each of
	# them a measurement of something else.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)

	_check_one_body_changes_gait_with_speed(player)
	_check_the_pattern_comes_from_the_body(player)
	_check_a_girdle_lands_together_only_when_it_can(player)
	_check_two_legs_is_a_measurement(player)
	_check_the_back_folds_only_when_the_girdles_pair(player)
	_check_the_body_tips_onto_its_feet(player)
	_finish()
	return false


# ------------------------------------------------------------------- speed ----

## The claim the old system could not make at all: one animal, several gaits.
##
## Posture used to decide how many feet could be off the ground and that was the
## end of it, so a creature moved identically at every speed it had. Whether a
## body can be caught mid-fall is a question about how fast it is going *for its
## size* — Froude number, and nothing else — so the same Cat must walk on three
## feet, run on two, and leave the ground entirely when it is going fast enough.
func _check_one_body_changes_gait_with_speed(player: Creature) -> void:
	var stroll: Dictionary = _measure(player, "Cat", 0.28)
	var run: Dictionary = _measure(player, "Cat", 1.0)

	_check(float(stroll["diagonality"]) < 0.35,
		"a strolling Cat did not walk in a four-beat lateral sequence (diagonality %.2f)"
			% stroll["diagonality"])
	_check(int(stroll["aloft"]) <= 2,
		"a strolling Cat had %d feet off the ground at once" % stroll["aloft"])
	_check(int(run["aloft"]) > int(stroll["aloft"]),
		"a Cat at a flat run picked up no more feet at once than one strolling (%d, %d)"
			% [stroll["aloft"], run["aloft"]])
	_check(float(run["duty"]) < float(stroll["duty"]),
		"a Cat at a flat run kept its feet down as long as one strolling (%.2f, %.2f)"
			% [run["duty"], stroll["duty"]])
	# And the two are the same animal. Nothing was rebuilt between them.
	_check(float(run["froude"]) > float(stroll["froude"]) * 4.0,
		"the two speeds were not far enough apart to be different gaits (Fr %.2f, %.2f)"
			% [stroll["froude"], run["froude"]])
	notes.append("Cat walks at Fr %.2f (diagonality %.2f) and %s at Fr %.2f"
		% [stroll["froude"], stroll["diagonality"], run["gait"], run["froude"]])


# ------------------------------------------------------------------ bodies ----

## Three builds driven identically, at the same fraction of their own top speed,
## and each one has to produce a different pattern — for a reason written in its
## own proportions rather than in its name.
func _check_the_pattern_comes_from_the_body(player: Creature) -> void:
	# A sprawled animal's limbs row out to the side, so almost none of a leg is
	# available to drive the body along and its girdles can never work as a pair
	# however fast it goes. What it has instead is a spine, and at speed it trots
	# with the whole of it — which is the reference lizard gait.
	var lizard: Dictionary = _measure(player, "Lizard", 1.0)
	_check(absf(float(lizard["diagonality"]) - 0.5) < 0.15,
		"a Lizard at speed did not trot on its diagonals (diagonality %.2f)"
			% lizard["diagonality"])
	_check(float(lizard["launch"]) < Footfall.LAUNCH_MIN,
		"a sprawled build was offered an asymmetric gait (launch %.2f)" % lizard["launch"])
	_check(float(lizard["sway"]) > 6.0,
		"a trotting Lizard's back barely moved (%.1f px of sway)" % lizard["sway"])

	# A columnar one cannot leave the ground at all — its knees do not open far
	# enough to push against anything, and nothing had to say so — and it is going
	# so slowly for its size that it never leaves the walking regime either. What is
	# left is the four-beat lateral sequence: one foot at a time, hind then fore
	# down each side in turn.
	var elephant: Dictionary = _measure(player, "Elephant", 1.0)
	_check(float(elephant["diagonality"]) < 0.3,
		"an Elephant at its top speed stopped walking in a lateral sequence (diagonality %.2f)"
			% elephant["diagonality"])
	_check(int(elephant["aloft"]) == 1,
		"an Elephant lifted %d feet at once" % elephant["aloft"])
	_check(float(elephant["froude"]) < Footfall.FROUDE_WALK,
		"an Elephant reached the running regime (Fr %.2f)" % elephant["froude"])

	notes.append("Lizard trots on %.2f diagonality, Elephant ambles on %.2f"
		% [lizard["diagonality"], elephant["diagonality"]])


# -------------------------------------------------------------- asymmetric ----

## A bound, a gallop and a hop are one thing: the two limbs of a girdle landing
## together instead of alternating. Whether a body may do that is three abilities
## multiplied — legs that point along the animal, a back that folds, and somewhere
## to push off to — and how far into it the animal is is its speed for its size.
func _check_a_girdle_lands_together_only_when_it_can(player: Creature) -> void:
	var cheetah: Dictionary = _measure(player, "Cheetah", 1.0)
	_check(float(cheetah["aerial"]) > 0.8,
		"a Cheetah at full stretch did not commit to an asymmetric gait (aerial %.2f)"
			% cheetah["aerial"])
	_check(int(cheetah["aloft"]) >= 3,
		"a galloping Cheetah never had more than %d feet off the ground" % cheetah["aloft"])
	_check(float(cheetah["hind_together"]) > 0.5,
		"a galloping Cheetah's hind feet landed apart %.0f%% of the time"
			% ((1.0 - float(cheetah["hind_together"])) * 100.0))

	# The control on the other side of the multiplication: an Elephant is driven
	# as hard as its body allows and still keeps every one of the symmetrical
	# gait's promises, because its knees do not open far enough to push against
	# anything. Nothing to gather with, nothing left the ground in numbers.
	var elephant: Dictionary = _measure(player, "Elephant", 1.0)
	_check(float(elephant["aerial"]) < Footfall.SUSPENSION_AT,
		"an Elephant committed to an asymmetric gait (aerial %.2f)" % elephant["aerial"])
	_check(int(elephant["aloft"]) <= 2,
		"an Elephant had %d feet off the ground at once" % elephant["aloft"])
	notes.append("Cheetah gathers %.2f, Elephant %.2f" % [cheetah["aerial"], elephant["aerial"]])


# ------------------------------------------------------------------ bipeds ----

## Two legs is not a posture, a species or a mode. It is an arm too short to reach
## the floor from a shoulder its own hind legs are holding up, and everything else
## follows from the rest of the simulation noticing.
func _check_two_legs_is_a_measurement(player: Creature) -> void:
	var rex: Dictionary = _measure(player, "T. rex", 1.0)
	_check(not bool(rex["bearing"]),
		"a T. rex put its forelimbs on the ground")
	_check(int(rex["fore_steps"]) == 0,
		"a two-legged animal took %d steps on its arms" % rex["fore_steps"])
	_check(int(rex["hind_steps"]) > 8,
		"a two-legged animal barely walked (%d hind steps)" % rex["hind_steps"])
	# The shoulders are carried by the back rather than by the arms — at the
	# angle the species holds its trunk, never dropped nose-down onto limbs a
	# fifth the length of its legs. The measured slope is the carried angle's
	# own sine (the rise is spread over the same span the pitch divides by), so
	# the check is against the build's number rather than against level, and a
	# species carried level still gets exactly the old assertion.
	var carried: float = sin(deg_to_rad(player.params.trunk_lift_deg))
	_check(absf(float(rex["pitch"]) - carried) < 0.06,
		"a two-legged animal stood off its carried trunk angle (pitch %.3f against %.3f)"
			% [rex["pitch"], carried])
	# ...and the arms are held, not dragged: their feet hang below the shoulder
	# rather than being solved to a floor they cannot come near.
	_check(float(rex["fore_foot_height"]) > 4.0,
		"a carried forelimb was solved down to the ground (%.1f px)" % rex["fore_foot_height"])

	# The same arithmetic with the spring turned up. A hop is the identical
	# collapse of the hind girdle a Cheetah's bound is, on a body with nothing
	# else on the floor to be out of phase with — and a Kangaroo pairs its hind
	# feet at *every* speed, for two different reasons that meet in the middle.
	# Fast it is the asymmetric collapse. Slow it is the pentapedal crawl: a
	# macropod cannot stride its hind legs out of phase on the ground, and what
	# affords the paired swing at a walk is the tail — a strut thick enough to
	# stand on, dropped to the floor by the reared trunk. See
	# Locomotion.tail_prop.
	var slow: Dictionary = _measure(player, "Kangaroo", 0.25)
	var fast: Dictionary = _measure(player, "Kangaroo", 1.0)
	_check(float(slow["hind_together"]) > 0.6,
		"a Kangaroo moving slowly alternated its hind feet (%.0f%% of landings paired)"
			% (float(slow["hind_together"]) * 100.0))
	_check(String(slow["gait"]) == "pentapedal crawl",
		"a slow Kangaroo's gait read as \"%s\", not the tail-propped crawl"
			% slow["gait"])
	_check(float(fast["hind_together"]) > 0.6,
		"a Kangaroo at speed did not put its hind feet down together (%.0f%%)"
			% (float(fast["hind_together"]) * 100.0))
	# ...and the crawl is the prop's, not a rule about bipeds: the T. rex has
	# the heavier tail and carries it level, a whole hip height off the floor,
	# so its slow gait keeps the alternating stride the same measurement gives
	# any unpropped pair of legs.
	var rex_slow: Dictionary = _measure(player, "T. rex", 0.25)
	_check(float(rex_slow["hind_together"]) < 0.3,
		"a slow T. rex paired its hind feet (%.0f%%) — its level tail cannot prop"
			% (float(rex_slow["hind_together"]) * 100.0))
	notes.append("T. rex strides on two, Kangaroo crawls %.0f%% then hops %.0f%% paired"
		% [float(slow["hind_together"]) * 100.0, float(fast["hind_together"]) * 100.0])


# ------------------------------------------------------------------- spine ----

## The back is part of the gait or it is decoration, and which one it is has to be
## visible in the body's own length. A galloping animal folds and extends; a
## trotting one does not, because a trot's two hind feet are half a cycle apart
## and cancel — the measurement selects the regime on its own.
func _check_the_back_folds_only_when_the_girdles_pair(player: Creature) -> void:
	var cheetah: Dictionary = _measure(player, "Cheetah", 1.0)
	var lizard: Dictionary = _measure(player, "Lizard", 1.0)
	_check(float(cheetah["stretch"]) > 0.04,
		"a galloping Cheetah's body never changed length (%.1f%%)"
			% (float(cheetah["stretch"]) * 100.0))
	_check(float(lizard["stretch"]) <= 0.0001,
		"a trotting Lizard's back folded (%.2f%%) — an alternating gait has no gather"
			% (float(lizard["stretch"]) * 100.0))
	# ...and a back that cannot fold does not, whatever its gait is doing.
	_check(player.locomotion.spine_freedom > 0.0,
		"spine freedom came out at nothing for a body that plainly bends")
	notes.append("Cheetah's back works %.0f%% of its length" % (float(cheetah["stretch"]) * 100.0))


# ---------------------------------------------------------------- attitude ----

## Four legs holding four different heights are a body that is tipped, and the tip
## is a measurement rather than a lean anybody drew. A bound has a whole girdle
## off the ground at once, so the weight lands fore-and-aft and the body pitches
## rather than rolls.
func _check_the_body_tips_onto_its_feet(player: Creature) -> void:
	var cheetah: Dictionary = _measure(player, "Cheetah", 1.0)
	# Quoted as the swing over the run rather than as a peak, because that is
	# what a body tipping about is: how far it travels, not how far off level it
	# ever got.
	_check(float(cheetah["pitch_swing"]) > float(cheetah["roll"]),
		"a bounding Cheetah rolled more than it pitched (%.3f roll, %.3f pitch)"
			% [cheetah["roll"], cheetah["pitch_swing"]])
	notes.append("Cheetah pitches %.3f over %.3f of roll"
		% [cheetah["pitch_swing"], cheetah["roll"]])


# ------------------------------------------------------------------ harness ----

## Drives one build at one throttle and reads the gait off the feet.
##
## Everything returned is measured from what the four limbs actually did, not
## asked of the solver — except the four diagnostic values at the bottom, which
## are what `Footfall` decided and are there so a failure can say *why*.
func _measure(player: Creature, preset: String, throttle: float) -> Dictionary:
	player.params.apply_preset(preset)
	player.command = MovementInput.Command.new()
	player.reset(Vector2.ZERO, 0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = throttle
	drive.sprint = throttle > 0.9

	var lifts: Dictionary = {}
	var was: Dictionary = {}
	var down: Dictionary = {}
	var steps: Dictionary = {}
	for limb in player.gait.limbs:
		lifts[limb.key] = []
		was[limb.key] = false
		down[limb.key] = 0
		steps[limb.key] = 0

	var aloft: int = 0
	var sway: float = 0.0
	var roll_lo: float = INF
	var roll_hi: float = -INF
	var pitch_lo: float = INF
	var pitch_hi: float = -INF
	var short: float = INF
	var long: float = -INF
	var fore_foot: float = 0.0
	var bearing: int = 0
	var aerial: float = 0.0

	for tick in SETTLE + SAMPLE:
		player.command = drive
		# Eighteen seconds flat out is longer than the quicker builds in the file
		# can hold a sprint, and an animal that has run itself out is held to a
		# pace it can keep up — see Stamina.hold. That is right in the habitat and
		# wrong here: what this measures is which feet a *running* body puts down
		# in what order, so the run has to last the window. Kept full rather than
		# shortening the sample, because the pattern is counted in footfalls and a
		# short window is a small count.
		player.stamina.reset()
		player._physics_process(TICK)
		if tick < SETTLE:
			continue
		# The solver's commitment, at its fullest over the run rather than at
		# whatever instant the window happens to close on. The reading breathes
		# with the surge of the gait as the body works across the habitat's
		# terrain, so the final tick is a sample of that oscillation's phase —
		# the build's answer to "does this animal commit" is its peak.
		aerial = maxf(aerial, player.gait.footfall.aerial)
		var up: int = 0
		for limb in player.gait.limbs:
			if limb.stepping and not was[limb.key]:
				(lifts[limb.key] as Array).append(tick)
				steps[limb.key] += 1
			was[limb.key] = limb.stepping
			if limb.stepping:
				up += 1
			else:
				down[limb.key] += 1
			sway = maxf(sway, limb.sway)
			if limb.pair == Limb.FRONT:
				fore_foot = maxf(fore_foot, limb.foot_height)
			if limb.bearing:
				bearing += 1
		aloft = maxi(aloft, up)
		roll_lo = minf(roll_lo, player.gait.roll)
		roll_hi = maxf(roll_hi, player.gait.roll)
		pitch_lo = minf(pitch_lo, player.gait.pitch)
		pitch_hi = maxf(pitch_hi, player.gait.pitch)
		short = minf(short, player.segment_rest())
		long = maxf(long, player.segment_rest())
	player.command = MovementInput.Command.new()

	var cycle: float = _cycle(lifts, player)
	var hind: float = _phase(lifts["RL"], lifts["RL"], cycle)
	var duty: float = 0.0
	var walked: int = 0
	for limb in player.gait.limbs:
		if not limb.bearing:
			continue
		duty += float(down[limb.key]) / float(SAMPLE)
		walked += 1
	var want: Footfall = player.gait.footfall

	return {
		# Hildebrand's two, measured off the footfalls themselves.
		"diagonality": fposmod(_phase(lifts["FL"], lifts["RL"], cycle) - hind, 1.0),
		"duty": duty / maxf(float(walked), 1.0),
		"aloft": aloft,
		# How often the two hind feet leave the ground on the same beat — the one
		# reading that tells a bound, a gallop and a hop apart from everything else.
		"hind_together": _paired(lifts["RL"], lifts["RR"], cycle),
		"fore_steps": int(steps["FL"]) + int(steps["FR"]),
		"hind_steps": int(steps["RL"]) + int(steps["RR"]),
		"fore_foot_height": fore_foot,
		"sway": sway,
		"roll": roll_hi - roll_lo,
		"pitch": (pitch_lo + pitch_hi) * 0.5,
		"pitch_swing": pitch_hi - pitch_lo,
		# How much of its own length the back worked over the run.
		"stretch": (long - short) / maxf(long, 0.001),
		"bearing": bearing > 0 and player.locomotion.forelimbs_bear,
		# What the solver decided, for the failure messages.
		"froude": want.froude,
		"launch": want.launch,
		"aerial": aerial,
		"interference": want.interference,
		"gait": want.describe(),
	}


## Mean interval between successive lifts of whichever limb stepped most, in
## ticks. The stride, measured rather than asked for.
func _cycle(lifts: Dictionary, player: Creature) -> float:
	var best: Array = []
	for limb in player.gait.limbs:
		if (lifts[limb.key] as Array).size() > best.size():
			best = lifts[limb.key]
	if best.size() < 2:
		return 0.0
	return float(best[best.size() - 1] - best[0]) / float(best.size() - 1)


## Circular mean phase of one limb's lifts against another's cycle. Circular
## because a phase just under one and one just over zero are the same phase.
func _phase(lifts: Array, reference: Array, cycle: float) -> float:
	if lifts.is_empty() or reference.is_empty() or cycle <= 0.0:
		return 0.0
	var sx: float = 0.0
	var sy: float = 0.0
	for t in lifts:
		var nearest: float = INF
		for r in reference:
			if absf(float(t - r)) < absf(nearest):
				nearest = float(t - r)
		var a: float = fposmod(nearest / cycle, 1.0) * TAU
		sx += cos(a)
		sy += sin(a)
	return fposmod(atan2(sy, sx) / TAU, 1.0)


## Share of one limb's lifts that happen within a tenth of a stride of the
## other's. One is a pair that lands as a single footfall; nothing is two limbs
## taking turns.
func _paired(a: Array, b: Array, cycle: float) -> float:
	if a.is_empty() or b.is_empty() or cycle <= 0.0:
		return 0.0
	var window: float = maxf(cycle * 0.1, 1.0)
	var together: int = 0
	for t in a:
		for u in b:
			if absf(float(t - u)) <= window:
				together += 1
				break
	return float(together) / float(a.size())


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("footfall OK — the order the feet come down in is read off the body: %s"
			% " · ".join(notes))
		quit(0)
	else:
		for failure in failures:
			print("FOOTFALL FAIL — ", failure)
		quit(1)
