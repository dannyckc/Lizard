## What the creature is physically made of: how much of it there is, how hard it
## can pull, and how hard its jaws close.
##
## None of the three is a slider of its own, and none of them is read off the
## picture any more. They are counted out of *cells*: the body the pose describes
## is measured as a volume, that volume is a number of biological cells — the one
## unit in the game that never scales, see CELL_SIZE — and each cell weighs what
## the tissue standing in it weighs. An Elephant outweighs a Lizard because it is
## *built of* twenty-odd times the cells, not because someone remembered to move
## a second slider; a fat animal is heavier because fat is real tissue in its
## stack; a creature eaten half open gets lighter, and lighter by the density of
## exactly what was chewed out of it, because the same lattice that says where
## the holes are is what the census counts through.
##
## Strength is no longer mass with an exponent. It is the muscle cells — and only
## the muscle cells — raised to the area power, so a body that grows by laying
## down fat gets heavier without getting stronger, and one that grows thicker
## legs gets stronger because those legs are muscle. The square-cube law is not
## stated anywhere: an animal scaled up isometrically grows muscle with its
## volume, cross-section with the two-thirds power of it, and comes out slower
## per kilo, because that is what the arithmetic of counting does.
##
## Refreshed once per tick, after the body and the lattice. Everything that reads
## it — contact shares, hauling, grip strain — is strictly a consumer, so this
## stays a description of the creature rather than another system acting on it.
class_name Physique
extends RefCounted

## Edge of one biological cell, in world pixels. The one size in the game that is
## the same for every creature: a larger animal is more of these, never larger
## ones. Everything below is a count of them — a body part's size *is* its cell
## count, so doubling a part's linear dimensions is an eightfold gain in the
## cells it contains, and therefore in what it weighs.
const CELL_SIZE: float = 4.0
const CELL_VOLUME: float = CELL_SIZE * CELL_SIZE * CELL_SIZE

## What one cell of each tissue weighs, relative to water. Indexed by
## TissueGrid's layers, because they are the same tissues: bone is nearly twice
## the density of the flesh around it, fat floats, and muscle sits just over
## water like the meat it is. This is the whole of how composition reaches the
## scales — a bony animal and a fat one of the same size weigh what their
## different stacks add up to, and nothing anywhere else says so.
const TISSUE_DENSITY: Array[float] = [
	1.10,  # skin
	0.92,  # fat
	1.06,  # muscle
	1.80,  # bone
	1.05,  # organ
]

## How deep one hit point of each tissue stands in the body, relative to muscle.
##
## The lattice's hit points are a *bite* currency — how much closing of the jaws
## a layer soaks up — and toughness per pixel of depth is not the same from
## tissue to tissue: fat yields easily, so its few hit points are a thick soft
## layer; bone resists fiercely, so its many hit points are a modest thickness
## of skeleton. This is the exchange rate between the two currencies, and it is
## what the census converts through — so a reserve of fat is the fifth of the
## body's depth it is on a real animal, not the sliver its bite-cost implies,
## and the skeleton is a frame rather than a third of the flesh.
const LAYER_DEPTH: Array[float] = [
	1.0,  # skin
	4.0,  # fat
	1.0,  # muscle
	0.4,  # bone
	1.2,  # organ
]

## The default Lizard build's census, in density-weighted cells, so `density` 1.0
## reads as mass 1.0 there and every other creature is a ratio against it. A
## constant rather than a measured baseline for the same reason the lattice's
## dimensions are: it has to mean the same thing after the creation menu has
## restructured the body underneath it. Still quoted in the damage ledger's own
## units, because it norms the trunk reading that sizes the limbs — see `update`.
const REFERENCE_CELL_MASS: float = 280.0
## ...and its muscle alone, in cells, so `muscle_power` 1.0 reads as strength 1.0
## on the same animal. Ledger units, for the latticeless fallback only.
const REFERENCE_MUSCLE_CELLS: float = 172.0
## The same two rulers for the 3D cell lattice the census is now counted off:
## the default build's density-weighted standing cells, and its muscle cells
## alone. Chosen so the default build weighs and pulls *exactly* what it did
## under the ledger census it replaced — it reads 3804.94 units and 1151 muscle,
## quoted against slightly smaller rulers because the old census also sat the
## same fraction over its own reference — so no calibrated behaviour anywhere
## downstream moves. Re-measure with tests/LatticeProbe.gd if the carve changes.
##
## These last moved when the hull rule stopped rewriting thin structures into
## skin (AnatomyLattice.sheathed). Nothing about the animal's size changed and
## the cell count did not move at all; what moved is what those cells are *made
## of*, and a quarter of the body stopped being counted as hide. The muscle
## ruler grows most because that is where most of it went — which is the same
## fact as a lizard's legs having muscle in them at last.
##
## The units ruler moved again when the carve stopped dropping sections too
## shallow to hold a cell centre, which is what put the last slices of every
## tail back in the census (3804.94 units -> 3822.34 on the default build). The
## new cells are vertebra and sheath at the very tip of the tail: no muscle
## joined them, so the muscle ruler holds still.
const REFERENCE_LATTICE_UNITS: float = 3810.2835
const REFERENCE_LATTICE_MUSCLE: float = 1146.7139

## Least a girdle may be reduced to by having its muscle eaten. Not zero: a leg
## with nothing driving it is dragged rather than deleted, and every consumer of
## `drive` already has its own floor under what a spent limb still does.
const DRIVE_FLOOR: float = 0.08

## Silhouette volume of the default Lizard build, kept as the reference for the
## plan-view `volume` reading below — a picture-space number some consumers still
## want, distinct from the census the mass is counted out of.
const REFERENCE_VOLUME: float = 23224.0
## Head cap radius of that same default build, ditto.
const REFERENCE_HEAD_RADIUS: float = 13.0
## Nothing is ever weightless — the contact solver divides by a mass sum, and a
## creature chewed down to its last cell still has to have a share of a push.
const MIN_MASS: float = 0.02
## Strength and bite force both go as a cross-sectional *area* while mass goes as
## a volume, so both scale with volume^(2/3). That is the square-cube law, and it
## is the whole reason a small creature can drag proportionally more than a large
## one — and why a large one still wins outright.
const AREA_EXPONENT: float = 2.0 / 3.0

## Mass, in Lizard units. Sets who moves whom in every contact and every grip.
var mass: float = 1.0
## The force this creature can put into locomotion, in the same currency as the
## load a grip hangs off it. Read off the muscle cells alone — see `update`.
var strength: float = 1.0
## The force the jaws clamp with, in the same currency again — so a grip's load
## and the bite holding it are directly comparable.
var bite_force: float = 1.0
## Plan-view volume of the drawn silhouette, before density or damage.
var volume: float = 0.0
## Fraction of its original tissue the creature still carries.
var condition: float = 1.0
## Padding carried, against an ordinary animal of the same build. Descriptive —
## the weight of the fat itself is already in the census.
var padding: float = 1.0

## The census: biological cells standing in the whole animal, and per region of
## it. What "how big is this body part" now means — a chest widened in the
## creation menu contains more cells and says so here, and a leg bitten hollow
## contains fewer.
var cells: float = 0.0
var region_cells: PackedFloat32Array = PackedFloat32Array()
## Muscle cells standing, the only tissue strength is read off.
var muscle_cells: float = 0.0

## Muscle standing behind each girdle: the pair's own limbs plus the girdle
## region they hang from — thorax in x, pelvis in y — in cells.
##
## The muscle that swings a leg is mostly not on the leg. It is on the trunk, on
## the girdle the leg hangs from, and it reaches the limb across the socket; so
## "how much muscle drives this pair" is a question about a region of the body
## rather than about the limbs alone, and this is that region counted.
var girdle_muscle: Vector2 = Vector2.ZERO

## How much of that muscle is still standing, against what the animal was built
## with there. Exactly one on a body nobody has touched — for every build, by
## construction — and it is what makes this a description of an injury rather
## than of a species.
##
## The distinction matters and it is why this is quoted against the creature's
## own intact girdle rather than against a reference animal. How strong a build
## is for its size is `strength`, and how it splits its muscle between its two
## ends is `girdle_share`; neither of those is a thing that should move because
## the animal is hurt. This is: a hip eaten hollow stops driving the hind legs,
## which under the whole-body reading it did not, because a girdle is a small
## share of an animal and chewing one barely moved the total.
var girdle_drive: Vector2 = Vector2.ONE

## Which end of the animal its locomotor muscle is on: the fore girdle's share in
## x, the hind girdle's in y, adding to one.
##
## The reading that says a cheetah is built to drive from behind and an elephant
## from the shoulder. Descriptive — nothing multiplies a gait by it, because how
## much force there is altogether is already `strength` and pricing the same
## muscle twice would be the square-cube law applied at both ends of one animal.
var girdle_share: Vector2 = Vector2(0.5, 0.5)

## Mass each limb of a girdle is built to hold up, in Lizard units: x the fore
## pair, y the hind. This is what sizes a leg's thickness — see Limb.girth_of —
## so a heavier body demands thicker, more muscular legs and a forelimb that
## carries nothing (a biped's arm) is built to its own length instead. Quoted
## off the *intact* trunk at the species' density, because a skeleton is built
## for the body it grew under and does not slim when that body is bitten.
var limb_load: Vector2 = Vector2(0.25, 0.25)

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

## Physical volume standing over each region, px³, rebuilt each update. The
## bridge between the drawn body and the cell count: a region's cells are its
## volume over CELL_VOLUME, apportioned to tissues by its own reference stack.
var _region_volume: PackedFloat32Array = PackedFloat32Array()
## Rest half-widths at each spine station, for the region volumes above. Held
## rather than allocated because it is refilled every tick.
var _rest_widths: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_region_volume.resize(BodyPlan.REGIONS)
	region_cells.resize(BodyPlan.REGIONS)


## Re-derives all of it from the pose and lattice solved this tick.
##
## `state` is what the body can still *do*, as opposed to what is still there.
## The distinction matters for exactly one reading: mass and bite force are
## properties of tissue and are counted off the lattice, while strength is a
## muscle being driven — so a limb that is entirely present, well fed and simply
## not answering its nerve contributes its weight and none of its pull.
##
## `posture` is needed because a body is deep as well as wide and how deep is a
## stance trait — the same `depth_ratio` the lattice poses the cells with, so
## what the census weighs is exactly the solid the bites land in. Left null (a
## bare physique in a test) it is derived from the params, which is the same
## answer arrived at the long way.
func update(body: BodyShape, spine: Spine, tissue: TissueGrid, p: CreatureParams,
		state: BodyState = null, posture: Posture = null, scale: float = 1.0) -> void:
	if body == null or spine == null or body.widths.size() < 2 or p == null:
		return
	volume = body_volume(body, spine)
	condition = clampf(tissue.integrity(), 0.0, 1.0) if tissue != null else 1.0
	padding = tissue.fat_carried() if tissue != null else 1.0
	var stance: Posture = posture if posture != null else Posture.new(p.posture)

	if tissue != null:
		# The trunk first: its slabs are what the legs will be asked to hold up.
		# Measured off the animal's *rest* geometry rather than the pose solved
		# this tick, because what it sizes is the skeleton — see `limb_load`,
		# which is quoted off the intact trunk for exactly this reason. A body is
		# the same animal mid-stride bunched, mid-lunge stretched or mid-swallow
		# distended, and reading the census off the pose made the load breathe
		# with all three — which re-carved the whole cell lattice every few ticks
		# of a gallop, the single largest cost in the game.
		_axial_volumes(body, spine, tissue.plan, stance.depth_ratio, p, scale)

		# What each limb must carry: the intact trunk, at the species' density,
		# split across the limbs that actually bear. A biped's whole weight goes
		# through its hind pair and its arms carry nothing — which is why a
		# T. rex's legs come out pillars and its arms stay the twigs they are,
		# with no rule anywhere saying so.
		var trunk: float = p.density \
			* _tally(tissue, tissue.region_full) / REFERENCE_CELL_MASS
		var bearing: bool = Locomotion.bears_on_forelimbs(p)
		limb_load = Vector2(
			trunk * 0.25 if bearing else 0.0,
			trunk * (0.25 if bearing else 0.5))

		# The load is what sizes the legs, so it is settled before the lattice
		# lays cells around their bones. The lattice is the census: a genuine 3D
		# body of constant-sized cells, rebuilt only when the animal's own
		# description changes, mirrored against the damage ledger every tick.
		if tissue.lattice == null:
			tissue.lattice = AnatomyLattice.new()
		tissue.lattice.ensure(tissue.plan, p, scale, stance.depth_ratio,
			tissue.fat_reserve, limb_load)
		tissue.lattice.refresh_damage(tissue)

		# The standing census, counted straight off the cells: every region,
		# every tissue, at whatever is left standing in it. Damage needs no
		# multiplier — a bitten region simply counts fewer cells, and fewer of
		# whichever tissue the bite actually took. The same counts the anatomy
		# panel prints and its specimen draws, which is the whole claim.
		cells = float(tissue.lattice.standing_total)
		muscle_cells = float(tissue.lattice.tissue_cells(AnatomyLattice.MUSCLE))
		for region in BodyPlan.REGIONS:
			region_cells[region] = float(tissue.lattice.region_cells(region))
		mass = maxf(p.density * tissue.lattice.standing_units \
			/ REFERENCE_LATTICE_UNITS, MIN_MASS)
		_muscle_behind_the_girdles(tissue)
	else:
		mass = maxf(p.density * (volume / REFERENCE_VOLUME), MIN_MASS)

	# Strength is the muscle, and only the muscle, at the area power: force is
	# cross-section, and cross-section is what a two-thirds power of the tissue's
	# own bulk measures. Fat and bone are in the mass and not in this, so a
	# padded animal is duller for free and a bony one no fiercer. The species'
	# `density` *is* in it — it describes the animal's tissue throughout, muscle
	# included, so a denser build's muscle is denser muscle — which keeps mass
	# and strength in one currency: power-to-weight falls as the cube root of
	# density exactly as it falls with size.
	var drive: float = state.locomotion if state != null and state.impaired else 1.0
	var fibre: float = p.density * muscle_cells / REFERENCE_LATTICE_MUSCLE \
		if tissue != null else mass
	strength = maxf(p.muscle_power * pow(maxf(fibre, 0.0), AREA_EXPONENT) * drive, 0.0001)

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


## Counts the muscle each girdle has to drive its pair with — see `girdle_drive`.
##
## Straight off the lattice, so it is the same cells the specimen draws and the
## scales weigh, and so a bite that opens a hip takes muscle out of this the tick
## it lands.
func _muscle_behind_the_girdles(tissue: TissueGrid) -> void:
	var lat: AnatomyLattice = tissue.lattice
	var fore := Vector2(
		float(lat.region_tissue(BodyPlan.THORAX, AnatomyLattice.MUSCLE)),
		float(lat.region_tissue_built(BodyPlan.THORAX, AnatomyLattice.MUSCLE)))
	var hind := Vector2(
		float(lat.region_tissue(BodyPlan.PELVIS, AnatomyLattice.MUSCLE)),
		float(lat.region_tissue_built(BodyPlan.PELVIS, AnatomyLattice.MUSCLE)))
	for key in BodyPlan.LIMB_KEYS:
		var reg: int = int(tissue.plan.limb_region[key])
		var mine := Vector2(
			float(lat.region_tissue(reg, AnatomyLattice.MUSCLE)),
			float(lat.region_tissue_built(reg, AnatomyLattice.MUSCLE)))
		if key.begins_with("F"):
			fore += mine
		else:
			hind += mine
	girdle_muscle = Vector2(fore.x, hind.x)
	girdle_drive = Vector2(
		clampf(fore.x / maxf(fore.y, 1.0), 0.0, 1.0),
		clampf(hind.x / maxf(hind.y, 1.0), 0.0, 1.0))
	var total: float = maxf(fore.x + hind.x, 1.0)
	girdle_share = Vector2(fore.x / total, hind.x / total)


## Biological cells standing in one region — how big that body part is, in the
## only unit that means the same thing on every creature.
func cells_of(region: int) -> float:
	return region_cells[region] if region >= 0 and region < region_cells.size() else 0.0


# ----------------------------------------------------------------- census ----

## Physical volume of the axial body, attributed region by region.
##
## The same chain of elliptical slabs the lattice tessellates: half-width from
## the profile, half-depth the posture's ratio of it, a hemispherical head cap as
## deep as it is wide and a tail cap tapering with the tip. Everything here
## deliberately mirrors TissueGrid's posing of the same flesh, so the solid the
## census weighs and the solid a bite lands in are one body. (The constant π is
## dropped from every term alike — the census is a ratio against a reference
## counted the same way, so it cancels.)
##
## Measured at *rest*: every interval at its rest length and every station at
## its profile width, which is the same body `build` lays out before the solver,
## a swallow or a hold has done anything to it. On a standing animal the two
## measurements are identical; on a moving one this is the only reading that
## does not turn stride into anatomy.
func _axial_volumes(body: BodyShape, spine: Spine, plan: BodyPlan,
		depth_ratio: float, p: CreatureParams, scale: float) -> void:
	_region_volume.fill(0.0)
	var n: int = spine.size()
	var last: int = mini(body.last_index, n - 1)
	if last < 1 or plan == null:
		return
	if _rest_widths.size() != n:
		_rest_widths.resize(n)
	BodyShape.section_profile(p, scale, _rest_widths)
	# The same floor `build` puts under the drawn widths, so the two readings
	# stay one body at rest.
	for i in n:
		_rest_widths[i] = maxf(_rest_widths[i], 0.6)
	var seg_len: float = p.segment_length * scale
	for i in range(last):
		var w: float = (_rest_widths[i] + _rest_widths[i + 1]) * 0.5
		var slab: float = w * (w * depth_ratio) * seg_len
		_region_volume[plan.region_at((float(i) + 0.5) / float(last))] += slab
	# The head cap is a hemisphere as deep as it is wide — exactly how the
	# lattice poses it — and it is the whole of the HEAD region's volume: the
	# strip behind it already belongs to the neck and trunk.
	var r: float = _rest_widths[0]
	_region_volume[BodyPlan.HEAD] += r * r * r * (2.0 / 3.0)
	var tip: float = _rest_widths[last]
	_region_volume[BodyPlan.TAIL] += tip * (tip * depth_ratio) * tip * (2.0 / 3.0)


## Adds up the axial tissue stacks as density-weighted cells — the trunk the
## limbs are asked to carry.
##
## Quoted off the damage ledger rather than the cell lattice, deliberately: the
## lattice needs the limb loads *before* it can lay a leg's cells, so the trunk
## reading that produces those loads has to come from somewhere the legs are not.
## The conversion runs through each region's *reference* stack: the region's
## physical volume is worth its reference depth (hit points through
## LAYER_DEPTH), so a layer's cells are its share of that, and tissue beyond the
## reference (a heavy fat reserve) is genuinely extra cells.
func _tally(tissue: TissueGrid, hp: PackedFloat32Array) -> float:
	var total: float = 0.0
	for region in BodyPlan.REGIONS:
		if tissue.plan.is_limb_region(region):
			continue
		var base: int = region * TissueGrid.LAYERS
		var norm: float = 0.0
		for layer in TissueGrid.LAYERS:
			norm += tissue.region_norm[base + layer] * LAYER_DEPTH[layer]
		if norm <= 0.0 or _region_volume[region] <= 0.0:
			continue
		var cells_per_depth: float = _region_volume[region] / (norm * CELL_VOLUME)
		for layer in TissueGrid.LAYERS:
			total += hp[base + layer] * LAYER_DEPTH[layer] * cells_per_depth \
				* TISSUE_DENSITY[layer]
	return total


# ------------------------------------------------------------- silhouette ----

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


## Where that volume actually is, on the ground plane.
##
## The same chain of discs as above with each slab weighted by where it sits
## instead of only by how big it is — so it is a measurement of the drawn animal
## rather than a fraction of the distance between two girdles. That distinction is
## the whole reason it exists: a two-legged animal balances because its tail is
## behind its hips and its head is in front of them, and no interpolation between
## the shoulder and the hip can ever say so. This can, because it is the sum of
## where the body is.
##
## It follows the spine wherever the spine has bent to, which is right and is also
## a mechanic: a creature curled hard round to one side is genuinely carrying its
## weight over there.
static func centroid(body: BodyShape, spine: Spine) -> Vector2:
	var last: int = mini(body.last_index, spine.size() - 1)
	if last < 1:
		return spine.points[0] if spine.size() > 0 else Vector2.ZERO
	var total: float = 0.0
	var sum := Vector2.ZERO
	for i in range(last):
		var w: float = (body.widths[i] + body.widths[i + 1]) * 0.5
		var slab: float = w * w * spine.points[i].distance_to(spine.points[i + 1])
		total += slab
		sum += (spine.points[i] + spine.points[i + 1]) * 0.5 * slab
	# The two caps, at the two ends. A snout is a real hemisphere of animal out in
	# front of the first cross-section and a tail tip is one behind the last, and on
	# a short-bodied creature with a big head they are a serious share of it.
	var snout: float = body.widths[0]
	var tip: float = body.widths[last]
	var snout_cap: float = snout * snout * snout * (2.0 / 3.0)
	var tip_cap: float = tip * tip * tip * (2.0 / 3.0)
	total += snout_cap + tip_cap
	sum += spine.points[0] * snout_cap + spine.points[last] * tip_cap
	return sum / total if total > 0.0001 else spine.points[0]


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
