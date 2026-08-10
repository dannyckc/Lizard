## Hairline slider used by the monochrome creation menu.
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

## Where this control's own baseline sits on the track — the value the creature's
## species carries — drawn as a notch under the line. Left infinite on a slider
## that has nothing to be compared against, and then nothing is drawn.
##
## It is here rather than in the panel because it is a fact about *this* track:
## the whole point of it is that the distance between the notch and the handle is
## the distance between the animal and its species, and only the control knows
## where along itself either of those falls.
var reference: float = INF:
	get:
		return _reference
	set(next):
		_reference = next
		queue_redraw()

const INK := Color("14140f")
const PAPER := Color("f3f1ec")
## How far the baseline notch drops below the track.
const NOTCH: float = 4.0

var _reference: float = INF
var _dragging: bool = false


func _ready() -> void:
	# Only if nobody has said otherwise. A panel that has sized its own tracks has
	# done it to line them up with the rows around them, and the default arriving
	# late would put every one of them back.
	if custom_minimum_size == Vector2.ZERO:
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
	if is_finite(_reference) and max_value > min_value:
		var at: float = lerpf(left, right,
			clampf(inverse_lerp(min_value, max_value, _reference), 0.0, 1.0))
		draw_line(Vector2(at, y + 2.0), Vector2(at, y + 2.0 + NOTCH), Color(INK, 0.34), 1.0)
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


## Whether the pointer currently has hold of the handle. What the creation menu
## meters its parameter writes by: a drag is a stream of values and lands a few
## times a second, while a click, a key nudge or a test driving the control
## programmatically is one value and lands at once.
func is_dragging() -> bool:
	return _dragging


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
