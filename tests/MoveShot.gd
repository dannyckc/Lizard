## Pictures of the walk and the turn — what the pacing and the spine actually
## look like. Must run windowed: headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1100x800 --script tests/MoveShot.gd [--  tag]
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://move"
const ZOOM: float = 2.4

var lab: Node
var frames: int = 0
var saved: Array = []
var tag: String = ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		tag = "-" + str(arg)
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		lab.terrain.clear()
		lab.set_process(false)
		lab.hud.visible = false
	if frames < 4:
		return false
	var cat: Creature2 = lab.creature
	lab.camera.zoom = Vector2(ZOOM, ZOOM)
	lab.camera.position = cat.centre()

	match frames:
		5:
			cat.command.throttle = 1.0
		120:
			_shoot("walk-a")
		132:
			_shoot("walk-b")
		144:
			_shoot("walk-c")
		150:
			cat.command.turn = 1.0
		180:
			_shoot("turn-early")
		230:
			_shoot("turn-mid")
		290:
			_shoot("turn-late")
		300:
			cat.command.turn = 0.0
			cat.command.sprint = true
		420:
			_shoot("sprint")
			print("move shots: " + " · ".join(saved))
			print("  in " + ProjectSettings.globalize_path(OUT))
			quit(0)
	return false


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s%s.png" % [OUT, word, tag])
	saved.append(word)
