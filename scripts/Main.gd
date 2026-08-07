## Game root: wires input to the creature, follows it with the camera, keeps the
## food field topped up and owns the HUD / tuning panel.
##
## Node order in the scene matters — Main ticks before its children, so the
## movement command written here is the one the creature consumes this tick.
extends Node2D

const GRID_SPACING: float = 90.0
## Creature is ~200 px long; this frames it without losing the sense of speed.
const DEFAULT_ZOOM: float = 1.4
const COL_GRID := Color(1, 1, 1, 0.035)
const COL_GRID_MAJOR := Color(1, 1, 1, 0.06)

@onready var food_field: FoodField = $FoodField
@onready var creature: Creature = $Creature
@onready var view: CreatureView = $Creature/View
@onready var camera: Camera2D = $Camera2D

var input := MovementInput.new()
var panel: TuningPanel
var hud: Label


func _ready() -> void:
	camera.make_current()
	camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	camera.global_position = creature.head_pos
	food_field.refresh(creature.head_pos)
	_build_ui()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	hud = Label.new()
	hud.position = Vector2(18, 14)
	hud.add_theme_color_override("font_color", Color(0.85, 0.92, 0.88))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)

	panel = TuningPanel.new()
	panel.params = creature.params
	layer.add_child(panel)


func _physics_process(_delta: float) -> void:
	# Don't drive the creature with the mouse while the cursor is on a slider.
	input.mouse_steering = get_viewport().gui_get_hovered_control() == null
	creature.command = input.read(creature.head_pos, creature.heading, get_global_mouse_position())

	food_field.refresh(creature.head_pos)
	var eaten: int = food_field.consume(creature.head_pos, creature.mouth_radius())
	if eaten > 0:
		creature.feed(eaten)


func _process(delta: float) -> void:
	# Look slightly ahead of the head so there is room to see where you are
	# going, and ease the camera so it doesn't transmit the head's every wobble.
	var look_ahead: Vector2 = creature.move_dir * (creature.speed_norm * 110.0)
	var goal: Vector2 = creature.head_pos + look_ahead
	camera.global_position = camera.global_position.lerp(goal, 1.0 - exp(-4.0 * delta))

	_update_hud()
	queue_redraw()


func _update_hud() -> void:
	var stepping: int = 0
	for limb in creature.gait.limbs:
		if limb.stepping:
			stepping += 1
	var state: String = "idle"
	if creature.speed_norm > 0.05:
		state = "walking"
	if absf(creature.ang_vel) > 0.6 and creature.speed_norm < 0.35:
		state = "turning"
	if creature.command.sprint and creature.speed_norm > 0.7:
		state = "running"

	hud.text = "\n".join([
		"WASD / arrows  move + turn      hold LMB  steer to cursor      Shift  sprint",
		"F1 tuning panel      F2 debug draw      R reset      wheel zoom",
		"",
		"state: %s    speed: %d px/s    feet airborne: %d/4" % [state, int(absf(creature.speed)), stepping],
		"food: %d    size: x%.2f    segments: %d" % [creature.food_eaten, creature.size_scale, creature.spine.size()],
	])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				panel.visible = not panel.visible
			KEY_F2:
				view.debug = not view.debug
			KEY_R:
				creature.reset()
				food_field.pellets.clear()
				food_field.refresh(creature.head_pos)
				camera.global_position = creature.head_pos
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)


func _zoom_by(factor: float) -> void:
	var z: float = clampf(camera.zoom.x * factor, 0.35, 3.0)
	camera.zoom = Vector2(z, z)


## Reference grid, so movement and turning are readable against the ground.
func _draw() -> void:
	var half: Vector2 = get_viewport_rect().size * 0.5 / camera.zoom
	var centre: Vector2 = camera.global_position
	var min_x: float = floor((centre.x - half.x) / GRID_SPACING) * GRID_SPACING
	var max_x: float = centre.x + half.x
	var min_y: float = floor((centre.y - half.y) / GRID_SPACING) * GRID_SPACING
	var max_y: float = centre.y + half.y

	var x: float = min_x
	while x <= max_x:
		var major: bool = int(round(x / GRID_SPACING)) % 5 == 0
		draw_line(Vector2(x, min_y), Vector2(x, max_y), COL_GRID_MAJOR if major else COL_GRID, 1.0)
		x += GRID_SPACING

	var y: float = min_y
	while y <= max_y:
		var major_y: bool = int(round(y / GRID_SPACING)) % 5 == 0
		draw_line(Vector2(min_x, y), Vector2(max_x, y), COL_GRID_MAJOR if major_y else COL_GRID, 1.0)
		y += GRID_SPACING
