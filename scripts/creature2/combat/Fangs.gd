## The teeth in one creature's jaws — Dentition's port, priced off the census.
##
## Two arches of teeth set in an arc around the head, nested rather than
## opposed, exactly as v1 grew them: only four numbers are authored (count,
## length, keenness, gape — BodySpec's dentition block) and type, contact patch
## and penetration all fall out of them. The front of the arc is incisors, the
## canine station carries a fang if the mouth is keen enough to have one,
## blades run back as far as keenness reaches, and the rest is molars.
## Penetration is force over contact area, so few keen teeth drive one bite
## deep and a mouthful of cusps spreads the same bite into a shallow crush —
## none of which is listed anywhere.
##
## What changed from v1 is where the force comes from and where the depth goes.
## The force is the jaw compartment — masseter muscle counted off the census,
## quoted against the reference cat's so the default build closes at exactly
## the reference depth — because v2 authors no bite-damage number anywhere.
## And the depth lands as *pixels of flesh* walked into census cells
## (Corpus.wound), so tooth depth maps straight onto layer thickness: a canine
## that is worth 3 px spends the skin's px, then the fat's, and parks in the
## muscle, and the next bite starts where it stopped.
class_name Fangs
extends RefCounted

const UPPER: int = 0
const LOWER: int = 1

const INCISOR: int = 0
const CANINE: int = 1
const CARNASSIAL: int = 2
const MOLAR: int = 3

## Where each arch is seated, as a fraction of the gape radius — the gap
## between the two is what makes a bite mark two rows rather than one.
const UPPER_SEAT: float = 1.0
const LOWER_SEAT: float = 0.84
## How far in from its seat a tooth's contact patch sits: teeth converge on
## what they close on, so the tip end of the crown is what touches.
const TIP_BIAS: float = 0.72
const MIN_PATCH_SEAT: float = 0.12

## Where along the arc the canine station falls, and below what keenness a
## mouth has no canines at all.
const CANINE_STATION: float = 0.30
const CANINE_THRESHOLD: float = 0.30
const INCISOR_SPAN: float = 0.18

# Per type, indexed INCISOR..MOLAR — ported with their reasons (Dentition.gd).
const CROWN: Array[float] = [0.55, 1.0, 0.72, 0.46]
const SLOT_FILL: Array[float] = [0.78, 0.60, 0.95, 1.0]
const STOUTNESS: Array[float] = [0.72, 1.0, 0.34, 1.05]
const KEENNESS: Array[float] = [0.90, 1.15, 1.10, 0.40]

## Summed contact area of the reference build's dentition, in normalized arc
## units — measured off it and pinned, exactly as Impetus.SPECIFIC_REF is, so
## penetration is a ratio and the default cat bites at exactly REF_DEPTH.
const REFERENCE_CONTACT: float = 0.174349

## What one closing of reference jaws at reference pressure is worth, in
## pixels of flesh — the v2 unit of a bite, spent through Corpus.wound's
## layer walk. Sized against the reference cat's own flank: skin and fat and
## a toothful of muscle, nowhere near through the rib bone in one closing.
const REF_DEPTH: float = 2.6

## The reference build's jaw compartment (masseter volume off the census),
## pinned beside CorpusProbe's constants. Bite force is the living jaw over
## this — a chewed or shrunken masseter closes softer, nothing is told.
const JAW_REF: float = 416.954952

## Bounds on the pressure ratio and on how much further a long tooth reaches
## than a short one — both ends past which a bite stops being a bite.
const MIN_PRESSURE: float = 0.35
const MAX_PRESSURE: float = 2.6
const MIN_REACH: float = 0.45
const MAX_REACH: float = 1.9

## The jaw's own bearing once the points are buried: the broad shallow half of
## a bite, all of a blunt mouth's work and little of a keen one's.
const CRUSH_BLUNT: float = 1.0
const CRUSH_KEEN: float = 0.35


## One tooth. Everything a fraction of the arc it is set in, so a dentition is
## a property of the species and not of the size of the animal wearing it.
class Tooth extends RefCounted:
	var jaw: int = UPPER
	var kind: int = MOLAR
	## Signed angle from the mouth's forward axis, along the arc.
	var angle: float = 0.0
	var seat: float = 1.0
	var patch_seat: float = 1.0
	## How far the crown projects inward from its seat.
	var crown: float = 0.2
	## Contact patch half-extents: along the jaw line, and across it.
	var half_along: float = 0.02
	var half_across: float = 0.02
	var sharpness: float = 0.5


var teeth: Array[Tooth] = []
## Half-angle of the arc the teeth are set in.
var span: float = 1.22
## Summed contact area, normalized arc units — what penetration is priced off.
var contact_area: float = 0.0
var mean_crown: float = 0.0
## The species' own keenness, kept for the bearing share.
var keenness: float = 0.5


## Grows a full set from the spec. Deterministic in it: the same animal has
## the same teeth every run.
static func grow(spec: BodySpec) -> Fangs:
	var f := Fangs.new()
	f.span = deg_to_rad(clampf(spec.jaw_gape_deg, 5.0, 175.0))
	var keen: float = clampf(spec.tooth_sharpness, 0.0, 1.0)
	f.keenness = keen
	var per_arch: int = maxi(spec.tooth_count, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([spec.tooth_count, spec.tooth_size, spec.tooth_sharpness,
		spec.jaw_gape_deg, spec.tooth_variation])

	for jaw in [UPPER, LOWER]:
		var seat: float = UPPER_SEAT if jaw == UPPER else LOWER_SEAT
		# The lower arch is offset half a slot as well as set inside the upper,
		# so the rows mesh; both stay symmetric about the midline.
		var arch: Array[Tooth] = []
		for i in per_arch:
			var t: float = (float(i) + 0.5) / float(per_arch) if jaw == UPPER \
				else (float(i) + 1.0) / float(per_arch + 1)
			var tooth := Tooth.new()
			tooth.jaw = jaw
			tooth.angle = lerpf(-f.span, f.span, t)
			tooth.seat = seat
			arch.append(tooth)
		f._assign_kinds(arch, keen)
		for tooth in arch:
			f._shape(tooth, per_arch, keen, spec, rng)
			f.teeth.append(tooth)

	f._measure()
	return f


## Type, read off position along the arc and keenness — the boundaries move
## with keenness rather than being fixed (Dentition._assign_kinds, verbatim).
func _assign_kinds(arch: Array[Tooth], keen: float) -> void:
	var blade_reach: float = lerpf(0.34, 0.95, keen)
	var fang_left: int = -1
	var fang_right: int = -1
	if keen >= CANINE_THRESHOLD:
		var best_left: float = INF
		var best_right: float = INF
		for i in arch.size():
			var u: float = absf(arch[i].angle) / span
			var distance: float = absf(u - CANINE_STATION)
			if arch[i].angle < 0.0 and distance < best_left:
				best_left = distance
				fang_left = i
			elif arch[i].angle >= 0.0 and distance < best_right:
				best_right = distance
				fang_right = i
	for i in arch.size():
		var u: float = absf(arch[i].angle) / span
		if i == fang_left or i == fang_right:
			arch[i].kind = CANINE
		elif u <= INCISOR_SPAN:
			arch[i].kind = INCISOR
		elif u <= blade_reach:
			arch[i].kind = CARNASSIAL
		else:
			arch[i].kind = MOLAR


## Everything a tooth measures, from its type and the room it has.
func _shape(tooth: Tooth, per_arch: int, keen: float,
		spec: BodySpec, rng: RandomNumberGenerator) -> void:
	var kind: int = tooth.kind
	var spread: float = clampf(spec.tooth_variation, 0.0, 1.0)
	var jitter: float = 1.0 + rng.randf_range(-spread, spread)
	tooth.sharpness = clampf(keen * KEENNESS[kind], 0.0, 1.0)
	tooth.crown = maxf(spec.tooth_size * CROWN[kind] * jitter, 0.01)
	tooth.patch_seat = maxf(tooth.seat - tooth.crown * TIP_BIAS, MIN_PATCH_SEAT)
	# The arc length one tooth has to itself; keenness narrows what of that
	# slot actually touches — the same crown ground to a point meets the flesh
	# over a fraction of the area, which is exactly why it goes deeper.
	var slot: float = 2.0 * span * tooth.patch_seat / float(per_arch)
	var half_base: float = maxf(slot * 0.5 * SLOT_FILL[kind] * jitter, 0.004)
	tooth.half_along = maxf(half_base * lerpf(1.0, 0.42, tooth.sharpness), 0.004)
	tooth.half_across = maxf(tooth.half_along * STOUTNESS[kind], 0.003)


func _measure() -> void:
	contact_area = 0.0
	mean_crown = 0.0
	for tooth in teeth:
		contact_area += PI * tooth.half_along * tooth.half_across
		mean_crown += tooth.crown
	mean_crown /= float(maxi(teeth.size(), 1))


## Force over area — where count, size and keenness turn into depth, and why
## none of them needed a damage number of its own.
func pressure() -> float:
	return clampf(REFERENCE_CONTACT / maxf(contact_area, 0.000001),
		MIN_PRESSURE, MAX_PRESSURE)


## What one closing of *these* jaws on *this* body is worth, px of flesh: the
## reference depth, scaled by the living masseter over the reference one and
## by the dentition's own pressure. The whole of bite force, and every term of
## it is derived.
func close_depth(corpus: Corpus) -> float:
	var jaw: float = float(corpus.compartments().get(&"jaw", JAW_REF))
	return REF_DEPTH * (jaw / JAW_REF) * pressure()


## Per-tooth share of a closing worth `depth`: length is a real advantage and
## a small one — keenness decided the depth, this only says which teeth lead.
func tooth_depth(tooth: Tooth, depth: float) -> float:
	return depth * clampf(tooth.crown / maxf(mean_crown, 0.000001),
		MIN_REACH, MAX_REACH)


## The jaw bearing down behind the buried points — the bruise the punctures
## sit in, and where a blunt mouth does all its work.
func crush_depth(depth: float) -> float:
	return depth * lerpf(CRUSH_BLUNT, CRUSH_KEEN, keenness)


## Where one tooth's contact patch sits in the world, for a mouth carried at
## `origin` facing `fwd` with a muzzle `reach` long and `width` across at the
## corners — the same elliptical arc v1 bit and drew with, at the jaw's own
## height. The 2.5D of a bite: the arc is a plan shape, its height is the
## mouth's, and whether each tooth finds flesh there is the target's own
## posed anatomy's answer (Contour.locate).
func tooth_point(tooth: Tooth, origin: Vector3, fwd: Vector2,
		reach: float, width: float) -> Vector3:
	var perp := Vector2(-fwd.y, fwd.x)
	var flat: Vector2 = Vector2(origin.x, origin.y) \
		+ fwd * (cos(tooth.angle) * tooth.patch_seat * reach) \
		+ perp * (sin(tooth.angle) * tooth.patch_seat * width)
	return Vector3(flat.x, flat.y, origin.z)


## The one length the crowns are quoted in for a mouth of these two radii.
static func arc_scale(reach: float, width: float) -> float:
	return sqrt(maxf(reach, 0.001) * maxf(width, 0.001))
