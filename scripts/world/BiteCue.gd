## The bite marks lying in the world, drawn from the same impressions that ate
## the tissue under them.
##
## This is not a label and not an effect. `Main` hands it the very BiteMark it
## hands the victim's lattice, so every red print here is one tooth, at the
## place that tooth landed, sized as it was sized and darkened by how deep it
## drove. A mark over unbroken ground is a tooth that missed, and it should be —
## that is the mouth being read, not the damage being illustrated.
##
## Several marks are kept rather than one. Chewing works the jaws faster than a
## print fades, and a second creature biting must not erase the first one's.
class_name BiteCue
extends Node2D

## Long enough to read the shape of the mouth that made it, short enough that
## the flesh underneath — which is the permanent record — remains the thing you
## are looking at.
const DURATION: float = 0.55
const FADE_TIME: float = 0.30
## Prints held at once. Past this the oldest is overwritten, which is the right
## failure: the marks that matter are the recent ones.
const CAPACITY: int = 8
## Segments per print. A tooth is a small ellipse on screen; eight sides is
## already round at the scale these are drawn.
const FACETS: int = 8
## Blood, not ink. The one place in the palette where the creature's own colour
## appears outside its body — because that is exactly what a bite mark is.
const MARK := Color("a51f14")
const MARK_DEEP := Color("5e0f08")
## Depth, in the lattice's hit points, at which a print reads as fully driven
## home. Skin is 0.4 and muscle 5.5, so a print this dark is one that has gone
## through the hide into the meat.
const FULL_DEPTH: float = 4.0
## How much of its weight the broad patch the jaw bears with keeps. It is a
## bruise rather than a wound — the punctures are the mark, and a crush laid on
## at the same strength blots them out instead of sitting behind them.
const BEARING_WEIGHT: float = 0.4


## One closing of one set of jaws, with its own clock.
class Print extends RefCounted:
	var mark: BiteMark
	var remaining: float = 0.0


var prints: Array[Print] = []
var _next: int = 0
## Reused geometry, so a screen of prints is one canvas command rather than one
## per tooth — the same reason the creature's own cells are batched.
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _ready() -> void:
	z_index = 30
	prints.resize(CAPACITY)
	for i in CAPACITY:
		prints[i] = Print.new()


## Records a bite where it landed. The mark is retained rather than copied — it
## is finished the moment it is emitted and nothing writes to one afterwards.
func show_mark(mark: BiteMark) -> void:
	if mark == null or mark.is_empty():
		return
	var slot: Print = prints[_next]
	_next = (_next + 1) % CAPACITY
	slot.mark = mark
	slot.remaining = DURATION
	queue_redraw()


func is_showing() -> bool:
	for p in prints:
		if p.remaining > 0.0:
			return true
	return false


func clear() -> void:
	for p in prints:
		p.remaining = 0.0
		p.mark = null
	queue_redraw()


func _process(delta: float) -> void:
	var live: bool = false
	for p in prints:
		if p.remaining <= 0.0:
			continue
		p.remaining = maxf(p.remaining - delta, 0.0)
		live = true
	if live:
		queue_redraw()


func _draw() -> void:
	var count: int = 0
	for p in prints:
		if p.remaining > 0.0 and p.mark != null:
			count += p.mark.impressions.size()
	if count == 0:
		return
	if _points.size() != count * FACETS:
		_points.resize(count * FACETS)
		_colors.resize(count * FACETS)
		_indices.resize(count * (FACETS - 2) * 3)

	var v: int = 0
	var t: int = 0
	for p in prints:
		if p.remaining <= 0.0 or p.mark == null:
			continue
		var fade: float = clampf(p.remaining / FADE_TIME, 0.0, 1.0)
		# Prints swell very slightly as they fade, which is blood spreading out
		# of the puncture rather than the puncture growing.
		var bloom: float = 1.0 + (1.0 - p.remaining / DURATION) * 0.18
		for imp in p.mark.impressions:
			# Depth is the whole of the colour: a tooth that only creased the
			# skin leaves a faint print and one that reached meat leaves a dark
			# one, so the mark reads as the wound it just made.
			var bite: float = clampf(imp.depth / FULL_DEPTH, 0.0, 1.0)
			var weight: float = BEARING_WEIGHT if imp.bearing else 1.0
			var tint := Color(MARK.lerp(MARK_DEEP, bite),
				(0.34 + 0.5 * bite) * fade * weight)
			var side := Vector2(-imp.axis.y, imp.axis.x)
			var along: float = imp.half_along * bloom
			var across: float = imp.half_across * bloom
			for k in FACETS:
				var a: float = TAU * float(k) / float(FACETS)
				_points[v + k] = imp.pos \
					+ imp.axis * (cos(a) * along) + side * (sin(a) * across)
				_colors[v + k] = tint
			for k in range(1, FACETS - 1):
				_indices[t] = v
				_indices[t + 1] = v + k
				_indices[t + 2] = v + k + 1
				t += 3
			v += FACETS

	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)
