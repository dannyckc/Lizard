## What the creature is physically made of: how much of it there is, how hard it
## can pull, and how hard its jaws close.
##
## None of the three is a slider of its own. They are read off the body that is
## already being solved every tick — the silhouette's widths, the length they are
## strung along, the head cap, and how much tissue is still standing in the
## lattice — and scaled by three per-species power parameters. That is deliberate
## twice over. A Komodo comes out five times a Lizard because it is *drawn* five
## times the Lizard, not because someone remembered to move a second slider; and
## a creature eaten half open gets lighter, weaker and slacker-jawed for free,
## because the same lattice that says where the holes are is what these are
## measured through.
##
## Refreshed once per tick, after the body and the lattice. Everything that reads
## it — contact shares, hauling, grip strain — is strictly a consumer, so this
## stays a description of the creature rather than another system acting on it.
class_name Physique
extends RefCounted

## Silhouette volume of the default Lizard build, so `density` 1.0 reads as mass
## 1.0 there and every other creature is a ratio against it. A constant rather
## than a measured baseline for the same reason the lattice's dimensions are: it
## has to mean the same thing after the tuning panel has restructured the body
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


## Re-derives all three from the pose and lattice solved this tick.
func update(body: BodyShape, spine: Spine, tissue: TissueGrid, p: CreatureParams) -> void:
	if body == null or spine == null or body.widths.size() < 2 or p == null:
		return
	volume = body_volume(body, spine)
	condition = clampf(tissue.integrity(), 0.0, 1.0) if tissue != null else 1.0
	mass = maxf(p.density * (volume / REFERENCE_VOLUME) * condition, MIN_MASS)

	var area: float = pow(mass, AREA_EXPONENT)
	strength = maxf(p.muscle_power * area, 0.0001)

	# Bite force is sized off the head rather than off the body, because the head
	# is the part that does the biting and the part you can see doing it: a broad
	# skull reads as a hard bite before any number is involved. It is narrowed by
	# the surviving head tissue for the same reason every other query is — jaws
	# on a chewed-out skull are not the jaws the creature started with.
	var head_scale: float = body.head_radius / REFERENCE_HEAD_RADIUS
	var jaw_solid: float = tissue.head_solid() if tissue != null else 1.0
	bite_force = maxf(p.jaw_power * head_scale * head_scale * jaw_solid, 0.0)


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
