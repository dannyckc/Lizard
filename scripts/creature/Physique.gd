## What the creature is physically made of: how much of it there is, how hard it
## can pull, and how hard its jaws close.
##
## None of the three is a slider of its own. They are read off the body that is
## already being solved every tick — the silhouette's widths, the length they are
## strung along, the head cap, and how much tissue is still standing in the
## lattice — and scaled by three per-species power parameters. That is deliberate
## twice over. An Elephant comes out twenty times a Lizard because it is *drawn*
## twenty times the Lizard, not because someone remembered to move a second
## slider; and a creature eaten half open gets lighter, weaker and slacker-jawed
## for free, because the same lattice that says where the holes are is what these
## are measured through.
##
## Refreshed once per tick, after the body and the lattice. Everything that reads
## it — contact shares, hauling, grip strain — is strictly a consumer, so this
## stays a description of the creature rather than another system acting on it.
class_name Physique
extends RefCounted

## Silhouette volume of the default Lizard build, so `density` 1.0 reads as mass
## 1.0 there and every other creature is a ratio against it. A constant rather
## than a measured baseline for the same reason the lattice's dimensions are: it
## has to mean the same thing after the creation menu has restructured the body
## underneath it.
const REFERENCE_VOLUME: float = 29000.0
## Head cap radius of that same default build, ditto.
const REFERENCE_HEAD_RADIUS: float = 13.0
## Nothing is ever weightless — the contact solver divides by a mass sum, and a
## creature chewed down to its last cell still has to have a share of a push.
const MIN_MASS: float = 0.02
## Strength and bite force both go as a cross-sectional *area* while mass goes as
## a volume, so both scale with mass^(2/3). That is the square-cube law, and it
## is the whole reason a small creature can drag proportionally more than a large
## one — and why a large one still wins outright.
const AREA_EXPONENT: float = 2.0 / 3.0
## How much of its own weight a body's padding is. Quoted against an ordinary
## animal of the same plan, so a creature at the default reserve weighs exactly
## what it always did and only a deliberately fat or deliberately lean one moves —
## which is the whole reason fat can be added to the stack without silently
## reweighing every existing species.
const FAT_MASS_GAIN: float = 0.18

## Mass, in Lizard units. Sets who moves whom in every contact and every grip.
var mass: float = 1.0
## The force this creature can put into locomotion, in the same currency as the
## load a grip hangs off it.
var strength: float = 1.0
## The force the jaws clamp with, in the same currency again — so a grip's load
## and the bite holding it are directly comparable.
var bite_force: float = 1.0
## Plan-view volume of the drawn silhouette, before density or damage.
var volume: float = 0.0
## Fraction of its original tissue the creature still carries.
var condition: float = 1.0
## Padding carried, against an ordinary animal of the same build. Part of what
## this creature weighs.
var padding: float = 1.0
## How much of the body lies beyond each girdle: ahead of the shoulder in x,
## behind the hip in y, as shares of the whole drawn animal.
##
## The one reading here that is about where the weight is rather than how much of
## it there is, and it exists because a push is taken about a pivot. To drive with
## a girdle an animal has to get its weight over that girdle, and how far it can
## shift is set by what there is on the far side to balance against: a hind pair
## has the whole trunk in front of it and a tail behind, and rearing back over the
## hips is a thing every quadruped can do — while getting the trunk, the hips and
## the tail up over the shoulders is a thing none of them can, because there is
## only a head on the other side of that joint.
##
## That asymmetry, and not a rule about quadrupeds, is why propulsion comes from
## the hind limbs — and why the two builds in the file with long heavy tails are
## the two that jump best. See Leap, which is the only consumer.
var balance: Vector2 = Vector2(0.15, 0.30)


## Re-derives all three from the pose and lattice solved this tick.
##
## `state` is what the body can still *do*, as opposed to what is still there.
## The distinction matters for exactly one of the three: mass and bite force are
## properties of tissue and are read off the lattice, while strength is a muscle
## being driven — so a limb that is entirely present, well fed and simply not
## answering its nerve contributes its weight and none of its pull.
func update(body: BodyShape, spine: Spine, tissue: TissueGrid, p: CreatureParams,
		state: BodyState = null) -> void:
	if body == null or spine == null or body.widths.size() < 2 or p == null:
		return
	volume = body_volume(body, spine)
	condition = clampf(tissue.integrity(), 0.0, 1.0) if tissue != null else 1.0
	padding = tissue.fat_carried() if tissue != null else 1.0
	mass = maxf(p.density * (volume / REFERENCE_VOLUME) * condition
		* (1.0 + FAT_MASS_GAIN * (padding - 1.0)), MIN_MASS)

	var area: float = pow(mass, AREA_EXPONENT)
	var drive: float = state.locomotion if state != null and state.impaired else 1.0
	strength = maxf(p.muscle_power * area * drive, 0.0001)

	# Bite force is sized off the head rather than off the body, because the head
	# is the part that does the biting and the part you can see doing it: a broad
	# skull reads as a hard bite before any number is involved. It is narrowed by
	# the surviving head tissue for the same reason every other query is — jaws
	# on a chewed-out skull are not the jaws the creature started with.
	var head_scale: float = body.head_radius / REFERENCE_HEAD_RADIUS
	var jaw_solid: float = tissue.head_solid() if tissue != null else 1.0
	bite_force = maxf(p.jaw_power * head_scale * head_scale * jaw_solid, 0.0)

	# Where that weight is, either side of the two girdles. Off the same chain of
	# discs the volume is — it is the same body measured with the sum split in two
	# places instead of taken whole — so a tail switched off genuinely takes the
	# counterweight away with it rather than only shortening the silhouette.
	balance = Vector2(
		beyond(body, spine, p.front_limb_t, true),
		beyond(body, spine, p.rear_limb_t, false))


## Plan-view volume of the drawn body: a chain of discs, one per cross-section,
## clipped exactly where the silhouette is clipped, with a round cap at each end.
##
## Built from the same widths the view fills and the collision capsules narrow,
## so what you can see is precisely what it weighs — including the tail, which is
## why turning the tail off makes a creature lighter rather than only shorter.
static func body_volume(body: BodyShape, spine: Spine) -> float:
	var last: int = mini(body.last_index, spine.size() - 1)
	var total: float = 0.0
	for i in range(last):
		var w: float = (body.widths[i] + body.widths[i + 1]) * 0.5
		total += w * w * spine.points[i].distance_to(spine.points[i + 1])
	var snout: float = body.widths[0]
	var tip: float = body.widths[last]
	total += (snout * snout * snout + tip * tip * tip) * (2.0 / 3.0)
	return total


## Share of that same volume lying on one side of a station along the body.
##
## `t` is the station as a fraction from the snout, which is exactly the unit the
## girdles are placed in; `ahead` picks which side. The same chain of discs as
## above with the sum split rather than taken whole, so what it reports is a real
## measurement of the drawn animal — a broad chest counts, a switched-off tail
## does not, and a creature chewed open behind the hips loses its counterweight
## along with the flesh.
static func beyond(body: BodyShape, spine: Spine, t: float, ahead: bool) -> float:
	var last: int = mini(body.last_index, spine.size() - 1)
	if last < 1:
		return 0.0
	var station: float = clampf(t, 0.0, 1.0) * float(last)
	var total: float = 0.0
	var side: float = 0.0
	for i in range(last):
		var w: float = (body.widths[i] + body.widths[i + 1]) * 0.5
		var slab: float = w * w * spine.points[i].distance_to(spine.points[i + 1])
		total += slab
		# The station falls inside one of the slabs, so that slab is divided where
		# it actually falls rather than being handed wholesale to whichever side won
		# a rounding. Without it a girdle placed a hundredth of a body further back
		# could move the answer by a whole segment, which on a short spine is a
		# tenth of the animal.
		var share: float = clampf(station - float(i), 0.0, 1.0)
		side += slab * (share if ahead else 1.0 - share)
	# The two caps, whole: a snout is always ahead of any girdle and a tail tip
	# always behind one.
	var snout: float = body.widths[0]
	var tip: float = body.widths[last]
	var snout_cap: float = snout * snout * snout * (2.0 / 3.0)
	var tip_cap: float = tip * tip * tip * (2.0 / 3.0)
	total += snout_cap + tip_cap
	side += snout_cap if ahead else tip_cap
	return clampf(side / maxf(total, 0.0001), 0.0, 1.0)
