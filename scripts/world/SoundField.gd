## World-owned record of sounds currently travelling through the habitat.
##
## A sound is an event and a wavefront, not a visual particle effect. This node
## owns its physical origin, strength, travel and obstacle queries; HearingSense
## can therefore detect it without any renderer, while HearingRenderer is only
## one optional presentation of the same state.
class_name SoundField
extends Node

signal sound_emitted(wave: SoundWave)

enum Kind { STEP, BITE, FEED, IMPACT }

const MIN_AMPLITUDE: float = 0.05
const MAX_AMPLITUDE: float = 1.2
const MAX_SOUNDS: int = 8
const BASE_REACH: float = 70.0
const REACH_GAIN: float = 175.0
const BASE_LIFE: float = 0.95
const LIFE_GAIN: float = 0.95
const PROPAGATION_CURVE: float = 0.82
const RAY_EPSILON: float = 0.75


class SoundWave extends RefCounted:
	var id: int = 0
	var origin: Vector2 = Vector2.ZERO
	var amplitude: float = 0.0
	var kind: int = Kind.IMPACT
	var source_id: int = 0
	var age: float = 0.0
	var life: float = 1.0
	var reach: float = 1.0
	## One stable seed is enough for the renderer to derive every dot without
	## putting presentation data into the world's sound event.
	var visual_seed: float = 0.0


var waves: Array[SoundWave] = []
var elapsed: float = 0.0

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Announces a physical sound. Callers name the event and its source; they know
## nothing about listeners, profiles, particles or cameras.
func emit_sound(at: Vector2, amplitude: float, kind: int,
		source: Node = null) -> SoundWave:
	if amplitude < MIN_AMPLITUDE:
		return null
	var wave := SoundWave.new()
	wave.id = _next_id
	_next_id += 1
	wave.origin = at
	wave.amplitude = minf(amplitude, MAX_AMPLITUDE)
	wave.kind = kind
	wave.source_id = source.get_instance_id() if source != null else 0
	wave.life = BASE_LIFE + wave.amplitude * LIFE_GAIN
	wave.reach = BASE_REACH + wave.amplitude * REACH_GAIN
	wave.visual_seed = _rng.randf()
	waves.append(wave)
	if waves.size() > MAX_SOUNDS:
		waves.pop_front()
	sound_emitted.emit(wave)
	return wave


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	elapsed += delta
	for i in range(waves.size() - 1, -1, -1):
		var wave: SoundWave = waves[i]
		wave.age += delta
		if wave.age >= wave.life:
			waves.remove_at(i)


func clear() -> void:
	waves.clear()
	elapsed = 0.0


## Radius of one coherent wavefront. The curve is the design's near-constant
## propagation with a slight ease near the end, never a ballistic particle arc.
func radius(wave: SoundWave, life_fraction: float = -1.0) -> float:
	if wave == null:
		return 0.0
	var t: float = life_fraction
	if t < 0.0:
		t = wave.age / maxf(wave.life, 0.001)
	return wave.reach * pow(clampf(t, 0.0, 1.0), PROPAGATION_CURVE)


## Distance to the first solid boundary along a particle's route. Creature body
## silhouettes are current solved world geometry. Any future habitat obstacle can
## join `sound_obstacles` and expose `sound_outline() -> PackedVector2Array`.
func blocking_distance(from: Vector2, direction: Vector2, max_distance: float,
		ignore_source_id: int = 0, ignore_listener_id: int = 0) -> float:
	if max_distance <= 0.0 or direction.length_squared() <= 0.000001:
		return max_distance
	var ray: Vector2 = direction.normalized()
	var nearest: float = max_distance
	for polygon in _obstacle_outlines(ignore_source_id, ignore_listener_id):
		nearest = minf(nearest, _ray_polygon_distance(from, ray, nearest, polygon))
	return nearest


## Batched counterpart used by HearingRenderer. Fetching and allocating the
## obstacle outlines once per wave is much cheaper than repeating the scene-tree
## group queries for every one of its visual particles.
func blocking_distances(from: Vector2, directions: PackedVector2Array,
		max_distance: float, ignore_source_id: int = 0,
		ignore_listener_id: int = 0) -> PackedFloat32Array:
	var distances := PackedFloat32Array()
	distances.resize(directions.size())
	if max_distance <= 0.0:
		distances.fill(max_distance)
		return distances
	var outlines: Array = _obstacle_outlines(ignore_source_id, ignore_listener_id)
	for i in directions.size():
		var direction: Vector2 = directions[i]
		if direction.length_squared() <= 0.000001:
			distances[i] = max_distance
			continue
		var ray: Vector2 = direction.normalized()
		var nearest: float = max_distance
		for polygon in outlines:
			nearest = minf(nearest,
				_ray_polygon_distance(from, ray, nearest, polygon))
		distances[i] = nearest
	return distances


## Number of distinct solid bodies crossed by a direct source/listener path.
## HearingSense turns this physical answer into species-specific attenuation.
func occlusion_count(from: Vector2, to: Vector2, ignore_source_id: int = 0,
		ignore_listener_id: int = 0) -> int:
	if from.distance_squared_to(to) <= 0.000001:
		return 0
	var count: int = 0
	for polygon in _obstacle_outlines(ignore_source_id, ignore_listener_id):
		if _segment_hits_polygon(from, to, polygon):
			count += 1
	return count


func _obstacle_outlines(ignore_source_id: int, ignore_listener_id: int) -> Array:
	var outlines: Array = []
	if not is_inside_tree():
		return outlines
	for node in get_tree().get_nodes_in_group("creatures"):
		if node.get_instance_id() == ignore_source_id \
				or node.get_instance_id() == ignore_listener_id:
			continue
		var creature := node as Creature
		if creature != null and creature.body != null and creature.body.outline.size() >= 3:
			outlines.append(creature.body.outline)
	for node in get_tree().get_nodes_in_group("sound_obstacles"):
		if node.get_instance_id() == ignore_source_id \
				or node.get_instance_id() == ignore_listener_id \
				or not node.has_method("sound_outline"):
			continue
		var outline: Variant = node.sound_outline()
		if outline is PackedVector2Array and outline.size() >= 3:
			outlines.append(outline)
	return outlines


func _ray_polygon_distance(origin: Vector2, direction: Vector2, max_distance: float,
		polygon: PackedVector2Array) -> float:
	var nearest: float = max_distance
	for i in polygon.size():
		var hit: float = _ray_segment_distance(origin, direction, nearest,
			polygon[i], polygon[(i + 1) % polygon.size()])
		nearest = minf(nearest, hit)
	return nearest


func _ray_segment_distance(origin: Vector2, direction: Vector2, max_distance: float,
		a: Vector2, b: Vector2) -> float:
	var edge: Vector2 = b - a
	var denominator: float = direction.cross(edge)
	if absf(denominator) <= 0.000001:
		return max_distance
	var offset: Vector2 = a - origin
	var along: float = offset.cross(edge) / denominator
	var across: float = offset.cross(direction) / denominator
	if along > RAY_EPSILON and along < max_distance and across >= 0.0 and across <= 1.0:
		return along
	return max_distance


func _segment_hits_polygon(from: Vector2, to: Vector2,
		polygon: PackedVector2Array) -> bool:
	var delta: Vector2 = to - from
	var distance: float = delta.length()
	if distance <= 0.000001:
		return false
	var direction: Vector2 = delta / distance
	return _ray_polygon_distance(from, direction, distance, polygon) < distance
