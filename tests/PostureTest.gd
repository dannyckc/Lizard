## Headless check for the three stances — see Posture.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/PostureTest.gd
##
## Posture is one trait: the angle the limbs are carried out of the ground plane.
## Everything else about a stance is supposed to *follow* from that, so this is
## written to catch the failure where it silently does not — where the three
## builds are three sets of numbers that happen to differ rather than one
## geometric fact seen from several directions.
##
## The projection first, because the rest is downstream of it. Then the things a
## player would actually see: how far out the feet land, how much of the leg the
## body is standing over, how high the animal is held, how much its spine does of
## the walking, how many feet stay down, and how it turns. Then the two things
## that would be easy to get wrong by taking the projection too literally — an
## upright leg is stout rather than spindly, and every stance has to be able to
## walk at all.
##
## How a limb *travels* rather than how it stands is LocomotionTest's, and so is
## the vertical solve that puts the foot on the floor underneath it.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false
var summary: String = ""


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

	_check_projection()
	_check_trait_is_the_only_difference(player)
	_check_stance_width(player)
	_check_height(player)
	_check_undulation(player)
	_check_support(player)
	_check_turning(player)
	_check_limbs_are_not_spindly(player)
	_check_everything_walks(player)
	_finish()
	return false


# ------------------------------------------------------------- projection ----

## The one fact, and the two projections of it. A limb held flatter shows more of
## itself from above and holds the body lower; one held upright shows less and
## holds it higher. Nothing else in this file would mean anything if these two
## were not exact complements.
func _check_projection() -> void:
	var last_plan: float = INF
	var last_lift: float = -INF
	for kind in Posture.COUNT:
		var p := Posture.new(kind)
		var plan: float = p.plan_reach(100.0)
		var lift: float = p.clearance(100.0)
		_check(plan < last_plan,
			"%s did not draw its feet in further than the stance before it (%.1f)"
				% [p.name(), plan])
		_check(lift > last_lift,
			"%s did not stand higher than the stance before it (%.1f)" % [p.name(), lift])
		_check(absf(plan * plan + lift * lift - 10000.0) < 1.0,
			"%s's reach and clearance are not two views of one leg (%.1f, %.1f)"
				% [p.name(), plan, lift])
		last_plan = plan
		last_lift = lift


## Posture is an anatomical category rather than a tuning group: the same animal
## with the same numbers and a different stance is a different animal. So the
## trait on its own has to move the geometry, with nothing else touched.
func _check_trait_is_the_only_difference(player: Creature) -> void:
	player.params.apply_preset("Lizard")
	player.params.posture = Posture.SPRAWLED
	var flat: Dictionary = _measure(player)
	player.params.posture = Posture.COLUMNAR
	var tall: Dictionary = _measure(player)
	_check(player.params.leg_length == CreatureParams.new().leg_length,
		"changing the stance quietly changed the legs as well")
	_check(tall["clearance"] > flat["clearance"] * 3.0,
		"the same legs held upright did not raise the body (%.1f -> %.1f)"
			% [flat["clearance"], tall["clearance"]])
	_check(tall["track"] < flat["track"],
		"the same legs held upright did not bring the feet in (%.1f -> %.1f)"
			% [flat["track"], tall["track"]])
	player.params.apply_preset("Lizard")


# ------------------------------------------------------------------ stance ----

## Where the feet land, and how much of the leg the torso is standing over.
##
## Two things have to be true at once and they pull against each other: the upper
## limb has to disappear under the body — that is what an upright shoulder *is* —
## while the animal still has to visibly have legs, because a leg you cannot see
## is a leg it does not appear to have.
##
## What resolves them is that they are answered in different views. Seen from
## *above*, an upright animal's feet come inside its own flanks and that is the
## stance working: the legs are under the body because they are pillars under a
## body. Seen on the *screen* they are still clear of it, because the feet are on
## the floor and the floor is drawn below a torso held a leg's length off it. So
## the plan view is asked whether the stance is upright, and the drawn view is
## asked whether you can see it — and the second is exactly the 2.5D projection
## rather than a second stance-width dial.
func _check_stance_width(player: Creature) -> void:
	var lines: Array[String] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		var socket_out: float = 0.0
		var foot_out: float = 0.0
		var drawn_clear: float = -INF
		var flank: float = 0.0
		for limb in player.gait.limbs:
			var a: Spine.Frame = player.body.anchors[limb.key]
			var station: int = player.spine.size() / 4
			var axis: Vector2 = player.spine.points[station]
			var perp: Vector2 = player.spine.perps[station]
			socket_out = maxf(socket_out, absf((a.pos - axis).dot(perp)))
			foot_out = maxf(foot_out, absf((limb.plan[2] - axis).dot(perp)))
			# The drawn body is registered to its own reference plane, so what a
			# foot has to clear on screen is the silhouette at that plane.
			drawn_clear = maxf(drawn_clear,
				(limb.joints[2] - axis).length() - player.body.widths[station])
			flank = maxf(flank, player.body.widths[station])
		_check(drawn_clear > 0.0,
			"%s's feet were drawn inside its own silhouette (%.1f px short of clear)"
				% [preset, -drawn_clear])
		if player.posture.socket_inset > 0.0:
			_check(socket_out < flank,
				"%s's shoulder (%.1f) sat outside the body (%.1f) that is meant to hide it"
					% [preset, socket_out, flank])
		lines.append("%s track %.0f/flank %.0f" % [preset, foot_out, flank])
	# Sprawled feet fall outside the animal and columnar ones underneath it, which
	# is the difference between legs held out to the side and legs held as pillars.
	_apply(player, "Lizard")
	var sprawled: float = _plan_track(player)
	_apply(player, "Elephant")
	var columnar: float = _plan_track(player)
	_check(sprawled > 1.0, "a sprawled animal's feet did not fall outside its own flanks (%.2f)"
		% sprawled)
	_check(columnar < 1.0, "a columnar animal's feet did not fall under its own body (%.2f)"
		% columnar)
	summary = " · ".join(lines)


## How far out the feet stand, seen from above, as a multiple of the flank at the
## same station. Over one is a foot outside the silhouette; under one is a foot
## beneath it.
func _plan_track(player: Creature) -> float:
	var widest: float = 0.0
	for limb in player.gait.limbs:
		var t: float = player.params.front_limb_t if limb.pair == Limb.FRONT \
			else player.params.rear_limb_t
		var station: int = clampi(int(round(t * float(player.spine.size() - 1))),
			0, player.spine.size() - 1)
		var out: float = absf(
			(limb.plan[2] - player.spine.points[station]).dot(player.spine.perps[station]))
		widest = maxf(widest, out / maxf(player.body.widths[station], 0.001))
	return widest


## Clearance, and what it does to the bands. A columnar animal's belly is above a
## sprawled one's whole body — which is the fact the entire vertical layer trades
## on, and it is not written down anywhere: it is legs times an angle.
func _check_height(player: Creature) -> void:
	_apply(player, "Lizard")
	var low: Stature = _copy(player.stature)
	_apply(player, "Elephant")
	var high: Stature = player.stature
	_check(high.clearance > low.torso.y,
		"an Elephant's belly (%.0f) was not above a Lizard's whole body (%.0f)"
			% [high.clearance, low.torso.y])
	_check(low.limbs.x <= 0.001 and high.limbs.x <= 0.001,
		"a leg stopped reaching the ground")
	_check(high.limbs.y > low.limbs.y,
		"a tall animal's legs did not span more height than a low one's")
	_apply(player, "Lizard")


## A sprawled animal lengthens its stride by throwing its spine side to side; an
## upright one has taken that job back into the legs. So undulation is a property
## of the stance rather than of the species, and the two upright builds have to be
## visibly quieter through the body.
func _check_undulation(player: Creature) -> void:
	var sway: Array[float] = []
	for preset in ["Lizard", "Cat", "Elephant"]:
		sway.append(_sway(player, preset))
	_check(sway[0] > sway[1] * 2.0,
		"a sprawled body did not undulate more than a semi-upright one (%.1f vs %.1f)"
			% [sway[0], sway[1]])
	_check(sway[1] > sway[2],
		"a semi-upright body did not undulate more than a columnar one (%.1f vs %.1f)"
			% [sway[1], sway[2]])
	_check(sway[2] < 2.0, "a columnar body still wagged %.1f px through the spine" % sway[2])


## How much of the body a walking creature swings sideways, measured off the
## midpoint of the spine against the line the head is travelling along.
func _sway(player: Creature, preset: String) -> float:
	_apply(player, preset)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	var mid: int = player.spine.size() / 2
	var lo: float = INF
	var hi: float = -INF
	for tick in 240:
		player.command = drive
		player._physics_process(TICK)
		if tick < 60:
			continue
		# How far the middle of the back sits off the line the head is travelling
		# along, rather than off the world's y axis. Undulation is a body bending
		# against itself, and measured absolutely it cannot be told apart from a
		# body being shoved sideways — which is what the fastest of the three does
		# when it catches up with the other animal in the habitat.
		var across: Vector2 = Vector2(-player.move_dir.y, player.move_dir.x)
		var offset: float = (player.spine.points[mid] - player.head_pos).dot(across)
		lo = minf(lo, offset)
		hi = maxf(hi, offset)
	player.command = MovementInput.Command.new()
	return hi - lo


## Weight support, which is no longer the posture's to decide — and this check is
## here to say so.
##
## It used to be. `feet_down` was a hard ceiling on how many feet could be off the
## ground, so a stance chose once and for all between an amble and a trot, and the
## same creature moved identically at every speed it had. That is most of why every
## build in the game read as a scaled lizard, and it is now Footfall's answer:
## whether a body may be caught mid-fall is a question about how fast it is going
## *for its size*, and whether it can throw itself clear of the ground at all is a
## question about its legs, its back and whether it can leap.
##
## So the claim reverses. One creature, two speeds, and the number has to change;
## and a build that cannot leave the ground may not reach a suspension however
## fast it is driven.
func _check_support(player: Creature) -> void:
	var strolling: int = _max_feet_up(player, "Cat", 0.3)
	var running: int = _max_feet_up(player, "Cat", 1.0)
	_check(strolling < running,
		"a Cat lifted as many feet strolling as it did at a flat run (%d, %d) — the gait is not changing with speed"
			% [strolling, running])
	_check(strolling <= 2,
		"a strolling Cat had %d feet off the ground at once" % strolling)

	# The Elephant is the control, and the whole of why is that it cannot leave the
	# ground: an animal with no way to push itself off the floor has no asymmetric
	# gait to reach, so speed buys it nothing but a quicker amble. Nothing forbids
	# it — there is no rule about columnar builds anywhere in the solver, and no
	# leap parameter to have written a zero into either. Its joints do not fold, so
	# there is nowhere to push from; see Leap.
	_check(_max_feet_up(player, "Elephant", 1.0) == 1,
		"an Elephant lifted more than one foot at a time — it is trotting, not ambling")


func _max_feet_up(player: Creature, preset: String, throttle: float) -> int:
	_apply(player, preset)
	var drive := MovementInput.Command.new()
	drive.throttle = throttle
	drive.sprint = throttle > 0.9
	var worst: int = 0
	for tick in 420:
		player.command = drive
		player._physics_process(TICK)
		if tick < 120:
			continue
		var up: int = 0
		for limb in player.gait.limbs:
			if limb.stepping:
				up += 1
		worst = maxi(worst, up)
	player.command = MovementInput.Command.new()
	return worst


## Turning. A semi-upright build turns flat and a columnar one carves, and both
## come off the same `agility` term rather than off either species having been
## given a different turn rate for the purpose.
func _check_turning(player: Creature) -> void:
	var quick: float = _turn_radius(player, "Cat")
	var heavy: float = _turn_radius(player, "Elephant")
	_check(heavy > quick * 2.0,
		"a columnar animal did not carve a wider circle than a semi-upright one (%.0f vs %.0f px)"
			% [heavy, quick])
	# ...and a wide turn has to still be a turn. A radius past the horizon is a
	# creature that cannot change direction rather than one that changes it slowly.
	_check(heavy < 4000.0, "a columnar animal's turn radius came out at %.0f px" % heavy)


## Radius of the arc a creature at speed actually carves: how fast it is going
## against how fast it is coming round.
func _turn_radius(player: Creature, preset: String) -> float:
	_apply(player, preset)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.turn = 1.0
	for _tick in 240:
		player.command = drive
		player._physics_process(TICK)
	var radius: float = absf(player.speed) / maxf(absf(player.ang_vel), 0.0001)
	player.command = MovementInput.Command.new()
	return radius


## The projection is about where a limb *reaches*, not about how much limb there
## is. Taking it literally everywhere would draw a columnar animal on four
## spindles, so thickness is priced off the bone instead — and the check is that
## two identical legs held at different angles are equally thick.
func _check_limbs_are_not_spindly(player: Creature) -> void:
	player.params.apply_preset("Lizard")
	player.params.posture = Posture.SPRAWLED
	var flat: Dictionary = _measure(player)
	player.params.posture = Posture.COLUMNAR
	var tall: Dictionary = _measure(player)
	_check(is_equal_approx(flat["girth"], tall["girth"]),
		"the same leg held upright came out %.2f px thick instead of %.2f"
			% [tall["girth"], flat["girth"]])
	_check(is_equal_approx(flat["bone"], tall["bone"]),
		"the same leg held upright changed length (%.1f -> %.1f)"
			% [flat["bone"], tall["bone"]])
	_check(tall["chain"] < flat["chain"],
		"the upright leg was solved at its full length rather than its projection")
	player.params.apply_preset("Lizard")


## Whatever the stance, the animal has to walk. A projected limb has a much
## smaller working envelope than the bone it came from, and a stride authored
## against the bone is one the foot can never reach — so this is the check that
## the envelope cap is doing its job for every build in the file.
func _check_everything_walks(player: Creature) -> void:
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_apply(player, name)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		var steps: int = 0
		var travelled: Vector2 = player.head_pos
		for _tick in 600:
			player.command = drive
			player._physics_process(TICK)
			for limb in player.gait.limbs:
				if limb.stepping and limb.step_t <= TICK / maxf(limb.step_duration, 0.001):
					steps += 1
		player.command = MovementInput.Command.new()
		_check(steps > 20,
			"a walking %s took %d steps in ten seconds" % [name, steps])
		_check(travelled.distance_to(player.head_pos) > 200.0,
			"a walking %s covered %.0f px in ten seconds"
				% [name, travelled.distance_to(player.head_pos)])


# ------------------------------------------------------------------ tools ----

## The handful of geometric facts about the creature as it currently stands.
func _measure(player: Creature) -> Dictionary:
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)
	var limb: Limb = player.gait.limbs[0]
	var station: int = player.spine.size() / 4
	var axis: Vector2 = player.spine.points[station]
	var perp: Vector2 = player.spine.perps[station]
	return {
		"clearance": player.stature.clearance,
		"track": absf((limb.joints[2] - axis).dot(perp)),
		"girth": limb.girth(player.size_scale),
		"bone": limb.anatomical_length,
		"chain": limb.total_length,
	}


## Stature is refreshed in place every tick, so anything held across a species
## change has to be a copy of the numbers rather than the object.
func _copy(s: Stature) -> Stature:
	var out := Stature.new()
	out.clearance = s.clearance
	out.depth = s.depth
	out.reference = s.reference
	out.torso = s.torso
	out.head = s.head
	out.limbs = s.limbs
	out.whole = s.whole
	out.bite = s.bite
	return out


func _apply(player: Creature, preset: String) -> void:
	player.set_bite_held(false)
	player.params.apply_preset(preset)
	player.command = MovementInput.Command.new()
	player.reset(Vector2.ZERO, 0.0)
	player._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("posture OK — one angle, and the stance follows: %s" % summary)
		quit(0)
	else:
		for failure in failures:
			print("POSTURE FAIL — ", failure)
		quit(1)
