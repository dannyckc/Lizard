## Screen-space presentation of one SightSense.
##
## This node deliberately sits outside the creature and below its view in canvas
## order. It resolves the habitat already drawn beneath it, while the controlled
## creature and HUD remain crisp above it. It never answers detection questions;
## SightSense owns that gameplay-facing API.
class_name SightRenderer
extends Node2D

@export var senses_path: NodePath
@export var effect_z_index: int = 5

var senses: CreatureSenses
var _shader_material: ShaderMaterial
var _elapsed: float = 0.0


func _ready() -> void:
	z_index = effect_z_index
	if not senses_path.is_empty():
		senses = get_node_or_null(senses_path) as CreatureSenses
	if senses != null:
		senses.sight_profile_changed.connect(_on_sight_profile_changed)
	_shader_material = ShaderMaterial.new()
	# Load only when a renderer exists. Pure simulation tests and server builds can
	# use SightSense without asking a graphics backend to compile presentation.
	_shader_material.shader = load("res://shaders/sight.gdshader") as Shader
	material = _shader_material
	_apply_profile()
	queue_redraw()


func _process(delta: float) -> void:
	if senses == null or senses.sight == null or senses.sight.profile == null:
		visible = false
		return
	visible = true
	_elapsed += delta
	var viewport := get_viewport()
	var canvas_transform: Transform2D = viewport.get_canvas_transform()
	var visible_rect: Rect2 = viewport.get_visible_rect()
	var origin_world: Vector2 = senses.sight.origin()
	var direction_world: Vector2 = senses.sight.direction()
	var origin_screen: Vector2 = canvas_transform * origin_world
	var direction_screen: Vector2 = (canvas_transform * (origin_world + direction_world)) - origin_screen
	var unit_x: Vector2 = (canvas_transform * (origin_world + Vector2.RIGHT)) - origin_screen
	var unit_y: Vector2 = (canvas_transform * (origin_world + Vector2.DOWN)) - origin_screen
	var pixels_per_world: float = (unit_x.length() + unit_y.length()) * 0.5
	var creature: Creature = senses.sight.creature
	var speed_gain: float = 1.0 + minf(1.0, absf(creature.speed) / 190.0) \
		* senses.sight.profile.motion_reach_gain

	# SCREEN_UV belongs to the render target, while the canvas transform is in
	# logical viewport coordinates. Embedded play and canvas-item stretching can
	# render those logical coordinates at a much larger physical resolution. A
	# pixel-space uniform therefore drifts and shrinks SIGHT as the window grows.
	# Express the eye in normalized viewport space and let the shader convert UV
	# deltas back through the same logical viewport dimensions instead.
	var viewport_size: Vector2 = visible_rect.size
	var sight_origin_uv: Vector2 = (origin_screen - visible_rect.position) / viewport_size
	_shader_material.set_shader_parameter("sight_origin_uv", sight_origin_uv)
	_shader_material.set_shader_parameter("viewport_size", viewport_size)
	_shader_material.set_shader_parameter("sight_direction", direction_screen.normalized())
	_shader_material.set_shader_parameter("pixels_per_world", pixels_per_world * creature.size_scale)
	_shader_material.set_shader_parameter("time_seconds", _elapsed)
	_shader_material.set_shader_parameter("clear_reach", senses.sight.profile.clear_reach * speed_gain)
	_shader_material.set_shader_parameter("peripheral_reach", senses.sight.profile.peripheral_reach * speed_gain)
	queue_redraw()


func refresh_profile() -> void:
	_apply_profile()


func _on_sight_profile_changed(_profile: SightProfile) -> void:
	_apply_profile()


func _apply_profile() -> void:
	if _shader_material == null or senses == null or senses.sight == null \
		or senses.sight.profile == null:
		return
	var profile: SightProfile = senses.sight.profile
	_shader_material.set_shader_parameter("clear_reach", profile.clear_reach)
	_shader_material.set_shader_parameter("clear_width", profile.clear_width)
	_shader_material.set_shader_parameter("clear_near_radius", profile.clear_near_radius)
	_shader_material.set_shader_parameter("peripheral_reach", profile.peripheral_reach)
	_shader_material.set_shader_parameter("peripheral_width", profile.peripheral_width)
	_shader_material.set_shader_parameter("peripheral_near_radius", profile.peripheral_near_radius)
	_shader_material.set_shader_parameter("unseen_blur_lod", profile.unseen_blur_lod)
	_shader_material.set_shader_parameter("peripheral_blur_lod", profile.peripheral_blur_lod)
	_shader_material.set_shader_parameter("unseen_desaturation", profile.unseen_desaturation)
	_shader_material.set_shader_parameter("unseen_contrast", profile.unseen_contrast)
	_shader_material.set_shader_parameter("peripheral_desaturation", profile.peripheral_desaturation)
	_shader_material.set_shader_parameter("peripheral_contrast", profile.peripheral_contrast)
	_shader_material.set_shader_parameter("paper_wash", profile.paper_wash)
	_shader_material.set_shader_parameter("peripheral_opacity", profile.peripheral_opacity)
	_shader_material.set_shader_parameter("unresolved_paper", profile.unresolved_paper)


func _draw() -> void:
	# Convert the four viewport corners back into world coordinates. Drawing the
	# resulting polygon in the normal world canvas preserves ordering with food,
	# carcasses and the player while SCREEN_UV keeps the shader screen-aligned at
	# every camera position and zoom level.
	var size: Vector2 = get_viewport_rect().size
	var inverse: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var corners := PackedVector2Array([
		inverse * Vector2.ZERO,
		inverse * Vector2(size.x, 0.0),
		inverse * size,
		inverse * Vector2(0.0, size.y),
	])
	draw_colored_polygon(corners, Color.WHITE)
