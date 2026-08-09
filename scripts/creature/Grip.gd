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
## Hit points in an intact cell of skin over fat over muscle — what FLESH_TENSILE
## is quoted against. A bind still backed by bone therefore resists about twice as
## much, and one already chewed most of the way through gives almost at once.
## Padding counts because it is tissue the jaws have hold of: there is more of a
## fat animal in a mouthful, and more of it holding that mouthful on.
const FLESH_REFERENCE_HP: float = TissueGrid.SKIN_HP + TissueGrid.FAT_HP \
	+ TissueGrid.MUSCLE_HP
## How far, in pixels, flesh at the point of parting has drawn out of the body.
## The tether lengthens by this much as it yields, so the two creatures visibly
## come apart before anything tears rather than snapping at a fixed distance.
## Quoted for tissue that is all skin over fat — see `softness`, which is what a
## given animal's flank actually manages against it.
const MAX_STRETCH: float = 7.0
## Skin over fat in an intact cell — what `softness` is measured against, and
## deliberately only the two layers that move. Muscle is anchored to bone and
## does not draw out, which is why it is in the tensile reference above and not
## in this one.
const SOFT_REFERENCE_HP: float = TissueGrid.SKIN_HP + TissueGrid.FAT_HP

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
##
## Two things draw it out and they are different in kind. Any load at all tents
## the skin and fat up into the jaws: that is elastic, it comes back the moment
## the pull does, and it is most of what a bite actually looks like. Past the
## tissue's yield point the fibres begin to part instead and the draw stops
## coming back, which is what `stress` measures on its way to a tear. The larger
## of the two, because they are the same tissue giving and it cannot be drawn out
## twice — and both are scaled by how much of it there is to draw.
func stretch() -> float:
	return MAX_STRETCH * softness() * maxf(taut(), stress)


## What the tissue in these jaws is carrying, against what it can carry. Zero on
## a hold nothing is pulling against, one at the point the fibres start to go.
func taut() -> float:
	return clampf(load / maxf(tissue_strength(), 0.0001), 0.0, 1.0)


## How far the held flesh has actually been drawn out of the body, as against how
## far it is *allowed* to be by `stretch` above.
##
## The whole of the daylight between where the jaws hold flesh and where the
## flesh currently is, capped by what this much soft tissue will give. The two
## are different jobs and both are needed: the allowance is what the tether
## defends, this is what the body has to be drawn into to look like the animal it
## is. A tether between two moving bodies always lags the one that is running by
## about the distance it covered in a tick — nothing discrete can do better — and
## skin over fat is exactly the thing that takes that up on a real animal. So the
## teeth stay buried in a flank that is visibly stretched toward them, instead of
## hanging off one at a polite and unexplained distance.
##
## Past the cap the tissue is at its limit and the daylight is real, which is
## also correct: that is a hold in the last moments before something gives, and
## what gives is decided by the load rather than by this.
func drawn() -> float:
	return clampf(biter.jaw_point().distance_to(anchor()) - biter.jaw_hold(),
		0.0, MAX_STRETCH * softness())


## How much of what these jaws are holding is the kind of tissue that moves.
##
## Skin and fat slide over the muscle beneath them; muscle is anchored to bone
## and does not. So the same pull draws a padded flank a long way out and a lean
## one barely at all, and flesh already eaten down past the fat stops stretching
## because what stretched is no longer there. It is the second half of what makes
## a hold a conversation between two anatomies rather than a constant: the mouth
## decides how much of the victim it has, and this decides what that much gives.
##
## Measured over the jaws' own footprint, exactly as `tissue_strength` is and for
## the same reason — the cell at the bind is the one the teeth have just gone
## through, so asking it alone would report that a fresh bite is holding nothing.
func softness() -> float:
	return clampf(victim.anatomy.tissue.soft_within(anchor(), biter.gape_radius())
		/ SOFT_REFERENCE_HP, 0.0, 1.0)


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


## How far the flesh may sit from the middle of the mouthful and still be
## between the teeth: the span of the mouth itself, plus however far the tissue
## has already drawn out of the body under the load on it.
##
## Both terms belong to a different animal, which is the point. The mouth says
## how much of anything it can have hold of at once; the victim's own soft tissue
## says how far it will follow the jaws before the two part company.
func contact_span() -> float:
	return biter.gape_radius() + stretch()


## How far past that the flesh has got. Zero or less is teeth in tissue.
func contact_gap() -> float:
	return biter.jaw_point().distance_to(anchor()) - contact_span()


## What these jaws have hold of, in the lattice's own hit points — the tissue
## actually standing inside the arch, averaged over the footprint the teeth cover.
## Zero is a mouth closed on a hole.
func purchase() -> float:
	return victim.anatomy.tissue.flesh_within(anchor(), biter.gape_radius())


## Whether this is a hold at all, asked of the two bodies rather than of a flag.
##
## A latch is teeth in tissue and it is nothing else, so both halves have to be
## true at the same instant: the flesh has to be inside the mouth, and there has
## to be flesh there for the teeth to be in. Neither is a rule about biting —
## the first is the biter's own arch against where the victim's body currently
## is, the second is the victim's own remaining tissue — and because it is a
## reading rather than a state, the same line decides whether jaws take hold on
## the frame they shut and whether they still have hold two seconds later. Jaws
## that lose contact have not been beaten by anything; they have simply come off,
## which is the one way a hold could previously never end.
func is_holding() -> bool:
	return contact_gap() <= 0.0 and purchase() > 0.0


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
