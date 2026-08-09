## Focused behavioural checks for locomotion feel.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/MovementFeelTest.gd
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var checked: bool = false


func _initialize() -> void:
	# SceneTree's root is not fully ready here; assertions run on the first frame.
	pass


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	_check_reverse_keeps_facing()
	_check_reverse_is_slower_than_forward()
	_check_reverse_turn_stays_wider_than_the_body()
	_check_turn_response()
	_check_turn_switch_answers_promptly()
	_check_turn_switch_stays_put()
	_check_moving_turn_has_no_extra_sweep()
	_check_strike_leaves_the_body_alone()

	if failures.is_empty():
		print("movement feel OK — reverse keeps facing, turns start at the front, strikes throw only the head")
		quit(0)
	else:
		for failure in failures:
			print("MOVEMENT FAIL — ", failure)
		quit(1)
	return false


func _check_reverse_keeps_facing() -> void:
	var creature := _spawn_creature()
	var facing := Vector2.RIGHT.rotated(creature.heading)
	var start_head: Vector2 = creature.head_pos
	var start_tail: Vector2 = creature.spine.points[creature.spine.size() - 1]
	var reverse := MovementInput.Command.new()
	reverse.throttle = -1.0

	# Three seconds rather than two. Backing up is a fraction of a walking speed
	# that is itself now the pace the legs can be cycled at — see
	# Locomotion.leg_speed — so the same hundred pixels of retreat takes longer to
	# cover. The claim is that the whole animal goes backwards facing forwards.
	for _tick in 180:
		creature.command = reverse
		creature._physics_process(TICK)

	var head_travel: Vector2 = creature.head_pos - start_head
	var tail_travel: Vector2 = creature.spine.points[creature.spine.size() - 1] - start_tail
	var torso_facing: Vector2 = creature.spine.forwards[1]
	_check(absf(wrapf(creature.heading, -PI, PI)) < 0.0001,
		"reverse changed the commanded heading by %.2f degrees" % rad_to_deg(creature.heading))
	_check(head_travel.dot(facing) < -100.0,
		"reverse moved the control anchor only %.1f px backward" % -head_travel.dot(facing))
	_check(tail_travel.dot(facing) < -80.0,
		"reverse left the body behind (tail moved only %.1f px backward)" % -tail_travel.dot(facing))
	_check(torso_facing.dot(facing) > 0.70,
		"reverse folded the torso away from its facing (dot %.2f)" % torso_facing.dot(facing))
	_check(absf(head_travel.dot(Vector2(-facing.y, facing.x))) < 2.0,
		"straight reverse drifted %.1f px sideways" % absf(head_travel.y))
	_destroy_creature(creature)


## Backing up is a deliberate retreat, not a mirrored walk: it settles well
## under forward speed, and holding sprint must not buy any of the gap back.
func _check_reverse_is_slower_than_forward() -> void:
	var creature := _spawn_creature()
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.sprint = true
	for _tick in 90:
		creature.command = drive
		creature._physics_process(TICK)
	var forward_speed: float = absf(creature.speed)

	drive.throttle = -1.0
	for _tick in 120:
		creature.command = drive
		creature._physics_process(TICK)
	var reverse_speed: float = absf(creature.speed)
	var reverse_cap: float = creature.params.move_speed * creature.params.reverse_speed_factor

	_check(reverse_speed < forward_speed * 0.7,
		"reverse reached %.0f px/s against %.0f forward" % [reverse_speed, forward_speed])
	_check(reverse_speed <= reverse_cap + 0.5,
		"sprinting in reverse exceeded the walk-speed fraction (%.0f > %.0f px/s)" % [
			reverse_speed, reverse_cap])
	_destroy_creature(creature)


## Backing up and steering at the same time has to describe an arc the body can
## follow. Turning about the head instead swings the whole length around the
## nose: the head carves a circle several times tighter than the creature is
## long and the spine coils into it, which is neither backing up nor turning.
func _check_reverse_turn_stays_wider_than_the_body() -> void:
	var creature := _spawn_creature()
	var reverse := MovementInput.Command.new()
	reverse.throttle = -1.0
	reverse.turn = 1.0
	for _tick in 180:
		creature.command = reverse
		creature._physics_process(TICK)

	var arc: float = creature.spine.arc_length()
	var span: float = creature.head_pos.distance_to(
		creature.spine.points[creature.spine.size() - 1])
	var reverse_rate: float = deg_to_rad(creature.params.turn_speed_deg) \
		* creature.params.reverse_speed_factor
	_check(span > arc * 0.85,
		"three seconds of reversing into a turn coiled the body (%.0f px across %.0f of spine)"
			% [span, arc])
	_check(absf(creature.ang_vel) <= reverse_rate + 0.01,
		"reverse steered at %.0f deg/s, its own forward rate rather than a backing one"
			% rad_to_deg(absf(creature.ang_vel)))
	_destroy_creature(creature)


func _check_turn_response() -> void:
	var creature := _spawn_creature()
	var turn := MovementInput.Command.new()
	turn.turn = 1.0
	var start: Vector2 = creature.head_pos

	for _tick in 6:
		creature.command = turn
		creature._physics_process(TICK)

	# Four degrees in a tenth of a second, not eight. A standing turn is walked —
	# the feet have to be picked up and put down round the arc, and there are only
	# so many steps a second in a leg of a given length, see Locomotion.walked_turn
	# — so the reference build comes round at about ninety degrees a second where
	# it used to manage a hundred and ninety unbounded. What this still pins is
	# that the control answers immediately and eases in rather than snapping.
	var six_tick_turn: float = rad_to_deg(absf(creature.heading))
	_check(six_tick_turn >= 4.0,
		"turn input changed heading only %.1f degrees in 100 ms" % six_tick_turn)

	turn.turn = -1.0
	for _tick in 12:
		creature.command = turn
		creature._physics_process(TICK)
	_check(creature.ang_vel < 0.0,
		"opposite turn input had not reversed angular velocity after 200 ms")
	_check(start.distance_to(creature.head_pos) < creature.params.turn_pivot * 1.25,
		"a brief direction change repositioned the head by %.1f px" % start.distance_to(creature.head_pos))
	_destroy_creature(creature)


## Switching A to D must not carry the old swing for a readable beat: the
## angular velocity has to cross zero within a few ticks of the command flip.
func _check_turn_switch_answers_promptly() -> void:
	var creature := _spawn_creature()
	var turn := MovementInput.Command.new()
	turn.turn = -1.0
	for _tick in 30:
		creature.command = turn
		creature._physics_process(TICK)
	_check(creature.ang_vel < 0.0, "held left turn did not build angular velocity")

	turn.turn = 1.0
	var ticks_to_cross: int = -1
	for tick in 12:
		creature.command = turn
		creature._physics_process(TICK)
		if creature.ang_vel > 0.0:
			ticks_to_cross = tick + 1
			break
	_check(ticks_to_cross >= 1 and ticks_to_cross <= 3,
		"A->D switch carried the old swing for %d ticks" % ticks_to_cross)
	_destroy_creature(creature)


## A standing creature that turns one way and then the other has to end up where
## it started. It is the front of the body that changes direction — the head and
## neck swing about a station on the spine and the rest follows — so the swing
## must not turn into the whole creature shuffling sideways across the ground,
## which is what a pivot pinned to the head produces.
func _check_turn_switch_stays_put() -> void:
	var creature := _spawn_creature()
	var turn := MovementInput.Command.new()
	turn.turn = -1.0
	for _tick in 90:
		creature.command = turn
		creature._physics_process(TICK)

	var mid: int = creature.spine.size() / 2
	var facing: float = creature.spine.forwards[mid].angle()
	var swept: float = 0.0
	var start: Vector2 = _spine_centre(creature)
	turn.turn = 1.0
	for _tick in 30:
		creature.command = turn
		creature._physics_process(TICK)
		var now: float = creature.spine.forwards[mid].angle()
		swept += absf(wrapf(now - facing, -PI, PI))
		facing = now

	_check(start.distance_to(_spine_centre(creature)) < 30.0,
		"switching a standing turn walked the body %.1f px across the ground"
			% start.distance_to(_spine_centre(creature)))
	# Twenty degrees in half a second, at the walked turn rate above. The point of
	# the check is that the *body* comes round rather than the head alone, so it is
	# the sweep of a mid-spine station that is measured; the figure moved with the
	# turn rate and the claim did not.
	_check(rad_to_deg(swept) > 20.0,
		"the body only came round %.1f degrees in half a second of standing turn"
			% rad_to_deg(swept))
	_destroy_creature(creature)


## At walking speed, heading plus linear travel already describes the complete
## arc. A turn pivot left active here appears as a second sideways correction.
func _check_moving_turn_has_no_extra_sweep() -> void:
	var creature := _spawn_creature()
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _tick in 90:
		creature.command = drive
		creature._physics_process(TICK)

	drive.turn = 1.0
	var unexplained: Vector2 = Vector2.ZERO
	for _tick in 12:
		var before: Vector2 = creature.head_pos
		creature.command = drive
		creature._physics_process(TICK)
		var linear: Vector2 = creature.move_dir * (creature.speed * TICK)
		unexplained += (creature.head_pos - before) - linear

	_check(unexplained.length() < 0.5,
		"a moving turn added %.2f px of pivot repositioning" % unexplained.length())
	_destroy_creature(creature)


## A strike throws the head, not the creature. The reach is the neck extending
## past the body, so a bite aimed hard across the cursor must leave the torso
## exactly where it was standing — it may not haul the spine round after the
## mouse, which is what feeding the throw to the body solver did.
func _check_strike_leaves_the_body_alone() -> void:
	var creature := _spawn_creature()
	var aim := MovementInput.Command.new()
	aim.aim_active = true
	aim.aim_world = creature.head_pos + Vector2.RIGHT.rotated(deg_to_rad(-70.0)) * 200.0
	for _tick in 30:
		creature.command = aim
		creature._physics_process(TICK)

	var torso: float = creature.spine.forwards[1].angle()
	var tail: Vector2 = creature.spine.points[creature.spine.size() - 1]
	var neck: float = creature.params.segment_length
	creature.request_bite(aim.aim_world)
	var reach: float = 0.0
	for _tick in 40:
		creature.command = aim
		creature._physics_process(TICK)
		reach = maxf(reach, creature.spine.points[0].distance_to(creature.spine.points[1]))

	var swung: float = rad_to_deg(absf(wrapf(creature.spine.forwards[1].angle() - torso, -PI, PI)))
	_check(swung < 5.0, "a strike swung the torso %.1f degrees round after the cursor" % swung)
	_check(tail.distance_to(creature.spine.points[creature.spine.size() - 1]) < 5.0,
		"a strike dragged the tail %.1f px"
			% tail.distance_to(creature.spine.points[creature.spine.size() - 1]))
	_check(reach > neck + creature.params.bite_reach * 0.8,
		"the head was never thrown past the body (%.1f px of neck against %.1f at rest)"
			% [reach, neck])
	_destroy_creature(creature)


func _spine_centre(creature: Creature) -> Vector2:
	var sum := Vector2.ZERO
	for i in creature.spine.size():
		sum += creature.spine.points[i]
	return sum / float(creature.spine.size())


func _spawn_creature() -> Creature:
	var creature := Creature.new()
	creature.params = CreatureParams.new()
	root.add_child(creature)
	return creature


func _destroy_creature(creature: Creature) -> void:
	root.remove_child(creature)
	creature.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
