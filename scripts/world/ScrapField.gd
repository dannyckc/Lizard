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

## Hard ceiling on live chunks. Cells from one tear are coalesced before they
## arrive here, so this is a ceiling on pieces of meat rather than pixels.
const MAX_SCRAPS: int = 96
## Velocity retained per second while a chunk is still flying.
const DRAG: float = 8.5
## Below this speed a chunk is considered to have come to rest, and stops
## costing anything but a draw.
const SETTLE_SPEED: float = 5.0

const BLOB_VERTS: int = 10
const COL_SKIN := Color("211c17")
## Torn fat. Pale and grainless, the same tone it has in the body it came out of,
## so a piece of a well-padded animal is recognisable as such where it lands.
const COL_FAT := Color("e0cfa8")
const COL_MUSCLE := Color("9c3b26")
const COL_MUSCLE_DEEP := Color("5f2114")
const COL_SHADOW := Color("14140f", 0.075)


class Scrap extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var angle: float = 0.0
	var spin: float = 0.0
	var size: float = 3.0
	var mass: float = 9.0
	var aspect: float = 1.2
	var layer: int = 0
	var settled: bool = false
	## Stable irregular radii for the organic outline. Generated once, never per
	## draw, so a resting piece keeps its shape.
	var shape := PackedFloat32Array()
	## Instance id of the creature this came off, held as an id rather than a
	## reference so a scrap can outlive its former owner.
	var source_id: int = 0


var scraps: Array[Scrap] = []

var _rng := RandomNumberGenerator.new()
## Reused geometry, so drawing a full field allocates nothing per frame.
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _flat := PackedColorArray([COL_SHADOW])
var _strand_points := PackedVector2Array()


func _ready() -> void:
	_rng.randomize()
	z_index = 2  # above the food pellets, below the creatures


## Pulls a bite's worth of shed tissue a short distance outward from `origin`.
## Broad pieces carry more inertia and barely tumble; this is a heavy tear, not
## a particle spray.
##
## `source_id` is the creature it came off, which is the one creature that may not
## then eat it. An id rather than a reference because meat outlives the animal it
## was, and because by the time some of it arrives here it has been chewed off a
## severed leg that was itself lying in a third creature's mouth — whose flesh it
## is has not changed through any of that.
func scatter(chunks: Array, origin: Vector2, source_id: int) -> void:
	for chunk in chunks:
		var scrap := Scrap.new()
		scrap.pos = chunk.pos
		scrap.size = chunk.size
		scrap.mass = chunk.mass
		scrap.aspect = chunk.aspect
		scrap.layer = chunk.layer
		scrap.source_id = source_id
		var away: Vector2 = chunk.pos - origin
		var dir: Vector2 = away.normalized() if away.length_squared() > 1.0 \
			else Vector2.RIGHT.rotated(_rng.randf() * TAU)
		var weight: float = clampf(8.0 / maxf(scrap.size, 8.0), 0.34, 1.0)
		var impulse: float = _rng.randf_range(42.0, 88.0) * weight
		if scrap.layer == TissueGrid.MUSCLE:
			impulse *= 0.78
		scrap.vel = dir.rotated(_rng.randfn(0.0, 0.18)) * impulse
		scrap.angle = chunk.angle + _rng.randfn(0.0, 0.16)
		scrap.spin = _rng.randfn(0.0, 2.1) * weight
		scrap.shape.resize(BLOB_VERTS)
		for k in BLOB_VERTS:
			scrap.shape[k] = _rng.randf_range(0.86, 1.10)
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


## Drawn as weighty irregular blobs whose area matches the joined tissue cells.
## A subtle shadow anchors each piece and muscle retains visible longitudinal
## grain after it is severed.
func _draw() -> void:
	var count: int = scraps.size()
	if count == 0:
		return
	var points_per_blob: int = BLOB_VERTS + 1  # centre + perimeter
	if _points.size() != count * points_per_blob:
		_points.resize(count * points_per_blob)
		_colors.resize(count * points_per_blob)
		_indices.resize(count * BLOB_VERTS * 3)
	var v: int = 0
	var t: int = 0
	for scrap in scraps:
		var major: float = sqrt(scrap.aspect)
		var minor: float = 1.0 / major
		var radius: float = scrap.size * 0.5
		var color: Color = _scrap_color(scrap.layer)
		_points[v] = scrap.pos
		_colors[v] = color
		for k in BLOB_VERTS:
			var theta: float = TAU * float(k) / float(BLOB_VERTS)
			var local := Vector2(cos(theta) * major, sin(theta) * minor) \
				* (radius * scrap.shape[k])
			_points[v + k + 1] = scrap.pos + local.rotated(scrap.angle)
			_colors[v + k + 1] = color
		for k in BLOB_VERTS:
			_indices[t] = v
			_indices[t + 1] = v + k + 1
			_indices[t + 2] = v + ((k + 1) % BLOB_VERTS) + 1
			t += 3
		v += points_per_blob

	draw_set_transform(Vector2(0.0, 2.5), 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _flat)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)

	# A few uninterrupted strands sell muscle density without outlining the
	# polygon or revealing the simulation cells that made it. All disconnected
	# strands share one canvas command; a tear no longer adds three draw calls per
	# muscle piece on its first visible frame.
	_strand_points.clear()
	for scrap in scraps:
		if scrap.layer != TissueGrid.MUSCLE:
			continue
		var axis: Vector2 = Vector2.RIGHT.rotated(scrap.angle)
		var across := Vector2(-axis.y, axis.x)
		var half_length: float = scrap.size * sqrt(scrap.aspect) * 0.29
		var spacing: float = scrap.size / sqrt(scrap.aspect) * 0.12
		for strand in range(-1, 2):
			var offset: Vector2 = across * (float(strand) * spacing)
			_strand_points.append(scrap.pos - axis * half_length + offset)
			_strand_points.append(scrap.pos + axis * half_length + offset)
	if not _strand_points.is_empty():
		draw_multiline(_strand_points, COL_MUSCLE_DEEP, 0.8, true)


## Meat looks like what it was cut from. Only the layers that actually come away
## in pieces reach here — bone is ground down in place and an organ is pulped
## where it lies — so the three that do get their own tone.
static func _scrap_color(layer: int) -> Color:
	match layer:
		TissueGrid.SKIN: return COL_SKIN
		TissueGrid.FAT: return COL_FAT
		_: return COL_MUSCLE
