## Saves pictures of the cursor look and the bite — the eyeball half of the
## controls port. Must run windowed: headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/AimShot.gd
##
## Drives the body the way the lab's own pump does (a world point for the
## cursor, then the pick, the aim and the mark) with the pump itself switched
## off, so the shot decides its own frames.
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://aim"
const WARM: int = 60

var lab: Node
var prey: Creature2
var cursor: Vector2 = Vector2.ZERO
var frames: int = 0
var saved: Array = []


func _initialize() -> void:
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		lab.terrain.clear()
		lab.get_node("Camera2D").zoom = Vector2(2.6, 2.6)
		lab.set_process(false)
		prey = Creature2.new()
		prey.name = "Quarry"
		prey.spawn_position = Vector2(112.0, -18.0)
		prey.spawn_heading = PI * 0.55
		# Its own skin, because a body built in code has no view node and the
		# whole point of these shots is to look at one.
		var skin := Likeness.new()
		skin.show_behind_parent = true
		prey.add_child(skin)
		lab.add_child(prey)
	if frames < 4:
		return false

	var cat: Creature2 = lab.creature
	_aim(cat)
	lab.camera.position = lab.camera.position.lerp(cat.head_pos, 0.14)

	match frames:
		10:
			cursor = Vector2(60.0, 150.0)
		WARM:
			_shoot("look-down")
		WARM + 5:
			cursor = Vector2(40.0, -170.0)
		WARM * 2:
			_shoot("look-up")
		WARM * 2 + 5:
			cursor = _on_prey()
		WARM * 3:
			_shoot("aimed")
		WARM * 3 + 4:
			cat.set_bite_held(true)
			cat.request_bite(cursor)
		WARM * 3 + 10:
			_shoot("lunge")
		WARM * 4:
			_shoot("latched")
		WARM * 4 + 5:
			cat.set_bite_held(false)
		WARM * 5:
			_shoot("let-go")
			print("aim shots: " + " · ".join(saved))
			print("  in " + ProjectSettings.globalize_path(OUT))
			quit(0)
	return false


## The lab's own cursor pump, minus the mouse.
func _aim(cat: Creature2) -> void:
	if cursor.x < INF:
		cat.command.aim_active = true
		cat.command.aim_world = cursor
		cat.aim_at(Quarry.resolve(Quarry.pick(lab.get_tree(), cursor, cat), cat))
	lab.mark.show_aim(cat, lab.camera.zoom.x)


## A point on the prey's drawn flank — where a player would put the pointer.
func _on_prey() -> Vector2:
	var flesh: Vector3 = prey.contour.place(BodySchema.TRUNK, 0.45, PI * 0.5)
	return Contour.seen(flesh)


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT, word]
	image.save_png(path)
	saved.append(word)
