## A set of jaws holding onto another creature — the whole of what a latched
## bite is.
##
## Physically it is one inextensible tether between the biter's jaw point and a
## point bound into the victim's *body space*, resolved by exactly the machinery
## body contacts already use: a rigid translation of each complete creature, in
## shares set by their masses, applied in the same phase of the tick. A contact
## only ever pushes and a grip only ever pulls, and the two act at almost the
## same place, so a tether that could also push would spend its life fighting the
## separation pass instead of holding on.
##
## Everything the interaction reads as — latching, being towed, thrashing free,
## chewing — falls out of that one constraint and the masses either side of it.
## Nothing in here decides who wins.
##
## The biter owns the grip and is its only writer. The victim finds it by looking
## for whoever is holding it, exactly the way a creature finds the bodies it is
## standing inside, so neither party ever writes into the other's state.
class_name Grip
extends RefCounted

var biter: Creature
var victim: Creature
## (spine_t, lateral) in the victim's body space — the same coordinates the
## anatomy hit reports and the tissue lattice stores damage in, and for the same
## reason: the pose is rebuilt from scratch every tick, so a hold recorded in
## world space would be a hold on nothing by the next one.
var bind: Vector2 = Vector2.ZERO
## Jaw-to-flesh distance the tether treats as already satisfied — the play in the
## jaws, plus whatever gap they actually closed at.
var rest_length: float = 0.0
## Slack measured this tick, before either party took any of it up. The biter
## writes it during the contact phase and reads it back at the end of the tick.
var tension: float = 0.0
## Smoothed force on the jaws, in the same units as `Physique.bite_force`.
var load: float = 0.0
## Seconds until the jaws close again.
var chew_timer: float = 0.0


func is_alive() -> bool:
	return is_instance_valid(biter) and is_instance_valid(victim) \
		and biter.spine != null and victim.spine != null \
		and biter.body != null and victim.body != null


## Where the jaws are holding, in world space.
func anchor() -> Vector2:
	return victim.body_point(bind)


## Vector from the jaws to the flesh they are holding, zero while there is still
## play left in them. Only the part beyond `rest_length` is returned, so the
## tether is a rope rather than a spring: it takes up slack and does nothing
## else.
func slack() -> Vector2:
	var delta: Vector2 = anchor() - biter.jaw_point()
	var distance: float = delta.length()
	var over: float = distance - rest_length
	if over <= 0.0 or distance <= 0.0001:
		return Vector2.ZERO
	return delta * (over / distance)


## Load as a fraction of what these jaws can hold. At 1.0 they are pulled off.
func strain() -> float:
	return load / maxf(biter.physique.bite_force, 0.0001)


## True once the tissue the jaws are bound to has been eaten clean through.
## Jaws clamped on a hole are clamped on nothing — the same rule the bite query
## and the collision capsules already follow, applied to a hold that has to
## notice it continuously rather than on impact. It is also how a grip ends by
## being chewed off: the mouthful comes away and takes the hold with it.
func bind_is_hollow() -> bool:
	return victim.bind_solid(bind) <= 0.0
