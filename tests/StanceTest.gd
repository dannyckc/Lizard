## Headless check for the posture × locomotor classification — see Stance.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/StanceTest.gd
##
## A stance is two facts said together: how the limbs are carried out of the
## ground plane (the posture) and how many of them the body is walking on (the
## locomotor mode). Every combination of the two is a real animal — a sprawled
## quadruped is a lizard and a sprawled biped is a basilisk mid-sprint; an erect
## quadruped is a cat and an erect biped is a tyrannosaur — so this file builds
## one of each and holds every one of them to the same three claims: it
## classifies as what it is, it stands (or runs) with its weight over its
## support, and the classification is doing real work in the simulation rather
## than labelling it.
##
## Then the part that is new with the second axis: a body may support more than
## one stance and move between them with its gait. The crocodile's high walk and
## the basilisk's bipedal sprint are the two shipped rules, and both are checked
## as movements — entered at the pace that earns them, left with hysteresis,
## blended without teleports, and without the flesh census being re-carved by a
## change that is carriage rather than tissue.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false
var summary: Array[String] = []


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var player: Creature = main.creature
	_check(player != null, "the habitat did not build a creature")
	if player == null:
		_finish()
		return false

	_check_blend_is_exact_at_the_ends()
	_check_presets_keep_their_one_stance(player)
	_check_the_matrix(player)
	_check_high_walk(player)
	_check_bipedal_sprint(player)
	_finish()
	return false


# ---------------------------------------------------------------- the axes ----

## The blend is the transition, so its ends have to be the table to the digit —
## a stance test pinned to the rows must still be pinned after a body has been
## through a transition and back. And the middle has to be between the ends,
## because it is a skeleton part way through a movement rather than a third
## stance.
func _check_blend_is_exact_at_the_ends() -> void:
	var mixed := Posture.new()
	var sprawled := Posture.new(Posture.SPRAWLED)
	var semi := Posture.new(Posture.SEMI_UPRIGHT)
	mixed.mix(Posture.SPRAWLED, Posture.SEMI_UPRIGHT, 0.0)
	_check(is_equal_approx(mixed.tilt, sprawled.tilt)
			and is_equal_approx(mixed.joint, sprawled.joint),
		"a blend at zero was not exactly the stance it starts from")
	mixed.mix(Posture.SPRAWLED, Posture.SEMI_UPRIGHT, 1.0)
	_check(is_equal_approx(mixed.tilt, semi.tilt)
			and is_equal_approx(mixed.joint, semi.joint)
			and mixed.feet_down == semi.feet_down,
		"a blend at one was not exactly the stance it arrives in")
	mixed.mix(Posture.SPRAWLED, Posture.SEMI_UPRIGHT, 0.5)
	_check(mixed.tilt > sprawled.tilt and mixed.tilt < semi.tilt,
		"a blend halfway through was not between its two ends")
	_check(Stance.MODE_NAMES.size() == Stance.MODE_COUNT,
		"the locomotor axis does not name every mode it has")


# ------------------------------------------------- nothing existing moved ----

## Every preset — and the default build — is one stance, the one its sheet
## measures. No facultative offer appears on any of them (the Lizard is a
## monitor, not a basilisk: its hind pair is 1.29 of its fore, below the line),
## so every calibrated gait in every other test is untouched by the second axis
## existing. The Lizard is then actually sprinted to make the claim in motion.
func _check_presets_keep_their_one_stance(player: Creature) -> void:
	var builds: Array[String] = ["(default)"]
	for preset in CreatureParams.PRESETS:
		builds.append(str(preset))
	for name in builds:
		_apply(player, name)
		var expected_mode: int = Stance.QUADRUPEDAL \
			if Locomotion.bears_on_forelimbs(player.params) else Stance.BIPEDAL
		_check(player.stance.supported.size() == 1,
			"%s supports %d stances where its sheet describes one"
				% [name, player.stance.supported.size()])
		_check(player.stance.supports(player.params.posture, expected_mode),
			"%s does not support the stance it is built in" % name)
		_check(player.posture.kind == player.params.posture,
			"%s is not standing in its own posture" % name)
		_check(player.stance.mode() == expected_mode,
			"%s classified as %s" % [name, player.stance.describe()])
		_check(player.locomotion.forelimbs_bear == (expected_mode == Stance.QUADRUPEDAL),
			"%s's locomotor mode and its bearing forelimbs disagree" % name)

	# The control, in motion: a flat-out sprinting Lizard keeps all four feet in
	# the gait, because a monitor's hind pair is under the dominance line and no
	# offer was ever derived for it.
	_apply(player, "Lizard")
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.sprint = true
	for _tick in 300:
		player.command = drive
		player._physics_process(TICK)
		_check(player.stance.mode() == Stance.QUADRUPEDAL,
			"a sprinting monitor reared — the dominance line is not holding")
		if failures.size() > 0:
			break
	player.command = MovementInput.Command.new()


# -------------------------------------------------------------- the matrix ----

## One build per posture × mode combination, each held to the same claims: it
## classifies as what it is, and it stands with its weight over what is holding
## it up. The quadrupedal column is the four presets; the bipedal column is the
## two obligate presets plus two constructed builds — a semi-upright biped (a
## chimpanzee walking upright, approximately) and a columnar one (Megatherium,
## approximately) — because no preset ships those forms.
func _check_the_matrix(player: Creature) -> void:
	_expect_standing(player, "Lizard", {}, Posture.SPRAWLED, Stance.QUADRUPEDAL)
	_expect_standing(player, "Cat", {}, Posture.SEMI_UPRIGHT, Stance.QUADRUPEDAL)
	_expect_standing(player, "Cheetah", {}, Posture.ERECT, Stance.QUADRUPEDAL)
	_expect_standing(player, "Elephant", {}, Posture.COLUMNAR, Stance.QUADRUPEDAL)
	_expect_standing(player, "T. rex", {}, Posture.ERECT, Stance.BIPEDAL)
	_expect_standing(player, "Kangaroo", {}, Posture.ERECT, Stance.BIPEDAL)
	# The two bipedal forms no preset ships, built by moving the one axis that
	# separates them from the ones that do — which is the demonstration that the
	# axes are genuinely independent. A two-legged body stands because its mass
	# brackets its hips (see Plumb; rearing forecloses nothing in plan view), so
	# each starts from a sheet that already balances on two and changes how the
	# limbs are carried, not where the weight is.
	#
	# The kangaroo's beam held on semi-upright limbs is the approximate upright-
	# walking chimpanzee — facultative in life, obligate as built here, which is
	# exactly the difference between a sheet and a behaviour.
	_expect_standing(player, "Kangaroo", {
		"posture": Posture.SEMI_UPRIGHT,
	}, Posture.SEMI_UPRIGHT, Stance.BIPEDAL)
	# And the tyrannosaur's balanced beam on columnar pillars — joints that
	# neither fold nor spring, a tail-propped slow walker — is the approximate
	# ground sloth.
	_expect_standing(player, "T. rex", {
		"posture": Posture.COLUMNAR,
		"hind_fold_range": 0.50, "trunk_lift_deg": 30.0,
		"tail_base_width": 14.0, "move_speed": 70.0,
	}, Posture.COLUMNAR, Stance.BIPEDAL)
	# The sprawled biped is the one combination that is only ever a gait — a
	# basilisk stands on four and runs on two — so it is checked in motion, in
	# _check_bipedal_sprint, and only its support is asserted here.
	_apply(player, "Lizard")
	player.params.leg_length = 55.0
	player.params.arm_length = 26.0
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	_check(player.stance.supports(Posture.SPRAWLED, Stance.BIPEDAL),
		"a hind-driven sprawler does not support the bipedal sprint")
	_check(player.stance.mode() == Stance.QUADRUPEDAL,
		"a standing basilisk-build is not on its four feet")
	summary.append("8 stances stand")


## Builds it, stands it still for three seconds, and asks the two questions
## every stance in the matrix has to answer.
func _expect_standing(player: Creature, preset: String, tweaks: Dictionary,
		expected_posture: int, expected_mode: int) -> void:
	_apply(player, preset)
	for key in tweaks:
		player.params.set(key, tweaks[key])
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 180:
		player._physics_process(TICK)
	var label: String = "%s %s/%s" % [preset, Posture.NAMES[expected_posture],
		Stance.MODE_NAMES[expected_mode]]
	_check(player.posture.kind == expected_posture
			and player.stance.mode() == expected_mode,
		"%s classified as %s" % [label, player.stance.describe()])
	_check(player.stance.supports(expected_posture, expected_mode),
		"%s does not support the stance it is standing in" % label)
	# The centre-of-gravity validation: the line the weight drops has to come
	# down inside whatever is holding the animal up, or the pose is a fall
	# being drawn as a stance. See Plumb — the support is the planted feet
	# grown by their own radius, plus the tail where a biped genuinely props.
	#
	# A quadruped is held to the line strictly: four corners bracket the weight
	# and there is no excuse. A biped's support has almost no width across the
	# line between its two feet — Plumb says so in as many words, and it is why
	# a biped has to keep moving — so its line is allowed the wobble of a
	# breathing pose, and the claim with teeth is the one below: the balance
	# system, which owns falling over, holds it standing.
	_check(player.plumb.posed and player.plumb.feet >= 2,
		"%s is not standing on measured support" % label)
	var margin: float = 0.0 if expected_mode == Stance.QUADRUPEDAL else -0.1
	_check(player.plumb.steadiness() >= margin,
		"%s stands with its weight outside its own feet (%.2f of support)"
			% [label, player.plumb.steadiness()])
	_check(player.alive and not player.balance.failed
			and player.balance.hold >= Balance.STANDING_MIN,
		"%s could not stand for three seconds" % label)
	# The classification is load-bearing, not a label: the mode is exactly
	# whether the forelimbs are in the gait.
	var fore_bearing: bool = false
	for limb in player.gait.limbs:
		if limb.pair == Limb.FRONT and limb.bearing:
			fore_bearing = true
	_check(fore_bearing == (expected_mode == Stance.QUADRUPEDAL),
		"%s's gait and its locomotor mode disagree about the forelimbs" % label)


# ------------------------------------------------------------ the high walk ----

## The crocodile's stance change: a sprawled build with the socket range to
## re-carry its limbs rises into a semi-upright high walk when it travels, and
## settles back down when it stops. The posture axis moving with the gait —
## and the flesh staying put while it does.
func _check_high_walk(player: Creature) -> void:
	_apply(player, "Lizard")
	player.params.stance_range = 1
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 30:
		player._physics_process(TICK)
	_check(player.stance.supports(Posture.SEMI_UPRIGHT, Stance.QUADRUPEDAL),
		"a croc-socketed sprawler does not support the high walk")
	_check(player.posture.kind == Posture.SPRAWLED,
		"a resting croc-build is not lying in its sprawl")
	var resting_clearance: float = player.stature.clearance
	var carve: int = player.anatomy.tissue.lattice.revision

	# Travel. The stance has to rise with the gait — and rise as a movement,
	# a few pixels a tick, never a swap.
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	var last: float = player.stature.clearance
	var worst_jump: float = 0.0
	for _tick in 360:
		player.command = drive
		player._physics_process(TICK)
		worst_jump = maxf(worst_jump, absf(player.stature.clearance - last))
		last = player.stature.clearance
	_check(player.posture.kind == Posture.SEMI_UPRIGHT,
		"a travelling croc-build did not rise into its high walk (still %s)"
			% player.stance.describe())
	_check(not player.stance.transitioning(),
		"six seconds of travel and the high walk has not finished arriving")
	_check(player.stature.clearance > resting_clearance + 4.0,
		"the high walk did not actually raise the body (%.1f -> %.1f px)"
			% [resting_clearance, player.stature.clearance])
	_check(worst_jump < 5.0,
		"the stance change teleported the body %.1f px in one tick" % worst_jump)
	_check(player.locomotion.forelimbs_bear,
		"the high walk took the forelimbs out of the gait — it is a posture "
			+ "change, not a mode change")
	# The census is the build's, and a carriage change may not touch it: the
	# lattice re-carving here is the exact 16 ms mid-gait stall ScenarioProbe
	# exists to catch.
	_check(player.anatomy.tissue.lattice.revision == carve,
		"rising into the high walk re-carved the flesh census")

	# And back down: the exit is under the entry, so the settle happens at a
	# stop, not at the first slow stride.
	player.command = MovementInput.Command.new()
	for _tick in 240:
		player._physics_process(TICK)
	_check(player.posture.kind == Posture.SPRAWLED,
		"a stopped croc-build did not settle back into its sprawl (still %s)"
			% player.stance.describe())
	summary.append("high walk rises %.0f px and settles" % (last - resting_clearance))


# ------------------------------------------------------- the bipedal sprint ----

## The basilisk's stance change: a hind-driven sprawler asked for everything
## lifts its working forelimbs and runs on two, then drops back to four when
## the sprint ends. The locomotor axis moving with the gait — dynamic balance,
## measured as the body staying up, not as the line staying inside the feet.
func _check_bipedal_sprint(player: Creature) -> void:
	_apply(player, "Lizard")
	player.params.leg_length = 55.0
	player.params.arm_length = 26.0
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)

	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.sprint = true
	var reared: int = 0
	var upright_and_balanced: bool = true
	for _tick in 420:
		player.command = drive
		player._physics_process(TICK)
		if player.stance.mode() == Stance.BIPEDAL:
			reared += 1
			if player.balance.failed or not player.alive:
				upright_and_balanced = false
	_check(reared > 60,
		"a sprinting basilisk-build never committed to two legs (%d ticks)" % reared)
	_check(upright_and_balanced,
		"the bipedal sprint fell over — the trajectory is not dynamically balanced")
	_check(player.stance.mode() == Stance.BIPEDAL,
		"still flat out, and back on four feet — the sprint did not hold")
	_check(not player.locomotion.forelimbs_bear,
		"bipedal, and the locomotion still counts four bearing limbs")
	_check(player.locomotion.bearing_limbs == 2,
		"the bipedal duty factor is not being quoted against two legs")
	var fore_up: bool = true
	for limb in player.gait.limbs:
		if limb.pair == Limb.FRONT and limb.bearing:
			fore_up = false
	_check(fore_up, "bipedal, and a forelimb is still in the footfall")
	_check(player.posture.kind == Posture.SPRAWLED,
		"the sprint changed the posture as well as the mode")

	# Ease off. The exit threshold is under the entry — hysteresis — and the
	# body comes back to its four feet as it slows.
	player.command = MovementInput.Command.new()
	for _tick in 300:
		player._physics_process(TICK)
	_check(player.stance.mode() == Stance.QUADRUPEDAL,
		"the sprint over, and the build is still on two legs")
	_check(player.locomotion.forelimbs_bear,
		"back on four feet, and the forelimbs still are not bearing")
	summary.append("bipedal sprint holds %d ticks" % reared)


# ------------------------------------------------------------------ tools ----

func _apply(player: Creature, preset: String) -> void:
	player.set_bite_held(false)
	if preset == "(default)":
		player.params.copy_from(CreatureParams.new())
	else:
		player.params.apply_preset(preset)
	player.command = MovementInput.Command.new()
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("stance OK — two axes, one skeleton: %s" % " · ".join(summary))
		quit(0)
	else:
		for failure in failures:
			print("STANCE FAIL — ", failure)
		quit(1)
