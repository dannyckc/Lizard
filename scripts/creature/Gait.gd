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
## steps -> let the body down onto them -> solve IK. Steps are advanced before
## new ones are chosen so the "is my diagonal partner busy?" test sees this
## tick's truth, and the body is settled before the chains are posed so each leg
## is solved to the height its own foot has just put the shoulder at.
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

## Working envelope a limb keeps once there is no longer any ground under it.
## Nothing is holding a foot out in mid-air, so it comes in under the body — but
## the leg is still a leg and still attached, so this is a tuck rather than a
## fold. Feet do not plant, do not land and make no sound while it applies,
## because there is nothing there for them to do any of that against.
const TUCK_REACH: float = 0.62
## How fast a tucked limb draws in. Slower than a step, because the leg is being
## carried rather than placed.
const TUCK_RESPONSE: float = 7.0

# --- how far the body comes down ----------------------------------------------
# How high the foot comes up, how long it takes to get there, how far it goes and
# how quickly the body follows it are all `Locomotion`'s answers now — they are
# arithmetic on the animal's own mass, muscle and bones, and none of them can be a
# number typed into a preset. What is left here is the one rule about how far the
# body is allowed to sag when nothing is holding it up properly.

## Least the body may sag toward, as a share of the height its posture asks for.
## A creature whose feet have all fallen behind it is crouching, not collapsing.
const SUPPORT_FLOOR: float = 0.45


var limbs: Array[Limb] = []
## What this body can do about moving itself: its stride, its cadence, how long
## its feet stay down and how much of the vault its joints swallow. Owned by the
## creature and handed in each tick, for the same reason the anatomy is — it is a
## description of the whole animal, and three other systems read it too.
var loco: Locomotion = Locomotion.new()
## How this body holds its legs under it. Owned here rather than passed in for
## the same reason the limbs are: it is a fixed property of the animal being
## walked, not a per-tick input, and every line below that reads it would
## otherwise have to be handed it.
var posture: Posture = Posture.new()
## World-space contacts completed during the most recent update. This is motion
## state, not audio: Creature announces the landing and the world decides what
## sensory event, if any, it produces.
var landed: PackedVector2Array = PackedVector2Array()

# --- what the legs are currently holding the body at --------------------------
# Read out rather than set: each is a measurement of the four feet, taken after
# they have been placed. Between them they are the whole of the creature's weight
# shift, and none of them is animated — a body bobs because its feet moved, and
# leans because the ones on one side are further out than the ones on the other.

## Height the shoulders and the hips are actually being held at. Two numbers
## because they are held up by two different pairs of legs, and an animal whose
## arms are shorter than its legs stands nose-down without anything saying so.
var shoulder_height: float = 0.0
var hip_height: float = 0.0
## Height of the middle of the back — what Stature reads as the body's clearance.
var support: float = 0.0
## Whether the three above are a measurement yet. False until the first tick has
## placed four feet, and until then nothing may read them: a body with no gait
## solved has no feet to be standing on and has to fall back on its posture.
var measured: bool = false
## How extended the legs are actually standing this tick — the locomotion's own
## answer, less whatever the animal is folding away to get its mouth lower. Read
## rather than set by anything outside: it is what the crouch *is*.
var stance_extension: float = 0.78


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
## `reference` is the height the picture is registered to, and `airborne` says
## there is no ground under the feet at all. Both are consequences of the 2.5D
## layer above this one; left at their defaults every line below runs exactly as
## it did before it existed.
##
## `surface_query` is what is under a foot: handed a plan position, a foot radius
## and the highest that foot could be put down, it answers with the height of the
## surface there. Left out, the floor is at zero everywhere, which is the flat
## world this solver was written in and every line below still runs unchanged in
## it. `crouch` is how much of its own fold the animal is spending on getting
## lower — see `_stance_extension`.
func update(delta: float, body: BodyShape, move_dir: Vector2, speed_norm: float,
		p: CreatureParams, scale: float,
		collision_query: Callable = Callable(),
		state: BodyState = null,
		reference: float = 0.0, airborne: bool = false,
		surface_query: Callable = Callable(), crouch: float = 0.0) -> void:
	landed.clear()
	if body.anchors.is_empty():
		return

	var top_speed: float = maxf(p.move_speed * scale, 1.0)
	var swing: float = deg_to_rad(p.limb_swing_deg)
	var impaired: bool = state != null and state.impaired
	var arm: float = p.arm_length * scale
	var leg: float = p.leg_length * scale
	# What the posture asks for, before the feet get a say. The two pairs are
	# quoted separately because they are held up by different bones: a body with
	# short arms stands nose-down, and nothing had to decide that it should.
	#
	# Against `stance_reach` of the bone rather than the whole of it, and that is
	# not a fudge factor: a standing animal's legs are bent, and a stance quoted
	# against a locked-out leg is one the limb has nothing left to walk with. A
	# columnar build is where it shows — asked for the full 95% of its leg it
	# stands at the exact limit of its own reach, and a foot at the limit of its
	# reach cannot be moved forward at all, so the creature stands rigid and
	# glides. Every other number the stance is built from is already quoted this
	# way, so the rest pose comes out consistent: extended this far, at this
	# angle, is one leg described once.
	#
	# ...and then folded, by however much of its fold the animal is spending on
	# being lower. Nothing else about the crouch is written anywhere: a leg held
	# at less of itself is a shorter leg, so the stance comes in, the body comes
	# down with it, and the bands, the silhouette and the picture follow because
	# every one of them is read off the height the feet are holding.
	var rest: float = _stance_extension(crouch)
	stance_extension = rest
	var wants := Vector2(posture.clearance(arm * rest), posture.clearance(leg * rest))
	if not measured:
		# Somewhere for the first limb solve to hang its sockets from. Replaced by
		# a real reading of the feet at the end of this same tick.
		shoulder_height = wants.x
		hip_height = wants.y
		support = (wants.x + wants.y) * 0.5

	# --- 1. retarget: recompute each foot's ideal position ------------------
	for limb in limbs:
		_read_function(limb, state, impaired)
		if airborne:
			# Nothing to stand on. The limb keeps every capability it had — this is
			# not damage — it simply loses the ground those capabilities were being
			# spent against, so its envelope draws in and it stops being placed.
			limb.reach *= TUCK_REACH
		if _skip(limb):
			continue
		var a: Spine.Frame = body.anchors[limb.key]
		var front: bool = limb.pair == Limb.FRONT
		var bone: float = arm if front else leg
		limb.set_lengths(bone, posture.drawn_reach(bone))
		limb.swing_base = loco.swing_time(bone)
		limb.reference = reference
		# How high this socket is being carried — measured last tick off the feet
		# that were under it, so the leg is solved to the body it is actually
		# holding up rather than to the one the posture would like it to.
		limb.socket_height = shoulder_height if front else hip_height

		# How fast is *this* socket travelling? Every timing below is sized off
		# that rather than off the body's linear speed, so a limb on the outside
		# of a turn takes long quick strides while one near the turn centre
		# barely shuffles — and a creature pivoting on the spot, whose linear
		# speed is zero, still walks its hind feet around.
		limb.track_socket(a.pos, delta, move_dir, body.head.pos)
		limb.pace = maxf(speed_norm, clampf(limb.socket_speed / top_speed, 0.0, 1.0))

		# How far from directly beneath its own socket the foot may be put down.
		# The triangle rather than a flat projection of the leg, and that is what
		# an upright animal's stride is made of: a near-vertical limb shows barely a
		# third of itself in plan view, so measured that way its foot could never
		# be set down far enough forward to be walking — while the actual leg, most
		# of it spent going down and the rest available to lean, has half as much
		# again to reach with.
		# Quoted against the height this animal *stands* at rather than the height
		# it happens to be at this instant, and that is not a shortcut — measuring
		# it off the current sag closes a loop with nothing damping it. A body
		# carried low reaches further across the ground, feet placed further out
		# hold the body lower still, and a creature that dipped once on being set
		# down would settle into a permanent splay-legged crouch with its shoulders
		# at half height. The envelope is a property of the stance; the sag is what
		# happens inside it.
		limb.plan_limit = loco.walking_reach(bone, wants.x if front else wants.y,
			_max_reach(limb, p))

		# Where this foot rests, then: the circle the leg reaches across at the
		# stance it stands in, and how much of it the swing plane has left out to
		# the side. Both are the tilt — the first is the leg seen from above, the
		# second is that same cosine again.
		#
		# ...and then narrowed, if it has to be, to leave the stride somewhere to
		# happen — see Locomotion.stance_limit. The two are spent out of one disc,
		# and a stance that uses the whole of it is an animal with no stride and
		# feet that are dragged by its own wave.
		var lean: float = cos(posture.tilt) * p.stance_width
		limb.set_stance(a, p, minf(posture.plan_reach(bone * rest) * limb.reach,
			loco.stance_limit(limb.plan_limit, limb.sway) / maxf(lean, 0.0001)), lean)
		limb.inboard_limit = body.socket_out.get(limb.key, 0.0) * posture.adduction()

		# ...and how much of that the fore-and-aft swing may use — see
		# Locomotion.excursion. Quoted at the bottom of the animal's own bob, so it
		# is the travel the limb has over a whole stride rather than the travel it
		# has at this instant, and what the sideways stance is spending is already
		# taken off it. That last part is not a detail: a sprawled foot rests most
		# of a leg out to the side, so the fore-and-aft room left on the same disc
		# is a good deal less than the disc is wide, and a stride sized off the
		# whole disc would have the foot skidding along the boundary for the last
		# third of every step.
		# Against where the sway puts the foot rather than where it rests, because
		# the boundary is met at the worst instant of the wave and not at the
		# average one.
		limb.sweep_limit = maxf(
			loco.excursion(bone, wants.x if front else wants.y,
				absf(limb.rest_lat) + limb.sway,
				_max_reach(limb, p), _swing_fan(limb, swing)),
			0.001)

		# Stride is that travel, and nothing else. Not a species number capped by
		# the envelope afterwards — a stride longer than the travel the limb has is
		# not a long stride, it is no stride at all: the clamp skids the planted
		# foot along the boundary, the distance trigger is never reached, and the
		# leg is towed for as long as the creature keeps walking. That is what a
		# columnar animal's hind legs were doing, and there was no value of
		# `stride_distance` that would have fixed it, because the number that
		# decides it is the length of the leg and the angle it is carried at.
		#
		# What is left over from the anatomy is the two things that are genuinely
		# about this tick: a slow limb shuffles rather than lunging, and a limb with
		# no force left in it reaches less far.
		limb.stride = loco.stride(limb.sweep_limit, p.foot_lead) * posture.stride_gain \
			* (0.45 + 0.55 * limb.pace) * lerpf(STRIDE_FLOOR, 1.0, limb.drive)

		limb.plan[0] = a.pos
		limb.joints[0] = a.pos + Posture.drop(limb.socket_height, reference)
		limb.heights[0] = limb.socket_height
		# Where this foot would like to be: its rest stance, thrown ahead along the
		# way its own socket is travelling. Clamped into the envelope, because an
		# ideal outside it is not an ideal — it is a point the foot is measured
		# against, aimed at and can never arrive at, so the limb reads as
		# permanently overdue and is skidded along the boundary trying to close a
		# gap that does not shut.
		#
		# It matters most on a body that walks with its spine. A sprawled animal's
		# socket is swinging sideways as fast as the animal is going forwards, so
		# half of "ahead" for that shoulder is out past the side of its own leg —
		# and the wave puts it there twice a cycle, every cycle.
		limb.ideal = limb.clamp_to_envelope(a, limb.rest_point(a)
			+ limb.travel * (p.foot_lead * limb.stride * limb.pace))

		if not limb.initialised:
			# First tick: plant the feet where they already want to be so the
			# creature does not start by taking four simultaneous steps.
			limb.planted = limb.ideal
			limb.ground = limb.ideal
			limb.visual = limb.ideal + limb.rise()
			limb.initialised = true

		# With nothing underneath it a foot has nowhere to be nailed to, so it is
		# carried with the socket instead of being left behind by it. This is the
		# whole of the tuck: the error never grows, so nothing further down asks
		# this limb to step, and a leg that is not stepping is a leg being held.
		if airborne:
			limb.stepping = false
			limb.planted = limb.planted.lerp(limb.ideal, 1.0 - exp(-TUCK_RESPONSE * delta))

		# A foot the body has outrun skids to the edge of what the limb can
		# reach rather than staying nailed down and dislocating the leg. The
		# error stays large either way, so it is still first in line to step.
		#
		# This is also, unchanged, what dragging a dead limb looks like: a leg that
		# never picks up is a leg the body permanently outruns, so it is towed
		# along its own envelope for as long as the creature keeps walking. The
		# behaviour was already here — all a severed nerve does is stop the limb
		# taking the step that would have ended it.
		#
		# Placement is always decided for a foot on the ground, whatever the foot is
		# doing at this instant: a plant happens on a surface, so the reach that has
		# to be there is the reach down to whatever is under it. Which is no longer
		# always the floor — it is the top of whatever this foot is standing on, and
		# on the open plain that is the same number it always was.
		limb.surface = _surface_under(limb, limb.planted, scale, surface_query)
		limb.foot_height = limb.surface
		# Against what the joint can do rather than against the stride, and the two
		# are different questions. `sweep_limit` is how far this limb *walks*: it is
		# where the gait may choose to put a foot down. Where a foot may legally
		# *be* is the joint's own fan, which is wider — and a foot that has been
		# shoved outside the walking envelope by something it bumped into is
		# somewhere it can perfectly well stand. Held to the stride instead, it is
		# hauled back into the corridor every tick while the contact pass pushes it
		# out again, and the leg buzzes between the two forever.
		limb.planted = limb.clamp_to_envelope(a, limb.planted, _swing_fan(limb, swing))
		limb.error = limb.planted.distance_to(limb.ideal)

	# --- 2. advance any step already in flight ------------------------------
	for limb in limbs:
		if _skip(limb):
			continue
		if not limb.stepping:
			limb.ground = limb.planted
			limb.foot_height = limb.surface
			limb.visual = limb.planted + limb.rise()
			continue

		# Keep re-aiming the landing spot at the (moving) ideal while airborne,
		# otherwise feet land in stale positions during a turn. The aim point is
		# where the ideal will be when the foot actually touches down, not where
		# it is now — see _landing_spot().
		var remaining: float = (1.0 - limb.step_t) * limb.step_duration
		var retarget: float = 1.0 - exp(-STEP_RETARGET_RESPONSE * delta)
		var aim: Vector2 = limb.clamp_to_envelope(
			body.anchors[limb.key], _landing_spot(limb, remaining))
		limb.step_to = limb.step_to.lerp(aim, retarget)
		# The spot keeps moving, so what is under it keeps changing: a foot aimed
		# past the edge of a ledge while it is in the air is a foot that is about to
		# be put down on the floor instead, and it has to arrive at the right height
		# or the leg lands inside the ground.
		limb.step_to_surface = _surface_under(limb, limb.step_to, scale, surface_query)

		limb.step_t += delta / maxf(limb.step_duration, 0.001)
		if limb.step_t >= 1.0:
			limb.step_t = 1.0
			limb.stepping = false
			limb.planted = limb.step_to
			limb.surface = limb.step_to_surface
			landed.append(limb.planted)

		# Smoothstep along the ground path (ease out of and into the plant) with
		# a sine arc for the height — a half period is exactly one hop.
		var eased: float = smoothstep(0.0, 1.0, limb.step_t)
		limb.ground = limb.step_from.lerp(limb.step_to, eased)
		# Two terms now, and only the second is the step. The first is the ramp from
		# the surface the foot left to the one it is arriving at, which is what makes
		# a step onto a ledge a step *up* rather than a step that ends underground —
		# and on flat ground the two surfaces are equal and it contributes nothing,
		# which is why the arc below is unchanged.
		#
		# Clearance is the joint's own doing, so it is priced off what is still
		# working the knee rather than off the limb as a whole. A leg that can
		# still be swung from the shoulder but cannot flex below it scuffs.
		limb.foot_height = lerpf(limb.step_from_surface, limb.step_to_surface, eased) \
			+ sin(limb.step_t * PI) * _step_clearance(limb) \
			* (0.45 + 0.55 * limb.pace) * lerpf(LIFT_FLOOR, 1.0, limb.flex)
		limb.visual = limb.ground + limb.rise()

	# --- 3. decide which feet pick up ---------------------------------------
	# A body with nothing under it never picks a foot up, because a step is a
	# push against the ground and there is none. Skipping the contest outright
	# rather than failing every limb's test is the same distinction `_skip` draws:
	# these legs are not stepping badly, they are not stepping.
	if airborne:
		_carry_body(delta, p, wants)
		for limb in limbs:
			if not _skip(limb):
				_solve_limb(limb, body, p, scale, collision_query)
		return

	var busy: Array[bool] = [false, false]
	var aloft: int = 0
	var candidates: Array[Limb] = []
	for limb in limbs:
		if _skip(limb):
			continue
		if limb.stepping:
			busy[limb.group] = true
			aloft += 1
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
	#
	# Against each limb's own stride rather than in raw pixels, because the four
	# are not asking the same question: an arm is shorter than a leg, strides
	# shorter for it, and is due for a step at a smaller drift. Compared flat, the
	# pair with the longer stride is permanently the more overdue-looking of the
	# two and takes every slot — which on a single-support build is the whole of
	# the gait.
	candidates.sort_custom(func(a: Limb, b: Limb) -> bool:
		return a.error / maxf(a.stride, 0.001) > b.error / maxf(b.stride, 0.001))

	# How many feet this build will lift at once. Two for a body that can throw
	# itself between diagonals; one for a columnar animal, which has to keep
	# three legs under a great deal of weight and therefore ambles rather than
	# trots. It is the posture's one hard rule, and it is the reason a heavy
	# stance reads as deliberate without anything having slowed it down.
	var limit: int = posture.airborne_limit()
	var coupling: float = clampf(p.diagonal_coupling * posture.coupling_gain, 0.0, 1.0)

	for limb in candidates:
		if limb.stepping:
			continue
		if aloft >= limit:
			break
		# Never lift a foot while the opposite diagonal is airborne: that is
		# what keeps at least two feet down and the creature standing.
		if busy[1 - limb.group]:
			continue

		_start_step(limb, body, p, scale, surface_query)
		busy[limb.group] = true
		aloft += 1

		# Pull the diagonal partner onto the same beat if it is anywhere near
		# due. This is the difference between a readable trot and four legs
		# doing their own thing; coupling 0 disables it entirely.
		for other in limbs:
			if other == limb or other.group != limb.group or other.stepping:
				continue
			if aloft >= limit:
				break
			# The same gate as the contest above, and it has to be here too: a beat
			# is an invitation, not an order. Without this a dead limb is pulled
			# into its partner's step and picks itself up, which is the one thing a
			# limb with no nerve reaching it must never do — and it would happen on
			# the alternate ticks, so the leg would appear to work intermittently.
			if not _can_step(other):
				continue
			if other.error > other.stride * (1.0 - coupling):
				_start_step(other, body, p, scale, surface_query)
				aloft += 1

	# --- 4. let the body down onto the feet that were just placed -------------
	# Before the limbs are posed rather than after, and the ordering is the whole
	# difference between a leg that reaches and one that skids. A foot is put down
	# where the stride says, which is out at the reach the leg has once the body
	# has come down over it; solve the chain first and the shoulder is still up
	# where it was last tick, the leg is a fraction too short for its own foot, and
	# the envelope drags the foot back in. Then the body sinks, the foot is let out
	# again, and the two chase each other for the whole of the stance phase — which
	# is exactly what a planted foot creeping backward under a walking animal is.
	#
	# Settling first, the chain is solved to a body that is already standing where
	# these feet put it.
	_carry_body(delta, p, wants)
	for limb in limbs:
		if _skip(limb):
			continue
		limb.socket_height = shoulder_height if limb.pair == Limb.FRONT else hip_height

	# --- 5. solve the limbs ---------------------------------------------------
	for limb in limbs:
		if _skip(limb):
			continue
		_solve_limb(limb, body, p, scale, collision_query)


## How high the four feet are actually holding the body, and how the body follows
## them down.
##
## Nothing here decides anything. A leg is a fixed length, so a foot set down
## further from its socket is a socket held lower — that is Pythagoras, and it is
## the only rule in this function. Everything that reads as weight comes out of
## it: the body sinks as a stride reaches its extreme and rises again as the foot
## comes back under the shoulder, which is a bob at exactly step frequency
## because that is what it is a measurement of; a short-armed animal stands
## nose-down because its shoulders are held by shorter bones than its hips; and a
## columnar creature barely moves at all, because a leg held near vertical loses
## almost no height to being swung.
##
## Only feet that are down are asked. A limb in the air is not carrying anything,
## and a limb that cannot bear weight has already said so.
func _carry_body(delta: float, p: CreatureParams, wants: Vector2) -> void:
	var front: float = _pair_support(Limb.FRONT, p, wants.x)
	var rear: float = _pair_support(Limb.REAR, p, wants.y)
	# Weight takes a moment to settle onto a leg, but a body that has just been
	# built is not settling onto anything — it is already standing there. Easing
	# in from the posture's guess instead would spend the first third of a second
	# lowering the animal onto its own feet, and the feet, whose envelope is a
	# function of how high their socket is, would take a step to keep up. A
	# creature that shuffles once on being placed is a creature no fixture can
	# take aim at.
	#
	# How fast it settles is quoted per step cycle rather than per second, because
	# that is what it is a measurement of: the body follows its feet at the pace
	# its feet are moving. A response tuned for a lizard taking four steps a second
	# would smooth an elephant's whole walk into a glide.
	var response: float = 1.0 - exp(-loco.settle(_body_cycle()) * delta) if measured else 1.0
	measured = true
	# Eased toward what the legs are offering, and then cut off hard at what they
	# can physically reach. The two are different claims and only the second is a
	# law: a body may take its time settling onto its feet, but it may never for
	# one tick be held higher than the leg standing under it is long. Easing alone
	# leaves it a fraction of a second above its own feet after every fast
	# placement, and a body above its feet is a body floating — which is the whole
	# thing the vertical limb solve exists to prevent.
	shoulder_height = minf(lerpf(shoulder_height, front, response), _pair_ceiling(Limb.FRONT, p))
	hip_height = minf(lerpf(hip_height, rear, response), _pair_ceiling(Limb.REAR, p))
	support = (shoulder_height + hip_height) * 0.5


## The height one pair of legs is holding its end of the body at: whichever of the
## two is doing worse, since the body cannot ride higher than the shortest reach
## underneath it.
##
## Each leg answers twice and the truth is between them. Held at one length it
## vaults — high with the foot underneath the shoulder, low with the foot thrown
## out fore or aft — and that is what a step does to a body. Levelling perfectly,
## it simply stands at the height the stance asks for and extends as required,
## which is what an animal is doing when it carries a head steady over rough
## ground. Neither alone is a walk.
##
## `wants` is a *clearance* rather than a height — how far this pair of legs likes
## to hold its end of the body above whatever it is standing on — so it is quoted
## against each foot's own surface rather than against the world's floor. On flat
## ground every surface is zero and the two are the same number, which is why
## nothing about this function changed for an animal on a plain. On a ledge they
## are not: a leg standing six pixels up holds the shoulder six pixels higher, and
## a levelling term that had forgotten to say so would cap the body at the height
## it stands at on the floor and quietly pin the animal to the ground it had just
## climbed off.
func _pair_support(pair: int, p: CreatureParams, wants: float) -> float:
	var held: float = INF
	var floor_height: float = INF
	for limb in limbs:
		if limb.pair != pair or _skip(limb) or limb.stepping:
			continue
		if limb.carry < SUPPORT_MIN:
			continue
		var vault: float = limb.support_height(stance_extension)
		var level: float = minf(limb.surface + wants,
			limb.support_height(_max_reach(limb, p)))
		held = minf(held, lerpf(vault, level, loco.absorbed))
		floor_height = minf(floor_height, limb.surface)
	if is_inf(held):
		return wants
	# The sag is measured from the ground under the feet for the same reason the
	# stance is. A body crouching on a ledge crouches toward the ledge.
	return maxf(held, floor_height + wants * SUPPORT_FLOOR)


## The highest one pair of legs could possibly hold its end of the body, with the
## feet where they are now. Pythagoras again, and at the limb's outright limit
## rather than the reach it prefers to stand at: this is not where the body wants
## to be, it is the line it may not be on the wrong side of.
##
## Every limb of the pair answers, including one in the air — see
## Limb.carry_ceiling. Carrying and reaching are different questions and only the
## first is about being planted.
##
## Infinite when nothing is attached — a body with no legs of that pair left is
## not being held up by them, and whatever is deciding its height, it is not this.
func _pair_ceiling(pair: int, p: CreatureParams) -> float:
	var ceiling: float = INF
	for limb in limbs:
		if limb.pair != pair or _skip(limb) or limb.carry < SUPPORT_MIN:
			continue
		ceiling = minf(ceiling, limb.carry_ceiling(_max_reach(limb, p)))
	return ceiling


## Limbs this solver has no business touching: the ones that are not there, and
## the ones nothing is holding out.
##
## The second is not a weaker version of walking, which is why it is a skip rather
## than another number to multiply a stride by. A leg whose bone has been ground
## through has no stance to be placed in and no step to take badly; it hangs from
## the socket and goes where the body drags it, and that is `Ragdoll`'s business.
func _skip(limb: Limb) -> bool:
	return limb.severed or limb.carried


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
		limb.carried = false
		return
	var region: BodyState.Region = state.limb(limb.key)
	if region == null:
		return
	limb.severed = region.severed
	# A limb still on the animal but no longer on its skeleton stops being walked
	# and starts being carried. Nothing below is wrong for it — it is simply that
	# a stride, a plant and a swing are all answers about where to *put* a limb,
	# and there is nothing left to put this one anywhere.
	limb.carried = region.hanging
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


func _start_step(limb: Limb, body: BodyShape, p: CreatureParams, scale: float,
		surface_query: Callable) -> void:
	limb.step_from = limb.planted
	limb.step_from_surface = limb.surface
	limb.step_index += 1
	limb.step_duration = _step_duration(limb)
	limb.step_to = limb.clamp_to_envelope(
		body.anchors[limb.key], _landing_spot(limb, limb.step_duration))
	limb.step_to_surface = _surface_under(limb, limb.step_to, scale, surface_query)
	limb.step_t = 0.0
	limb.stepping = true


## How high the ground is where this foot is being put down.
##
## The ceiling handed to the query is the one anatomical fact in it, and it is the
## same one `Traversal` makes its first condition of a climb: a foot goes as high
## as the joint that swings it and no higher, so anything whose top is above the
## socket is not a surface this leg can stand on and the query answers with
## whatever is underneath instead. That is the difference between stepping onto a
## ledge and walking into a wall, and it is decided here — per foot, per tick, off
## the height that foot's own shoulder is currently being carried at — rather than
## by anything that knows what the obstacle is.
##
## Zero with no query attached, which is the flat floor this solver was written
## against and the behaviour every line of it still has without one.
func _surface_under(limb: Limb, at: Vector2, scale: float, query: Callable) -> float:
	if not query.is_valid():
		return 0.0
	var foot: float = limb.foot_radius(scale)
	var answer: Variant = query.call(at, foot, limb.socket_height + foot)
	return (answer as Vector2).x if answer is Vector2 else 0.0


## How extended the legs stand this tick: what the animal's locomotion asks for,
## folded toward the tightest a limb may be drawn up by however much crouch is
## being spent.
##
## `Limb.REACH_MIN` is the floor rather than a chosen one — it is the shortest the
## two-bone chain may be solved to anywhere in the game, so "fully folded" is the
## same number here and in the IK, and a crouch can never ask for a leg the solver
## would then refuse to draw.
func _stance_extension(crouch: float) -> float:
	return lerpf(loco.extension, Limb.REACH_MIN, clampf(crouch, 0.0, 1.0))


## How high this limb picks its foot up at the top of a step. A real height in
## world pixels, not a screen offset, because it is the height something else has
## to be shorter than to pass underneath — see Locomotion.lift for why it is a
## share of the animal rather than a number.
func _step_clearance(limb: Limb) -> float:
	return loco.lift(limb.socket_height, limb.anatomical_length) * posture.step_height_gain


## How long this limb's swing phase should last.
##
## Three terms, and the middle one is new and is the reason a columnar animal now
## walks on four legs instead of two:
##
##   * the limb's own pendulum swing, shortened at pace. A leg is a weight hanging
##     off a shoulder, so a long one takes longer to come through however strong
##     the animal is — which is the whole of why an elephant's feet move
##     deliberately, and it is not a number anybody chose.
##   * the duty factor, as a deadline. A posture that keeps three feet on the
##     ground is a posture in which a foot may be in the air for a quarter of its
##     cycle and not a moment more. Without this the two front legs of a
##     single-support build used the whole of the airborne slot between them —
##     each of them aloft half the time — and the hind pair, which could never
##     find a gap, was towed along the ground for as long as the creature walked.
##     Nothing was wrong with the hind legs; there was simply never room for them.
##   * a weak limb swings *slower*, which is the second half of a limp. The
##     ceiling rises with it, because a leg that cannot keep up is exactly a leg
##     that should be seen labouring rather than one held to a healthy tempo.
func _step_duration(limb: Limb) -> float:
	var labour: float = lerpf(SWING_SLOWEST, 1.0, limb.drive)
	var base: float = limb.swing_base * (1.0 - 0.55 * limb.pace) * labour
	var budget: float = loco.swing_budget(limb.stride / maxf(limb.socket_speed, 1.0))
	return clampf(minf(base, budget), Locomotion.SWING_FLOOR, limb.swing_base * labour)


## How long one limb's whole step cycle currently is, averaged over the legs that
## are walking. A measurement rather than a setting: the stride each foot has and
## how fast its own socket is travelling through it.
func _body_cycle() -> float:
	var total: float = 0.0
	var count: int = 0
	for limb in limbs:
		if _skip(limb):
			continue
		total += limb.stride / maxf(limb.socket_speed, 1.0)
		count += 1
	return total / maxf(float(count), 1.0)


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


## Poses one limb, and then routes it around anything in the way.
##
## The target is where the foot is standing *on the ground plane* — its height is
## already on the limb — and the whole chain is built up from there, so a foot the
## solver was given stays exactly where it was given. Contact avoidance moves that
## target and asks again; it never touches a bone.
func _solve_limb(limb: Limb, body: BodyShape, p: CreatureParams,
		scale: float, collision_query: Callable) -> void:
	var a: Spine.Frame = body.anchors[limb.key]
	# The joint's own fan, not the stride: routing around an obstacle is a limb
	# being pushed somewhere, and where it may be pushed is an anatomical question.
	# Held to the walking corridor the leg has nowhere to go round a body parked
	# against its shank, and stands in it.
	var fan: float = _swing_fan(limb, deg_to_rad(p.limb_swing_deg))
	var target: Vector2 = limb.clamp_to_envelope(a, limb.ground, fan)
	limb.solve_stance(a, target, p.fabrik_iterations)

	if not collision_query.is_valid():
		return

	# Contacts are tested where the limb *is*, on the ground plane, and each part
	# carries the heights it occupies alongside. Both halves are needed and the
	# first is not a detail: "underneath" is a statement about two things sharing a
	# position and differing in height, so it can only be asked in the one frame
	# where a foot and the animal walking under it have the same coordinates. Ask
	# it in the picture instead and a raised foot has simply moved somewhere else,
	# which is not the same claim at all.
	#
	# So a leg only routes around what it would actually walk into: a planted foot
	# is an obstacle at ankle height, and the same foot picked up is a doorway.
	var upper_radius: float = limb.girth(scale) * 0.5
	var lower_radius: float = upper_radius * 0.72
	var foot_radius: float = limb.foot_radius(scale)
	var contact_applied: bool = false
	for _iteration in LIMB_CONTACT_ITERATIONS:
		var upper_push: Vector2 = collision_query.call(
			limb.key, 0, limb.plan[0], limb.plan[1], upper_radius, limb.segment_band(0, scale))
		var lower_push: Vector2 = collision_query.call(
			limb.key, 1, limb.plan[1], limb.plan[2], lower_radius, limb.segment_band(1, scale))
		var foot_push: Vector2 = collision_query.call(
			limb.key, 2, limb.plan[2], limb.plan[2], foot_radius, limb.segment_band(2, scale))

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
			a, target + correction.limit_length(max_correction), fan)
		if next_target.distance_squared_to(target) <= 0.000001:
			# The direct route can point outside the limb's stance corridor. In
			# that case walk along the obstacle instead, keeping the choice of side
			# stable by preferring the limb's anatomical outward direction.
			var route: Vector2 = Vector2(-correction.y, correction.x).normalized()
			if route.dot(limb.rest_dir) < 0.0:
				route = -route
			next_target = limb.clamp_to_envelope(a, target + route * max_correction, fan)
			if next_target.distance_squared_to(target) <= 0.000001:
				next_target = limb.clamp_to_envelope(a, target - route * max_correction, fan)
			if next_target.distance_squared_to(target) <= 0.000001:
				break
		target = next_target
		contact_applied = true
		limb.solve_stance(a, target, p.fabrik_iterations)

	# Keep the gait's world-space foot state aligned with the collision-safe
	# solve. A planted foot slides around the obstacle; an airborne one keeps
	# its lift and is re-routed again as its procedural arc advances.
	if contact_applied:
		limb.ground = target
		limb.visual = target + limb.rise()
		if not limb.stepping:
			limb.planted = target


## True when the creature has at least one foot in the air.
func any_stepping() -> bool:
	for limb in limbs:
		if limb.stepping:
			return true
	return false
