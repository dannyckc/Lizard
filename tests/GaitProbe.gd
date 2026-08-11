## Phase-3 gate for the v2 locomotion — see docs/V2_DESIGN.md §11.2.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/GaitProbe.gd
##
## Asserts what the ported gait claims to be, with the claims taken from
## LocomotionTest / FootfallTest / MovementFeelTest / TraversalTest / StanceTest
## rather than their constants:
##
##   * **the legs deliver the height** — both girdles stand at what the stance
##     geometry says they can, measured off the four feet, and standing costs the
##     body no drift;
##   * **a planted foot is nailed to the world** — no creep at any pace, which is
##     the one thing a dragged foot cannot fake;
##   * **speed is what the legs deliver** — the body never outruns `leg_speed`, and
##     the ground it covers in one cycle is the excursion its feet actually have;
##   * **the pattern falls out of the speed** — a slow walk is a four-beat lateral
##     sequence with one foot up, a cruise is a trot, a sprint is asymmetric, and
##     the duty factor falls the whole way;
##   * **Froude quotes the stance height** — a crouched body reads the same regime
##     as an upright one at the same speed, so a stalk cannot trot;
##   * **rotary is a spine threshold** — the same body either side of
##     Cadence.ROTARY_SPINE gallops transverse or rotary and nothing else changes;
##   * **it is stable on broken ground** — walking a run of ledges keeps every
##     anatomical invariant, climbs at the animal's own rate and never stalls;
##   * **one stride between four legs** — the shortest-striding limb sets it;
##   * **a limp is not a mode** — a haunch chewed off the census shortens that leg's
##     stride and slows its swing, with nothing having decided to limp;
##   * **one integrator** — a leap leaves the ground on Gravity.Fall, arrives near
##     the apex it was priced at, and lands back on its feet.
extends SceneTree

const TICK: float = 1.0 / 60.0

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

	_check_stands(creature)
	_check_feet_stay_put(creature)
	_check_speed_is_delivery(creature)
	_check_pattern_follows_speed(creature)
	_check_froude_quotes_the_stance(creature)
	_check_rotary_is_a_threshold(creature)
	_check_one_stride(creature)
	_check_limp_is_the_census(creature)
	_check_leap(creature)
	_check_terrain(creature)
	_finish()
	return false


# --------------------------------------------------------- the legs hold it up ----

func _check_stands(c: Creature2) -> void:
	_walk(c, 0.0, false, 120)
	var t: Tread = c.tread
	_check(t.measured, "the gait never measured the feet it is standing on")
	# What the stance says these legs deliver, asked of the carriage directly: the
	# body may stand where its own geometry puts it and nowhere else.
	var wants_fore: float = c.attitude.active.stance_clearance(
		c.body.limb_length(true), c.attitude.active.fore.stand,
		c.body.stance_width, c.locomotor.foot_bias.x)
	var wants_hind: float = c.attitude.active.stance_clearance(
		c.body.limb_length(false), c.attitude.active.hind.stand,
		c.body.stance_width, c.locomotor.foot_bias.y)
	_check(absf(t.shoulder_height - wants_fore) < 0.6,
		"the shoulders stand at %.2f px against the %.2f the fore legs deliver"
		% [t.shoulder_height, wants_fore])
	_check(absf(t.hip_height - wants_hind) < 0.6,
		"the hips stand at %.2f px against the %.2f the hind legs deliver"
		% [t.hip_height, wants_hind])
	# The armature is standing where the gait put it, not where the spec guessed.
	var a: Armature = c.armature
	_check(absf(a.pos[a.withers_index()].z - t.shoulder_height) < 0.2,
		"the withers ride %.2f px off the height the fore feet measured"
		% absf(a.pos[a.withers_index()].z - t.shoulder_height))
	_check(absf(a.pos[a.pelvis_index()].z - t.hip_height) < 0.2,
		"the pelvis rides %.2f px off the height the hind feet measured"
		% absf(a.pos[a.pelvis_index()].z - t.hip_height))
	# Every foot on the floor, and no foot outside the leg that carries it.
	for foot in t.feet:
		_check(not foot.stepping, "%s is stepping on an animal standing still" % foot.key)
		_check(absf(foot.foot_height) < 1.0,
			"%s stands with its foot %.2f px off the ground" % [foot.key, foot.foot_height])
		_check(foot.planted.distance_to(foot.socket) <= foot.bone * foot.lock + 0.1,
			"%s stands with its foot outside its own reach" % foot.key)
	var pose: PackedVector3Array = c.armature.pos.duplicate()
	_walk(c, 0.0, false, 300)
	var drift: float = 0.0
	for i in c.armature.pos.size():
		drift = maxf(drift, Vector2(pose[i].x, pose[i].y)
			.distance_to(Vector2(c.armature.pos[i].x, c.armature.pos[i].y)))
	_check(drift < 0.2,
		"a body standing on a solved gait drifted %.3f px in five seconds" % drift)
	notes.append("stands at shoulder %.1f / hip %.1f px on four planted feet"
		% [t.shoulder_height, t.hip_height])


# ------------------------------------------------------------- feet stay where put ----

func _check_feet_stay_put(c: Creature2) -> void:
	var worst: float = 0.0
	var pace: String = ""
	# Settled into each pace before the measurement, and that is the claim rather
	# than a convenience: a body still *accelerating* is outrunning feet it put down
	# for a slower animal, and those feet are dragged to the edge of what the leg can
	# reach — deliberately, because the alternative is dislocating it. What may never
	# happen is a foot creeping under a body travelling steadily.
	for run: Array in [[0.3, false], [1.0, false], [1.0, true]]:
		_walk(c, run[0], run[1], 600)
		var was: Dictionary = {}
		var lifted: Dictionary = {}
		for foot in c.tread.feet:
			was[foot.key] = foot.planted
			lifted[foot.key] = foot.stepping
		var skid: float = 0.0
		for _i in 240:
			c._physics_process(TICK)
			for foot in c.tread.feet:
				if not foot.stepping and not lifted[foot.key]:
					skid = maxf(skid, was[foot.key].distance_to(foot.planted))
				was[foot.key] = foot.planted
				lifted[foot.key] = foot.stepping
		if skid > worst:
			worst = skid
			pace = "%.1f throttle%s" % [run[0], " sprinting" if run[1] else ""]
	_check(worst < 0.05,
		"a planted foot crept %.3f px in one tick at a settled %s" % [worst, pace])
	notes.append("planted feet creep %.4f px a tick at every settled pace" % worst)


# ------------------------------------------------------- speed is what legs give ----

func _check_speed_is_delivery(c: Creature2) -> void:
	# Flat out, with everything asked for. The body may not exceed what its legs
	# will carry it at — that ceiling is the whole of "requests versus delivery".
	_walk(c, 1.0, true, 900)
	var t: Tread = c.tread
	_check(t.leg_speed > 0.0, "the gait never priced what the legs can deliver")
	_check(absf(c.speed) <= t.leg_speed + 1.0,
		"the body travels %.1f px/s on legs that deliver %.1f" % [c.speed, t.leg_speed])
	_check(absf(c.speed) > t.leg_speed * 0.9,
		"the body is only doing %.1f of the %.1f px/s its legs offer"
		% [c.speed, t.leg_speed])

	# ...and the ground covered over one measured cycle is the excursion the feet
	# actually have. Stride over cycle, measured rather than asserted.
	var cycle: float = t.cycle_length()
	var start: Vector2 = c.armature.centre()
	var ticks: int = maxi(int(cycle / TICK), 1)
	for _i in ticks:
		c._physics_process(TICK)
	var covered: float = start.distance_to(c.armature.centre())
	# The *shortest* limb's whole excursion, because that is what priced the ceiling:
	# a body travels at the pace of the leg with least to give.
	var excursion: float = INF
	for foot in t.feet:
		excursion = minf(excursion, foot.sweep_limit * 2.0)
	_check(absf(covered - excursion) < excursion * 0.35,
		"one cycle carried the body %.1f px on feet with %.1f px of travel"
		% [covered, excursion])
	notes.append("flat out at %.0f px/s — %.1f px a cycle on %.1f px of foot travel"
		% [absf(c.speed), covered, excursion])


# ------------------------------------------------------- the pattern is the speed ----

func _check_pattern_follows_speed(c: Creature2) -> void:
	_walk(c, 0.2, false, 480)
	var slow: String = c.tread.cadence.describe()
	var slow_lift: int = c.tread.cadence.lift_limit
	var slow_duty: float = c.tread.duty_measured()
	var slow_down: float = _feet_down(c, 120)
	_check(slow == "lateral-sequence walk",
		"a slow walk came out as a %s" % slow)
	_check(slow_lift == Cadence.LIFT_CAREFUL,
		"a slow walk lifts %d feet at once" % slow_lift)
	_check(slow_down > 2.8,
		"a slow walk keeps only %.2f feet on the ground" % slow_down)

	_walk(c, 1.0, false, 480)
	var cruise: String = c.tread.cadence.describe()
	var cruise_duty: float = c.tread.duty_measured()
	var cruise_down: float = _feet_down(c, 120)
	_check(cruise == "trot", "a cruise came out as a %s" % cruise)

	_walk(c, 1.0, true, 900)
	var sprint: String = c.tread.cadence.describe()
	var sprint_duty: float = c.tread.duty_measured()
	var sprint_down: float = _feet_down(c, 120)
	_check(c.tread.cadence.aerial > 0.0,
		"a sprint never left the symmetrical regime (aerial %.3f)"
		% c.tread.cadence.aerial)
	_check(sprint.ends_with("gallop") or sprint == "bound",
		"a sprint came out as a %s" % sprint)
	_check(slow_duty > cruise_duty and cruise_duty > sprint_duty,
		"the duty factor did not fall with pace (%.2f / %.2f / %.2f)"
		% [slow_duty, cruise_duty, sprint_duty])
	_check(slow_down > cruise_down and cruise_down > sprint_down,
		"the animal did not keep fewer feet down as it went faster (%.2f / %.2f / %.2f)"
		% [slow_down, cruise_down, sprint_down])
	notes.append("walk → %s (%.2f feet down) · cruise → %s (%.2f) · sprint → %s (%.2f)"
		% [slow, slow_down, cruise, cruise_down, sprint, sprint_down])


# ----------------------------------------------- Froude quotes the stance height ----

func _check_froude_quotes_the_stance(c: Creature2) -> void:
	# The pendulum an animal vaults over is its leg. A body crouched onto folded
	# joints has not grown a shorter one, so the regime it reads has to be quoted
	# against the height it *stands* at — otherwise a stalking creature reads as
	# sprinting for its size and trots through its own stalk, which is the v1 bug
	# this claim is ported from.
	_walk(c, 0.6, false, 600)
	var standing: float = c.tread.hip_height
	# Crouch it through the one channel a crouch has: a jump held and never
	# released folds both girdles by the share each is about to push with.
	c.command.throttle = 0.6
	c.command.jump = true
	for _i in 300:
		c._physics_process(TICK)
	var crouched: float = c.tread.hip_height
	var speed: float = 0.0
	for foot in c.tread.feet:
		speed = maxf(speed, foot.socket_speed)
	var stance_hip: float = c.attitude.active.stance_clearance(
		c.body.limb_length(false), c.attitude.active.hind.stand,
		c.body.stance_width, c.locomotor.foot_bias.y)
	var off_stance: float = speed * speed / (Gravity.PULL * stance_hip)
	var off_crouch: float = speed * speed / (Gravity.PULL * maxf(crouched, 1.0))
	c.command.jump = false
	_check(crouched < standing - 1.0,
		"holding a jump did not crouch the body (%.2f → %.2f px)"
		% [standing, crouched])
	_check(absf(c.tread.cadence.froude - off_stance) < off_stance * 0.05,
		"the regime reads %.4f against the %.4f the stance height gives"
		% [c.tread.cadence.froude, off_stance])
	_check(absf(c.tread.cadence.froude - off_crouch) > off_stance * 0.05,
		"the regime is being quoted against the crouch (%.4f) rather than the stance"
		% off_crouch)
	notes.append("crouched %.1f px, the regime still reads %.4f off the %.1f px stance (the crouch would say %.4f)"
		% [standing - crouched, c.tread.cadence.froude, stance_hip, off_crouch])


# ------------------------------------------------------ rotary is a spine threshold ----

func _check_rotary_is_a_threshold(c: Creature2) -> void:
	var built: float = c.body.spine_freedom
	_check(built < Cadence.ROTARY_SPINE,
		"the reference cat's back (%.2f) is not under the rotary threshold" % built)
	_walk(c, 1.0, true, 900)
	_check(c.tread.cadence.describe() == "transverse gallop",
		"the built back gallops %s at a sprint rather than transverse"
		% c.tread.cadence.describe())

	# ...and the same pattern asked deeper into the asymmetric regime than this cat
	# can take itself, which is where a lead change lives. Cadence is a derivation,
	# so it can be asked about a body going faster than this one manages without
	# pretending the animal got there.
	var hip: float = c.tread.hip_height
	# Far enough into the asymmetric regime for a lead to exist and short of the
	# far end of it, where both girdles pair up and the gait is a bound rather than
	# a gallop of either kind.
	var regime: float = 0.78
	var flying: float = sqrt((Cadence.FROUDE_WALK
		+ regime * (Cadence.FROUDE_RUN - Cadence.FROUDE_WALK)) * Gravity.PULL * hip)
	var reach := Vector2(20.0, 20.0)
	var stiff := Cadence.new()
	var freer := Cadence.new()
	c.locomotor.spine_freedom = built
	stiff.update(c.attitude.active, c.locomotor, c.body, hip, flying, reach,
		60.0, 0.0, true, c.bound.launch, 0.0)
	c.locomotor.spine_freedom = Cadence.ROTARY_SPINE + 0.05
	freer.update(c.attitude.active, c.locomotor, c.body, hip, flying, reach,
		60.0, 0.0, true, c.bound.launch, 0.0)
	c.locomotor.spine_freedom = built
	_check(stiff.aerial > Cadence.ROTARY_AT,
		"the test speed does not reach the asymmetric regime (aerial %.2f)"
		% stiff.aerial)
	_check(stiff.describe() == "transverse gallop",
		"a %.2f back gallops %s" % [built, stiff.describe()])
	_check(freer.describe() == "rotary gallop",
		"a %.2f back gallops %s" % [Cadence.ROTARY_SPINE + 0.05, freer.describe()])
	_check((freer.fore_split - 0.5) * (freer.hind_split - 0.5) < 0.0,
		"the rotary gallop did not reverse the fore pair's order")
	notes.append("at %.0f px/s a %.2f back gallops transverse and a %.2f back rotary"
		% [flying, built, Cadence.ROTARY_SPINE + 0.05])


# -------------------------------------------------------- one animal, one stride ----

func _check_one_stride(c: Creature2) -> void:
	_walk(c, 1.0, false, 600)
	var t: Tread = c.tread
	var shortest: float = INF
	for foot in t.feet:
		shortest = minf(shortest, loco_stride(t, foot))
	_check(absf(t.stride_shared - shortest) < 0.01,
		"the shared stride is %.2f px against the shortest limb's %.2f"
		% [t.stride_shared, shortest])
	# Every foot walks off the one stride, scaled only by its own pace and drive.
	for foot in t.feet:
		var mine: float = t.stride_shared * (0.45 + 0.55 * foot.pace) \
			* lerpf(Tread.STRIDE_FLOOR, 1.0, foot.drive)
		_check(absf(foot.stride - mine) < 0.01,
			"%s walks off a stride of its own (%.2f against %.2f)"
			% [foot.key, foot.stride, mine])
	# And the four cycles agree, which is what having one stride is for: a girdle
	# stepping more often than the other has no fixed cycle for a phase to be of.
	var fore: float = 0.0
	var hind: float = 0.0
	for foot in t.feet:
		if foot.cycle <= 0.0:
			continue
		if foot.fore:
			fore = maxf(fore, foot.cycle)
		else:
			hind = maxf(hind, foot.cycle)
	if fore > 0.0 and hind > 0.0:
		_check(absf(fore - hind) < maxf(fore, hind) * 0.35,
			"the fore girdle turns over in %.3f s and the hind in %.3f" % [fore, hind])
	notes.append("one stride of %.1f px, cycles fore %.3f / hind %.3f s"
		% [t.stride_shared, fore, hind])


## The stride this limb would take if nothing else on the animal had a say — the
## capacity `_share_stride` then takes the least of.
func loco_stride(t: Tread, foot: Tread.Foot) -> float:
	return t.loco.stride(foot.sweep_limit, t.spec.foot_lead)


# ------------------------------------------------------------ a limp is anatomy ----

func _check_limp_is_the_census(c: Creature2) -> void:
	_walk(c, 1.0, false, 600)
	var sound_stride: float = c.tread.of(&"HL").stride
	var sound_swing: float = c.tread.of(&"HL").step_duration
	_check(absf(c.tread.of(&"HL").drive - 1.0) < 0.0001,
		"an intact haunch reads %.4f rather than exactly one" % c.tread.of(&"HL").drive)
	# Chew the left thigh — the census, and nothing else, is told about it.
	var census: Corpus.CensusChain = c.corpus.chain(&"HL")
	for st in 2:
		for sec in census.sectors:
			c.corpus.gouge(&"HL", st, sec, 1.6)
	_walk(c, 1.0, false, 600)
	var hurt: Tread.Foot = c.tread.of(&"HL")
	var other: Tread.Foot = c.tread.of(&"HR")
	_check(hurt.drive < 0.92 and hurt.drive > Tread.CONTROL_MIN,
		"a chewed thigh reads %.2f of its muscle — not a limp either way" % hurt.drive)
	_check(hurt.stride < sound_stride * 0.98,
		"the chewed leg strides %.2f px against the %.2f it had sound"
		% [hurt.stride, sound_stride])
	_check(hurt.step_duration > sound_swing * 1.02,
		"the chewed leg swings in %.0f ms against the %.0f it had sound"
		% [hurt.step_duration * 1000.0, sound_swing * 1000.0])
	_check(hurt.stride < other.stride,
		"the chewed leg (%.2f px) strides as far as its partner (%.2f)"
		% [hurt.stride, other.stride])
	var limping: String = "%.2f muscle, %.1f px stride against %.1f, %.0f ms swing against %.0f" \
		% [hurt.drive, hurt.stride, sound_stride, hurt.step_duration * 1000.0,
			sound_swing * 1000.0]

	# ...and past the point where the limb answers at all it stops being asked. It
	# still exists, is still solved and is still dragged along its own envelope —
	# which is what dragging a dead leg looks like, and it is the same lines of code.
	for st in 4:
		for sec in census.sectors:
			c.corpus.gouge(&"HL", st, sec, 40.0)
	_walk(c, 1.0, false, 480)
	var dead: Tread.Foot = c.tread.of(&"HL")
	_check(dead.drive < Tread.CONTROL_MIN,
		"a haunch chewed hollow still answers with %.2f" % dead.drive)
	var stepped: bool = false
	for _i in 300:
		c._physics_process(TICK)
		stepped = stepped or dead.stepping
	_check(not stepped, "a limb with no muscle left still picks itself up")
	_check(dead.error > 0.0,
		"the dragged limb is not being outrun by the body it is attached to")
	notes.append("a chewed thigh: " + limping + "; chewed hollow it stops stepping")
	# Put the animal back: every later check is about a sound body.
	c.corpus.build(c.body)
	c.reset()


# ------------------------------------------------------------------- the leap ----

func _check_leap(c: Creature2) -> void:
	_walk(c, 0.0, false, 120)
	_check(c.bound.capable, "the cat cannot jump higher than it lifts a foot")
	var priced: float = c.bound.full
	c.command.jump = true
	var peak: float = 0.0
	for _i in 120:
		c._physics_process(TICK)
		peak = maxf(peak, c.armature.fall.height)
	c.command.jump = false
	var airborne: bool = false
	for _i in 240:
		c._physics_process(TICK)
		peak = maxf(peak, c.armature.fall.height)
		airborne = airborne or c.armature.fall.is_airborne()
	_check(airborne, "a full-charge jump never left the ground")
	_check(absf(peak - priced) < priced * 0.15,
		"the jump reached %.1f px against the %.1f it was priced at" % [peak, priced])
	_walk(c, 0.0, false, 240)
	_check(not c.armature.fall.is_airborne(), "the body never came back down")
	_check(absf(c.tread.hip_height - c.armature.hind_stance) < 2.0,
		"the body landed standing at %.2f px rather than its own %.2f"
		% [c.tread.hip_height, c.armature.hind_stance])
	notes.append("a charged leap clears %.0f px and lands on its feet" % peak)


# ------------------------------------------------------------ broken ground ----

func _check_terrain(c: Creature2) -> void:
	var terrain: Terrain = main.terrain
	terrain.clear()
	# A run of ledges along the walking line, each one a real step up for a cat.
	for i in 6:
		terrain.add(Vector2(120.0 + float(i) * 90.0, 0.0), 34.0,
			6.0 + float(i % 3) * 4.0)
	c.reset()
	_walk(c, 1.0, false, 30)
	var start: Vector2 = c.armature.centre()
	var worst_bone: float = 0.0
	var worst_stick: float = 0.0
	var worst_bend: float = 0.0
	var lowest: float = INF
	var highest: float = -INF
	var stalled: int = 0
	var last: Vector2 = start
	for i in 900:
		c._physics_process(TICK)
		worst_bone = maxf(worst_bone, c.armature.worst_bone_error())
		worst_stick = maxf(worst_stick, c.armature.worst_stick_error())
		worst_bend = maxf(worst_bend, c.armature.worst_bend_excess())
		lowest = minf(lowest, c.tread.hip_height)
		highest = maxf(highest, c.tread.hip_height)
		if i % 60 == 59:
			if last.distance_to(c.armature.centre()) < 20.0:
				stalled += 1
			last = c.armature.centre()
	var travelled: float = start.distance_to(c.armature.centre())
	_check(travelled > 900.0,
		"fifteen seconds of walking over ledges covered %.0f px" % travelled)
	_check(stalled == 0, "the animal stalled on the ledges for %d second(s)" % stalled)
	_check(worst_bone < 0.05,
		"a limb bone stretched %.4f px crossing broken ground" % worst_bone)
	_check(worst_stick < 0.05,
		"an axial stick stretched %.4f px crossing broken ground" % worst_stick)
	_check(worst_bend < 0.001,
		"a joint passed its graded limit by %.5f rad on broken ground" % worst_bend)
	_check(highest - lowest > 4.0,
		"the body never rose onto anything (hips held %.1f..%.1f px)"
		% [lowest, highest])
	# And the verdicts the same body gives about what it just walked over.
	var body: Crossing.Body = Crossing.of(c.tread, c.locomotor, c.attitude.active,
		c.body, c.corpus)
	_check(Crossing.assess(body, 0.0, 4.0, 30.0) == Crossing.OVER,
		"a 4 px kerb is not something this cat walks over")
	_check(Crossing.assess(body, 0.0, 14.0, 34.0) == Crossing.MOUNT,
		"a 14 px ledge is not something this cat steps onto")
	_check(Crossing.assess(body, 0.0, 80.0, 34.0) == Crossing.BLOCKED,
		"an 80 px wall is not stopping this cat")
	_check(Crossing.assess(body, body.stand * 1.4, body.stand * 2.0, 34.0)
		== Crossing.UNDER, "this cat will not walk under an overhang it fits below")
	terrain.clear()
	notes.append("walks %.0f px of ledges, hips %.0f..%.0f px, anatomy exact"
		% [travelled, lowest, highest])


# ------------------------------------------------------------------- helpers ----

## Drives the creature at a throttle until the gait has settled into it.
func _walk(c: Creature2, throttle: float, sprint: bool, ticks: int) -> void:
	c.command.throttle = throttle
	c.command.sprint = sprint
	c.command.jump = false
	for _i in ticks:
		c._physics_process(TICK)


## The mean number of feet on the ground over a window — the duty factor as a
## count, which is the form a person can check by eye.
func _feet_down(c: Creature2, ticks: int) -> float:
	var total: int = 0
	for _i in ticks:
		c._physics_process(TICK)
		for foot in c.tread.feet:
			if not foot.stepping:
				total += 1
	return float(total) / float(maxi(ticks, 1))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("gait OK — the legs carry the body: %s" % " · ".join(notes))
	else:
		print("GAIT FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
