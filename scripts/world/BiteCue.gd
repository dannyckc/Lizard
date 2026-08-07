## Brief world-space action label for a top-down bite. The creature silhouette
## carries direction through its real forward lunge; this cue marks the exact
## place where that lunge resolves without cutting a sideways mouth into it.
class_name BiteCue
extends Node2D

const DURATION: float = 0.26
const FADE_TIME: float = 0.12
const INK := Color("14140f")
const PAPER := Color("f3f1ec")

var remaining: float = 0.0
var world_pos: Vector2 = Vector2.ZERO
var _font: Font


func _ready() -> void:
	_font = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	if _font == null:
		_font = ThemeDB.fallback_font
	z_index = 30


func show_at(at: Vector2) -> void:
	world_pos = at
	remaining = DURATION
	queue_redraw()


func is_showing() -> bool:
	return remaining > 0.0


func _process(delta: float) -> void:
	if remaining <= 0.0:
		return
	remaining = maxf(remaining - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if remaining <= 0.0 or _font == null:
		return
	var elapsed: float = DURATION - remaining
	var alpha: float = clampf(remaining / FADE_TIME, 0.0, 1.0)
	var rise: float = smoothstep(0.0, 1.0, elapsed / DURATION) * 7.0
	var at: Vector2 = world_pos + Vector2(0.0, -18.0 - rise)
	var pulse: float = 1.0 + sin(elapsed / DURATION * PI) * 0.08

	# A compact paper disc keeps the word readable over either creature while a
	# dark ring pins it to the impact point rather than making it a HUD message.
	draw_circle(at, 16.0 * pulse, Color(PAPER, 0.88 * alpha))
	draw_arc(at, 16.0 * pulse, 0.0, TAU, 28, Color(INK, 0.34 * alpha), 1.0, true)
	var width: float = 42.0
	var baseline := at + Vector2(-width * 0.5, 4.2)
	draw_string(_font, baseline, "Bite", HORIZONTAL_ALIGNMENT_CENTER,
		width, 12, Color(INK, alpha))
