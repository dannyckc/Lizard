## Headless check that a jump is anatomy — see Leap, Spring, Jump.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/JumpTest.gd
##
## There used to be a `leap_height` parameter: a per-species multiple of the
## animal's own height, consulted once when the key went down. It could say
## anything at all and nothing about the body could contradict it, which is the
## defect this whole file exists to pin closed. A jump is now four measurements —
## how hard the muscle pulls for what the body weighs, how far the joints extend
## through, what elastic tissue is wound along the bones, and how much weight the
## animal can get over the girdle doing the pushing — so every claim below is
## about a *body* rather than about a control.
##
## Three groups, and they are three different kinds of claim:
##
##   * **the control** — hold and release, and what the holding is worth. That a
##     tap is a hop and a hold is a leap, that the hold stops being worth anything
##     at a time this animal's own legs set, and that the whole of it is stored
##     rather than multiplied.
##   * **the body doing it** — that the crouch, the push, the tuck, the reach and
##     the fold are real joint angles rather than an animation. Every one of them
##     is checked by measuring the height the *feet* are holding the body at,
##     because that is the only channel any of it travels through.
##   * **the anatomy deciding it** — that a build with no travel in its joints
##     cannot jump however long the key is held, that taking the elastic tissue
##     out of a leg makes it jump less far, and that a body too short-limbed to
##     push with can still throw itself if it has a catch to let go with. That
##     last one is the insects, and it is the reason none of this is a rule about
##     species.
extends SceneTree

const TICK: float = 1.0 / 60.0

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
	# Flat, empty ground. Every measurement here is of one body pushing against the
	# floor, and an obstacle to climb or an animal to walk into would make each of
	# them a measurement of something else.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)

	_check_the_hold_is_the_jump(player)
	_check_the_charge_is_capped(player)
	_check_the_body_does_it(player)
	_check_the_hind_limbs_drive(player)
	_check_the_landing_is_absorbed(player)
	_check_it_leaves_from_where_it_was(player)
	_check_anatomy_decides(player)
	_finish()
	return false


# ----------------------------------------------------------------- control ----

## A tap is a hop and a hold is a leap, and the difference is stored work.
##
## The claim is specifically that the apex is *ordered* by how long the key was
## down, not that any particular hold is worth any particular height — which is
## the anatomy's business and is checked further down.
func _check_the_hold_is_the_jump(player: Creature) -> void:
	var tap: float = _jump(player, "Cat", 1)
	var brief: float = _jump(player, "Cat", 12)
	var full: float = _jump(player, "Cat", 45)

	_check(tap > 0.0, "a Cat given one tick of the key never left the ground")
	_check(brief > tap * 1.15,
		"a brief hold jumped no higher than a tap (%.0f px, %.0f px)" % [brief, tap])
	_check(full > brief * 1.3,
		"a full charge jumped no higher than a brief one (%.0f px, %.0f px)"
			% [full, brief])
	# And the whole of it is the animal's own arithmetic rather than a control
	# curve: a fully charged jump has to arrive at what Leap says this body is
	# worth. Loosely, because the push-off spends a few pixels standing the animal
	# up on its own legs before it leaves, and that height is real but is not
	# elevation.
	var wanted: float = player.leap.peak(1.0)
	_check(absf(full - wanted) < wanted * 0.25,
		"a fully charged Cat cleared %.0f px where its anatomy says %.0f" % [full, wanted])
	notes.append("Cat tap %.0f px, held %.0f px, anatomy says %.0f" % [tap, full, wanted])


## Holding on past the top is a creature standing in a crouch.
##
## The charge time is a limb's own swing period — see Leap.LOAD_SWINGS — so this
## is not a timer that was chosen. What it must do is *stop*: a key held for five
## times as long as the store takes to wind has to produce exactly the jump the
## full wind produces, or the charge is a power multiplier wearing a spring's
## clothes.
func _check_the_charge_is_capped(player: Creature) -> void:
	_apply(player, "Cat")
	var window: int = int(ceil((player.leap.charge_time + player.leap.gather_time) / TICK))
	var wound: float = _jump(player, "Cat", window + 4)
	var leaned_on: float = _jump(player, "Cat", window * 5)
	_check(absf(leaned_on - wound) < maxf(wound * 0.05, 1.0),
		"holding the key five times as long added %.1f px to a %.0f px jump"
			% [leaned_on - wound, wound])

	# ...and the store itself says so, rather than the apex merely coinciding.
	_apply(player, "Cat")
	var hold := MovementInput.Command.new()
	hold.climb = 1.0
	player.command = hold
	for _t in window * 5:
		player._physics_process(TICK)
	_check(is_equal_approx(player.jump.charge, 1.0),
		"a Cat held at full charge read %.3f rather than a full store" % player.jump.charge)
	_check(player.jump.phase == Jump.LOAD,
		"a Cat holding a full charge was %s rather than holding it"
			% player.jump.phase_name())
	notes.append("Cat winds in %.2f s and holds there" % player.leap.charge_time)
	_release(player)


# -------------------------------------------------------------------- body ----

## Every phase is a joint angle, and the only channel any of it has to the
## picture is the height the feet are holding the body at.
##
## So that is what is measured. If the crouch were an animation the body would not
## come down; if the push-off were an impulse the body would not go up before it
## left; and if the tuck were drawn rather than posed the legs would not draw in.
## Each of the three is a different sign of the same number — see
## Gait._stance_extension.
func _check_the_body_does_it(player: Creature) -> void:
	_apply(player, "Cat")
	var standing: float = player.gait.support
	var lowest: float = INF
	var highest: float = -INF
	var grounded_high: float = -INF
	var seen: Dictionary = {}

	var hold := MovementInput.Command.new()
	hold.climb = 1.0
	player.command = hold
	var window: int = int(ceil((player.leap.charge_time + player.leap.gather_time) / TICK)) + 6
	for tick in window + 200:
		hold.climb = 1.0 if tick < window else 0.0
		player._physics_process(TICK)
		seen[player.jump.phase] = true
		if player.jump.phase == Jump.LOAD:
			lowest = minf(lowest, player.gait.support)
		if player.jump.phase == Jump.THRUST:
			highest = maxf(highest, player.gait.support)
			if player.elevation.is_grounded():
				grounded_high = maxf(grounded_high, player.gait.support)
	_release(player)

	_check(lowest < standing - 1.0,
		"a Cat winding a jump did not come down at all (%.1f px standing, %.1f crouched)"
			% [standing, lowest])
	_check(highest > standing + 1.0,
		"a Cat pushing off did not stand up on its legs (%.1f px standing, %.1f pushing)"
			% [standing, highest])
	# The one that says it is a push rather than a launch: the body is already
	# rising while its feet are still on the floor.
	_check(grounded_high > standing,
		"a Cat gained no height before leaving the ground (%.1f px, standing %.1f)"
			% [grounded_high, standing])

	# And all six phases happened, in the one order they can happen in.
	for phase in [Jump.GATHER, Jump.LOAD, Jump.THRUST, Jump.FLIGHT, Jump.REACH,
			Jump.ABSORB, Jump.RECOVER]:
		_check(seen.has(phase),
			"a whole jump never entered %s" % Jump.PHASE_NAMES[phase])
	notes.append("Cat rides %.0f px standing, %.0f crouched, %.0f at full push"
		% [standing, lowest, highest])


## A quadruped pushes with the girdle it can get its weight over, and on a body
## with a trunk in front and a tail behind that is the hind one.
##
## Nothing anywhere says so — see Physique.balance, which measures how much of the
## animal is on the far side of each girdle, and Leap, which spends it. The
## forelimbs are not idle: they crouch, they straighten under a body accelerating
## away from them, and they take the landing. What they do not do is drive.
func _check_the_hind_limbs_drive(player: Creature) -> void:
	_apply(player, "Cat")
	var behind: float = player.leap.share.y
	# Most of the push, rather than a fixed multiple of it. Part of what separates
	# the two girdles is `Physique.balance` — how much animal there is on the far
	# side of each — and that reading got a good deal less lopsided when the width
	# profile's hip knot was moved onto the hips: a Cat's tail is a light, tapering
	# thing, and it had been drawn at nearly hip width for three quarters of its
	# length. What is left doing the separating is the articulation, which is where
	# it belonged — a knee that folds past its stance, a longer light shin and most
	# of the animal's stored tissue, all of them on the hind girdle.
	_check(behind > 0.55,
		"a Cat's forelimbs took %.0f%% of the push" % (player.leap.share.x * 100.0))

	var deepest := Vector2.ZERO
	var hold := MovementInput.Command.new()
	hold.climb = 1.0
	player.command = hold
	for _t in 60:
		player._physics_process(TICK)
		deepest = deepest.max(player.jump.load)
	_check(deepest.y > deepest.x,
		"a Cat gathering folded its forelimbs (%.2f) as deeply as its hind (%.2f)"
			% [deepest.x, deepest.y])
	_release(player)

	# A two-legged animal has only one girdle to push with, and that too is a
	# measurement — an arm too short to reach the floor is an arm that is carried.
	_apply(player, "Kangaroo")
	_check(player.leap.share.x <= 0.0,
		"a two-legged build was given %.2f of its push in the forelimbs"
			% player.leap.share.x)
	notes.append("Cat pushes %.0f%% behind, Kangaroo %.0f%%"
		% [behind * 100.0, player.leap.share.y * 100.0])


## What goes up is caught by the joints, and by how much of them the arrival
## actually used.
##
## The bracing girdle is the one at the front of a body coming down nose-first out
## of a ballistic arc, so on a quadruped it is the forelimbs — which is the other
## half of what they are for. A deeper fall has to fold them further, and the
## scale it is measured against is the work that girdle could take out of a body,
## which is the same force-over-distance the push was.
func _check_the_landing_is_absorbed(player: Creature) -> void:
	var gentle: float = _landing_fold(player, 40.0)
	var hard: float = _landing_fold(player, 260.0)
	_check(gentle > 0.0, "a Cat landing from 40 px did not flex at all")
	_check(hard > gentle * 1.5,
		"a Cat landing from 260 px folded no further than from 40 (%.2f, %.2f)"
			% [hard, gentle])
	_check(hard <= Jump.ABSORB_DEPTH + 0.001,
		"a landing drove a joint past its own stop (%.2f)" % hard)
	notes.append("Cat folds %.2f of its joint from 40 px, %.2f from 260" % [gentle, hard])


## How far the front joints folded on the way out of a drop from `from` pixels.
func _landing_fold(player: Creature, from: float) -> float:
	_apply(player, "Cat")
	player.elevation.height = from
	player.elevation.rate = 0.0
	var deepest: float = 0.0
	for _t in 180:
		player._physics_process(TICK)
		deepest = maxf(deepest, player.jump.load.x)
	return deepest


## A jump starts from the pose the animal was already in.
##
## Two claims and they are separable. Nothing snaps: the joints are eased toward
## every phase's demand at a rate the limb's own pendulum sets, so no tick may move
## the body by anything like the whole of its travel. And nothing is reset: a
## creature jumping while it walks keeps its speed, and keeps the ground it was
## covering — leaning into the push trades apex for distance rather than adding
## either.
func _check_it_leaves_from_where_it_was(player: Creature) -> void:
	_apply(player, "Cat")
	var run := MovementInput.Command.new()
	run.throttle = 1.0
	player.command = run
	for _t in 120:
		player._physics_process(TICK)
	var cruising: float = player.speed
	_check(cruising > 40.0, "the Cat never got going (%.0f px/s)" % cruising)

	var worst: float = 0.0
	var last: float = player.gait.support
	var from: Vector2 = player.head_pos
	var window: int = int(ceil((player.leap.charge_time + player.leap.gather_time) / TICK)) + 6
	var landed_at: Vector2 = from
	var covered: bool = false
	for tick in window + 200:
		run.climb = 1.0 if tick < window else 0.0
		player._physics_process(TICK)
		worst = maxf(worst, absf(player.gait.support - last))
		last = player.gait.support
		if tick > window and player.elevation.is_grounded() and not covered:
			covered = true
			landed_at = player.head_pos
	# Before the release, because letting go of the throttle is what stops a
	# creature and this check is about the jump not stopping one.
	_check(player.speed > 0.0, "a Cat that jumped while running stopped dead")
	_release(player)

	# A limb's whole travel is its stand-to-fold span, and no single tick may spend
	# anything approaching it. Generous, because it is looking for a snap rather
	# than measuring a rate.
	var travel: float = (player.articulation.hind.stand - player.articulation.hind.fold) \
		* player.params.leg_length * player.size_scale
	_check(worst < travel * 0.35,
		"a jump moved the body %.1f px in one tick of a %.1f px joint travel"
			% [worst, travel])
	_check(covered and landed_at.distance_to(from) > 60.0,
		"a running jump covered %.0f px of ground" % landed_at.distance_to(from))
	notes.append("a running Cat jumps %.0f px down the road" % landed_at.distance_to(from))


# ----------------------------------------------------------------- anatomy ----

## The three claims the parameter could not make.
func _check_anatomy_decides(player: Creature) -> void:
	# A body whose joints do not open cannot push, and holding the key for as long
	# as you like does not give it anywhere to push from. It is not refused: the
	# arithmetic comes out under what it lifts one foot by, which is the difference
	# between not having a jump and having been told it may not jump.
	_apply(player, "Elephant")
	_check(not player.leap.capable,
		"an Elephant was credited with a jump of %.0f px" % player.leap.peak(1.0))
	_check(_jump(player, "Elephant", 240) <= 0.0,
		"an Elephant held the key long enough and left the ground")
	# ...and it still visibly tries, which is the honest reading of an animal with
	# a little fold and no push: it settles onto its hind legs and nothing happens.
	_apply(player, "Elephant")
	var hold := MovementInput.Command.new()
	hold.climb = 1.0
	player.command = hold
	var shifted: float = 0.0
	for _t in 120:
		player._physics_process(TICK)
		shifted = maxf(shifted, absf(player.jump.load.y))
	_release(player)
	_check(shifted > 0.0, "an Elephant asked to jump did not shift its weight at all")

	# Take the elastic tissue out of a leg and the same leg jumps less far. This is
	# the only check that isolates the spring, and it has to be the same body:
	# every bone, angle and muscle below is identical between the two runs.
	var sprung: float = _peak_with(player, "Cat", {})
	var slack: float = _peak_with(player, "Cat", {"fore_spring": 0.0, "hind_spring": 0.0})
	_check(sprung > slack * 1.15,
		"a Cat with its tendons removed jumped as far as one with them (%.0f px, %.0f px)"
			% [slack, sprung])

	# And the mechanism that is not a tendon. A body with legs too short to push
	# through — an insect's proportions, and it is the joint travel doing it rather
	# than the size — returns almost nothing of what it stores, because a spring
	# gives its work back by opening a joint and this one barely opens. A catch
	# does not care: it lets go independently of the limb, which is why the insects
	# that jump have one and the ones that do not, do not.
	var stub: Dictionary = {
		"posture": Posture.SEMI_UPRIGHT,
		"arm_length": 10.0, "leg_length": 12.0,
		"hind_fold_range": 0.30, "fore_fold_range": 0.30,
		"hind_spring": 1.0, "fore_spring": 0.6,
		"density": 0.5, "muscle_power": 2.0,
	}
	var unlatched: float = _peak_with(player, "Lizard", stub)
	var latched: Dictionary = stub.duplicate()
	latched["spring_latch"] = 1.0
	var caught: float = _peak_with(player, "Lizard", latched)
	_check(caught > unlatched * 1.35,
		"a catch bought a short-limbed body nothing (%.1f px, %.1f px)"
			% [caught, unlatched])
	notes.append("tendons are worth %.0f px to a Cat; a catch is worth %.1f px to a stub-legged build"
		% [sprung - slack, caught - unlatched])
	_apply(player, "Lizard")


# ------------------------------------------------------------------- rigs ----

## One jump: hold for `ticks`, let go, and report the apex.
func _jump(player: Creature, preset: String, ticks: int) -> float:
	_apply(player, preset)
	var hold := MovementInput.Command.new()
	player.command = hold
	var peak: float = 0.0
	for tick in ticks + 400:
		hold.climb = 1.0 if tick < ticks else 0.0
		player._physics_process(TICK)
		peak = maxf(peak, player.elevation.height)
		if tick > ticks + 30 and player.jump.phase == Jump.STANDING:
			break
	_release(player)
	return peak


## The apex of a fully charged jump on a preset with `overrides` applied on top —
## the same body twice, with one piece of anatomy moved between the runs.
func _peak_with(player: Creature, preset: String, overrides: Dictionary) -> float:
	player.params.apply_preset(preset)
	for key in overrides:
		player.params.set(key, overrides[key])
	player.command = MovementInput.Command.new()
	player.reset(player.head_pos, player.heading)
	player._physics_process(TICK)
	var hold := MovementInput.Command.new()
	player.command = hold
	var window: int = int(ceil((player.leap.charge_time + player.leap.gather_time) / TICK)) + 6
	var peak: float = 0.0
	for tick in window + 400:
		hold.climb = 1.0 if tick < window else 0.0
		player._physics_process(TICK)
		peak = maxf(peak, player.elevation.height)
	_release(player)
	return peak


func _release(player: Creature) -> void:
	player.command = MovementInput.Command.new()
	for _t in 4:
		player._physics_process(TICK)


func _apply(creature: Creature, preset: String) -> void:
	creature.params.apply_preset(preset)
	creature.command = MovementInput.Command.new()
	creature.reset(Vector2.ZERO, 0.0)
	# Long enough for the gait to have stood the body up on four measured feet, so
	# every height compared below is a reading of the legs rather than of the
	# posture's opening guess.
	for _t in 60:
		creature._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("jump OK — the hold is the store and the store is anatomy: %s"
			% " · ".join(notes))
		quit(0)
	else:
		for failure in failures:
			print("JUMP FAIL — ", failure)
		quit(1)
