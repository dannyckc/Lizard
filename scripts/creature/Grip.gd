## A set of jaws holding onto another creature — the whole of what a latched
## bite is.
##
## Physically it is one inextensible tether between the biter's jaw point and an
## anatomical point on the victim. Torso holds live in body space; limb holds
## retain the limb, bone and station reported by the anatomy query. Living bodies
## resolve the tether through their existing rigid mass share, while a carcass
## can feed it into its free spine or limb particles at the held point.
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

## Force one intact cell of flesh on a Lizard-massed victim resists being pulled
## out with, in the same currency as `load` and `Physique.bite_force`. This is
## the number that decides which of the two ways a hold can end happens first:
## below the jaws' own force, the flesh gives before they do and the meat comes
## away in them; above it, they are pulled off a body that stayed in one piece.
const FLESH_TENSILE: float = 0.62
## Hit points in an intact cell of skin over muscle — what FLESH_TENSILE is
## quoted against. A bind still backed by bone therefore resists about twice as
## much, and one already chewed most of the way through gives almost at once.
const FLESH_REFERENCE_HP: float = TissueGrid.SKIN_HP + TissueGrid.MUSCLE_HP
## How far, in pixels, flesh at the point of parting has drawn out of the body.
## The tether lengthens by this much as it yields, so the two creatures visibly
## come apart before anything tears rather than snapping at a fixed distance.
const MAX_STRETCH: float = 7.0

var biter: Creature
var victim: Creature
## (spine_t, lateral) in the victim's body space — the same coordinates the
## anatomy hit reports and the tissue lattice stores damage in, and for the same
## reason: the pose is rebuilt from scratch every tick, so a hold recorded in
## world space would be a hold on nothing by the next one.
var bind: Vector2 = Vector2.ZERO
## Limb binding, when the jaws closed on a movable limb rather than the torso.
## The anatomy query already distinguishes these structures; retaining that
## answer here is what makes a pull on a foot articulate the leg instead of
## silently being converted into a pull on the nearest point of the spine.
var limb_key: String = ""
var limb_segment: int = -1
var limb_u: float = 0.0
## Jaw-to-flesh distance the tether treats as already satisfied — the play in the
## jaws, plus whatever gap they actually closed at.
var rest_length: float = 0.0
## Slack measured this tick, before either party took any of it up. The biter
## writes it during the contact phase and reads it back at the end of the tick.
var tension: float = 0.0
## Smoothed force on the jaws, in the same units as `Physique.bite_force`.
var load: float = 0.0
## How far the flesh in the jaws is from parting, 0 slack to 1 torn. Written by
## the biter each tick from how far past its yield point the pull has been and
## for how long; read back here as the stretch the tether has taken on.
var stress: float = 0.0


func is_alive() -> bool:
	return is_instance_valid(biter) and is_instance_valid(victim) \
		and biter.spine != null and victim.spine != null \
		and biter.body != null and victim.body != null


## Where the jaws are holding, in world space.
func anchor() -> Vector2:
	if holds_limb():
		return victim.limb_point(limb_key, limb_segment, limb_u)
	return victim.body_point(bind)


func holds_limb() -> bool:
	return not limb_key.is_empty() and limb_segment >= 0


func bind_body(at: Vector2) -> void:
	bind = at
	limb_key = ""
	limb_segment = -1
	limb_u = 0.0


func bind_limb(key: String, segment: int, u: float) -> void:
	limb_key = key
	limb_segment = clampi(segment, 0, 2)
	limb_u = clampf(u, 0.0, 1.0)


## Vector from the jaws to the flesh they are holding, zero while there is still
## play left in them. Only the part beyond the jaws' play and whatever the flesh
## has already drawn out is returned, so the tether is a rope rather than a
## spring: it takes up slack and does nothing else.
func slack() -> Vector2:
	var delta: Vector2 = anchor() - biter.jaw_point()
	var distance: float = delta.length()
	var over: float = distance - rest_length - stretch()
	if over <= 0.0 or distance <= 0.0001:
		return Vector2.ZERO
	return delta * (over / distance)


## How far the held flesh has drawn out of the body under the pull. Yielding
## tissue is the only elasticity in the whole join — the tether itself stays
## inextensible — so the give a heavy pull shows is the victim stretching, which
## is what it should look like right up until it parts.
func stretch() -> float:
	return MAX_STRETCH * stress


## Load as a fraction of what these jaws can hold. At 1.0 they are pulled off.
func strain() -> float:
	return load / maxf(biter.physique.bite_force, 0.0001)


## What the flesh in these jaws can be pulled with before it parts, in the same
## currency as `load` and the bite force above — so the two failures are directly
## comparable and neither is privileged.
##
## Two terms, and both are read rather than set. What is actually left inside the
## jaws' own footprint, so a mouthful backed by bone holds on far harder than one
## over an open cavity and a wound already chewed most of the way through gives
## almost at once. And the victim's own cross-section, by the same square-cube
## exponent the rest of the physique uses, because a mouthful of a large animal
## is a physically larger piece of meat with proportionally more fibre holding it
## to the body.
func tissue_strength() -> float:
	var footprint: float = victim.anatomy.tissue.flesh_within(
		anchor(), biter.gape_radius())
	return FLESH_TENSILE * (footprint / FLESH_REFERENCE_HP) \
		* pow(maxf(victim.physique.mass, 0.0001), Physique.AREA_EXPONENT)


## True once there is nothing left for the jaws to be holding. Jaws clamped on a
## hole are clamped on nothing — the same rule the bite query and the collision
## capsules already follow, applied to a hold that has to notice it continuously
## rather than on impact. It is also how a grip ends by being chewed off: the
## mouthful comes away and takes the hold with it.
##
## Two ways to be holding nothing, and both have to count. The body may no longer
## reach that far at all, and the cell the jaws are actually bound to may have
## been emptied while the column beside it still stands. The second is the
## ordinary aftermath of a tear, and without it a set of jaws would go on pulling
## against flesh that is already in them and part it again every tick.
func bind_is_hollow() -> bool:
	if holds_limb():
		return victim.limb_bind_solid(limb_key, limb_segment) <= 0.0
	return victim.bind_solid(bind) <= 0.0 or victim.bind_hp(bind) <= 0.0
