## Phase-3 gate for the v2 locomotion loop — see docs/V2_DESIGN.md §11.2.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/MotionProbe.gd
##
## Asserts what the loop claims to be, as behaviours rather than constants:
##
##   * **it stands** — no ask, no steps, no drift: a body whose support is not
##     being used up reorganises nothing.
##   * **acceleration drives it** — a throttle becomes a velocity through a
##     derived push; the speed never exceeds the ask, and the delivered
##     acceleration is printed as the calibration.
##   * **planted feet never creep** — a foot on the ground is a world-fixed
##     anchor, checked to the float.
##   * **the pattern comes out of the speed** — steps emerge from support
##     drift: near-continuous support strolling, diagonal company at a trot,
##     more air at a sprint. Nothing selects a gait by name.
##   * **it turns** — on the move as an arc, at a standstill by stepping the
##     body round; anatomy holds through both.
##   * **the world is anticipated** — a ledge on the path is climbed by feet
##     landing on the higher surface and each girdle riding its own feet, with
##     no ledge-case anywhere in the mover.
##   * **physics is not overridden** — a shove changes the real velocity; the
##     same loop that walks recovers, with rescue steps, or fails and falls.
##   * **a leap is ballistic** — take-off hands the body to the world's one
##     integrator; the plan velocity keeps; the feet gather and re-plant.
##   * **wounds weaken the engine** — a chewed haunch drops the derived power
##     and the planted grip, because the compartments shrank.
##   * **anatomy holds throughout** — every stick, bend and bone exact after
##     everything above.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false

## Worst anatomy errors accumulated over every scenario.
var worst_stick: float = 0.0
var worst_bend: float = 0.0
var worst_bone: float = 0.0


func _initialize() -> void:
	main = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var creature: Creature2 = main.creature
	_check(creature != null, "the lab did not build a creature")
	if creature == null:
		_finish()
		return false
	main.terrain.clear()

	_check_stands(creature)
	_check_delivers(creature)
	_check_no_creep(creature)
	_check_pattern(creature)
	_check_turns(creature)
	_check_ledge(creature)
	_check_shove(creature)
	_check_leap(creature)
	_check_wound(creature)

	_check(worst_stick <= 0.02,
		"a stick strayed %.4f px from its rest somewhere above" % worst_stick)
	_check(worst_bend <= 0.002,
		"a bend passed its graded limit by %.4f rad somewhere above" % worst_bend)
	_check(worst_bone <= 0.05,
		"a bone strayed %.4f px from its length somewhere above" % worst_bone)
	notes.append("anatomy through it all: stick %.4f / bend %.4f / bone %.4f"
		% [worst_stick, worst_bend, worst_bone])

	_finish()
	return false


# ------------------------------------------------------------------ helpers ----

func _tick(c: Creature2, n: int) -> void:
	for i in n:
		c._physics_process(TICK)
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())


func _calm(c: Creature2) -> void:
	main.terrain.clear()
	c.command.throttle = 0.0
	c.command.turn = 0.0
	c.command.sprint = false
	c.command.jump = false
	c.reset()
	_tick(c, 10)


## Ticks `n` and counts lift-offs, mean grounded feet, co-swing company.
func _observe(c: Creature2, n: int) -> Dictionary:
	var fw: Footwork = c.travel.footwork
	var was: Array[bool] = []
	for f in fw.feet:
		was.append(f.swinging)
	var lifts: int = 0
	var down_sum: float = 0.0
	var pair_ticks: int = 0
	var diagonal_ticks: int = 0
	var multi_ticks: int = 0
	for i in n:
		c._physics_process(TICK)
		var up: Array[int] = []
		for j in fw.feet.size():
			var f: Footwork.Foot = fw.feet[j]
			if f.swinging and not was[j]:
				lifts += 1
			was[j] = f.swinging
			if f.swinging:
				up.append(j)
		down_sum += fw.feet.size() - up.size()
		if up.size() >= 2:
			multi_ticks += 1
		if up.size() == 2:
			pair_ticks += 1
			if Rhythm.DIAGONAL[up[0]] == up[1]:
				diagonal_ticks += 1
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())
	return {
		"lifts": lifts,
		"down": down_sum / float(n),
		"multi": float(multi_ticks) / float(n),
		"diagonal": float(diagonal_ticks) / maxf(float(pair_ticks), 1.0),
	}


# ------------------------------------------------------------------- claims ----

func _check_stands(c: Creature2) -> void:
	_calm(c)
	var start: Vector2 = c.centre()
	var seen: Dictionary = _observe(c, 120)
	_check(int(seen["lifts"]) == 0,
		"an unasked body took %d steps standing still" % int(seen["lifts"]))
	var drift: float = c.centre().distance_to(start)
	_check(drift < 0.5, "standing still drifted the body %.3f px" % drift)
	_check(c.poise.feet == 4, "standing on %d feet of 4" % c.poise.feet)
	notes.append("stands: 4 feet, %.3f px drift in 2 s, no steps" % drift)


func _check_delivers(c: Creature2) -> void:
	_calm(c)
	c.command.throttle = 1.0
	var cruise: float = c.cruise_speed()
	var t_half: float = -1.0
	var t_nine: float = -1.0
	var top: float = 0.0
	for i in 300:
		c._physics_process(TICK)
		top = maxf(top, c.speed)
		if t_half < 0.0 and c.speed >= cruise * 0.5:
			t_half = float(i + 1) * TICK
		if t_nine < 0.0 and c.speed >= cruise * 0.9:
			t_nine = float(i + 1) * TICK
	_check(top <= cruise * 1.02,
		"the body outran its own ask: %.1f of %.1f px/s" % [top, cruise])
	_check(c.speed >= cruise * 0.95,
		"flat out the legs delivered %.1f of the %.1f asked" % [c.speed, cruise])
	_check(t_half > 0.0 and t_half <= 0.6,
		"half the cruise took %.2f s" % t_half)
	var accel: float = cruise * 0.5 / maxf(t_half, 0.001)
	notes.append("delivers: half cruise in %.2f s, nine tenths in %.2f s — %.0f px/s² (%.2f g), power %.3f"
		% [t_half, t_nine, accel, accel / Gravity.PULL, c.travel.impetus.power])


func _check_no_creep(c: Creature2) -> void:
	_calm(c)
	c.command.throttle = 1.0
	_tick(c, 120)
	var fw: Footwork = c.travel.footwork
	var anchors: Array[Vector2] = []
	for f in fw.feet:
		anchors.append(f.anchor)
	var worst: float = 0.0
	for i in 120:
		c._physics_process(TICK)
		for j in fw.feet.size():
			var f: Footwork.Foot = fw.feet[j]
			if not f.swinging:
				if anchors[j] != Vector2.INF:
					worst = maxf(worst, f.anchor.distance_to(anchors[j]))
				anchors[j] = f.anchor
			else:
				anchors[j] = Vector2.INF
	_check(worst == 0.0, "a planted foot crept %.6f px" % worst)
	notes.append("planted feet creep %.4f px a tick at cruise" % worst)


func _check_pattern(c: Creature2) -> void:
	# The stroll: support stays nearly continuous, steps come one at a time.
	_calm(c)
	c.command.throttle = 0.28
	_tick(c, 180)
	var stroll: Dictionary = _observe(c, 180)
	_check(float(stroll["down"]) >= 2.7,
		"strolling kept only %.2f feet down" % float(stroll["down"]))
	_check(float(stroll["multi"]) <= 0.15,
		"strolling had two feet up %.0f%% of the time" % (float(stroll["multi"]) * 100.0))

	# The trot: at cruise the diagonal coupling pairs the beats.
	_calm(c)
	c.command.throttle = 1.0
	_tick(c, 180)
	var trot: Dictionary = _observe(c, 180)
	_check(float(trot["down"]) < float(stroll["down"]),
		"cruise kept as many feet down as the stroll")
	_check(float(trot["diagonal"]) >= 0.55,
		"at cruise only %.0f%% of paired swings were diagonal"
		% (float(trot["diagonal"]) * 100.0))

	# The sprint: more of the cycle in the air, and genuinely faster.
	_calm(c)
	c.command.throttle = 1.0
	c.command.sprint = true
	_tick(c, 240)
	var sprint: Dictionary = _observe(c, 180)
	var sprint_speed: float = c.speed
	_check(float(sprint["down"]) < float(stroll["down"]) - 0.5,
		"sprinting kept %.2f feet down against the stroll's %.2f"
		% [float(sprint["down"]), float(stroll["down"])])
	_check(sprint_speed > c.cruise_speed() * 1.15,
		"the sprint delivered %.1f px/s over a cruise of %.1f"
		% [sprint_speed, c.cruise_speed()])
	notes.append("pattern from speed: stroll %.2f / trot %.2f / sprint %.2f feet down, %.0f%% diagonal at the trot, sprint %.0f px/s"
		% [float(stroll["down"]), float(trot["down"]), float(sprint["down"]),
			float(trot["diagonal"]) * 100.0, sprint_speed])


func _check_turns(c: Creature2) -> void:
	# On the move: the same ask plus a turn is an arc.
	_calm(c)
	c.command.throttle = 1.0
	_tick(c, 90)
	var heading_was: float = c.heading
	c.command.turn = 1.0
	_tick(c, 90)
	var swung: float = absf(wrapf(c.heading - heading_was, -PI, PI))
	_check(swung > 0.8, "1.5 s of full turn on the move swung %.2f rad" % swung)
	_check(c.speed > c.cruise_speed() * 0.5,
		"turning bled the walk to %.1f px/s" % c.speed)

	# At a standstill: the legs walk the body round, stepping as they go.
	_calm(c)
	var start: Vector2 = c.centre()
	heading_was = c.heading
	c.command.turn = 1.0
	var seen: Dictionary = _observe(c, 120)
	swung = absf(wrapf(c.heading - heading_was, -PI, PI))
	var wander: float = c.centre().distance_to(start)
	_check(swung > 1.2, "2 s of standstill turn swung only %.2f rad" % swung)
	_check(wander < 18.0, "the standstill turn wandered %.1f px off the spot" % wander)
	_check(int(seen["lifts"]) >= 2,
		"the body turned %.2f rad on planted feet — %d steps" % [swung, int(seen["lifts"])])
	notes.append("turns: %.2f rad on the spot in 2 s, %d steps, %.1f px of wander"
		% [swung, int(seen["lifts"]), wander])


func _check_ledge(c: Creature2) -> void:
	_calm(c)
	var dir: Vector2 = c.move_dir
	var foot: Vector2 = c.centre() + dir * 180.0
	main.terrain.add(foot, 160.0, 10.0)
	c.command.throttle = 0.8
	var most_split: float = 0.0
	var fell: bool = false
	for i in 260:
		c._physics_process(TICK)
		most_split = maxf(most_split,
			c.armature.fore_carry - c.armature.hind_carry)
		fell = fell or c.armature.collapsed
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())
	var rest_split: float = a.fore_stance - a.hind_stance
	_check(not fell, "a 10 px ledge felled the body")
	_check(most_split - rest_split >= 4.0,
		"the fore girdle never climbed ahead: carry split rose %.1f px over rest"
		% (most_split - rest_split))
	var up_fore: float = a.fore_carry - a.fore_stance
	var up_hind: float = a.hind_carry - a.hind_stance
	_check(up_fore > 7.0 and up_hind > 7.0,
		"the body did not end up on the ledge (carries +%.1f / +%.1f px)"
		% [up_fore, up_hind])
	notes.append("a 10 px ledge is climbed: fore leads by %.1f px, both girdles end +%.1f/+%.1f"
		% [most_split - rest_split, up_fore, up_hind])
	main.terrain.clear()


func _check_shove(c: Creature2) -> void:
	_calm(c)
	var side: Vector2 = Vector2(-c.move_dir.y, c.move_dir.x)
	c.shove(side * 300.0)
	var seen: Dictionary = _observe(c, 90)
	_check(not c.armature.collapsed, "a 300 px/s shove felled a standing body")
	_check(c.speed < 5.0, "1.5 s after a shove the body still slides at %.1f px/s" % c.speed)
	_check(int(seen["lifts"]) >= 1,
		"the shove was absorbed without a single recovery step")
	var steadiness: float = c.poise.steadiness()
	_check(steadiness >= 0.0,
		"recovered from the shove but standing at steadiness %.2f" % steadiness)
	notes.append("a 300 px/s shove is caught in %d steps, steadiness back to %.2f"
		% [int(seen["lifts"]), steadiness])


func _check_leap(c: Creature2) -> void:
	_calm(c)
	c.command.throttle = 1.0
	_tick(c, 90)
	var v_before: float = c.speed
	c.command.jump = true
	_tick(c, 24)
	c.command.jump = false
	var peak: float = 0.0
	var flew: int = 0
	var landed: bool = false
	for i in 120:
		c._physics_process(TICK)
		if c.armature.fall.is_airborne():
			flew += 1
			peak = maxf(peak, c.armature.fall.height)
			if c.poise.feet != 0:
				_check(false, "airborne on %d planted feet" % c.poise.feet)
				break
		elif flew > 0:
			landed = true
			break
	var kept: float = c.speed
	_check(flew > 6, "the charged jump never left the ground")
	_check(peak >= 6.0, "the jump peaked at %.1f px" % peak)
	_check(landed, "the leap never came down")
	_check(kept > v_before * 0.5,
		"the take-off threw the run away: %.1f px/s of %.1f kept" % [kept, v_before])
	c.command.throttle = 0.0
	_tick(c, 60)
	_check(not c.armature.collapsed, "the landing felled the body")
	_check(c.poise.feet == 4,
		"pulled up after the landing, only %d feet are down" % c.poise.feet)
	notes.append("a running leap peaks %.1f px, keeps %.0f%% of its speed, lands on its feet"
		% [peak, kept / maxf(v_before, 0.1) * 100.0])


func _check_wound(c: Creature2) -> void:
	_calm(c)
	var power_before: float = c.travel.impetus.power
	for station in 2:
		for sector in BodySchema.SECTORS[BodySchema.LIMB]:
			c.corpus.gouge(&"HL", station, sector, 10.0)
	_tick(c, 5)
	var power_after: float = c.travel.impetus.power
	var grip: float = c.travel.footwork.grip
	_check(power_after < power_before - 0.001,
		"a chewed thigh left the engine at power %.3f" % power_after)
	_check(grip < 0.995,
		"a chewed thigh left the standing grip at %.3f" % grip)
	notes.append("a chewed thigh drops power %.3f → %.3f and standing grip to %.2f"
		% [power_before, power_after, grip])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("motion OK — the loop stands, walks and recovers: %s" % " · ".join(notes))
	else:
		print("MOTION FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
