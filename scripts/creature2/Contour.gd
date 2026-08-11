## The skin — the census's flesh, placed on the solved chain (docs/V2_DESIGN.md
## §10, §4.3). SpecimenMesh's successor, and v2's only geometry.
##
## The construction is a ring skin, as v1's was: the body is sliced along each
## chain and each slice divided into the census's own sectors, and the reach of
## every sector is a cell. What has changed is where the answer comes from.
## v1 asked a cartesian lattice "how far out does the visible solid reach in
## this direction" and had to walk cells to find out; v2 reads
## `Corpus.surface_radius`, which is the bone core plus what each layer has
## left. So this file invents no shape and stores no shape: a radius is the
## census's, a frame is where the armature put the bone, and all that is owned
## here is the arithmetic between the two.
##
## That is what makes "what is hit is what is displayed" a property of the code
## rather than a discipline. A bite writes hp on a cell; the ring over that cell
## is thinner on the same tick; every view draws the thinner ring, because there
## is no second surface anywhere to update, and no carve to re-run — the cells
## never moved, only the frames did.
##
## Cost is rings and sectors, never volume. The topology is built once: which
## rings exist, which sticks they ride, which column each reads. A tick poses
## ~97 frames and evaluates ~730 surface points; the radii are re-read only when
## the census's `revision` moves, which is a wound and nothing else. An animal
## twice the size carves exactly the same mesh.
##
## Three levels of resolution meet here and it is worth being clear which is
## which: the armature's ~35 *nodes* are the physics controller, the census's
## fixed *stations* are where damage and mass are bookkept, and the *rings* this
## file lays down are neither — `BodySchema.RINGS_PER_STICK` of them per stick,
## interpolating the station radii, because smoothness belongs to the sampler
## and costs the simulation nothing.
class_name Contour
extends RefCounted

## How far past its last ring a free end's cone reaches, as a share of that
## ring's mean radius. A tail tip and a toe are cones; ported from v1's
## SpecimenMesh with its number.
const CONE: float = 0.8
## The head's is longer, because a snout is not a taper — it is a face. Sized
## off the Gait HUD mock, which draws the cat as a head circle of 8.5 and a
## muzzle 10 past it.
const SNOUT: float = 1.2

## Below this a tangent is no direction at all and the previous ring's frame
## stands — a chain folded exactly back on itself has no axis to speak of.
const MIN_TANGENT: float = 0.000001


## One chain's run of rings, plus everything about that chain a view needs and
## should not have to re-derive: its census resolution, which sectors are its
## flanks, and what order its sectors must be painted in.
class Band extends RefCounted:
	var name: StringName
	var kind: StringName
	var limb: bool = false
	var stations: int = 0
	var sectors: int = 0
	## Ring index of the first ring, and how many.
	var first: int = 0
	var count: int = 0
	## +1 where the census runs toward the head, −1 where it runs away from it
	## (the tail). The armature's plan frames all point cranially, so this is
	## what turns "forward along the animal" into "forward along this chain",
	## and it is the whole reason a wound on the right of the tail is drawn on
	## the right of the tail.
	var sense: float = 1.0
	## The armature node whose plan frame gives a limb its lateral — a leg hangs
	## below its socket and has no plan direction of its own worth trusting.
	var socket: int = -1
	## Whether the far end is free, and so closed with a cone, and how far past
	## the last ring that cone reaches.
	var tip: bool = false
	var cone: float = CONE
	## Sector paint order, ventral first. A ring seen from almost overhead
	## projects to a sliver: both its sides land on the same pixels, so the one
	## facing the camera has to go down last or the belly is drawn over the back.
	var order: PackedInt32Array = PackedInt32Array()
	## The two sectors on the flanks — the plan silhouette, and the shadow.
	var right: int = 0
	var left: int = 0
	## Banked trigonometry for the sector angles, so posing a ring is
	## multiplications.
	var cosines: PackedFloat32Array = PackedFloat32Array()
	var sines: PackedFloat32Array = PackedFloat32Array()


var corpus: Corpus
var armature: Armature

var bands: Array[Band] = []
var _by_name: Dictionary = {}

# ------------------------------------------------------------------ rings ----
# Flat arrays, ring-indexed. `a`/`b` are the armature nodes the ring rides
# between at fraction `u`; `p`/`q` are the neighbours the axial spline needs.

var rings: int = 0
var ring_band: PackedInt32Array = PackedInt32Array()
## Arc position along the chain, [0..1] — the census's own `t`.
var ring_t: PackedFloat32Array = PackedFloat32Array()
var ring_a: PackedInt32Array = PackedInt32Array()
var ring_b: PackedInt32Array = PackedInt32Array()
var ring_p: PackedInt32Array = PackedInt32Array()
var ring_q: PackedInt32Array = PackedInt32Array()
var ring_u: PackedFloat32Array = PackedFloat32Array()
## First index into the per-sector arrays, and the census column that sector 0
## of this ring reads (a column's sectors are consecutive, so sector s is
## `ring_column[r] + s`).
var ring_base: PackedInt32Array = PackedInt32Array()
var ring_column: PackedInt32Array = PackedInt32Array()
var ring_station: PackedInt32Array = PackedInt32Array()

## The posed frame: where the ring's centre is and which way its θ = 0 (dorsal)
## and θ = π/2 (right flank) point. Written by `pose`, read by everything.
var ring_centre: PackedVector3Array = PackedVector3Array()
var ring_axis: PackedVector3Array = PackedVector3Array()
var ring_up: PackedVector3Array = PackedVector3Array()
var ring_lat: PackedVector3Array = PackedVector3Array()

# ------------------------------------------------------------- per sector ----

## Surface radius per ring-sector, interpolated between the two census stations
## bracketing the ring. Re-read only when the census moves.
var radius: PackedFloat32Array = PackedFloat32Array()
## ...and where that puts the flesh in the world. The surface, posed.
var surface: PackedVector3Array = PackedVector3Array()

## Cone tip per band, valid where `band.tip`.
var tips: PackedVector3Array = PackedVector3Array()

var _radius_rev: int = -1
var _posed: bool = false


# ------------------------------------------------------------------ build ----

## Lays out the ring topology over a built census and a built armature. Rest
## data only: which sticks exist, how long they are, how the census is divided.
## Nothing here reads a pose, and re-running it is only ever a rebuild of the
## animal.
func build(p_corpus: Corpus, p_armature: Armature) -> void:
	corpus = p_corpus
	armature = p_armature
	bands.clear()
	_by_name.clear()

	# Where each axial node sits in the armature's solve order, so a ring can
	# name the neighbours its spline needs across a chain junction: the tail's
	# last ring is smoothed by the trunk, and the trunk's by the neck, because
	# to the solver they were always one line.
	var axial_at: Dictionary = {}
	for k in armature.axial.size():
		axial_at[armature.axial[k]] = k

	var per_stick: int = maxi(BodySchema.RINGS_PER_STICK, 1)
	var total_rings: int = 0
	var total_sectors: int = 0
	var per_chain: Array = []
	for census in corpus.chains:
		var segments: Array = _segments(armature.chain(census.name), axial_at)
		per_chain.append(segments)
		total_rings += segments.size() * per_stick + 1
		total_sectors += (segments.size() * per_stick + 1) * census.sectors

	rings = total_rings
	ring_band.resize(rings)
	ring_t.resize(rings)
	ring_a.resize(rings)
	ring_b.resize(rings)
	ring_p.resize(rings)
	ring_q.resize(rings)
	ring_u.resize(rings)
	ring_base.resize(rings)
	ring_column.resize(rings)
	ring_station.resize(rings)
	ring_centre.resize(rings)
	ring_axis.resize(rings)
	ring_up.resize(rings)
	ring_lat.resize(rings)
	radius.resize(total_sectors)
	surface.resize(total_sectors)
	tips.resize(corpus.chains.size())

	var r: int = 0
	var base: int = 0
	for ci in corpus.chains.size():
		var census: Corpus.CensusChain = corpus.chains[ci]
		var chain: Armature.Chain = armature.chain(census.name)
		var band := Band.new()
		band.name = census.name
		band.kind = census.kind
		band.limb = chain.limb
		band.stations = census.stations
		band.sectors = census.sectors
		band.first = r
		band.socket = chain.parent_node
		# A chain whose census runs away from the head reads the armature's
		# cranial frames backwards; the tail is the only one that does.
		band.sense = -1.0 if census.kind == BodySchema.TAIL else 1.0
		# Everything but the trunk ends in the open air: a snout, a tail tip,
		# four toes. The trunk's two ends are junctions with flesh either side.
		band.tip = census.kind != BodySchema.TRUNK
		band.cone = SNOUT if census.kind == BodySchema.NECK else CONE
		band.right = int(float(band.sectors) * 0.25)
		band.left = int(float(band.sectors) * 0.75)
		band.cosines.resize(band.sectors)
		band.sines.resize(band.sectors)
		var keyed: Array = []
		for s in band.sectors:
			var theta: float = (float(s) + 0.5) / float(band.sectors) * TAU
			band.cosines[s] = cos(theta)
			band.sines[s] = sin(theta)
			# The quad from sector s to s + 1 faces the angle between them.
			keyed.append([cos((float(s) + 1.0) / float(band.sectors) * TAU), s])
		keyed.sort_custom(func(x, y): return x[0] < y[0])
		band.order.resize(band.sectors)
		for i in keyed.size():
			band.order[i] = keyed[i][1]

		var segments: Array = per_chain[ci]
		var total: float = 0.0
		for seg in segments:
			total += seg[4]
		band.count = segments.size() * per_stick + 1
		var arc: float = 0.0
		for i in band.count:
			var j: int = mini(i / per_stick, segments.size() - 1)
			var u: float = float(i - j * per_stick) / float(per_stick)
			if i == band.count - 1:
				u = 1.0
			var seg: Array = segments[j]
			ring_band[r] = bands.size()
			ring_a[r] = seg[0]
			ring_b[r] = seg[1]
			ring_p[r] = seg[2]
			ring_q[r] = seg[3]
			ring_u[r] = u
			ring_t[r] = clampf(arc / maxf(total, 0.001), 0.0, 1.0)
			# Which station this ring reads for its cell state. Radii are
			# interpolated between stations (`refresh`) because the silhouette
			# is continuous; hp is not, because a wound has an edge and the
			# cell it stops at is the honest place to put it.
			var at: float = ring_t[r] * float(band.stations) - 0.5
			ring_station[r] = clampi(int(round(at)), 0, band.stations - 1)
			ring_column[r] = corpus.column(band.name, ring_station[r], 0)
			ring_base[r] = base
			base += band.sectors
			arc += seg[4] / float(per_stick)
			r += 1
		bands.append(band)
		_by_name[band.name] = band

	_radius_rev = -1
	_posed = false
	refresh()


## The sticks a chain's rings ride, as [a, b, before, after, length]. An axial
## chain takes its neighbours from the armature's solve order; a limb takes its
## own, and its girdle-offset stick is trunk rather than leg, so the flesh
## starts at the socket exactly where the census does.
func _segments(chain: Armature.Chain, axial_at: Dictionary) -> Array:
	var out: Array = []
	var rooted: bool = chain.parent_node < 0
	for j in chain.nodes.size():
		var a: int
		var b: int = chain.nodes[j]
		if rooted:
			if j == 0:
				continue
			a = chain.nodes[j - 1]
		else:
			if chain.limb and j == 0:
				continue  # the girdle offset: trunk interior, not limb flesh
			a = chain.parent_node if j == 0 else chain.nodes[j - 1]
		var length: float = armature.stick_bone[chain.sticks[j - 1 if rooted else j]]
		var before: int = a
		var after: int = b
		if not chain.limb and axial_at.has(a) and axial_at.has(b):
			var ka: int = axial_at[a]
			var kb: int = axial_at[b]
			var step: int = signi(kb - ka)
			if ka - step >= 0 and ka - step < armature.axial.size():
				before = armature.axial[ka - step]
			if kb + step >= 0 and kb + step < armature.axial.size():
				after = armature.axial[kb + step]
		out.append([a, b, before, after, length])
	return out


# ---------------------------------------------------------------- the pose ----

## Places every ring on the solved chain and evaluates the surface. The one
## per-tick cost of the skin, and it is a walk of rings — the census is not
## touched unless a wound moved it.
func pose() -> void:
	refresh()
	for bi in bands.size():
		var band: Band = bands[bi]
		var last: int = band.first + band.count - 1
		# Centres first, whole band, because the frames are read off them.
		# The axial line is splined through the armature's nodes (a back is a
		# curve between its stations, and v1's sampler already said so); a limb
		# is not, because an elbow is a corner and rounding it would draw a
		# bone bending.
		for r in range(band.first, last + 1):
			var u: float = ring_u[r]
			if band.limb:
				ring_centre[r] = armature.pos[ring_a[r]].lerp(armature.pos[ring_b[r]], u)
			else:
				ring_centre[r] = _spline(armature.pos[ring_p[r]], armature.pos[ring_a[r]],
					armature.pos[ring_b[r]], armature.pos[ring_q[r]], u)

		for r in range(band.first, last + 1):
			var ahead: Vector3 = ring_centre[mini(r + 1, last)]
			var behind: Vector3 = ring_centre[maxi(r - 1, band.first)]
			var axis: Vector3 = ahead - behind
			if axis.length_squared() < MIN_TANGENT:
				axis = ring_axis[r] if _posed else Vector3(1.0, 0.0, 0.0)
			axis = axis.normalized()
			# The lateral is the animal's own right, and it comes from the
			# armature's plan frame rather than from the ring line: a leg
			# hanging straight down has no plan direction, and a neck carried
			# steeply has one too foreshortened to trust.
			var flat: Vector2
			if band.limb:
				flat = armature.perp[band.socket]
			else:
				flat = armature.fwd[ring_a[r]].lerp(armature.fwd[ring_b[r]], ring_u[r])
				if flat.length_squared() < MIN_TANGENT:
					flat = armature.fwd[ring_a[r]]
				flat = Vector2(-flat.y, flat.x)
			var lat := Vector3(flat.x, flat.y, 0.0)
			lat -= axis * axis.dot(lat)
			if lat.length_squared() < MIN_TANGENT:
				lat = ring_lat[r] if _posed else Vector3(0.0, 1.0, 0.0)
			lat = lat.normalized()
			# Dorsal completes the frame, read along the chain's own heading —
			# which is why the tail's back is up and not down.
			var up: Vector3 = (axis * band.sense).cross(lat)
			ring_axis[r] = axis
			ring_lat[r] = lat
			ring_up[r] = up

			var at: int = ring_base[r]
			for s in band.sectors:
				surface[at + s] = ring_centre[r] \
					+ (up * band.cosines[s] + lat * band.sines[s]) * radius[at + s]

		if band.tip:
			tips[bi] = ring_centre[last] + ring_axis[last] * (mean_radius(last) * band.cone)
	_posed = true


## Re-reads the radii off the census. Keyed to the census's revision, so an
## ordinary tick does nothing at all here and a bite costs one walk of rings.
func refresh() -> void:
	if corpus == null or _radius_rev == corpus.revision:
		return
	_radius_rev = corpus.revision
	for band in bands:
		for r in range(band.first, band.first + band.count):
			var at: float = ring_t[r] * float(band.stations) - 0.5
			var lo: int = clampi(int(floor(at)), 0, band.stations - 1)
			var hi: int = clampi(lo + 1, 0, band.stations - 1)
			var f: float = clampf(at - float(lo), 0.0, 1.0)
			var base: int = ring_base[r]
			for s in band.sectors:
				radius[base + s] = lerpf(corpus.surface_radius(band.name, lo, s),
					corpus.surface_radius(band.name, hi, s), f)


# ----------------------------------------------------------------- reading ----

func band(name: StringName) -> Band:
	return _by_name.get(name)


## Which way a sector faces, in the world.
func direction(ring: int, sector: int) -> Vector3:
	var b: Band = bands[ring_band[ring]]
	return ring_up[ring] * b.cosines[sector] + ring_lat[ring] * b.sines[sector]


## The same sector's surface with the outer layers lifted off — bone only at 1,
## and the whole animal at 4. The peel view is four evaluations of this; there
## is no second geometry under the skin, only a smaller radius.
func peel(ring: int, sector: int, layers: int) -> Vector3:
	var b: Band = bands[ring_band[ring]]
	# Sampled exactly as the surface is, between the same two stations, so the
	# outermost peel and the drawn skin are the same point rather than nearly.
	var r: float = radius_at(b.name, ring_t[ring], sector, layers)
	return ring_centre[ring] + direction(ring, sector) * r


## The surface radius at an arbitrary body address, interpolated exactly as the
## rings are. What a probe asks when it wants the drawn radius without going
## through a ring, and what a contact test will ask in Phase 5.
func radius_at(name: StringName, t: float, sector: int, layers: int = 4) -> float:
	var b: Band = _by_name[name]
	var at: float = clampf(t, 0.0, 1.0) * float(b.stations) - 0.5
	var lo: int = clampi(int(floor(at)), 0, b.stations - 1)
	var hi: int = clampi(lo + 1, 0, b.stations - 1)
	var f: float = clampf(at - float(lo), 0.0, 1.0)
	return lerpf(corpus.layer_radius(name, lo, sector, layers),
		corpus.layer_radius(name, hi, sector, layers), f)


## Mean radius around a ring — its girth as drawn.
func mean_radius(ring: int) -> float:
	var b: Band = bands[ring_band[ring]]
	var sum: float = 0.0
	for s in b.sectors:
		sum += radius[ring_base[ring] + s]
	return sum / float(b.sectors)


## How many quads the skin is, all four chains' worth of tube plus the cones —
## the figure the cost claim is made about, and it does not move with the size
## of the animal or with what has been bitten out of it.
func facet_count() -> int:
	var n: int = 0
	for b in bands:
		n += (b.count - 1) * b.sectors
		if b.tip:
			n += b.sectors
	return n


## Catmull-Rom through four chain nodes. The same curve v1's `Spine.sample`
## drew frames on, which is why a v2 back reads like a v1 back between its
## far fewer stations.
static func _spline(before: Vector3, a: Vector3, b: Vector3, after: Vector3,
		u: float) -> Vector3:
	var u2: float = u * u
	var u3: float = u2 * u
	return 0.5 * (a * 2.0
		+ (b - before) * u
		+ (before * 2.0 - a * 5.0 + b * 4.0 - after) * u2
		+ (a * 3.0 - before - b * 3.0 + after) * u3)
