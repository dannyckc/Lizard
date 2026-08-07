## Procedural locomotion: decides where each foot wants to be, when it should
## pick up, and where it should land. No animation clips, no timelines.
##
## The rule is entirely reactive:
##   * every foot has an ideal position derived from the body's current pose;
##   * a planted foot stays nailed to the world until it drifts further than
##     `stride_distance` from that ideal;
##   * when it does, it arcs to a new spot slightly *ahead* of the ideal and
##     re-plants there.
##
## Because the trigger is distance rather than a timer, step frequency falls out
## of movement speed for free — walk slowly and steps are rare, sprint and they
## come fast — and the creature is naturally still when idle.
##
## Order within update(): retarget -> advance in-flight steps -> decide new
## steps -> solve IK. Steps are advanced before new ones are chosen so the
## "is my diagonal partner busy?" test sees this tick's truth.
class_name Gait
extends RefCounted

var limbs: Array[Limb] = []


func setup() -> void:
	limbs.clear()
	var fl: Limb = Limb.new(); fl.setup("FL", Limb.FRONT, 1.0)
	var fr: Limb = Limb.new(); fr.setup("FR", Limb.FRONT, -1.0)
	var rl: Limb = Limb.new(); rl.setup("RL", Limb.REAR, 1.0)
	var rr: Limb = Limb.new(); rr.setup("RR", Limb.REAR, -1.0)
	# Order matters: it is the tie-breaker when both diagonal pairs are equally
	# overdue (e.g. moving in a perfectly straight line), and it is what stops
	# all four feet lifting on the same tick.
	limbs = [fl, rr, fr, rl]


func update(delta: float, body: BodyShape, move_dir: Vector2, speed_norm: float,
		p: CreatureParams, scale: float) -> void:
	if body.anchors.is_empty():
		return

	# Stride shortens at low speed so a slow creature shuffles rather than
	# lunging, and lengthens toward a full stride at top speed.
	var stride: float = p.stride_distance * scale * (0.45 + 0.55 * speed_norm)
	var lead: Vector2 = move_dir * (p.foot_lead * stride * speed_norm)

	# --- 1. retarget: recompute each foot's ideal position ------------------
	for limb in limbs:
		var a: Spine.Frame = body.anchors[limb.key]
		limb.set_lengths((p.arm_length if limb.pair == Limb.FRONT else p.leg_length) * scale)

		# Rest stance in the socket's own frame: partly forward/backward,
		# mostly out to the side, normalised so it always sits at the same
		# reach no matter how the biases are tuned.
		var bias: float = p.front_foot_bias if limb.pair == Limb.FRONT else p.rear_foot_bias
		var dir: Vector2 = a.fwd * bias + a.perp * (limb.side * p.stance_width)
		if dir.length_squared() < 0.000001:
			dir = a.perp * limb.side
		dir = dir.normalized()

		limb.joints[0] = a.pos
		limb.ideal = a.pos + dir * (limb.total_length * p.stance_reach) + lead

		if not limb.initialised:
			# First tick: plant the feet where they already want to be so the
			# creature does not start by taking four simultaneous steps.
			limb.planted = limb.ideal
			limb.ground = limb.ideal
			limb.visual = limb.ideal
			limb.joints[1] = a.pos.lerp(limb.ideal, 0.5) + a.fwd * (limb.bend_sign * limb.total_length * 0.25)
			limb.joints[2] = limb.ideal
			limb.initialised = true

		limb.error = limb.planted.distance_to(limb.ideal)

	# --- 2. advance any step already in flight ------------------------------
	for limb in limbs:
		if not limb.stepping:
			limb.ground = limb.planted
			limb.lift = 0.0
			limb.visual = limb.planted
			continue

		# Keep re-aiming the landing spot at the (moving) ideal while airborne,
		# otherwise feet land in stale positions during a turn.
		var retarget: float = 1.0 - exp(-9.0 * delta)
		limb.step_to = limb.step_to.lerp(limb.ideal + move_dir * (stride * 0.45 * speed_norm), retarget)

		limb.step_t += delta / maxf(limb.step_duration, 0.001)
		if limb.step_t >= 1.0:
			limb.step_t = 1.0
			limb.stepping = false
			limb.planted = limb.step_to

		# Smoothstep along the ground path (ease out of and into the plant) with
		# a sine arc for the fake lift — a half period is exactly one hop.
		var eased: float = smoothstep(0.0, 1.0, limb.step_t)
		limb.ground = limb.step_from.lerp(limb.step_to, eased)
		limb.lift = sin(limb.step_t * PI) * p.step_height * scale * (0.45 + 0.55 * speed_norm)
		limb.visual = limb.ground - Vector2(0.0, limb.lift)

	# --- 3. decide which feet pick up ---------------------------------------
	var busy: Array[bool] = [false, false]
	var candidates: Array[Limb] = []
	for limb in limbs:
		if limb.stepping:
			busy[limb.group] = true
			continue
		# Recompute against this tick's plant: step 2 may have just landed this
		# foot, and deciding on the pre-landing error would re-fire it instantly.
		limb.error = limb.planted.distance_to(limb.ideal)
		if limb.error >= stride:
			candidates.append(limb)

	# Most overdue foot first. This is what keeps the gait fair: the diagonal
	# gate below can only ever let one pair through at a time, so with a fixed
	# order the same pair wins every contest and the other pair is dragged along
	# the ground indefinitely. Sorting by how far each foot has drifted means a
	# blocked pair's error keeps climbing until it outbids the pair that has
	# just re-planted, which is exactly the alternation we want.
	candidates.sort_custom(func(a: Limb, b: Limb) -> bool: return a.error > b.error)

	for limb in candidates:
		if limb.stepping:
			continue
		# Never lift a foot while the opposite diagonal is airborne: that is
		# what keeps at least two feet down and the creature standing.
		if busy[1 - limb.group]:
			continue

		_start_step(limb, move_dir, stride, speed_norm, p)
		busy[limb.group] = true

		# Pull the diagonal partner onto the same beat if it is anywhere near
		# due. This is the difference between a readable trot and four legs
		# doing their own thing; coupling 0 disables it entirely.
		for other in limbs:
			if other == limb or other.group != limb.group or other.stepping:
				continue
			if other.error > stride * (1.0 - p.diagonal_coupling):
				_start_step(other, move_dir, stride, speed_norm, p)

	# --- 4. solve the limbs -------------------------------------------------
	for limb in limbs:
		_solve_limb(limb, body, p)


func _start_step(limb: Limb, move_dir: Vector2, stride: float, speed_norm: float, p: CreatureParams) -> void:
	limb.step_from = limb.planted
	# Overshoot the ideal in the direction of travel so the foot lands *ahead*
	# of the body and has room to be dragged back before it is due again.
	limb.step_to = limb.ideal + move_dir * (stride * 0.45 * speed_norm)
	# Faster movement means quicker steps; the floor keeps it from going silly.
	limb.step_duration = maxf(p.step_duration * (1.0 - 0.55 * speed_norm), 0.06)
	limb.step_t = 0.0
	limb.stepping = true


func _solve_limb(limb: Limb, body: BodyShape, p: CreatureParams) -> void:
	var a: Spine.Frame = body.anchors[limb.key]
	var root: Vector2 = a.pos
	# Solve to the *lifted* position, not the ground one, so the leg folds up
	# and clears during a step instead of dragging along the floor.
	var target: Vector2 = limb.visual

	# Seed the middle joint toward a pole before solving. FABRIK keeps whichever
	# side of the root->target axis it starts on, so this is what stops elbows
	# and knees popping between the two mirror solutions. The offset shrinks as
	# the limb straightens, which is roughly where the real joint would sit.
	var span: float = root.distance_to(target)
	var slack: float = maxf(limb.total_length * limb.total_length - span * span, 0.0)
	var pole: Vector2 = root.lerp(target, 0.5) + a.fwd * (limb.bend_sign * sqrt(slack) * 0.5)
	limb.joints[1] = limb.joints[1].lerp(pole, 0.4)

	limb.joints = Fabrik.solve(limb.joints, limb.lengths, root, target, p.fabrik_iterations, 0.05)


## True when the creature has at least one foot in the air.
func any_stepping() -> bool:
	for limb in limbs:
		if limb.stepping:
			return true
	return false
