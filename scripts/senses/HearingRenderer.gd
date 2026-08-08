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
const PIGMENT_SHADER: String = "res://shaders/smell.gdshader"

var senses: CreatureSenses


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
	queue_redraw()


func _draw() -> void:
	if senses == null or senses.hearing == null:
		return
	var hearing: HearingSense = senses.hearing
	var field: SoundField = hearing.field
	var profile: HearingProfile = hearing.profile
	if field == null or profile == null or field.waves.is_empty():
		return

	var canvas: Transform2D = get_viewport().get_canvas_transform()
	var inverse: Transform2D = canvas.affine_inverse()
	var screen_size: Vector2 = get_viewport_rect().size
	draw_set_transform_matrix(inverse)

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
		_draw_wave(wave, field, profile, canvas, t, radius_world)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_wave(wave: SoundField.SoundWave, field: SoundField,
		profile: HearingProfile, canvas: Transform2D, t: float,
		radius_world: float) -> void:
	var count: int = maxi(1, roundi(float(profile.base_dot_count)
		+ wave.amplitude * profile.amplitude_dot_gain))
	var envelope: float = minf(1.0, t / maxf(profile.fade_in_fraction, 0.001)) \
		* pow(maxf(0.0, 1.0 - t), profile.dissolve_power)
	var base_alpha: float = (profile.base_opacity
		+ wave.amplitude * profile.amplitude_opacity_gain) * envelope \
		* profile.layer_opacity

	for i in count:
		var seed: float = _hash01(wave.visual_seed + float(i) * 0.754877666)
		var angular: float = _hash01(seed + 19.17)
		var survival: float = lerpf(profile.survival_floor, 1.0,
			_hash01(seed + 41.73))
		if t >= survival:
			continue
		var alpha: float = base_alpha * minf(1.0,
			(survival - t) / maxf(profile.dot_fade_fraction, 0.001))
		var angle: float = TAU * float(i) / float(count) \
			+ (angular - 0.5) * profile.angular_jitter * TAU / float(count)
		var direction := Vector2(cos(angle), sin(angle))
		var stop: float = field.blocking_distance(wave.origin, direction, wave.reach,
			wave.source_id)
		var travel: float = minf(radius_world, stop)
		if radius_world > stop + 0.001:
			var hit_t: float = pow(clampf(stop / maxf(wave.reach, 0.001), 0.0, 1.0),
				1.0 / SoundField.PROPAGATION_CURVE)
			alpha *= clampf(1.0 - (t - hit_t)
				/ maxf(profile.obstacle_fade_fraction, 0.001), 0.0, 1.0)
		if alpha <= MIN_ALPHA:
			continue

		var at_screen: Vector2 = canvas * (wave.origin + direction * travel)
		var jitter_px: float = (_hash01(seed + 73.91) - 0.5) * profile.radial_jitter_px
		at_screen += direction * jitter_px
		var dot_radius: float = profile.dot_radius_px \
			+ _hash01(seed + 97.31) * profile.dot_radius_spread_px
		draw_circle(at_screen, dot_radius, Color(profile.ink, alpha), true, -1.0, true)


## Stable pseudo-random scalar. It gives a wave organic imperfections without
## storing particle objects or letting any choice drift between frames.
func _hash01(value: float) -> float:
	return fposmod(sin(value * 91.3458 + 17.123) * 47453.5453, 1.0)
