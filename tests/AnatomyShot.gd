## Saves pictures of the anatomy specimen, and times the pass that draws it.
## Must run windowed — headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/AnatomyShot.gd -- --preset Elephant
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const TICK: float = 1.0 / 60.0
const OUT: String = "user://anatomy"
const SAMPLE: int = 120

var main: Node
var frames: int = 0
var preset: String = "Lizard"
var shots: Array = []
var timed: bool = false
var started: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--preset" and i + 1 < args.size():
			preset = args[i + 1]
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		var player: Creature = main.get_node("Creature")
		player.params.apply_preset(preset)
		player.reset(Vector2.ZERO, 0.0)
		if "--field" not in OS.get_cmdline_user_args():
			main.hud.set_view(EvolutionHUD.VIEW_ANATOMY)
		var args: PackedStringArray = OS.get_cmdline_user_args()
		var v: AnatomyView = _view()
		if v != null:
			if "--peel" in args:
				v.set_layer_shown(AnatomyLattice.SKIN, false)
				v.set_layer_shown(AnatomyLattice.FAT, false)
			if "--bones" in args:
				v.set_layer_shown(AnatomyLattice.SKIN, false)
				v.set_layer_shown(AnatomyLattice.FAT, false)
				v.set_layer_shown(AnatomyLattice.MUSCLE, false)
				v.set_layer_shown(AnatomyLattice.ORGAN, false)
			if "--xray" in args:
				v.xray = true
			if "--slice" in args:
				v.slice_axis = AnatomyView.SLICE_FLAT
				v.slice_at = 0.9
			if "--wire" in args:
				v.show_lattice = true
		return false
	if frames < 40:
		return false
	# Frame cost with the specimen on screen, which is the number that matters:
	# the pass runs inside the redraw, so timing it in isolation misses the
	# upload and the sort.
	if frames <= 40 + SAMPLE:
		if frames == 41:
			started = Time.get_ticks_usec()
		if frames == 40 + SAMPLE:
			print("%s: %.3f ms/frame with the specimen up (%d frames)"
				% [preset, float(Time.get_ticks_usec() - started) / (1000.0 * float(SAMPLE - 1)),
					SAMPLE - 1])
		return false
	if not timed:
		timed = true
		if view_has_marks():
			_time()
	if frames % 6 != 0:
		return false
	shots.append(frames)
	_save("%s-%d" % [preset, shots.size()])
	if shots.size() >= 3:
		quit(0)
		return false
	# Turn the specimen between shots, so the pictures show it from more than one
	# eye and any seam that only opens at an angle has a chance to show.
	var view: AnatomyView = _view()
	if view != null:
		view.spin = 0.9 * float(shots.size())
		view.tilt = 0.5
	return false


func view_has_marks() -> bool:
	return _view() != null and _view().has_method("_place_marks")


func _view() -> AnatomyView:
	return main.hud.anatomy.view if main.hud.anatomy != null else null


## What the specimen pass actually costs, driven by hand so the number is the
## work rather than the frame interval.
func _time() -> void:
	var view: AnatomyView = _view()
	if view == null:
		print("no specimen view")
		return
	var lat: AnatomyLattice = view.lattice()
	var grid: TissueGrid = view.tissue()
	if lat == null or grid == null:
		print("no lattice")
		return
	var t0: int = Time.get_ticks_usec()
	for _r in 30:
		view._refresh_stations(grid)
	var frames_ms: float = float(Time.get_ticks_usec() - t0) / 30000.0
	view._draw_key = 0
	t0 = Time.get_ticks_usec()
	for _r in 10:
		view._draw_key = 0
		view._refresh_draw_list(lat, grid)
	var list_ms: float = float(Time.get_ticks_usec() - t0) / 10000.0
	t0 = Time.get_ticks_usec()
	for _r in 30:
		view._place_marks(lat)
	var place_ms: float = float(Time.get_ticks_usec() - t0) / 30000.0
	print("%s: %d cells, %d drawn, %d facing · frames %.3f ms · list %.3f ms · place %.3f ms"
		% [preset, lat.count, view._draw_list.size(), view._shown_count,
			frames_ms, list_ms, place_ms])


func _save(name: String) -> void:
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = "%s/%s.png" % [OUT, name]
	image.save_png(path)
	print("saved %s" % ProjectSettings.globalize_path(path))
