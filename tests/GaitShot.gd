## Saves pictures of the Gait view while the creature is actually walked.
## Must run windowed — headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/GaitShot.gd -- --preset Cat --sprint
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://gait"
## Frames driven before each shot, so the animal is well into its gait.
const WARM: int = 240
const BETWEEN: int = 90
## Frames the crouch is held for before the push-off — see Jump.
const CHARGE: int = 24

var main: Node
var frames: int = 0
var preset: String = "Lizard"
var shot: int = 0
var shot_air: bool = false
var saved: Array = []


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--preset" and i + 1 < args.size():
			preset = args[i + 1]
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	var player: Creature = main.get_node("Creature")
	if frames == 2:
		player.params.apply_preset(preset)
		player.reset(Vector2.ZERO, 0.0)
		# An empty, flat paddock: a shot of a walk into a carcass is a shot of the
		# collision solver, not the gait.
		main.terrain.clear()
		main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)
		main.hud.set_view(EvolutionHUD.VIEW_GAIT)
		main.hud.gait_panel.set_active_species(preset)
		# The world's input pump would overwrite the command with the (unpressed)
		# keyboard every tick; the shot drives the creature by command instead.
		main.set_physics_process(false)
	if frames < 2:
		return false

	# Drive the animal by command rather than by keys, the same channel a player
	# uses. Warm-up walks it; the middle stretch runs it; the last stalks.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	player.command.throttle = 1.0
	player.command.sprint = "--sprint" in args and frames > WARM
	player.command.stalk = "--stalk" in args and frames > WARM * 2 + BETWEEN
	# The jump is held and let go, the way the key is: the crouch charges the
	# spring and the release is the push-off.
	if "--jump" in args:
		player.command.climb = 1.0 if frames > WARM and frames <= WARM + CHARGE else 0.0

	if frames == WARM:
		_shoot("walk")
	elif "--jump" in args and frames > WARM + CHARGE and not shot_air \
			and player.elevation.height > 0.0 and player.elevation.rate <= 0.0:
		# At the apex, which is where the figure has the furthest to lift.
		shot_air = true
		_shoot("air")
	elif frames == WARM * 2 and "--sprint" in args:
		_shoot("run")
	elif frames == WARM * 3 and "--stalk" in args:
		_shoot("low")
	elif frames >= WARM * 3 + BETWEEN:
		print("gait shots: " + " · ".join(saved))
		quit(0)
	return false


func _shoot(word: String) -> void:
	shot += 1
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = "%s/%s-%02d-%s.png" % [OUT, preset.to_lower().replace(" ", ""), shot, word]
	root.get_viewport().get_texture().get_image().save_png(path)
	saved.append(ProjectSettings.globalize_path(path))
	var player: Creature = main.get_node("Creature")
	print("%s %s: %s · Fr %.2f · duty %.2f · cycle %.2f · height %.1f" % [preset, word,
		player.gait.footfall.describe(), player.gait.footfall.froude,
		player.gait.duty_measured(), player.gait.cycle_length(),
		player.elevation.height])
