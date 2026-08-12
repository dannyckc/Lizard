## The census — v2's one body model, in body space (docs/V2_DESIGN.md §5).
##
## Successor of AnatomyLattice + TissueGrid + TissueForm + BodyShape and the
## census halves of Physique/Plumb: what is hit is exactly what is displayed,
## because mass, damage and shape are the same numbers. Every point of flesh
## has a body address `(chain, t, θ, d)` quantized into polar cells
## `(chain, station, sector, layer)`; a cell holds two numbers — `thickness`,
## the rest anatomy compiled from the spec's knots, and `hp`, the entire
## damage state. Effective thickness is `thickness × hp`, so a chewed-away
## wedge is thinner: the mesh dents, the mass drops and the next bite lands
## deeper, all automatically, because they all read this cell.
##
## The compile is the successor of v1's carve — knots → station ellipses →
## sector cells — and it runs once, from rest-pose data only, in microseconds.
## Nothing pose-derived is an input here, by construction: the live pose only
## ever *transforms* rings this file laid down (that is the armature's and the
## mesh's business), and posing can never re-carve anything.
##
## Derivations are read-only functions of the cells, each with exactly one
## owner (§7): mass and centre of mass are here (density × wedge-shell
## volume, the core bone counted with them); strength is the five muscle
## compartments; girth is the mean surface radius; compliance is the
## fat-over-structure ratio contacts read. Poise bakes the same cells to
## per-node masses for the armature — the census stays the owner, everything
## else holds a baked copy keyed to `revision`.
class_name Corpus
extends RefCounted

## A wound may thin a wedge to nothing but the wedge is still the animal's —
## hp has a floor of zero, never below, and division guards sit on this.
const MIN_MASS: float = 0.0001

## Where the neck chain's census stops being neck and starts being head, as a
## fraction of its arc — derived from the spec (the head stick's share), never
## authored twice. Compartment membership (neck vs jaw) reads this.
var jaw_from: float = 0.77


## One chain's slice of the census: its resolution, its rest geometry and its
## slice of the flat cell arrays. Rest geometry is body space — x pelvis →
## withers along the trunk, y flank to flank, z height above the ground the
## standing build delivers — and exists so the centre of mass and the baked
## node moments have places to weight; the live pose never reads it.
class CensusChain extends RefCounted:
	var name: StringName
	var kind: StringName
	## Which knot group authors this chain's tissue (limbs share per girdle).
	var group: StringName
	## First global column; columns run `base + station * sectors + sector`.
	var base: int = 0
	var stations: int = 0
	var sectors: int = 0
	## Censused arc length, px — for a limb the three bones, the girdle-offset
	## stick being trunk interior, not limb flesh.
	var length: float = 0.0
	## Axial length of one station's wedge, px.
	var seg: float = 0.0
	var side: float = 0.0
	## Per-station: bone-core radius, arc coordinate of the station centre
	## (from the chain's attach point), and the rest-pose frame — centre plus
	## the θ=0 (dorsal) and θ=π/2 (right-flank) unit vectors.
	var core: PackedFloat32Array = PackedFloat32Array()
	var arc: PackedFloat32Array = PackedFloat32Array()
	var centre: PackedVector3Array = PackedVector3Array()
	var up: PackedVector3Array = PackedVector3Array()
	var lat: PackedVector3Array = PackedVector3Array()
	## Reduced station moments for Poise, refreshed with the derivations:
	## mass, mass-weighted mean vertical offset off the station centre, and
	## mean lateral offset (zero on an intact flank-symmetric animal — wounds
	## are what give it a value).
	var st_mass: PackedFloat32Array = PackedFloat32Array()
	var st_rise: PackedFloat32Array = PackedFloat32Array()
	var st_side: PackedFloat32Array = PackedFloat32Array()


var spec: BodySpec

## This creature's own organs, vessels and nerves — the spec's table, copied at
## build so a wound to one animal's heart is a wound to *its* heart and not to
## the species'. Feature hp and breach state live on these dictionaries; the
## spec stays rest anatomy, authored once and never written back.
var features: Array[Dictionary] = []

## The cells. Flat arrays indexed `column * 4 + layer`; `columns` is
## BodySchema.column_count() and the two can never drift because the chains
## are allocated off the same constants.
var columns: int = 0
var thickness: PackedFloat32Array = PackedFloat32Array()
var hp: PackedFloat32Array = PackedFloat32Array()

## Bumped by every build and every wound — the signal consumers key their
## baked copies to. A tick that changed nothing walks no cells.
var revision: int = 0

var chains: Array[CensusChain] = []
var _by_name: Dictionary = {}

# Cached derivations, refreshed when `revision` moves.
var _derived_rev: int = -1
var _mass: float = 0.0
var _com: Vector3 = Vector3.ZERO
## Second moment about the body's own fore-and-aft axis, taken at the origin —
## Σ m·(y² + z²). The first moment above says where the weight is; this says how
## hard it is to roll, and it is the same walk's other accumulator. Kept at the
## origin rather than at the centre so the walk needs no second pass: the centre
## is not known until the end, and the parallel-axis shift is one subtraction
## afterward (`roll_inertia`).
var _roll_moment: float = 0.0
var _compartments: Dictionary = {}
## Muscle a chain still has against the muscle it was built with, as
## (effective, built) volume. What "how much of this leg is answering" is, and
## the only honest source for it: the same cells the compartments are summed
## from, before hp is spent on them.
var _chain_muscle: Dictionary = {}
## Per-layer volume standing and volume built, indexed by BodySchema.Layer, and
## what each layer currently weighs. Two different questions about one tissue and
## they come apart — a limb chewed off takes muscle and skin with it and leaves
## the body a larger fraction bone than it started — so both are counted, in the
## one walk, rather than a reader inferring either from the other.
var _layer_live: PackedFloat32Array = PackedFloat32Array()
var _layer_built: PackedFloat32Array = PackedFloat32Array()
var _layer_mass: PackedFloat32Array = PackedFloat32Array()
## What the animal would weigh with every cell whole — the denominator of
## `integrity`, and the only thing in the census that remembers a body that has
## since been bitten.
var _built_mass: float = 0.0

## Body length the `along` fraction is quoted against: the trunk between its
## girdles, because "are the legs under the weight" is the question the
## fraction exists to make a subtraction.
var trunk_length: float = 0.0


# ------------------------------------------------------------------ build ----

## Compiles the census from rest anatomy: the spec's chains give the bone
## cores and arc lengths, the knot tables give the tissue, and the §5.3 chain
## of representations runs knots → per-station ellipses → sector cells. Every
## input is rest-pose data; re-running it is only ever a physique change.
func build(p_spec: BodySpec) -> void:
	spec = p_spec
	chains.clear()
	_by_name.clear()

	var specs: Array[BodySpec.ChainSpec] = spec.chains()
	var fore_stance: float = spec.stance_height(true)
	var hind_stance: float = spec.stance_height(false)
	trunk_length = spec.trunk_length
	jaw_from = spec.neck_length / maxf(spec.neck_length + spec.head_offset, 0.001)

	# Trunk node arc positions, needed to hang the other chains' origins off
	# the stations they attach at.
	var trunk_spec: BodySpec.ChainSpec = specs[0]
	var trunk_arcs := PackedFloat32Array([0.0])
	for l in trunk_spec.lengths:
		trunk_arcs.append(trunk_arcs[trunk_arcs.size() - 1] + l)
	var trunk_total: float = trunk_arcs[trunk_arcs.size() - 1]

	var next_base: int = 0
	for c in specs:
		var chain := CensusChain.new()
		chain.name = c.name
		chain.kind = c.kind
		chain.group = _group_of(c)
		chain.base = next_base
		chain.stations = BodySchema.STATIONS[c.kind]
		chain.sectors = BodySchema.SECTORS[c.kind]
		chain.side = c.side

		# Censused sticks: everything for axial chains, the bones for a limb.
		var lengths: PackedFloat32Array = c.lengths.slice(1) if c.limb else c.lengths
		var radii: PackedFloat32Array = c.radii.slice(1) if c.limb else c.radii
		chain.length = 0.0
		for l in lengths:
			chain.length += l
		chain.seg = chain.length / float(chain.stations)

		# Rest frame: origin and axis per chain kind. The trunk's z runs from
		# what the hind legs deliver to what the fore legs do; carried chains
		# leave their girdle along the carry line; a limb's stations ride the
		# chord from socket to planted toe — the standing leg is folded, and
		# the fold's few px of excursion is below what a centre of mass needs.
		var origin: Vector3
		var tip: Vector3
		match c.kind:
			BodySchema.TRUNK:
				origin = Vector3(0.0, 0.0, hind_stance)
				tip = Vector3(trunk_total, 0.0, fore_stance)
			BodySchema.NECK:
				origin = Vector3(trunk_total, 0.0, fore_stance)
				var carry: float = deg_to_rad(c.carry_deg)
				tip = origin + Vector3(cos(carry), 0.0, sin(carry)) * chain.length
			BodySchema.TAIL:
				origin = Vector3(0.0, 0.0, hind_stance)
				var droop: float = deg_to_rad(c.carry_deg)
				tip = origin + Vector3(-cos(droop), 0.0, sin(droop)) * chain.length
			_:
				var socket_arc: float = trunk_arcs[c.attach_index]
				var socket_z: float = lerpf(hind_stance, fore_stance,
					socket_arc / maxf(trunk_total, 0.001))
				origin = Vector3(socket_arc, c.side * c.lengths[0], socket_z)
				tip = Vector3(socket_arc + c.foot_lead, origin.y, 0.0)

		var axis: Vector3 = (tip - origin).normalized()
		var lat := Vector3(0.0, 1.0, 0.0)
		var up: Vector3 = axis.cross(lat)
		if up.z < -0.5:
			up = -up
		up = up.normalized()

		chain.core.resize(chain.stations)
		chain.arc.resize(chain.stations)
		chain.centre.resize(chain.stations)
		chain.up.resize(chain.stations)
		chain.lat.resize(chain.stations)
		chain.st_mass.resize(chain.stations)
		chain.st_rise.resize(chain.stations)
		chain.st_side.resize(chain.stations)
		for st in chain.stations:
			var t: float = (float(st) + 0.5) / float(chain.stations)
			var at: float = t * chain.length
			chain.arc[st] = at
			chain.core[st] = _radius_at(lengths, radii, at)
			chain.centre[st] = origin + (tip - origin) * t
			chain.up[st] = up
			chain.lat[st] = lat

		next_base += chain.stations * chain.sectors
		chains.append(chain)
		_by_name[chain.name] = chain

	columns = next_base
	thickness.resize(columns * 4)
	hp.resize(columns * 4)
	hp.fill(1.0)

	# The features become this animal's: deep-copied so organ hp and vessel
	# breaches are per-creature state, exactly as cell hp is.
	features.clear()
	for f: Dictionary in spec.features:
		features.append(f.duplicate(true))

	# The compile proper: evaluate the knots per station, quantize per sector.
	for chain in chains:
		for st in chain.stations:
			var t: float = (float(st) + 0.5) / float(chain.stations)
			for layer in 4:
				var knot: Vector3 = _eval_knots(chain.group, layer, t)
				var off: float = _eval_ventral(chain.group, layer, t)
				for sec in chain.sectors:
					var theta: float = (float(sec) + 0.5) / float(chain.sectors) * TAU
					var cell: int = (chain.base + st * chain.sectors + sec) * 4 + layer
					thickness[cell] = _sector_thickness(knot.x, knot.y, off, theta)

	revision += 1


## The knot group a chain draws its tissue from: limbs pair up per girdle,
## everything else authors under its own name.
func _group_of(c: BodySpec.ChainSpec) -> StringName:
	if not c.limb:
		return c.name
	return &"fore_limb" if c.name in [&"FL", &"FR"] else &"hind_limb"


## Bone-core radius at an arc position — the radius of the stick covering it.
func _radius_at(lengths: PackedFloat32Array, radii: PackedFloat32Array,
		at: float) -> float:
	var run: float = 0.0
	for j in lengths.size():
		run += lengths[j]
		if at <= run:
			return radii[j]
	return radii[radii.size() - 1]


## Piecewise-linear knot evaluation: (rx, rz) at t, ends held. Returned as a
## Vector3 with z unused so one call carries both axes.
func _eval_knots(group: StringName, layer: int, t: float) -> Vector3:
	var knots: Array = _knot_list(group, layer)
	if knots.is_empty():
		return Vector3.ZERO
	var lo: Array = knots[0]
	var hi: Array = knots[knots.size() - 1]
	if t <= lo[0]:
		return Vector3(lo[1], lo[2], 0.0)
	if t >= hi[0]:
		return Vector3(hi[1], hi[2], 0.0)
	for k in range(1, knots.size()):
		if t <= knots[k][0]:
			var a: Array = knots[k - 1]
			var b: Array = knots[k]
			var s: float = (t - a[0]) / maxf(b[0] - a[0], 0.00001)
			return Vector3(lerpf(a[1], b[1], s), lerpf(a[2], b[2], s), 0.0)
	return Vector3(hi[1], hi[2], 0.0)


func _eval_ventral(group: StringName, layer: int, t: float) -> float:
	var knots: Array = _knot_list(group, layer)
	if knots.is_empty():
		return 0.0
	var lo: Array = knots[0]
	var hi: Array = knots[knots.size() - 1]
	if t <= lo[0]:
		return lo[3]
	if t >= hi[0]:
		return hi[3]
	for k in range(1, knots.size()):
		if t <= knots[k][0]:
			var a: Array = knots[k - 1]
			var b: Array = knots[k]
			return lerpf(a[3], b[3], (t - a[0]) / maxf(b[0] - a[0], 0.00001))
	return hi[3]


func _knot_list(group: StringName, layer: int) -> Array:
	var per_chain: Dictionary = spec.tissue_knots.get(group, {})
	return per_chain.get(layer, [])


## One sector's thickness off the station ellipse: the polar radius of an
## ellipse with vertical semi-axis rz (θ = 0, dorsal) and lateral rx, plus
## the ventral hang ramped from nothing at the back to its full value at the
## belly. Clamped at zero — a layer may be absent in a wedge, never negative.
func _sector_thickness(rx: float, rz: float, ventral: float,
		theta: float) -> float:
	if rx <= 0.0001 or rz <= 0.0001:
		return maxf(ventral * (1.0 - cos(theta)) * 0.5, 0.0)
	var c: float = cos(theta)
	var s: float = sin(theta)
	var ellipse: float = (rx * rz) / sqrt(rx * rx * c * c + rz * rz * s * s)
	return maxf(ellipse + ventral * (1.0 - c) * 0.5, 0.0)


# ---------------------------------------------------------------- address ----

func chain(name: StringName) -> CensusChain:
	return _by_name.get(name)


## Global column index of (chain, station, sector).
func column(name: StringName, station: int, sector: int) -> int:
	var c: CensusChain = _by_name[name]
	return c.base + clampi(station, 0, c.stations - 1) * c.sectors \
		+ posmod(sector, c.sectors)


## Which sector an angle falls in — θ from dorsal, wrapped.
func sector_of(name: StringName, theta: float) -> int:
	var c: CensusChain = _by_name[name]
	return int(floor(wrapf(theta, 0.0, TAU) / TAU * float(c.sectors))) % c.sectors


func station_of(name: StringName, t: float) -> int:
	var c: CensusChain = _by_name[name]
	return clampi(int(t * float(c.stations)), 0, c.stations - 1)


# ------------------------------------------------------------ derivations ----

## Surface radius of a column: the bone core plus every layer's effective
## thickness. Rings for rendering, capsules for contact and depth for wound
## resolution are all this one sum — the "one census" law in a single line.
func surface_radius(name: StringName, station: int, sector: int) -> float:
	return layer_radius(name, station, sector, 4)


## The same sum with only the innermost `layers` of the radial stack counted:
## 1 is bare bone, 2 adds muscle, 3 adds fat, 4 is the surface. The anatomy
## view's peel is four evaluations of this one function rather than four
## geometries (§10), and a wound walk that has spent the skin is asking for a
## radius of 3.
func layer_radius(name: StringName, station: int, sector: int,
		layers: int) -> float:
	var col: int = column(name, station, sector) * 4
	var c: CensusChain = _by_name[name]
	var r: float = c.core[station]
	for layer in clampi(layers, 0, 4):
		r += thickness[col + layer] * hp[col + layer]
	return r


## Mean surface radius around a station — the silhouette's width there, and
## the girth the load^0.4 relation reads.
func girth(name: StringName, station: int) -> float:
	var c: CensusChain = _by_name[name]
	var sum: float = 0.0
	for sec in c.sectors:
		sum += surface_radius(name, station, sec)
	return sum / float(c.sectors)


## Total mass — Σ wedge-shell volumes × tissue density × hp, plus the bone
## cores. The one scale in the game; nothing else may weigh a creature.
func mass() -> float:
	_derive()
	return _mass


## Centre of mass in body space (x pelvis → withers, y flank to flank,
## z height above the ground of the standing build).
func com() -> Vector3:
	_derive()
	return _com


## How hard the animal is to roll about its own fore-and-aft axis, through its
## own centre of mass — the second moment to `com`'s first, off the same walk
## and the same cells, so mass, weight and inertia can never be three opinions.
##
## Parallel axis, once, at the end: the walk accumulates about the body origin
## because it does not know the centre until it has finished. What it buys is
## real: a fat flank and a hanging leg are further from the axis than a spine
## is, so they resist a roll out of proportion to what they weigh, and a body
## bitten hollow through one side rolls easier because those cells stopped
## counting — the same argument that made weight a census reading in v1.
##
## Body units, as mass is: the roll dynamics divide torque by this and both
## sides carry the same scale.
func roll_inertia() -> float:
	_derive()
	return maxf(_roll_moment - _mass * (_com.y * _com.y + _com.z * _com.z),
		MIN_MASS)


## Where the weight is between the girdles: 0 at the pelvis, 1 at the
## withers. "Are the legs under the weight" is this fraction against [0, 1].
func along() -> float:
	_derive()
	return _com.x / maxf(trunk_length, 0.001)


## What the animal would weigh whole. Only the readouts want this — nothing in
## the body may be sized against a body that no longer exists.
func built_mass() -> float:
	_derive()
	return _built_mass


## How much of its own tissue the creature still has, by weight — exactly 1.0
## on an intact animal. The whole-body counterpart of `soundness`, and it is a
## reading rather than a state: nothing is stored anywhere saying a creature is
## wounded, so this cannot disagree with the cells.
func integrity() -> float:
	_derive()
	return clampf(_mass / maxf(_built_mass, MIN_MASS), 0.0, 1.0)


## What share of the body's weight one layer of tissue currently is. The shares
## add up to the animal rather than to the four toggles of a peel, because a
## bone core is bone whether or not the skeleton is being shown.
func layer_mass_share(layer: int) -> float:
	_derive()
	return _layer_mass[layer] / maxf(_mass, MIN_MASS)


## ...and how much of that layer is still standing, by volume: built against
## left. The other question, and it comes apart from the first — a torn-off
## limb takes skin and muscle and leaves the rest of the body proportionally
## bonier.
func layer_standing(layer: int) -> float:
	_derive()
	if _layer_built[layer] <= MIN_MASS:
		return 1.0
	return clampf(_layer_live[layer] / _layer_built[layer], 0.0, 1.0)


## The five muscle compartments (§7.3 B): summed effective muscle volume of
## each compartment's stations. Girdle-share, drive, bite force and spine
## power all derive from these — Locomotion ports onto them with a renamed
## input, and nothing reads muscle any other way.
func compartments() -> Dictionary:
	_derive()
	return _compartments


## How much of one chain's muscle is still answering, 0..1 — effective volume
## over built volume. Exactly 1.0 on an intact animal, which is the guarantee
## that a sound creature walks as though this reading did not exist; a haunch
## bitten hollow drops it, and the gait shortens that leg's stride and slows its
## swing without anything having decided to limp.
func soundness(name: StringName) -> float:
	_derive()
	var muscle: Vector2 = _chain_muscle.get(name, Vector2.ZERO)
	if muscle.y <= MIN_MASS:
		return 1.0
	return clampf(muscle.x / muscle.y, 0.0, 1.0)


## The same reading for a whole girdle: its limbs and the trunk muscle standing
## behind them. What the drive across a socket is a share of.
func girdle_soundness(fore: bool) -> float:
	_derive()
	var sum := Vector2.ZERO
	for chain in chains:
		if chain.kind != BodySchema.LIMB:
			continue
		if (chain.group == &"fore_limb") != fore:
			continue
		sum += _chain_muscle.get(chain.name, Vector2.ZERO) as Vector2
	if sum.y <= MIN_MASS:
		return 1.0
	return clampf(sum.x / sum.y, 0.0, 1.0)


## How much of the body's weight hangs beyond a station of the trunk, as a share
## of the whole — the counterweight a girdle has to push against. x is what is
## ahead of the fore girdle, y what is behind the hind girdle, and a jump comes
## out of the hind legs because of this rather than because of a rule.
func balance(fore_x: float, hind_x: float) -> Vector2:
	_derive()
	var ahead: float = 0.0
	var behind: float = 0.0
	for chain in chains:
		for st in chain.stations:
			var m: float = chain.st_mass[st]
			var at: float = chain.centre[st].x
			if at > fore_x:
				ahead += m
			elif at < hind_x:
				behind += m
	var total: float = maxf(_mass, MIN_MASS)
	return Vector2(ahead / total, behind / total)


## The soft-body feel as a material property (§7.5): fat over everything
## structural in the column. A fat flank dents and cushions; a bony shin is
## stiff and fragile.
func compliance(name: StringName, station: int, sector: int) -> float:
	var col: int = column(name, station, sector) * 4
	var c: CensusChain = _by_name[name]
	var fat: float = thickness[col + BodySchema.Layer.FAT] \
		* hp[col + BodySchema.Layer.FAT]
	var hard: float = c.core[station] \
		+ thickness[col + BodySchema.Layer.BONE] * hp[col + BodySchema.Layer.BONE] \
		+ thickness[col + BodySchema.Layer.MUSCLE] * hp[col + BodySchema.Layer.MUSCLE]
	return fat / maxf(hard, 0.0001)


## The tissue stack under a body address, outside-in — what a wound resolves
## through and what the anatomy probe quotes: [[layer, thickness, hp], …].
func tissue_at(name: StringName, t: float, theta: float) -> Array:
	var st: int = station_of(name, t)
	var sec: int = sector_of(name, theta)
	var col: int = column(name, st, sec) * 4
	var out: Array = []
	for layer in [BodySchema.Layer.SKIN, BodySchema.Layer.FAT,
			BodySchema.Layer.MUSCLE, BodySchema.Layer.BONE]:
		out.append([layer, thickness[col + layer], hp[col + layer]])
	return out


# ----------------------------------------------------------------- wounds ----

## Removes flesh from a wedge, outside-in — skin, then fat, then muscle, then
## bone, each layer soaking what its effective thickness can before the rest
## passes deeper. This is the tissue half of §6's wound resolution (feature
## intersection arrives with combat in Phase 5); `depth_px` is how deep the
## tooth or the test reaches, and the return is how much flesh actually came
## away. Writes hp on the same cells everything reads: the mass drops, the
## ring dents and the next bite lands deeper without another line of code.
func gouge(name: StringName, station: int, sector: int, depth_px: float) -> float:
	var col: int = column(name, station, sector) * 4
	var left: float = depth_px
	var taken: float = 0.0
	for layer in [BodySchema.Layer.SKIN, BodySchema.Layer.FAT,
			BodySchema.Layer.MUSCLE, BodySchema.Layer.BONE]:
		if left <= 0.0:
			break
		var cell: int = col + layer
		var eff: float = thickness[cell] * hp[cell]
		if eff <= 0.0:
			continue
		var bite: float = minf(eff, left)
		hp[cell] = maxf(hp[cell] - bite / thickness[cell], 0.0)
		taken += bite
		left -= bite
	if taken > 0.0:
		revision += 1
	return taken


## The whole of §6's wound resolution: the tissue depth-walk above, then the
## surviving depth intersected with the features standing in that (t, θ)
## neighbourhood. `depth_px` is what the tooth (or the test) is worth; what
## comes back is everything the wound did — flesh taken, organs damaged,
## vessels breached, nerves cut — for whoever keeps the consequences (Vitals).
##
## The wound *front* is measured as a fraction of the column's built flesh
## depth, outside-in, which is the coordinate the feature table quotes its
## depth bands in (0 the skin, 1 the bone core). Measured after the walk and
## against the built column rather than the standing one, so a second bite
## into the same wedge starts where the first left off and reaches features
## the first could not — the ribs protect the heart until the ribs are gone,
## and nothing anywhere says so.
func wound(name: StringName, station: int, sector: int,
		depth_px: float) -> Dictionary:
	var taken: float = gouge(name, station, sector, depth_px)
	var report: Dictionary = {
		"chain": name, "station": station, "sector": sector,
		"taken": taken, "organs": [], "breached": [], "severed": [],
	}
	# Where the front now stands, 0 at the built surface, 1 at the bone core.
	var col: int = column(name, station, sector) * 4
	var built: float = 0.0
	var left: float = 0.0
	for layer in 4:
		built += thickness[col + layer]
		left += thickness[col + layer] * hp[col + layer]
	if built <= MIN_MASS:
		return report
	var front: float = clampf((built - left) / built, 0.0, 1.0)
	if front <= 0.0:
		return report

	var c: CensusChain = _by_name[name]
	var t: float = (float(station) + 0.5) / float(c.stations)
	var theta: float = (float(sector) + 0.5) / float(c.sectors) * TAU
	var half_t: float = 0.5 / float(c.stations)
	var half_th: float = PI / float(c.sectors)

	for f: Dictionary in features:
		if f.get("chain", &"") != name:
			continue
		match f.get("feature", ""):
			"organ":
				var r: Vector2 = f["t_range"]
				if t < r.x - half_t or t > r.y + half_t:
					continue
				if _angle_gap(theta, f["theta"]) > float(f["spread"]) + half_th:
					continue
				var band: Vector2 = f["depth"]
				if front < band.x:
					continue
				# How much of the organ's own band the front has driven
				# through is what one wound costs it: a nick nicks, a bite
				# through the whole band destroys.
				var through: float = clampf((front - band.x)
					/ maxf(band.y - band.x, 0.01), 0.0, 1.0)
				if through <= 0.0:
					continue
				var was: float = float(f.get("hp", 1.0))
				f["hp"] = maxf(was - through, 0.0)
				if was > 0.0:
					(report["organs"] as Array).append(f)
			"vessel":
				if _path_reached(f, t, theta, front, half_t, half_th):
					(report["breached"] as Array).append(f)
			"nerve":
				if _path_reached(f, t, theta, front, half_t, half_th) \
						and not bool(f.get("cut", false)):
					f["cut"] = true
					(report["severed"] as Array).append(f)
	return report


## Whether a wound front at (t, θ, front) reaches a polyline feature: the
## wounded wedge has to stand over some span of the path, at its angle, and
## the front has to have passed its depth. One rule for vessels and nerves.
func _path_reached(f: Dictionary, t: float, theta: float, front: float,
		half_t: float, half_th: float) -> bool:
	var path: Array = f.get("path", [])
	for k in range(maxi(path.size() - 1, 1)):
		var a: Array = path[k]
		var b: Array = path[mini(k + 1, path.size() - 1)]
		var lo: float = minf(a[0], b[0]) - half_t
		var hi: float = maxf(a[0], b[0]) + half_t
		if t < lo or t > hi:
			continue
		var s: float = clampf((t - a[0]) / maxf(b[0] - a[0], 0.00001), 0.0, 1.0)
		if _angle_gap(theta, lerpf(a[1], b[1], s)) > half_th * 1.5:
			continue
		if front >= lerpf(a[2], b[2], s):
			return true
	return false


static func _angle_gap(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


# --------------------------------------------------------------- features ----

## Every feature whose body coordinates fall inside a chain's t range —
## organs by range overlap, vessels and nerves by any path point. The
## anatomy view's overlays render these directly; the wound walk intersects
## them; neither re-derives a thing.
func features_in(name: StringName, t_range: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in features:
		if f.get("chain", &"") != name:
			continue
		match f.get("feature", ""):
			"organ":
				var r: Vector2 = f["t_range"]
				if r.y >= t_range.x and r.x <= t_range.y:
					out.append(f)
			_:
				for point: Array in f.get("path", []):
					if point[0] >= t_range.x and point[0] <= t_range.y:
						out.append(f)
						break
	return out


# ------------------------------------------------------------ the one walk ----

## The single pass over the cells behind every cached derivation. Wedge-shell
## volume is closed-form (frustumless here — stations are prisms of `seg`):
## Δθ/2 · (r_out² − r_in²) · seg, centroid at the polar-wedge mean radius
## corrected by sinc(Δθ/2) for the chord. The bone cores ride the station
## centres. Also refreshes the per-station moments Poise bakes from, so the
## census and its reductions can never be two walks disagreeing.
func _derive() -> void:
	if _derived_rev == revision:
		return
	_derived_rev = revision

	var density: Array[float] = BodySchema.DENSITY
	var total: float = 0.0
	var moment := Vector3.ZERO
	var roll_moment: float = 0.0
	var fore_g: float = 0.0
	var hind_g: float = 0.0
	var epaxial: float = 0.0
	var neck_m: float = 0.0
	var jaw_m: float = 0.0

	_chain_muscle.clear()
	_layer_live.resize(4)
	_layer_built.resize(4)
	_layer_mass.resize(4)
	_layer_live.fill(0.0)
	_layer_built.fill(0.0)
	_layer_mass.fill(0.0)
	_built_mass = 0.0
	for chain in chains:
		var half: float = PI / float(chain.sectors)
		var shape: float = sin(half) / half
		var muscle := Vector2.ZERO
		chain.st_mass.fill(0.0)
		chain.st_rise.fill(0.0)
		chain.st_side.fill(0.0)
		for st in chain.stations:
			var centre: Vector3 = chain.centre[st]
			var up: Vector3 = chain.up[st]
			var lat: Vector3 = chain.lat[st]
			var st_mass: float = 0.0
			var st_rise: float = 0.0
			var st_side: float = 0.0

			# The core: a cylinder of bone at the axis.
			var core: float = chain.core[st]
			var core_mass: float = PI * core * core * chain.seg \
				* density[BodySchema.Layer.BONE]
			st_mass += core_mass
			moment += centre * core_mass
			roll_moment += (centre.y * centre.y + centre.z * centre.z) * core_mass
			# The core is bone that is not a cell — it cannot be bitten, so it
			# stands in both the built body and the standing one.
			_layer_mass[BodySchema.Layer.BONE] += core_mass
			_built_mass += core_mass

			for sec in chain.sectors:
				var theta: float = (float(sec) + 0.5) / float(chain.sectors) * TAU
				var dir: Vector3 = up * cos(theta) + lat * sin(theta)
				var col: int = (chain.base + st * chain.sectors + sec) * 4
				var r0: float = core
				var t01: float = (float(st) + 0.5) / float(chain.stations)
				# What this wedge's muscle was built as, before any of it was
				# spent — the denominator "how much of this limb still
				# answers" is a fraction of. Counted on the same shell the
				# effective volume below is, so an intact wedge reads exactly
				# one, and counted here so nothing walks the cells again.
				var raw: float = thickness[col + BodySchema.Layer.MUSCLE]
				if raw > 0.00001:
					var under: float = core + thickness[col + BodySchema.Layer.BONE]
					muscle.y += half * ((under + raw) * (under + raw)
						- under * under) * chain.seg
				# The shell each layer was *built* on, walked beside the shell it
				# actually stands on: a chewed inner layer pulls everything
				# outside it inward, so the two radii part company the moment
				# anything is bitten and the built one is the only honest
				# denominator for "how much of this tissue is left".
				var b0: float = core
				for layer in 4:
					var raw_t: float = thickness[col + layer]
					var b1: float = b0 + raw_t
					if raw_t > 0.00001:
						var built_vol: float = half * (b1 * b1 - b0 * b0) * chain.seg
						_layer_built[layer] += built_vol
						_built_mass += built_vol * density[layer]
					b0 = b1
					var eff: float = thickness[col + layer] * hp[col + layer]
					if eff <= 0.00001:
						continue
					var r1: float = r0 + eff
					var area2: float = r1 * r1 - r0 * r0
					var vol: float = half * area2 * chain.seg
					var m: float = vol * density[layer]
					var rbar: float = (2.0 / 3.0) * (r1 * r1 * r1 - r0 * r0 * r0) \
						/ maxf(area2, 0.00001) * shape
					var at: Vector3 = centre + dir * rbar
					moment += at * m
					roll_moment += (at.y * at.y + at.z * at.z) * m
					st_mass += m
					_layer_live[layer] += vol
					_layer_mass[layer] += m
					st_rise += (at.z - centre.z) * m
					st_side += (at.y - centre.y) * m
					if layer == BodySchema.Layer.MUSCLE:
						muscle.x += vol
						match chain.kind:
							BodySchema.TRUNK:
								epaxial += vol
							BodySchema.NECK:
								if t01 >= jaw_from:
									jaw_m += vol
								else:
									neck_m += vol
							BodySchema.LIMB:
								if chain.group == &"fore_limb":
									fore_g += vol
								else:
									hind_g += vol
							_:
								pass
					r0 = r1
			total += st_mass
			chain.st_mass[st] = st_mass
			if st_mass > MIN_MASS:
				chain.st_rise[st] = st_rise / st_mass
				chain.st_side[st] = st_side / st_mass
		_chain_muscle[chain.name] = muscle

	_mass = total
	_com = moment / maxf(total, MIN_MASS)
	_roll_moment = roll_moment
	_compartments = {
		&"fore_girdle": fore_g,
		&"hind_girdle": hind_g,
		&"epaxial": epaxial,
		&"neck": neck_m,
		&"jaw": jaw_m,
	}


## Per-station reduced moments for Poise — mass, rise off the station centre,
## lateral lean. Kept on the chain by `_derive`; this accessor exists so the
## bake never walks cells.
func station_moments(name: StringName) -> CensusChain:
	_derive()
	return _by_name[name]
