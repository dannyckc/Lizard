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
	KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_CTRL, KEY_SPACE,
	KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT,
]

var failures: Array[String] = []
var notes: Array[String] = []
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
	_check_walking_follows_the_head()
	_check_hand_steering_has_the_last_word()
	_check_close_control()
	_release_all_keys()

	if failures.is_empty():
		print("controls OK — a walk goes where the head looks, the hand overrules it, and close control is slow and low: %s"
			% " · ".join(notes))
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

	# Ctrl is one instruction — come down — and it arrives as two facts because it
	# means two things to two bodies: a descent to something already in the air,
	# and close control to something standing on the ground. Neither may have
	# quietly replaced the other.
	command = device.read(Vector2.ZERO, 0.0, cursor_a)
	_check(not command.stalk, "close control was on with nothing held")
	_set_physical_key(KEY_CTRL, true)
	command = device.read(Vector2.ZERO, 0.0, cursor_a)
	_check(command.stalk, "physical Ctrl did not ask for close control")
	_check(is_equal_approx(command.climb, -1.0),
		"Ctrl stopped meaning come down when it started meaning close control")
	_check(is_zero_approx(command.throttle) and is_zero_approx(command.turn),
		"Ctrl leaked into the ground plane")
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


## An animal walking forward goes where it is looking.
##
## The claim has three parts and all three are here, because any one of them on
## its own is a different and worse mechanic: the body comes round to the
## direction the head is already pointing; it *arrives* rather than orbiting; and
## the head straightens out onto the body as it does, which is what makes it one
## movement instead of a heading snap with a head animation over the top.
func _check_walking_follows_the_head() -> void:
	_release_all_keys()
	var creature: Creature = _spawn_creature(0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.aim_active = true
	# A fixed place in the world rather than a fixed angle off the body: a cursor
	# held permanently over the animal's shoulder is a creature asked to turn for
	# ever, and it would turn for ever. Pointing at somewhere it never gets to is
	# what makes "did it arrive" a question with an answer.
	var mark: Vector2 = creature.head_pos + Vector2.RIGHT.rotated(deg_to_rad(70.0)) * 900.0
	var start: float = absf(wrapf((mark - creature.head_pos).angle() - creature.heading, -PI, PI))
	var overshoot: float = 0.0
	# Ten seconds rather than two and a half. A walking turn is bounded by the arc
	# the body can carve across the ground — see Creature.MIN_TURN_ARC — so coming
	# round seventy degrees is a manoeuvre the animal walks through, on a circle
	# wider than it is long, rather than one it snaps into. The claim is that it
	# arrives and settles with its neck straight, not how soon; the window stops
	# short of where it would walk past the mark and start turning back.
	for _tick in 600:
		drive.aim_world = mark
		creature.command = drive
		creature._physics_process(TICK)
		var error: float = wrapf((mark - creature.head_pos).angle() - creature.heading, -PI, PI)
		overshoot = maxf(overshoot, -error)
		_check_pose_invariants(creature, "head-led walk")

	var final_error: float = absf(wrapf(
		(mark - creature.head_pos).angle() - creature.heading, -PI, PI))
	var neck: float = absf(wrapf(creature.head_look_angle - creature.heading, -PI, PI))
	_check(final_error < deg_to_rad(8.0),
		"a creature walking toward a mark %.0f degrees off its bow only came round to %.0f"
			% [rad_to_deg(start), rad_to_deg(start - final_error)])
	_check(overshoot < deg_to_rad(10.0),
		"the body swung %.0f degrees past the heading it was turning onto"
			% rad_to_deg(overshoot))
	_check(neck < deg_to_rad(8.0),
		"the head was still carried %.0f degrees off the body it had brought round"
			% rad_to_deg(neck))
	notes.append("head leads %.0f deg -> %.0f, neck %.0f"
		% [rad_to_deg(start), rad_to_deg(final_error), rad_to_deg(neck)])

	# ...and none of it happens standing still. A creature that is not walking
	# anywhere is watching, and watching is not steering — which is the whole of
	# what keeps the mouse off the body.
	var standing: Creature = _spawn_creature(0.0)
	var watch := MovementInput.Command.new()
	watch.aim_active = true
	watch.aim_world = standing.head_pos + Vector2.RIGHT.rotated(deg_to_rad(70.0)) * 900.0
	var held: float = standing.heading
	for _tick in 120:
		standing.command = watch
		standing._physics_process(TICK)
	_check(absf(wrapf(standing.heading - held, -PI, PI)) <= ANGLE_EPSILON,
		"a standing creature steered itself %.3f degrees with its eyes"
			% rad_to_deg(absf(wrapf(standing.heading - held, -PI, PI))))
	_destroy_creature(standing)
	_destroy_creature(creature)


## The hand overrules the head. A player holding a turn key is steering, and what
## the head is doing is then a look rather than an instruction — otherwise every
## deliberate turn away from something the animal is watching would be fought by
## the animal.
func _check_hand_steering_has_the_last_word() -> void:
	_release_all_keys()
	var creature: Creature = _spawn_creature(0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.turn = -1.0
	drive.aim_active = true
	var start: float = creature.heading
	for _tick in 60:
		# Off to the right the whole way, which is the side the hand is not turning
		# toward: the two inputs disagree on every tick of this.
		drive.aim_world = creature.head_pos + Vector2.RIGHT.rotated(
			creature.heading + deg_to_rad(70.0)) * 700.0
		creature.command = drive
		creature._physics_process(TICK)
	_check(wrapf(creature.heading - start, -PI, PI) < -deg_to_rad(20.0),
		"a creature holding a left turn against a cursor on its right came round %.0f degrees"
			% rad_to_deg(wrapf(creature.heading - start, -PI, PI)))
	_destroy_creature(creature)


## Close control: slower, and as low as this particular skeleton goes.
##
## Both halves are asked of one body in one run, because they are one instruction
## — and the second half is asked of the *fold* rather than of a number of pixels,
## since how far an animal can get its belly down is a fact about its own joints.
func _check_close_control() -> void:
	_release_all_keys()
	var creature: Creature = _spawn_creature(0.0)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	for _tick in 150:
		creature.command = drive
		creature._physics_process(TICK)
	var open_speed: float = creature.speed
	var standing: float = creature.gait.support

	drive.stalk = true
	for _tick in 150:
		creature.command = drive
		creature._physics_process(TICK)
	_check(creature.is_stalking(), "Ctrl held on the ground was not close control")
	_check(creature.crouch > 0.85,
		"close control spent only %.0f%% of the animal's fold" % (creature.crouch * 100.0))
	_check(creature.gait.support < standing - 1.0,
		"the crouch never reached the body: it rode %.1f px before and %.1f px after"
			% [standing, creature.gait.support])
	_check(creature.speed < open_speed * 0.6,
		"a stalking creature moved at %.0f px/s against %.0f walking"
			% [creature.speed, open_speed])
	notes.append("stalk %.0f -> %.0f px/s, rides %.1f -> %.1f px"
		% [open_speed, creature.speed, standing, creature.gait.support])

	# And it is a mode nothing latches into: released, the animal stands back up
	# and walks off at the speed it always had.
	drive.stalk = false
	for _tick in 180:
		creature.command = drive
		creature._physics_process(TICK)
	_check(creature.crouch < 0.05,
		"the animal stayed folded %.2f after close control was released" % creature.crouch)
	_check(creature.speed > open_speed * 0.9,
		"a creature that stopped stalking only got back to %.0f px/s of %.0f"
			% [creature.speed, open_speed])
	_destroy_creature(creature)


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
	# The rest length the spine is actually being solved to — see
	# Creature.segment_rest. Identical to the parameter on anything that is not
	# folding its back, which is every creature this file drives.
	var seg_len: float = creature.segment_rest()
	var max_bend: float = deg_to_rad(creature.params.max_bend_deg)
	for i in range(1, creature.spine.size()):
		var actual: float = creature.spine.points[i - 1].distance_to(creature.spine.points[i])
		_check(absf(actual - seg_len) <= POSITION_EPSILON,
			"%s stretched segment %d to %.6f px (rest %.6f)" % [
				label, i, actual, seg_len])
	# Against the limit each joint was solved to rather than one for the animal:
	# a tapering tail bends further than the back it hangs off, and the spine is
	# the one place that says by how much — see Spine.bend_at.
	for i in range(1, creature.spine.size() - 1):
		var front: float = (creature.spine.points[i - 1] - creature.spine.points[i]).angle()
		var back: float = (creature.spine.points[i] - creature.spine.points[i + 1]).angle()
		var bend: float = absf(wrapf(front - back, -PI, PI))
		var limit: float = creature.spine.bend_at(i, max_bend)
		_check(bend <= limit + ANGLE_EPSILON,
			"%s exceeded max bend at joint %d: %.4f° > %.4f°" % [
				label, i, rad_to_deg(bend), rad_to_deg(limit)])


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
