## One arm or leg: a two-bone FABRIK chain plus the state of its step cycle.
##
## Holds no logic of its own beyond bookkeeping — Gait decides when it steps,
## Fabrik decides where its joints end up.
class_name Limb
extends RefCounted

const FRONT: int = 0
const REAR: int = 1

## Closest a foot may sit to its own socket, as a fraction of total limb length.
## Stops the chain folding back on itself when the body walks over its own foot.
const REACH_MIN: float = 0.30
## How far from straight-out-to-the-side a foot may swing before it would be
## crossing the body's midline. 90 degrees is the midline exactly, so the margin
## is what keeps the leg clear of the torso rather than skimming it.
const MIDLINE_LIMIT_DEG: float = 78.0
## Slack kept between the knee and the socket's own outward plane, so the joint
## reads as sitting outside the body rather than grazing it.
const KNEE_CLEARANCE_DEG: float = 6.0

var key: String = "FL"
var pair: int = FRONT
## +1 = the +perpendicular side of the body, -1 = the other side.
var side: float = 1.0
## Diagonal gait group. Legs sharing a group step together (a trot).
var group: int = 0
## Which way the elbow/knee is seeded to bend, along the body's forward axis.
## Front limbs fold backward, rear limbs fold forward — the quadruped look.
var bend_sign: float = -1.0

## [shoulder/hip, elbow/knee, foot]
var joints: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var lengths: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
var total_length: float = 2.0

## Where the foot is nailed to the world while it bears weight.
var planted: Vector2 = Vector2.ZERO
## Where the foot *would* like to be, given the body's current pose and speed.
var ideal: Vector2 = Vector2.ZERO
## Unit vector from the socket toward the rest stance — the centre of the fan
## this limb is allowed to swing through.
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
## Fake height above the ground. Top-down has no vertical axis, so height is
## faked as a screen-space offset; `visual` is `ground` shifted up by it.
var lift: float = 0.0
## Where the foot appears to be, and what the IK actually solves toward — so
## the whole leg picks up during a step rather than just the foot marker.
var visual: Vector2 = Vector2.ZERO

var initialised: bool = false


func setup(p_key: String, p_pair: int, p_side: float) -> void:
	key = p_key
	pair = p_pair
	side = p_side
	# Diagonal pairing: front-left moves with rear-right, front-right with
	# rear-left. Comparing the two booleans is the whole rule.
	group = 0 if ((pair == FRONT) == (side > 0.0)) else 1
	bend_sign = -1.0 if pair == FRONT else 1.0


func set_lengths(total: float) -> void:
	total_length = maxf(total, 1.0)
	lengths[0] = total_length * 0.52
	lengths[1] = total_length * 0.48


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


## Bearing past which the knee itself would swing inboard of the socket, for a
## foot `r` from the socket. Returns an angle in the same frame as bearing().
##
## Given the socket, the foot and two fixed bones there are only two possible
## joint positions, so once the foot is placed the knee cannot be moved out of
## the way — the limit has to be enforced on the foot. The joint folds toward
## `bend_sign`, and as the foot swings that same way the two converge until the
## joint's outward offset passes through zero and the leg buckles into the
## torso. That crossing is where the perpendicular half-chord `h` overtakes the
## along-axis distance `x`, which is what this returns.
func knee_safe_bearing(r: float) -> float:
	var l0: float = lengths[0]
	var l1: float = lengths[1]
	var x: float = (r * r + l0 * l0 - l1 * l1) / (2.0 * maxf(r, 0.0001))
	var h: float = sqrt(maxf(l0 * l0 - x * x, 0.0))
	if h < 0.0001:
		return PI * 0.5
	return maxf(atan2(maxf(x, 0.0), h) - deg_to_rad(KNEE_CLEARANCE_DEG), 0.0)


## The foot's bearing in the socket's own frame: 0 is straight out to this
## limb's side, positive is toward the head. Working in this frame rather than
## in world angles is what makes the limits below mean the same thing on both
## sides of the body and at any body heading.
func bearing(a: Spine.Frame, v: Vector2) -> float:
	return atan2(v.dot(a.fwd), v.dot(a.perp * side))


## Projects `target` into the region this limb can physically reach: an annulus
## sector around the socket, held clear of the body's midline and of the
## bearings where the knee would fold inward.
##
## Feet are placed in world space and the body then walks out from under them,
## so nothing else in the system stops a foot ending up behind the opposite
## shoulder — and FABRIK will happily solve to it, drawing the leg straight
## through the torso, or lay the chain out dead straight when it is out of
## range. This is the guarantee that the drawn limb always reads as a limb, no
## matter how far the gait has fallen behind the body.
##
## Returns `target` untouched when it is already legal, so a resting foot is
## never nudged by the round trip through polar coordinates.
func clamp_to_envelope(a: Spine.Frame, target: Vector2, max_reach: float, swing: float) -> Vector2:
	var v: Vector2 = target - a.pos
	var r: float = v.length()
	var lo: float = total_length * REACH_MIN
	var hi: float = total_length * max_reach
	if r < 0.000001:
		return a.pos + rest_dir * lo

	var midline: float = deg_to_rad(MIDLINE_LIMIT_DEG)
	var phi: float = bearing(a, v)
	var rest_phi: float = bearing(a, rest_dir)
	var clamped_r: float = clampf(r, lo, hi)
	var safe: float = knee_safe_bearing(clamped_r)

	if r >= lo and r <= hi \
			and absf(wrapf(phi - rest_phi, -PI, PI)) <= swing \
			and absf(phi) <= midline \
			and bend_sign * phi <= safe:
		return target

	# Three limits, each a projection onto its own legal range, applied
	# weakest-first so the hard anatomical ones always win.
	#   1. the swing fan, measured from the rest stance — the taste dial;
	var out_phi: float = rest_phi + clampf(wrapf(phi - rest_phi, -PI, PI), -swing, swing)
	#   2. the midline, so a foot never comes round to the body's centreline;
	out_phi = clampf(out_phi, -midline, midline)
	#   3. the knee, which buckles inward before the foot ever reaches the
	#      midline and so binds first on the side the joint folds toward.
	if bend_sign > 0.0:
		out_phi = minf(out_phi, safe)
	else:
		out_phi = maxf(out_phi, -safe)

	var out_axis: Vector2 = a.perp * side
	return a.pos + (out_axis * cos(out_phi) + a.fwd * sin(out_phi)) * clamped_r


func anchor() -> Vector2:
	return joints[0]


func elbow() -> Vector2:
	return joints[1]


func foot() -> Vector2:
	return joints[2]
