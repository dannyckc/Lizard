## Saves pictures of the v2 lab's HUD — the eyeball half of the troubleshooting-UI
## port. Must run windowed: headless renders nothing, and reports the viewport as
## square whatever `--resolution` says, so layout measured there is wrong.
##
## The animal stands through all of it. The throttle below is still written, and
## still read by nothing, while the movers are out for rewrite — so what these
## shots check is the chrome and the drawn body, not a walk.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/LabShot.gd
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://lab"
const WARM: int = 90

var lab: Node
var frames: int = 0
var saved: Array = []


func _initialize() -> void:
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		lab.terrain.clear()
		lab.get_node("Camera2D").zoom = Vector2(2.2, 2.2)
		# The lab's own pump would overwrite the command with the (unpressed)
		# keyboard every frame; the shot drives the creature by command instead.
		# The camera follow lives in that same pump, so the shot carries it too.
		lab.set_process(false)
	if frames < 3:
		return false

	var creature: Creature2 = lab.creature
	var hud: LabHUD = lab.hud
	creature.command.throttle = 0.0 if frames < WARM else 1.0
	lab.camera.position = lab.camera.position.lerp(lab._camera_focus(), 0.12)

	match frames:
		WARM - 20:
			_shoot("field-idle")
		WARM * 2:
			_shoot("field-asked")
		WARM * 2 + 5:
			hud.set_view(LabHUD.VIEW_ANATOMY)
		WARM * 3:
			_shoot("anatomy")
		WARM * 3 + 5:
			hud.anatomy.view.set_layer_shown(BodySchema.Layer.SKIN, false)
			hud.anatomy.view.set_layer_shown(BodySchema.Layer.FAT, false)
			hud.anatomy._sync_toggles()
		WARM * 3 + 45:
			_shoot("anatomy-peeled")
		WARM * 3 + 50:
			hud.anatomy._on_slice_pressed(SpecimenStage.SLICE_SIDE)
		WARM * 3 + 90:
			_shoot("anatomy-section")
		WARM * 3 + 95:
			# The rest of the drawer's hand, through its own handlers rather than
			# around them: right-click isolates a tissue, a chip holds one chain
			# up, and the pointer over the stage names the cell it is on.
			hud.anatomy._on_slice_pressed(SpecimenStage.SLICE_OFF)
			hud.anatomy._on_row_input(_right_click(), SpecimenDrawer.ROWS.size() - 3)
			hud.anatomy._sync_toggles()
			hud.anatomy._on_focus_pressed(&"HL")
		WARM * 3 + 130:
			# A frame ahead of the picture: the readout is a Label, and the shot
			# grabs the frame that has already been rendered. Swept down the middle
			# of the slab rather than aimed at its centre — the specimen is a walking
			# animal and the middle of its bounds is as often between its legs as on
			# it, which is a miss rather than a failure.
			for step in 9:
				var at: Vector2 = hud.anatomy.view.size * Vector2(0.5, 0.34 + step * 0.04)
				hud.anatomy.view._pick(at)
				if hud.anatomy._readout.text.begins_with("HOVER"):
					continue
				print("  hover reads: " + hud.anatomy._readout.text)
				break
		WARM * 3 + 135:
			_shoot("anatomy-isolated")
		WARM * 3 + 140:
			hud.anatomy._on_row_input(_right_click(), SpecimenDrawer.ROWS.size() - 3)
			hud.anatomy._on_focus_pressed(&"HL")
			hud.anatomy._sync_toggles()
		WARM * 4:
			_shoot("anatomy-focused")
		WARM * 4 + 5:
			hud.set_view(LabHUD.VIEW_FIELD)
		WARM * 4 + 40:
			_shoot("field-again")
			print("lab shots: " + " · ".join(saved))
			print("  in " + ProjectSettings.globalize_path(OUT))
			quit(0)
	return false


func _right_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	return click


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT, word]
	image.save_png(path)
	saved.append(word)
