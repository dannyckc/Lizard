## Saves pictures of the standalone Physics HUD while the scenarios run. Must be
## run windowed — headless renders nothing, and the whole point is the layout.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1600x1000 --script tests/PhysicsShot.gd
##
## One frame per scenario, taken a few seconds in so the gait is well under way
## rather than being caught in its first stride.
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://physics"
## Frames of settling before the first shot, and between the ones after it.
const WARM: int = 150
const BETWEEN: int = 230
## Which scenarios are worth a picture, and what to call each shot.
const SHOTS: Array = [
	[0, "cruise"], [1, "accelerate"], [4, "turn"], [5, "ledge"], [6, "brink"],
	[7, "shove"], [8, "collapse"],
]

var bench: PhysicsBench
var frames: int = 0
var taken: int = 0
var saved: Array = []


func _initialize() -> void:
	bench = load("res://scenes/PhysicsHud.tscn").instantiate() as PhysicsBench
	root.add_child(bench)


func _process(_delta: float) -> bool:
	frames += 1
	if bench == null or bench.hud == null:
		return false
	if frames == 2:
		bench.hud.pick_scenario(int(SHOTS[0][0]))
	if taken >= SHOTS.size():
		print("physics shots: " + " · ".join(saved))
		quit(0)
		return true
	if frames == WARM + BETWEEN * taken:
		_shoot(str(SHOTS[taken][1]))
		taken += 1
		if taken < SHOTS.size():
			bench.hud.pick_scenario(int(SHOTS[taken][0]))
	return false


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = "%s/physics-%02d-%s.png" % [OUT, taken + 1, word]
	root.get_viewport().get_texture().get_image().save_png(path)
	saved.append(ProjectSettings.globalize_path(path))
	var r: MotionReadout = bench.creature.motion_readout()
	print("%s: %s · %.0f px/s · %d down · margin %.1f · %d samples" % [
		word, r.state, r.speed, r.feet_down, r.margin, r.samples()])
