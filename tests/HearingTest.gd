## Focused contract test for the third SENSES layer.
##
## Checks sound as world state, creature-specific arrival/detection, physical
## occlusion, the coherent-ring rendering contract, event wiring and resets.
##
##   godot --headless --path . --script tests/HearingTest.gd
extends SceneTree

var failures: PackedStringArray = PackedStringArray()
var main: Node


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	call_deferred("_run")


func _run() -> void:
	var senses: CreatureSenses = main.senses
	var hearing: HearingSense = senses.hearing if senses != null else null
	var field: SoundField = main.sound_field
	_check(hearing != null, "SENSES component did not register hearing")
	_check(senses.layer(&"hearing") == hearing,
		"hearing is not an independent perception layer")
	_check(senses.layer(&"sight") == senses.sight and senses.layer(&"smell") == senses.smell,
		"registering hearing disturbed sight or smell")
	if hearing == null or field == null:
		_finish()
		return

	_check(hearing.field == field, "hearing is not reading the habitat's sound field")
	_check(hearing.origin().is_equal_approx(main.creature.body.head.pos),
		"hearing does not follow the solved head")
	_world_wave(field)
	_arrival_and_profile(senses, hearing, field)
	_occlusion(hearing, field)
	_layering(senses)
	_events_and_reset(senses, field)
	_finish()


func _world_wave(field: SoundField) -> void:
	field.clear()
	var quiet = field.emit_sound(Vector2.ZERO, SoundField.MIN_AMPLITUDE * 0.5,
		SoundField.Kind.IMPACT)
	_check(quiet == null and field.waves.is_empty(),
		"inaudible noise still creates a visual/world event")
	var wave := field.emit_sound(Vector2(20.0, 30.0), 0.6, SoundField.Kind.IMPACT)
	_check(wave != null and field.waves.size() == 1, "a sound event made no wave")
	if wave == null:
		return
	_check(wave.origin == Vector2(20.0, 30.0) and wave.kind == SoundField.Kind.IMPACT,
		"sound lost its physical source or kind")
	var r0: float = field.radius(wave)
	field.advance(wave.life * 0.35)
	var r1: float = field.radius(wave)
	field.advance(wave.life * 0.25)
	var r2: float = field.radius(wave)
	_check(r0 < r1 and r1 < r2 and r2 < wave.reach,
		"wavefront does not expand smoothly at one coherent radius")
	field.advance(wave.life)
	_check(field.waves.is_empty(), "a spent sound never leaves the habitat")
	for i in SoundField.MAX_SOUNDS + 4:
		field.emit_sound(Vector2(float(i), 0.0), 0.2, SoundField.Kind.STEP)
	_check(field.waves.size() == SoundField.MAX_SOUNDS,
		"the live sound field can grow without bound")


func _arrival_and_profile(senses: CreatureSenses, hearing: HearingSense,
		field: SoundField) -> void:
	field.clear()
	hearing.reset()
	var listener: Vector2 = hearing.origin()
	var source: Vector2 = listener + Vector2(100.0, 0.0)
	var wave := field.emit_sound(source, 1.0, SoundField.Kind.FEED)
	hearing.advance(0.01)
	_check(hearing.heard_sounds.is_empty(),
		"hearing detected a sound before its wavefront arrived")
	field.advance(wave.life * 0.55)
	hearing.advance(0.01)
	_check(not hearing.heard_sounds.is_empty(),
		"an audible wave reached the creature without being detected")
	if not hearing.heard_sounds.is_empty():
		var read: HearingSense.HeardSound = hearing.heard_sounds[0]
		_check(read.kind == SoundField.Kind.FEED and read.strength > 0.0,
			"the gameplay read lost the sound's kind or strength")
		_check(read.direction.dot(Vector2.RIGHT) > 0.99,
			"hearing did not localise the source")

	var near_strength: float = hearing.strength_at(listener + Vector2(30.0, 0.0))
	var far_strength: float = hearing.strength_at(listener + Vector2(220.0, 0.0))
	_check(near_strength > far_strength and far_strength > 0.0,
		"hearing strength does not resolve with distance")
	_check(hearing.strength_at(listener + Vector2(hearing.profile.reach + 1.0, 0.0)) == 0.0,
		"hearing reads past its configured reach")

	var species_profile := HearingProfile.new()
	species_profile.reach = 123.0
	species_profile.sensitivity = 1.7
	senses.set_hearing_profile(species_profile)
	_check(senses.hearing.profile == species_profile and senses.hearing.profile.reach == 123.0,
		"a species-specific hearing profile cannot replace the default")
	senses.set_hearing_profile(HearingProfile.new())


func _occlusion(hearing: HearingSense, field: SoundField) -> void:
	field.clear()
	hearing.reset()
	var listener: Vector2 = hearing.origin()
	# Lay the carcass across the direct route. It is real solved body geometry,
	# not a renderer mask created just for the test.
	main.target_creature.reset(listener + Vector2(90.0, 0.0), PI * 0.5)
	var source: Vector2 = listener + Vector2(180.0, 0.0)
	var blockers: int = field.occlusion_count(source, listener, 0,
		main.creature.get_instance_id())
	_check(blockers > 0, "a solid creature does not occlude sound")
	var clear_strength: float = _unoccluded_strength(hearing, source)
	var occluded_strength: float = hearing.strength_at(source)
	_check(occluded_strength < clear_strength * 0.5,
		"obstacle did not materially weaken the gameplay-facing sound")
	var stop: float = field.blocking_distance(source, Vector2.LEFT, 180.0)
	_check(stop > 0.0 and stop < source.distance_to(listener),
		"wave particles have no physical stopping boundary on an obstacle")
	var directions := PackedVector2Array([Vector2.LEFT, Vector2.UP, Vector2.RIGHT])
	var batched: PackedFloat32Array = field.blocking_distances(source, directions, 180.0)
	_check(batched.size() == directions.size(),
		"batched wave occlusion lost particle directions")
	for i in directions.size():
		_check(is_equal_approx(batched[i],
			field.blocking_distance(source, directions[i], 180.0)),
			"batched wave occlusion disagrees with the physical ray query")

	var wave := field.emit_sound(source, 1.0, SoundField.Kind.IMPACT)
	field.advance(wave.life * 0.7)
	hearing.advance(0.01)
	_check(not hearing.heard_sounds.is_empty() and hearing.heard_sounds[0].occluded,
		"an arrived sound behind cover is not marked as occluded")


func _unoccluded_strength(hearing: HearingSense, source: Vector2) -> float:
	var target: Creature = main.target_creature
	var old_position: Vector2 = target.head_pos
	var old_heading: float = target.heading
	target.reset(Vector2(5000.0, 5000.0), old_heading)
	var strength: float = hearing.strength_at(source)
	target.reset(old_position, old_heading)
	return strength


func _layering(senses: CreatureSenses) -> void:
	var renderer: HearingRenderer = main.hearing_renderer
	_check(renderer.senses == senses,
		"HearingRenderer is not consuming the creature component")
	_check(main.sight_renderer.z_index < renderer.z_index
		and renderer.z_index < main.smell_renderer.z_index,
		"hearing is not between the sight treatment and smell annotations")
	_check(renderer.z_index < main.view.z_index,
		"the controlled creature is not kept above its hearing layer")
	var pigment := renderer.material as ShaderMaterial
	_check(pigment != null and pigment.shader != null
		and pigment.shader.code.contains("blend_mul"),
		"sound dots are laid over the habitat as light rather than printed as ink")
	var profile: HearingProfile = senses.hearing.profile
	_check(profile.angular_jitter < 1.0 and profile.radial_jitter_px <= 2.0,
		"default particles can scatter out of their coherent ring")
	_check(pigment != null and pigment.shader.code.contains("fwidth"),
		"batched sound dots lost their shader-antialiased edge")
	_check(main._msaa_for_output_size(Vector2i(2560, 1440)) == Viewport.MSAA_4X
		and main._msaa_for_output_size(Vector2i(3840, 2160)) == Viewport.MSAA_2X,
		"output MSAA no longer keeps 4× through 1440p and falls back above it")
	_check(main.camera.is_current(), "adding the hearing layer displaced the active camera")
	var zoom_before: float = main.camera.zoom.x
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	main._unhandled_input(wheel)
	_check(main.camera.zoom.x > zoom_before, "camera zoom stopped working with hearing active")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	main._unhandled_input(wheel)
	_check(is_equal_approx(main.camera.zoom.x, zoom_before),
		"camera zoom no longer round-trips after adding hearing")


func _events_and_reset(senses: CreatureSenses, field: SoundField) -> void:
	field.clear()
	main._on_foot_landed(main.creature.body.head.pos, 0.12, main.creature)
	main._on_foot_landed(main.creature.body.head.pos, 0.12, main.creature)
	_check(not field.waves.is_empty() and field.waves[-1].kind == SoundField.Kind.STEP,
		"movement footfalls are not connected to hearing")
	main._on_creature_bite_started(
		BiteMark.mouthful(main.creature.jaw_point(), Vector2.RIGHT, 1.0, 1.0),
		main.creature)
	_check(field.waves[-1].kind == SoundField.Kind.BITE,
		"combat bites are not connected to hearing")
	main.food_field.pellets = PackedVector2Array([main.creature.body.head.pos])
	main._physics_process(1.0 / 60.0)
	_check(field.waves[-1].kind == SoundField.Kind.FEED,
		"eating food is not connected to hearing")

	senses.hearing.heard_sounds.append(HearingSense.HeardSound.new())
	main.hud.select_species("Cat")
	_check(senses.active_species == "Cat", "species change did not reset SENSES")
	_check(senses.hearing.heard_sounds.is_empty(),
		"a species change kept the old creature's heard events")
	field.emit_sound(main.creature.head_pos, 0.5, SoundField.Kind.IMPACT)
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.pressed = true
	main._unhandled_input(reset)
	_check(field.waves.is_empty(), "a full reset left old sounds in flight")
	_check(senses.hearing.heard_sounds.is_empty(), "a full reset left the old hearing read")
	_check(senses.active_species == "Cat", "full reset lost the active species")
	_check(senses.hearing.origin().is_equal_approx(main.creature.body.head.pos),
		"hearing did not follow the head after reset")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("hearing OK — coherent waves arrive, attenuate, occlude and reset independently")
		quit(0)
	else:
		for failure in failures:
			print("HEARING FAIL — ", failure)
		quit(1)
