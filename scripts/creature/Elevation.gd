## Where a body is in the one direction the top-down plane does not have.
##
## The world is still solved on the ground plane: x and y are the whole of where
## a creature is, and nothing in the spine, the gait or the contact pass has any
## idea this file exists. What is added here is a single scalar — how far off that
## plane the animal currently is — and the rule that two things can only touch
## each other when the heights they occupy overlap. That is the entire 2.5D
## layer. It is not a third axis of movement; it is a second question asked of
## every interaction that was already being tested horizontally.
##
## The four states the design calls for are *read* rather than written, which is
## why there is no transition table below and nothing anywhere sets a mode:
##
##   * grounded — the scalar is zero;
##   * leaping  — off the ground with nothing holding it up, so it is falling
##                whether or not it is still going up;
##   * gliding  — off the ground with wings carrying it, below the height those
##                wings can sustain;
##   * flying   — the same, at or above it.
##
## A creature with no wings can therefore only ever be grounded or leaping, and
## nothing had to say so: `wings` is zero, so the two airborne branches are
## unreachable. A creature with wings that stops working them is leaping again
## mid-air, which is exactly what a stall is.
class_name Elevation
extends RefCounted

const GROUNDED: int = 0
const LEAPING: int = 1
const GLIDING: int = 2
const FLYING: int = 3

const STATE_NAMES: Array[String] = ["grounded", "leaping", "gliding", "flying"]

## Pull toward the ground plane, in pixels per second squared.
##
## Aliased from `Gravity` rather than restated, and that is the whole of what
## makes this file a creature under gravity rather than a creature with its own.
## A severed leg, a dropped carcass and the animal that jumped over both are
## pulled down at one rate, because there is one number and every one of them
## reads it. Two descriptions of a pull is two things that can disagree, and the
## day they do is the day a body falls at a different speed than the leg it just
## lost.
const GRAVITY: float = Gravity.PULL
## How hard a wing beat can climb, in pixels per second at one unit of lift.
const CLIMB_SPEED: float = 220.0
## How fast a glide gives height up, at one unit of lift. Divided by lift, so a
## broader wing sinks more slowly on the same air — which is the whole difference
## between a glider and a creature falling with its arms out.
const SINK_SPEED: float = 90.0
## Extra downward acceleration when a flier folds up and dives, as a multiple of
## gravity's own.
const DIVE_GAIN: float = 1.6
## How quickly vertical velocity is taken to what the wings are asking for. A
## wing is not a rocket: it converts, and it takes a moment about it.
const LIFT_RESPONSE: float = 4.5
## Ceiling a wing can hold a body at, as a multiple of the animal's own length
## per unit of lift. A creature is out of a terrestrial predator's reach long
## before this, so the number only decides how much sky there is above that.
const CEILING_SPAN: float = 2.4
## Share of that ceiling above which the creature counts as high flight rather
## than low flight. Below it a flier is still in among the bodies on the ground
## and can be reached by a leap; above it, it is simply gone.
const HIGH_FLIGHT_SHARE: float = 0.45
## Below this the body is on the ground. Well under a pixel, so no leap can end
## early and nothing can hover imperceptibly. From `Gravity` for the same reason
## the pull is: what counts as standing on something is not a per-file opinion.
const TOUCHDOWN: float = Gravity.TOUCHDOWN

## Height above the ground plane, in world pixels — the same unit as x and y, so
## a leap is drawn to the same scale as the animal taking it.
var height: float = 0.0
## Rate of change of that, in pixels per second.
var rate: float = 0.0
## True on the tick the body came back down. Motion state, not a sound: the
## creature announces the landing and the habitat decides what it is worth.
var landed: bool = false
## How fast it was going when it got there, in pixels per second. Kept because
## `rate` is zero by the time anybody reads it — a landing is over the instant it
## happens, and what it was worth is how hard it arrived.
var impact: float = 0.0
## What the wings are being asked for and what they were able to give, cached for
## the state read below and for the HUD. Neither is a mode.
var _sustained: bool = false
var _ceiling: float = 0.0


func reset() -> void:
	height = 0.0
	rate = 0.0
	landed = false
	impact = 0.0
	_sustained = false
	_ceiling = 0.0


## Throws the body upward hard enough to peak at `peak` pixels. Refused unless it
## is standing on the ground, because a leap is a push against something.
##
## `effort` is what the legs can currently deliver — one on a sound animal, less
## on one that is damaged or towing something. It scales the apex rather than the
## launch speed, so a creature at half effort clears half the height rather than
## seven tenths of it, which is the honest reading: the peak of a leap is the
## work put into it.
func leap(peak: float, effort: float = 1.0) -> bool:
	if not is_grounded() or peak <= 0.0 or effort <= 0.0:
		return false
	rate = Gravity.launch_rate(peak * effort)
	height = TOUCHDOWN
	return true


## Advances the scalar one tick.
##
## `climb` is the vertical command, -1 to +1. `wings` is how much lift this
## animal's anatomy generates, zero on anything without them. `body_length` sizes
## the ceiling, and `effort` is the same fraction of itself the creature has
## available to a leap.
func advance(delta: float, climb: float, wings: float, body_length: float,
		effort: float = 1.0) -> void:
	landed = false
	_ceiling = CEILING_SPAN * body_length * wings
	if height <= 0.0 and rate <= 0.0:
		height = 0.0
		rate = 0.0
		_sustained = false
		return

	# What the wings are doing this tick. A wing only carries a body that is
	# asking to be carried: fold them and the animal is ballistic again, which is
	# the one line that makes "stall" a thing that can happen without being a
	# state anybody wrote.
	_sustained = wings > 0.0 and climb >= 0.0
	if _sustained:
		var target: float = -SINK_SPEED / maxf(wings, 0.05)
		if climb > 0.0 and height < _ceiling:
			target = CLIMB_SPEED * wings * effort * climb
		rate = lerpf(rate, target, 1.0 - exp(-LIFT_RESPONSE * delta))
	else:
		# Ballistic. A flier that folds up dives harder than it falls, which is
		# the only thing `climb` does to a body with nothing holding it up.
		var pull: float = GRAVITY * (1.0 + DIVE_GAIN * maxf(-climb, 0.0) * signf(wings))
		rate -= pull * delta

	height += rate * delta
	# Nothing may be held above what the wings can reach, however long the climb
	# was asked for. The velocity goes with the height, so a creature pinned to
	# its ceiling starts sinking the moment it stops beating rather than
	# continuing upward on stale momentum.
	if _ceiling > 0.0 and height > _ceiling:
		height = _ceiling
		rate = minf(rate, 0.0)
	if height <= TOUCHDOWN and rate <= 0.0:
		landed = height > 0.0 or rate < -TOUCHDOWN
		impact = absf(rate)
		height = 0.0
		rate = 0.0
		_sustained = false


## Brings the body back to the ground immediately — what happens when whatever
## was holding it up stops. A collapse, not a landing.
func ground() -> void:
	landed = height > 0.0
	height = 0.0
	rate = 0.0
	_sustained = false


func is_grounded() -> bool:
	return height <= TOUCHDOWN


func is_airborne() -> bool:
	return not is_grounded()


## The state, read off the scalar and off what the wings did with it. Nothing
## writes this, and nothing may: the moment it is stored it can disagree with the
## height it is supposed to describe.
func state() -> int:
	if is_grounded():
		return GROUNDED
	if not _sustained:
		return LEAPING
	return FLYING if height >= _ceiling * HIGH_FLIGHT_SHARE else GLIDING


func state_name() -> String:
	return STATE_NAMES[state()]


## Highest this animal's wings can hold it. Zero on anything flightless, which is
## also what makes the two flight states unreachable for it.
func ceiling() -> float:
	return _ceiling


## Pulls this body's height toward another's, by `share` of the gap. Used by the
## one thing that joins two creatures across the vertical axis: a set of jaws.
## Nothing else in the world reaches between two heights, because nothing else
## physically holds one body to another.
func tether(other_height: float, share: float) -> void:
	var pull: float = (other_height - height) * clampf(share, 0.0, 1.0)
	if absf(pull) <= 0.0001:
		return
	height = maxf(height + pull, 0.0)
	# The pull is a position correction, not a throw. Leaving the rate alone
	# would let a tugged body keep climbing on velocity it was never given.
	rate = lerpf(rate, 0.0, clampf(share, 0.0, 1.0))
