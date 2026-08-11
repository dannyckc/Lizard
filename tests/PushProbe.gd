## Calibration probe for v2 propulsion — SprintProbe's successor.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/PushProbe.gd
##
## Not a test. This is where the ground-push model's constants are argued about:
## it builds the reference cat, reads what its muscle, its levers and its legs come
## to, then accelerates it from a standstill and times the ramp — walking first,
## then flat out. Everything printed is derived from the census; nothing in the v2
## body has an acceleration parameter, so if a number below is wrong the argument
## is about `Locomotor.PUSH_REFERENCE`, the knots, or the laws — never about tuning
## one animal.
##
## The rows after the default body are the axes the creation menu will have: fibre
## composition either way of the mixed default (a sprinter gets away harder and a
## stayer duller off the same legs), and muscle laid on or taken off the girdles,
## which is the one thing `power` is a ratio of.
extends SceneTree

const TICK: float = 1.0 / 60.0
## Long enough for the heaviest build to arrive at its own top speed.
const RAMP_TICKS: int = 60 * 20

var main: Node
var done: bool = false


func _initialize() -> void:
	main = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if done:
		return false
	done = true
	_run()
	quit(0)
	return true


func _run() -> void:
	var c: Creature2 = main.creature
	# Flat ground and an empty road: every second printed below is a body against
	# its own weight, not against a rock it happened to meet.
	main.terrain.clear()

	_report(c, "reference cat")

	for fibre: float in [0.0, 1.0]:
		var was: float = c.body.fast_twitch
		c.body.fast_twitch = fibre
		c.build(Vector2.ZERO, 0.0)
		_report(c, "fast twitch %.1f" % fibre)
		c.body.fast_twitch = was

	# Muscle either way, which is the axis `power` is a ratio of: the same skeleton
	# with more or less on it. Written as a multiplier over the authored knots,
	# exactly as the creation menu's sliders will write them.
	for gain: float in [0.7, 1.4]:
		var knots: Dictionary = c.body.tissue_knots.duplicate(true)
		for group: StringName in knots:
			var layers: Dictionary = knots[group]
			var muscle: Array = layers.get(BodySchema.Layer.MUSCLE, [])
			for knot: Array in muscle:
				knot[1] *= gain
				knot[2] *= gain
		var was: Dictionary = c.body.tissue_knots
		c.body.tissue_knots = knots
		c.build(Vector2.ZERO, 0.0)
		_report(c, "muscle x%.1f" % gain)
		c.body.tissue_knots = was
	c.build(Vector2.ZERO, 0.0)


## One body: what it is, and then two standing starts.
func _report(c: Creature2, label: String) -> void:
	_settle(c, 90)
	var loco: Locomotor = c.locomotor
	var joints: Carriage = c.attitude.active
	print("%s: mass %.1f  power %.3f  drive %.2f  lever %.2f/%.2f  stance %s"
		% [label, c.corpus.mass(), loco.power, joints.drive,
			joints.fore.advantage, joints.hind.advantage, c.attitude.describe()])
	print("    push %.0f px/s² (%.3f g)  duty %.2f  swing %.0f ms  legs %.0f px/s  walks %.0f  flat out %.0f"
		% [loco.accel, loco.accel / Gravity.PULL, loco.duty,
			loco.swing_time(c.body.hind_leg_length, joints.hind.gear) * 1000.0,
			c.tread.leg_speed, c.cruise_speed(), c.flat_out()])
	print("    stands %.1f/%.1f px  stride %.1f px  leap %.0f px (%.2f heights)  launch %.2f"
		% [c.tread.shoulder_height, c.tread.hip_height, c.tread.stride_shared,
			c.bound.full, c.bound.heights(c.tread.support), c.bound.launch])
	_ramp(c, false)
	_ramp(c, true)


## One standing start, held until the speed settles, and the shape of it printed:
## how far the body got in the first second and the first three, when it passed
## half and nine tenths of the speed it ended at, and what that speed was.
func _ramp(c: Creature2, sprint: bool) -> void:
	# Standing, and asked for nothing, before the start is taken — a body still
	# carrying the last run's speed would time its ramp from halfway up it.
	c.command.throttle = 0.0
	c.command.sprint = false
	c.reset()
	_settle(c, 30)
	var top: float = 0.0
	for _tick in RAMP_TICKS:
		c.command.throttle = 1.0
		c.command.sprint = sprint
		c._physics_process(TICK)
		top = maxf(top, absf(c.speed))

	var t50: float = -1.0
	var t90: float = -1.0
	var at_1s: float = 0.0
	var at_3s: float = 0.0
	c.command.throttle = 0.0
	c.command.sprint = false
	c.reset()
	_settle(c, 30)
	var start: Vector2 = c.armature.centre()
	for tick in RAMP_TICKS:
		c.command.throttle = 1.0
		c.command.sprint = sprint
		c._physics_process(TICK)
		var now: float = float(tick + 1) * TICK
		if t50 < 0.0 and absf(c.speed) >= top * 0.5:
			t50 = now
		if t90 < 0.0 and absf(c.speed) >= top * 0.9:
			t90 = now
		if tick == 59:
			at_1s = start.distance_to(c.armature.centre())
		if tick == 179:
			at_3s = start.distance_to(c.armature.centre())
	print("    %s: top %.0f px/s · %s · half in %s · nine tenths in %s · %.0f px in 1 s · %.0f px in 3 s"
		% ["sprint" if sprint else "walk  ", top, c.tread.cadence.describe(),
			_seconds(t50), _seconds(t90), at_1s, at_3s])
	c.command.throttle = 0.0
	c.command.sprint = false


func _settle(c: Creature2, ticks: int) -> void:
	for _i in ticks:
		c._physics_process(TICK)


static func _seconds(at: float) -> String:
	return "never" if at < 0.0 else "%.2f s" % at
