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
	var aim_active: bool = false


var command: Command = Command.new()

## Disabled while the cursor is interacting with the tuning UI. This affects
## only the articulated head pose; the mouse never writes locomotion or facing.
var mouse_look: bool = true


func read(_head_pos: Vector2, _heading: float, mouse_world: Vector2) -> Command:
	var throttle: float = 0.0
	var turn: float = 0.0

	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		throttle += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		throttle -= 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		turn -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		turn += 1.0

	command.throttle = clampf(throttle, -1.0, 1.0)
	command.turn = clampf(turn, -1.0, 1.0)
	command.sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	command.aim_world = mouse_world
	command.aim_active = mouse_look
	return command
