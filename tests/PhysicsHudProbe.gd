## Gate for the standalone Physics HUD — the bench, its nine scenarios and the
## clock it holds.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/PhysicsHudProbe.gd
##
## `tests/MotionHudProbe.gd` already pins the seam itself — that what the panel
## draws is what `Footwork`, `Poise`, `Keel` and `Impetus` measured, to the float.
## What is checked here is the half that is new: that the scenarios are *commands*
## and the loop genuinely answers them, that a scenario which builds ground builds
## the ground it says it does, that the panel prints the seam it was handed, and
## that the clock it borrows is given back.
##
##   * **the drive is the ask** — what the slider asks for is what the loop
##     reports being asked for, and letting go of the throttle stops the animal.
##   * **each scenario does its own thing** — the standing start accelerates, the
##     brake stops, the two turns turn (one on the spot, one at speed), the ledge
##     is climbed, the brink is balked at, the shove displaces the body sideways
##     and the collapse puts it down.
##   * **a looping scenario starts over** — and the body is back where it began.
##   * **the panel invents nothing** — every reading on the left rail is the seam,
##     formatted.
##   * **the clock is borrowed and given back** — pause stops the world, a step is
##     exactly one tick, and slow motion is the rate that was asked for.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var notes: Array[String] = []
var bench: PhysicsBench
var creature: Creature2
var hud: PhysicsHud
var scenario: MotionScenario
var checked: bool = false


func _initialize() -> void:
	bench = load("res://scenes/PhysicsHud.tscn").instantiate() as PhysicsBench
	root.add_child(bench)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	creature = bench.creature
	hud = bench.hud
	scenario = bench.scenario
	_check(creature != null and hud != null and scenario != null,
		"the bench did not build a creature, a HUD and a scenario")
	if creature == null or hud == null or scenario == null:
		_finish()
		return false

	_check_drive_is_the_ask()
	_check_standing_start()
	_check_brake()
	_check_turn_on_the_spot()
	_check_turn_at_cruise()
	_check_ledge()
	_check_brink()
	_check_shove()
	_check_collapse()
	_check_loop_restarts()
	_check_panel_reads_the_seam()
	_check_gives_the_clock_back()

	_finish()
	return false


# ------------------------------------------------------------------ helpers ----

## The bench's own tick order: the scenario asks, and then the body answers.
func _run(seconds: float) -> void:
	for _i in int(maxf(seconds, 0.0) / TICK):
		bench._physics_process(TICK)
		creature._physics_process(TICK)


func _start(which: int) -> void:
	hud.pick_scenario(which)


func _travelled(from: Vector2) -> float:
	return creature.centre().distance_to(from)


# ------------------------------------------------------------------- claims ----

## The slider is an ask, and the ask is what the loop says it was asked for.
## Letting go of it is the other half: a hand on the drive outranks the script.
func _check_drive_is_the_ask() -> void:
	_start(0)
	scenario.hand_drive(0.5)
	_run(1.5)
	var r: MotionReadout = creature.motion_readout()
	var want: float = 0.5 * creature.flat_out()
	_check(absf(r.ask - want) < 1.0,
		"drive at 0.50 asked the loop for %.1f px/s, not %.1f" % [r.ask, want])
	_check(scenario.manual, "taking the drive did not take the scenario off its script")
	_run(2.0)
	_check(r.speed > MotionReadout.TRAVELLING,
		"a half-open drive left the animal at %.1f px/s" % r.speed)
	scenario.hand_drive(0.0)
	_run(2.5)
	_check(r.speed < 8.0, "the drive was shut and the animal is still at %.1f px/s" % r.speed)
	notes.append("the drive is the ask: 0.50 → %.0f px/s asked, shut → %.1f px/s"
		% [want, r.speed])


## S2: from a standstill to everything. What is being checked is that the body
## accelerates *and* that it had to — a delivery that never falls short of the
## demand is a body with no mass to feel.
func _check_standing_start() -> void:
	_start(1)
	var r: MotionReadout = creature.motion_readout()
	_run(0.35)
	var before: float = r.speed
	var clamped: bool = false
	for _i in int(3.0 / TICK):
		bench._physics_process(TICK)
		creature._physics_process(TICK)
		if r.demand > MotionReadout.DEMANDING and r.delivered < r.demand - 0.5:
			clamped = true
	_check(before < 12.0, "the standing start was already at %.1f px/s" % before)
	_check(r.speed > 0.5 * creature.flat_out(),
		"three seconds of full throttle reached %.1f px/s of %.1f"
		% [r.speed, creature.flat_out()])
	_check(clamped, "the demand was never clamped — the body felt no mass at all")
	notes.append("standing start: %.1f → %.1f px/s, demand clamped on the way"
		% [before, r.speed])


func _check_brake() -> void:
	_start(2)
	var r: MotionReadout = creature.motion_readout()
	_run(0.6)
	var moving: float = r.speed
	_run(2.5)
	_check(moving > MotionReadout.TRAVELLING,
		"the brake scenario never got moving (%.1f px/s)" % moving)
	_check(r.speed < 8.0, "the brake left the animal at %.1f px/s" % r.speed)
	notes.append("brake: %.1f px/s → %.1f px/s" % [moving, r.speed])


## S4: a turn on the spot is the legs walking the body round — the heading comes
## about and the animal stays where it is.
func _check_turn_on_the_spot() -> void:
	_start(3)
	var from: Vector2 = creature.centre()
	var was: float = creature.heading
	_run(3.0)
	var swung: float = absf(wrapf(creature.heading - was, -PI, PI))
	_check(swung > 0.5, "turning on the spot came round %.2f rad in three seconds" % swung)
	_check(_travelled(from) < 60.0,
		"a turn on the spot travelled %.1f px" % _travelled(from))
	notes.append("turn on the spot: %.2f rad, %.1f px travelled"
		% [swung, _travelled(from)])


func _check_turn_at_cruise() -> void:
	_start(4)
	var was: float = creature.heading
	_run(3.5)
	var swung: float = absf(wrapf(creature.heading - was, -PI, PI))
	var r: MotionReadout = creature.motion_readout()
	_check(swung > 0.4, "turning at cruise came round %.2f rad" % swung)
	_check(r.speed > MotionReadout.TRAVELLING,
		"the turn at cruise is not at cruise (%.1f px/s)" % r.speed)
	notes.append("turn at cruise: %.2f rad at %.1f px/s" % [swung, r.speed])


## S6: the ledge is built, and it is climbed — the body ends up standing on it,
## which is the whole of "a step is walked up in stride".
func _check_ledge() -> void:
	_start(5)
	_check(bench.terrain.obstacles.size() == 1,
		"the ledge scenario built %d obstacles" % bench.terrain.obstacles.size())
	_run(6.0)
	var under: float = creature.ground_at(creature.centre())
	_check(under > MotionScenario.LEDGE_RISE - 0.5,
		"six seconds of walking left the body over ground at %.1f px, not on the +%d ledge"
		% [under, int(MotionScenario.LEDGE_RISE)])
	notes.append("ledge: standing on ground %.0f px up" % under)


## S7: the brink is the same measurement the other way round — the drop is past
## what a leg can reach down, so the ask is refused and the body stops at the rim
## instead of walking off it.
func _check_brink() -> void:
	_start(6)
	var r: MotionReadout = creature.motion_readout()
	var balked: bool = false
	var rim: float = creature.armature.spawn_at.x + MotionScenario.BRINK_AT
	for _i in int(8.0 / TICK):
		bench._physics_process(TICK)
		creature._physics_process(TICK)
		if r.headroom <= 0.0:
			balked = true
	_check(balked, "the body never balked at a %d px drop" % int(MotionScenario.BRINK_DROP))
	_check(creature.centre().x < rim + 20.0,
		"the body walked %.1f px past the brink" % (creature.centre().x - rim))
	notes.append("brink: balked, stopped %.0f px short of the rim"
		% (rim - creature.centre().x))


## S8: the shove is a velocity the body did not ask for, arriving through the
## same seam a charge does — so the animal is genuinely carried sideways, heels
## over, and *catches itself*. The last part is the scenario: a blow that put the
## body down would be S9 twice over.
func _check_shove() -> void:
	_start(7)
	_run(MotionScenario.SHOVE_AT - 0.05)
	var facing: Vector2 = Vector2.RIGHT.rotated(creature.heading)
	var across := Vector2(-facing.y, facing.x)
	var was: Vector2 = creature.centre()
	var r: MotionReadout = creature.motion_readout()
	var sideways: float = 0.0
	var heel: float = 0.0
	var rescued: bool = false
	for _i in int(2.0 / TICK):
		bench._physics_process(TICK)
		creature._physics_process(TICK)
		sideways = maxf(sideways, absf((creature.centre() - was).dot(across)))
		heel = maxf(heel, absf(r.roll))
		rescued = rescued or r.state == &"RESCUE"
	_check(sideways > 6.0,
		"a %.0f px/s shove moved the body %.1f px sideways"
		% [scenario.shove_speed(), sideways])
	_check(rescued, "the shove never asked the legs for a rescue step")
	_check(not creature.armature.collapsed,
		"the shove put the body down — that is the collapse scenario, not this one")
	notes.append("shove: %.0f px/s put the body %.1f px across its own line and %.1f° over, caught by rescue steps"
		% [scenario.shove_speed(), sideways, rad_to_deg(heel)])


func _check_collapse() -> void:
	_start(8)
	_run(MotionScenario.COLLAPSE_AT + 1.0)
	_check(creature.armature.collapsed, "the collapse scenario left the body standing")
	_check(creature.motion_readout().state == &"COLLAPSED",
		"the loop reports %s after a collapse" % creature.motion_readout().state)
	notes.append("collapse: the body is down and the loop says so")


## A scenario with a loop starts over, and starting over is a real reset: the body
## is back at its spawn and the record is empty behind it.
func _check_loop_restarts() -> void:
	_start(8)
	var spawn: Vector2 = creature.armature.spawn_at
	_run(7.2)
	_check(scenario.elapsed < 1.0,
		"a 7.0 s scenario is %.2f s in — it never looped" % scenario.elapsed)
	_check(not creature.armature.collapsed, "the restart left the body collapsed")
	_check(creature.centre().distance_to(spawn) < 120.0,
		"the restart left the body %.0f px from its spawn"
		% creature.centre().distance_to(spawn))
	notes.append("a looping scenario starts over: %.2f s in, body back at its spawn"
		% scenario.elapsed)


## The left rail is the seam, formatted — nothing on it is worked out here.
func _check_panel_reads_the_seam() -> void:
	_start(0)
	_run(2.5)
	hud.refresh()
	var r: MotionReadout = creature.motion_readout()
	var want: Dictionary = {
		"ASK": "%.0f PX/S" % r.ask,
		"SPEED": "%.1f PX/S" % r.speed,
		"DEMAND": "%.0f PX/S²" % r.demand,
		"DELIVERED": "%.0f PX/S²" % r.delivered,
		"CEILING": "%.0f PX/S²" % r.ceiling,
		"GRIP": "%.2f" % r.grip,
		"FEET DOWN": "%d / %d" % [r.feet_down, r.steps.size()],
		"MARGIN": "%.1f PX" % r.margin,
		"STEADINESS": "%.2f" % r.steadiness,
		"ROLL": "%.1f°" % rad_to_deg(r.roll),
	}
	for key in want:
		var label: Label = hud._loop.get(key)
		_check(label != null and label.text == str(want[key]),
			"the panel prints %s for %s, the seam says %s"
			% ["nothing" if label == null else label.text, key, want[key]])
	_check(hud._state.text == str(r.state),
		"the panel says %s and the loop says %s" % [hud._state.text, r.state])
	notes.append("every reading on the rail is the seam: %d checked" % want.size())


## The clock is the one thing the panel takes that is not its own.
func _check_gives_the_clock_back() -> void:
	_start(0)
	_run(1.0)
	hud.set_rate(0.25)
	_check(is_equal_approx(Engine.time_scale, 0.25),
		"slow motion asked for 0.25× and the world runs at %.2f×" % Engine.time_scale)
	hud.toggle_pause()
	_check(is_equal_approx(Engine.time_scale, 0.0),
		"pausing left the world running at %.2f×" % Engine.time_scale)
	var before: int = creature.motion_readout().samples()
	var at: Vector2 = creature.centre()
	hud.step_once()
	_check(creature.motion_readout().samples() == before + 1,
		"one step advanced the loop by %d ticks"
		% (creature.motion_readout().samples() - before))
	_check(at.distance_to(creature.centre()) < 5.0,
		"one step moved the body %.1f px" % at.distance_to(creature.centre()))
	hud.toggle_pause()
	_check(is_equal_approx(Engine.time_scale, 0.25),
		"unpausing left the world at %.2f× rather than back at the slow rate"
		% Engine.time_scale)
	hud.set_rate(1.0)
	hud._exit_tree()
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"the panel kept the clock at %.2f× on its way out" % Engine.time_scale)
	notes.append("the clock is borrowed and given back: 0.25× slow, paused, stepped one tick, released")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("physics HUD OK — the scenarios drive the loop and the panel reads it: %s"
			% " · ".join(notes))
	else:
		print("PHYSICS HUD FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
