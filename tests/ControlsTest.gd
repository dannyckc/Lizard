## Focused headless check for the boundary between device input, body movement
## and cursor-driven head articulation.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/ControlsTest.gd
extends SceneTree

const TICK: float = 1.0 / 60.0
const POSITION_EPSILON: float = 0.001
const ANGLE_EPSILON: float = 0.0001
const CONTROL_KEYS: Array[Key] = [
	KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT,
	KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT,
]

var failures: Array[String] = []
var checked: bool = false


func _initialize() -> void:
	# SceneTree's root is not fully ready during _initialize; run assertions from
	# the first process tick so spawned Creatures receive _ready immediately.
	_release_all_keys()


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	# A previous test process should not be able to poison this one, and every
	# synthetic press below has a matching release even when an assertion fails.
	_release_all_keys()
	_check_device_mapping()
	_check_mouse_only_pose(0.0, "forward-facing")
	_check_mouse_only_pose(deg_to_rad(113.0), "rotated")
	_check_aim_isolated_from_wasd()
	_release_all_keys()

	if failures.is_empty():
		print("controls OK — physical WASD owns locomotion; cursor aim articulates only the head")
		quit(0)
	else:
		for failure in failures:
			print("CONTROLS FAIL — ", failure)
		quit(1)
	return false


## MainLoop cleanup is a second line of defence for interrupted/error exits.
func _finalize() -> void:
	_release_all_keys()


func _check_device_mapping() -> void:
	var device := MovementInput.new()
	var cursor_a := Vector2(123.0, -456.0)
	var neutral: MovementInput.Command = device.read(Vector2(8.0, 9.0), 1.7, cursor_a)
	_check(is_zero_approx(neutral.throttle), "neutral input produced throttle")
	_check(is_zero_approx(neutral.turn), "mouse-only input produced body turn")
	_check(neutral.aim_active, "enabled mouse look did not mark aim active")
	_check(neutral.aim_world == cursor_a, "cursor position was not copied into aim_world")

	_set_physical_key(KEY_W, true)
	var command: MovementInput.Command = device.read(Vector2.ZERO, 0.0, cursor_a)
	_check(is_equal_approx(command.throttle, 1.0), "physical W did not map to forward throttle")
	_check(is_zero_approx(command.turn), "physical W leaked into turn")
	_set_physical_key(KEY_W, false)

	_set_physical_key(KEY_S, true)
	command = device.read(Vector2.ZERO, 0.0, cursor_a)
	_check(is_equal_approx(command.throttle, -1.0), "physical S did not map to reverse throttle")
	_check(is_zero_approx(command.turn), "physical S leaked into turn")
	_set_physical_key(KEY_S, false)

	_set_physical_key(KEY_A, true)
	command = device.read(Vector2.ZERO, 0.0, cursor_a)
	_check(is_equal_approx(command.turn, -1.0), "physical A did not map to left turn")
	_check(is_zero_approx(command.throttle), "physical A leaked into throttle")
	_set_physical_key(KEY_A, false)

	_set_physical_key(KEY_D, true)
	command = device.read(Vector2.ZERO, 0.0, cursor_a)
	_check(is_equal_approx(command.turn, 1.0), "physical D did not map to right turn")
	_check(is_zero_approx(command.throttle), "physical D leaked into throttle")

	# Changing both cursor position and the heading argument cannot rewrite the
	# active D command. The mouse payload remains available separately for the head.
	var cursor_b := Vector2(-900.0, 275.0)
	command = device.read(Vector2(44.0, -31.0), deg_to_rad(137.0), cursor_b)
	_check(is_equal_approx(command.turn, 1.0), "cursor aim overrode physical D turn")
	_check(is_zero_approx(command.throttle), "cursor aim introduced point-and-go throttle")
	_check(command.aim_world == cursor_b, "updated cursor position did not reach aim_world")

	device.mouse_look = false
	command = device.read(Vector2.ZERO, -2.4, cursor_a)
	_check(not command.aim_active, "disabled mouse look still marked aim active")
	_check(command.aim_world == cursor_a, "inactive aim discarded the current cursor position")
	_check(is_equal_approx(command.turn, 1.0), "disabling mouse look changed the D command")
	_set_physical_key(KEY_D, false)

	_set_physical_key(KEY_W, true)
	_set_physical_key(KEY_S, true)
	_set_physical_key(KEY_A, true)
	_set_physical_key(KEY_D, true)
	command = device.read(Vector2.ZERO, 0.0, cursor_a)
	_check(is_zero_approx(command.throttle), "W and S did not cancel")
	_check(is_zero_approx(command.turn), "A and D did not cancel")
	_release_all_keys()


## With no movement keys held, cursor aim may move point 0 around the neck but
## cannot move the authoritative body anchor or any downstream spine particle.
func _check_mouse_only_pose(facing: float, label: String) -> void:
	_release_all_keys()
	var creature: Creature = _spawn_creature(facing)
	var device := MovementInput.new()
	var start_head: Vector2 = creature.head_pos
	var start_heading: float = creature.heading
	var start_points: PackedVector2Array = creature.spine.points.duplicate()
	var start_forward: Vector2 = creature.body.head.fwd
	var aim_direction: Vector2 = Vector2.RIGHT.rotated(facing + deg_to_rad(60.0))
	var cursor: Vector2 = start_head + aim_direction * 600.0
	var start_error: float = absf(wrapf(
		aim_direction.angle() - start_forward.angle(), -PI, PI))

	for _tick in 90:
		creature.command = device.read(creature.head_pos, creature.heading, cursor)
		creature._physics_process(TICK)

	var final_error: float = absf(wrapf(
		aim_direction.angle() - creature.body.head.fwd.angle(), -PI, PI))
	_check(creature.head_pos.distance_to(start_head) <= POSITION_EPSILON,
		"%s mouse-only aim moved head_pos by %.6f px" % [label,
			creature.head_pos.distance_to(start_head)])
	_check(absf(wrapf(creature.heading - start_heading, -PI, PI)) <= ANGLE_EPSILON,
		"%s mouse-only aim changed body heading" % label)
	_check(absf(creature.speed) <= POSITION_EPSILON,
		"%s mouse-only aim created locomotion speed" % label)
	_check(creature.spine.points[0].distance_to(start_points[0]) > 1.0,
		"%s cursor did not visibly shift the articulated head" % label)
	_check(final_error < start_error - 0.05,
		"%s head did not turn toward cursor (%.1f° -> %.1f°)" % [label,
			rad_to_deg(start_error), rad_to_deg(final_error)])

	var downstream_drift: float = 0.0
	for i in range(1, creature.spine.size()):
		downstream_drift = maxf(downstream_drift,
			creature.spine.points[i].distance_to(start_points[i]))
	_check(downstream_drift <= POSITION_EPSILON,
		"%s mouse-only aim moved the neck/tail by %.6f px" % [label, downstream_drift])
	_check_pose_invariants(creature, "%s mouse-only pose" % label)
	_destroy_creature(creature)


## Run the same rotated W+D route twice with opposite cursor targets. Everything
## owned by locomotion must be identical; only point 0 and its visible frame may
## differ. This catches even a one-tick leak from the posed head into Verlet.
func _check_aim_isolated_from_wasd() -> void:
	_release_all_keys()
	_set_physical_key(KEY_W, true)
	_set_physical_key(KEY_D, true)
	var facing: float = deg_to_rad(-47.0)
	var left_aim: Dictionary = _run_aimed_route(facing, deg_to_rad(-62.0))
	var right_aim: Dictionary = _run_aimed_route(facing, deg_to_rad(62.0))
	_set_physical_key(KEY_W, false)
	_set_physical_key(KEY_D, false)

	_check(absf(wrapf(float(left_aim.heading) - float(right_aim.heading), -PI, PI))
		<= ANGLE_EPSILON, "different cursor aims changed the final WASD heading")
	_check((left_aim.head_pos as Vector2).distance_to(right_aim.head_pos as Vector2)
		<= POSITION_EPSILON, "different cursor aims changed the WASD trajectory")
	_check(is_equal_approx(float(left_aim.speed), float(right_aim.speed)),
		"different cursor aims changed locomotion speed")
	_check(is_equal_approx(float(left_aim.ang_vel), float(right_aim.ang_vel)),
		"different cursor aims changed angular velocity")

	var left_points: PackedVector2Array = left_aim.points
	var right_points: PackedVector2Array = right_aim.points
	_check(left_points.size() == right_points.size(), "aim routes produced different spine sizes")
	var downstream_delta: float = 0.0
	for i in range(1, mini(left_points.size(), right_points.size())):
		downstream_delta = maxf(downstream_delta, left_points[i].distance_to(right_points[i]))
	_check(downstream_delta <= POSITION_EPSILON,
		"cursor aim leaked into spine points 1..tail by %.6f px" % downstream_delta)
	_check(left_points[0].distance_to(right_points[0]) > 1.0,
		"opposite cursor aims produced the same articulated head position")
	_check((left_aim.head_fwd as Vector2).dot(right_aim.head_fwd as Vector2) < 0.995,
		"opposite cursor aims produced the same visible head direction")


func _run_aimed_route(facing: float, aim_offset: float) -> Dictionary:
	var creature: Creature = _spawn_creature(facing)
	var device := MovementInput.new()
	for _tick in 72:
		# Keep the cursor on the requested side of the moving body. Since heading is
		# precisely the state under test, a mouse leak makes the two runs diverge.
		var aim_direction: Vector2 = Vector2.RIGHT.rotated(creature.heading + aim_offset)
		var cursor: Vector2 = creature.head_pos + aim_direction * 800.0
		creature.command = device.read(creature.head_pos, creature.heading, cursor)
		creature._physics_process(TICK)
		_check_pose_invariants(creature, "aimed W+D route")

	var result := {
		"heading": creature.heading,
		"head_pos": creature.head_pos,
		"speed": creature.speed,
		"ang_vel": creature.ang_vel,
		"points": creature.spine.points.duplicate(),
		"head_fwd": creature.body.head.fwd,
	}
	_destroy_creature(creature)
	return result


func _check_pose_invariants(creature: Creature, label: String) -> void:
	var seg_len: float = creature.params.segment_length * creature.size_scale
	var max_bend: float = deg_to_rad(creature.params.max_bend_deg)
	for i in range(1, creature.spine.size()):
		var actual: float = creature.spine.points[i - 1].distance_to(creature.spine.points[i])
		_check(absf(actual - seg_len) <= POSITION_EPSILON,
			"%s stretched segment %d to %.6f px (rest %.6f)" % [
				label, i, actual, seg_len])
	for i in range(1, creature.spine.size() - 1):
		var front: float = (creature.spine.points[i - 1] - creature.spine.points[i]).angle()
		var back: float = (creature.spine.points[i] - creature.spine.points[i + 1]).angle()
		var bend: float = absf(wrapf(front - back, -PI, PI))
		_check(bend <= max_bend + ANGLE_EPSILON,
			"%s exceeded max bend at joint %d: %.4f° > %.4f°" % [
				label, i, rad_to_deg(bend), rad_to_deg(max_bend)])


func _spawn_creature(facing: float) -> Creature:
	var creature := Creature.new()
	creature.params = CreatureParams.new()
	creature.spawn_heading = facing
	root.add_child(creature)
	return creature


func _destroy_creature(creature: Creature) -> void:
	root.remove_child(creature)
	creature.free()


func _set_physical_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_check(Input.is_physical_key_pressed(key) == pressed,
		"synthetic physical key %s did not %s reliably" % [
			OS.get_keycode_string(key), "press" if pressed else "release"])


func _release_all_keys() -> void:
	for key in CONTROL_KEYS:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = false
		event.echo = false
		Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
