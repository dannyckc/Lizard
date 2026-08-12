## What an animal does when nothing is being asked of it — standing still, badly.
##
## A body at rest is not a body that has stopped. It is a tall, heavy thing held
## up by four props and a great deal of continuous correction: the weight slides
## about over the feet, the legs answer it, and every so often one of them gives
## up its footing and takes it again somewhere better. That is what this file
## produces, and it produces it **without steering the creature anywhere** —
## there is no AI in the game yet, and this is not the beginning of one. It sets
## no position, writes no command, chooses no destination and knows nothing about
## the world. It has exactly one output:
##
##     creature.shove(acceleration × delta)
##
## which is `Impetus`'s external-force seam, the same one a charge or a collision
## pushes through. Everything visible follows from the loop reacting to it: the
## thrust the intent demands back becomes `Travel`'s lean, the lean displaces the
## feet's homes, the drift against the planted anchors accumulates, and when it
## passes `Footwork.TRIGGER` a foot steps — in whatever company `Rhythm` allows.
## The animal shifts its balance according to the locomotion rules because the
## locomotion rules are the only thing acting on it.
##
## The acceleration is two terms:
##
##   * **the sway** — slow sinusoids on incommensurate periods, so the body never
##     repeats a cycle and never looks metronomic. This is the animal's own
##     restlessness: breathing, a head turning, weight coming off a tired leg. It
##     averages to nothing, which is most of why the body stays where it was put.
##   * **the post** — a spring back toward the spot it was stood on, which
##     removes the rest. Without it, tens of thousands of ticks of zero-mean
##     noise still add up to a random walk, and an unattended body would be
##     somewhere else in the morning. It is a spring and not a destination: it
##     saturates at `POST_REACH`, so a body knocked right out of its bay is
##     walked back to the edge of it and no further, and it is nowhere near
##     strong enough to overcome a shove, a slope, or a player shepherding it.
##
## Both are accelerations rather than velocities on purpose. A velocity written
## in here would be the creature being animated; an acceleration is a force
## acting on it, and the standing body fights it exactly as hard as `Impetus`
## fights any other force it did not ask for — which is why the sway comes out
## small and damped no matter what numbers are put in.
##
## **What it actually does, measured** (`ProvingProbe`, at these numbers): the
## body holds within a pixel or two of its post for stretches of a minute at a
## time, taking no steps at all — the weight moves, the spine and the legs
## answer it, and nothing lifts. Then the sway peaks past `Footwork.TRIGGER`,
## the animal starts adjusting its feet, and over the next half-minute it shifts
## about twenty pixels — an eighth of its own length — before its own balance
## and the post bring it back to a standstill. That cycle is *not* designed and
## it is not tuned for; it is what a threshold in the step trigger does to a
## body under a continuous disturbance, and it is left alone because it is both
## bounded and true. What was tuned is only how hard the disturbance pushes, and
## it was tuned against the one property that matters: over any length of time
## the animal is where it was left, because there is no term in here that
## prefers a direction.
class_name Repose
extends RefCounted

## Peak sway acceleration, px/s². Read against the standing brake it works
## against — `Impetus` sheds an unasked-for velocity at roughly
## `1/RESPONSE + HOLD` per second — so the couple of pixels of drift this
## actually produces is a much smaller number than this one looks.
const SWAY: float = 34.0

## The two periods the sway is built from, seconds. Deliberately not a ratio of
## small whole numbers: the sum never comes back round, so the body never falls
## into a loop the eye can learn.
const SLOW: float = 5.7
const FAST: float = 3.1

## How hard the post pulls, px/s² per px of displacement, and the displacement
## past which it stops growing. Saturating is what keeps it a spring rather than
## a leash: a body knocked right out of its bay is walked back to the edge of it
## and no further, and nothing here can overcome a shove, a slope, or a player
## shepherding the animal somewhere else.
const POST_PULL: float = 8.0
const POST_REACH: float = 10.0


var creature: Creature2
## Where the body was stood. Plan only: what it is standing *on* is the world's
## business, and a resident on a ledge keeps its post on the ledge.
var post: Vector2 = Vector2.ZERO
## How restless this individual is, 0..1 against `SWAY`.
var restlessness: float = 1.0

var _clock: float = 0.0
## Where in its own cycle this body is, so two animals standing side by side are
## not two copies of one animation.
var _phase: float = 0.0


func attach(p_creature: Creature2, seed_phase: float = 0.0) -> void:
	creature = p_creature
	post = p_creature.centre()
	_phase = seed_phase
	_clock = 0.0


## One tick of standing about. Costs nothing on a body that is dead, in the air,
## or being asked for something — a collapsed carcass has no balance to keep, and
## a walking animal's balance is already the loop's whole subject.
func tick(delta: float) -> void:
	if creature == null or not creature.alive or creature.armature.collapsed:
		return
	if creature.armature.fall.is_airborne():
		return
	if absf(creature.command.throttle) > 0.01 or absf(creature.command.turn) > 0.01:
		return
	_clock += delta

	var t: float = _clock + _phase
	# Two circles at different rates: the weight wanders a slow lens-shaped path
	# rather than rocking along one line, which is what a settled animal's centre
	# of mass actually does.
	var sway := Vector2(
		sin(TAU * t / SLOW) * 0.75 + sin(TAU * t / FAST + 1.7) * 0.25,
		cos(TAU * t / SLOW + 0.4) * 0.45 + cos(TAU * t / FAST) * 0.30)
	var push: Vector2 = sway * (SWAY * clampf(restlessness, 0.0, 1.0))

	# ...and the spring that keeps a night of it from being a journey.
	var home: Vector2 = post - creature.centre()
	push += home.limit_length(POST_REACH) * POST_PULL

	creature.shove(push * delta)


## Re-reads the post from where the body currently is — after a reset, or once a
## body that has been shoved somewhere is meant to belong there.
func plant() -> void:
	if creature != null:
		post = creature.centre()
