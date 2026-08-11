## Where each foot wants to be, when it picks up, and where it lands — Gait's
## successor, solving the armature's four limb chains instead of its own.
##
## The rule is entirely reactive:
##
##   * every foot has an ideal position derived from the body's current pose;
##   * a planted foot stays nailed to the world until it drifts further than
##     `stride` from that ideal;
##   * when it does, it arcs to a spot slightly *ahead* of the ideal and re-plants.
##
## Because the trigger is distance rather than a timer, step frequency falls out of
## how fast the animal is actually going, and a creature is naturally still when
## idle. Which foot goes next is not decided here — see Cadence, where it falls out
## of the body's proportions and how fast it is going for its size. What this file
## owns is when a foot is *due*, which is still the distance rule above.
##
## Order within `update`: read the sockets the armature has just placed → size each
## foot's envelope → share one stride between the four → solve the pattern →
## advance steps in flight → decide new steps → let the body down onto them → hand
## the armature its feet. Steps advance before new ones are chosen so the "is
## anything from another beat still in the air?" test sees this tick's truth, and
## the body is settled before the limbs are placed so each leg is solved to the
## height its own foot has just put the shoulder at.
##
## Everything this file reads out — the girdle heights, the pitch, the roll, the
## top speed — is a *measurement* of the four feet after they have been placed. A
## body bobs because its feet moved and leans because the ones on one side are
## further out than the ones on the other; none of it is animated.
class_name Tread
extends RefCounted

## How fast a step's landing spot chases the (moving) ideal while the foot is in
## the air, and how far ahead of it a foot may be aimed.
const STEP_RETARGET_RESPONSE: float = 14.0
const LANDING_PREDICTION_STRIDES: float = 0.65

## How far a swinging foot is carried in under its own socket at the top of the
## step, as a share of the way there, before it is scaled by the joint's own
## travel. The fold half of a swing: the limb comes through bent, not towed
## straight between two footprints — so a cat tucks and a column does not.
const SWING_TUCK: float = 0.30

## How far a foot will look for somewhere better to stand, in footprints, and in
## how many steps out. Short: this is a foot being placed a little more carefully,
## not a leg going hunting.
const FOOTING_STEPS: int = 3
const FOOTING_REACH: float = 0.9

## How fast a body may be carried up or down, as a multiple of the vertical speed
## one of its own steps moves a foot at. An ease is not a speed, and on broken
## ground the difference is the whole bug: easing moves the body by a fraction of
## what is *left*, so a target that jumps by the height of a rock moves the body
## furthest on the first tick — which on a leg near its own lock-out is a few
## pixels of socket arriving as tens of degrees of knee. A body has mass and legs
## have a rate; this is the rate, quoted against the animal's own step.
const CARRY_RATE: float = 2.5

## Least the body may sag toward, as a share of the height its stance asks for. A
## creature whose feet have all fallen behind it is crouching, not collapsing.
const SUPPORT_FLOOR: float = 0.45

## Working envelope a limb keeps once there is no longer any ground under it.
## Nothing is holding a foot out in mid-air, so it comes in under the body — a tuck
## rather than a fold, because the leg is still attached. Feet do not plant, do not
## land and are not stepped while it applies.
const TUCK_REACH: float = 0.62
const TUCK_RESPONSE: float = 7.0

## What a failing limb does, and none of these names a behaviour. A limb with less
## muscle answering reaches less far and swings slower; its diagonal partner does
## not; and the gait's own distance trigger turns that asymmetry into a
## short-long-short rhythm on its own. Both are 1.0 on an intact animal — the
## census reads exactly one — which is the guarantee that a sound creature walks as
## though this were not here.
const STRIDE_FLOOR: float = 0.34
const SWING_SLOWEST: float = 2.1
## Below this much muscle a limb no longer initiates steps at all. It still exists,
## is still solved and is still dragged; it is only never asked.
const CONTROL_MIN: float = 0.12

## How much of a new interval is believed at once, and the longest gap between two
## lifts of the same limb that still counts as a cycle rather than the animal having
## stopped and started again.
const CYCLE_BLEND: float = 0.5
const CYCLE_MAX: float = 4.0
## Weight given to the pattern against sheer overdue-ness when the two disagree.
## The pattern has to win most contests or it is not a pattern; it may never win all
## of them or a limb held off the beat by an obstacle would be towed forever.
const BEAT_AUTHORITY: float = 2.4
## Past this much of a cycle since anything last stepped, the beat is stale and the
## body is simply standing.
const BEAT_STALE: float = 2.0

## Corrections under this many pixels are not applied by the envelope clamp. Far
## below anything visible, far above the resting chain's micro-jitter: a planted
## foot left exactly on the boundary would otherwise follow every micron of it
## forever instead of staying nailed to the world.
const ENVELOPE_SLOP: float = 0.05

## How fast a socket's own velocity is smoothed, and how its share of the body's
## wave is told apart from the animal simply going somewhere.
const SOCKET_SMOOTH: float = 9.0
const SWAY_LEAK: float = 5.0
const SWAY_FADE: float = 0.6


## One foot and everything about the step it is in the middle of. The limb's bones
## are the armature's and its flesh is the census's; what lives here is the gait
## state — where this foot is nailed, where it would like to be, and how far
## through a step it is.
class Foot extends RefCounted:
	var key: StringName
	var chain: Armature.Chain
	var fore: bool = true
	var side: float = 1.0

	# --- what the anatomy says, cached once a tick -------------------------
	## The three bones, at their true length.
	var bone: float = 1.0
	var stand: float = 0.78
	var lock: float = 0.94
	var fold: float = 0.30
	var swing: float = 1.08
	var push: float = 0.15
	## How extended this limb stands *this* tick: `stand`, less however much of its
	## own fold is being spent on getting lower — or more, when something is pushing
	## the joint the other way. The crouch and the push-off, and nothing else about
	## either is written down anywhere.
	var working: float = 0.78
	var foot_size: float = 2.0
	## Its own pendulum period at a standstill.
	var swing_base: float = 0.25
	## How much of this limb's muscle is still answering, and how much of the joint
	## below the socket is. Both 1.0 on an intact animal.
	var drive: float = 1.0
	var flex: float = 1.0
	## Whether this limb is one of the ones the animal is standing on.
	var bearing: bool = true

	# --- where the socket is and what it is doing --------------------------
	var socket: Vector2 = Vector2.ZERO
	var fwd: Vector2 = Vector2.RIGHT
	var perp: Vector2 = Vector2.UP
	## The height this limb is holding its own corner of the body at.
	var corner: float = 0.0
	var socket_vel: Vector2 = Vector2.ZERO
	var socket_speed: float = 0.0
	var travel: Vector2 = Vector2.RIGHT
	var pace: float = 0.0
	## How far this socket is carried to either side of the line the animal walks
	## along by the body's own undulation. Measured rather than predicted: the
	## amplitude depends on where along the back the socket sits, on the wave, and —
	## by much the largest term — on the socket being held out on the flank of a body
	## that is rotating underneath it.
	var sway: float = 0.0
	var _sway_mean: float = 0.0
	var _prev_socket: Vector2 = Vector2.ZERO
	var _tracked: bool = false

	# --- the stance it is placed in ----------------------------------------
	var rest_lat: float = 0.0
	var rest_fore: float = 0.0
	var rest_dir: Vector2 = Vector2.UP
	## Radius of the disc on the ground the foot may be set down inside, already the
	## leg's own reach seen through the height it is holding the body at.
	var plan_limit: float = 1.0
	## Half the fore-and-aft excursion available to it, from `rest_fore`.
	var sweep_limit: float = 1.0
	## ...and the width that travel was measured against, so the placement cannot
	## exceed it. One disc, spent once.
	var lat_limit: float = 1.0
	var inboard_limit: float = 0.0
	## How high this limb holds its socket with its foot at rest — the height it
	## *wants*, as against `corner`, which is where the feet have actually left it.
	var rest_height: float = 0.0

	# --- and where it actually is ------------------------------------------
	var planted: Vector2 = Vector2.ZERO
	var ideal: Vector2 = Vector2.ZERO
	var ground: Vector2 = Vector2.ZERO
	var error: float = 0.0
	var stride: float = 1.0
	## Height of the foot, and of the surface it is standing on. They differ only
	## during a step: the foot is lifted *off* one surface and set down on another,
	## so an arc runs between the two with the clearance added on top.
	var foot_height: float = 0.0
	var surface: float = 0.0
	var foothold: float = INF
	## How far this foot has rolled forward onto its toe — where it sits in its own
	## fore-and-aft travel, and nothing else, so it comes round once per stance phase
	## because that is what a stance phase is.
	var toe: float = 0.0

	var stepping: bool = false
	var step_t: float = 0.0
	var step_duration: float = 0.25
	var step_from: Vector2 = Vector2.ZERO
	var step_to: Vector2 = Vector2.ZERO
	var step_from_surface: float = 0.0
	var step_to_surface: float = 0.0
	var step_index: int = 0
	## When this limb last left the ground on the gait's own clock, and how long it
	## has been taking to come round again. Measured rather than predicted: the
	## pattern places this beat against the last one that really happened.
	var last_lift: float = -1.0
	var cycle: float = -1.0
	var initialised: bool = false

	## The foot's offset from the socket in the socket's own frame: x outward on this
	## limb's side, y toward the head. Working here is what makes every limit mean the
	## same thing on both sides of the body and at any heading.
	func local(v: Vector2) -> Vector2:
		return Vector2(v.dot(perp * side), v.dot(fwd))

	func rest_point() -> Vector2:
		return socket + perp * (side * rest_lat) + fwd * rest_fore

	## How far the ankle is lifted off the ground by the foot rolling forward onto
	## its toe. The last joint in the chain and the only one a column has: a leg held
	## near vertical has no sinking to lengthen its stride with and no knee flexion to
	## push out of. What is left is the foot.
	func toe_rise() -> float:
		return foot_size * push * toe * flex

	## Highest this limb could hold its socket with its foot where it is planted, if
	## it were extended to `reach` of itself. Pythagoras, measured from the surface
	## the foot is standing on rather than the world's floor — a leg does not know
	## what is under its foot, it knows how far it reaches from it.
	func support_height(reach: float) -> float:
		var span: float = bone * reach
		var out: float = planted.distance_to(socket)
		return surface + toe_rise() + sqrt(maxf(span * span - out * out, 0.0))

	## The same with the foot exactly where it is right now — planted or part way
	## through a step. A limb in the air holds nothing up, but it is still attached,
	## and the body may not ride higher than the leg can reach down to it.
	func carry_ceiling(reach: float) -> float:
		var span: float = bone * reach
		var out: float = ground.distance_to(socket)
		return foot_height + sqrt(maxf(span * span - out * out, 0.0))

	## How high the foot of a limb standing on nothing hangs: from its own socket by
	## whatever of itself is not drawn up. Never below the surface, because a leg
	## cannot hang through the ground.
	func hang_height(share: float) -> float:
		var span: float = bone * clampf(share, fold, 1.0)
		var out: float = planted.distance_to(socket)
		return maxf(corner - sqrt(maxf(span * span - out * out, 0.0)), surface)

	## Projects a target into the region this limb can physically stand in: never
	## further inboard than its own socket allows, inside the fore-and-aft excursion
	## it swings through, and inside the annulus the leg can reach at all — measured
	## through the air rather than across the floor, because a foot directly beneath a
	## high shoulder has no plan offset and is still most of a leg away from it.
	##
	## Returns the target untouched when it is already legal, and when the projection
	## would move it by less than ENVELOPE_SLOP.
	func clamp_to_envelope(target: Vector2, fan: float = -1.0) -> Vector2:
		var here: Vector2 = local(target - socket)
		var hi: float = maxf(plan_limit, 0.001)
		# The joint's own fan when one is passed, and it is an arc of the *limb* about
		# its socket rather than of the plan-view disc — the two are the same on a
		# sprawled animal and wildly different on a columnar one.
		var fore_limit: float = sweep_limit if fan < 0.0 \
			else maxf(bone * stand * sin(minf(fan, PI * 0.5)), 0.001)
		# Outward only while this is a question about where to *put* a foot. Asked
		# where a foot may legally be, the joint has no such limit and neither has
		# this: a foot shoved wide by something it met is somewhere the animal can
		# perfectly well stand.
		var lat: float = maxf(here.x, -inboard_limit)
		if fan < 0.0:
			lat = minf(lat, lat_limit)
		var along: float = clampf(here.y, rest_fore - fore_limit, rest_fore + fore_limit)
		var drop: float = corner - foot_height
		var near: float = _flat_span(bone * fold, drop)
		var out := Vector2(lat, along)
		var r: float = out.length()
		if r > hi:
			out *= hi / r
		elif r < near:
			out = (Vector2(rest_lat, rest_fore).normalized() if r < 0.000001
				else out / r) * near
		var world: Vector2 = socket + perp * (side * out.x) + fwd * out.y
		return target if world.distance_squared_to(target) \
			<= ENVELOPE_SLOP * ENVELOPE_SLOP else world

	## What a span of the limb measures across the floor once the vertical gap has
	## been taken out of it.
	static func _flat_span(through: float, drop: float) -> float:
		return sqrt(maxf(through * through - drop * drop, 0.0))

	## How fast this socket is actually travelling, and how much of that is the body
	## waving rather than the animal going anywhere. `origin` is a point carried by
	## the body that does not itself undulate — the head — against which the wave can
	## be told apart from travel.
	func track(pos: Vector2, delta: float, fallback: Vector2, origin: Vector2) -> void:
		if delta <= 0.0 or not _tracked:
			_prev_socket = pos
			_tracked = true
			socket_vel = Vector2.ZERO
			socket_speed = 0.0
			travel = fallback
			_sway_mean = (pos - origin).dot(Vector2(-fallback.y, fallback.x))
			return
		var instant: Vector2 = (pos - _prev_socket) / delta
		_prev_socket = pos
		socket_vel = socket_vel.lerp(instant, 1.0 - exp(-SOCKET_SMOOTH * delta))
		socket_speed = socket_vel.length()
		# A body translating and turning as one piece holds its offset from the head
		# exactly, whatever it is doing, so what is left once the slow mean is taken
		# out is the wave and nothing else. The peak only fades while the animal is
		# moving: a creature that has stopped keeps the stance its walking left it in,
		# because a foot moved while nothing is happening is a foot that crept.
		var lateral: float = (pos - origin).dot(Vector2(-fallback.y, fallback.x))
		_sway_mean = lerpf(_sway_mean, lateral, 1.0 - exp(-SWAY_LEAK * delta))
		var fade: float = SWAY_FADE if socket_speed > 1.0 else 0.0
		sway = maxf(absf(lateral - _sway_mean), sway * exp(-fade * delta))
		travel = socket_vel / socket_speed if socket_speed > 1.0 else fallback


var feet: Array[Foot] = []
var loco: Locomotor
var cadence: Cadence = Cadence.new()
var carriage: Carriage
var spec: BodySpec
## World-space contacts completed during the most recent update. Motion state
## rather than audio: the creature announces the landing and the world decides
## what, if anything, it is worth.
var landed: PackedVector2Array = PackedVector2Array()

# --- what the legs are currently holding the body at --------------------------

## Height the shoulders and the hips are actually being held at, and the middle of
## the back between them. Two numbers because they are held up by two different
## pairs of legs — an animal whose arms are shorter than its legs stands nose-down
## without anything saying so.
var shoulder_height: float = 0.0
var hip_height: float = 0.0
var support: float = 0.0
## Whether the three above are a measurement yet. Until the first tick has placed
## four feet nothing may read them: a body with no gait solved has no feet to be
## standing on and has to fall back on its stance.
var measured: bool = false

## How fast these legs can actually carry this body, px/s, and the stride that
## answer is priced off. The one reading here the *body* consumes rather than the
## picture: the stride is whatever this tick's geometry left the shortest-striding
## bearing limb, and the cycle is the longest swing among the legs doing the
## carrying, because a body goes at the pace of its slowest leg.
var leg_speed: float = 0.0
## ...and the same for a body turning on the spot, which is slower: a standing turn
## is walked one foot at a time, because `Cadence.caution` is at its highest exactly
## when nothing is travelling.
var pivot_speed: float = 0.0
var stride_shared: float = 0.0

## How steeply the body is tipped, nose to tail and flank to flank: world height
## gained per world pixel travelled along the animal, in its own frame. A slope
## rather than a difference, because a difference is meaningless without knowing
## what it is spread over.
var pitch: float = 0.0
var roll: float = 0.0
## How far the two ends have converged: +1 is a back folded right up with the hind
## feet swung forward under the shoulders, -1 one stretched out at full extension.
## Under any alternating gait the limbs of a pair are half a cycle apart and their
## offsets cancel, so this stays at nothing however hard the animal is working;
## under a bound or a gallop the pair moves together and it swings across its whole
## range twice a stride. Nothing had to detect a gallop to make the spine flex.
var gather: float = 0.0

## How completely the body can throw itself — handed in by whatever owns the leap,
## because whether an asymmetric gait is available at all is a question about
## joints, muscle and elastic tissue rather than about anything this file measures.
var _launch: float = 0.0
var _drive: float = 0.0
var _beat_key: StringName = &""
var _beat_age: float = 0.0
var _clock: float = 0.0


## Builds the four feet against the armature's limb chains. Order matters only as a
## last tie-breaker — two feet exactly as overdue as each other and exactly as close
## to their own beat are separated by this and nothing else — so they are
## interleaved rather than listed by girdle.
func setup(armature: Armature) -> void:
	feet.clear()
	landed.clear()
	for key: StringName in [Cadence.FL, Cadence.HR, Cadence.FR, Cadence.HL]:
		var chain: Armature.Chain = armature.chain(key)
		if chain == null:
			continue
		var foot := Foot.new()
		foot.key = key
		foot.chain = chain
		foot.fore = key in [Cadence.FL, Cadence.FR]
		foot.side = chain.side
		feet.append(foot)


func set_launch(value: float) -> void:
	_launch = clampf(value, 0.0, 1.0)


func of(key: StringName) -> Foot:
	for foot in feet:
		if foot.key == key:
			return foot
	return null


## One tick of the whole gait.
##
## `move_dir` is the way the body is heading and `speed_norm` how much of its own
## cruise it is doing. `surface_query` is what is under a foot — handed a plan
## position, a foot radius and the highest that foot could be put down, it answers
## with the height there and how much room a foot of that size has on it; left out,
## the floor is at zero everywhere. `load` is what each girdle's joints are being
## asked for this tick (positive folds toward a crouch, negative extends toward a
## push) and `drive` how quickly whatever is asking is moving them, in response per
## second — both zero on a walking animal, which is why nothing below behaves
## differently for the existence of the jump.
func update(delta: float, armature: Armature, p_loco: Locomotor,
		p_carriage: Carriage, p_spec: BodySpec, corpus: Corpus,
		move_dir: Vector2, speed_norm: float, airborne: bool = false,
		surface_query: Callable = Callable(), load: Vector2 = Vector2.ZERO,
		drive: float = 0.0) -> void:
	landed.clear()
	loco = p_loco
	carriage = p_carriage
	spec = p_spec
	_drive = maxf(drive, 0.0)
	if feet.is_empty() or loco == null or carriage == null:
		return

	# What full pace means for this body: the species asks for a speed and the legs
	# answer with one, and it is the lower of the two a socket's speed is quoted
	# against. Measured against the request alone, a creature its legs are holding
	# back would never read as going flat out and every reading downstream of pace
	# would sit permanently at half throttle.
	var top_speed: float = maxf(spec.move_speed, 1.0)
	if leg_speed > 0.0:
		top_speed = maxf(minf(top_speed, leg_speed), 1.0)

	# What the stance asks for, before the feet get a say — per girdle, because the
	# two ends of an animal are not the same limb. A cat carries a straight strut in
	# front and a folded spring behind, so its shoulders and hips are held up by legs
	# standing at quite different fractions of themselves, and the fact that they
	# arrive at nearly the same height is a consequence of the bones being different
	# lengths rather than of anything levelling the body.
	var wants := Vector2(
		_rest_clearance(true, _stance_extension(load.x, true)),
		_rest_clearance(false, _stance_extension(load.y, false)))
	if not measured:
		shoulder_height = wants.x
		hip_height = wants.y
		support = (wants.x + wants.y) * 0.5
		for foot in feet:
			foot.corner = wants.x if foot.fore else wants.y

	var head: Vector2 = armature.plan(armature.head_index())

	# --- 1. retarget: recompute each foot's ideal position ------------------
	for foot in feet:
		_read_anatomy(foot, corpus, load)
		_read_socket(foot, armature)
		if airborne or not foot.bearing:
			# Nothing to stand on. The limb keeps every capability it had — this is
			# not damage — it simply loses the ground those capabilities were being
			# spent against, so its envelope draws in and it stops being placed.
			# Unless it is being put out for something: a limb asked to extend is a
			# limb reaching, and it reaches out of the same tuck rather than round it,
			# so a body coming down out of an arc has its legs down before it arrives.
			var reaching: float = clampf(-(load.x if foot.fore else load.y), 0.0, 1.0)
			foot.plan_limit *= lerpf(TUCK_REACH, 1.0, reaching)

		foot.track(foot.socket, delta, move_dir, head)
		foot.pace = maxf(speed_norm, clampf(foot.socket_speed / top_speed, 0.0, 1.0))

		# How far from directly beneath its socket the foot may be put down: the
		# triangle rather than a flat projection of the leg, which is what an upright
		# animal's stride is made of. Quoted against the height this animal *stands*
		# at rather than where it happens to be — measuring it off the current sag
		# closes a loop with nothing damping it, and a creature that dipped once would
		# settle into a permanent splay-legged crouch.
		# ...and how much of the gap the foot's own toe takes out of it over the
		# stance. Half the peak, because the toe rolls up progressively and the disc
		# it is sizing is symmetrical while the push-off is not.
		var rise: float = foot.foot_size * foot.push * 0.5 * foot.flex
		var lean: float = cos(carriage.tilt) * spec.stance_width
		var steady: float = sqrt(maxf(pow(foot.bone * foot.working, 2.0)
			- _steady_stance(foot, lean), 0.0))
		foot.plan_limit = loco.walking_reach(foot.bone, steady, _max_reach(foot),
			foot.fore, rise)

		# Where this foot rests: the circle the leg reaches across at the stance it
		# stands in, and how much of that the swing plane has left out to the side.
		# Narrowed, if it has to be, to leave the stride somewhere to happen — the two
		# are spent out of one disc, and a stance that uses the whole of it is an
		# animal with no stride whose feet are dragged by its own wave.
		_set_stance(foot, minf(
			carriage.plan_reach(foot.bone * foot.working),
			loco.stance_limit(foot.plan_limit, foot.sway) / maxf(lean, 0.0001)), lean)
		foot.inboard_limit = spec.girdle_offset * carriage.adduction()

		# The height this limb is actually holding its end of the body at — the stance
		# it ended up in, so it does move with the wave. It is the levelling term
		# rather than the envelope: where the body wants to be rather than where its
		# foot may go, and the two want different answers to the same question.
		foot.rest_height = sqrt(maxf(pow(foot.bone * foot.working, 2.0)
			- Vector2(foot.rest_lat, foot.rest_fore).length_squared(), 0.0))

		# How much of the disc the fore-and-aft swing may use. Against where the sway
		# puts the foot rather than where it rests, because the boundary is met at the
		# worst instant of the wave and not at the average one. Nothing is added here
		# for what the spine contributes to a stride: the back moves the *socket*, and
		# a foot whose socket has been carried forward has covered more ground without
		# reaching further from it — it arrives through `track`, and written in here as
		# well it would be the same ground counted twice.
		foot.lat_limit = absf(foot.rest_lat) + foot.sway
		foot.sweep_limit = maxf(loco.excursion(foot.bone, steady, foot.lat_limit,
			_max_reach(foot), _swing_fan(foot), foot.fore, rise), 0.001)
		# Stride is that travel and nothing else. Not a species number capped by the
		# envelope afterwards: a stride longer than the travel a limb has is not a long
		# stride, it is no stride at all — the clamp skids the planted foot along the
		# boundary, the trigger is never reached, and the leg is towed for as long as
		# the creature keeps walking.
		foot.stride = loco.stride(foot.sweep_limit, spec.foot_lead)

	# --- 1a. one animal, one stride ----------------------------------------
	_share_stride()

	for foot in feet:
		# Where this foot would like to be: its rest stance, thrown ahead along the
		# way its own socket is travelling, and clamped into the envelope — an ideal
		# outside it is not an ideal, it is a point the foot is measured against and
		# can never arrive at, so the limb reads as permanently overdue.
		foot.ideal = foot.clamp_to_envelope(foot.rest_point()
			+ foot.travel * (spec.foot_lead * foot.stride * foot.pace))

		if not foot.initialised:
			# First tick: plant the feet where they already want to be, so the creature
			# does not start by taking four simultaneous steps.
			foot.planted = foot.ideal
			foot.ground = foot.ideal
			foot.initialised = true

		# With nothing underneath it a foot has nowhere to be nailed to, so it is
		# carried with the socket instead of being left behind by it. This is the whole
		# of the tuck: the error never grows, so nothing asks this limb to step, and a
		# leg that is not stepping is a leg being held. The same line covers a forelimb
		# that never reaches the ground — there is no difference between an arm with no
		# floor under it because the animal jumped and one with no floor under it
		# because the animal stands on two legs.
		if airborne or not foot.bearing:
			foot.stepping = false
			foot.planted = foot.planted.lerp(foot.ideal, 1.0 - exp(-TUCK_RESPONSE * delta))

		# A planted foot is standing on something, and what it is standing on does not
		# change under it from one sixtieth of a second to the next. The query answers
		# about a *place*, and the place a planted foot occupies moves — dragged along
		# its envelope, shoved by contacts, its own reach ceiling rising and falling
		# with the walking bob — so taking a new answer whole teleports the foot to it.
		# It settles instead at the speed that foot moves vertically in its own step,
		# which is the fastest this animal moves that foot at all.
		var under: Vector2 = _surface_under(foot, foot.planted, surface_query)
		foot.foothold = under.y
		if foot.stepping:
			foot.surface = under.x
		else:
			foot.surface = move_toward(foot.surface, under.x, _foot_speed(foot) * delta)
		_read_toe(foot)
		foot.foot_height = _hold(foot, airborne)
		# Against what the joint can do rather than against the stride: `sweep_limit`
		# is where the gait may choose to put a foot down, and where a foot may legally
		# *be* is the joint's own fan, which is wider.
		foot.planted = foot.clamp_to_envelope(foot.planted, _swing_fan(foot))
		foot.error = foot.planted.distance_to(foot.ideal)

	# --- 1b. what pattern are these four feet in? --------------------------
	# Here rather than higher up because every input it takes is something the loop
	# above has just measured. The hip the Froude number is quoted against is the
	# height this animal *stands* at, not where it happens to be held this instant:
	# the pendulum an animal vaults over is its leg, and a body crouched onto folded
	# joints has not grown a shorter one. Measuring it as though it had inflates the
	# regime exactly when the animal is being most careful.
	_solve_pattern(delta, armature, _rest_clearance(false, carriage.hind.stand))

	# --- 2. advance any step already in flight -----------------------------
	for foot in feet:
		if not foot.stepping:
			foot.ground = foot.planted
			foot.foot_height = _hold(foot, airborne)
			continue

		# Keep re-aiming the landing spot at the (moving) ideal while airborne, or
		# feet land in stale positions during a turn. The aim is where the ideal will
		# be when the foot touches down, not where it is now.
		var remaining: float = (1.0 - foot.step_t) * foot.step_duration
		var retarget: float = 1.0 - exp(-STEP_RETARGET_RESPONSE * delta)
		var aim: Vector2 = foot.clamp_to_envelope(_landing_spot(foot, remaining))
		# ...and then asked whether there is anywhere to stand where it has ended up.
		# After the ease rather than before it, because the ease decides where the foot
		# is actually going: searching from the aim and easing toward the answer lands
		# it between the two, which on broken ground is reliably the edge between them.
		foot.step_to = _footing(foot, foot.step_to.lerp(aim, retarget), surface_query)
		var arriving: Vector2 = _surface_under(foot, foot.step_to, surface_query)
		foot.step_to_surface = arriving.x

		foot.step_t += delta / maxf(foot.step_duration, 0.001)
		if foot.step_t >= 1.0:
			foot.step_t = 1.0
			foot.stepping = false
			foot.planted = foot.step_to
			foot.surface = foot.step_to_surface
			foot.foothold = arriving.y
			landed.append(foot.planted)

		# Smoothstep along the ground path with a sine arc for the height — a half
		# period is exactly one hop.
		var eased: float = smoothstep(0.0, 1.0, foot.step_t)
		foot.ground = foot.step_from.lerp(foot.step_to, eased)
		# A swing is not a straight tow between two footprints: the joint folds as the
		# limb comes through, and a folded limb's foot is carried in under its own
		# socket. How far in is how much travel the joint actually has between standing
		# and folded — a cat's shank tucks up under its hip mid-swing, a columnar leg
		# pendulums through nearly straight, and neither was told to.
		var fold_room: float = clampf((foot.stand - foot.fold)
			/ maxf(foot.stand, 0.0001), 0.0, 1.0)
		foot.ground = foot.ground.lerp(foot.socket,
			SWING_TUCK * fold_room * sin(foot.step_t * PI) * foot.flex)
		# Two terms, and only the second is the step: the first is the ramp from the
		# surface the foot left to the one it is arriving at, which is what makes a
		# step onto a ledge a step *up* rather than one that ends underground.
		# Clearance is the joint's own doing, so it is priced off what is still working
		# the knee rather than off the limb as a whole.
		foot.foot_height = lerpf(foot.step_from_surface, foot.step_to_surface, eased) \
			+ sin(foot.step_t * PI) * _step_clearance(foot) \
			* (0.45 + 0.55 * foot.pace) * foot.flex

	# --- 3. decide which feet pick up --------------------------------------
	# A body with nothing under it never picks a foot up, because a step is a push
	# against the ground and there is none.
	if airborne:
		_carry_body(delta, wants)
		_place(armature)
		return

	var aloft: int = 0
	var candidates: Array[Foot] = []
	for foot in feet:
		if foot.stepping:
			aloft += 1
			continue
		# Recompute against this tick's plant: step 2 may have just landed this foot,
		# and deciding on the pre-landing error would re-fire it instantly.
		foot.error = foot.planted.distance_to(foot.ideal)
		if not _can_step(foot):
			continue
		if foot.error >= foot.stride:
			candidates.append(foot)

	# Best fit to the beat first, with overdue-ness as the tie-breaker rather than
	# the rule. This is where a footfall pattern becomes an order: overdue-ness alone
	# says only that a foot which has drifted a long way should go before one that
	# has not, so what comes out is whatever the geometry happened to produce — which
	# on every build is the same near-trot. Overdue-ness is quoted against each
	# limb's own stride rather than in pixels, because an arm is shorter than a leg
	# and is due at a smaller drift.
	var elapsed: float = _beat_phase()
	candidates.sort_custom(func(a: Foot, b: Foot) -> bool:
		return _bid(a, elapsed) > _bid(b, elapsed))

	var limit: int = cadence.lift_limit
	var coupling: float = clampf(spec.beat_coupling * carriage.coupling_gain, 0.0, 1.0)
	for foot in candidates:
		if foot.stepping:
			continue
		if aloft >= limit:
			break
		# Never lift a foot while one belonging to a *different* beat is still in the
		# air. That is what keeps the animal standing, and it is the same rule a
		# hard-wired diagonal gate used to be — only which limbs are opposed is now
		# read off the pattern instead of off which corner of the body a leg is on.
		if _beat_blocked(foot):
			continue

		_start_step(foot, surface_query)
		_beat_key = foot.key
		_beat_age = 0.0
		aloft += 1

		# ...and pull anything that shares this beat onto it, if it is anywhere near
		# due. This is the difference between a readable gait and four legs doing
		# their own thing, and it is what makes a pair land *together*: a bound, a
		# pace and a pronk are all this line firing on limbs the pattern has put in
		# phase.
		for other in feet:
			if other == foot or other.stepping:
				continue
			if aloft >= limit:
				break
			if not cadence.shares_beat(foot.key, other.key):
				continue
			if not _can_step(other):
				continue
			if other.error > other.stride * (1.0 - coupling):
				_start_step(other, surface_query)
				aloft += 1

	# --- 4. let the body down onto the feet that were just placed ----------
	# Before the limbs are placed rather than after, and the ordering is the whole
	# difference between a leg that reaches and one that skids: a foot is put down
	# out at the reach the leg has once the body has come down over it, so solving
	# the chain first leaves the shoulder up where it was last tick, the leg a
	# fraction too short for its own foot, and the envelope dragging the foot back in.
	_carry_body(delta, wants)

	# --- 5. hand the armature its feet -------------------------------------
	_place(armature)


# ------------------------------------------------------------ the anatomy ----

## Caches what this limb's girdle can do with itself, so the gait, the placement
## and the height solve read one agreed set of numbers rather than re-deriving
## them. Every capability is 1.0 on an intact animal, which is the guarantee that a
## sound creature walks exactly as it would if none of this were here.
func _read_anatomy(foot: Foot, corpus: Corpus, load: Vector2) -> void:
	var joint: Carriage.Joint = carriage.of(foot.fore)
	foot.bone = spec.limb_length(foot.fore)
	foot.stand = joint.stand
	foot.lock = joint.lock
	foot.fold = joint.fold
	foot.swing = joint.swing
	foot.push = joint.push
	foot.working = _stance_extension(load.x if foot.fore else load.y, foot.fore)
	foot.foot_size = maxf(foot.bone * 0.10, 3.0)
	# Through this girdle's own lever: a limb whose tendons insert close to the
	# joint is thrown through its swing sooner, and one geared for force pays for
	# its push in exactly this line.
	foot.swing_base = loco.swing_time(foot.bone, joint.gear)
	# What the muscle behind this limb can put across its socket, and what is left
	# working the joint below it. Off the census, so a hip chewed hollow shortens
	# that leg's stride and slows its swing the tick the bite lands, and neither is
	# a limp anybody decided on.
	var soundness: float = corpus.soundness(foot.key) if corpus != null else 1.0
	foot.drive = minf(soundness,
		loco.girdle_drive.x if foot.fore else loco.girdle_drive.y)
	foot.flex = soundness
	# Whether this limb is one of the ones the animal is standing on. False on a
	# forelimb too short to reach the ground the hips are holding the body over —
	# and it is not an injury: the leg is sound, it is simply carried.
	foot.bearing = not foot.fore or loco.forelimbs_bear


## Reads where the armature is currently holding this socket. The frame is the
## girdle station's own, so every limit downstream means the same thing at any
## heading, and the height is the corner *this* leg is holding rather than its
## girdle's mean — a shoulder on the side the animal has its weight over is
## genuinely carried higher than the one swinging through, which is what a roll is.
func _read_socket(foot: Foot, armature: Armature) -> void:
	var parent: int = foot.chain.parent_node
	foot.fwd = armature.fwd[parent]
	foot.perp = armature.perp[parent]
	foot.socket = armature.plan(parent) + foot.perp * (foot.side * spec.girdle_offset)


## Where this limb stands, in the socket's own frame. The stance radius is split by
## the posture: out to the side goes as much of it as the swing plane has not
## rotated away, and the fore/aft bias is spent out of what is left — so the front
## pair stands a little forward and the rear a little back without either being
## pushed off the circle its own leg reaches.
func _set_stance(foot: Foot, stance: float, lean: float) -> void:
	foot.rest_lat = stance * lean
	foot.rest_fore = sqrt(maxf(stance * stance - foot.rest_lat * foot.rest_lat, 0.0)) \
		* (loco.foot_bias.x if foot.fore else loco.foot_bias.y)
	var dir: Vector2 = foot.perp * (foot.side * foot.rest_lat) + foot.fwd * foot.rest_fore
	foot.rest_dir = dir.normalized() if dir.length_squared() > 0.000001 \
		else foot.perp * foot.side


## The square of how far this foot rests from directly beneath its socket, with the
## body's own wave taken out. The envelope is sized off this, and a height that
## breathed with the undulation would be an envelope that breathed — so the radius
## a planted foot is clamped into would move under it twice a cycle and skid it.
func _steady_stance(foot: Foot, lean: float) -> float:
	var wide: float = minf(foot.plan_limit,
		loco.stance_limit(foot.plan_limit, 0.0) / maxf(lean, 0.0001))
	var lat: float = wide * lean
	var along: float = sqrt(maxf(wide * wide - lat * lat, 0.0)) \
		* (loco.foot_bias.x if foot.fore else loco.foot_bias.y)
	return lat * lat + along * along


## How high one pair of legs holds its end of the body with its feet where they
## rest — the height that pair *wants*, and the one the envelope is sized at.
## Closed-form from the stance rather than from the solved feet, because the rest
## stance is narrowed by the room left for the stride, which is sized off this,
## which would be a loop.
func _rest_clearance(fore: bool, extension: float) -> float:
	return carriage.stance_clearance(spec.limb_length(fore), extension,
		spec.stance_width, loco.foot_bias.x if fore else loco.foot_bias.y)


## How extended the legs stand this tick: what the stance asks for, folded toward
## the tightest a limb may be drawn up by however much crouch is being spent.
## Signed, and the sign is the difference between the two things a limb does about
## its own length — positive folds toward a crouch, negative extends toward a
## push-off, which is why a take-off is visible before there is any elevation.
func _stance_extension(load: float, fore: bool) -> float:
	var joint: Carriage.Joint = carriage.of(fore)
	if load >= 0.0:
		return lerpf(joint.stand, joint.fold, clampf(load, 0.0, 1.0))
	return lerpf(joint.stand, joint.lock, clampf(-load, 0.0, 1.0))


func _max_reach(foot: Foot) -> float:
	return foot.lock


func _swing_fan(foot: Foot) -> float:
	return foot.swing


## Whether this limb can pick itself up at all: it has to have ground under it and
## enough muscle answering to be asked. A limb that fails still exists, is still
## placed and is still dragged; it is only never asked.
func _can_step(foot: Foot) -> bool:
	return foot.bearing and foot.drive >= CONTROL_MIN


# ------------------------------------------------------------- the pattern ----

## Re-derives the footfall pattern from the feet as they have just been solved.
## Everything handed over is a measurement taken this tick. The speed is the mean
## of the four sockets rather than the body's linear speed, because a creature
## pivoting on the spot has a linear speed of zero and hips going as fast as they
## ever do; the girdle gap is measured on one flank, so a body curled into a turn
## reports the shorter distance its own feet actually have to share.
func _solve_pattern(delta: float, armature: Armature, stance_hip: float) -> void:
	_clock += delta
	_beat_age += delta
	var pace: float = 0.0
	var walking: int = 0
	var fore: float = 0.0
	var rear: float = 0.0
	var lead_left: float = 0.0
	var lead_right: float = 0.0
	var fore_socket := Vector2.ZERO
	var hind_socket := Vector2.ZERO
	for foot in feet:
		pace += foot.socket_speed
		walking += 1
		if foot.fore:
			fore = maxf(fore, foot.sweep_limit)
			if foot.side < 0.0:
				fore_socket = foot.socket
		else:
			rear = maxf(rear, foot.sweep_limit)
			if foot.side < 0.0:
				hind_socket = foot.socket
			# Which way the animal is coming round, measured rather than asked for:
			# the hind socket on the outside of a turn sweeps the wider arc. Running
			# straight the two are equal and the gallop below has no lead at all,
			# which is honest — a straight-line asymmetric gait is a bound.
			if foot.side < 0.0:
				lead_left = foot.socket_speed
			else:
				lead_right = foot.socket_speed
	var speed: float = pace / maxf(float(walking), 1.0)
	var gap: float = fore_socket.distance_to(hind_socket)
	var lead: float = (lead_left - lead_right) / maxf(speed, 1.0)

	cadence.update(carriage, loco, spec,
		maxf(stance_hip if stance_hip > 0.0 else hip_height, 1.0), speed,
		Vector2(fore, rear), gap, lead, loco.forelimbs_bear, _launch, loco.tail_prop)
	_measure_gather()


## Reads how far the two ends of the animal have converged — each foot's offset
## from its own socket along the body as a share of that limb's travel, the hind
## pair's mean less the fore pair's.
func _measure_gather() -> void:
	var ends := Vector2.ZERO
	var counted := Vector2.ZERO
	for foot in feet:
		if not foot.bearing:
			continue
		var along: float = foot.local(foot.ground - foot.socket).y - foot.rest_fore
		var share: float = clampf(along / maxf(foot.sweep_limit, 0.001), -1.0, 1.0)
		if foot.fore:
			ends.x += share
			counted.x += 1.0
		else:
			ends.y += share
			counted.y += 1.0
	if counted.y <= 0.0:
		gather = 0.0
		return
	# With no forelimbs on the ground there is nothing at the front to converge
	# with, so what the hind pair alone says is the whole of it — a hop rather than
	# a bound, and a hopping body does fold, over its hips.
	var hind: float = ends.y / counted.y
	var forelimb: float = ends.x / counted.x if counted.x > 0.0 else 0.0
	gather = clampf((hind - forelimb) * 0.5, -1.0, 1.0)


## How far through a cycle it is since the last foot left the ground. Negative when
## there is no beat to measure from: sequencing a creature that stopped and started
## again off a stamp from before it stopped would be sequencing off a coincidence.
func _beat_phase() -> float:
	if _beat_key == &"":
		return -1.0
	var cycle: float = _measured_cycle()
	if cycle <= 0.0001 or _beat_age > cycle * BEAT_STALE:
		return -1.0
	return _beat_age / cycle


## How long one limb's whole cycle is actually taking, averaged over the legs that
## have done one. The observed interval rather than the predicted one: a beat has to
## be placed against the last beat that really happened.
func _measured_cycle() -> float:
	var total: float = 0.0
	var count: int = 0
	for foot in feet:
		if not foot.bearing or foot.cycle <= 0.0:
			continue
		total += foot.cycle
		count += 1
	return total / float(count) if count > 0 else _body_cycle()


## What one candidate is worth this tick: how overdue it is, less how far off its
## own beat lifting it now would be.
func _bid(foot: Foot, elapsed: float) -> float:
	var overdue: float = foot.error / maxf(foot.stride, 0.001)
	if elapsed < 0.0:
		return overdue
	return overdue - BEAT_AUTHORITY * cadence.off_beat(foot.key, _beat_key, elapsed)


## Whether a limb still in the air belongs to a different part of the cycle than
## this one — in which case this foot waits, because the two were never meant to be
## off the ground together.
func _beat_blocked(foot: Foot) -> bool:
	for other in feet:
		if other == foot or not other.stepping:
			continue
		if not cadence.may_overlap(foot.key, other.key):
			return true
	return false


# --------------------------------------------------------------- the steps ----

func _start_step(foot: Foot, surface_query: Callable) -> void:
	# How long this limb has taken to come round to itself again. Every lift is a
	# reading, whether the limb won the contest or was pulled onto somebody else's
	# beat, because it is this limb's own cycle either way.
	if foot.last_lift >= 0.0:
		var span: float = _clock - foot.last_lift
		if span > 0.0 and span < CYCLE_MAX:
			foot.cycle = span if foot.cycle <= 0.0 \
				else lerpf(foot.cycle, span, CYCLE_BLEND)
	foot.last_lift = _clock
	foot.step_from = foot.planted
	foot.step_from_surface = foot.surface
	foot.step_index += 1
	foot.step_duration = _step_duration(foot)
	# Where the stride says, and then somewhere it can actually stand. On level
	# ground the second is the first and this is one extra query.
	foot.step_to = _footing(foot, foot.clamp_to_envelope(
		_landing_spot(foot, foot.step_duration)), surface_query)
	foot.step_to_surface = _surface_under(foot, foot.step_to, surface_query).x
	foot.step_t = 0.0
	foot.stepping = true


## How long this limb's swing phase should last. Three terms: the limb's own
## pendulum shortened at pace, the duty factor as a deadline, and a weak limb
## swinging *slower*, which is the second half of a limp. The pendulum is a floor as
## well as a target, and that one change is most of what stopped the creatures
## reading as machinery — a deadline is a statement about the gait's arithmetic, a
## pendulum is a statement about the leg, and when the two disagreed the deadline
## used to win all the way down to a flat forty-five milliseconds.
func _step_duration(foot: Foot) -> float:
	var labour: float = lerpf(SWING_SLOWEST, 1.0, foot.drive)
	var base: float = loco.hurried_swing(foot.swing_base, foot.pace) * labour
	var budget: float = loco.swing_budget(foot.stride / maxf(foot.socket_speed, 1.0),
		float(cadence.lift_limit) / float(maxi(loco.bearing_limbs, 1)), foot.pace)
	# The deadline may still hurry a step — a socket racing round the outside of a
	# turn has a short cycle at any speed — but only as far as muscle can hurry a
	# limb. Below that there is no step being taken, only a leg being redrawn.
	return clampf(minf(base, budget),
		loco.hurried_swing(foot.swing_base, 1.0) * labour,
		foot.swing_base * labour)


## Where a foot should touch down if it lifts now and lands in `flight` seconds.
## Aiming at the present ideal is what makes hind feet look unplanted: by the time
## the foot lands the body has moved on, so it arrives already behind and is dragged
## the whole of its stance. The prediction is capped because `ideal` already
## contains the authored lead.
func _landing_spot(foot: Foot, flight: float) -> Vector2:
	var prediction: Vector2 = (foot.socket_vel * flight).limit_length(
		foot.stride * LANDING_PREDICTION_STRIDES)
	return foot.ideal + prediction


## How high a foot picks up at the top of a step — a real height in world pixels,
## because it is the height something else has to be shorter than to pass
## underneath.
func _step_clearance(foot: Foot) -> float:
	return loco.lift(foot.corner, foot.bone) * carriage.step_height_gain


## How fast this limb moves its own foot vertically: the height one of its steps
## lifts the foot over how long that step takes. The fastest anything moves this
## foot, and therefore the ceiling on every other way it is allowed to change height.
func _foot_speed(foot: Foot) -> float:
	return _step_clearance(foot) / maxf(_step_duration(foot), 0.001)


## How high a foot that is not taking a step is being held: on the surface it is
## standing on, or — for a limb that is not standing on anything — hung from its own
## socket. Without the second a vestigial arm is solved to a floor a whole leg below
## its shoulder and drawn as a spike.
func _hold(foot: Foot, airborne: bool) -> float:
	if not airborne and foot.bearing:
		return foot.surface + foot.toe_rise()
	return foot.hang_height(TUCK_REACH)


## How far this foot has rolled forward onto its toe: where it sits in its own
## fore-and-aft travel, and nothing else — so it comes round once per stance phase
## because that is what a stance phase is. Zero on anything the animal is not
## standing on, because a push needs something to push against.
func _read_toe(foot: Foot) -> void:
	if foot.stepping or not foot.bearing or foot.push <= 0.0:
		foot.toe = 0.0
		return
	var behind: float = foot.rest_fore - foot.local(foot.planted - foot.socket).y
	foot.toe = clampf(behind / maxf(foot.sweep_limit, 0.001), 0.0, 1.0)


## Settles what one step of this animal is worth, for all four legs at once.
##
## A body is one object: over one cycle every foot returns to the same place
## relative to the shoulder it hangs from, and in between the whole animal has moved
## forward by exactly one stride — so the four legs have one step length between
## them, set by the leg with the least to spend. Without it the two ends of an
## animal run at two cadences and the footfall pattern, which is a statement about
## *phase*, has no fixed cycle to be a phase of.
##
## What is *not* shared is the two per-limb terms applied afterwards: a limb on the
## outside of a turn genuinely covers more ground, and one with no force left in it
## genuinely reaches less far.
func _share_stride() -> void:
	var shared: float = INF
	var sweep: float = INF
	var swing: float = 0.0
	for foot in feet:
		if not foot.bearing:
			continue
		shared = minf(shared, foot.stride)
		sweep = minf(sweep, foot.sweep_limit)
		# The longest swing among the legs doing the carrying, for the same reason the
		# stride is the shortest: a body travels at the pace of the leg that holds it
		# up latest, not at the average of four.
		swing = maxf(swing, foot.swing_base)
	if is_inf(shared):
		return
	stride_shared = maxf(shared, 0.001)
	if swing > 0.0 and not is_inf(sweep):
		# Against the most feet this body would ever lift rather than the number it is
		# lifting right now — an animal picks its feet up one at a time *because* it is
		# going slowly, so a ceiling priced off that would hold it at the speed which
		# made it careful and nothing could ever reach a run. And never all of them:
		# a body with every foot in the air is not walking quickly, it is airborne.
		var bearing: int = maxi(loco.bearing_limbs, 1)
		var aloft: int = mini(cadence.lift_ceiling, maxi(bearing - 1, 1))
		leg_speed = loco.leg_speed(sweep * 2.0, swing, float(aloft) / float(bearing))
		pivot_speed = loco.leg_speed(sweep * 2.0, swing, 1.0 / float(bearing))
	for foot in feet:
		foot.stride = stride_shared * (0.45 + 0.55 * foot.pace) \
			* lerpf(STRIDE_FLOOR, 1.0, foot.drive)


## How long one limb's whole step cycle currently is, averaged over the legs that
## are walking — the stride each foot has over how fast its own socket is going.
func _body_cycle() -> float:
	var total: float = 0.0
	var count: int = 0
	for foot in feet:
		if not foot.bearing:
			continue
		total += foot.stride / maxf(foot.socket_speed, 1.0)
		count += 1
	return total / maxf(float(count), 1.0)


# ---------------------------------------------------------- the body's height ----

## How high the four feet are actually holding the body, and how the body follows
## them down.
##
## Nothing here decides anything. A leg is a fixed length, so a foot set down
## further from its socket is a socket held lower — that is Pythagoras, and it is
## the only rule in this function. Everything that reads as weight comes out of it:
## the body sinks as a stride reaches its extreme and rises again as the foot comes
## back under the shoulder, which is a bob at exactly step frequency because that is
## what it is a measurement of.
func _carry_body(delta: float, wants: Vector2) -> void:
	var rear: float = _pair_support(false, wants.y)
	# A girdle with nothing under it is not held up by legs — it is held up by the
	# back, at whatever angle this animal carries its trunk, which is its own or the
	# one its weight demands, whichever is steeper.
	var front: float = _pair_support(true, wants.x) if loco.forelimbs_bear \
		else rear + sin(deg_to_rad(loco.carried_deg())) * maxf(_girdle_span(), 0.0)
	# Weight takes a moment to settle onto a leg, but a body that has just been built
	# is not settling onto anything — it is already standing there. How fast it
	# settles is quoted per step cycle rather than per second, because that is what it
	# measures: the body follows its feet at the pace its feet are moving. The floor
	# under the response is whatever has hold of the legs — a limb being driven open
	# is changing length on the timescale of whatever is driving it.
	var response: float = 1.0 - exp(-maxf(loco.settle(_body_cycle()), _drive) * delta) \
		if measured else 1.0
	var climb: float = _carry_speed() * delta if measured else INF
	measured = true
	# Eased toward what the legs offer, held to the speed a leg can raise a body at,
	# and only then cut off at what it can reach. The order is the point: a rate is a
	# statement about how the body gets there, so it applies to the easing; the
	# ceiling is a statement about where it may be at all, so nothing comes after it.
	shoulder_height = minf(_toward(shoulder_height, front, response, climb),
		_pair_ceiling(true))
	hip_height = minf(_toward(hip_height, rear, response, climb),
		_pair_ceiling(false))
	support = (shoulder_height + hip_height) * 0.5
	_carry_corners(response, climb)


## The same measurement one leg at a time, and the whole of the creature's weight
## transfer. `_pair_support` answers what a *pair* is holding its end at and takes
## whichever is doing worse, because the body cannot ride higher than the shortest
## reach underneath it; that is right for the height and it throws away the thing
## that makes a walk read as heavy — the two legs of a pair are usually holding
## their own corners at different heights, and a body held at four different heights
## is tipped. A limb in the air holds nothing, so its corner eases toward the pair's
## height rather than toward the floor.
func _carry_corners(response: float, climb: float) -> void:
	for foot in feet:
		var held: float = shoulder_height if foot.fore else hip_height
		if foot.bearing and not foot.stepping:
			# The clearance this pair asks for, measured from wherever its foot
			# currently is rather than from the floor — which on a foot rolled up onto
			# its toe is a little above it. Left off, the levelling term spends the
			# whole push-off arguing with the leg that is lifting the body.
			held = lerpf(foot.support_height(foot.working),
				foot.surface + foot.toe_rise() + foot.rest_height, loco.absorbed)
		var settled: float = _toward(foot.corner, held, response, climb)
		if foot.bearing:
			settled = minf(settled, foot.carry_ceiling(_max_reach(foot)))
		foot.corner = settled

	# The two differences, over the two lengths they are spread across. The levers
	# are the animal's own stance, so both slopes come out of the geometry rather
	# than out of a constant — a build whose feet fall close under the midline tips
	# further for the same difference in how its sides are held.
	var along: float = maxf(_girdle_span(), 1.0)
	var across: float = maxf(_track(), 1.0)
	pitch = (shoulder_height - hip_height) / along
	var left: float = 0.0
	var right: float = 0.0
	for foot in feet:
		if foot.side < 0.0:
			left += foot.corner
		else:
			right += foot.corner
	roll = (left - right) * 0.5 / across


## Eases a height toward what the legs are offering, then holds the move to what a
## leg could have made in the time available. Two claims, different in kind: the
## ease says the body follows its feet rather than snapping to them; the limit says
## there is a speed at which it can follow, and no ease expresses a speed.
static func _toward(from: float, to: float, response: float, limit: float) -> float:
	return from + clampf(lerpf(from, to, response) - from, -limit, limit)


## How fast this body may be carried up or down, px/s — read off the animal's own
## step rather than chosen. Unless something has hold of the legs, in which case it
## is not a walk and this is not the rate: a body thrown upward by its own joints
## moves at whatever is driving them.
func _carry_speed() -> float:
	if _drive > 0.0:
		return INF
	var slowest: float = INF
	for foot in feet:
		if not foot.bearing:
			continue
		slowest = minf(slowest, _foot_speed(foot))
	return INF if is_inf(slowest) else slowest * CARRY_RATE


## The height one pair of legs is holding its end of the body at: whichever of the
## two is doing worse, since the body cannot ride higher than the shortest reach
## underneath it. Each leg answers twice and the truth is between them — held at one
## length it vaults, levelling perfectly it simply stands at the height the stance
## asks for, and neither alone is a walk. `wants` is a *clearance*, so it is quoted
## against each foot's own surface rather than the world's floor: a body crouching
## on a ledge crouches toward the ledge.
func _pair_support(fore: bool, wants: float) -> float:
	var held: float = INF
	var floor_height: float = INF
	for foot in feet:
		if foot.fore != fore or foot.stepping or not foot.bearing:
			continue
		var vault: float = foot.support_height(foot.working)
		var level: float = minf(foot.surface + foot.toe_rise() + foot.rest_height,
			foot.support_height(_max_reach(foot)))
		held = minf(held, lerpf(vault, level, loco.absorbed))
		floor_height = minf(floor_height, foot.surface)
		wants = minf(wants, foot.rest_height)
	if is_inf(held):
		return wants
	return maxf(held, floor_height + wants * SUPPORT_FLOOR)


## The highest one pair could hold its end of the body with the feet where they are
## now — at the limb's outright limit rather than the reach it prefers. Not where
## the body wants to be: the line it may not be on the wrong side of.
func _pair_ceiling(fore: bool) -> float:
	var ceiling: float = INF
	for foot in feet:
		if foot.fore != fore or not foot.bearing:
			continue
		ceiling = minf(ceiling, foot.carry_ceiling(_max_reach(foot)))
	return ceiling


## Distance between the two girdles' sockets, on the ground plane.
func _girdle_span() -> float:
	var fore := Vector2.ZERO
	var rear := Vector2.ZERO
	for foot in feet:
		if foot.fore:
			fore = foot.socket
		else:
			rear = foot.socket
	return fore.distance_to(rear)


## How wide this animal is actually standing: the mean gap between the feet on one
## side and those on the other — the lever a roll turns about.
func _track() -> float:
	var left := Vector2.ZERO
	var right := Vector2.ZERO
	var counted := Vector2.ZERO
	for foot in feet:
		if not foot.bearing:
			continue
		if foot.side < 0.0:
			left += foot.ground
			counted.x += 1.0
		else:
			right += foot.ground
			counted.y += 1.0
	if counted.x <= 0.0 or counted.y <= 0.0:
		return 0.0
	return (left / counted.x).distance_to(right / counted.y)


# ---------------------------------------------------------------- the ground ----

## How high the ground is where this foot is being put down, and how much room a
## foot of this size has there. The ceiling handed to the query is the one
## anatomical fact in it: a foot goes as high as the joint that swings it and no
## higher, so anything whose top is above the socket is not a surface this leg can
## stand on and the query answers with whatever is underneath — which is the
## difference between stepping onto a ledge and walking into a wall.
func _surface_under(foot: Foot, at: Vector2, query: Callable) -> Vector2:
	if not query.is_valid():
		return Vector2(0.0, INF)
	var answer: Variant = query.call(at, foot.foot_size, foot.corner + foot.foot_size)
	return answer as Vector2 if answer is Vector2 else Vector2(0.0, INF)


## Where this foot should actually be put down, given where the step was aimed.
##
## A foothold is a place with room on it. The aim comes from the stride and knows
## nothing about what is underfoot, so on broken ground it regularly lands on the
## lip of something — and standing there is what a body does immediately before it
## slips off. So the foot looks around: candidates are offsets of its own footprint,
## tried nearest-first and taken as soon as one has room — inward toward the socket
## first, because that is how an animal shifts its weight when a foothold is poor,
## then along and across its own travel. Nothing is repositioned when the aim is
## already sound, which is nearly always and is the whole of the flat-ground
## behaviour: one query, no search.
func _footing(foot: Foot, aim: Vector2, query: Callable) -> Vector2:
	var surface: Vector2 = _surface_under(foot, aim, query)
	if surface.y >= 0.0:
		return aim
	var inward: Vector2 = foot.socket - aim
	inward = inward.normalized() if inward.length_squared() > 0.000001 else foot.travel
	var across := Vector2(-foot.travel.y, foot.travel.x)
	var best: Vector2 = aim
	var best_room: float = surface.y
	for step in FOOTING_STEPS:
		var span: float = foot.foot_size * float(step + 1) * FOOTING_REACH
		for direction in [inward, -foot.travel, foot.travel, across, -across]:
			var candidate: Vector2 = foot.clamp_to_envelope(aim + direction * span,
				_swing_fan(foot))
			var room: float = _surface_under(foot, candidate, query).y
			if room >= 0.0:
				return candidate
			if room > best_room:
				best_room = room
				best = candidate
	# Nowhere within reach has room for the whole foot, so the least bad place is
	# where it goes: an animal crossing rubble is picking its way over footholds
	# that are all poor, and it still has to put its feet somewhere.
	return best


# ------------------------------------------------------------- the armature ----

## Hands the armature what it has to solve to: the two girdle heights the feet have
## measured, each limb's own corner, and where its foot is standing in three
## dimensions. Nothing here poses a bone — the chain graph owns that — and nothing
## in the armature decides where a foot goes.
func _place(armature: Armature) -> void:
	armature.fore_carry = shoulder_height
	armature.hind_carry = hip_height
	for foot in feet:
		foot.chain.foot_driven = true
		foot.chain.grounded = foot.bearing and not foot.stepping
		foot.chain.socket_rise = foot.corner
		foot.chain.foot_target = Vector3(foot.ground.x, foot.ground.y,
			foot.foot_height)


# ------------------------------------------------------------------ readings ----
# What the gait is doing right now, in the terms a person would measure it in.
# Read by the panels and by nothing that decides anything: every one is a
# measurement the solver above already took, quoted rather than recomputed.

## True when the creature has at least one foot in the air.
func any_stepping() -> bool:
	for foot in feet:
		if foot.stepping:
			return true
	return false


## How long one full limb cycle is currently taking, seconds.
func cycle_length() -> float:
	return _measured_cycle()


## Where in its own cycle the animal is, 0..1, measured from the phase of the limb
## that last left the ground. Negative while there is no beat to be in.
func cycle_position() -> float:
	var elapsed: float = _beat_phase()
	if elapsed < 0.0:
		return -1.0
	return fposmod(cadence.phase(_beat_key) + elapsed, 1.0)


## The mean pace of the legs doing the walking, 0..1 of flat out.
func mean_pace() -> float:
	var total: float = 0.0
	var count: int = 0
	for foot in feet:
		if not foot.bearing:
			continue
		total += foot.pace
		count += 1
	return total / float(count) if count > 0 else 0.0


## The share of its cycle each foot is currently keeping on the ground.
func duty_now() -> float:
	return loco.duty_at(mean_pace()) if loco != null else 0.5


## The duty factor as it would actually be measured: the share of its own measured
## cycle each walking foot spends on the ground. Falls back to the commanded duty
## until the legs have stepped enough to be measured.
func duty_measured() -> float:
	var total: float = 0.0
	var count: int = 0
	for foot in feet:
		if not foot.bearing or foot.cycle <= 0.0:
			continue
		total += 1.0 - clampf(foot.step_duration / maxf(foot.cycle, 0.001), 0.0, 1.0)
		count += 1
	return total / float(count) if count > 0 else duty_now()
