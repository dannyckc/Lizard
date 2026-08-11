## Saves pictures of the v2 animal while it is actually walked — the eyeball
## half of the Phase-4 gate. Must run windowed: headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/SkinShot.gd -- --zoom 4
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://skin"
const WARM: int = 150
const BETWEEN: int = 90

var lab: Node
var frames: int = 0
var zoom: float = 4.0
var saved: Array = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--zoom" and i + 1 < args.size():
			zoom = float(args[i + 1])
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frames += 1
	var creature: Creature2 = lab.creature
	if frames == 2:
		lab.terrain.clear()
		var camera: Camera2D = lab.get_node("Camera2D")
		camera.zoom = Vector2(zoom, zoom)
		# The lab's own pump would overwrite the command with the (unpressed)
		# keyboard every frame; the shot drives the creature by command instead.
		lab.set_process(false)
	if frames < 2:
		return false

	var args: PackedStringArray = OS.get_cmdline_user_args()
	creature.command.throttle = 0.0 if frames < WARM else 1.0
	creature.command.sprint = frames > WARM * 2 + BETWEEN
	var look: Vector2 = creature.centre()
	if "--head" in OS.get_cmdline_user_args():
		var head: Vector3 = creature.armature.pos[creature.armature.head_index()]
		look = Vector2(head.x, head.y)
	lab.get_node("Camera2D").position = look

	if frames == WARM - 10:
		_shoot("stand")
	elif frames == WARM * 2:
		_shoot("walk")
	elif frames == WARM * 3 + BETWEEN:
		_shoot("run")
	elif frames == WARM * 3 + BETWEEN + 30:
		creature.toggle_collapsed()
	elif frames == WARM * 3 + BETWEEN + 120:
		_shoot("down")
	elif frames > WARM * 3 + BETWEEN + 130:
		print("skin shots: " + " · ".join(saved))
		print("  in " + ProjectSettings.globalize_path(OUT))
		quit(0)
	return false


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT, word]
	image.save_png(path)
	saved.append(word)
