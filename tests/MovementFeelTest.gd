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
	_check_turn_response()
	_check_turn_switch_answers_promptly()
	_check_moving_turn_has_no_extra_sweep()

	if failures.is_empty():
		print("movement feel OK — reverse keeps facing and steering answers promptly")
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

	for _tick in 120:
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


func _check_turn_response() -> void:
	var creature := _spawn_creature()
	var turn := MovementInput.Command.new()
	turn.turn = 1.0
	var start: Vector2 = creature.head_pos

	for _tick in 6:
		creature.command = turn
		creature._physics_process(TICK)

	var six_tick_turn: float = rad_to_deg(absf(creature.heading))
	_check(six_tick_turn >= 8.0,
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
