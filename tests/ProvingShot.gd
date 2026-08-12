## Pictures of the proving ground — the eyeball half of the testing area.
##
## Must run windowed: headless renders nothing (and reports the viewport square
## whatever `--resolution` says).
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/ProvingShot.gd
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://proving"

var lab: Node
var frames: int = 0
var saved: Array = []


func _initialize() -> void:
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		# The lab's pump owns the camera; the shot drives it instead.
		lab.set_process(false)
		lab.hud.visible = false
	if frames < 3:
		return false

	var zone: Proving = lab.get_node("Proving")
	match frames:
		10:
			_look(zone.at, 1.0)
		12:
			_shoot("zone")
		20:
			_look(zone.at + Vector2(-230.0, Proving.COURSE), 2.6)
		22:
			_shoot("steps")
		30:
			_look(zone.at + Vector2(120.0, Proving.COURSE), 2.2)
		32:
			_shoot("solids")
		40:
			_look(zone.at + Vector2(-60.0, Proving.BAYS), 1.9)
		42:
			_shoot("bays")
		240:
			# ...and the same bays four seconds later, to see whether the living
			# one has moved and the dead one has not.
			_shoot("bays-later")
			print("proving shots: " + " · ".join(saved))
			print("  in " + ProjectSettings.globalize_path(OUT))
			quit(0)
	return false


func _look(where: Vector2, zoom: float) -> void:
	lab.camera.position = where
	lab.camera.zoom = Vector2(zoom, zoom)


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT, word]
	image.save_png(path)
	saved.append(word)
