## Calibration probe for propulsion: builds each preset, reads what its muscle,
## its levers and its legs come to, then accelerates it from a standstill and
## times the ramp — walking first, then flat out. Not a test — this is where the
## ground-push model's constants are argued about, the way StaminaProbe is for
## the aerobic ones.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/SprintProbe.gd
extends SceneTree

const TICK: float = 1.0 / 60.0
## Long enough for the heaviest build to arrive at its own top speed.
const RAMP_TICKS: int = 60 * 20

var main: Node
var done: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if done:
		return false
	done = true
	_run()
	quit(0)
	return true


func _run() -> void:
	var player: Creature = main.get_node("Creature")
	# Flat ground and an empty road, for the same reason StaminaProbe clears them:
	# every second printed below is a body against its own weight, not against a
	# rock it happened to meet.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, -40000.0), 0.0)
	for preset in ["Lizard", "Cat", "Elephant", "Cheetah", "T. rex", "Kangaroo"]:
		player.params.apply_preset(preset)
		player.reset(Vector2.ZERO, 0.0)
		for _tick in 30:
			player._physics_process(TICK)
		var loco: Locomotion = player.locomotion
		print("%s: mass %.3f  power %.3f  drive %.2f  lever %.2f/%.2f"
			% [preset, player.physique.mass, loco.power, player.posture.drive,
				loco.articulation.fore.advantage, loco.articulation.hind.advantage])
		print("    push %.0f px/s² (%.3f g)  duty %.2f  legs %.0f px/s  walks %.0f  flat out %.0f"
			% [loco.accel, loco.accel / Gravity.PULL, loco.duty,
				player.gait.leg_speed, player.cruise_speed(), player.flat_out()])
		_ramp(player, false)
		_ramp(player, true)

	# The fibre axis, which no preset spends: every species stands at the 0.5
	# no-op, so the only place composition shows is a build the creation menu has
	# moved off it. Both ends on the default body — the sprinter gets away harder
	# and the stayer duller, off the same legs, while Stamina tilts the store the
	# other way; see Locomotion.PUSH_TWITCH and Stamina.FIBRE_TILT.
	for fibre in [0.0, 1.0]:
		player.params.apply_preset("Lizard")
		player.params.fast_twitch = fibre
		player.reset(Vector2.ZERO, 0.0)
		for _tick in 30:
			player._physics_process(TICK)
		print("Lizard at fast twitch %.1f: push %.0f px/s² (%.3f g)"
			% [fibre, player.locomotion.accel, player.locomotion.accel / Gravity.PULL])
		_ramp(player, true)


## One standing start, held until the speed settles, and the shape of it printed:
## how far the body got in the first second and the first three, when it passed
## half and nine tenths of the speed it ended at, and what that speed was.
func _ramp(player: Creature, sprint: bool) -> void:
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 30:
		player._physics_process(TICK)
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.sprint = sprint
	var start: Vector2 = player.head_pos
	var top: float = 0.0
	for tick in RAMP_TICKS:
		player.command = drive
		player._physics_process(TICK)
		top = maxf(top, absf(player.speed))
	var t50: float = -1.0
	var t90: float = -1.0
	var at_1s: float = 0.0
	var at_3s: float = 0.0
	player.reset(Vector2.ZERO, 0.0)
	for _tick in 30:
		player._physics_process(TICK)
	start = player.head_pos
	for tick in RAMP_TICKS:
		player.command = drive
		player._physics_process(TICK)
		var now: float = float(tick + 1) * TICK
		if t50 < 0.0 and absf(player.speed) >= top * 0.5:
			t50 = now
		if t90 < 0.0 and absf(player.speed) >= top * 0.9:
			t90 = now
		if tick == 59:
			at_1s = start.distance_to(player.head_pos)
		if tick == 179:
			at_3s = start.distance_to(player.head_pos)
	player.command = MovementInput.Command.new()
	print("    %s: top %.0f px/s · half in %s · nine tenths in %s · %.0f px in 1 s · %.0f px in 3 s"
		% ["sprint" if sprint else "walk  ", top, _seconds(t50), _seconds(t90),
			at_1s, at_3s])


static func _seconds(at: float) -> String:
	return "never" if at < 0.0 else "%.2f s" % at
