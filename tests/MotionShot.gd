## Saves pictures of the Physics drawer while the v2 creature is actually walked.
## Must run windowed — headless renders nothing (and the whole point is layout).
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1600x1000 --script tests/MotionShot.gd -- --sprint
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://motion"
## Frames walked before each shot, so the gait is well under way rather than
## being caught in its first stride.
const WARM: int = 200
const BETWEEN: int = 110

var main: Node
var frames: int = 0
var saved: Array = []


func _initialize() -> void:
	main = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	var creature: Creature2 = main.creature
	if creature == null:
		return false
	if frames == 2:
		main.terrain.clear()
		main.hud.set_view(LabHUD.VIEW_PHYSICS)
		# The lab's input pump would overwrite the command with the unpressed
		# keyboard every tick; the shot drives the animal by command instead.
		main.set_physics_process(false)
		main.set_process(false)
	if frames < 2:
		return false

	var args: PackedStringArray = OS.get_cmdline_user_args()
	creature.command.throttle = 1.0
	creature.command.sprint = "--sprint" in args and frames > WARM + BETWEEN
	creature.command.turn = 1.0 if "--turn" in args and frames > WARM * 2 else 0.0

	if frames == WARM:
		_shoot("walk")
	elif frames == WARM * 2:
		_shoot("run" if "--sprint" in args else "walk2")
	elif frames == WARM * 2 + BETWEEN:
		_shoot("turn" if "--turn" in args else "cruise")
	elif frames > WARM * 2 + BETWEEN * 2:
		print("motion shots: " + " · ".join(saved))
		quit(0)
	return false


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = "%s/motion-%02d-%s.png" % [OUT, saved.size() + 1, word]
	root.get_viewport().get_texture().get_image().save_png(path)
	saved.append(ProjectSettings.globalize_path(path))
	var r: MotionReadout = (main.creature as Creature2).motion_readout()
	var tells: Dictionary = r.tells()
	print("%s: %s · %.0f px/s · %d down · margin %.1f · %d samples" % [
		word, r.state, r.speed, r.feet_down, r.margin, r.samples()])
	print("   tells " + str(tells))
