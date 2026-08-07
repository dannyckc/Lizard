## Turns raw device state into an abstract movement command.
##
## Kept deliberately separate from the creature so the same body can be driven
## by an AI, a replay or a test harness by handing it a different Command.
## Uses physical key positions so the layout is WASD on any keyboard layout.
class_name MovementInput
extends RefCounted

## What the creature actually consumes. Nothing device-specific survives here.
class Command extends RefCounted:
	var throttle: float = 0.0   ## -1 (reverse) .. +1 (full forward)
	var turn: float = 0.0       ## -1 (left) .. +1 (right)
	var sprint: bool = false
	var aim_world: Vector2 = Vector2.ZERO


var command: Command = Command.new()

## When true, the cursor continuously steers the head. Left click is reserved
## for the bite action and is handled by Main's unhandled-input path.
var mouse_steering: bool = true


func read(head_pos: Vector2, heading: float, mouse_world: Vector2) -> Command:
	var throttle: float = 0.0
	var turn: float = 0.0

	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		throttle += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		throttle -= 0.55  # backing up is slower than walking forward
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn += 1.0

	# Always aim toward the cursor, easing off the turn as we line up so the
	# creature settles onto the heading instead of oscillating. Mouse aiming
	# changes facing only; W/S remain authoritative for forward movement.
	if mouse_steering:
		var to_mouse: Vector2 = mouse_world - head_pos
		if to_mouse.length() > 12.0:
			var offset: float = wrapf(to_mouse.angle() - heading, -PI, PI)
			turn = clampf(offset * 2.2, -1.0, 1.0)

	command.throttle = clampf(throttle, -1.0, 1.0)
	command.turn = clampf(turn, -1.0, 1.0)
	command.sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	command.aim_world = mouse_world
	return command
