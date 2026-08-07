## Boots the real Main scene headless and walks the creature for a few seconds
## with the debug overlay on, so every _draw() path (body fill, outline, limbs,
## planted + stepping feet, debug wedges, HUD, grid) actually executes. Catches
## bad draw arguments and scene wiring mistakes that a pure-simulation test
## cannot.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/RenderSmoke.gd
extends SceneTree

var draws: int = 0
var ticks: int = 0
var main: Node


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	# Synthesise real key presses rather than writing to Creature.command
	# directly: Main replaces that object every tick from MovementInput, so this
	# is both the only thing that sticks and a genuine test of the input path.
	_hold(KEY_W)
	_hold(KEY_D)


func _hold(physical_keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.pressed = true
	Input.parse_input_event(ev)


func _process(_delta: float) -> bool:
	# Headless renders far faster than real time, so progress is measured in
	# physics ticks below; this only tallies draws.
	draws += 1
	if draws == 4:
		main.get_node("Creature/View").debug = true
	return false


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks == 120:
		main.get_node("Creature").params.tail_enabled = false  # exercise tail clipping
	if ticks >= 240:
		var c: Creature = main.get_node("Creature")
		var stepped: bool = false
		for limb in c.gait.limbs:
			stepped = stepped or limb.planted != limb.ideal
		print("render smoke OK — %d draws / %d ticks | speed %.0f px/s | travelled %.0f px | outline %d verts | feet moved: %s"
			% [draws, ticks, c.speed, c.head_pos.length(), c.body.outline.size(), str(stepped)])
		quit()
	return false
