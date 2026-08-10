## Saves one cropped picture of the anatomy drawer per layer combination, so the
## specimen can be read at every setting of the toggles rather than at the one it
## happens to open on. Throwaway diagnostic scaffolding.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/LayerShot.gd -- --preset Lizard
extends SceneTree

const OUT: String = "user://layers"
const ZOOM: int = 2

var main: Node
var frames: int = 0
var preset: String = "Lizard"
var shot: int = -1
var settle: int = 0

## name, layers mask, vessels, nerves
var cases: Array = [
	["all", AnatomyView.ALL_LAYERS, true, true],
	["noskin", AnatomyView.ALL_LAYERS & ~1, true, true],
	["muscle-only", 1 << AnatomyLattice.MUSCLE, false, false],
	["bone-only", 1 << AnatomyLattice.BONE, false, false],
	["organs", 0, true, true],
	["vessels-only", 0, true, false],
	["nerves-only", 0, false, true],
	["nets-over-skin", AnatomyView.ALL_LAYERS, true, true],
	["fat-only", 1 << AnatomyLattice.FAT, false, false],
	["skin-only", 1 << AnatomyLattice.SKIN, false, false],
	["xray", AnatomyView.ALL_LAYERS, true, true],
	["section", AnatomyView.ALL_LAYERS, true, true],
	["zoomed", AnatomyView.ALL_LAYERS, false, false],
	["dead", AnatomyView.ALL_LAYERS, true, true],
]


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
		main.hud.set_view(EvolutionHUD.VIEW_ANATOMY)
		return false
	if frames < 30:
		return false
	if settle > 0:
		settle -= 1
		return false
	if shot >= 0:
		_save(str(cases[shot][0]))
	shot += 1
	if shot >= cases.size():
		quit(0)
		return false
	_apply(cases[shot])
	settle = 4
	return false


func _apply(one: Array) -> void:
	var view: AnatomyView = main.hud.anatomy.view
	view.layers = int(one[1])
	view.show_vessels = bool(one[2])
	view.show_nerves = bool(one[3])
	view.spin = 0.9
	view.tilt = 0.45
	view.xray = str(one[0]) == "xray"
	view.slice_axis = AnatomyView.SLICE_SIDE if str(one[0]) == "section" \
		else AnatomyView.SLICE_OFF
	view.slice_at = 0.5
	view.set_zoom(2.4 if str(one[0]) == "zoomed" else 1.0)
	if str(one[0]) == "dead":
		var player: Creature = main.get_node("Creature")
		player.collapse()
	main.hud.anatomy.refresh()


func _save(name: String) -> void:
	var image: Image = root.get_texture().get_image()
	var panel: Control = main.hud.anatomy
	var at: Rect2 = Rect2(panel.global_position, panel.size)
	image = image.get_region(Rect2i(at.position, at.size))
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM,
		Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = "%s/%s.png" % [OUT, name]
	image.save_png(path)
	print("saved %s" % ProjectSettings.globalize_path(path))
