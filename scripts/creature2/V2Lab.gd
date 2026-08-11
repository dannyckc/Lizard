## The v2 rebuild's habitat — a minimal Main (docs/V2_DESIGN.md §11.1).
##
## Camera, terrain, an input pump and one v2 creature, and nothing else: no
## fields, no senses, no HUD. v1's Main keeps running as the executable spec
## for behaviour; this scene exists so every phase of the rebuild has somewhere
## to stand its work up next to that oracle without touching it. Probes
## instantiate this scene headless, so nothing here may require a display.
##
## The input pump is deliberately tiny and lives entirely in this file — what the
## lab offers is the handling a probe cannot: walk the animal about, drag a node to
## feel the constraints answer, drop the body, knock it over, look at it.
##
##   W / S        throttle forward and back
##   A / D        turn
##   shift        sprint
##   space        jump (held to charge, released to spring)
##   wheel        zoom
##   R            reset the creature to its spawn
##   K            collapse / revive (ragdoll mode toggle)
##   F            drop the body from a height
##   V            skeleton over the flesh — the state rather than the animal
##   drag         haul the nearest body node with the mouse
class_name V2Lab
extends Node2D

const ZOOM_STEP: float = 1.12
const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 6.0
## How close to a node a click has to land to pick it up, world px.
const PICK_RADIUS: float = 26.0
const DROP_HEIGHT: float = 160.0

@onready var camera: Camera2D = $Camera2D
@onready var terrain: Node2D = $Terrain

var creature: Node2D = null
## Node index the mouse currently holds, -1 for none.
var _held: int = -1


func _ready() -> void:
	creature = get_node_or_null("Creature2")
	camera.make_current()


func _process(_delta: float) -> void:
	if creature == null:
		return
	camera.position = creature.centre()
	# Polled rather than evented, because a throttle is a state rather than a
	# keystroke: the animal is being asked for something for as long as the key is
	# down, and the gait reads the ask every tick.
	var command: Creature2.Command = creature.command
	command.throttle = (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
	command.turn = (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	command.sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	command.jump = Input.is_physical_key_pressed(KEY_SPACE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_pump_button(event)
	elif event is InputEventMouseMotion and _held >= 0:
		_pump_drag(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_pump_key(event)


func _pump_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom(ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom(1.0 / ZOOM_STEP)
		MOUSE_BUTTON_LEFT:
			if not event.pressed:
				_held = -1
			elif creature != null:
				_held = creature.pick_node(_world_mouse(), PICK_RADIUS)


func _pump_drag(_event: InputEventMouseMotion) -> void:
	if creature == null or _held < 0:
		return
	creature.haul_node(_held, _world_mouse())


func _pump_key(event: InputEventKey) -> void:
	if creature == null:
		return
	match event.keycode:
		KEY_R:
			creature.reset()
		KEY_K:
			creature.toggle_collapsed()
		KEY_F:
			creature.drop(DROP_HEIGHT)
		KEY_V:
			creature.debug = not creature.debug
			creature.queue_redraw()


func _zoom(factor: float) -> void:
	var z: float = clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)


func _world_mouse() -> Vector2:
	return get_global_mouse_position()
