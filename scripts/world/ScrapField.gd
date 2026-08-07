## Chunks of skin and muscle a bite knocked off a creature, lying in the world
## as meat.
##
## Kept separate from FoodField because the two behave nothing alike: pellets
## are ambient scenery that respawns in a ring around the player and is culled
## behind it, whereas scraps are produced by a specific event at a specific
## place, fly, settle, and then stay exactly where they landed until something
## eats them. What they share is only the `consume()` contract, which is what
## lets Main feed a creature from either without caring which.
##
## The world owns these rather than the bitten creature: tissue that has come
## off is no longer part of anybody's anatomy, and it has to outlive both
## participants walking away.
class_name ScrapField
extends Node2D

## Hard ceiling on live chunks. A sustained fight sheds faster than anything
## eats, so the oldest scraps are dropped rather than letting the array — and
## the per-frame integration over it — grow without bound.
const MAX_SCRAPS: int = 160
## Velocity retained per second while a chunk is still flying.
const DRAG: float = 5.5
## Below this speed a chunk is considered to have come to rest, and stops
## costing anything but a draw.
const SETTLE_SPEED: float = 8.0

const COL_SKIN := Color("2b241c")
const COL_MUSCLE := Color("9c3b26")


class Scrap extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var angle: float = 0.0
	var spin: float = 0.0
	var size: float = 3.0
	var layer: int = 0
	var settled: bool = false
	## Instance id of the creature this came off, held as an id rather than a
	## reference so a scrap can outlive its former owner.
	var source_id: int = 0


var scraps: Array[Scrap] = []

var _rng := RandomNumberGenerator.new()
## Reused geometry, so drawing a full field allocates nothing per frame.
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func _ready() -> void:
	_rng.randomize()
	z_index = 2  # above the food pellets, below the creatures


## Throws a bite's worth of shed tissue outward from `origin` — the jaw that
## took it — so the spray reads as having been torn out in that direction.
## `source` is the creature it came off, which is the one creature that may not
## then eat it.
func scatter(chunks: Array, origin: Vector2, source: Node) -> void:
	var source_id: int = source.get_instance_id() if source != null else 0
	for chunk in chunks:
		var scrap := Scrap.new()
		scrap.pos = chunk.pos
		scrap.size = chunk.size
		scrap.layer = chunk.layer
		scrap.source_id = source_id
		var away: Vector2 = chunk.pos - origin
		var dir: Vector2 = away.normalized() if away.length_squared() > 1.0 \
			else Vector2.RIGHT.rotated(_rng.randf() * TAU)
		scrap.vel = dir.rotated(_rng.randfn(0.0, 0.45)) * _rng.randf_range(60.0, 190.0)
		scrap.angle = _rng.randf() * TAU
		scrap.spin = _rng.randfn(0.0, 7.0)
		scraps.append(scrap)

	var excess: int = scraps.size() - MAX_SCRAPS
	if excess > 0:
		scraps = scraps.slice(excess)


## Removes every scrap within `radius` of `pos` that `eater` is allowed to have,
## and returns how many were eaten. Same shape as FoodField.consume() on purpose
## — see the class comment.
##
## A creature never eats its own tissue. Without that rule, jaws closing on a
## victim's head shed chunks straight into the victim's own mouth volume, and
## being bitten *feeds* you — which is both absurd and a growth exploit.
func consume(pos: Vector2, radius: float, eater: Node) -> int:
	var eaten: int = 0
	var r2: float = radius * radius
	var eater_id: int = eater.get_instance_id() if eater != null else 0
	for i in range(scraps.size() - 1, -1, -1):
		if scraps[i].source_id == eater_id:
			continue
		if scraps[i].pos.distance_squared_to(pos) <= r2:
			scraps.remove_at(i)
			eaten += 1
	return eaten


func clear() -> void:
	scraps.clear()


func _process(delta: float) -> void:
	# Exponential decay rather than a linear step, so the settle looks the same
	# whatever the frame rate — and settled chunks fall out of the maths
	# entirely, which is what keeps a full field free.
	var keep: float = exp(-DRAG * delta)
	for scrap in scraps:
		if scrap.settled:
			continue
		scrap.pos += scrap.vel * delta
		scrap.angle += scrap.spin * delta
		scrap.vel *= keep
		scrap.spin *= keep
		if scrap.vel.length_squared() < SETTLE_SPEED * SETTLE_SPEED:
			scrap.vel = Vector2.ZERO
			scrap.spin = 0.0
			scrap.settled = true
	queue_redraw()


## Drawn as rotated squares: the same cell the chunk was torn out of, now loose.
##
## Emitted as one indexed triangle array, for the reason spelled out in
## CreatureView._build — a full field is 160 chunks, and 160 separate
## polygon commands a frame is a measurable slice of the budget on its own.
func _draw() -> void:
	var count: int = scraps.size()
	if count == 0:
		return
	if _points.size() != count * 4:
		_points.resize(count * 4)
		_colors.resize(count * 4)
		_indices.resize(count * 6)
	var v: int = 0
	var t: int = 0
	for scrap in scraps:
		var u: Vector2 = Vector2.RIGHT.rotated(scrap.angle) * (scrap.size * 0.5)
		var w := Vector2(-u.y, u.x)
		_points[v] = scrap.pos - u - w
		_points[v + 1] = scrap.pos + u - w
		_points[v + 2] = scrap.pos + u + w
		_points[v + 3] = scrap.pos - u + w
		var color: Color = COL_SKIN if scrap.layer == TissueGrid.SKIN else COL_MUSCLE
		for k in 4:
			_colors[v + k] = color
		_indices[t] = v
		_indices[t + 1] = v + 1
		_indices[t + 2] = v + 2
		_indices[t + 3] = v
		_indices[t + 4] = v + 2
		_indices[t + 5] = v + 3
		v += 4
		t += 6
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)
