## One arm or leg: a two-bone FABRIK chain plus the state of its step cycle.
##
## Holds no logic of its own beyond bookkeeping — Gait decides when it steps,
## Fabrik decides where its joints end up.
class_name Limb
extends RefCounted

const FRONT: int = 0
const REAR: int = 1

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
## Distance between those two — the trigger for taking a step.
var error: float = 0.0

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


func anchor() -> Vector2:
	return joints[0]


func elbow() -> Vector2:
	return joints[1]


func foot() -> Vector2:
	return joints[2]
