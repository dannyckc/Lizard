## Hairline slider used by the monochrome tuning panel.
##
## Godot's stock slider is intentionally quite tactile and large.  This small
## control keeps the same mouse and keyboard behaviour while drawing the thin
## track and ink dot from the UI reference.
class_name MinimalSlider
extends Control

signal value_changed(value: float)

var _min_value: float = 0.0
var _max_value: float = 1.0
var _value: float = 0.0

@export var min_value: float = 0.0:
	get:
		return _min_value
	set(next):
		_min_value = next
		_set_value(value, false)
@export var max_value: float = 1.0:
	get:
		return _max_value
	set(next):
		_max_value = next
		_set_value(value, false)
@export var step: float = 0.01
@export var value: float = 0.0:
	get:
		return _value
	set(next):
		_set_value(next, false)

const INK := Color("14140f")
const PAPER := Color("f3f1ec")

var _dragging: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(76.0, 26.0)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var y: float = size.y * 0.5
	var left: float = 4.0
	var right: float = maxf(size.x - 4.0, left + 1.0)
	var t: float = inverse_lerp(min_value, max_value, value) if max_value > min_value else 0.0
	var x: float = lerpf(left, right, clampf(t, 0.0, 1.0))

	draw_line(Vector2(left, y), Vector2(right, y), Color(INK, 0.20), 1.0, true)
	draw_line(Vector2(left, y), Vector2(x, y), INK, 1.0, true)
	draw_circle(Vector2(x, y), 6.0, Color(PAPER, 0.96))
	draw_circle(Vector2(x, y), 3.5, INK)
	if has_focus():
		draw_arc(Vector2(x, y), 7.0, 0.0, TAU, 20, Color(INK, 0.18), 1.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			grab_focus()
			_set_from_x(event.position.x)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x(event.position.x)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var direction: float = 0.0
		if event.keycode in [KEY_LEFT, KEY_DOWN]:
			direction = -1.0
		elif event.keycode in [KEY_RIGHT, KEY_UP]:
			direction = 1.0
		if direction != 0.0:
			_set_value(value + maxf(step, 0.001) * direction, true)
			accept_event()


func set_value_silent(next: float) -> void:
	_set_value(next, false)


func _set_from_x(x: float) -> void:
	var t: float = clampf(inverse_lerp(4.0, maxf(size.x - 4.0, 5.0), x), 0.0, 1.0)
	var next: float = lerpf(min_value, max_value, t)
	if step > 0.0:
		next = snappedf(next, step)
	_set_value(next, true)


func _set_value(next: float, emit: bool) -> void:
	var clamped: float = clampf(next, min_value, max_value)
	if step > 0.0:
		clamped = snappedf(clamped, step)
	if is_equal_approx(_value, clamped):
		queue_redraw()
		return
	_value = clamped
	queue_redraw()
	if emit:
		value_changed.emit(_value)
