## The teeth in one creature's jaws, generated from its species parameters.
##
## Two arches of teeth set in an arc around the head, upper and lower. Seen from
## directly above — which is the only way anything is seen here — the two arches
## are nested rather than opposed: the upper arch is the wider of the two, so a
## closing set of jaws leaves two concentric rows of punctures with the lower
## row meshing into the gaps of the upper — bar the one pair that meets at the
## midline, since both arches are symmetric about the snout and an odd count
## puts a tooth on it, exactly as a mouthful of incisors does. That nesting is
## not a drawing trick; it is where every tooth actually is, and it is what
## `stamp` hands the tissue lattice to eat with.
##
## Only four numbers are authored — how many teeth, how long, how keen, and how
## wide the mouth opens. Everything else falls out of them:
##
##   * **Type** is read off where a tooth sits and how keen the species is. The
##     front of the arc is incisors, the canine station carries a fang if the
##     mouth is keen enough to have one, blades run back from there as far as
##     keenness reaches, and the rest of the arc is crushing molars. So a
##     needle-mouthed animal is fangs and blades nearly to the corners while a
##     blunt one is cusps and millstones — without either being listed anywhere.
##   * **Contact patch** is the slot the tooth has to sit in, narrowed by its
##     own keenness and shaped by its type: a blade is set edge-on and cuts a
##     slit, a canine is a cone and punches a hole, a molar is nearly as thick
##     as it is long and presses a bruise.
##   * **Penetration** is force over that patch, so it is not a parameter at
##     all. Few keen teeth concentrate one bite into deep punctures; a mouthful
##     of blunt cusps spreads the same bite into a broad shallow crush. That is
##     the whole reason a dentition is worth generating rather than drawing.
##
## A mark carries both halves of what jaws do: the punctures the teeth make, and
## the broad shallow patch the jaw itself bears with once they are buried. Which
## of the two a species does its damage through is the same keenness number
## again.
class_name Dentition
extends RefCounted

const UPPER: int = 0
const LOWER: int = 1

const INCISOR: int = 0
const CANINE: int = 1
const CARNASSIAL: int = 2
const MOLAR: int = 3

## Where each arch is seated, as a fraction of the gape radius. The gap between
## the two is what makes a bite mark two rows rather than one.
const UPPER_SEAT: float = 1.0
const LOWER_SEAT: float = 0.84
## How far in from its seat a tooth's contact patch sits, as a fraction of its
## own crown. Teeth converge inward on what they close on, so what actually
## touches the flesh is the tip end of the crown rather than the gum line.
const TIP_BIAS: float = 0.72
## Closest to the centre of the mouth a patch may be driven, so a fang longer
## than the gape is wide still bites in front of the throat rather than behind
## it.
const MIN_PATCH_SEAT: float = 0.12

## Where along the arc the canine station falls, 0 at the midline of the snout
## and 1 at the corner of the mouth.
const CANINE_STATION: float = 0.30
## Below this keenness a mouth has no canines at all. A blunt dentition is cusps
## the whole way round, and nothing here should invent a fang for one.
const CANINE_THRESHOLD: float = 0.30
## How far back from the midline incisors reach.
const INCISOR_SPAN: float = 0.18

# --- per type, indexed by the four kinds above ------------------------------
## Crown length, as a fraction of `tooth_size` — which is quoted as a canine,
## the longest thing in any mouth that has one.
const CROWN: Array[float] = [0.55, 1.0, 0.72, 0.46]
## How much of its own slot along the jaw line the crown fills. A blade wants
## the whole of it; a fang stands clear of its neighbours.
const SLOT_FILL: Array[float] = [0.78, 0.60, 0.95, 1.0]
## Thickness across the jaw line against length along it. This is the difference
## between the three ways a tooth meets flesh: a carnassial is a blade set
## edge-on and cuts a slit, a canine is round and punches, a molar is a face.
const STOUTNESS: Array[float] = [0.72, 1.0, 0.34, 1.05]
## Multiplier on the species' own keenness. A molar is blunt in a mouth full of
## needles and a canine is the sharpest thing in a mouth full of pegs.
const KEENNESS: Array[float] = [0.90, 1.15, 1.10, 0.40]

## Summed contact area of the default build's dentition, in normalized arc units
## — measured off it rather than chosen, exactly as Physique's reference volume
## and head radius are. It is what makes penetration a *ratio*: a mouth with
## half this much tooth touching the flesh drives twice as deep with the same
## jaws behind it, and the default build comes out at exactly `bite_damage`.
const REFERENCE_CONTACT: float = 0.1743
## Bounds on that ratio. Unbounded, a single needle would drive an arbitrarily
## deep hole and a mouth crowded with millstones would stop breaking skin at
## all; both ends stop being a bite.
const MIN_PRESSURE: float = 0.35
const MAX_PRESSURE: float = 2.6
## Bounds on how much further a long tooth reaches than a short one in the same
## mouth. Length is a real advantage and a small one — it is keenness that
## decides depth, and this only says which teeth in a given bite lead.
const MIN_REACH: float = 0.45
const MAX_REACH: float = 1.9

# --- what the jaw itself presses with ---------------------------------------
# Teeth are not the whole of a bite. They stand proud of the gum and go in
# first, but a bite is a closing rather than an impulse: once the points are
# buried the jaw keeps shutting, and everything the arch encloses is crushed
# between the two rows. That is the broad shallow half of any bite mark — the
# bruise the punctures sit in — and it is where a blunt dentition does all of
# its work. A mouth of cusps is nearly all bearing and almost no puncture; a
# mouth of blades is the reverse. Neither is written anywhere; both are this one
# interpolation on keenness.
const CRUSH_BLUNT: float = 1.0
const CRUSH_KEEN: float = 0.35
## The bearing patch is inscribed in the tooth arc — everything the jaws close
## around, and nothing outside them. Slightly under, because an arc's chord is
## inside its own curve and a bruise reaching past the outermost tooth would be
## a mark of a mouth that is not there.
const BEARING_INSET: float = 0.94


## One tooth. Everything is a fraction of the arc it is set in rather than a
## measurement in pixels, so a dentition is a property of the species and not of
## how big the animal wearing it happens to be.
class Tooth extends RefCounted:
	var jaw: int = UPPER
	var kind: int = MOLAR
	## Signed angle from the mouth's forward axis, along the arc.
	var angle: float = 0.0
	## Radius the crown is rooted at, and the radius its contact patch sits at.
	var seat: float = 1.0
	var patch_seat: float = 1.0
	## How far the crown projects inward from its seat.
	var crown: float = 0.2
	## Contact patch half-extents: along the jaw line, and across it.
	var half_along: float = 0.02
	var half_across: float = 0.02
	## Half-width of the crown where it leaves the gum, before keenness grinds
	## it to its point. Only the view reads this — what bites is the patch.
	var half_base: float = 0.02
	## 0 a blunt cusp, 1 a needle.
	var sharpness: float = 0.5


var teeth: Array[Tooth] = []
## Half-angle of the arc the teeth are set in.
var span: float = 1.22
## Summed contact area, in normalized arc units. What penetration is priced off.
var contact_area: float = 0.0
## Mean crown length, so a tooth's reach can be read against its own mouth.
var mean_crown: float = 0.0
## Mean seat of the contact patches — how far out the arch of teeth actually
## sits, and therefore how much mouth the jaw closes around.
var front_seat: float = 1.0
## The species' own keenness, kept because the jaw's bearing share is read off
## it — see the crush constants above.
var keenness: float = 0.5
## Where the mouthful lands relative to the arc centre, along the forward axis
## and as a fraction of the arc's forward reach. Symmetric about the midline, so
## it has no sideways term. The head is placed by this, which is what puts the
## jaws over the flesh they damage rather than behind it.
var centroid: float = 0.0
## The parameter set these teeth were grown from. Compared each tick so a slider
## regrows them, exactly as changing the segment count rebuilds the spine.
var signature: int = 0


## Grows a full set from a species' parameters. Deterministic in them, so a
## given animal has the same teeth every run and two of the same species have
## the same mouth.
static func grow(p: CreatureParams) -> Dentition:
	var d := Dentition.new()
	d.signature = signature_of(p)
	d.span = deg_to_rad(clampf(p.jaw_gape_deg, 5.0, 175.0))
	var keen: float = clampf(p.tooth_sharpness, 0.0, 1.0)
	d.keenness = keen
	var per_arch: int = maxi(p.tooth_count, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = d.signature

	for jaw in [UPPER, LOWER]:
		var seat: float = UPPER_SEAT if jaw == UPPER else LOWER_SEAT
		# The lower arch is offset half a slot as well as set inside the upper
		# one, so the two rows mesh. Both series stay symmetric about the
		# midline, so neither arch is lopsided.
		var arch: Array[Tooth] = []
		for i in per_arch:
			var t: float = (float(i) + 0.5) / float(per_arch) if jaw == UPPER \
				else (float(i) + 1.0) / float(per_arch + 1)
			var tooth := Tooth.new()
			tooth.jaw = jaw
			tooth.angle = lerpf(-d.span, d.span, t)
			tooth.seat = seat
			arch.append(tooth)
		d._assign_kinds(arch, keen)
		for tooth in arch:
			d._shape(tooth, per_arch, keen, p, rng)
			d.teeth.append(tooth)

	d._measure()
	return d


## The parameters a dentition is a function of. Any change to one of them is a
## different mouth and regrows it.
static func signature_of(p: CreatureParams) -> int:
	return hash([p.tooth_count, p.tooth_size, p.tooth_sharpness,
		p.jaw_gape_deg, p.tooth_variation])


## Type, read off position along the arc and the species' keenness. The
## boundaries move with keenness rather than being fixed, which is the whole of
## why a keen mouth is fangs and blades to the corners and a blunt one is cusps
## and crushers — nothing here chooses a dentition, it falls out of two numbers.
##
## The "carnassial" band is a blade only in a mouth keen enough to make one;
## `KEENNESS` leaves the same slot in a blunt mouth as a stout premolar, which
## is what it should be.
func _assign_kinds(arch: Array[Tooth], keen: float) -> void:
	var blade_reach: float = lerpf(0.34, 0.95, keen)
	# One fang per side, at whichever slot lands nearest the canine station.
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
		p: CreatureParams, rng: RandomNumberGenerator) -> void:
	var kind: int = tooth.kind
	var spread: float = clampf(p.tooth_variation, 0.0, 1.0)
	var jitter: float = 1.0 + rng.randf_range(-spread, spread)

	tooth.sharpness = clampf(keen * KEENNESS[kind], 0.0, 1.0)
	tooth.crown = maxf(p.tooth_size * CROWN[kind] * jitter, 0.01)
	tooth.patch_seat = maxf(tooth.seat - tooth.crown * TIP_BIAS, MIN_PATCH_SEAT)

	# The arc length one tooth has to itself. Keenness then narrows what of that
	# slot actually touches: the same crown ground to a point meets the flesh
	# over a fraction of the area, which is exactly why it goes deeper.
	var slot: float = 2.0 * span * tooth.patch_seat / float(per_arch)
	tooth.half_base = maxf(slot * 0.5 * SLOT_FILL[kind] * jitter, 0.004)
	tooth.half_along = maxf(tooth.half_base * lerpf(1.0, 0.42, tooth.sharpness), 0.004)
	tooth.half_across = maxf(tooth.half_along * STOUTNESS[kind], 0.003)


## The three whole-mouth figures the stamp is priced and placed off.
func _measure() -> void:
	contact_area = 0.0
	mean_crown = 0.0
	front_seat = 0.0
	var forward: float = 0.0
	for tooth in teeth:
		contact_area += PI * tooth.half_along * tooth.half_across
		mean_crown += tooth.crown
		front_seat += tooth.patch_seat
		forward += tooth.patch_seat * cos(tooth.angle)
	var count: float = float(maxi(teeth.size(), 1))
	mean_crown /= count
	front_seat /= count
	centroid = forward / count


## Force over area. A mouth with less tooth touching the flesh drives the same
## jaws deeper into it — so this is where tooth count, size and keenness turn
## into damage, and why none of them needed a damage number of its own.
func pressure() -> float:
	return clampf(REFERENCE_CONTACT / maxf(contact_area, 0.000001),
		MIN_PRESSURE, MAX_PRESSURE)


# ---------------------------------------------------------------- the arc ----
# The arc the teeth are set in is an ellipse rather than a circle, and that is
# anatomy rather than styling: a mouth reaches further forward than the skull is
# wide — that is what a snout *is* — while the corners of it can never be
# outside the head they are cut into. So the arc takes two radii, a forward
# reach and the skull's own half-width, and every tooth is placed on it.
#
# Both `stamp` and the view read their geometry through these, so what is drawn
# is the same arc that bites, down to the tooth.

## World position at one angle along the arc, `r` in normalized seat units.
static func arc_point(origin: Vector2, fwd: Vector2, perp: Vector2,
		reach: float, width: float, angle: float, r: float) -> Vector2:
	return origin + fwd * (cos(angle) * r * reach) + perp * (sin(angle) * r * width)


## Unit vector along the jaw line at one angle — the direction a blade shears.
static func arc_tangent(fwd: Vector2, perp: Vector2,
		reach: float, width: float, angle: float) -> Vector2:
	var t: Vector2 = fwd * (-sin(angle) * reach) + perp * (cos(angle) * width)
	return t.normalized() if t.length_squared() > 0.000001 else perp


## The single length a dentition's own measurements are quoted in, for a mouth
## of these two radii. The geometric mean, so a long narrow snout and a short
## broad one carrying the same teeth carry the same *size* of teeth.
static func arc_scale(reach: float, width: float) -> float:
	return sqrt(maxf(reach, 0.001) * maxf(width, 0.001))


## Closes these jaws at a place, and reports the mark they leave.
##
## `origin` is the centre of the arc — the head — with `reach` its forward
## semi-axis and `width` the skull's half-width. `depth` is what one closing of
## these particular jaws is worth in the lattice's hit points, before the teeth
## decide how it is spent.
func stamp(origin: Vector2, forward: Vector2, perp: Vector2,
		reach: float, width: float, depth: float) -> BiteMark:
	var mark := BiteMark.new()
	var fwd: Vector2 = forward.normalized() if forward.length_squared() > 0.000001 \
		else Vector2.RIGHT
	var side: Vector2 = perp.normalized() if perp.length_squared() > 0.000001 \
		else Vector2(-fwd.y, fwd.x)
	var scale: float = arc_scale(reach, width)
	var force: float = depth * pressure()
	for tooth in teeth:
		var imp := BiteMark.Impression.new()
		imp.pos = arc_point(origin, fwd, side, reach, width, tooth.angle, tooth.patch_seat)
		# The patch's long axis runs along the jaw line — a blade shears
		# sideways through flesh, it does not slice outward from the throat.
		imp.axis = arc_tangent(fwd, side, reach, width, tooth.angle)
		imp.half_along = tooth.half_along * scale
		imp.half_across = tooth.half_across * scale
		imp.sharpness = tooth.sharpness
		imp.kind = tooth.kind
		imp.jaw = tooth.jaw
		imp.depth = force * clampf(tooth.crown / maxf(mean_crown, 0.000001),
			MIN_REACH, MAX_REACH)
		mark.add(imp)

	# ...and the jaw closing behind them, over everything the arch encloses. One
	# patch, because what bears here is the mouth rather than any tooth in it:
	# it runs from the throat out to the front of the arch and as wide as the
	# arch is at its middle, which is the flesh actually held between the rows.
	var half_reach: float = front_seat * reach * 0.5
	var band := BiteMark.Impression.new()
	band.pos = origin + fwd * half_reach
	band.axis = fwd
	band.half_along = half_reach * BEARING_INSET
	band.half_across = front_seat * width * sin(minf(span, PI * 0.5)) * BEARING_INSET
	band.sharpness = 0.0
	band.bearing = true
	band.depth = depth * lerpf(CRUSH_BLUNT, CRUSH_KEEN, keenness)
	mark.add(band)

	mark.close(origin + fwd * (centroid * reach))
	return mark


## How far from the centre of the mouthful the flesh these jaws have closed on
## actually sits, for a mouth of these two radii.
##
## The arch is a ring around what it holds rather than a row in front of it — see
## the arc above — so this is the mean distance from the mouthful's centre out to
## the contact patches, less the crowns the teeth are buried to. A hold at exactly
## this distance is a hold with the teeth in the flesh, which is the only distance
## a latched bite has any business being at: nearer and the snout is inside the
## victim, further and the mouth is off it and there is a gap where the teeth
## should be.
##
## It is a property of the mouth and of nothing else, which is what makes it the
## rest length a grip is entitled to. A long-snouted animal holds its victim
## further from its face than a blunt one does, and a mouthful of needles closes
## further onto the flesh than a mouthful of cusps, because the crowns are longer.
func hold_radius(reach: float, width: float) -> float:
	if teeth.is_empty():
		return 0.0
	var centre: float = centroid * reach
	var total: float = 0.0
	for tooth in teeth:
		total += Vector2(cos(tooth.angle) * tooth.patch_seat * reach - centre,
			sin(tooth.angle) * tooth.patch_seat * width).length()
	return maxf(total / float(teeth.size()) - mean_crown * arc_scale(reach, width), 0.0)


## How many teeth of one type are set in these jaws. Reporting only; nothing in
## the simulation asks a dentition what it is made of.
func count_of(kind: int) -> int:
	var n: int = 0
	for tooth in teeth:
		if tooth.kind == kind:
			n += 1
	return n
