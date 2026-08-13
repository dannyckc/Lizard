## Close-up pictures of the bite: the approach, the closing and the hold, against
## a standing animal and against a body on the floor — which is what the two
## kinds of bite are in this view. Must run windowed: headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1200x900 --script tests/BiteShot.gd
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://bite"
const ZOOM: float = 4.6
## Where along the target the cursor is held — the mid-trunk, in both runs. Which
## way round the jaws then come in is the approach's answer, not the cursor's.
const STATION: float = 0.45

var lab: Node
var prey: Creature2
var cursor: Vector2 = Vector2.INF
var frames: int = 0
var saved: Array = []
## 0 a standing animal (the mouth arrives level: a bite into the flank),
## 1 a body on the floor (the mouth is above it: a bite down onto the back).
var run: int = 0


func _initialize() -> void:
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		lab.terrain.clear()
		lab.set_process(false)
		lab.hud.visible = false
		_spawn()
	if frames < 4:
		return false

	var cat: Creature2 = lab.creature
	# The pointer is kept on the same flesh right up to the click, the way a hand
	# tracks a moving animal.
	if frames >= 16 and frames < 64:
		cursor = _on_prey()
	_aim(cat)
	lab.camera.zoom = Vector2(ZOOM, ZOOM)
	lab.camera.position = cat.armature.plan(cat.armature.head_index())

	match frames:
		60:
			_shoot("%s-1-aimed" % _word())
		64:
			_report_aim(cat)
			cat.set_bite_held(true)
			cat.request_bite(cursor)
		70:
			_shoot("%s-2-lunge" % _word())
		95:
			_shoot("%s-3-latched" % _word())
			_report(cat)
		150:
			_shoot("%s-4-held" % _word())
			_report(cat)
		156:
			cat.set_bite_held(false)
		180:
			_shoot("%s-5-let-go" % _word())
			if run == 0:
				run = 1
				frames = 4
				cursor = Vector2.INF
				cat.reset()
				prey.queue_free()
				prey = null
				_spawn()
			else:
				print("bite shots: " + " · ".join(saved))
				print("  in " + ProjectSettings.globalize_path(OUT))
				quit(0)
	return false


func _word() -> String:
	return "standing" if run == 0 else "downed"


func _spawn() -> void:
	prey = Creature2.new()
	prey.name = "Quarry"
	prey.spawn_position = Vector2(96.0, -8.0)
	prey.spawn_heading = PI * 0.55
	var skin := Likeness.new()
	skin.show_behind_parent = true
	prey.add_child(skin)
	lab.add_child(prey)
	if run == 1:
		prey.toggle_collapsed()
		prey.simulate(2.0)


func _aim(cat: Creature2) -> void:
	if cursor.x < INF:
		cat.command.aim_active = true
		cat.command.aim_world = cursor
		cat.aim_at(Quarry.resolve(Quarry.pick(lab.get_tree(), cursor, cat), cat))
	lab.mark.show_aim(cat, lab.camera.zoom.x)


## A point on the prey's drawn flank — where a player would put the pointer.
func _on_prey() -> Vector2:
	var flesh: Vector3 = prey.contour.place(BodySchema.TRUNK, STATION, PI * 0.5)
	return Contour.seen(flesh)


func _report_aim(cat: Creature2) -> void:
	var reach: Dictionary = cat.aim_reach
	var contact: Dictionary = reach.get("contact", {})
	print("%s: aims at trunk t=%.2f theta=%.2f (%.0f° round from the back), ok=%s"
		% [_word(), contact.get("t", -1.0), contact.get("theta", -1.0),
			rad_to_deg(float(contact.get("theta", 0.0))), reach.get("ok", false)])


## What the hold actually is, in numbers — the picture alone cannot say whether
## a head over a back is over the spine or short of it.
func _report(cat: Creature2) -> void:
	if cat.maw.holding.is_empty():
		print("%s: nothing held" % _word())
		return
	var seat: Vector3 = cat.maw.bite_point()
	var jaw: Vector3 = cat.maw.jaw_point()
	var axis: Vector3 = prey.contour.axis(cat.maw.holding["band"],
		cat.maw.holding["t"])
	print("%s: holds theta %.0f° | jaw→seat %.2f px | jaw %.1f px off the axis and %.1f above it"
		% [_word(), rad_to_deg(float(cat.maw.holding["theta"])),
			Vector2(seat.x - jaw.x, seat.y - jaw.y).length(),
			Vector2(jaw.x - axis.x, jaw.y - axis.y).length(), jaw.z - axis.z])


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT, word])
	saved.append(word)
