## Twenty-four-dot biomass track from the lower-left HUD.
class_name BiomassMeter
extends Control

const INK := Color("14140f")
const PIP_COUNT: int = 24

var _progress: float = 0.0

var progress: float = 0.0:
	get:
		return _progress
	set(next):
		_progress = clampf(next, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(187.0, 9.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var spacing: float = size.x / float(PIP_COUNT - 1)
	var last_filled: float = progress * float(PIP_COUNT - 1)
	for i in PIP_COUNT:
		var color: Color = INK if float(i) <= last_filled else Color(INK, 0.20)
		draw_circle(Vector2(float(i) * spacing, size.y * 0.5), 1.5, color)
