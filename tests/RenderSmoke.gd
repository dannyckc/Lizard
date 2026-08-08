## Boots the real Main scene headless and walks the creature for a few seconds
## with the debug overlay on, so every _draw() path (body fill, tissue grain,
## limbs, planted + stepping feet, Bite cue, HUD, grid and screen-space Sight)
## actually executes. Catches bad draw arguments, shader compilation failures
## and scene wiring mistakes that a pure-simulation test cannot.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/RenderSmoke.gd
extends SceneTree

var draws: int = 0
var ticks: int = 0
var main: Node
## Whether the grip overlay had anything to draw at any point in the run.
var gripped: bool = false


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
	gripped = gripped or (main.get_node("Creature") as Creature).grip != null
	# Hold first, scar second: the hold repositions the target, and the scarring
	# has to survive to the end of the run for the wound cell draws to be
	# exercised on every frame after it rather than only on a handful.
	if ticks == 30:
		_take_hold()  # the grip overlay, which only draws while jaws are latched
	if ticks == 45:
		_scar_target()  # exercise the skin, muscle, bone and cavity cell draws
	if ticks == 120:
		main.get_node("Creature").params.tail_enabled = false  # exercise tail clipping
	if ticks >= 240:
		var c: Creature = main.get_node("Creature")
		var stepped: bool = false
		for limb in c.gait.limbs:
			stepped = stepped or limb.planted != limb.ideal
		var target: Creature = main.get_node("TargetCreature")
		print("render smoke OK — %d draws / %d ticks | speed %.0f px/s | travelled %.0f px | outline %d verts | feet moved: %s | gripped: %s | target integrity %.2f | %d scraps"
			% [draws, ticks, c.speed, c.head_pos.length(), c.body.outline.size(),
				str(stepped), str(gripped), target.anatomy.tissue.integrity(),
				main.get_node("ScrapField").scraps.size()])
		quit()
	return false


## Puts the player's jaws on the target and holds them there, so the debug
## overlay's tether, anchor, strain arc and play ring all get drawn — none of
## which exist on a creature that is merely biting.
func _take_hold() -> void:
	var player: Creature = main.get_node("Creature")
	var target: Creature = main.get_node("TargetCreature")
	# Along the player's own heading, not along +x: it has been turning since the
	# first tick, so a fixed offset would put the target off to one side and the
	# lunge would resolve into empty space.
	var ahead: Vector2 = Vector2.RIGHT.rotated(player.heading)
	target.reset(player.head_pos + ahead * 52.0, player.heading + PI)
	player.set_bite_held(true)
	player.request_bite(target.head_pos)


## Chews each structure hard enough to expose every layer the cell renderer can
## draw — thinned skin, muscle, worn bone and a hole clean through — and sheds
## enough tissue to exercise the scrap field's spawn, settle and draw paths.
func _scar_target() -> void:
	var target: Creature = main.get_node("TargetCreature")
	main.get_node("BiteCue").show_at(target.body.head.pos)
	var points: Array[Vector2] = [target.body.head.pos]
	var torso_i: int = mini(4, target.body.last_index - 1)
	points.append(target.spine.points[torso_i]
		+ target.spine.perps[torso_i] * target.body.widths[torso_i])
	var limb: Limb = target.gait.limbs[0]
	points.append(limb.joints[1].lerp(limb.joints[2], 0.5))
	points.append(limb.joints[2])
	for point in points:
		for _repeat in 6:
			target.apply_bite(point, 9.0, 3.0)
