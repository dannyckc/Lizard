## Particulate presentation of the world state resolved by one HearingSense.
##
## Every sound is one thin coherent circular wavefront. Dots keep their angular
## order, grow sparse by dropping out, and fade as ink. A ray that meets solid
## habitat geometry stops on that boundary and dissolves there, leaving a clean
## acoustic shadow instead of passing through the obstacle unchanged.
class_name HearingRenderer
extends Node2D

@export var senses_path: NodePath
## Above SightRenderer and below SmellRenderer / the controlled CreatureView.
@export var effect_z_index: int = 6

const MIN_ALPHA: float = 0.012
const CULL_MARGIN: float = 20.0
const DOT_AA_MARGIN: float = 0.75
const PIGMENT_SHADER: String = "res://shaders/hearing.gdshader"


## Everything arbitrary about a wave particle is fixed for the wave's lifetime.
## Keeping it here avoids re-running five hashes, trigonometry and angular setup
## for hundreds of identical particles on every frame.
class WaveVisual extends RefCounted:
	var directions := PackedVector2Array()
	var survivals := PackedFloat32Array()
	var radial_jitters := PackedFloat32Array()
	var radii := PackedFloat32Array()
	var stops := PackedFloat32Array()

var senses: CreatureSenses
var _wave_visuals: Dictionary = {}

## One triangle array replaces hundreds of individual draw_circle commands.
var _points := PackedVector2Array()
var _colours := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _vertex_count: int = 0
var _index_count: int = 0


func _ready() -> void:
	z_index = effect_z_index
	if not senses_path.is_empty():
		senses = get_node_or_null(senses_path) as CreatureSenses
	var pigment := ShaderMaterial.new()
	pigment.shader = load(PIGMENT_SHADER) as Shader
	material = pigment
	queue_redraw()


func _process(_delta: float) -> void:
	visible = senses != null and senses.hearing != null \
		and senses.hearing.profile != null and senses.hearing.field != null
	if visible:
		queue_redraw()


func refresh_profile() -> void:
	_wave_visuals.clear()
	queue_redraw()


func _draw() -> void:
	if senses == null or senses.hearing == null:
		return
	var hearing: HearingSense = senses.hearing
	var field: SoundField = hearing.field
	var profile: HearingProfile = hearing.profile
	if field == null or profile == null:
		return
	if field.waves.is_empty():
		_wave_visuals.clear()
		return

	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var inverse: Transform2D = canvas.affine_inverse()
	var screen_size: Vector2 = get_viewport_rect().size
	draw_set_transform_matrix(inverse)
	_prune_visuals(field.waves)

	var capacity: int = 0
	for wave in field.waves:
		capacity += _visual_for(wave, profile).directions.size()
	_prepare_mesh(capacity)

	for wave in field.waves:
		var t: float = wave.age / maxf(wave.life, 0.001)
		if t >= 1.0:
			continue
		var radius_world: float = field.radius(wave)
		var centre_screen: Vector2 = canvas * wave.origin
		var edge_screen: Vector2 = canvas * (wave.origin + Vector2.RIGHT * radius_world)
		var radius_screen: float = centre_screen.distance_to(edge_screen)
		if centre_screen.x + radius_screen < -CULL_MARGIN \
				or centre_screen.y + radius_screen < -CULL_MARGIN \
				or centre_screen.x - radius_screen > screen_size.x + CULL_MARGIN \
				or centre_screen.y - radius_screen > screen_size.y + CULL_MARGIN:
			continue
		_append_wave(wave, field, profile, canvas, t, radius_world)
	_flush_mesh()
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _append_wave(wave: SoundField.SoundWave, field: SoundField,
		profile: HearingProfile, canvas: Transform2D, t: float,
		radius_world: float) -> void:
	var visual: WaveVisual = _visual_for(wave, profile)
	# A sound carries the obstacle silhouette it met when emitted. Besides being
	# stable visually, this makes occlusion a one-time wave setup rather than
	# hundreds of polygon ray tests on every rendered frame.
	if visual.stops.is_empty():
		visual.stops = field.blocking_distances(wave.origin, visual.directions,
			wave.reach, wave.source_id)
	var count: int = visual.directions.size()
	var envelope: float = minf(1.0, t / maxf(profile.fade_in_fraction, 0.001)) \
		* pow(maxf(0.0, 1.0 - t), profile.dissolve_power)
	var base_alpha: float = (profile.base_opacity
		+ wave.amplitude * profile.amplitude_opacity_gain) * envelope \
		* profile.layer_opacity

	for i in count:
		var survival: float = visual.survivals[i]
		if t >= survival:
			continue
		var alpha: float = base_alpha * minf(1.0,
			(survival - t) / maxf(profile.dot_fade_fraction, 0.001))
		var direction: Vector2 = visual.directions[i]
		var stop: float = visual.stops[i]
		var travel: float = minf(radius_world, stop)
		if radius_world > stop + 0.001:
			var hit_t: float = pow(clampf(stop / maxf(wave.reach, 0.001), 0.0, 1.0),
				1.0 / SoundField.PROPAGATION_CURVE)
			alpha *= clampf(1.0 - (t - hit_t)
				/ maxf(profile.obstacle_fade_fraction, 0.001), 0.0, 1.0)
		if alpha <= MIN_ALPHA:
			continue

		var at_screen: Vector2 = canvas * (wave.origin + direction * travel)
		at_screen += direction * visual.radial_jitters[i]
		_append_dot(at_screen, visual.radii[i], Color(profile.ink, alpha))


func _visual_for(wave: SoundField.SoundWave, profile: HearingProfile) -> WaveVisual:
	if _wave_visuals.has(wave.id):
		return _wave_visuals[wave.id] as WaveVisual
	var visual := WaveVisual.new()
	var count: int = maxi(1, roundi(float(profile.base_dot_count)
		+ wave.amplitude * profile.amplitude_dot_gain))
	visual.directions.resize(count)
	visual.survivals.resize(count)
	visual.radial_jitters.resize(count)
	visual.radii.resize(count)
	for i in count:
		var seed: float = _hash01(wave.visual_seed + float(i) * 0.754877666)
		var angular: float = _hash01(seed + 19.17)
		var angle: float = TAU * float(i) / float(count) \
			+ (angular - 0.5) * profile.angular_jitter * TAU / float(count)
		visual.directions[i] = Vector2(cos(angle), sin(angle))
		visual.survivals[i] = lerpf(profile.survival_floor, 1.0,
			_hash01(seed + 41.73))
		visual.radial_jitters[i] = (_hash01(seed + 73.91) - 0.5) \
			* profile.radial_jitter_px
		visual.radii[i] = profile.dot_radius_px \
			+ _hash01(seed + 97.31) * profile.dot_radius_spread_px
	_wave_visuals[wave.id] = visual
	return visual


func _prune_visuals(waves: Array[SoundField.SoundWave]) -> void:
	var live: Dictionary = {}
	for wave in waves:
		live[wave.id] = true
	for wave_id in _wave_visuals.keys():
		if not live.has(wave_id):
			_wave_visuals.erase(wave_id)


func _prepare_mesh(dot_capacity: int) -> void:
	_vertex_count = 0
	_index_count = 0
	_points.resize(dot_capacity * 4)
	_colours.resize(dot_capacity * 4)
	_uvs.resize(dot_capacity * 4)
	_indices.resize(dot_capacity * 6)


func _append_dot(center: Vector2, radius: float, colour: Color) -> void:
	var extent: float = radius + DOT_AA_MARGIN
	var uv_extent: float = extent / maxf(radius, 0.2)
	var v: int = _vertex_count
	var t: int = _index_count
	_points[v] = center + Vector2(-extent, -extent)
	_points[v + 1] = center + Vector2(extent, -extent)
	_points[v + 2] = center + Vector2(extent, extent)
	_points[v + 3] = center + Vector2(-extent, extent)
	_uvs[v] = Vector2(-uv_extent, -uv_extent)
	_uvs[v + 1] = Vector2(uv_extent, -uv_extent)
	_uvs[v + 2] = Vector2(uv_extent, uv_extent)
	_uvs[v + 3] = Vector2(-uv_extent, uv_extent)
	for k in 4:
		_colours[v + k] = colour
	_indices[t] = v
	_indices[t + 1] = v + 1
	_indices[t + 2] = v + 2
	_indices[t + 3] = v
	_indices[t + 4] = v + 2
	_indices[t + 5] = v + 3
	_vertex_count += 4
	_index_count += 6


func _flush_mesh() -> void:
	if _index_count == 0:
		return
	_points.resize(_vertex_count)
	_colours.resize(_vertex_count)
	_uvs.resize(_vertex_count)
	_indices.resize(_index_count)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colours, _uvs)


## Stable pseudo-random scalar. It gives a wave organic imperfections without
## storing particle objects or letting any choice drift between frames.
func _hash01(value: float) -> float:
	return fposmod(sin(value * 91.3458 + 17.123) * 47453.5453, 1.0)
