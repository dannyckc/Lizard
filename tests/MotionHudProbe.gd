## Gate for the physics HUD's seam — see docs/V2_DESIGN.md §11.2, Phase 3.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/MotionHudProbe.gd
##
## The HUD's whole claim is that it is a **pure reader**: it draws the body the
## solver posed, the decisions the loop took, and nothing it worked out for
## itself. Every check below is that claim about one part of it — and the last
## two are the other half of the bargain, that watching the loop neither changes
## it nor costs it anything worth measuring.
##
##   * **it invents no geometry** — every foot the panel draws is at `Footwork`'s
##     own anchor, home, lift, landing and socket, to the float.
##   * **the weight it draws is Poise's** — the centre of mass, the margin and
##     the span to 1e-6, and the support polygon's vertices are exactly the
##     planted anchors: no second hull, wrapped round the same feet.
##   * **the foot rows are the footfalls** — walked 300 ticks, every sample of
##     every row matches what `Footwork` was doing on that tick, and every
##     desperate mark is a rule that actually fired.
##   * **delivery never exceeds the ceiling it is drawn against**, and the
##     ceiling falls as feet leave the ground, because it is `Impetus`'s.
##   * **the joints it reddens are the joints that are clamped** — a limb solving
##     at full stretch reads as clamped, and a folded one does not.
##   * **it says what it cannot measure** — the travel tells are blank on a
##     standing animal rather than reading zero, and finite once it walks.
##   * **the ledge is seen before it is reached** — the rise and the carry the
##     panel prints both move before any fore foot is on the step.
##   * **watching changes nothing** — the same run with the panel open and with
##     it shut leaves the body in the same place, to the float.
##   * **...and costs almost nothing** — the per-tick recording is timed and
##     printed. The drawing itself is not measurable headless (nothing renders);
##     `tests/MotionShot.gd` is where the panel is looked at.
extends SceneTree

const TICK: float = 1.0 / 60.0
## What the recording may cost the loop per tick, ms. A tripwire for someone
## putting a walk of the census in the seam, not a benchmark: the measurement
## itself is a difference between two runs of the whole loop and carries ±0.04 ms
## of noise, so the number to trip on is one that cannot be hit by anything but a
## real regression — a quarter of a millisecond is a fair fraction of a tick and
## more than an order of magnitude under a 60 Hz frame.
const BUDGET_MS: float = 0.25

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false


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

	_check_reads_the_feet(creature)
	_check_reads_the_weight(creature)
	_check_rows_are_footfalls(creature)
	_check_ceiling(creature)
	_check_clamped_joints(creature)
	_check_blank_when_unmeasurable(creature)
	_check_ledge(creature)
	_check_free_when_shut(creature)
	_check_cost(creature)
	_check_gives_the_clock_back(creature)

	_finish()
	return false


# ------------------------------------------------------------------ helpers ----

func _tick(c: Creature2, n: int) -> void:
	for _i in n:
		c._physics_process(TICK)


func _calm(c: Creature2, watching: bool = true) -> void:
	main.terrain.clear()
	c.command.throttle = 0.0
	c.command.turn = 0.0
	c.command.sprint = false
	c.command.jump = false
	c.reset()
	c.motion_readout().watch(watching)
	_tick(c, 10)


func _walk(c: Creature2, n: int, throttle: float = 1.0) -> void:
	c.command.throttle = throttle
	_tick(c, n)


# ------------------------------------------------------------------- claims ----

## Every mark the panel puts on a foot is Footwork's own number.
func _check_reads_the_feet(c: Creature2) -> void:
	_calm(c)
	_walk(c, 90)
	var r: MotionReadout = c.motion_readout()
	var fw: Footwork = c.travel.footwork
	var worst: float = 0.0
	var mismatched: int = 0
	for i in fw.feet.size():
		var f: Footwork.Foot = fw.feet[i]
		var s: MotionReadout.Step = r.steps[i]
		worst = maxf(worst, Vector2(s.anchor.x, s.anchor.y).distance_to(f.anchor))
		worst = maxf(worst, absf(s.anchor.z - f.anchor_z))
		worst = maxf(worst, s.home.distance_to(f.home))
		worst = maxf(worst, s.lift.distance_to(f.lift))
		worst = maxf(worst, s.land.distance_to(f.land))
		worst = maxf(worst, s.socket.distance_to(c.armature.socket_of(f.limb)))
		if s.swinging != f.swinging or not is_equal_approx(s.urgency, f.urgency):
			mismatched += 1
	_check(worst == 0.0,
		"a foot the panel draws is %.6f px from where Footwork put it" % worst)
	_check(mismatched == 0,
		"%d feet disagree with Footwork about swinging or urgency" % mismatched)
	notes.append("feet read straight through: %d of %d exact, %.6f px worst"
		% [fw.feet.size(), fw.feet.size(), worst])


## The weight, the margin and the support are Poise's, and the polygon drawn
## round the feet has the planted feet as its vertices — not a second hull.
func _check_reads_the_weight(c: Creature2) -> void:
	_calm(c)
	_walk(c, 120)
	var r: MotionReadout = c.motion_readout()
	var p: Poise = c.poise
	var off: float = r.com.distance_to(p.centre)
	_check(off < 1e-6, "the drawn centre of mass is %.9f px off Poise's" % off)
	_check(absf(r.com_height - p.height) < 1e-6,
		"the drawn weight hangs %.9f px off Poise's height"
		% absf(r.com_height - p.height))
	_check(absf(r.margin - p.clearance) < 1e-6,
		"the drawn margin is %.9f px off Poise's clearance" % absf(r.margin - p.clearance))
	_check(absf(r.span - p.span) < 1e-6, "the drawn span is not Poise's")
	_check(r.feet_down == p.feet, "the panel counts %d feet down, Poise counts %d"
		% [r.feet_down, p.feet])
	# Every vertex of the drawn polygon is a foot that is standing on something —
	# the same posed toe `Poise` measured its own clearance against — and every
	# one of them is where `Footwork` anchored that foot. Two claims because they
	# are two different ways for a panel to lie: wrapping its own hull round the
	# feet, and drawing feet the mover does not think are down.
	var toes: Array[Vector2] = []
	var anchors: Array[Vector2] = []
	for f in c.travel.footwork.feet:
		if f.swinging:
			continue
		var toe: Vector3 = c.armature.pos[f.limb.nodes[f.limb.nodes.size() - 1]]
		toes.append(Vector2(toe.x, toe.y))
		anchors.append(f.anchor)
	var strays: int = 0
	var loosest: float = 0.0
	for v in r.hull:
		var on_a_foot: bool = false
		for toe in toes:
			if v.distance_to(toe) == 0.0:
				on_a_foot = true
		if not on_a_foot:
			strays += 1
		var nearest: float = INF
		for anchor in anchors:
			nearest = minf(nearest, v.distance_to(anchor))
		loosest = maxf(loosest, nearest)
	_check(strays == 0, "%d hull vertices are not standing on a foot" % strays)
	_check(r.hull.size() == toes.size(),
		"the hull has %d vertices for %d planted feet" % [r.hull.size(), toes.size()])
	_check(loosest < 1.0,
		"a hull vertex is %.3f px from the anchor the foot was planted at" % loosest)
	notes.append("weight and support are Poise's: %.9f px off, %d-footed hull, %.3f px off its anchors"
		% [off, r.hull.size(), loosest])


## The timeline is the footfall, tick for tick — and a full-height mark is a rule
## that fired rather than a drawing flourish.
func _check_rows_are_footfalls(c: Creature2) -> void:
	_calm(c)
	c.command.throttle = 1.0
	var r: MotionReadout = c.motion_readout()
	var truth: Array[PackedByteArray] = []
	for _i in c.travel.footwork.feet.size():
		truth.append(PackedByteArray())
	var desperate: int = 0
	for _t in 300:
		c._physics_process(TICK)
		for i in c.travel.footwork.feet.size():
			var f: Footwork.Foot = c.travel.footwork.feet[i]
			var mark: int = MotionReadout.PLANTED
			if f.swinging:
				mark = MotionReadout.RESCUING if f.rescue_at.x < INF \
					else MotionReadout.SWINGING
			elif f.torn or f.urgency >= Rhythm.DESPERATE:
				mark = MotionReadout.DESPERATE
				desperate += 1
			truth[i].append(mark)
	var wrong: int = 0
	var samples: int = r.samples()
	for k in samples:
		for i in truth.size():
			# The ring holds the last `samples` ticks of the 300 just walked.
			var at: int = truth[i].size() - samples + k
			if at < 0:
				continue
			if r.sample_mark(k, i) != truth[i][at]:
				wrong += 1
	_check(wrong == 0, "%d timeline samples disagree with what the feet were doing"
		% wrong)
	_check(samples > 200, "only %d samples were recorded over 300 walked ticks" % samples)
	notes.append("timeline matches the feet over %d ticks (%d desperate marks)"
		% [samples, desperate])


## What was delivered never passes the ceiling the panel draws it against, and
## the ceiling is the feet's — it falls as they leave the ground.
func _check_ceiling(c: Creature2) -> void:
	_calm(c)
	c.command.throttle = 1.0
	var r: MotionReadout = c.motion_readout()
	var over: int = 0
	var full_grip: float = 0.0
	var least_grip: float = INF
	var least_ceiling: float = INF
	var most_ceiling: float = 0.0
	for _t in 240:
		c._physics_process(TICK)
		if r.delivered > r.ceiling + 0.001:
			over += 1
		if r.feet_down == c.travel.footwork.feet.size():
			full_grip = maxf(full_grip, r.grip)
			most_ceiling = maxf(most_ceiling, r.ceiling)
		if r.feet_down <= 2:
			least_grip = minf(least_grip, r.grip)
			least_ceiling = minf(least_ceiling, r.ceiling)
	_check(over == 0, "delivery passed its drawn ceiling on %d ticks" % over)
	_check(least_ceiling < most_ceiling,
		"the ceiling did not fall with feet lifted (%.1f square, %.1f on two)"
		% [most_ceiling, least_ceiling])
	notes.append("delivery stays under the drawn ceiling: %.0f px/s² square, %.0f on two feet"
		% [most_ceiling, least_ceiling])


## A joint reads as clamped when it is out of room and not otherwise: a leg
## stretched straight is at its cap, the same leg folded under the body is not.
func _check_clamped_joints(c: Creature2) -> void:
	_calm(c)
	var a: Armature = c.armature
	var limb: Armature.Chain = a.limbs[0]
	var folded: float = a.joint_slack(limb.nodes[1])
	_check(is_finite(folded), "a limb's own joint answers no limit at all")
	var standing: int = a.joints_at_cap(MotionReadout.AT_CAP)
	# Drag the foot out to the very end of the leg: nothing left to fold.
	var seat: Vector3 = a.socket_of(limb)
	var reach: float = 0.0
	for bone in limb.bones:
		reach += bone
	limb.foot_driven = true
	limb.socket_rise = seat.z
	limb.foot_target = Vector3(seat.x + reach, seat.y, seat.z)
	a.carry(0.0)
	a.settle(TICK, 0.0)
	var stretched: float = a.joint_slack(limb.nodes[1])
	_check(stretched < MotionReadout.AT_CAP,
		"a leg at full stretch still reports %.3f rad of fold left" % stretched)
	_check(a.joints_at_cap(MotionReadout.AT_CAP) > standing,
		"stretching a leg straight did not raise the clamped count")
	notes.append("clamped joints are measured: %.2f rad of fold standing, %.3f at full stretch"
		% [folded, stretched])
	_calm(c)


## Nothing is printed that cannot be measured. A standing animal has no gait for
## a tell to be about, and a panel that answered "0.0 PX" would be inviting the
## reader to fix a body that is doing exactly what it was asked.
func _check_blank_when_unmeasurable(c: Creature2) -> void:
	_calm(c)
	_tick(c, 120)
	var still: Dictionary = c.motion_readout().tells()
	for key in [&"bob", &"sway", &"stride", &"spread"]:
		_check(not is_finite(float(still[key])),
			"a standing animal reported a %s tell of %.2f" % [key, float(still[key])])
	_check(not is_finite(float(still[&"lag"])),
		"an animal going straight reported a spine lag")
	_walk(c, 200)
	var walking: Dictionary = c.motion_readout().tells()
	for key in [&"bob", &"sway", &"stride", &"delivery"]:
		_check(is_finite(float(walking[key])),
			"a walking animal could not measure its %s" % key)
	notes.append("tells stay blank standing and read walking: bob %.2f px · stride %.2f · delivery %.2f"
		% [float(walking[&"bob"]), float(walking[&"stride"]), float(walking[&"delivery"])])


## The anticipation is visible before it is needed: walking at a step, the rise
## the panel prints and the carry it draws both move while every fore foot is
## still on the low ground.
func _check_ledge(c: Creature2) -> void:
	_calm(c)
	main.terrain.clear()
	var at: Vector2 = c.centre() + Vector2.RIGHT * 150.0
	main.terrain.add(at, 90.0, 10.0)
	var r: MotionReadout = c.motion_readout()
	var flat: float = c.armature.fore_carry
	var saw: float = -1.0
	var lifted: float = -1.0
	var stepped: float = -1.0
	c.command.throttle = 1.0
	for _t in 300:
		c._physics_process(TICK)
		if saw < 0.0 and r.fore_rise > 0.5:
			saw = c.centre().x
		if lifted < 0.0 and c.armature.fore_carry > flat + 0.5:
			lifted = c.centre().x
		if stepped < 0.0:
			for step in r.steps:
				if step.fore and not step.swinging and step.anchor.z > 5.0:
					stepped = c.centre().x
	_check(saw > 0.0, "the panel never showed the rise ahead of a 10 px ledge")
	_check(lifted > 0.0 and stepped > 0.0, "the body never climbed the ledge")
	_check(lifted < stepped,
		"the carry rose at x %.1f, after the first fore foot was already on the step at %.1f"
		% [lifted, stepped])
	notes.append("the ledge is seen at x %.0f and the carry rises at %.0f, %.0f px before a fore foot is on it"
		% [saw, lifted, stepped - lifted])
	_calm(c)


## The body does not know it is being watched. Two identical runs, one recorded
## and one not, end in the same place — the recording reads state and writes
## none of it back.
func _check_free_when_shut(c: Creature2) -> void:
	_calm(c, false)
	_walk(c, 240)
	var shut: Vector2 = c.centre()
	var shut_speed: float = c.speed
	_calm(c, true)
	_walk(c, 240)
	var open: Vector2 = c.centre()
	var drift: float = shut.distance_to(open)
	_check(drift == 0.0,
		"watching the loop moved the body %.9f px over 4 s" % drift)
	_check(absf(shut_speed - c.speed) == 0.0,
		"watching the loop changed the speed by %.9f px/s" % absf(shut_speed - c.speed))
	notes.append("the trace is identical watched and unwatched: %.9f px over 240 ticks" % drift)


## What the reading costs the loop. Timed by hand rather than off the frame
## clock, which reports the tick interval instead of the work — see
## tests/PerfProbe.gd for the same reason.
func _check_cost(c: Creature2) -> void:
	_calm(c, false)
	c.command.throttle = 1.0
	_tick(c, 60)
	# Alternated and taken at its best, because the difference being measured is
	# smaller than the noise in any single run of it: a tick of the whole loop is
	# a few hundred microseconds and this is a few of them.
	var runs: int = 400
	var shut: float = INF
	var open: float = INF
	for _round in 3:
		c.motion_readout().watch(false)
		var was: int = Time.get_ticks_usec()
		_tick(c, runs)
		shut = minf(shut, float(Time.get_ticks_usec() - was))
		c.motion_readout().watch(true)
		was = Time.get_ticks_usec()
		_tick(c, runs)
		open = minf(open, float(Time.get_ticks_usec() - was))
	var cost: float = (open - shut) / float(runs) / 1000.0
	_check(cost < BUDGET_MS,
		"recording the loop costs %.3f ms a tick, past the %.2f ms budget"
		% [cost, BUDGET_MS])
	notes.append("recording costs %.3f ms of a %.3f ms tick (%.2f ms budget); the drawing is looked at in MotionShot"
		% [maxf(cost, 0.0), shut / float(runs) / 1000.0, BUDGET_MS])


## The clock is the one thing the panel takes that is not its own, so it has to
## give it back: opening switches the recording on, pausing stops the world,
## stepping advances exactly one tick, and closing the drawer leaves the game
## running at full speed with nothing being recorded.
func _check_gives_the_clock_back(c: Creature2) -> void:
	var hud: LabHUD = main.hud
	_check(hud != null and hud.physics != null, "the lab built no physics drawer")
	if hud == null or hud.physics == null:
		return
	var drawer: MotionDrawer = hud.physics
	# From a body nobody is watching — the claims above switched the recording on
	# by hand, and what is under test here is the drawer doing it.
	_calm(c, false)
	hud.set_view(LabHUD.VIEW_FIELD)
	_check(not c.motion_readout().watching,
		"the loop is being recorded with the panel shut")
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"the world runs at %.2f× with the panel shut" % Engine.time_scale)

	hud.set_view(LabHUD.VIEW_PHYSICS)
	_check(c.motion_readout().watching, "opening the panel did not start the recording")
	drawer.set_rate(0.25)
	_check(is_equal_approx(Engine.time_scale, 0.25),
		"slow motion asked for 0.25× and the world runs at %.2f×" % Engine.time_scale)

	drawer.toggle_pause()
	_check(is_equal_approx(Engine.time_scale, 0.0),
		"pausing left the world running at %.2f×" % Engine.time_scale)
	var before: int = c.motion_readout().samples()
	var at: Vector2 = c.centre()
	drawer.step_once()
	_check(c.motion_readout().samples() == before + 1,
		"one step advanced the loop by %d ticks"
		% (c.motion_readout().samples() - before))
	_check(at.distance_to(c.centre()) < 5.0,
		"one step moved the body %.1f px" % at.distance_to(c.centre()))

	hud.set_view(LabHUD.VIEW_FIELD)
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"closing a paused panel left the world at %.2f×" % Engine.time_scale)
	_check(not c.motion_readout().watching,
		"closing the panel left the loop being recorded")
	notes.append("the clock is borrowed and given back: 0.25× slow, paused, stepped one tick, released")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("motion HUD OK — the panel reads and never invents: %s" % " · ".join(notes))
	else:
		print("MOTION HUD FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
