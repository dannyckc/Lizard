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
##   * **it turns, and it turns by steering** — on the move as an arc, at a
##     standstill by stepping the body round, and either way the front of the
##     animal leads the back of it: A and D bend the body into the turn rather
##     than rotating it whole. Anatomy holds through both.
##   * **backwards is backwards** — the reverse walks the body away from what it
##     is facing, on its feet, while it goes on facing it: no turning round to
##     set off, and no crabbing sideways.
##   * **the world is anticipated** — a ledge on the path is climbed by feet
##     landing on the higher surface and each girdle riding its own feet, with
##     no ledge-case anywhere in the mover — and the body starts carrying
##     itself higher *before* any foot has reached the step.
##   * **a wall is a solid, not a rule** — the walk brakes to a brace against
##     it, and neither the ask nor a shove can put the trunk inside it: the
##     contact changes the real position and velocity, and the loop reacts.
##   * **a brink is balked at, and a fall off it is real** — the walk stops at
##     a drop the legs cannot deliver, feet crowd at the edge rather than
##     following the body over, and a body shoved past it loses its support
##     and arrives at the ground below.
##   * **physics is not overridden** — a shove changes the real velocity; the
##     same loop that walks recovers, with rescue steps, or fails and falls.
##   * **a leap is ballistic** — take-off hands the body to the world's one
##     integrator; the plan velocity keeps; the feet gather and re-plant —
##     and the arc ends on the surface the body is actually over, so a leap
##     lands on the table it crossed onto.
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
	_check_reverse(creature)
	_check_ledge(creature)
	_check_wall(creature)
	_check_wall_shove(creature)
	_check_brink(creature)
	_check_shove(creature)
	_check_leap(creature)
	_check_vault(creature)
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
		# A foot already in the air is seeded as no anchor at all. Its `anchor` is
		# last stride's and means nothing until it lands, so comparing the landing
		# against it reports a whole stride of "creep" — which is what this used to
		# do whenever a swing happened to end on the first observed tick.
		anchors.append(Vector2.INF if f.swinging else f.anchor)
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
	# ...and it is a *steer*: the front of the animal is ahead of the back of it
	# the whole way round. A body that turned as one rigid piece would read
	# exactly zero here, which is what it used to read.
	var lead: float = absf(wrapf(c.armature.fwd[c.armature.withers_index()].angle()
		- c.armature.fwd[c.armature.pelvis_index()].angle(), -PI, PI))
	_check(lead > deg_to_rad(8.0),
		"the standstill turn led with %.1f° of back — the animal turned as one piece"
			% rad_to_deg(lead))
	_check(lead <= c.travel._steer_lead(c.armature) + 0.05,
		"the back was bent %.1f° into the turn, past the %.1f° it steers with"
			% [rad_to_deg(lead), rad_to_deg(c.travel._steer_lead(c.armature))])
	notes.append("turns: %.2f rad on the spot in 2 s, %d steps, %.1f px of wander, front leading by %.0f°"
		% [swung, int(seen["lifts"]), wander, rad_to_deg(lead)])


## Backwards is backwards: the animal walks away from what it is facing, and it
## keeps facing it.
##
## Three separate things, and the old mover failed all three at once because it
## towed the pinned head back through its own neck: the trunk buckled sideways,
## the body ended up pointing the way it had come, and the animal had travelled
## a fifth of what it should have while doing it.
func _check_reverse(c: Creature2) -> void:
	_calm(c)
	var faced: float = c.heading
	var facing: Vector2 = Vector2.RIGHT.rotated(faced)
	var start: Vector2 = c.centre()
	c.command.throttle = -1.0
	_tick(c, 150)
	c.command.throttle = 0.0
	var went: Vector2 = c.centre() - start
	var a: Armature = c.armature
	var back: float = (a.plan(a.withers_index()) - a.plan(a.pelvis_index())).angle()

	_check(absf(wrapf(c.heading - faced, -PI, PI)) < 0.08,
		"backing up swung the heading %.1f°" % rad_to_deg(wrapf(c.heading - faced, -PI, PI)))
	_check(absf(wrapf(back - faced, -PI, PI)) < 0.35,
		"the animal backed up with its body turned %.0f° off the way it set out facing"
			% rad_to_deg(wrapf(back - faced, -PI, PI)))
	_check(went.dot(facing) < -60.0,
		"2.5 s of reverse carried the body %.1f px backwards" % -went.dot(facing))
	# ...and backwards, not sideways: a jack-knifed body crabs.
	_check(absf(went.dot(Vector2(-facing.y, facing.x))) < absf(went.dot(facing)) * 0.25,
		"the reverse wandered %.1f px sideways over %.1f px back"
			% [absf(went.dot(Vector2(-facing.y, facing.x))), -went.dot(facing)])
	# The reverse is gaited, not slid: the feet carry it.
	_calm(c)
	c.command.throttle = -1.0
	var seen_back: Dictionary = _observe(c, 150)
	c.command.throttle = 0.0
	_check(int(seen_back["lifts"]) >= 4,
		"the animal reversed on %d steps — it was being slid, not walked"
			% int(seen_back["lifts"]))
	notes.append("reverse: %.0f px back and %.1f px aside in 2.5 s, heading held to %.1f°, body %.0f° off, %d steps"
		% [-went.dot(facing), absf(went.dot(Vector2(-facing.y, facing.x))),
			rad_to_deg(absf(wrapf(c.heading - faced, -PI, PI))),
			rad_to_deg(absf(wrapf(back - faced, -PI, PI))), int(seen_back["lifts"])])


func _check_ledge(c: Creature2) -> void:
	_calm(c)
	var dir: Vector2 = c.move_dir
	var rest_fore: float = c.armature.fore_carry
	var foot: Vector2 = c.centre() + dir * 240.0
	main.terrain.add(foot, 160.0, 10.0)
	c.command.throttle = 0.8
	var most_split: float = 0.0
	var pre_lift: float = 0.0
	var fell: bool = false
	for i in 260:
		c._physics_process(TICK)
		most_split = maxf(most_split,
			c.armature.fore_carry - c.armature.hind_carry)
		fell = fell or c.armature.collapsed
		# The anticipation: while no fore foot has yet stood on the ledge, any
		# rise in the fore carry is the body adjusting its own trajectory to a
		# step it has only *seen*.
		var fore_up: bool = false
		for f in c.travel.footwork.feet:
			if f.fore and not f.swinging and f.anchor_z > 0.5:
				fore_up = true
		if not fore_up:
			pre_lift = maxf(pre_lift, c.armature.fore_carry - rest_fore)
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())
	var rest_split: float = a.fore_stance - a.hind_stance
	_check(not fell, "a 10 px ledge felled the body")
	_check(pre_lift >= 1.5,
		"the body never began carrying itself higher before its feet reached the step (pre-lift %.2f px)"
		% pre_lift)
	_check(most_split - rest_split >= 4.0,
		"the fore girdle never climbed ahead: carry split rose %.1f px over rest"
		% (most_split - rest_split))
	var up_fore: float = a.fore_carry - a.fore_stance
	var up_hind: float = a.hind_carry - a.hind_stance
	_check(up_fore > 7.0 and up_hind > 7.0,
		"the body did not end up on the ledge (carries +%.1f / +%.1f px)"
		% [up_fore, up_hind])
	notes.append("a 10 px ledge is anticipated %.1f px early and climbed: fore leads by %.1f px, both girdles end +%.1f/+%.1f"
		% [pre_lift, most_split - rest_split, up_fore, up_hind])
	main.terrain.clear()


## A wall is a solid, not a rule: the walk brakes to a brace against it and
## the trunk is never inside it — the contact presses the state out, the ask
## dies against the face, and the body stands braced rather than churning.
func _check_wall(c: Creature2) -> void:
	_calm(c)
	var dir: Vector2 = c.move_dir
	var at: Vector2 = c.centre() + dir * 140.0
	main.terrain.add(at, 70.0, 60.0)
	c.command.throttle = 1.0
	var worst_in: float = 0.0
	for i in 300:
		c._physics_process(TICK)
		worst_in = maxf(worst_in, 70.0 - c.centre().distance_to(at))
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())
	_check(not a.collapsed, "walking into a wall felled the body")
	_check(worst_in < 1.0,
		"the walk pressed the body %.1f px inside a solid wall" % worst_in)
	_check(c.speed < 15.0,
		"still driving at %.1f px/s against a wall after 5 s" % c.speed)
	notes.append("a wall stops the walk: braced %.1f px clear of the face at %.1f px/s"
		% [maxf(-worst_in, 0.0), c.speed])
	main.terrain.clear()


## Physics cannot put the body through the wall either: a hard shove into the
## face is a contact, and what changes is the state — the velocity into the
## face dies at it, the slide is held, and the body ends up against the wall,
## not inside or beyond it.
func _check_wall_shove(c: Creature2) -> void:
	_calm(c)
	var dir: Vector2 = c.move_dir
	var at: Vector2 = c.centre() + dir * 120.0
	main.terrain.add(at, 70.0, 60.0)
	c.shove(dir * 420.0)
	var worst_in: float = 0.0
	for i in 180:
		c._physics_process(TICK)
		worst_in = maxf(worst_in, 70.0 - c.centre().distance_to(at))
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())
	_check(worst_in < 1.0,
		"a 420 px/s shove drove the body %.1f px into a solid wall" % worst_in)
	_check(c.speed < 8.0,
		"3 s after being shoved at a wall the body still slides at %.1f px/s" % c.speed)
	_check(not a.collapsed, "a shove a wall absorbed still felled the body")
	notes.append("shoved at 420 px/s into a wall, the body is stopped by it — never inside, %.1f px/s left"
		% c.speed)
	main.terrain.clear()


## A brink is balked at, and a fall off it is real: the walk stops at a drop
## the legs cannot deliver, the feet crowd at the edge rather than following
## the body over — and a body shoved past the edge loses its support, falls,
## and arrives at the ground below.
func _check_brink(c: Creature2) -> void:
	_calm(c)
	var top: float = 60.0
	var mesa: Vector2 = c.centre()
	main.terrain.add(mesa, 150.0, top)
	c.reset()
	_tick(c, 20)
	_check(c.armature.hind_carry > top,
		"the body never stood up on the mesa (hind carry %.1f)" % c.armature.hind_carry)
	c.command.throttle = 1.0
	_tick(c, 300)
	var stopped_short: float = 150.0 - c.centre().distance_to(mesa)
	_check(not c.armature.collapsed, "the brink felled the body without a push")
	_check(c.speed < 15.0,
		"the body ran at a %.0f px brink at %.1f px/s" % [top, c.speed])
	_check(stopped_short > 0.0, "the walk carried the body off the mesa")
	c.command.throttle = 0.0
	c.shove(c.move_dir * 450.0)
	var fell: bool = false
	for i in 400:
		c._physics_process(TICK)
		fell = fell or c.armature.collapsed
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())
	_check(fell, "shoved past the brink, the body never fell")
	# Arrived on the plane below, not still up on the mesa. Not "flat at zero"
	# any more: a body pushed off an edge goes over the edge, and one lying on
	# its flank rests its spine a body-radius off the floor. The claim is the
	# height it came down to; the pose it came down in is TippingProbe's.
	var z: float = a.pos[a.pelvis_index()].z
	_check(z < top * 0.33,
		"went over the brink but never arrived below (pelvis z %.1f)" % z)
	notes.append("balks %.0f px short of a 60 px brink; shoved over, it falls and arrives below at z %.1f, heeled %.0f°"
		% [stopped_short, z, rad_to_deg(absf(c.travel.keel.roll))])
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


## The arc ends on the surface the body is actually over: a running leap that
## crosses onto a low table comes down on the table — the fall's floor is the
## ground under the body, not the height it took off from — and the body is
## carried on it afterwards.
func _check_vault(c: Creature2) -> void:
	_calm(c)
	c.command.throttle = 1.0
	_tick(c, 60)
	c.command.jump = true
	_tick(c, 22)
	# The table is laid down where *this* animal's leap is about to cross, not at
	# a distance in pixels: the claim is about the surface under the arc, and a
	# table pinned to one body's cruise is scaffolding that goes red when the
	# body's pace is retuned. Its near edge is just ahead of the take-off, so the
	# leap genuinely crosses onto it from the plane.
	var table: Vector2 = c.centre() + c.move_dir * 140.0
	main.terrain.add(table, 120.0, 12.0)
	c.command.jump = false
	var flew: int = 0
	var landed_on: float = -1.0
	for i in 240:
		c._physics_process(TICK)
		if c.armature.fall.is_airborne():
			flew += 1
		elif flew > 3:
			landed_on = main.terrain.surface(c.centre(), 1.5, INF).x
			break
	var a: Armature = c.armature
	worst_stick = maxf(worst_stick, a.worst_stick_error())
	worst_bend = maxf(worst_bend, a.worst_bend_excess())
	worst_bone = maxf(worst_bone, a.worst_bone_error())
	_check(flew > 6, "the running vault never left the ground")
	_check(landed_on > 10.0,
		"the leap came down on the plane (%.0f px), not the table it was over" % landed_on)
	_tick(c, 30)
	_check(not a.collapsed, "the vault landing felled the body")
	_check(a.fore_carry > 12.0 and a.hind_carry > 12.0,
		"the body did not end up carried on the table (carries %.1f / %.1f)"
		% [a.fore_carry, a.hind_carry])
	notes.append("a running leap comes down on the table it crossed onto (%.0f px up) and stays there"
		% landed_on)
	main.terrain.clear()


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
