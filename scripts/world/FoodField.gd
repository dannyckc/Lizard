## Scattered pellets that keep the world populated around the player and give
## the prototype something to do. Eating one increments Creature.food_eaten and
## nothing more: growth has been taken out until there is a real system for it,
## so food is currently a counter the HUD reads rather than an input to anything
## the creature does.
class_name FoodField
extends Node2D

@export var target_count: int = 46
@export var spawn_inner: float = 320.0
@export var spawn_outer: float = 1250.0
@export var cull_radius: float = 1900.0

## How high off the ground a pellet grows. Sampled per pellet between the two
## bounds below, so the field is a mix of things lying on the floor and things up
## in the air — and what an animal can eat becomes a question about how high it
## can get its mouth. This is the whole of "browsing": there is no second kind of
## food and no browse action, only forage that some animals cannot reach.
var heights: PackedFloat32Array = PackedFloat32Array()

@export var browse_low: float = 0.0
@export var browse_high: float = 130.0
## Share of the field that grows off the ground at all. The rest is forage a
## sprawled animal can walk over and eat, so the habitat is never closed to one.
@export_range(0.0, 1.0, 0.05) var browse_share: float = 0.35

var pellets: PackedVector2Array = PackedVector2Array()
var _phase: float = 0.0
var _rng := RandomNumberGenerator.new()

## How tall one pellet is. Small — it is a pellet — but not zero, so a mouth
## reaching to exactly the height it grows at can close on it.
const PELLET_THICKNESS: float = 8.0

const RING_SEGMENTS: int = 28
const CORE_SEGMENTS: int = 12
const RING_WIDTH: float = 1.0
const RING_COLOUR := Color(0.078, 0.078, 0.059, 0.26)
const CORE_COLOUR := Color("14140f")

## All pellets share one animated triangle array. The old arc/circle loop
## submitted two canvas commands per source on every frame; the scent field and
## the renderer now both treat food as cohorts.
var _points := PackedVector2Array()
var _colours := PackedColorArray()
var _indices := PackedInt32Array()
var _ring_directions := PackedVector2Array()
var _core_directions := PackedVector2Array()
var _topology_count: int = -1


func _ready() -> void:
	_rng.randomize()
	z_index = 1  # above Main's ground grid, below the creature
	_ring_directions.resize(RING_SEGMENTS)
	for k in RING_SEGMENTS:
		var angle: float = TAU * float(k) / float(RING_SEGMENTS)
		_ring_directions[k] = Vector2(cos(angle), sin(angle))
	_core_directions.resize(CORE_SEGMENTS)
	for k in CORE_SEGMENTS:
		var angle: float = TAU * float(k) / float(CORE_SEGMENTS)
		_core_directions[k] = Vector2(cos(angle), sin(angle))


## Culls pellets left far behind and tops the field back up in a ring ahead of
## and around `center`, so the player never walks into an empty world.
func refresh(center: Vector2) -> void:
	# `pellets` is written directly in several places — the world clears it on
	# reset, tests place them by hand — so the heights are reconciled to it here
	# rather than guarded at every call site. A disagreement means somebody
	# replaced the array, and there is then no way to tell which surviving height
	# belonged to which pellet: keeping them would silently hang a stale altitude
	# on a new pellet. So they all go back to the ground, which is both the honest
	# answer and the behaviour this field had before it had a vertical axis.
	if heights.size() != pellets.size():
		heights.resize(0)
		heights.resize(pellets.size())
	for i in range(pellets.size() - 1, -1, -1):
		if pellets[i].distance_to(center) > cull_radius:
			_forget(i)
	while pellets.size() < target_count:
		var angle: float = _rng.randf() * TAU
		var radius: float = lerpf(spawn_inner, spawn_outer, sqrt(_rng.randf()))
		pellets.append(center + Vector2.RIGHT.rotated(angle) * radius)
		heights.append(0.0 if _rng.randf() >= browse_share
			else lerpf(browse_low, browse_high, _rng.randf()))


## Removes every pellet within `radius` of `pos` that the mouth can also reach
## vertically, and returns how many were eaten.
##
## `reach` is the band the jaws cover — see Stature. Left unbounded, every pellet
## in range is eaten exactly as it always was, so nothing that does not know about
## height is affected by any of this.
func consume(pos: Vector2, radius: float, reach: Vector2 = Stature.UNBOUNDED) -> int:
	var eaten: int = 0
	var r2: float = radius * radius
	for i in range(pellets.size() - 1, -1, -1):
		if pellets[i].distance_squared_to(pos) > r2:
			continue
		var at: float = _height_of(i)
		if not Stature.overlaps(reach, Vector2(at, at + PELLET_THICKNESS)):
			continue
		_forget(i)
		eaten += 1
	return eaten


## How high a pellet is growing. A pellet with no recorded height is one on the
## ground — see the reconciliation in `refresh`.
func _height_of(index: int) -> float:
	return heights[index] if index < heights.size() else 0.0


func _forget(index: int) -> void:
	pellets.remove_at(index)
	if index < heights.size():
		heights.remove_at(index)


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	var count: int = pellets.size()
	if count == 0:
		return
	var verts_per_pellet: int = RING_SEGMENTS * 2 + CORE_SEGMENTS + 1
	if count != _topology_count:
		_prepare_topology(count)
	var vertex: int = 0
	for i in pellets.size():
		# Height reads the same way it does on a creature: the thing is drawn
		# lifted up the screen from where it actually stands. Same constant, so a
		# pellet growing level with a creature's mouth is drawn level with it.
		var p: Vector2 = pellets[i] - Vector2(0.0, _height_of(i) * Posture.PERSPECTIVE)
		# Food is an outlined specimen marker: a restrained breathing ring with an
		# ink core, rather than a gamey glowing collectible.
		var pulse: float = 1.0 + 0.12 * sin(_phase * 2.0 + float(i) * 1.7)
		var radius: float = 8.5 * pulse
		var inner: float = maxf(radius - RING_WIDTH, 0.0)
		for k in RING_SEGMENTS:
			var direction: Vector2 = _ring_directions[k]
			_points[vertex] = p + direction * inner
			_points[vertex + 1] = p + direction * radius
			vertex += 2

		_points[vertex] = p
		vertex += 1
		for k in CORE_SEGMENTS:
			_points[vertex] = p + _core_directions[k] * 2.6
			vertex += 1

	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colours)


func _prepare_topology(count: int) -> void:
	_topology_count = count
	var verts_per_pellet: int = RING_SEGMENTS * 2 + CORE_SEGMENTS + 1
	var indices_per_pellet: int = RING_SEGMENTS * 6 + CORE_SEGMENTS * 3
	_points.resize(count * verts_per_pellet)
	_colours.resize(count * verts_per_pellet)
	_indices.resize(count * indices_per_pellet)
	var vertex: int = 0
	var triangle: int = 0
	for _i in count:
		var ring_start: int = vertex
		for k in RING_SEGMENTS:
			_colours[vertex] = RING_COLOUR
			_colours[vertex + 1] = RING_COLOUR
			vertex += 2
		for k in RING_SEGMENTS:
			var here: int = ring_start + k * 2
			var next: int = ring_start + ((k + 1) % RING_SEGMENTS) * 2
			_indices[triangle] = here
			_indices[triangle + 1] = here + 1
			_indices[triangle + 2] = next + 1
			_indices[triangle + 3] = here
			_indices[triangle + 4] = next + 1
			_indices[triangle + 5] = next
			triangle += 6

		var core_start: int = vertex
		_colours[vertex] = CORE_COLOUR
		vertex += 1
		for _k in CORE_SEGMENTS:
			_colours[vertex] = CORE_COLOUR
			vertex += 1
		for k in CORE_SEGMENTS:
			_indices[triangle] = core_start
			_indices[triangle + 1] = core_start + k + 1
			_indices[triangle + 2] = core_start + ((k + 1) % CORE_SEGMENTS) + 1
			triangle += 3
