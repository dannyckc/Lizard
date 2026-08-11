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
## Readings taken across the ticks of one strike — see `_strike_through`.
var _struck_carry: float = 0.0
var _struck_mouth_gap: float = INF
var _struck_neck: float = 0.0
var _struck_drive: float = 0.0


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
	_check_the_neck_never_stretches(player, target)
	_check_the_body_delivers_the_throw(player, target)
	_check_a_hold_lifts_what_it_can(player, target)
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


# ------------------------------------------------------------------- neck ----

## The bone claim, on every build and at every phase of a strike: the distance
## from the skull to the shoulder is never more than the neck the animal has.
##
## It used to be exactly what a lunge was — the head link stretched by the whole
## of `bite_reach`, which on a Cat is a fifth of its own body — and the reach was
## honest about distance while the picture was telling a lie about anatomy. The
## limit lives in Spine.pose_head, so this is a claim about every species at
## once, and it is sampled through the ticks of the strike rather than after it,
## because after it there is nothing to see.
func _check_the_neck_never_stretches(player: Creature, target: Creature) -> void:
	var worst: float = 0.0
	for preset in ["Lizard", "Cat", "Elephant"]:
		_stage(player, target, preset, "Lizard", 0.55)
		player.aim_at(_flank_pick(target, player))
		_settle(player, target, 20)
		_strike_through(player, target)
		worst = maxf(worst, _struck_neck)
		_check(_struck_neck <= 1.0001,
			"a %s stretched its neck to %.3f of its own segment mid-strike"
				% [preset, _struck_neck])
		# ...and it is not stretched by a body being *held*, either, which is the
		# other place the head is placed by something outside the chain.
		player.set_bite_held(true)
		_strike_through(player, target)
		_check(_struck_neck <= 1.0001,
			"a %s holding on stretched its neck to %.3f of its segment"
				% [preset, _struck_neck])
		player.set_bite_held(false)
		_settle(player, target, 20)
	summary.append("neck peaks at %.3f of its length" % worst)


# ------------------------------------------------------------------- body ----

## Where the reach comes from now that the neck cannot supply it: the animal
## moving. The middle of the back — a station nothing but the creature itself can
## displace — genuinely travels forward through the strike, and it travels
## forward again by nothing at all once the strike is over, because a lunge is a
## movement and not a relocation.
##
## And what bounds it is what the body is standing on. `lunge_throw` is the
## species' reach held to its own support, so a creature in mid-air is offered
## the counter-poise and no more — which is the same number the reticle draws and
## the reach test prices the arm off, checked here as one claim rather than three.
func _check_the_body_delivers_the_throw(player: Creature, target: Creature) -> void:
	_stage(player, target, "Cat", "Lizard", 0.55)
	var start: Vector2 = player.head_pos
	player.aim_at(_flank_pick(target, player))
	_settle(player, target, 20)
	_strike_through(player, target)
	_check(_struck_drive > 1.0,
		"a cat's strike never moved its body forward at all (%.1f px at the back)"
			% _struck_drive)
	_check(player.head_pos.distance_to(start) < 4.0,
		"a lunge walked the creature %.1f px across the world"
			% player.head_pos.distance_to(start))
	_check(is_zero_approx(player.lunge_drive.length()),
		"the body was left thrown forward after the strike had finished")

	var standing: float = player.lunge_throw()
	var asked: float = player.params.bite_reach * player.size_scale
	_check(standing > asked * Creature.LUNGE_COUNTERPOISE + 0.001
			and standing <= asked + 0.001,
		"a cat on its feet was offered %.1f of its own %.1f px reach" % [standing, asked])
	player.elevation.leap(80.0, 1.0)
	player._physics_process(TICK)
	_check(player.lunge_throw() < standing,
		"a cat in the air could throw itself as far as one standing on the ground")
	player.elevation.reset()
	player._physics_process(TICK)
	summary.append("body carries %.0f px of the throw" % _struck_drive)


# ------------------------------------------------------------------- lift ----

## The pickup, and it is a weight problem rather than an animation. Jaws that
## have closed on something bring it back toward where the head rides, and how
## far they get is what the forequarter can lift against what is in them — so a
## Cat picks a Lizard up off the floor and the same Cat with an Elephant's leg in
## its mouth stays down there holding it.
##
## Read off the two things that have to agree: the biter's own carry, and the
## height the held body has actually been raised to. One is the neck and the
## other is the animal hanging from it, and a lift that moved one without the
## other would be a head rising off the thing in its mouth.
func _check_a_hold_lifts_what_it_can(player: Creature, target: Creature) -> void:
	var lifted: float = _hold_and_settle(player, target, "Cat", "Lizard")
	_check(lifted > 0.5,
		"a cat with a lizard in its jaws never lifted it off the floor (%.1f px)" % lifted)
	var strained: float = _hold_and_settle(player, target, "Cat", "Elephant")
	_check(strained < lifted * 0.5,
		"a cat lifted an elephant %.1f px, against %.1f px for a lizard"
			% [strained, lifted])
	summary.append("cat lifts a lizard %.0f px, an elephant %.0f" % [lifted, strained])


## Bites and holds on, and answers with how far off its own ground the thing in
## the jaws ended up. Zero when nothing was caught at all, which is a failure of
## the staging rather than of the lift and reads as one.
func _hold_and_settle(player: Creature, target: Creature, biter: String,
		victim: String) -> float:
	_stage(player, target, biter, victim, 0.5)
	# A cat cannot bite an elephant's back, so it goes for a leg — and then it has
	# to actually be standing beside that leg rather than beside the animal.
	_close_on(player, target, _reachable_pick(target, player))
	_settle(player, target, 30)
	player.aim_at(_reachable_pick(target, player))
	_settle(player, target, 20)
	player.set_bite_held(true)
	_strike_through(player, target)
	_settle(player, target, 90)
	var raised: float = 0.0
	if player.grip != null and player.grip.is_alive():
		raised = target.elevation.height
	else:
		_check(false, "a %s never got hold of the %s at all" % [biter, victim])
	player.set_bite_held(false)
	_settle(player, target, 60)
	return raised


# -------------------------------------------------------------- tall on short ----

## An Elephant biting a Lizard at its feet. Three claims in one scenario, and
## they are the shape of the whole interaction.
##
## Pointing at it does nothing whatever: ninety ticks with the cursor on the
## lizard and the elephant is standing exactly as it was. A hover is a question
## about the world, and the answer is drawn rather than performed.
##
## The click is what moves the body. The reach says where the jaws meet; the
## strike has to actually take the head there — the same `carry` number that
## poses the lattice crown and the drawn skull — and arrive within its own
## mouth's thickness of that height, which for an animal this tall means
## addressing the target before the jaws go at all.
##
## And then it comes back up. The head returns toward its perch on the recovery
## without the cursor having to be taken off the target.
func _check_tall_carries_its_head_down_to_short(player: Creature, target: Creature) -> void:
	_stage(player, target, "Elephant", "Lizard", 0.5)
	var pick: Reticle.Pick = _flank_pick(target, player)
	var reach: Reach = Reach.solve(player, pick.at, pick.band, main.terrain)
	_check(reach.possible,
		"an elephant could not reach the lizard at its feet (%s)" % reach.describe())
	var perch: float = player.stature.head_rest
	var stood: float = player.stature.clearance
	player.aim_at(pick)
	_settle(player, target, 90)
	_check(absf(player.stature.carry) < 1.0,
		"an elephant dipped %.1f px toward a target it had only been pointed at"
			% -player.stature.carry)
	_check(absf(player.stature.head_height - perch) < 1.0,
		"the head left its %.1f px perch for %.1f on a hover"
			% [perch, player.stature.head_height])
	_check(player.crouch < 0.02 and absf(player.stature.clearance - stood) < 1.0,
		"an elephant crouched %.0f%% toward a target nobody had clicked on"
			% (player.crouch * 100.0))

	var whole: float = target.anatomy.tissue.integrity()
	_strike_through(player, target)
	# The head has genuinely come off its perch during the strike: the carried
	# height is the stature's answer, so the drawn neck, the crown and the
	# mouth's band have all come down with it — one number, read where it is
	# owned.
	_check(_struck_carry < -1.0,
		"an elephant striking at its feet never carried its head down (deepest %.1f)"
			% _struck_carry)
	_check(_struck_mouth_gap
			< player.body.head_radius + player.gape_radius() * Stature.GAPE_REACH + 1.0,
		"the mouth closed %.1f px from the height the reach promised"
			% _struck_mouth_gap)
	_check(player.bite_connected, "the elephant's strike at the lizard below it missed")
	_check(target.anatomy.tissue.integrity() < whole,
		"a connected downward bite left the lizard whole")
	summary.append("elephant dips %.0f px onto a lizard" % -_struck_carry)
	# Still pointed at it, and still not holding it: the head comes home by
	# itself once the strike is over.
	_settle(player, target, 120)
	_check(player.stature.carry > -2.0,
		"the head never came back to its perch after the strike (carry %.1f)"
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


## The structure of `target` that `biter` should be going for: the flank if it
## can be reached, and otherwise the nearest leg.
##
## A leg is the one thing a low predator can reach on a tall one, which is why a
## scenario pitting a Cat against an Elephant has to ask rather than assume — the
## flank of an elephant is a body-height over a cat's head. The limb pick is built
## exactly as `Reticle` builds one — the plan position on the pick, the hit naming
## the bone — so the aim resolves onto the drawn chain the same way the cursor's
## would.
##
## Nearest rather than reachable, deliberately: the caller walks the animal up to
## whatever comes back, and a pick that refused to name anything out of reach
## would leave it nowhere to walk to.
func _reachable_pick(target: Creature, biter: Creature) -> Reticle.Pick:
	var flank: Reticle.Pick = _flank_pick(target, biter)
	if Reach.solve(biter, flank.at, flank.band, main.terrain).possible:
		return flank
	var best: Reticle.Pick = null
	var best_gap: float = INF
	for limb in target.gait.limbs:
		if limb.severed:
			continue
		for segment in 3:
			var span: int = mini(segment + 1, 2)
			var at: Vector2 = limb.plan[segment].lerp(limb.plan[span], 0.5)
			var band: Vector2 = target.anatomy.tissue.limb_band(limb.key, segment)
			var reach: Reach = Reach.solve(biter, at, band, main.terrain)
			if reach.refusal == "above" or reach.refusal == "below" \
					or reach.distance >= best_gap:
				continue
			best_gap = reach.distance
			var hit := AnatomyState.Hit.new()
			hit.region_id = "limb:%s:%d" % [limb.key, segment]
			hit.kind = AnatomyState.LIMB
			hit.world_point = limb.joints[segment].lerp(limb.joints[span], 0.5)
			hit.limb_key = limb.key
			hit.limb_segment = segment
			hit.limb_u = 1.0 if segment == 2 else 0.5
			best = Reticle.Pick.new()
			best.kind = "creature"
			best.creature = target
			best.hit = hit
			best.at = at
			best.band = band
			best.height = Reach.meeting(biter, band)
	return best if best != null else flank


## Walks `biter` up to something it has decided to bite, from the side it is
## already on, and leaves it standing at half its own arm from it.
func _close_on(biter: Creature, victim: Creature, pick: Reticle.Pick) -> void:
	var approach: Vector2 = biter.head_pos - victim.bounds_center
	approach = approach.normalized() if approach.length_squared() > 1.0 else Vector2.LEFT
	var stand: float = Reach.span_onto(biter, pick.band) * 0.45
	biter.reset(pick.at + approach * stand, (-approach).angle())


func _settle(a: Creature, b: Creature, ticks: int) -> void:
	for _tick in ticks:
		a._physics_process(TICK)
		b._physics_process(TICK)


func _settle_one(a: Creature, ticks: int) -> void:
	for _tick in ticks:
		a._physics_process(TICK)


## Throws one strike and watches the whole of it.
##
## Everything the animation is supposed to do happens inside these ticks and
## nowhere else now, so the readings have to be taken here rather than off the
## body afterwards — by the time the jaws have opened again the head is already
## on its way back to its perch and the evidence has gone.
func _strike_through(player: Creature, target: Creature) -> void:
	_struck_carry = 0.0
	_struck_mouth_gap = INF
	_struck_neck = 0.0
	_struck_drive = 0.0
	var stood: Vector2 = player.spine.points[player.spine.size() / 2]
	var ahead: Vector2 = Vector2.RIGHT.rotated(player.heading)
	player.request_bite(player.jaw_point())
	for _tick in 300:
		player._physics_process(TICK)
		target._physics_process(TICK)
		_struck_carry = minf(_struck_carry, player.stature.carry)
		# The invariant, sampled on every tick of the strike rather than at the
		# end of it: whatever the animation is doing, the distance from the skull
		# to the shoulder is never more than the neck this animal has.
		_struck_neck = maxf(_struck_neck, player.spine.points[0].distance_to(
			player.spine.points[1]) / player.segment_rest())
		# ...and how far the *body* went to deliver it, measured at the middle of
		# the back, where nothing but the animal moving can move it.
		_struck_drive = maxf(_struck_drive,
			(player.spine.points[player.spine.size() / 2] - stood).dot(ahead))
		if player.aim_reach != null and player.aim_reach.possible:
			_struck_mouth_gap = minf(_struck_mouth_gap,
				absf(player.jaw_height() - player.aim_reach.height))
		# Jaws that took hold never reach the end of the animation — the clock
		# stays on the hit frame for as long as the hold lasts, which is the whole
		# point of a hold — so the strike is over when it has either finished or
		# caught something.
		if player.can_bite() or player.is_bite_latched():
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
