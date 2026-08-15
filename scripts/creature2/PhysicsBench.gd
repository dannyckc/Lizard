## The physics bench — the standalone screen the Physics HUD is.
##
## One animal, one floor and the HUD over the whole window: no field view, no
## camera and nothing else in the world, because the picture *is* the readout.
## The lab (`V2Lab`) is where the same body is walked about by hand with the game
## running; this scene exists so the loop can be watched doing one thing at a
## time, deliberately, on ground built for it.
##
## The three parts and what each owns:
##
##   * `Creature2` — the animal, exactly as the lab builds it. Nothing here is a
##     special build and nothing here is driven except through `command`.
##   * `MotionScenario` — the hand on the controls: nine scripted asks, two of
##     which build ground first. It writes the command and nothing else.
##   * `PhysicsHud` — the reading, and the clock (pause, frame-step, slow motion).
##
## The tick order is the one thing this file owns: the scenario asks, and then the
## body answers. Both happen on the physics tick, in tree order, which is why the
## scenario is ticked from the parent of the creature rather than beside it.
##
##   1–9        pick a scenario · SPACE pause · . step one tick
##   ◄ ►        drive the animal by hand (and take the scenario off the script)
##   A / D      turn
class_name PhysicsBench
extends Node2D

@onready var terrain: Terrain = $Terrain

var creature: Creature2
var hud: PhysicsHud
var scenario: MotionScenario = MotionScenario.new()


func _ready() -> void:
	creature = get_node_or_null("Creature2") as Creature2
	scenario.attach(creature, terrain)
	_build_ui()
	scenario.pick(0)


## The HUD stands on its own canvas layer over an empty world — the same
## arrangement the lab uses, so a screen and a drawer are built the same way.
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 20
	add_child(layer)
	hud = PhysicsHud.new()
	hud.name = "PhysicsHud"
	hud.subject = creature
	hud.scenario = scenario
	layer.add_child(hud)
	hud.set_subject(creature)
	hud.set_scenario(scenario)


func _physics_process(delta: float) -> void:
	if creature == null:
		return
	# Polled rather than evented, because a turn is a state rather than a
	# keystroke: the animal is being asked to turn for as long as the key is down.
	scenario.hand_turn((1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
		- (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0))
	scenario.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_9:
		hud.pick_scenario(key - KEY_1)
		return
	match key:
		KEY_SPACE:
			hud.toggle_pause()
		KEY_PERIOD:
			hud.step_once()
		KEY_RIGHT:
			hud.nudge_drive(PhysicsHud.NUDGE)
		KEY_LEFT:
			hud.nudge_drive(-PhysicsHud.NUDGE)
