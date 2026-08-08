## Focused contract test for the first SENSES layer.
##
## Checks the gameplay-facing sight field independently from its shader, then
## verifies scene ordering and the species/full-reset integration around it.
##
##   godot --headless --path . --script tests/SightTest.gd
extends SceneTree

var failures: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true

	var senses: CreatureSenses = main.senses
	var sight: SightSense = senses.sight if senses != null else null
	_check(senses != null, "controlled creature has no SENSES component")
	_check(sight != null, "SENSES component did not register sight")
	_check(senses.layer(&"sight") == sight, "sight is not an independent perception layer")
	if sight == null:
		_finish()
		return false

	_check(sight.origin().is_equal_approx(main.creature.body.head.pos),
		"sight does not originate at the solved head")
	_check(sight.direction().is_equal_approx(main.creature.head_look_dir.normalized()),
		"sight does not follow the articulated look direction")

	var origin: Vector2 = sight.origin()
	var forward: Vector2 = sight.direction()
	var close_ahead: float = sight.clarity_at(origin + forward * 90.0)
	var far_ahead: float = sight.clarity_at(origin + forward * 900.0)
	var behind: float = sight.clarity_at(origin - forward * 260.0)
	_check(close_ahead > 0.75, "near forward sight is not clear")
	_check(close_ahead > far_ahead, "sight does not resolve with distance")
	_check(close_ahead > behind, "sight does not favor look direction")

	var player_view: CreatureView = main.view
	var target_view: CreatureView = main.target_view
	var renderer: SightRenderer = main.sight_renderer
	_check(target_view.z_index < renderer.z_index,
		"ambient creature is not included in sight treatment")
	_check(renderer.z_index < player_view.z_index,
		"player creature is not kept crisp above sight treatment")
	_check(renderer.senses == senses, "SightRenderer is not consuming the creature component")
	# Canvas-item stretch and embedded play can render a logical viewport into a
	# much larger physical target. The shader must receive normalized coordinates;
	# passing this same position as logical pixels made the field shrink and drift
	# whenever the embedded resolution increased.
	renderer._process(0.0)
	var sight_material := renderer.material as ShaderMaterial
	var visible_rect: Rect2 = renderer.get_viewport().get_visible_rect()
	var origin_screen: Vector2 = renderer.get_viewport().get_canvas_transform() * sight.origin()
	var expected_uv: Vector2 = (origin_screen - visible_rect.position) / visible_rect.size
	_check(sight_material != null, "SightRenderer has no shader material")
	if sight_material != null:
		var actual_uv: Vector2 = sight_material.get_shader_parameter("sight_origin_uv")
		var shader_viewport_size: Vector2 = sight_material.get_shader_parameter("viewport_size")
		_check(actual_uv.is_equal_approx(expected_uv),
			"SIGHT eye position is not normalized to the logical viewport")
		_check(shader_viewport_size.is_equal_approx(visible_rect.size),
			"SIGHT shader does not use the logical viewport dimensions")
	var species_profile := SightProfile.new()
	species_profile.clear_reach = 444.0
	senses.set_sight_profile(species_profile)
	_check(sight.profile == species_profile and sight.profile.clear_reach == 444.0,
		"a species-specific sight profile cannot replace the default")

	main.hud.select_species("Gecko")
	_check(senses.active_species == "Gecko", "species change did not reset SENSES")
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.pressed = true
	main._unhandled_input(reset)
	_check(senses.active_species == "Gecko", "full reset lost the active sight species")
	_check(sight.origin().is_equal_approx(main.creature.body.head.pos),
		"sight did not follow the head after reset")

	_finish()
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("sight OK — perception, rendering order and reset flow are independent")
		quit(0)
	else:
		for failure in failures:
			print("SIGHT FAIL — ", failure)
		quit(1)
