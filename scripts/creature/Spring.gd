## What in this body stores work and gives it back.
##
## The fifth structural descriptor, and the one the leap could not be honest
## without. `Articulation` says what angle a joint is carried at and how far it
## opens and closes; `Physique` says how hard the muscle across it can pull. Both
## describe a body that converts chemistry into movement at the instant it is
## asked to, and a great many animals do not work that way at all: the muscle
## pulls slowly against something elastic, that thing holds the work, and it is
## released later and very much faster than any muscle could have released it.
##
## That is not a detail of a few specialists. It is why a kangaroo hops more
## cheaply the faster it goes, why a horse's leg is mostly rope below the knee,
## and why a flea leaves the ground at an acceleration its own leg muscle could
## not produce for any length of time. So it is a structure, held per girdle
## beside the joint it crosses, rather than a multiplier on the jump.
##
## Three facts describe one, and each of them is a different piece of anatomy:
##
##   * **What it is made of** — how much of that girdle's drive passes through
##     something elastic on its way to the ground. A parameter, because it is
##     genuinely a property of the tissue rather than of the bones: two animals
##     with the same skeleton and different tendon can be different jumpers.
##   * **What it is wound along** — the distal bone and the foot at the end of
##     it. A spring stretched over a longer lever holds more, which is the whole
##     of why a jumping animal's lower leg is long and light and its foot is a
##     third limb segment. Read off `Articulation`, so a build given graviportal
##     proportions loses its store without anybody taking it away.
##   * **Whether it can be let go all at once** — see `latch`. A store paid out
##     through the joint's own extension can only leave as fast as the joint
##     opens, and a joint that barely opens cannot return what it is holding
##     however much that is. A catch that holds the store and then releases it
##     independently of the muscle removes that limit entirely, and it is what
##     lets a body with almost no limb travel throw itself many times its own
##     length. Insects that jump have one; insects that do not, do not — which is
##     why "can an insect jump" has no general answer and is not asked as one
##     here.
##
## Nothing in this file is a tendon specifically, and the vocabulary is
## deliberately mechanical. Resilin in a pad, apodeme in a cuticle, the bent rib
## of a click beetle and the long calcaneal tendon of a macropod are all the same
## three numbers: something that holds work, wound along some length, released
## through a joint or past it. The simulation asks how much and how fast, and
## there is no fourth question that would separate them.
class_name Spring
extends RefCounted

## How much of the foot counts as extra length for the store to be wound along.
## A foot is the last bone of the limb and the spring runs over the back of it —
## which is why a long-footed animal stores more without a longer leg, and why
## `toe_push` is the parameter doing it rather than a second one meaning the same
## thing. Half, because the toe is a lever arm about the ankle rather than a
## straight extension of the shin.
const TOE_LEVER: float = 0.5

## Joint travel, as a share of the whole limb, over which a store is returned
## completely. A spring gives its work back by pushing the joint open, so how
## much of it can be spent is how far there is to push through: a limb that
## extends by half of its own length pays out everything it holds, and one that
## extends by a twentieth pays out a twentieth of it. Around the stroke of an
## ordinary hind limb standing from a full crouch, so the term binds on the
## stiff and the short rather than on the animals a spring belongs to.
const FULL_STROKE: float = 0.45


## One girdle's elastic structure.
##
## Held rather than derived, in the same sense the joint is: it is a description
## of what is there, refreshed when the body is rebuilt, and every reading of
## what it can *do* belongs to `Leap`. The division is the same one the file
## header draws — this is the spring, and how much work a given animal manages to
## wind into it is a question about the muscle, which lives with the muscle.
class Store extends RefCounted:
	## Share of this girdle's drive that passes through elastic tissue.
	var elastic: float = 0.0
	## How much of the store is held by a catch rather than by the muscle itself.
	## At zero the spring is wound and released by the same contraction, so it can
	## only be paid out as the joint opens; at one it is held independently and
	## goes off as a single snap, which is what makes a very short limb able to
	## throw a body at all.
	var latch: float = 0.0
	## The length it is wound along, in world pixels: the distal bone and the foot
	## on the end of it.
	var lever: float = 0.0
	## And what that comes to — the length of wound elastic this girdle carries.
	## The one number `Leap` reads, because work is force times distance and this
	## is the distance; the force is the muscle's and belongs to the physique.
	var capacity: float = 0.0

	## Re-derives the three from one girdle's joint and the species' tissue.
	##
	## `bone` is the whole limb in world pixels, so everything below is a real
	## length and a creature drawn twice the size stores four times the work — as
	## it should, because it also weighs eight times as much and the two are what
	## `Leap` divides.
	func configure(joint: Articulation.Joint, bone: float, p_elastic: float,
			p_latch: float) -> void:
		elastic = clampf(p_elastic, 0.0, 1.0)
		latch = clampf(p_latch, 0.0, 1.0)
		lever = maxf(bone, 0.0) * (joint.lower + joint.push * TOE_LEVER)
		capacity = lever * elastic

	## How much of the store this joint can actually return, 0..1.
	##
	## A spring gives its work back by pushing something open, so a joint with
	## nowhere to go cannot spend what it is holding — which is the honest reason a
	## heavy columnar animal gets nothing out of the very real elastic tissue in
	## its legs. The catch is the way round it and the only way round it: a store
	## released independently of the joint's travel leaves at whatever rate the
	## catch lets go, and the limb is then a launcher rather than a lever.
	##
	## `stroke` is how far this limb is extending on this particular jump, so a
	## half-charged crouch pays out proportionally less. Which is not a penalty —
	## it is the same spring with less of the joint left to return through.
	func payout(stroke: float, bone: float) -> float:
		var through: float = clampf(stroke / maxf(bone * FULL_STROKE, 0.0001), 0.0, 1.0)
		return lerpf(through, 1.0, latch)


var fore: Store = Store.new()
var hind: Store = Store.new()


## Re-derives both girdles from the joints they cross and the species' tissue.
##
## Beside `Articulation.configure` and never apart from it: a spring is wound
## along a bone and let go through a joint, so it cannot be described until both
## of those are. `scale` is the creature's own drawn size, for the same reason
## every other length in the simulation carries it.
func configure(articulation: Articulation, p: CreatureParams, scale: float) -> void:
	if articulation == null or p == null:
		return
	fore.configure(articulation.fore, p.arm_length * scale, p.fore_spring, p.spring_latch)
	hind.configure(articulation.hind, p.leg_length * scale, p.hind_spring, p.spring_latch)


## The girdle a limb belongs to. `pair` is Limb.FRONT or Limb.REAR.
func of(pair: int) -> Store:
	return fore if pair == Limb.FRONT else hind
