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

## A few target/IK passes are enough for a two-bone chain to route around a
## smooth body capsule. Corrections are capped so a deeply spawned overlap
## unfolds over adjacent frames rather than making a foot teleport.
const LIMB_CONTACT_ITERATIONS: int = 6
const LIMB_CONTACT_SLOP: float = 0.35
const STEP_RETARGET_RESPONSE: float = 14.0
const LANDING_PREDICTION_STRIDES: float = 0.65

# --- what a failing limb does -------------------------------------------------
# Every constant below shapes how one number from BodyState turns into movement.
# None of them names a behaviour: there is no limp here, no drag, no collapse.
# There is a shorter stride, a slower swing, a lower foot and a limb that stops
# asking to be picked up — and a creature doing all four at once on one leg is
# limping, without anything having decided to.

## Stride left to a limb with no force at all, as a fraction of its healthy one.
## This is the whole of the limp: a weak leg reaches less far, its diagonal
## partner does not, and the gait's own distance trigger turns that asymmetry into
## a short-long-short rhythm on its own.
const STRIDE_FLOOR: float = 0.34
## How much longer a spent limb takes to swing through. Weakness is slowness as
## well as shortness, and without this a feeble leg would flick through its little
## stride at full speed and read as twitchy rather than laboured.
const SWING_SLOWEST: float = 2.1
## Foot clearance left to a limb that cannot work its own joint. At zero the foot
## never leaves the ground, so a limb with a cut nerve is dragged along it — the
## drag is a consequence of no lift, not a mode.
const LIFT_FLOOR: float = 0.0
## Working envelope left to a limb with no range of motion, and the further
## collapse a limb that cannot carry itself folds to. Kept clear of Limb.REACH_MIN
## so the envelope never inverts.
const REACH_FLOOR: float = 0.60
const FOLD_REACH: float = 0.70
## Swing fan left to a stiffened limb.
const SWING_FAN_FLOOR: float = 0.55
## Load-bearing at which a limb stops being asked to carry the body. It still
## exists, is still solved and is still dragged; it just is not stood on.
const SUPPORT_MIN: float = 0.30
## Below this much command a limb no longer initiates steps at all.
const CONTROL_MIN: float = 0.12
## How far a badly controlled foot misses its mark by, as a fraction of stride. A
## damaged nerve does not merely weaken a limb — it makes it inaccurate, and this
## is that: the foot is put down near where it was aimed rather than on it.
const PLACEMENT_SCATTER: float = 0.55

var limbs: Array[Limb] = []
## World-space contacts completed during the most recent update. This is motion
## state, not audio: Creature announces the landing and the world decides what
## sensory event, if any, it produces.
var landed: PackedVector2Array = PackedVector2Array()


func setup() -> void:
	limbs.clear()
	landed.clear()
	var fl: Limb = Limb.new(); fl.setup("FL", Limb.FRONT, 1.0)
	var fr: Limb = Limb.new(); fr.setup("FR", Limb.FRONT, -1.0)
	var rl: Limb = Limb.new(); rl.setup("RL", Limb.REAR, 1.0)
	var rr: Limb = Limb.new(); rr.setup("RR", Limb.REAR, -1.0)
	# Order matters: it is the tie-breaker when both diagonal pairs are equally
	# overdue (e.g. moving in a perfectly straight line), and it is what stops
	# all four feet lifting on the same tick.
	limbs = [fl, rr, fr, rl]


## `state` is what the anatomy says the four limbs can currently do. Left null —
## or given a body with nothing wrong with it — every line below runs on the
## values it always did, so a healthy creature is unaffected by the existence of
## the whole system.
func update(delta: float, body: BodyShape, move_dir: Vector2, speed_norm: float,
		p: CreatureParams, scale: float,
		collision_query: Callable = Callable(),
		state: BodyState = null) -> void:
	landed.clear()
	if body.anchors.is_empty():
		return

	var top_speed: float = maxf(p.move_speed * scale, 1.0)
	var swing: float = deg_to_rad(p.limb_swing_deg)
	var impaired: bool = state != null and state.impaired

	# --- 1. retarget: recompute each foot's ideal position ------------------
	for limb in limbs:
		_read_function(limb, state, impaired)
		if limb.severed:
			continue
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
		# lunging, and lengthens toward a full stride at top pace — and then again
		# by whatever force the limb can still put into pushing the body along.
		limb.stride = p.stride_distance * scale * (0.45 + 0.55 * limb.pace) \
			* lerpf(STRIDE_FLOOR, 1.0, limb.drive)

		# Rest stance in the socket's own frame — the centre of the swing fan.
		limb.set_rest_dir(a, p)

		limb.joints[0] = a.pos
		limb.ideal = a.pos \
			+ limb.rest_dir * (limb.total_length * p.stance_reach * limb.reach) \
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
		#
		# This is also, unchanged, what dragging a dead limb looks like: a leg that
		# never picks up is a leg the body permanently outruns, so it is towed
		# along its own envelope for as long as the creature keeps walking. The
		# behaviour was already here — all a severed nerve does is stop the limb
		# taking the step that would have ended it.
		limb.planted = limb.clamp_to_envelope(
			a, limb.planted, _max_reach(limb, p), _swing_fan(limb, swing))
		limb.error = limb.planted.distance_to(limb.ideal)

	# --- 2. advance any step already in flight ------------------------------
	for limb in limbs:
		if limb.severed:
			continue
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
		var retarget: float = 1.0 - exp(-STEP_RETARGET_RESPONSE * delta)
		var aim: Vector2 = limb.clamp_to_envelope(
			body.anchors[limb.key], _landing_spot(limb, remaining),
			_max_reach(limb, p), _swing_fan(limb, swing))
		limb.step_to = limb.step_to.lerp(aim, retarget)

		limb.step_t += delta / maxf(limb.step_duration, 0.001)
		if limb.step_t >= 1.0:
			limb.step_t = 1.0
			limb.stepping = false
			limb.planted = limb.step_to
			landed.append(limb.planted)

		# Smoothstep along the ground path (ease out of and into the plant) with
		# a sine arc for the fake lift — a half period is exactly one hop.
		var eased: float = smoothstep(0.0, 1.0, limb.step_t)
		limb.ground = limb.step_from.lerp(limb.step_to, eased)
		# Clearance is the joint's own doing, so it is priced off what is still
		# working the knee rather than off the limb as a whole. A leg that can
		# still be swung from the shoulder but cannot flex below it scuffs.
		limb.lift = sin(limb.step_t * PI) * p.step_height * scale \
			* (0.45 + 0.55 * limb.pace) * lerpf(LIFT_FLOOR, 1.0, limb.flex)
		limb.visual = limb.ground - Vector2(0.0, limb.lift)

	# --- 3. decide which feet pick up ---------------------------------------
	var busy: Array[bool] = [false, false]
	var candidates: Array[Limb] = []
	for limb in limbs:
		if limb.severed:
			continue
		if limb.stepping:
			busy[limb.group] = true
			continue
		# Recompute against this tick's plant: step 2 may have just landed this
		# foot, and deciding on the pre-landing error would re-fire it instantly.
		limb.error = limb.planted.distance_to(limb.ideal)
		# A limb with no command does not decline to step — nothing asks it to.
		# It stays out of the contest entirely and is dragged by the clamp above.
		if not _can_step(limb):
			continue
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
			# The same gate as the contest above, and it has to be here too: a beat
			# is an invitation, not an order. Without this a dead limb is pulled
			# into its partner's step and picks itself up, which is the one thing a
			# limb with no nerve reaching it must never do — and it would happen on
			# the alternate ticks, so the leg would appear to work intermittently.
			if not _can_step(other):
				continue
			if other.error > other.stride * (1.0 - p.diagonal_coupling):
				_start_step(other, body, p, swing)

	# --- 4. solve the limbs -------------------------------------------------
	for limb in limbs:
		if limb.severed:
			continue
		_solve_limb(limb, body, p, swing, scale, collision_query)


## Caches what the anatomy says about one limb, so everything downstream reads a
## single agreed set of numbers rather than re-deriving them.
##
## An unimpaired body — or one with no anatomy attached at all — leaves every
## value at 1.0, which is the guarantee that a healthy creature walks exactly as
## it did before this existed.
func _read_function(limb: Limb, state: BodyState, impaired: bool) -> void:
	if not impaired:
		limb.drive = 1.0
		limb.flex = 1.0
		limb.command = 1.0
		limb.carry = 1.0
		limb.reach = 1.0
		limb.severed = false
		return
	var region: BodyState.Region = state.limb(limb.key)
	if region == null:
		return
	limb.severed = region.severed
	limb.command = region.control
	limb.carry = region.load
	# Force across the socket is what pushes the body along, so that is what the
	# stride is priced off — not the limb's average. A shoulder eaten out and a
	# shank eaten out are different injuries and have to walk differently, and
	# these two lines are the whole of why they do.
	limb.drive = minf(region.strength,
		state.actuator(region.index, BodyPlan.JOINT_ROOT))
	limb.flex = state.actuator(region.index, BodyPlan.JOINT_MID)
	# A limb that cannot bear its own weight folds under the body as well as
	# reaching less far, so the two collapse into one envelope scale.
	var fold: float = 1.0 if region.load >= SUPPORT_MIN \
		else lerpf(FOLD_REACH, 1.0, region.load / SUPPORT_MIN)
	limb.reach = lerpf(REACH_FLOOR, 1.0, region.motion_range) * fold


## Whether this limb can pick itself up at all.
##
## Two ways to fail it, and they are different animals: no command reaching the
## limb, and not enough of it left to stand the body on while the diagonal is in
## the air. Either way the leg still exists, is still solved and is still dragged;
## it is only never *asked*.
func _can_step(limb: Limb) -> bool:
	return limb.command >= CONTROL_MIN and limb.carry >= SUPPORT_MIN


## The reach and the fan this limb may currently be placed inside. Both narrow
## with its range of motion, which is what stops a stiffened leg from being
## solved to a stance it could no longer physically adopt.
func _max_reach(limb: Limb, p: CreatureParams) -> float:
	return p.limb_max_reach * limb.reach


func _swing_fan(limb: Limb, swing: float) -> float:
	return swing * lerpf(SWING_FAN_FLOOR, 1.0, limb.reach)


func _start_step(limb: Limb, body: BodyShape, p: CreatureParams, swing: float) -> void:
	limb.step_from = limb.planted
	limb.step_index += 1
	limb.step_duration = _step_duration(limb, p)
	limb.step_to = limb.clamp_to_envelope(
		body.anchors[limb.key], _landing_spot(limb, limb.step_duration),
		_max_reach(limb, p), _swing_fan(limb, swing))
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
## A weak limb also swings *slower*, which is the second half of a limp — the
## ceiling rises with it, because a leg that cannot keep up is exactly a leg that
## should be seen labouring rather than one quietly held to a healthy tempo.
func _step_duration(limb: Limb, p: CreatureParams) -> float:
	var labour: float = lerpf(SWING_SLOWEST, 1.0, limb.drive)
	var base: float = p.step_duration * (1.0 - 0.55 * limb.pace) * labour
	var budget: float = limb.stride / maxf(limb.socket_speed, 1.0)
	return clampf(minf(base, budget), 0.05, p.step_duration * labour)


## Where a foot should touch down if it lifts now and lands in `flight` seconds.
##
## Aiming at the present ideal is what made the hind feet look unplanted: by the
## time the foot lands the body has moved on, so it arrives already behind and
## is dragged the whole of its stance phase. Leading by the socket's own
## velocity puts the foot down where the ideal will actually be. The prediction
## is capped because `ideal` already contains the authored foot lead: an
## uncapped flight prediction plus another fixed lead makes a quick turn or
## reversal send the foot on a needlessly wide correction.
func _landing_spot(limb: Limb, flight: float) -> Vector2:
	var prediction: Vector2 = (limb.socket_vel * flight).limit_length(
		limb.stride * LANDING_PREDICTION_STRIDES)
	return limb.ideal + prediction + _scatter(limb)


## How far a poorly controlled foot misses by.
##
## Nerve damage is not only weakness — a limb the animal has partly lost track of
## is put down *near* where it was aimed. The offset is fixed for the whole of one
## step rather than resampled per frame, because a foot hunting about in mid-air
## reads as jitter while a foot planted in the wrong place reads as a stumble.
##
## Derived from the step count rather than drawn from a generator, so a given body
## placing a given step misses the same way every run — the same determinism the
## carcass's resting pose is built on.
func _scatter(limb: Limb) -> Vector2:
	if limb.command >= 0.999:
		return Vector2.ZERO
	var miss: float = (1.0 - limb.command) * PLACEMENT_SCATTER * limb.stride
	var phase: float = float(hash(Vector2i(limb.step_index, limb.group)) % 62831) * 0.0001
	return Vector2.RIGHT.rotated(phase) * miss


func _solve_limb(limb: Limb, body: BodyShape, p: CreatureParams, swing: float,
		scale: float, collision_query: Callable) -> void:
	var a: Spine.Frame = body.anchors[limb.key]
	var reach: float = _max_reach(limb, p)
	var fan: float = _swing_fan(limb, swing)
	# Solve to the *lifted* position, not the ground one, so the leg folds up
	# and clears during a step instead of dragging along the floor. The lift is
	# a raw screen-space offset, so it can push an already-extended target out of
	# range; clamping here means the fake height can never straighten the leg.
	var target: Vector2 = limb.clamp_to_envelope(a, limb.visual, reach, fan)
	_solve_limb_to(limb, a, target, p)

	if collision_query.is_valid():
		var upper_radius: float = maxf(limb.total_length * 0.16, 2.5 * scale) * 0.5
		var lower_radius: float = upper_radius * 0.72
		var foot_radius: float = maxf(limb.total_length * 0.10, 3.0 * scale)
		var contact_applied: bool = false
		for _iteration in LIMB_CONTACT_ITERATIONS:
			var upper_push: Vector2 = collision_query.call(
				limb.key, 0, limb.joints[0], limb.joints[1], upper_radius)
			var lower_push: Vector2 = collision_query.call(
				limb.key, 1, limb.joints[1], limb.joints[2], lower_radius)
			var foot_push: Vector2 = collision_query.call(
				limb.key, 2, limb.joints[2], limb.joints[2], foot_radius)

			# Moving the target bends both bones through the ordinary IK solve.
			# The upper bone has only about half the foot's leverage, so amplify
			# its correction; lower-bone and foot contacts track more directly.
			var correction: Vector2 = foot_push
			if lower_push.length_squared() * 1.3 * 1.3 > correction.length_squared():
				correction = lower_push * 1.3
			if upper_push.length_squared() * 2.0 * 2.0 > correction.length_squared():
				correction = upper_push * 2.0
			if correction.length_squared() <= LIMB_CONTACT_SLOP * LIMB_CONTACT_SLOP:
				break

			var max_correction: float = maxf(limb.total_length * 0.22, 4.0 * scale)
			var next_target: Vector2 = limb.clamp_to_envelope(
				a, target + correction.limit_length(max_correction), reach, fan)
			if next_target.distance_squared_to(target) <= 0.000001:
				# The direct route can point outside the limb's reach fan. In that
				# case walk along the obstacle instead, keeping the choice of side
				# stable by preferring the limb's anatomical outward direction.
				var route: Vector2 = Vector2(-correction.y, correction.x).normalized()
				if route.dot(limb.rest_dir) < 0.0:
					route = -route
				next_target = limb.clamp_to_envelope(
					a, target + route * max_correction, reach, fan)
				if next_target.distance_squared_to(target) <= 0.000001:
					next_target = limb.clamp_to_envelope(
						a, target - route * max_correction, reach, fan)
				if next_target.distance_squared_to(target) <= 0.000001:
					break
			target = next_target
			contact_applied = true
			_solve_limb_to(limb, a, target, p)

		# Keep the gait's world-space foot state aligned with the collision-safe
		# solve. A planted foot slides around the obstacle; an airborne one keeps
		# its lift and is re-routed again as its procedural arc advances.
		if contact_applied:
			limb.visual = limb.joints[2]
			limb.ground = limb.visual + Vector2(0.0, limb.lift)
			if not limb.stepping:
				limb.planted = limb.ground
				limb.visual = limb.planted


## Seeds the anatomical bend and runs the existing fixed-length IK solve for a
## target. Contact avoidance only changes that target; it never compromises bone
## length or invents a second animation system.
func _solve_limb_to(limb: Limb, a: Spine.Frame, target: Vector2,
		p: CreatureParams) -> void:
	# The seed is what decides which way the joint bends — see Limb.seed_joint.
	limb.seed_joint(a, target)
	limb.joints = Fabrik.solve(limb.joints, limb.lengths, a.pos, target, p.fabrik_iterations, 0.05)


## True when the creature has at least one foot in the air.
func any_stepping() -> bool:
	for limb in limbs:
		if limb.stepping:
			return true
	return false
