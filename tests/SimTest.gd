## Headless invariant check for the creature simulation.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/SimTest.gd
##
## Drives a real Creature through idle -> walk -> turn -> pivot -> idle and
## asserts the things the solver is supposed to guarantee: segment lengths hold,
## bends stay inside the limit, IK bones keep their length, the gait never lifts
## both diagonals at once, and a resting creature keeps its feet still.
## Worth re-running after retuning stiffness / iterations / max bend.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []


func _initialize() -> void:
	_check_schema()
	for preset_name in CreatureParams.PRESETS:
		_run_case(str(preset_name))

	print("")
	if failures.is_empty():
		print("PASS — all invariants held")
	else:
		print("FAIL — %d problem(s):" % failures.size())
		for f in failures:
			print("  - ", f)
	quit(0 if failures.is_empty() else 1)


## The tuning panel drives everything through Object.set()/get() with float
## slider values, including properties typed as int. If that conversion ever
## stopped working the sliders would fail silently, so it is checked here.
func _check_schema() -> void:
	var params := CreatureParams.new()
	for row in CreatureParams.SCHEMA:
		if not row.has("prop"):
			continue
		var prop: String = row["prop"]
		if params.get(prop) == null:
			failures.append("SCHEMA lists '%s', which CreatureParams does not have" % prop)
			continue
		if row.get("bool", false):
			continue
		# Write a value off the slider's midpoint and read it straight back.
		var probe: float = snappedf((float(row["min"]) + float(row["max"])) * 0.5, float(row["step"]))
		params.set(prop, probe)
		var readback: float = float(params.get(prop))
		if absf(readback - probe) > maxf(float(row["step"]), 0.001):
			failures.append("'%s' did not round-trip: set %.3f, read %.3f" % [prop, probe, readback])
	print("schema: %d rows checked" % CreatureParams.SCHEMA.size())


func _run_case(preset_name: String) -> void:
	var params := CreatureParams.new()
	params.apply_preset(preset_name)

	var creature := Creature.new()
	creature.params = params
	root.add_child(creature)

	var cmd := MovementInput.Command.new()
	creature.command = cmd

	var max_seg_error: float = 0.0
	var worst_seg_tick: int = -1
	var worst_seg_index: int = -1
	var max_bend_excess: float = 0.0
	var max_bone_error: float = 0.0
	var max_airborne: int = 0
	var both_groups_airborne: bool = false
	var steps_taken: int = 0
	var nan_seen: bool = false
	var was_stepping := {}
	var distance_travelled: float = 0.0
	var previous_head: Vector2 = creature.head_pos

	var idle_marks: Dictionary = {}
	var idle_drift: float = 0.0

	# limb grounding: how far outside its socket the limb stays, how far it
	# reaches, and how far behind its ideal the gait ever lets a foot fall.
	var worst_inboard: float = 99.0
	var max_limb_reach: float = 0.0
	var max_foot_drift: float = 0.0
	# undulation: peak sway while walking dead straight from the origin, so the
	# undisturbed path is y = 0 and |y| is the sway directly.
	var max_sway: float = 0.0

	for tick in range(900):
		# scripted route: settle, walk, walk+turn, pivot on the spot, settle
		if tick < 60:
			cmd.throttle = 0.0; cmd.turn = 0.0
		elif tick < 300:
			cmd.throttle = 1.0; cmd.turn = 0.0
		elif tick < 420:
			cmd.throttle = 1.0; cmd.turn = 1.0
		elif tick < 500:
			cmd.throttle = 0.0; cmd.turn = -1.0
		else:
			cmd.throttle = 0.0; cmd.turn = 0.0

		creature._physics_process(TICK)
		distance_travelled += previous_head.distance_to(creature.head_pos)
		previous_head = creature.head_pos

		var spine: Spine = creature.spine
		var seg_len: float = params.segment_length * creature.size_scale
		var max_bend: float = deg_to_rad(params.max_bend_deg)

		for i in spine.size():
			if is_nan(spine.points[i].x) or is_nan(spine.points[i].y):
				nan_seen = true

		# 1. distance constraint
		for i in range(1, spine.size()):
			var d: float = spine.points[i - 1].distance_to(spine.points[i])
			var err: float = absf(d - seg_len) / seg_len
			if err > max_seg_error:
				max_seg_error = err
				worst_seg_tick = tick
				worst_seg_index = i

		# 2. angle constraint
		for i in range(1, spine.size() - 1):
			var a: float = (spine.points[i] - spine.points[i - 1]).angle()
			var b: float = (spine.points[i + 1] - spine.points[i]).angle()
			max_bend_excess = maxf(max_bend_excess, absf(wrapf(b - a, -PI, PI)) - max_bend)

		# 3. IK bone lengths + gait bookkeeping
		var airborne: int = 0
		var groups_up := [false, false]
		for limb in creature.gait.limbs:
			for j in range(limb.lengths.size()):
				var actual: float = limb.joints[j].distance_to(limb.joints[j + 1])
				max_bone_error = maxf(max_bone_error, absf(actual - limb.lengths[j]) / limb.lengths[j])
			if is_nan(limb.joints[2].x):
				nan_seen = true
			if limb.stepping:
				airborne += 1
				groups_up[limb.group] = true
			if limb.stepping and not was_stepping.get(limb.key, false):
				steps_taken += 1
			was_stepping[limb.key] = limb.stepping

			# 4. limb grounding. Feet are placed in world space and the body
			# then walks out from under them, so what goes wrong is geometric:
			# a leg left far enough behind straightens out and ends up drawn
			# across the torso. Measured against the socket's own outward axis,
			# so it means the same thing at any body heading.
			var anchor: Spine.Frame = creature.body.anchors[limb.key]
			var outward: Vector2 = anchor.perp * limb.side
			for j2 in [1, 2]:
				worst_inboard = minf(worst_inboard,
					(limb.joints[j2] - anchor.pos).dot(outward) / limb.total_length)
			max_limb_reach = maxf(max_limb_reach,
				anchor.pos.distance_to(limb.joints[2]) / limb.total_length)
			max_foot_drift = maxf(max_foot_drift, limb.error / maxf(limb.stride, 0.001))
		max_airborne = maxi(max_airborne, airborne)
		if groups_up[0] and groups_up[1]:
			both_groups_airborne = true

		# 5. undulation amplitude, sampled only on the straight-line leg of the
		# route and once the wave has established. The wave is meant to be a
		# kinematic offset, so sway must stay near `body_wave`; runaway here
		# means it is feeding the Verlet integrator again and the chain is
		# resonating, which swings the limb sockets far faster than the creature
		# is actually travelling and leaves the hind feet unable to plant.
		if tick >= 180 and tick < 300:
			for i in spine.size():
				max_sway = maxf(max_sway, absf(spine.points[i].y))

		# 5. idle stability: feet must not creep once the creature has settled.
		# Sampling starts well after input stops so a step already in flight is
		# allowed to finish — the invariant is "no perpetual creep", not
		# "instantly frozen".
		if tick == 780:
			for limb in creature.gait.limbs:
				idle_marks[limb.key] = limb.planted
		elif tick > 780:
			for limb in creature.gait.limbs:
				idle_drift = maxf(idle_drift, limb.planted.distance_to(idle_marks[limb.key]))

	var label: String = "[%s]" % preset_name
	print("%-14s seg_err=%.4f (t=%d i=%d)  bend_excess=%.5f  bone_err=%.5f  steps=%d  max_air=%d  idle_drift=%.3f  travelled=%.0f px"
		% [label, max_seg_error, worst_seg_tick, worst_seg_index, max_bend_excess, max_bone_error,
			steps_taken, max_airborne, idle_drift, distance_travelled])
	print("%-14s limb: inboard=%+.3f  reach=%.3f/%.2f  drift=%.2f x stride   sway=%.1f px (%.1f x body_wave)"
		% ["", worst_inboard, max_limb_reach, params.limb_max_reach, max_foot_drift,
			max_sway, max_sway / maxf(params.body_wave, 0.001)])

	if nan_seen:
		failures.append("%s produced NaN positions" % label)
	if max_seg_error > 0.05:
		failures.append("%s segment length drifted %.1f%% (>5%%)" % [label, max_seg_error * 100.0])
	if max_bend_excess > 0.001:
		failures.append("%s exceeded the bend limit by %.4f rad" % [label, max_bend_excess])
	if max_bone_error > 0.02:
		failures.append("%s IK bone length drifted %.1f%% (>2%%)" % [label, max_bone_error * 100.0])
	if steps_taken < 8:
		failures.append("%s barely stepped (%d steps in 11s of walking)" % [label, steps_taken])
	if both_groups_airborne:
		failures.append("%s lifted both diagonals at once (creature would fall)" % label)
	if idle_drift > 0.01:
		failures.append("%s feet crept %.3f px while idle" % [label, idle_drift])
	# A negative outward offset means a knee or a foot ended up on the far side
	# of its own socket, i.e. the limb was drawn through the torso.
	if worst_inboard < 0.0:
		failures.append("%s drew a limb %.3f of its length inside the body" % [label, -worst_inboard])
	# Past the reach limit the chain is pulled straight and stops reading as a
	# leg; 1% of slack covers the solver's tolerance.
	if max_limb_reach > params.limb_max_reach + 0.01:
		failures.append("%s stretched a limb to %.3f of its length (limit %.2f)"
			% [label, max_limb_reach, params.limb_max_reach])
	# Feet may fall behind — the diagonal gate makes them queue — but a foot
	# several strides adrift is being towed, not walked.
	if max_foot_drift > 3.5:
		failures.append("%s dragged a foot %.1f strides behind its ideal" % [label, max_foot_drift])
	# Resonance ran to 7-19x before the wave was made a true kinematic offset;
	# accumulation down the chain accounts for a little under 3x.
	if max_sway > params.body_wave * 5.0:
		failures.append("%s swayed %.1f px on a straight line (body_wave is %.1f) — spine is resonating"
			% [label, max_sway, params.body_wave])

	creature.queue_free()
	root.remove_child(creature)
