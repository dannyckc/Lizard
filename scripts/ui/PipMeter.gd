## The lower-left HUD's twenty-four-dot track.
##
## One control, used for both of the readings down there, and it knows what
## neither of them is: it is handed a fraction and draws a length. The dots rather
## than a solid bar are the field HUD's own idiom — the anatomy drawer states a
## proportion as a hairline, and this corner states one as a track — so a second
## reading placed beside the first needs no new shape to be legible.
class_name PipMeter
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


## Dots are counted rather than indexed, so the two ends read as what they are:
## nothing left is an empty track, and a sliver left is one dot. A track that lit
## its first pip at zero would be a bar telling a dead animal it had something.
func _draw() -> void:
	var spacing: float = size.x / float(PIP_COUNT - 1)
	var filled: int = int(ceil(progress * float(PIP_COUNT)))
	for i in PIP_COUNT:
		var color: Color = INK if i < filled else Color(INK, 0.20)
		draw_circle(Vector2(float(i) * spacing, size.y * 0.5), 1.5, color)
