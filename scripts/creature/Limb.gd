## One arm or leg: a two-bone FABRIK chain plus the state of its step cycle.
##
## The chain is solved in three dimensions and drawn in two. A limb runs from a
## socket the body holds at some height down to a foot standing on the floor, so
## the two bones span a real vertical gap — and solving that gap flat, as though
## the animal were a sticker on the ground, is what used to make an upright leg
## reach a distance it did not have and a tall body float above feet it was not
## actually standing on.
##
## So there are three parallel readings of the same chain, and only the first is
## authored:
##
##   * `plan` and `heights` — where each joint is on the ground plane, and how
##     far above it. This is the limb. Bone lengths are exact here.
##   * `joints` — where the picture puts it, which is `plan` displaced down the
##     screen by however much height it has lost. The drawn bones are foreshort-
##     ened and their screen lengths change as the animal moves; that is what a
##     projection does, and nothing may assert otherwise.
##
## The solve itself happens in the limb's *own* plane — the one containing the
## socket, the foot and the body's fore-aft axis. On a sprawled animal that plane
## is very nearly the ground, so the elbow folds backward across the floor; on a
## columnar one it is very nearly the sagittal plane, so the knee folds forward
## through the air underneath the body. Nothing chooses between those: the plane
## is spanned by where the foot is and which way the joint bends, so it tilts up
## as the limb does. It is also why nothing here has to guard against a knee
## buckling through the torso any more — a joint folding fore-and-aft cannot.
##
## Holds no logic of its own beyond bookkeeping — Gait decides when it steps,
## Fabrik decides where its joints end up.
class_name Limb
extends RefCounted

const FRONT: int = 0
const REAR: int = 1

## Closest a foot may come to its own socket, as a fraction of the limb's length
## — measured through the air, not across the floor. That distinction is the
## whole point: an upright leg standing straight down is a foot with no plan-view
## offset at all and a perfectly ordinary limb, while the same reading on a
## sprawled one is a leg folded up against its own shoulder.
const REACH_MIN: float = 0.30
## Corrections under this many pixels are not applied by the envelope clamp.
## Far below anything visible, far above the resting spine's micro-jitter —
## see clamp_to_envelope.
const ENVELOPE_SLOP: float = 0.05
## Below this the limb's own plane is degenerate and the fold direction has to be
## picked some other way — see solve_stance.
const PLANE_EPSILON: float = 0.0001

var key: String = "FL"
var pair: int = FRONT
## +1 = the +perpendicular side of the body, -1 = the other side.
var side: float = 1.0
## Diagonal gait group. Legs sharing a group step together (a trot).
var group: int = 0
## Which way the elbow/knee is seeded to bend, along the body's forward axis.
## Front limbs fold backward, rear limbs fold forward — the quadruped look.
var bend_sign: float = -1.0

## [shoulder/hip, elbow/knee, foot], as drawn. A projection of `plan`/`heights`,
## which is what everything that measures a limb against the world should read.
var joints: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## The same three joints on the ground plane, and their heights above it. Bone
## lengths are exact across these two together and across nothing else.
var plan: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var heights: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
## The two bones, at their true length. Rigid: the solver may not trade length
## for reach, which is the one thing FABRIK is here to guarantee.
var lengths: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
## What the drawn chain measures at full stretch — the plan reach across, plus
## whatever the perspective makes of the height. Used to normalise (how extended
## is this leg, how big a correction is a large one) and never to place a foot.
var total_length: float = 2.0
## The limb's actual length. Everything about how much *animal* is there — how
## thick the bone is drawn, how big the foot is, how much tissue the lattice lays
## down it — is priced off this, because an upright leg is not a spindly one.
var anatomical_length: float = 2.0

# --- where this limb stands ---------------------------------------------------
# The stance in the socket's own frame: how high the socket and the foot are, how
# far out to the side and fore-or-aft of the socket the foot rests, and the region
# around that it may be put down in. All of it is written by Gait each tick from
# the posture and the limb's own condition, and all of it is lengths rather than
# angles — a limb does not swing about its socket in this view, it swings about a
# joint held some way above the floor, and what that traces on the ground is an
# arc at very nearly constant radius rather than a fan.

## Height of the socket above the ground: what the body is holding this limb up
## by. The other end of the gap the two bones have to span.
var socket_height: float = 0.0
## Height of the foot. Zero for as long as it is on the floor, and the step arc's
## own clearance while it is not — a real height in the same pixels as x and y,
## which is why it is the same number the bones span, the same number the foot's
## band is built from, and the same number something small has to be shorter than
## to pass underneath.
var foot_height: float = 0.0
## The plane the picture is registered to, so this limb draws itself into the
## same view as the body it hangs off. See Stature.reference.
var reference: float = 0.0
## Resting offset of the foot from the socket: outward, and fore/aft.
var rest_lat: float = 0.0
var rest_fore: float = 0.0
## Radius of the disc on the ground the foot may be set down inside.
var plan_limit: float = 1.0
## Half the fore-and-aft excursion available to it, measured from `rest_fore`.
var sweep_limit: float = 1.0
## How far inboard of its own socket the foot may come. Zero on a sprawled limb,
## whose foot belongs outside the shoulder; most of the way to the spine on a
## columnar one, which stands underneath itself.
var inboard_limit: float = 0.0

## Where the foot is nailed to the world while it bears weight.
var planted: Vector2 = Vector2.ZERO
## Where the foot *would* like to be, given the body's current pose and speed.
var ideal: Vector2 = Vector2.ZERO
## Unit vector from the socket toward the rest stance — the direction the limb
## hangs in, seen from above. Nearly straight out to the side on a sprawled
## animal and barely defined on a columnar one, whose foot rests almost directly
## beneath its shoulder; kept because the contact router needs a stable outward
## sense to walk an obstacle around.
var rest_dir: Vector2 = Vector2.UP
## Distance between planted and ideal — the trigger for taking a step.
var error: float = 0.0

# --- how fast this socket is actually travelling ------------------------------
# The body's linear speed is not a usable stand-in. When the creature turns, and
# especially when it pivots on the spot where linear speed is zero, the hips
# sweep a far wider arc than the shoulders. Sizing every limb's stride and step
# timing off one shared body speed leaves the rear legs taking short, slow steps
# while their sockets race away — they sit permanently over threshold, get
# dragged, and the creature reads as swinging about its planted front feet.
var socket_vel: Vector2 = Vector2.ZERO
var socket_speed: float = 0.0
## Unit direction the socket is travelling, falling back to the body's heading
## when it is barely moving. This is what "ahead" means for *this* foot.
var travel: Vector2 = Vector2.RIGHT
## This limb's own 0..1 pace, standing in for the body's speed_norm.
var pace: float = 0.0
## Stride threshold derived from that pace. Cached so the debug view and the
## step decision cannot disagree about it.
var stride: float = 1.0
var prev_anchor: Vector2 = Vector2.ZERO
var socket_tracked: bool = false

var stepping: bool = false
var step_t: float = 0.0
var step_duration: float = 0.25
var step_from: Vector2 = Vector2.ZERO
var step_to: Vector2 = Vector2.ZERO

## Foot position on the ground plane this tick (planted, or along the step arc).
## This is the gameplay-truthful position: shadows and stride tests use it.
var ground: Vector2 = Vector2.ZERO
## Where the foot appears to be — `ground` displaced by what its height is worth
## on screen. What the eye reads as the foot; `ground` is where it really is.
var visual: Vector2 = Vector2.ZERO

var initialised: bool = false

## Scratch for the in-plane solve, kept so a walking creature allocates nothing.
var _plane: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

# --- what the anatomy says this limb can do -----------------------------------
# Read off BodyState once per tick and cached here so the gait, the IK and the
# debug overlay cannot disagree about it. All four are 1.0 on a sound limb, which
# is why a healthy creature moves identically to one with no anatomy at all.
#
# Nothing here is an injury. They are capabilities, and the limb has no idea what
# happened to it — which is the entire point of the split.

## Force available across the socket — what swings the limb, and so what pushes
## the body along.
var drive: float = 1.0
## Force available across the elbow or knee — what picks the foot up. Separate
## from `drive` because they fail separately: a leg chewed at the shank still
## swings from the shoulder and scuffs its foot along the ground.
var flex: float = 1.0
## How much of the limb the animal still commands. Zero is a limb that is
## physically present, possibly undamaged, and does not answer.
var command: float = 1.0
## What it can bear. Below Gait.SUPPORT_MIN the leg folds instead of carrying.
var carry: float = 1.0
## How far it can still be extended, as a multiple of its working envelope.
var reach: float = 1.0
## Off the animal entirely. A severed limb is not solved, not drawn and not
## stepped — there is nothing there.
var severed: bool = false
## Nothing is holding this limb out, so it is integrated rather than placed: the
## gait leaves it alone and `Ragdoll` carries it from the socket instead.
##
## Broader than any one injury, and deliberately so. It is true of every limb on a
## carcass and of a living animal's limb whose bone has been broken through, and
## those are the same fact about the rig — a chain with nothing posing it — arrived
## at from two different directions.
var carried: bool = false
## Bumped once per step. Seeds the placement scatter of a poorly controlled limb,
## so the error is fixed for the duration of a step rather than shivering every
## frame, and is reproducible run to run.
var step_index: int = 0


func setup(p_key: String, p_pair: int, p_side: float) -> void:
	key = p_key
	pair = p_pair
	side = p_side
	# Diagonal pairing: front-left moves with rear-right, front-right with
	# rear-left. Comparing the two booleans is the whole rule.
	group = 0 if ((pair == FRONT) == (side > 0.0)) else 1
	bend_sign = -1.0 if pair == FRONT else 1.0


## `anatomical` is the bone, and it is what the chain is solved with — the two
## bones are rigid in the world, however short the picture makes them look.
## `drawn` is what the same limb measures on screen at full stretch, used to
## normalise. Left out, the two are the same, which is the truth for a limb lying
## flat on the floor and so the right default for a carcass.
func set_lengths(anatomical: float, drawn: float = -1.0) -> void:
	anatomical_length = maxf(anatomical, 1.0)
	total_length = maxf(drawn if drawn >= 0.0 else anatomical_length, 1.0)
	lengths[0] = anatomical_length * 0.52
	lengths[1] = anatomical_length * 0.48


## Half-thickness of the upper bone, and the flesh over it. Off the anatomical
## length, so an upright leg is a stout column rather than a short thin one.
## Shared by the renderer, the lattice and the hit test so all three agree on how
## much limb is there.
func girth(scale: float) -> float:
	return maxf(anatomical_length * 0.16, 2.5 * scale)


func foot_radius(scale: float) -> float:
	return maxf(anatomical_length * 0.10, 3.0 * scale)


## Screen offset from where the foot *is* to where it is drawn. Height, and
## nothing else: the same displacement the whole body is drawn through, told
## about one foot. Down the screen by however far the floor sits below the plane
## the torso is drawn on, and back up by whatever the foot has been lifted.
func rise() -> Vector2:
	return Posture.drop(foot_height, reference)


## Highest this limb could hold its socket with its foot where it is now, if it
## were extended to `reach_share` of itself.
##
## Pythagoras and nothing else: a leg is a fixed length, so a foot set down
## further away is a body held lower. This is what stops an animal floating above
## feet it is not standing on, and — because the feet move as it walks — it is
## also where the body's bob comes from. Nothing authored it.
func support_height(reach_share: float) -> float:
	var span: float = (lengths[0] + lengths[1]) * reach_share
	var out: float = planted.distance_to(plan[0])
	return sqrt(maxf(span * span - out * out, 0.0))


## The heights one drawn part of this limb occupies: 0 and 1 are the two bones,
## 2 is the foot. Inflated by how thick that part is, because a bone is a capsule
## rather than a line and something has to pass under the whole of it.
func segment_band(segment: int, scale: float) -> Vector2:
	var half: float = foot_radius(scale)
	var lo: float = heights[2]
	var hi: float = heights[2]
	if segment < 2:
		half = girth(scale) * (0.5 if segment == 0 else 0.36)
		lo = minf(heights[segment], heights[segment + 1])
		hi = maxf(heights[segment], heights[segment + 1])
	return Vector2(maxf(lo - half, 0.0), hi + half)


## Worst relative error in the two bones, measured where they are real: through
## the air, across `plan` and `heights` together. Zero on a chain FABRIK has
## solved, and the invariant everything else about the limb rests on.
func bone_error() -> float:
	var worst: float = 0.0
	for i in 2:
		var flat: float = plan[i].distance_to(plan[i + 1])
		var up: float = heights[i + 1] - heights[i]
		var actual: float = sqrt(flat * flat + up * up)
		worst = maxf(worst, absf(actual - lengths[i]) / maxf(lengths[i], 0.0001))
	return worst


## Where this limb stands, in the socket's own frame. Anatomy rather than gait —
## it is where this limb hangs from this socket — so a limb that is not walking
## needs it just as much as one that is.
##
## `stance` is the plan-view radius the foot rests at: the whole leg, at whatever
## reach it stands at, seen from above. The posture splits it. Out to the side
## goes as much of it as the swing plane has not yet rotated away — nearly all of
## it on a sprawled animal, a tenth of it on a columnar one — and the fore/aft
## bias is spent out of what is left, so the front pair stands a little forward
## and the rear pair a little back without either of them being pushed off the
## circle their own leg reaches.
##
## Staying on that circle is the point, and it is not tidiness. The rest offset
## and the body's height are two sides of one triangle: a foot nudged outside the
## radius its leg rests at is a body that cannot be standing where it is standing,
## and the height solve answers by pinning the animal at full stretch, where it
## has nothing left to walk with.
func set_stance(a: Spine.Frame, p: CreatureParams, stance: float, lean: float) -> void:
	rest_lat = stance * lean
	rest_fore = sqrt(maxf(stance * stance - rest_lat * rest_lat, 0.0)) \
		* (p.front_foot_bias if pair == FRONT else p.rear_foot_bias)
	var dir: Vector2 = a.perp * (side * rest_lat) + a.fwd * rest_fore
	if dir.length_squared() < 0.000001:
		dir = a.perp * side
	rest_dir = dir.normalized()


## Where this limb rests, in the world.
func rest_point(a: Spine.Frame) -> Vector2:
	return a.pos + a.perp * (side * rest_lat) + a.fwd * rest_fore


## The foot's offset from the socket in the socket's own frame: x is outward on
## this limb's side, y is toward the head. Working here rather than in world
## angles is what makes every limit below mean the same thing on both sides of
## the body and at any heading.
func local(a: Spine.Frame, v: Vector2) -> Vector2:
	return Vector2(v.dot(a.perp * side), v.dot(a.fwd))


## Projects `target` into the region this limb can physically stand in.
##
## Three limits, and none of them is a fan about the socket, because a limb does
## not swing about its socket in this view — it swings about a joint the body is
## holding some way above the floor, and what that traces on the ground is an arc
## at very nearly constant radius. So what is bounded is the radius, the
## fore-and-aft travel along it, and which side of the animal it is on:
##
##   1. the foot never comes further inboard than `inboard_limit`, which on a
##      sprawled limb is its own socket — that foot belongs outside the shoulder,
##      exactly as it always did — and on an upright one is most of the way to the
##      spine, because standing underneath itself is what that stance is;
##   2. it stays inside the fore-and-aft excursion the limb swings through;
##   3. and it stays inside the annulus the leg can reach at all, measured through
##      the air rather than across the floor.
##
## Feet are placed in world space and the body then walks out from under them, so
## without this nothing stops a foot ending up behind the opposite shoulder —
## and FABRIK will happily solve to it, drawing the leg straight through the
## torso, or lay the chain out dead straight when it is out of range.
##
## Returns `target` untouched when it is already legal, so a resting foot is
## never nudged by the round trip through the socket's frame. The same courtesy
## covers a target the projection would move by less than ENVELOPE_SLOP: the
## Verlet spine never settles to perfect stillness, so a planted foot left
## exactly on the boundary by its last skid would otherwise follow every micron
## of that jitter forever instead of staying nailed to the world.
func clamp_to_envelope(a: Spine.Frame, target: Vector2, max_reach: float,
		swing: float = -1.0) -> Vector2:
	var v: Vector2 = target - a.pos
	var here: Vector2 = local(a, v)
	var hi: float = maxf(plan_limit * max_reach, 0.001)
	var fore_limit: float = sweep_limit if swing < 0.0 else maxf(hi * sin(minf(swing, PI * 0.5)), 0.001)

	var lat: float = maxf(here.x, -inboard_limit)
	var fore: float = clampf(here.y, rest_fore - fore_limit, rest_fore + fore_limit)

	# The reach limit last, and through the air rather than across the floor: what
	# the leg has to span is the gap to the foot, and the gap has a vertical side.
	# A foot directly beneath a high shoulder has no plan-view offset at all and is
	# still most of a leg away from it, which is precisely the case a flat test
	# would call folded up and then drag inside-out to "fix".
	var drop: float = socket_height - foot_height
	var span: float = lengths[0] + lengths[1]
	var far: float = _flat_span(span * max_reach, drop)
	var near: float = _flat_span(span * REACH_MIN, drop)
	var out: Vector2 = Vector2(lat, fore)
	var r: float = out.length()
	if r > minf(far, hi):
		out *= minf(far, hi) / r
	elif r < near:
		out = (Vector2(rest_lat, rest_fore).normalized() if r < 0.000001 else out / r) * near

	var world: Vector2 = a.pos + a.perp * (side * out.x) + a.fwd * out.y
	return target if world.distance_squared_to(target) <= ENVELOPE_SLOP * ENVELOPE_SLOP else world


## How much of a span of `through` is left once `drop` of it has been spent going
## down: the flat side of the triangle whose hypotenuse the leg is. Zero when the
## drop alone uses the whole of it, which is a leg standing dead vertical.
func _flat_span(through: float, drop: float) -> float:
	return sqrt(maxf(through * through - drop * drop, 0.0))


## Places the elbow/knee before a flat IK solve, so the joint folds the way this
## joint folds. Used by the ragdoll, whose limbs lie in the ground plane and have
## no height to be solved through; the standing chain seeds itself in its own
## plane inside `solve_stance`.
##
## FABRIK stays on whichever side of the root->target axis it starts on, so this
## seed is what decides which way the limb bends and what stops it popping
## between the two mirror solutions. For two bones the joint sits exactly where
## the circles around each end meet, so it is placed there rather than nudged
## toward an approximate pole — near-straight is precisely where FABRIK crawls,
## and a partial seed leaves a limb at full stretch reading as locked out rigid.
func seed_joint(a: Spine.Frame, target: Vector2) -> void:
	var axis: Vector2 = target - a.pos
	var span: float = axis.length()
	var fold: float = signf(axis.cross(a.fwd * bend_sign))
	if span <= 0.000001 or fold == 0.0:
		return
	var u: Vector2 = axis / span
	var knee: Vector2 = _fold_seed(span)
	# rot90 of the axis is always on the axis's positive-cross side, so `fold`
	# alone selects the side the joint is meant to bend toward.
	joints[1] = a.pos + u * knee.x + Vector2(-u.y, u.x) * (fold * knee.y)


## Poses the whole limb, from the foot on the floor up to the socket the body is
## carrying.
##
## `foot_plan` is where the foot is standing, on the ground plane. Everything
## else the pose needs — how high the socket is being held, how high the foot has
## been picked up — is already on the limb, and between them they are the gap the
## two bones have to span. Solving that gap is the whole function; the picture is
## three lines at the end of it.
##
## The chain is solved by FABRIK inside the limb's own plane, with the bones at
## their true length, so what comes back is a chain that is exactly right in the
## world and merely foreshortened in the view. That ordering matters: solving in
## the view and hoping the world agrees is what lets a foot slide out from under
## a leg that cannot actually reach it.
func solve_stance(a: Spine.Frame, foot_plan: Vector2, iterations: int) -> void:
	var flat: Vector2 = foot_plan - a.pos
	var drop: float = foot_height - socket_height
	var span: float = sqrt(flat.length_squared() + drop * drop)

	# The plane: one axis down the limb, one across it toward the fold. `fold`
	# starts as the body's fore-aft direction — which way this joint bends — and
	# is squared up against the limb, so a leg lying flat folds across the floor
	# and one standing upright folds through the air, off the same line.
	var along: Vector3 = Vector3(flat.x, flat.y, drop)
	along = along / span if span > PLANE_EPSILON else Vector3(a.fwd.x, a.fwd.y, 0.0)
	var fold: Vector3 = Vector3(a.fwd.x, a.fwd.y, 0.0) * bend_sign
	fold -= along * fold.dot(along)
	if fold.length_squared() < PLANE_EPSILON:
		# The limb is pointing exactly the way the joint folds, so there is no
		# fore-aft left to fold into. It bends out to the side instead, which is
		# the only other direction a shoulder has.
		fold = Vector3(a.perp.x, a.perp.y, 0.0) * side
		fold -= along * fold.dot(along)
		if fold.length_squared() < PLANE_EPSILON:
			fold = Vector3(0.0, 0.0, 1.0) - along * along.z
	fold = fold.normalized()

	# In-plane the chain is an ordinary flat two-bone problem: root at the origin,
	# target straight out along the limb, and the knee seeded exactly where the
	# two bone circles cross so FABRIK has nothing left to correct on its first
	# pass. It still owns the general case and the out-of-range fallback.
	var reach := Vector2(span, 0.0)
	_plane[0] = Vector2.ZERO
	_plane[1] = _fold_seed(span)
	_plane[2] = reach
	_plane = Fabrik.solve(_plane, lengths, Vector2.ZERO, reach, iterations, 0.05)

	var socket := Vector3(a.pos.x, a.pos.y, socket_height)
	for i in 3:
		var point: Vector3 = socket + along * _plane[i].x + fold * _plane[i].y
		plan[i] = Vector2(point.x, point.y)
		heights[i] = point.z
		joints[i] = plan[i] + Posture.drop(point.z, reference)


## Where the joint sits for a chain of this span, in the plane it folds in: along
## the limb by `x`, out of it by `y`. The exact circle-circle intersection, so it
## is a solution rather than a hint.
func _fold_seed(span: float) -> Vector2:
	var l0: float = lengths[0]
	var l1: float = lengths[1]
	var along: float = clampf((span * span + l0 * l0 - l1 * l1) / (2.0 * maxf(span, 0.000001)), -l0, l0)
	return Vector2(along, sqrt(maxf(l0 * l0 - along * along, 0.0)))


## Measures how fast this socket is moving through the world, for the gait to
## size its stride and step timing from. `fallback` is used as the travel
## direction while the socket is essentially stationary.
##
## Smoothed, because one tick of constraint correction is body jitter, not a
## gait signal, and an unsmoothed reading would make stride length flicker.
func track_socket(pos: Vector2, delta: float, fallback: Vector2) -> void:
	if delta <= 0.0 or not socket_tracked:
		prev_anchor = pos
		socket_tracked = true
		socket_vel = Vector2.ZERO
		socket_speed = 0.0
		travel = fallback
		return
	var instant: Vector2 = (pos - prev_anchor) / delta
	prev_anchor = pos
	socket_vel = socket_vel.lerp(instant, 1.0 - exp(-9.0 * delta))
	socket_speed = socket_vel.length()
	# Below a pixel a second the direction is numerical noise, so hold the body's
	# heading instead of letting the foot aim at a random bearing.
	travel = socket_vel / socket_speed if socket_speed > 1.0 else fallback


func anchor() -> Vector2:
	return joints[0]


func elbow() -> Vector2:
	return joints[1]


func foot() -> Vector2:
	return joints[2]
