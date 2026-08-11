## Headless check for the bite being a three-dimensional interaction — see
## Reach, Stature (the head carry and the neck's arc), Creature.mouth_band and
## the mark's band in Creature.bite_mark.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/BiteReachTest.gd
##
## The claim under test is one sentence: the targeting, the movement that
## answers it, the contact test and the damage all quote the same 3D point.
## A mouth is somewhere — a plan position *and* a height — and a strike
## connects with what that mouth actually arrived at, not with everything the
## animal's whole envelope could have reached instead. Everything below is that
## sentence read from a different chair:
##
##   * two level peers meet at flank height, and the mark that lands carries
##     the mouth's own band rather than the whole column;
##   * a tall animal biting something at its feet carries its head down to it —
##     the same `head_carry` number moves the lattice crown, the drawn head and
##     the mouth's hit band, so the check reads the *stature*, not a sprite;
##   * a short animal pointed at a back it cannot reach never chases it: the
##     head stays on its perch, the lunge is thrown level, and the back is not
##     asked;
##   * the neck is an arc, so height and distance are one purse: the same
##     horizontal gap is reachable at the mouth's own level and refused onto
##     the floor, and the boundary either side of the arm is exact;
##   * a bite at empty ground connects with nothing and harms nobody;
##   * a moving target is re-solved every tick, so the strike lands on where
##     the flesh is rather than where it was aimed.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false
var summary: Array[String] = []
var _last_mark: BiteMark = null


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var player: Creature = main.creature
	var target: Creature = main.target_creature
	_check(player != null and target != null, "the habitat did not build its bodies")
	if player == null or target == null:
		_finish()
		return false
	target.alive = true
	player.bite_started.connect(_capture_mark)

	_check_level_peers_meet_at_flank_height(player, target)
	_check_tall_carries_its_head_down_to_short(player, target)
	_check_short_never_chases_a_back_it_cannot_reach(player, target)
	_check_the_arm_is_one_purse_across_both_axes(player, target)
	_check_a_bite_at_nothing_lands_on_nothing(player, target)
	_check_a_moving_target_is_met_where_it_is(player, target)
	_check_the_carry_never_leaves_the_envelope(player)
	_finish()
	return false


# ------------------------------------------------------------------- peers ----

## Two similar animals on level ground: the ordinary case, and the one that has
## to stay ordinary. The strike connects, and the mark it lands with carries the
## mouth's own band — a thickness about the head, not the whole envelope — so
## the cells that erode are the cells at the height the jaws closed at.
func _check_level_peers_meet_at_flank_height(player: Creature, target: Creature) -> void:
	_stage(player, target, "Lizard", "Lizard", 0.55)
	var pick: Reticle.Pick = _flank_pick(target, player)
	var reach: Reach = Reach.solve(player, pick.at, pick.band, main.terrain)
	_check(reach.possible,
		"a lizard could not reach the flank of the lizard beside it (%s)" % reach.describe())
	player.aim_at(pick)
	_settle(player, target, 30)
	var whole: float = target.anatomy.tissue.integrity()
	_strike_through(player, target)
	_check(player.bite_connected, "a level strike at a peer's flank landed on nothing")
	_check(target.anatomy.tissue.integrity() < whole,
		"a connected bite left the flank whole")
	_check(_last_mark != null and _last_mark.reach != Stature.UNBOUNDED
			and _last_mark.reach.y - _last_mark.reach.x
				< player.stature.bite.y - player.stature.bite.x,
		"an aimed strike stamped its whole envelope on the mark rather than its mouth")
	_check(_last_mark != null and Volume.contains(_last_mark.reach, _last_mark.height),
		"the mark's drawn height %.1f sat outside the band its jaws occupied %s"
			% [_last_mark.height, Volume.describe(_last_mark.reach if _last_mark != null else Vector2.ZERO)])
	summary.append("peers meet at %.0f px" % _last_mark.height)


# -------------------------------------------------------------- tall on short ----

## An Elephant biting a Lizard at its feet. The reach says where the jaws meet;
## the carry has to actually take the head there — the same number that poses
## the lattice crown and the drawn skull — and the strike has to arrive within
## its own mouth's thickness of that height. This is the acceptance claim that
## the animation and the contact test are one system.
func _check_tall_carries_its_head_down_to_short(player: Creature, target: Creature) -> void:
	_stage(player, target, "Elephant", "Lizard", 0.5)
	var pick: Reticle.Pick = _flank_pick(target, player)
	var reach: Reach = Reach.solve(player, pick.at, pick.band, main.terrain)
	_check(reach.possible,
		"an elephant could not reach the lizard at its feet (%s)" % reach.describe())
	var perch: float = player.stature.head_rest
	player.aim_at(pick)
	_settle(player, target, 90)
	# The head has genuinely come off its perch: the carried height is the
	# stature's answer, so the drawn neck, the crown and the mouth's band have
	# all come down with it — one number, read where it is owned.
	_check(player.stature.carry < -1.0,
		"an elephant reaching for its feet never carried its head down (carry %.1f)"
			% player.stature.carry)
	_check(player.stature.head_height < perch - 1.0,
		"the carried head height %.1f never left its %.1f px perch"
			% [player.stature.head_height, perch])
	reach = Reach.solve(player, pick.at, pick.band, main.terrain)
	_check(absf(player.jaw_height() - reach.height)
			< player.body.head_radius + player.gape_radius() * Stature.GAPE_REACH + 1.0,
		"the mouth settled %.1f px from the height the reach promised (%.1f vs %.1f)"
			% [absf(player.jaw_height() - reach.height), player.jaw_height(), reach.height])
	var whole: float = target.anatomy.tissue.integrity()
	_strike_through(player, target)
	_check(player.bite_connected, "the elephant's strike at the lizard below it missed")
	_check(target.anatomy.tissue.integrity() < whole,
		"a connected downward bite left the lizard whole")
	summary.append("elephant dips %.0f px onto a lizard" % -player.stature.carry)
	player.aim_at(null)
	_settle(player, target, 90)
	_check(player.stature.carry > -2.0,
		"the head never came back to its perch after the target was dropped (carry %.1f)"
			% player.stature.carry)


# -------------------------------------------------------------- short on tall ----

## A Lizard pointed at an Elephant's back. The refusal is vertical, the body
## does not mime the reach it was refused, and the neutral strike — thrown, as
## every strike is — carries the mouth's own band, so the back a body-length
## overhead is never so much as asked.
func _check_short_never_chases_a_back_it_cannot_reach(player: Creature, target: Creature) -> void:
	_stage(player, target, "Lizard", "Elephant", 0.5)
	var over: float = 0.5
	var high := Reticle.Pick.new()
	high.at = target.spine.sample(over).pos
	high.band = target.anatomy.tissue.body_band(over)
	var up: Reach = Reach.solve(player, high.at, high.band, main.terrain)
	_check(not up.possible and up.refusal == "above",
		"a lizard under an elephant was told %s about its back" % up.describe())
	player.aim_at(high)
	_settle(player, target, 40)
	_check(absf(player.stature.carry) < 2.0,
		"a lizard strained %.1f px toward a back it cannot reach" % player.stature.carry)
	var back_before: float = target.anatomy.tissue.body_solid(over, 0.0)
	_strike_through(player, target)
	_check(_last_mark != null and _last_mark.reach != Stature.UNBOUNDED
			and _last_mark.reach.y < high.band.x,
		"a level snap's jaws reached %s against a back at %s"
			% [Volume.describe(_last_mark.reach if _last_mark != null else Vector2.ZERO),
				Volume.describe(high.band)])
	_check(is_equal_approx(target.anatomy.tissue.body_solid(over, 0.0), back_before),
		"a strike thrown from the floor reached an elephant's back")
	summary.append("lizard leaves the back alone")


# ---------------------------------------------------------------- one purse ----

## Height and distance are one budget, exchanged along the neck's arc. The same
## horizontal gap that is comfortably inside the arm at the mouth's own level is
## refused onto the floor, and either side of the arm the answer flips exactly —
## the acceptance test's "just inside and just outside anatomical reach", with
## the boundary computed rather than guessed.
func _check_the_arm_is_one_purse_across_both_axes(player: Creature, target: Creature) -> void:
	_stage(player, target, "Cat", "Lizard", 8000.0)
	player.aim_at(null)
	_settle(player, target, 20)
	var mouth: Vector2 = player.jaw_rest_point()
	var level := Volume.span(player.jaw_rest_height(), 4.0)
	var floor_band := Volume.ground()
	var level_arm: float = Reach.span_onto(player, level)
	var floor_arm: float = Reach.span_onto(player, floor_band)
	_check(floor_arm < level_arm - 1.0,
		"sweeping a cat's mouth to the floor cost it nothing off its arm (%.1f vs %.1f)"
			% [floor_arm, level_arm])

	var ahead: Vector2 = Vector2.RIGHT.rotated(player.heading)
	# Just inside and just outside, at both heights. The margin is two pixels on
	# arms tens of pixels long, so the boundary being tested is the arithmetic
	# rather than the slack around it.
	for probe in [[level, level_arm], [floor_band, floor_arm]]:
		var band: Vector2 = probe[0]
		var arm: float = probe[1]
		var inside: Reach = Reach.solve(player, mouth + ahead * (arm - 2.0), band, main.terrain)
		_check(inside.possible,
			"a target 2 px inside the %.1f px arm was refused (%s)" % [arm, inside.describe()])
		var outside: Reach = Reach.solve(player, mouth + ahead * (arm + 2.0), band, main.terrain)
		_check(not outside.possible and outside.refusal == "too far",
			"a target 2 px past the %.1f px arm was allowed (%s)" % [arm, outside.describe()])
	# ...and the cross claim, which is the whole point: the distance the level
	# mouth covers with room to spare is past the arm once the target is on the
	# floor.
	var diagonal: Reach = Reach.solve(player,
		mouth + ahead * (level_arm - 2.0), floor_band, main.terrain)
	_check(not diagonal.possible and diagonal.refusal == "too far",
		"the same gap that is reachable level was also granted onto the floor (%s)"
			% diagonal.describe())
	summary.append("cat's arm %.0f level, %.0f onto the floor" % [level_arm, floor_arm])


# -------------------------------------------------------------- empty space ----

## A bite aimed at bare ground: the whole interaction runs — the head dips, the
## lunge is thrown, the mark lands — and nothing whatever is harmed by it.
func _check_a_bite_at_nothing_lands_on_nothing(player: Creature, target: Creature) -> void:
	_stage(player, target, "Lizard", "Lizard", 3.0)
	var whole_target: float = target.anatomy.tissue.integrity()
	var patch := Reticle.Pick.new()
	patch.at = player.jaw_point() + Vector2.RIGHT.rotated(player.heading) * 12.0
	patch.band = Volume.ground()
	player.aim_at(patch)
	_settle(player, target, 30)
	_strike_through(player, target)
	_check(not player.bite_connected, "a bite at bare ground reported a connection")
	_check(is_equal_approx(target.anatomy.tissue.integrity(), whole_target),
		"a bite at bare ground damaged the animal standing a body away")
	summary.append("empty ground bitten cleanly")


# ------------------------------------------------------------- moving target ----

## The reach is re-solved and the carry re-eased every tick, so a strike thrown
## at a walking animal closes on where its flank is when the jaws arrive.
func _check_a_moving_target_is_met_where_it_is(player: Creature, target: Creature) -> void:
	_stage(player, target, "Cat", "Lizard", 0.6)
	# A pursuit: the lizard walks off and the cat runs it down, re-aiming at the
	# live flank every tick — exactly what the habitat's cursor resolution does —
	# and the strike is thrown while both bodies are genuinely moving.
	var flee := MovementInput.Command.new()
	flee.throttle = 0.5
	var chase := MovementInput.Command.new()
	chase.throttle = 1.0
	var whole: float = target.anatomy.tissue.integrity()
	var connected: bool = false
	var thrown: bool = false
	# Struck whenever the jaws are ready and the flank is inside half the arm —
	# repeatedly, because that is what the button is: a strike sized to a target
	# that then flees lands short, and the answer is the next strike, thrown at
	# where the flank now is. What is being tested is that the re-solved aim
	# keeps up with the moving flesh, not that one throw can see the future.
	for _tick in 300:
		target.command = flee
		player.command = chase
		var pick: Reticle.Pick = _flank_pick(target, player)
		player.aim_at(pick)
		if player.can_bite():
			var r: Reach = Reach.solve(player, pick.at, pick.band, main.terrain)
			if r.possible and r.distance < Reach.span_onto(player, pick.band) * 0.5 \
					and absf(target.speed) > 10.0:
				thrown = true
				player.request_bite(pick.at)
		player._physics_process(TICK)
		target._physics_process(TICK)
		connected = connected or player.bite_connected
		if connected:
			break
	player.command = MovementInput.Command.new()
	target.command = MovementInput.Command.new()
	_check(thrown, "the cat never ran the walking lizard down to strike at all")
	_check(connected, "a strike at a walking target never connected")
	_check(target.anatomy.tissue.integrity() < whole,
		"a connected strike at a walking target left it whole")
	summary.append("walking lizard bitten mid-stride")


# ----------------------------------------------------------------- envelope ----

## However hard the carry is driven, the head can never be carried outside the
## envelope the neck and the legs add up to — on any build. The clamp lives in
## Stature, so this is a claim about every species at once, including ones with
## very different necks.
func _check_the_carry_never_leaves_the_envelope(player: Creature) -> void:
	for preset in ["Lizard", "Cat", "Elephant"]:
		_apply(player, preset)
		_settle_one(player, 20)
		_check(player.stature.neck_arc > 0.0,
			"a %s has no neck arc at all" % preset)
		for ask in [10000.0, -10000.0]:
			player.head_carry = ask
			player._physics_process(TICK)
			var head: float = player.stature.head_height
			_check(head <= player.stature.bite.y + 0.5,
				"a %s carried its head to %.1f, past its own %.1f px envelope"
					% [preset, head, player.stature.bite.y])
			_check(head >= player.stature.bite.x + player.stature.fold - 0.5,
				"a %s carried its head to %.1f, below the %.1f its neck can reach unaided"
					% [preset, head, player.stature.bite.x + player.stature.fold])
		player.head_carry = 0.0
		player._physics_process(TICK)
	summary.append("carry clamped on all three builds")


# ------------------------------------------------------------------- tools ----

## Puts `biter` (as `biter_preset`) squarely behind `victim` (as
## `victim_preset`), facing it, at `gap` of the biter's own level arm from the
## victim's near flank — so every scenario is staged in the animal's own units
## and works on any pair of builds. A `gap` in the thousands parks the victim
## out of the way instead.
func _stage(biter: Creature, victim: Creature, biter_preset: String,
		victim_preset: String, gap: float) -> void:
	main.terrain.clear()
	_apply(biter, biter_preset)
	_apply(victim, victim_preset)
	if gap > 100.0:
		victim.reset(Vector2(0.0, 8000.0), 0.0)
		biter.reset(Vector2.ZERO, 0.0)
		_settle(biter, victim, 20)
		return
	victim.reset(Vector2.ZERO, 0.0)
	biter.reset(Vector2.ZERO, 0.0)
	_settle(biter, victim, 10)
	var stand_off: float = victim.bounds_radius + Reach.span(biter) * gap \
		+ biter.body.head_radius
	biter.reset(victim.bounds_center + Vector2(-stand_off, 0.0), 0.0)
	_settle(biter, victim, 30)
	# The stand-off is a guess in the biter's own units, and every claim below is
	# about what happens comfortably *within* reach — the exact boundary has its
	# own check — so walk in until the flank sits at under half the arm the
	# reach itself quotes onto that band.
	var pick: Reticle.Pick = _flank_pick(victim, biter)
	var r: Reach = Reach.solve(biter, pick.at, pick.band, main.terrain)
	var pull_in: float = r.distance - Reach.span_onto(biter, pick.band) * 0.45
	if gap <= 1.0 and pull_in > 0.0:
		biter.reset(biter.head_pos + Vector2(pull_in, 0.0), 0.0)
		_settle(biter, victim, 20)


## The near flank of `target`, picked the way the cursor's resolver would offer
## it: the surface facing the biter, at the station nearest its mouth, with the
## band the tissue there actually occupies.
func _flank_pick(target: Creature, biter: Creature) -> Reticle.Pick:
	var mouth: Vector2 = biter.jaw_point()
	var best_t: float = 0.5
	var best_d: float = INF
	for k in 21:
		var t: float = float(k) / 20.0
		var d: float = target.spine.sample(t).pos.distance_to(mouth)
		if d < best_d:
			best_d = d
			best_t = t
	var frame: Spine.Frame = target.spine.sample(best_t)
	var side: float = signf((mouth - frame.pos).dot(frame.perp))
	var pick := Reticle.Pick.new()
	pick.kind = "creature"
	pick.creature = target
	pick.at = target.body_point(Vector2(best_t, side if not is_zero_approx(side) else 1.0))
	pick.band = target.anatomy.tissue.body_band(best_t)
	pick.height = clampf(biter.jaw_rest_height(), pick.band.x, pick.band.y)
	return pick


func _settle(a: Creature, b: Creature, ticks: int) -> void:
	for _tick in ticks:
		a._physics_process(TICK)
		b._physics_process(TICK)


func _settle_one(a: Creature, ticks: int) -> void:
	for _tick in ticks:
		a._physics_process(TICK)


func _strike_through(player: Creature, target: Creature) -> void:
	player.request_bite(player.jaw_point())
	for _tick in 300:
		player._physics_process(TICK)
		target._physics_process(TICK)
		if player.can_bite():
			return
	_check(false, "a strike never finished: the animal is still mid-lunge")


func _apply(creature: Creature, preset: String) -> void:
	creature.set_bite_held(false)
	creature.aim_at(null)
	creature.params.apply_preset(preset)
	creature.command = MovementInput.Command.new()
	creature.elevation.reset()
	creature.reset(creature.head_pos, creature.heading)
	creature._physics_process(TICK)


func _capture_mark(mark: BiteMark) -> void:
	_last_mark = mark


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("bite reach OK — one 3D contact point for targeting, movement, contact and damage: %s"
			% " · ".join(summary))
		quit(0)
	else:
		for failure in failures:
			print("BITE REACH FAIL — %s" % failure)
		quit(1)
