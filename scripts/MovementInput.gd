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
	## -1 (dive / come down) .. +1 (leave the ground, and keep climbing if the
	## animal has anything to climb with). One axis rather than a jump button and
	## a fly button, because on a body standing on the ground it means leap and on
	## one already off it it means climb — and those are the same instruction
	## given to two different animals.
	##
	## It is a *held* instruction at the top end and not an event, which is the
	## whole of the jump control: on the ground, held means the animal is winding
	## itself up and released means it goes with whatever it wound — see Jump. So
	## the edge is nowhere in this file and nothing device-specific decides it, and
	## an AI or a replay that holds the axis for a third of a second and drops it
	## takes exactly the jump a player holding the key that long would.
	var climb: float = 0.0
	var sprint: bool = false
	## Close control: get low, go slow, place the body deliberately. The other
	## half of `climb`'s bottom end rather than a second key — on a body already
	## off the ground "come down" is a descent, and on one standing on it, it is
	## the animal getting its belly nearer the floor. Same instruction, two
	## animals, exactly as `climb` reads at the top.
	var stalk: bool = false
	var aim_world: Vector2 = Vector2.ZERO
	var aim_active: bool = false


var command: Command = Command.new()

## Disabled while the cursor is interacting with the tuning UI. What it turns off
## is aiming: the head stops tracking the pointer and, with it, the walk stops
## following the head — see `Creature._head_lead`. Throttle, turn and everything
## else on the command are untouched, so a creature crossing the paddock while a
## slider is being dragged keeps going exactly where it was pointed.
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

	var climb: float = 0.0
	var down: bool = Input.is_physical_key_pressed(KEY_CTRL)
	if Input.is_physical_key_pressed(KEY_SPACE):
		climb += 1.0
	if down:
		climb -= 1.0

	command.throttle = clampf(throttle, -1.0, 1.0)
	command.turn = clampf(turn, -1.0, 1.0)
	command.climb = clampf(climb, -1.0, 1.0)
	command.stalk = down
	command.sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	command.aim_world = mouse_world
	command.aim_active = mouse_look
	return command
