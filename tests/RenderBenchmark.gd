## Small repeatable GPU benchmark for the real scene. This must run with a
## display backend: headless mode does not execute the canvas shader workload.
##
##   godot --path . --resolution 2560x1440 --disable-vsync \
##       --script tests/RenderBenchmark.gd
##
## Add `-- --sprint`, `--no-sight`, `--no-hearing`, or `--no-smell` after the
## engine's `--` separator to reproduce and isolate active sense workloads.
extends SceneTree

const WARMUP_FRAMES := 90
const SAMPLE_FRAMES := 120

var frames := 0
var started_usec := 0
var main: Node
var stress_hearing := false
var stress_smell := false
var peak_waves: int = 0
var peak_marks: int = 0
var render_cpu_ms: float = 0.0
var render_gpu_ms: float = 0.0


func _initialize() -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var args := OS.get_cmdline_user_args()
	stress_hearing = "--stress-hearing" in args
	stress_smell = "--stress-smell" in args
	_disable_renderer("SightRenderer", "--no-sight" in args)
	_disable_renderer("HearingRenderer", "--no-hearing" in args)
	_disable_renderer("SmellRenderer", "--no-smell" in args)
	if "--sprint" in args:
		_hold(KEY_W)
		_hold(KEY_SHIFT)


func _disable_renderer(path: String, disabled: bool) -> void:
	if not disabled:
		return
	var renderer := main.get_node(path) as CanvasItem
	renderer.process_mode = Node.PROCESS_MODE_DISABLED
	renderer.visible = false


func _hold(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _process(_delta: float) -> bool:
	_maintain_stress_load()
	peak_waves = maxi(peak_waves, (main.get_node("SoundField") as SoundField).waves.size())
	peak_marks = maxi(peak_marks,
		(main.get_node("Creature/Senses") as CreatureSenses).smell.marks.size())
	frames += 1
	if frames == WARMUP_FRAMES:
		started_usec = Time.get_ticks_usec()
	elif frames > WARMUP_FRAMES:
		render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(
			root.get_viewport_rid())
		render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(
			root.get_viewport_rid())
	if frames == WARMUP_FRAMES + SAMPLE_FRAMES:
		var seconds := float(Time.get_ticks_usec() - started_usec) / 1000000.0
		var waves: int = (main.get_node("SoundField") as SoundField).waves.size()
		var marks: int = (main.get_node("Creature/Senses") as CreatureSenses).smell.marks.size()
		var smell_renderer := main.get_node("SmellRenderer") as SmellRenderer
		print("BENCH viewport=", root.size, " visible=", root.get_visible_rect().size,
			" msaa=", root.msaa_2d, " waves=", waves, "/", peak_waves,
			" marks=", marks, "/", peak_marks, " smell_glyphs=",
			smell_renderer.last_glyph_count, " batches=", smell_renderer.last_batch_count,
			" fps=%.1f ms=%.3f render_cpu=%.3f render_gpu=%.3f" % [
				SAMPLE_FRAMES / seconds, seconds * 1000.0 / SAMPLE_FRAMES,
				render_cpu_ms / SAMPLE_FRAMES, render_gpu_ms / SAMPLE_FRAMES])
		quit()
	return false


func _maintain_stress_load() -> void:
	if stress_hearing:
		var field := main.get_node("SoundField") as SoundField
		var creature := main.get_node("Creature") as Creature
		while field.waves.size() < SoundField.MAX_SOUNDS:
			var offset := Vector2(float(field.waves.size()) * 7.0, 0.0)
			field.emit_sound(creature.head_pos + offset, 0.18,
				SoundField.Kind.STEP, creature)
	if stress_smell:
		var smell: SmellSense = (main.get_node("Creature/Senses") as CreatureSenses).smell
		while smell.marks.size() < smell.profile.max_marks:
			var mark := SmellSense.Mark.new()
			var index: int = smell.marks.size()
			mark.pos = smell.origin() + Vector2.RIGHT.rotated(float(index) * 2.39996) \
				* (80.0 + float(index % 17) * 12.0)
			mark.source = smell.origin()
			mark.kind = index % ScentField.KIND_COUNT
			mark.confidence = float(index % 10) / 9.0
			mark.life = 1000.0
			# Start inside the steady part of the envelope. With age left at zero,
			# the deliberately long stress lifetime also made fade-in hundreds of
			# seconds long, so the old "400 marks" case actually drew only a handful.
			mark.age = 250.0
			mark.seed = fposmod(float(index) * 0.61803398875, 1.0)
			smell.marks.append(mark)
