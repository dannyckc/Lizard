## Focused interaction smoke test for the designed HUD.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/UIInteractionTest.gd
extends SceneTree

var failures: Array[String] = []
var main: Node
var checked: bool = false
## What the anatomy tab actually read off the creature, printed so a pass is
## evidence the panel is quoting a body rather than quietly reporting nothing.
var summary: String = "anatomy not reached"


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true

	var hud: EvolutionHUD = main.hud
	_check(hud != null, "HUD was not created")
	_check(hud.panel != null, "tuning panel was not created")
	if hud == null or hud.panel == null:
		_finish()
		return false

	hud.set_panel_open(false)
	_check(not hud.panel.visible, "tuning button did not close the drawer")
	hud.set_panel_open(true)
	_check(hud.panel.visible, "tuning button did not reopen the drawer")

	hud.select_species("Gecko")
	_check(main.creature.params.segment_count == 11, "Gecko tab did not apply its preset")
	_check(main.creature.spine.size() == 11, "species change did not rebuild the creature")

	main.creature.params.segment_count = 18
	hud.panel.refresh()
	hud.panel._on_reset_pressed()
	_check(main.creature.params.segment_count == 11, "panel reset did not restore the active species")

	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	main._unhandled_input(f1)
	_check(not hud.panel.visible, "F1 did not toggle the designed tuning drawer")

	hud.set_panel_open(true)
	_check_anatomy(hud)

	_finish()
	return false


## The anatomy tab. Checked as a *view of a creature* rather than as a widget:
## that it comes up on the body the world handed it, that pointing it at another
## body re-points the specimen with it, and that peeling a layer changes what the
## specimen is showing rather than only what the row says.
func _check_anatomy(hud: EvolutionHUD) -> void:
	var panel: AnatomyPanel = hud.anatomy
	_check(panel != null, "anatomy panel was not created")
	if panel == null:
		return

	_check(not panel.visible, "the anatomy drawer was out while the field view was up")
	hud.set_view(EvolutionHUD.VIEW_ANATOMY)
	_check(panel.visible, "the anatomy tab did not open its drawer")
	_check(not hud.panel.visible, "the tuning drawer stayed out under the specimen")
	_check(panel.creature() == main.creature,
		"the anatomy tab did not open on the creature the world gave it")

	# The specimen has to be *this* creature. Framed, upright, and made of the
	# lattice the creature is standing in — not of a drawing of a lizard.
	var view: AnatomyView = panel.view
	view.creature = main.creature
	view.size = Vector2(340.0, 326.0)
	view._settle(1.0)
	_check(view.fitted(), "the anatomy view never framed the creature")
	var snout: Vector2 = view.to_panel(main.creature.body.head.pos)
	var tail: Vector2 = view.to_panel(main.creature.body.tail_tip)
	_check(snout.y < tail.y, "the specimen was not presented snout-up")
	_check(Rect2(Vector2.ZERO, view.size).has_point(snout),
		"the specimen was framed off the stage")
	# Every station of the animal is on the page, which is the whole claim the fit
	# makes and the one that silently breaks when a creature changes size.
	var contained: bool = true
	for i in range(main.creature.body.last_index + 1):
		contained = contained and Rect2(Vector2.ZERO, view.size).has_point(
			view.to_panel(main.creature.spine.points[i]))
	_check(contained, "part of the creature was framed off the stage")

	# Peeling. The mask is what the colour reading is taken through, so an ink
	# that does not move when the skin comes off is a panel drawing its own body.
	var torso: TissueGrid.Patch = main.creature.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var cell: int = (TissueGrid.HEAD_COLS + 5) * torso.rows + torso.rows / 2
	var base: int = cell * TissueGrid.LAYERS
	var capacity: float = main.creature.anatomy.tissue.fat_capacity(torso, cell)
	var skinned: Color = CreatureView.tissue_color(torso.hp, base, capacity)
	view.set_layer_shown(TissueGrid.SKIN, false)
	_check(not view.layer_shown(TissueGrid.SKIN), "the skin layer would not come off")
	var peeled: Color = CreatureView.tissue_color(torso.hp, base, capacity, view.layers)
	_check(skinned != peeled, "peeling the skin off did not reach the layer under it")
	view.set_layer_shown(TissueGrid.SKIN, true)

	# The readout names the structure actually under the pointer.
	view._pick(view.to_panel(torso.centre_of(cell)))
	_check(panel._readout.text.begins_with("THORAX"),
		"hovering the chest did not read out the thorax: " + panel._readout.text)

	# A second specimen is a second body, not a second label — and the readouts
	# have to follow it. Bitten first, so the two bodies cannot agree by accident.
	var target: Creature = main.target_creature
	for _repeat in 8:
		target.apply_bite(BiteMark.mouthful(target.body.head.pos, Vector2.RIGHT, 12.0, 4.0))
	target.anatomy.update(target)
	panel.select_specimen(1)
	_check(panel.creature() == target,
		"picking the other specimen did not change whose anatomy is on the slab")
	panel.refresh()
	var wounded: String = panel._integrity.text
	_check(panel._note.text.contains("OUT OF"),
		"the stage note did not report the holes bitten in the specimen: " + panel._note.text)
	_check(panel._status.text != "Intact",
		"a specimen with its head chewed open still read as intact")
	panel.select_specimen(0)
	panel.refresh()
	_check(panel._integrity.text != wounded,
		"switching back to the unbitten specimen kept the bitten one's integrity")

	panel.refresh()
	summary = "specimen %s · integrity %s · %s · %s · brain %s heart %s bleed %s cut off %s" % [
		panel._chips[0].text, panel._integrity.text, panel._status.text, panel._note.text,
		panel._vitals[0].text, panel._vitals[1].text,
		panel._vitals[2].text, panel._vitals[3].text,
	]
	_check(panel._note.text.contains(str(main.creature.anatomy.tissue.cell_count())),
		"the stage note did not count the creature's own lattice: " + panel._note.text)

	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	main._unhandled_input(f3)
	_check(hud.active_view() == EvolutionHUD.VIEW_FIELD, "F3 did not toggle the view back")
	_check(hud.panel.visible, "returning to the field did not restore the tuning drawer")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("UI interaction smoke OK — drawer, species tabs, reset and the anatomy tab are live | %s"
			% summary)
		quit(0)
	else:
		for failure in failures:
			print("UI FAIL — ", failure)
		quit(1)
