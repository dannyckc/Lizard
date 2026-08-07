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

	var top_speed: float = maxf(p.move_speed * scale, 1.0)
	var swing: float = deg_to_rad(p.limb_swing_deg)

	# --- 1. retarget: recompute each foot's ideal position ------------------
	for limb in limbs:
		var a: Spine.Frame = body.anchors[limb.key]
		limb.set_lengths((p.arm_length if limb.pair == Limb.FRONT else p.leg_length) * scale)

		# How fast is *this* socket travelling? Every timing below is sized off
		# that rather than off the body's linear speed, so a limb on the outside
		# of a turn takes long quick strides while one near the turn centre
		# barely shuffles — and a creature pivoting on the spot, whose linear
		# speed is zero, still walks its hind feet around.
		limb.track_socket(a.pos, delta, move_dir)
		limb.pace = maxf(speed_norm, clampf(limb.socket_speed / top_speed, 0.0, 1.0))

		# Stride shortens at low pace so a slow limb shuffles rather than
		# lunging, and lengthens toward a full stride at top pace.
		limb.stride = p.stride_distance * scale * (0.45 + 0.55 * limb.pace)

		# Rest stance in the socket's own frame: partly forward/backward,
		# mostly out to the side, normalised so it always sits at the same
		# reach no matter how the biases are tuned.
		var bias: float = p.front_foot_bias if limb.pair == Limb.FRONT else p.rear_foot_bias
		var dir: Vector2 = a.fwd * bias + a.perp * (limb.side * p.stance_width)
		if dir.length_squared() < 0.000001:
			dir = a.perp * limb.side
		limb.rest_dir = dir.normalized()

		limb.joints[0] = a.pos
		limb.ideal = a.pos + limb.rest_dir * (limb.total_length * p.stance_reach) \
			+ limb.travel * (p.foot_lead * limb.stride * limb.pace)

		if not limb.initialised:
			# First tick: plant the feet where they already want to be so the
			# creature does not start by taking four simultaneous steps.
			limb.planted = limb.ideal
			limb.ground = limb.ideal
			limb.visual = limb.ideal
			limb.joints[1] = a.pos.lerp(limb.ideal, 0.5) + a.fwd * (limb.bend_sign * limb.total_length * 0.25)
			limb.joints[2] = limb.ideal
			limb.initialised = true

		# A foot the body has outrun skids to the edge of what the limb can
		# reach rather than staying nailed down and dislocating the leg. The
		# error stays large either way, so it is still first in line to step.
		limb.planted = limb.clamp_to_envelope(a, limb.planted, p.limb_max_reach, swing)
		limb.error = limb.planted.distance_to(limb.ideal)

	# --- 2. advance any step already in flight ------------------------------
	for limb in limbs:
		if not limb.stepping:
			limb.ground = limb.planted
			limb.lift = 0.0
			limb.visual = limb.planted
			continue

		# Keep re-aiming the landing spot at the (moving) ideal while airborne,
		# otherwise feet land in stale positions during a turn. The aim point is
		# where the ideal will be when the foot actually touches down, not where
		# it is now — see _landing_spot().
		var remaining: float = (1.0 - limb.step_t) * limb.step_duration
		var retarget: float = 1.0 - exp(-9.0 * delta)
		var aim: Vector2 = limb.clamp_to_envelope(
			body.anchors[limb.key], _landing_spot(limb, remaining), p.limb_max_reach, swing)
		limb.step_to = limb.step_to.lerp(aim, retarget)

		limb.step_t += delta / maxf(limb.step_duration, 0.001)
		if limb.step_t >= 1.0:
			limb.step_t = 1.0
			limb.stepping = false
			limb.planted = limb.step_to

		# Smoothstep along the ground path (ease out of and into the plant) with
		# a sine arc for the fake lift — a half period is exactly one hop.
		var eased: float = smoothstep(0.0, 1.0, limb.step_t)
		limb.ground = limb.step_from.lerp(limb.step_to, eased)
		limb.lift = sin(limb.step_t * PI) * p.step_height * scale * (0.45 + 0.55 * limb.pace)
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
		if limb.error >= limb.stride:
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

		_start_step(limb, body, p, swing)
		busy[limb.group] = true

		# Pull the diagonal partner onto the same beat if it is anywhere near
		# due. This is the difference between a readable trot and four legs
		# doing their own thing; coupling 0 disables it entirely.
		for other in limbs:
			if other == limb or other.group != limb.group or other.stepping:
				continue
			if other.error > other.stride * (1.0 - p.diagonal_coupling):
				_start_step(other, body, p, swing)

	# --- 4. solve the limbs -------------------------------------------------
	for limb in limbs:
		_solve_limb(limb, body, p, swing)


func _start_step(limb: Limb, body: BodyShape, p: CreatureParams, swing: float) -> void:
	limb.step_from = limb.planted
	limb.step_duration = _step_duration(limb, p)
	limb.step_to = limb.clamp_to_envelope(
		body.anchors[limb.key], _landing_spot(limb, limb.step_duration), p.limb_max_reach, swing)
	limb.step_t = 0.0
	limb.stepping = true


## How long this limb's swing phase should last.
##
## Base duration shortens with pace, as before. The second term is the one that
## matters on a turn: a foot has to be back down before its socket has dragged
## the ideal a full stride further on, or it lands already overdue and fires
## again immediately, and the limb spends its whole life in the air being
## towed. Capping the duration at that budget is what keeps the hind legs
## stepping rather than skating when the hips are sweeping fast.
func _step_duration(limb: Limb, p: CreatureParams) -> float:
	var base: float = p.step_duration * (1.0 - 0.55 * limb.pace)
	var budget: float = limb.stride / maxf(limb.socket_speed, 1.0)
	return clampf(minf(base, budget), 0.05, p.step_duration)


## Where a foot should touch down if it lifts now and lands in `flight` seconds.
##
## Aiming at the present ideal is what made the hind feet look unplanted: by the
## time the foot lands the body has moved on, so it arrives already behind and
## is dragged the whole of its stance phase. Leading by the socket's own
## velocity puts the foot down where the ideal will actually be, and the extra
## stride fraction is the margin it then has to be dragged back through before
## it is due again.
func _landing_spot(limb: Limb, flight: float) -> Vector2:
	return limb.ideal + limb.socket_vel * flight \
		+ limb.travel * (limb.stride * 0.45 * limb.pace)


func _solve_limb(limb: Limb, body: BodyShape, p: CreatureParams, swing: float) -> void:
	var a: Spine.Frame = body.anchors[limb.key]
	var root: Vector2 = a.pos
	# Solve to the *lifted* position, not the ground one, so the leg folds up
	# and clears during a step instead of dragging along the floor. The lift is
	# a raw screen-space offset, so it can push an already-extended target out of
	# range; clamping here means the fake height can never straighten the leg.
	var target: Vector2 = limb.clamp_to_envelope(a, limb.visual, p.limb_max_reach, swing)

	# Place the knee before solving. FABRIK stays on whichever side of the
	# root->target axis it starts on, so the seed is what decides which way the
	# joint bends and stops it popping between the two mirror solutions.
	#
	# For two bones the knee is just where the circles around each end meet, so
	# the seed is placed there exactly rather than nudged toward an approximate
	# pole. That is worth doing because of where the reach clamp leaves the foot:
	# hard against the limit, with the chain nearly straight — and near-straight
	# is precisely where FABRIK crawls. From a partial seed six passes get the
	# knee about seven eighths of the way out and leave the foot overshooting its
	# target by a noticeable margin, which reads as the leg locking out rigid
	# exactly when the creature is working hardest. Seeded exactly, the first
	# pass has nothing left to correct and returns on the tolerance check;
	# FABRIK still owns the general case and the out-of-range fallback.
	var l0: float = limb.lengths[0]
	var l1: float = limb.lengths[1]
	var axis: Vector2 = target - root
	var span: float = axis.length()
	var fold: float = signf(axis.cross(a.fwd * limb.bend_sign))
	if span > 0.000001 and fold != 0.0:
		var u: Vector2 = axis / span
		# Distance along the axis to the knee, and its offset perpendicular to
		# it. rot90 of the axis is always on the axis's positive-cross side, so
		# `fold` alone selects the side the joint is meant to bend toward.
		var along: float = clampf((span * span + l0 * l0 - l1 * l1) / (2.0 * span), -l0, l0)
		var off: float = sqrt(maxf(l0 * l0 - along * along, 0.0))
		limb.joints[1] = root + u * along + Vector2(-u.y, u.x) * (fold * off)

	limb.joints = Fabrik.solve(limb.joints, limb.lengths, root, target, p.fabrik_iterations, 0.05)


## True when the creature has at least one foot in the air.
func any_stepping() -> bool:
	for limb in limbs:
		if limb.stepping:
			return true
	return false
