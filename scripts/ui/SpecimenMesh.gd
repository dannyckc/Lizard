## The specimen's surface, as a low-poly mesh skinned off the cell lattice.
##
## The mesh *is* the census. Every facet is a real quad of the animal's own
## surface, and the cell it was skinned off is carried on it — so hovering a
## facet reads a cell, peeling a tissue drops the surface onto the layer beneath
## it, and a bite is a crater in the geometry rather than a stain painted on it.
## Nothing here invents a shape: the only question asked of the lattice is "how
## far out does the visible solid reach in this direction", and the answer is a
## cell.
##
## The construction is a ring skin. The body is sliced at every station of its
## own ledger and each slice is divided into a fixed number of sectors around
## the long axis; a limb is sliced the same way around its own. In each sector
## the outermost cell that is still standing and still being shown wins, and its
## reach becomes a vertex. Consecutive rings are stitched into quads. A ring
## whose neighbour is empty is sealed: a taper closes into a cone, but an end the
## teeth cut closes flat, so a stump shows the cross-section it was bitten
## through rather than a whittled point.
##
## Two kinds of cell are not skinned, and both because a ring is the wrong shape
## for them. A cell belonging to a continuous structure — a vertebra, a rib, the
## aorta — is drawn by that structure's own tube; thrown a ring skin instead, a
## rib cage comes out as a barrel, which is a solid the animal has not got. And a
## ring with too few sectors to close is not closed: a place where the animal is
## two cells wide has no hoop in it, and a loop drawn through three points is a
## triangle claiming to be a leg. Neither sort is dropped — the first goes to the
## chains and the second to `loose`, and the specimen draws both. What this file
## will not do is invent a surface; what it will not do either is leave flesh off
## the slab for being awkward.
##
## Two things fall out of doing it this way, and both are the point:
##
##   * **It is cheap and it is bounded.** A lizard and an elephant carve the same
##     few hundred facets, because the ring grid is a statement about the surface
##     rather than about the number of cells behind it. The old surface was one
##     quad per exposed cell face and grew without limit with the animal.
##   * **It is honest.** The reach in every sector is a standing, shown cell, so
##     the silhouette is the real silhouette, a peeled specimen is genuinely the
##     shape of the muscle under the skin, and a crater is where the flesh
##     actually went.
##
## Everything here is stated in the lattice's own posing coordinates — patch,
## station, and the three offsets a cell carries — so the finished mesh poses
## through exactly the same per-station frames the cells do. It bends with the
## animal for free and there is no second geometry anywhere.
class_name SpecimenMesh
extends RefCounted

## Sectors a ring is divided into. The body carries more than a limb because it
## is the thing being looked at, and because a limb is only a couple of cells
## across: dividing a leg fourteen ways asks the lattice for detail it does not
## have, and the ring comes back full of holes.
const BODY_SECTORS: int = 14
const LIMB_SECTORS: int = 6

## Most rings a patch may be sliced into. The spacing is a cell wherever the
## animal is small enough for that, and stretches on a big one — so a lizard is
## ringed at its own resolution and an elephant carves the same mesh rather than
## a hundred times as much of it.
##
## The count is a statement about how the specimen should *read* rather than
## about how finely it could be cut. Rings a cell apart make a tube finely
## enough tessellated that the facets vanish, and a surface whose facets vanish
## is back to being a smooth wash with nothing to tell one plane from the next.
## Two dozen down the body is the density at which the planes are legible as
## planes.
const BODY_BANDS: int = 26
const LIMB_BANDS: int = 9

const BUCKETS: int = BODY_BANDS * BODY_SECTORS + 4 * LIMB_BANDS * LIMB_SECTORS
const BANDS: int = BODY_BANDS + 4 * LIMB_BANDS

## How far past the winning cell's own centre its vertex is pushed, in cells. Half
## a cell puts the surface on the cell's outer face, which is where the animal
## actually ends.
const OUT: float = 0.5
## How far a tapering end's cone reaches past its last ring, as a share of that
## ring's own mean radius. A snout and a tail tip are cones; nothing else is.
const CONE: float = 0.8
## Least sectors of a ring that must have found a cell of their own before the
## ring is worth closing at all, as a share of the ring, with an absolute floor
## of three: below three points there is no loop to draw.
##
## It used to be nearly half the ring, and that was a statement about the wrong
## thing. A tail tip and an ankle are genuinely three or four cells around, so
## their rings never met the share, so the last stations of every tail and the
## bottom of every leg were dropped out of the mesh and drawn as loose cells —
## which is why the specimen's tail ended in a shower of beads with a sealed cone
## some way above it. The flesh was there and the surface was not.
##
## Three points *are* a cross-section when the animal is two cells wide, and the
## sectors they leave empty are filled from their neighbours rather than opened
## (see `_close_ring`), so what comes out is a tapering tube rather than a
## triangle. A ring with real flesh missing is still dropped — that is what the
## floor of three is for — and the cells go on to `loose` as they always did.
const RING_ENOUGH: float = 0.25

# --- vertices, in the lattice's own posing coordinates -------------------------
var v_patch := PackedByteArray()
var v_station := PackedFloat32Array()
var v_lat := PackedFloat32Array()
var v_fore := PackedFloat32Array()
var v_lift := PackedFloat32Array()
var v_count: int = 0

# --- facets -------------------------------------------------------------------
## Four corner indices apiece. A cap triangle repeats its last corner, so every
## facet is one layout and the draw pass has no special case.
var f_v := PackedInt32Array()
## The lattice cell this facet was skinned off — what the hover reads, what the
## ink and the wear are taken from.
var f_cell := PackedInt32Array()
## Which nested shell it belongs to, for the X-ray; 0 is the outermost.
var f_shell := PackedByteArray()
## 1 where the facet is a section's own cut face, which is lit flat rather than
## by its own turn: a cut is a plane through the animal, not a piece of its skin.
var f_flat := PackedByteArray()
## 1 where the cell the facet stands on is up against flesh the teeth have taken
## — the rim of a crater, which is the one place an open wound can be seen.
var f_raw := PackedByteArray()
var count: int = 0

## Surface cells the ring skin could not make a facet of: the outermost cell of
## a sector on a ring too thin to close. They are still the outside of the
## animal, so the specimen draws them cell by cell — see `AnatomyView._loose_pass`
## — and nothing a layer is showing is left off the slab for being awkward.
var loose := PackedInt32Array()

# Reused between builds; sized once and refilled.
var _best_r := PackedFloat32Array()
var _best_i := PackedInt32Array()
var _best_raw := PackedByteArray()
var _vert_of := PackedInt32Array()
var _band_n := PackedInt32Array()
var _band_s := PackedFloat32Array()
var _band_lift := PackedFloat32Array()
var _band_r := PackedFloat32Array()
var _band_cut := PackedByteArray()
## Where each patch's rings start along its own long axis, and how far apart they
## stand — a cell wherever the animal is small enough for that, stretched on a
## big one so the mesh stays the same size whatever is on the slab.
var _axis_lo := PackedFloat32Array()
var _axis_step := PackedFloat32Array()


func _init() -> void:
	_best_r.resize(BUCKETS)
	_best_i.resize(BUCKETS)
	_best_raw.resize(BUCKETS)
	_vert_of.resize(BUCKETS)
	_band_n.resize(BANDS)
	_band_s.resize(BANDS)
	_band_lift.resize(BANDS)
	_band_r.resize(BANDS)
	_band_cut.resize(BANDS)
	_axis_lo.resize(AnatomyLattice.PATCH_KEYS.size())
	_axis_step.resize(AnatomyLattice.PATCH_KEYS.size())


## Where a patch's buckets start, and how the patch is divided.
static func _bucket_base(pk: int) -> int:
	return 0 if pk == 0 \
		else BODY_BANDS * BODY_SECTORS + (pk - 1) * LIMB_BANDS * LIMB_SECTORS


static func _band_base(pk: int) -> int:
	return 0 if pk == 0 else BODY_BANDS + (pk - 1) * LIMB_BANDS


static func sectors_of(pk: int) -> int:
	return BODY_SECTORS if pk == 0 else LIMB_SECTORS


static func bands_of(pk: int) -> int:
	return BODY_BANDS if pk == 0 else LIMB_BANDS


## Skins the mesh.
##
## `surfaces` is one list of surface cells per shell, outermost first — the cells
## that stand on the boundary of what that shell is showing — and `plane_cells`
## are the cells standing in a section plane, which are laid as the cut face
## itself.
##
## `chained` is the lattice's cell-to-chain-sample table: a cell that answers a
## sample belongs to a continuous structure — a vertebra, a rib, the aorta — and
## is skinned by that structure's own tube rather than here. It matters only when
## such a tissue is the outermost thing being shown, and then it matters
## entirely: a ring skin thrown over a rib cage joins one rib to the next and
## produces a barrel, which is a solid the animal does not have. A skeleton
## should look like a skeleton at every setting of the toggles, and the way to
## get that is to let the ribs be ribs. Everything else — the skull, the flesh,
## the organs — is a heap of cells with a surface, and is skinned here.
##
## `skin_on` says the hide is being worn, and it decides what happens to a
## chained cell that is *sheathed* — a vertebra at a tail tip, the bone at an
## ankle, anywhere the animal is too thin to hold a cell of skin over its own
## frame. Such a cell is being seen as hide, so while the hide is on it is
## skinned here like any flesh, and its structure's tube is left to the views
## that have actually uncovered it. Left to the tube instead, the ankle wore its
## own skeleton outside its skin: a bone-coloured lump on every joint of an
## otherwise whole animal.
func build(lat: AnatomyLattice, surfaces: Array, plane_cells: PackedInt32Array,
		slice_axis: int, chained: PackedInt32Array = PackedInt32Array(),
		skin_on: bool = false) -> void:
	v_count = 0
	count = 0
	loose.resize(0)
	v_patch.resize(0)
	v_station.resize(0)
	v_lat.resize(0)
	v_fore.resize(0)
	v_lift.resize(0)
	f_v.resize(0)
	f_cell.resize(0)
	f_shell.resize(0)
	f_flat.resize(0)
	f_raw.resize(0)
	for s in surfaces.size():
		_skin(lat, surfaces[s], s, chained, skin_on)
	if slice_axis >= 0 and plane_cells.size() > 0:
		_cut_faces(lat, plane_cells, slice_axis)


## One shell: bucket its surface cells into rings, keep the outermost of each
## sector, close the gaps the lattice was too coarse to fill, and stitch what is
## left into quads.
func _skin(lat: AnatomyLattice, surface: PackedInt32Array, shell: int,
		chained: PackedInt32Array, skin_on: bool) -> void:
	_best_r.fill(-1.0)
	_best_i.fill(-1)
	_best_raw.fill(0)
	_vert_of.fill(-1)
	_band_n.fill(0)
	_band_s.fill(0.0)
	_band_lift.fill(0.0)
	_band_r.fill(0.0)
	_band_cut.fill(0)

	# Hoisted: a property read per cell per array is thousands of property reads.
	var patch_of: PackedByteArray = lat.patch_of
	var station: PackedFloat32Array = lat.station
	var side: PackedFloat32Array = lat.lat
	var ahead: PackedFloat32Array = lat.fore
	var up: PackedFloat32Array = lat.lift
	var where: PackedVector3Array = lat.pos

	# Where each patch begins and ends along its own long axis, and how finely it
	# can therefore be ringed. Rings are cut on the *axis* rather than on the
	# ledger's stations because the lattice is carved in slices along exactly this
	# axis: cut it anywhere else and whole rings come up empty wherever the
	# stations run faster than the cells do — which on a head, where eight
	# stations cover four slices, is most of them.
	var lo := PackedFloat32Array()
	var hi := PackedFloat32Array()
	lo.resize(AnatomyLattice.PATCH_KEYS.size())
	hi.resize(AnatomyLattice.PATCH_KEYS.size())
	lo.fill(INF)
	hi.fill(-INF)
	# Whether the chain table was handed over at all: without it every cell is
	# skinned, which is what the tests that build a mesh on its own get.
	var chains: bool = chained.size() == lat.count
	# A sheathed chained cell is being seen as hide while the hide is on, so it
	# is skinned here rather than left to its tube — see the note on `build`.
	var sheath: PackedByteArray = lat.sheathed
	var hide: bool = skin_on and sheath.size() == lat.count
	for i in surface:
		if chains and chained[i] >= 0 and not (hide and sheath[i] != 0):
			continue
		var pk: int = patch_of[i]
		var u: float = where[i].x if pk == 0 else -where[i].z
		lo[pk] = minf(lo[pk], u)
		hi[pk] = maxf(hi[pk], u)
	for pk in AnatomyLattice.PATCH_KEYS.size():
		var span: float = hi[pk] - lo[pk]
		_axis_lo[pk] = lo[pk]
		_axis_step[pk] = AnatomyLattice.CELL if span <= 0.0 \
			else maxf(AnatomyLattice.CELL, span / float(bands_of(pk) - 1))

	for i in surface:
		if chains and chained[i] >= 0 and not (hide and sheath[i] != 0):
			continue
		var pk: int = patch_of[i]
		var sectors: int = BODY_SECTORS if pk == 0 else LIMB_SECTORS
		var u: float = where[i].x if pk == 0 else -where[i].z
		var band: int = clampi(int((u - _axis_lo[pk]) / _axis_step[pk]),
			0, bands_of(pk) - 1)
		# The two axes the ring turns in: across and up on the body, across and
		# fore-and-aft on a limb, because that is the plane each one's own long
		# axis is perpendicular to.
		var ax: float = side[i]
		var ay: float = up[i] if pk == 0 else ahead[i]
		var r: float = sqrt(ax * ax + ay * ay)
		var sector: int = int(fposmod(atan2(ax, ay), TAU) / TAU * float(sectors)) % sectors
		var at: int = _bucket_base(pk) + band * sectors + sector
		if r <= _best_r[at]:
			continue
		_best_r[at] = r
		_best_i[at] = i

	for pk in AnatomyLattice.PATCH_KEYS.size():
		var bands: int = bands_of(pk)
		var sectors: int = sectors_of(pk)
		var bucket_base: int = _bucket_base(pk)
		var band_base: int = _band_base(pk)
		for band in bands:
			var row: int = bucket_base + band * sectors
			var here: int = band_base + band
			var found: int = 0
			for sector in sectors:
				if _best_i[row + sector] >= 0:
					found += 1
			if found == 0:
				continue
			# Too little of the ring to be a ring. A limb's ankle and a tail's
			# last slice are genuinely two or three cells around, and a loop
			# drawn through three points is a triangle claiming to be a leg.
			#
			# The cells are not dropped for it, though — they are flesh that is
			# there, and a specimen that leaves out the flesh it cannot make a
			# ring of is a specimen with holes in it wherever a tissue thins out.
			# They are handed on as loose cells and drawn one by one, which is
			# the honest picture of a place where the animal is two cells wide.
			#
			# The floor is three on the trunk and nothing at all on a limb, and
			# the split is about what the tissues there are shaped like. On the
			# trunk a two-cell band can be two unrelated pockets on opposite
			# flanks, and a hoop drawn through those invents a surface clean
			# across the animal. Everything on a limb, though, is genuinely
			# wrapped around the limb's own axis — the skin, the fat and the
			# muscle are annular by construction and the bone is chained away —
			# so a ring recovered from however few cells a band has is a slim
			# hoop of a genuinely hooped thing. That is what turned a peeled
			# leg's fat from a scatter of boxes into the sleeve it actually is.
			if pk == 0 and found < maxi(int(float(sectors) * RING_ENOUGH), 3):
				for sector in sectors:
					if _best_i[row + sector] >= 0:
						loose.append(_best_i[row + sector])
						_best_i[row + sector] = -1
				continue
			if found < sectors:
				_close_ring(row, sectors)
			# Ring aggregates, off the cells the sectors ended up standing on.
			for sector in sectors:
				var i: int = _best_i[row + sector]
				if i < 0:
					continue
				_band_n[here] += 1
				_band_s[here] += station[i]
				_band_lift[here] += up[i]
				_band_r[here] += _best_r[row + sector]
				# Whether this piece of surface is the rim of a crater. Asked once
				# per winning cell rather than once per facet, and it is the only
				# question in the build that reads the neighbour table.
				if _touches_gone(lat, i):
					_best_raw[row + sector] = 1
					_band_cut[here] = 1
			var n: int = _band_n[here]
			if n == 0:
				continue
			_band_s[here] /= float(n)
			_band_lift[here] /= float(n)
			_band_r[here] /= float(n)

	# The vertices: each sector's own reach, on the sector's own heading rather
	# than on its cell's, so a ring comes out a clean polygon.
	for pk in AnatomyLattice.PATCH_KEYS.size():
		var bands: int = bands_of(pk)
		var sectors: int = sectors_of(pk)
		var bucket_base: int = _bucket_base(pk)
		var band_base: int = _band_base(pk)
		var step: float = TAU / float(sectors)
		for band in bands:
			var here: int = band_base + band
			if _band_n[here] == 0:
				continue
			var row: int = bucket_base + band * sectors
			for sector in sectors:
				if _best_i[row + sector] < 0:
					continue
				var r: float = _best_r[row + sector] + AnatomyLattice.CELL * OUT
				var angle: float = (float(sector) + 0.5) * step
				# The ring turns in the plane its patch's long axis is
				# perpendicular to: across and up on the body, across and
				# fore-and-aft on a limb — the same pair the sectors were
				# measured in.
				var across: float = r * sin(angle)
				var along: float = r * cos(angle)
				_vert_of[row + sector] = _vertex(pk, _band_s[here], across,
					0.0 if pk == 0 else along, along if pk == 0 else _band_lift[here])

	# The skin itself: a quad between every pair of rings that follow one another.
	#
	# *Follow*, not neighbour. A band with no cells in it is a place the lattice
	# had nothing to say, not a place the animal stops — a station whose cells all
	# went to a chain, or a stretch where the rings are cut finer than the cells
	# are. Stitching strictly to `band + 1` tore the tube open at every one of
	# them and then sealed both raw ends into cones, which is how a continuous
	# tail came out as a string of separate pieces. So the ring after this one is
	# the next one that exists, and the two ends of the run are the only places
	# anything is sealed.
	for pk in AnatomyLattice.PATCH_KEYS.size():
		var bands: int = bands_of(pk)
		var sectors: int = sectors_of(pk)
		var bucket_base: int = _bucket_base(pk)
		var band_base: int = _band_base(pk)
		var run: Array[int] = []
		for band in bands:
			if _band_n[band_base + band] > 0:
				run.append(band)
		if run.is_empty():
			continue
		for j in range(run.size() - 1):
			var near: int = bucket_base + run[j] * sectors
			var far: int = bucket_base + run[j + 1] * sectors
			for sector in sectors:
				var next: int = (sector + 1) % sectors
				var a: int = _vert_of[near + sector]
				var b: int = _vert_of[near + next]
				var c: int = _vert_of[far + next]
				var d: int = _vert_of[far + sector]
				if a < 0 or b < 0 or c < 0 or d < 0:
					continue
				_face(a, b, c, d, _best_i[near + sector], shell, 0,
					_best_raw[near + sector])
		# ...and the seals, at the two ends of the run and nowhere else.
		_seal(pk, run[0], -1, bucket_base + run[0] * sectors, sectors, shell)
		var last: int = run[run.size() - 1]
		_seal(pk, last, 1, bucket_base + last * sectors, sectors, shell)


## Fills the sectors of one ring that found no cell of their own.
##
## A leg two cells across has fewer cells around it than the ring has sectors, and
## a gap left open would tear a hole down the length of it. So an empty sector
## takes the reach its neighbours have, and stands on the nearer of their cells —
## which is a statement about the lattice being coarser than the ring rather than
## about the animal, and is why it fills rather than opens.
##
## Only ever reached on a ring that already has most of its sectors: a ring with
## real flesh missing was dropped before this, and a crater is a shorter reach
## rather than an absent one.
func _close_ring(row: int, sectors: int) -> void:
	for sector in sectors:
		if _best_i[row + sector] >= 0:
			continue
		var back: int = 0
		var ahead: int = 0
		while back < sectors - 1 \
				and _best_i[row + (sector - back - 1 + sectors * 2) % sectors] < 0:
			back += 1
		while ahead < sectors - 1 and _best_i[row + (sector + ahead + 1) % sectors] < 0:
			ahead += 1
		var a: int = row + (sector - back - 1 + sectors * 2) % sectors
		var b: int = row + (sector + ahead + 1) % sectors
		if _best_i[a] < 0 or _best_i[b] < 0:
			continue
		var t: float = float(back + 1) / float(back + ahead + 2)
		_best_r[row + sector] = lerpf(_best_r[a], _best_r[b], t)
		_best_i[row + sector] = _best_i[a] if back <= ahead else _best_i[b]


## Closes one end of the mesh. A taper reaches on into a cone, so a snout has a
## nose and a tail has a tip; an end the teeth cut closes flat on itself, so a
## stump shows the section it was bitten through. Limbs always close flat — a
## foot is blunt, and a leg's own long axis is not one of the offsets a cell
## carries, so there is nothing to reach along.
func _seal(pk: int, band: int, dir: int, row: int, sectors: int, shell: int) -> void:
	var here: int = _band_base(pk) + band
	# The body reaches on along its own long axis, which is the offset a cell
	# carries fore and aft; a limb's runs through the stations instead, so there
	# is nothing to reach along and the cap is the ring's own centre.
	var reach: float = 0.0
	if pk == 0 and _band_cut[here] == 0:
		reach = _band_r[here] * CONE * float(dir)
	var pole: int = _vertex(pk, _band_s[here], 0.0, reach,
		0.0 if pk == 0 else _band_lift[here])
	for sector in sectors:
		var a: int = _vert_of[row + sector]
		var b: int = _vert_of[row + (sector + 1) % sectors]
		if a < 0 or b < 0:
			continue
		# Wound the way the quads are, so the cap's own facing agrees with the
		# skin it closes: reversed on the near end, where the ring is being seen
		# from the other side.
		if dir < 0:
			_face(b, a, pole, pole, _best_i[row + sector], shell, 0,
				_best_raw[row + sector])
		else:
			_face(a, b, pole, pole, _best_i[row + sector], shell, 0,
				_best_raw[row + sector])


## The cut face of a section: the cells standing in the plane, laid flat on it.
## Drawn in the two offsets the slice axis leaves free, so the face is a real
## piece of the plane through the animal's own frame rather than a page effect.
func _cut_faces(lat: AnatomyLattice, plane_cells: PackedInt32Array,
		slice_axis: int) -> void:
	var half: float = AnatomyLattice.CELL * 0.5
	for i in plane_cells:
		var pk: int = lat.patch_of[i]
		# A limb sliced across its own length has no second offset to spread the
		# face over — its long axis is the station — so it keeps the hull it
		# already has and no cut face is laid.
		if slice_axis == 0 and pk != 0:
			continue
		var s: float = lat.station[i]
		var side: float = lat.lat[i]
		var ahead: float = lat.fore[i]
		var up: float = lat.lift[i]
		var v0: int = 0
		var v1: int = 0
		var v2: int = 0
		var v3: int = 0
		match slice_axis:
			0:
				v0 = _vertex(pk, s, side - half, ahead, up - half)
				v1 = _vertex(pk, s, side + half, ahead, up - half)
				v2 = _vertex(pk, s, side + half, ahead, up + half)
				v3 = _vertex(pk, s, side - half, ahead, up + half)
			1:
				v0 = _vertex(pk, s, side, ahead - half, up - half)
				v1 = _vertex(pk, s, side, ahead + half, up - half)
				v2 = _vertex(pk, s, side, ahead + half, up + half)
				v3 = _vertex(pk, s, side, ahead - half, up + half)
			_:
				v0 = _vertex(pk, s, side - half, ahead - half, up)
				v1 = _vertex(pk, s, side + half, ahead - half, up)
				v2 = _vertex(pk, s, side + half, ahead + half, up)
				v3 = _vertex(pk, s, side - half, ahead + half, up)
		_face(v0, v1, v2, v3, i, 0, 1, 1 if _touches_gone(lat, i) else 0)


## Whether a cell stands against flesh the ledger has taken — which is what tells
## a bitten end from one the animal simply tapers to.
static func _touches_gone(lat: AnatomyLattice, i: int) -> bool:
	var base: int = i * 6
	for k in 6:
		var n: int = lat.neighbor[base + k]
		if n >= 0 and lat.gone[n] != 0:
			return true
	return false


func _vertex(pk: int, station: float, side: float, ahead: float, up: float) -> int:
	v_patch.append(pk)
	v_station.append(station)
	v_lat.append(side)
	v_fore.append(ahead)
	v_lift.append(up)
	v_count += 1
	return v_count - 1


func _face(a: int, b: int, c: int, d: int, cell: int, shell: int, flat: int,
		raw: int) -> void:
	f_v.append(a)
	f_v.append(b)
	f_v.append(c)
	f_v.append(d)
	f_cell.append(cell)
	f_shell.append(shell)
	f_flat.append(flat)
	f_raw.append(raw)
	count += 1
