## The creature's short-term prediction of its own path — the environment half
## of the locomotion loop.
##
## Locomotion must account for the world continuously rather than treating
## terrain as an exception (docs/V2_DESIGN.md §Phase 3), and this file is how:
## it holds the immediate future as *measurements* — what is under a point,
## what rises along the strip the body is about to cross, how far ahead the
## first thing the legs cannot climb stands — and everything else consumes
## those measurements. A foot asks it where its landing actually is, so a step
## onto a ledge places the foot on the ledge with no ledge-case anywhere; the
## intent asks it how much of its ask the path ahead permits, so a wall slows
## the body the way an obstacle does and not the way a rule does.
##
## Deliberately thin, and meant to stay so as the world grows: when moving
## surfaces and other creatures arrive, they arrive as more things `surface`
## and `first_wall` know about, and no consumer changes.
class_name Outlook
extends RefCounted

## How far ahead the path is watched, seconds of current travel. Short by
## design: this is the next stride or two, not a route plan.
const HORIZON: float = 0.45

## Sample stations along the watched strip.
const SAMPLES: int = 4

## The tallest single step a leg takes in stride, as a share of its own
## length. Above this a rise is a wall to the walk — a leap's business.
const CLIMB_SHARE: float = 0.55

## The patch of ground a foot asks about, px.
const FOOT_PAD: float = 1.5


var terrain: Terrain


func attach(p_terrain: Terrain) -> void:
	terrain = p_terrain


## What is under a point. The one ground read every part of the locomotion
## takes — feet land on it, carries are quoted over it.
func surface(at: Vector2, pad: float = FOOT_PAD) -> float:
	if terrain == null:
		return 0.0
	return terrain.surface(at, pad, INF).x


## How much of an ask the path ahead permits, 0..1: 1 on open ground, falling
## to 0 as the first unclimbable rise closes in. `from` is where the body is,
## `motion` is where it is asking to be in a horizon's time, `base_z` what the
## body is standing at, `leg` the limb that would have to climb.
func headroom(from: Vector2, motion: Vector2, base_z: float, leg: float) -> float:
	if terrain == null or motion.length_squared() < 1.0:
		return 1.0
	var tallest: float = leg * CLIMB_SHARE
	for i in range(1, SAMPLES + 1):
		var t: float = float(i) / float(SAMPLES)
		if surface(from + motion * t) - base_z > tallest:
			# The wall is between the previous clear sample and this one; what
			# is permitted is travel up to it.
			return maxf(float(i - 1) / float(SAMPLES), 0.0)
	return 1.0


## The furthest point along `from → to` a leg of `leg` can actually put a foot,
## with the height it would land at. On open ground this is `to` on its own
## surface; a climbable ledge inside the span answers with the top of the
## ledge — which is the whole of "place foot on the higher surface"; an
## unclimbable one pulls the landing short to its base.
func reach_along(from: Vector2, to: Vector2, from_z: float, leg: float) -> Vector3:
	var z: float = surface(to)
	if z - from_z <= leg * CLIMB_SHARE:
		return Vector3(to.x, to.y, z)
	for i in range(SAMPLES - 1, -1, -1):
		var t: float = float(i) / float(SAMPLES)
		var at: Vector2 = from.lerp(to, t)
		var here: float = surface(at)
		if here - from_z <= leg * CLIMB_SHARE:
			return Vector3(at.x, at.y, here)
	return Vector3(from.x, from.y, from_z)


## The steepest rise along the watched strip, px above `base_z` — what the
## body trajectory reads to start carrying itself higher *before* the feet
## get there, so a step is approached rather than hit.
func rise_ahead(from: Vector2, motion: Vector2, base_z: float) -> float:
	if terrain == null or motion.length_squared() < 1.0:
		return 0.0
	var most: float = 0.0
	for i in range(1, SAMPLES + 1):
		var t: float = float(i) / float(SAMPLES)
		most = maxf(most, surface(from + motion * t) - base_z)
	return most
