## Focused interaction smoke test for the designed HUD.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/UIInteractionTest.gd
extends SceneTree

var failures: Array[String] = []
var main: Node
var checked: bool = false


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

	_finish()
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("UI interaction smoke OK — drawer, species tabs and reset are live")
		quit(0)
	else:
		for failure in failures:
			print("UI FAIL — ", failure)
		quit(1)
