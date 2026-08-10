## Saves cropped pictures of the anatomy stage from side-on angles, per preset,
## at a handful of layer settings — the views where a seam between a limb and
## the trunk shows. Throwaway diagnostic scaffolding.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/SideShot.gd -- --preset Cat
extends SceneTree

const OUT: String = "user://side"
const ZOOM: int = 2

var main: Node
var frames: int = 0
var preset: String = "Cat"
var shot: int = -1
var settle: int = 0

## name, spin, tilt, layers mask, vessels, nerves
var cases: Array = [
	["side", 0.0, 1.45, AnatomyView.ALL_LAYERS, false, false],
	["side-quarter", 0.7, 1.1, AnatomyView.ALL_LAYERS, false, false],
	["front", 1.57, 1.45, AnatomyView.ALL_LAYERS, false, false],
	["side-muscle", 0.0, 1.45, 1 << AnatomyLattice.MUSCLE, false, false],
	["side-fat", 0.0, 1.45, 1 << AnatomyLattice.FAT, false, false],
	["side-bone", 0.0, 1.45, 1 << AnatomyLattice.BONE, false, false],
	["side-organ", 0.0, 1.45, 1 << AnatomyLattice.ORGAN, false, false],
	["side-nerves", 0.0, 1.45, 0, false, true],
	["side-vessels", 0.0, 1.45, 0, true, false],
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
		_save("%s-%s" % [preset, str(cases[shot][0])])
	shot += 1
	if shot >= cases.size():
		quit(0)
		return false
	_apply(cases[shot])
	settle = 4
	return false


func _apply(one: Array) -> void:
	var view: AnatomyView = main.hud.anatomy.view
	view.spin = float(one[1])
	view.tilt = float(one[2])
	view.layers = int(one[3])
	view.show_vessels = bool(one[4])
	view.show_nerves = bool(one[5])
	view.set_zoom(1.6)
	main.hud.anatomy.refresh()


func _save(name: String) -> void:
	var image: Image = root.get_texture().get_image()
	var stage: Control = main.hud.anatomy.view
	var at: Rect2 = Rect2(stage.global_position, stage.size)
	image = image.get_region(Rect2i(at.position, at.size))
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM,
		Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = "%s/%s.png" % [OUT, name]
	image.save_png(path)
	print("saved %s" % ProjectSettings.globalize_path(path))
