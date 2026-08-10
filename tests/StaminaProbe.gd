## Calibration probe for stamina: builds each preset, walks it, then sprints it
## until the store is empty, and prints what its engine, its heart and its own
## weight came to. Not a test — this is where Stamina.REFERENCE_ENGINE was
## measured and where the shape of the constants above it is argued about.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/StaminaProbe.gd
extends SceneTree

const TICK: float = 1.0 / 60.0
## Long enough for anything in the file to blow, at 60 Hz.
const SPRINT_TICKS: int = 60 * 180

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
	# Every reading here is a body running against its own heart. A rock to climb
	# over or a carcass to walk into would be a body running against those, and the
	# seconds printed below would be a measurement of the habitat.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, -40000.0), 0.0)
	for preset in ["Lizard", "Cat", "Elephant", "Camel", "Cheetah", "T. rex", "Kangaroo"]:
		player.params.apply_preset(preset)
		player.reset(Vector2.ZERO, 0.0)
		for _tick in 30:
			player._physics_process(TICK)
		var s: Stamina = player.stamina
		var locomotor: float = player.physique.girdle_muscle.x + player.physique.girdle_muscle.y
		print("%s: mass %.4f  locomotor muscle %.0f cells  loco/mass %.4f"
			% [preset, player.physique.mass, locomotor,
				locomotor / maxf(player.physique.mass, 0.001)])
		print("    engine %.3f  heart %.2f  cardio %.3f  sustains %.2f of top  store %.1f s"
			% [s.engine, player.params.heart_power, s.cardio, s.capacity, s.depth])
		print("    walks %.0f px/s  flat out %.0f px/s  walk is %.2f of that  sustains %.0f px/s"
			% [player.cruise_speed(), player.flat_out(),
				player.cruise_speed() / player.flat_out(),
				s.capacity * player.flat_out()])

		# What a walk and a sprint actually work the legs at. Both are means over a
		# settled run rather than peaks: the ceiling the effort is quoted against
		# moves a little with the footfall pattern, and one tick of it is not what
		# the animal is doing.
		print("    walking %.2f effort · sprinting %.2f effort (sustains %.2f)"
			% [_mean_effort(player, false), _mean_effort(player, true), s.capacity])

		# Flat out, from full, until the store is gone — what the bar actually does
		# while the key is held.
		player.reset(Vector2.ZERO, 0.0)
		for _tick in 30:
			player._physics_process(TICK)
		var drive := MovementInput.Command.new()
		drive.throttle = 1.0
		drive.sprint = true
		var top: float = 0.0
		var winded_at: float = -1.0
		var empty_at: float = -1.0
		var held: float = 0.0
		for tick in SPRINT_TICKS:
			player.command = drive
			player._physics_process(TICK)
			var now: float = float(tick) * TICK
			top = maxf(top, absf(player.speed))
			if winded_at < 0.0 and player.stamina.winded:
				winded_at = now
			if empty_at < 0.0 and player.stamina.reserve <= 0.0:
				empty_at = now
				held = absf(player.speed)
				break
		print("    sprint %.0f px/s (%.2f effort) · winded at %s · spent at %s · held to %.0f px/s"
			% [top, top / player.flat_out(),
				_seconds(winded_at), _seconds(empty_at), held])

		# ...and standing still, which is the other half of the loop.
		var rested: float = -1.0
		for tick in SPRINT_TICKS:
			player.command = MovementInput.Command.new()
			player._physics_process(TICK)
			if player.stamina.reserve >= 0.999:
				rested = float(tick) * TICK
				break
		print("    recovers in %s standing" % _seconds(rested))


## Mean effort over five settled seconds of travel, walking or flat out.
static func _mean_effort(player: Creature, sprint: bool) -> float:
	var drive := MovementInput.Command.new()
	drive.throttle = 1.0
	drive.sprint = sprint
	for _tick in 120:
		player.command = drive
		player._physics_process(TICK)
	var total: float = 0.0
	for _tick in 300:
		player.command = drive
		player._physics_process(TICK)
		total += player.stamina.effort
	player.command = MovementInput.Command.new()
	return total / 300.0


static func _seconds(at: float) -> String:
	return "never" if at < 0.0 else "%.1f s" % at
