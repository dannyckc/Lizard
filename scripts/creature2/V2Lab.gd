## The v2 rebuild's habitat — a minimal Main (docs/V2_DESIGN.md §11.1).
##
## Camera, terrain, an input pump, one v2 creature and the troubleshooting HUD
## over the top of it: no fields, no senses, no world. v1's Main keeps running as
## the executable spec for behaviour; this scene exists so every phase of the
## rebuild has somewhere to stand its work up next to that oracle without touching
## it. Probes instantiate this scene headless, so nothing here may require a
## display — the HUD is built, hidden and idle in that case, and costs a probe
## nothing but its construction.
##
## The floor is bare except in one marked-off corner south of the spawn: the
## **proving ground** (`Proving`), which holds the steps, the solids, the
## overhang and two other animals — one alive and standing about, one dead. Walk
## south to it. Everything else out here is plain ground on purpose, because a
## gait is read against an empty floor.
##
## The input pump is deliberately tiny and lives entirely in this file — what the
## lab offers is the handling a probe cannot: walk the animal about, drag a node to
## feel the constraints answer, drop the body, knock it over, open it up.
##
##   mouse        look: the head tracks the cursor and the walk follows the head
##   LMB          bite at whatever the cursor is on — held, the jaws keep it
##                (the hold tows, and feeds on a carcass); released, they let go
##   W / S        throttle forward and back
##   A / D        turn
##   shift        sprint
##   space        jump (held to charge, released to spring)
##   wheel        zoom
##   F3           step the view round: field → anatomy → field
##   R            reset the creature to its spawn
##   K            collapse / revive (ragdoll mode toggle)
##   F            drop the body from a height
##   V            skeleton over the flesh — the state rather than the animal
##   RMB drag     haul the nearest body node with the mouse
class_name V2Lab
extends Node2D

const ZOOM_STEP: float = 1.12
const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 6.0
## How close to a node a click has to land to pick it up, world px.
const PICK_RADIUS: float = 26.0
const DROP_HEIGHT: float = 160.0
## How fast the camera settles onto what it is looking at. v1's rate, because
## opening a drawer has to slide the animal across at the speed the camera already
## follows a walk at — see `_camera_focus`.
const FOLLOW_RATE: float = 3.2

@onready var camera: Camera2D = $Camera2D
@onready var terrain: Node2D = $Terrain

var creature: Node2D = null
var hud: LabHUD = null
## The mark on whatever the cursor has hold of. Its own node above the world
## rather than a few more strokes in this file, because it has to be drawn over
## the animal it has selected — see AimMark.
var mark: AimMark = null
## Node index the mouse currently holds, -1 for none.
var _held: int = -1


func _ready() -> void:
	creature = get_node_or_null("Creature2")
	camera.make_current()
	mark = AimMark.new()
	mark.name = "AimMark"
	add_child(mark)
	_build_ui()
	camera.position = _camera_focus()


## The HUD stands on its own canvas layer, so it keeps the window while the camera
## follows the animal about underneath it.
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 20
	add_child(layer)
	hud = LabHUD.new()
	hud.name = "HUD"
	layer.add_child(hud)
	hud.set_subject(creature as Creature2)


## Where the camera is trying to look: the animal, pushed over by half whatever
## column the HUD has taken out of the window, so it sits in the middle of the
## paper that is left rather than in the middle of the glass. The HUD says how far
## in screen pixels and the zoom turns that into a distance in the world.
##
## The same lerp carries this as carries the animal's own movement, which is the
## whole reason it is a shift of what the camera is *looking at* rather than a
## rect the field is drawn into: opening a drawer slides the picture across at the
## speed the camera already follows a walk at, and closing one slides it back from
## wherever it had got to. Nothing snaps, and there is no second easing to keep in
## step with the first.
func _camera_focus() -> Vector2:
	if creature == null:
		return camera.position
	# The head, as v1's habitat frames it: the animal is being worn rather than
	# watched, so the picture is centred on the end of it that is doing the
	# looking and the body trails behind. Deliberately `head_pos` — the mover's
	# own anchor — and not the drawn head, or the camera would sway with every
	# glance the cursor took.
	var look: Vector2 = creature.head_pos
	if hud == null:
		return look
	return look + Vector2(hud.field_shift() / camera.zoom.x, 0.0)


func _process(delta: float) -> void:
	if creature == null:
		return
	camera.position = camera.position.lerp(_camera_focus(),
		1.0 - exp(-FOLLOW_RATE * delta))
	# Polled rather than evented, because a throttle is a state rather than a
	# keystroke: the animal is being asked for something for as long as the key is
	# down, and the gait is meant to read the ask every tick. Nothing reads it while
	# the movers are out for rewrite, so W/A/S/D move nothing — the drag, the drop,
	# the collapse and the views all still work.
	var command: Creature2.Command = creature.command
	command.throttle = (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
	command.turn = (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	command.sprint = Input.is_physical_key_pressed(KEY_SHIFT)
	command.jump = Input.is_physical_key_pressed(KEY_SPACE)
	# The head settles forward while the cursor is over the HUD. Mouse look is
	# purely aim and never touches the axes above, so an animal crossing the lab
	# while a drawer is being read keeps going exactly where it was pointed.
	command.aim_active = get_viewport().gui_get_hovered_control() == null
	command.aim_world = _world_mouse()
	_aim_cursor()
	if mark != null:
		mark.show_aim(creature as Creature2, camera.zoom.x)


## Resolves the cursor into one target and hands it to the creature.
##
## Every tick rather than on the click, and that is what makes it a *target*
## rather than a mouse coordinate: the animal is looking at whatever the pointer
## is on before any button is pressed, the reach to it is priced, and the mark
## says whether the jaws can be got onto it — so the strike, when it comes, is
## thrown at something the player has already been told about.
##
## Owned here rather than by the creature because which of the several things
## under one pixel was meant is a question about the world, and only the world
## can see all of them. Which is exactly why it takes two calls: `pick` is that
## question and is answered without reference to anybody, and `resolve` is the
## other one — which surface *this* animal's jaws would meet, and whether the
## marker has to stop short because it cannot get that far.
func _aim_cursor() -> void:
	var me := creature as Creature2
	if me == null:
		return
	if not me.command.aim_active:
		me.aim_at(null)
		return
	me.aim_at(Quarry.resolve(Quarry.pick(get_tree(), _world_mouse(),
		me, Quarry.SLACK), me))


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
			# The button is two things at once and both are told to the body:
			# the press is one strike, and the state of the button is whether
			# the jaws keep what they close on. A press while already holding is
			# neither — the mouth is busy, and it goes on chewing.
			if creature == null:
				return
			creature.set_bite_held(event.pressed)
			if event.pressed:
				creature.request_bite(_world_mouse())
		MOUSE_BUTTON_RIGHT:
			# The lab's own handling, moved off the left button now that the
			# left button is the animal's: hauling a node about is a thing done
			# *to* a specimen, not by it.
			if not event.pressed:
				_held = -1
			elif creature != null:
				_held = creature.pick_node(_world_mouse(), PICK_RADIUS)


func _pump_drag(_event: InputEventMouseMotion) -> void:
	if creature == null or _held < 0:
		return
	creature.haul_node(_held, _world_mouse())


## A bite may begin only from unhandled world input, but its release must be
## observed even if the cursor moves over the HUD while the jaws are clamped.
## `_input` runs before GUI dispatch, so handling only the release here
## preserves both rules.
func _input(event: InputEvent) -> void:
	if creature != null and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		creature.set_bite_held(false)


## A window that loses focus with the button down has not asked the animal to
## hold on forever.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(creature):
		creature.set_bite_held(false)


func _pump_key(event: InputEventKey) -> void:
	if event.keycode == KEY_F3:
		if hud != null:
			hud.toggle_view()
		return
	if creature == null:
		return
	match event.keycode:
		KEY_R:
			creature.reset()
			camera.position = _camera_focus()
			if hud != null:
				hud.reset_hint()
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
