## Compact pill toggle matching the tuning-panel reference.
class_name InkToggle
extends Control

signal toggled(pressed: bool)

var _button_pressed: bool = true

@export var button_pressed: bool = true:
	get:
		return _button_pressed
	set(next):
		_button_pressed = next
		queue_redraw()

const INK := Color("14140f")


func _ready() -> void:
	# See MinimalSlider: a panel that has sized its controls keeps that size.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(76.0, 26.0)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP


func _draw() -> void:
	var origin := Vector2(1.0, 6.0)
	var track := Rect2(origin, Vector2(26.0, 14.0))
	draw_style_box(_track_style(), track)
	var knob_x: float = 18.0 if button_pressed else 6.0
	draw_circle(Vector2(origin.x + knob_x, origin.y + 7.0), 4.0, Color(INK, 1.0 if button_pressed else 0.28))
	if has_focus():
		draw_rect(track.grow(2.0), Color(INK, 0.20), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	var activate: bool = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		activate = true
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_ENTER]:
		activate = true
	if activate:
		grab_focus()
		button_pressed = not button_pressed
		toggled.emit(button_pressed)
		accept_event()


func _track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.02)
	style.border_color = Color(INK, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style
