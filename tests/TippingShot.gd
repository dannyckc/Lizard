## Pictures of the body going over — the eyeball half of the roll gate. Must run
## windowed: headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1200x800 --script tests/TippingShot.gd
##
## Four frames: standing level, mid-heel under a survivable push, on its flank
## after a felling one, and — for contrast — the same animal killed on its feet,
## which flops belly-down because nothing rolled it.
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://tipping"
const WARM: int = 90

var lab: Node
var frames: int = 0
var saved: Array = []
var stage: int = 0
var mark: int = 0


func _initialize() -> void:
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _lat(c: Creature2) -> Vector2:
	var dir: Vector2 = Vector2.RIGHT.rotated(c.heading)
	return Vector2(-dir.y, dir.x)


func _process(_delta: float) -> bool:
	frames += 1
	var c: Creature2 = lab.creature
	if frames == 2:
		lab.terrain.clear()
		var camera: Camera2D = lab.get_node("Camera2D")
		camera.zoom = Vector2(4.0, 4.0)
		lab.set_process(false)
	if frames < 2:
		return false
	lab.get_node("Camera2D").position = c.centre()
	var a: Armature = c.armature
	var back: float = a.pos[a.withers_index()].z + a.flesh_r[a.withers_index()]
	var here: Vector2 = c.centre()

	match stage:
		0:
			if frames == WARM:
				_shoot("level")
				c.shove(_lat(c) * 120.0, Vector3(here.x, here.y, back))
				mark = frames
				stage = 1
		1:
			if frames == mark + 20:
				_shoot("heeled")
			elif frames == mark + 200:
				c.reset()
				mark = frames
				stage = 2
		2:
			if frames == mark + 40:
				c.shove(_lat(c) * 200.0, Vector3(here.x, here.y, back))
			elif frames == mark + 220:
				_shoot("flank")
				c.reset()
				mark = frames
				stage = 3
		3:
			if frames == mark + 40:
				c.toggle_collapsed()
			elif frames == mark + 220:
				_shoot("belly")
				print("tipping shots: " + " · ".join(saved))
				print("  in " + ProjectSettings.globalize_path(OUT))
				quit(0)
	return false


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT, word])
	saved.append(word)
