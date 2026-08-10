## The shapes the tissues take, derived from the lattice and nothing else.
##
## The lattice is the census: which boxes of which tissue the animal is made of.
## This file is the *form* those boxes add up to — the structures a tissue is
## organised into, each in the representation that tissue actually has:
##
##   * **Chains.** Every internal structure that is a continuous solid rather
##     than a heap — the vertebral column, each rib and girdle hoop, the limb
##     bone cores, the spinal cord, the aorta and carotid, the neurovascular
##     bundles — is gathered into a run of samples along its own axis, each
##     sample a centre, a thickness and the lattice cells it stands for. A bone
##     is its centreline and thickness profile; a major vessel or nerve is a
##     spline of the cells it threads. The specimen draws these as continuous
##     tubes instead of cell-by-cell, which is what a mineralised matrix and a
##     vessel wall look like — and a sample whose cells are gone breaks the
##     chain, so a fracture is a gap in the bone rather than a missing pebble.
##
##   * **Supply trees.** The plan's conduits say which regions the two networks
##     reach; these are the *local* branches inside each region, grown by space
##     colonisation over the lattice itself: attractor cells are sampled from
##     the tissues that demand supply — muscle and organs for blood, skin and
##     muscle for nerve — and branches walk cell to cell from the nearest point
##     of the tree toward them. Every branch vertex is a real lattice cell, so
##     the branches live inside the flesh, pose with it, and die with it.
##
##   * **Density fields.** Capillaries and nerve endings are not structures to
##     draw one by one; they are how much of each region's tissue asks to be
##     supplied. One number per region per network, read off the same demand
##     table the attractors are sampled with — the branch count already shows
##     it spatially, and the number is there for anything that wants to ask.
##
## Everything here is derived. It never counts mass, never takes damage of its
## own, and can be rebuilt from the lattice at any time without anything else
## noticing — which is the proof it is a representation and not a second anatomy.
class_name TissueForm
extends RefCounted

# --- chains -------------------------------------------------------------------
## Padding a sample's thickness gets past its members' own spread, so a tube
## covers the boxes it stands for out to their faces rather than their centres.
const RADIUS_PAD: float = AnatomyLattice.CELL * 0.55
## Share of a sample's member cells that must be gone before the sample is a
## break in the chain rather than a worn stretch of it.
const BREAK_SHARE: float = 0.5
## Sectors a hoop's ring is walked in. Enough that a rib reads as a curve; few
## enough that a sector always holds a cluster of cells rather than one.
const HOOP_SECTORS: int = 24

## How a chain's thickness is measured: the spread of a sample's members in the
## plane *across* the chain, because the spread along it is the sampling and not
## the structure.
const AXIS_LONG: int = 0
const AXIS_DOWN: int = 1
const AXIS_RING: int = 2

# --- supply -------------------------------------------------------------------
## What one cell of each tissue asks of the blood, relative to muscle. Organs
## outrank everything; fat and bone barely ask.
const VESSEL_DEMAND: Array[float] = [0.35, 0.18, 1.0, 0.10, 1.25, 0.55, 0.0]
## And of the nerves: skin is sense, muscle is command, fat is nearly silent.
const NERVE_DEMAND: Array[float] = [0.95, 0.05, 1.0, 0.05, 0.45, 0.0, 0.12]
## A cell is worth branching toward when it demands at least this much.
const ATTRACT_FLOOR: float = 0.4
## Most attractor cells one region contributes to one network, most lattice
## steps one branch may take toward its attractor, and how near a branch has to
## get before the attractor counts as reached.
const ATTRACTORS: int = 12
const BRANCH_STEPS: int = 16
const REACHED: float = AnatomyLattice.CELL * 1.3
## Cells the whole animal is sampled down to before regions cap their own share
## — what keeps an elephant's tree the same size as a lizard's.
const SAMPLE_BUDGET: int = 6000

const NETWORKS: int = 2
const NERVES: int = 0
const VESSELS: int = 1

# --- flat sample storage --------------------------------------------------------
## Every chain's samples, flattened. A chain is a [from, to) range over these.
var s_patch: PackedByteArray = PackedByteArray()
var s_station: PackedFloat32Array = PackedFloat32Array()
var s_lat: PackedFloat32Array = PackedFloat32Array()
var s_fore: PackedFloat32Array = PackedFloat32Array()
var s_lift: PackedFloat32Array = PackedFloat32Array()
var s_radius: PackedFloat32Array = PackedFloat32Array()
var s_canon: PackedVector3Array = PackedVector3Array()
## The member cell nearest the sample's centre — what a pick on the tube reads.
var s_rep: PackedInt32Array = PackedInt32Array()
## Where along its own chain the sample stands, for adjacency: consecutive
## buckets are joined, a skipped bucket is a gap the carve itself left.
var s_bucket: PackedInt32Array = PackedInt32Array()
## The sample's member cells, as a [from, to) range over `member_cells`.
var s_members: PackedInt32Array = PackedInt32Array()
var member_cells: PackedInt32Array = PackedInt32Array()
var sample_total: int = 0

## Chain c runs over samples [chain_from[c], chain_from[c + 1]).
var chain_from: PackedInt32Array = PackedInt32Array()
var chain_kind: PackedByteArray = PackedByteArray()
var chain_part: PackedByteArray = PackedByteArray()
var chain_count: int = 0

## Lattice cell -> its flat sample, or -1 where the cell is not part of a chain.
## This is the whole interface the draw pass needs: a cell that answers -1 is
## marked cell by cell as before, one that answers a sample is drawn as its tube.
var sample_of: PackedInt32Array = PackedInt32Array()

# --- supply trees ---------------------------------------------------------------
## Branch polylines per network: each branch is a run of lattice cell indices,
## and its region says whose delivery it fades with.
var branches: Array = [[], []]
var branch_region: Array = [PackedInt32Array(), PackedInt32Array()]
## Which branch each one grew out of, or -1 where it grew straight off a named
## run. A tree is only a tree because every branch of it is somebody's branch,
## and a drawing that leaves out a stem has to leave out everything hanging from
## it or it is drawing twigs floating in flesh. Parents always come first, so one
## pass in growth order is enough to answer it.
var branch_parent: Array = [PackedInt32Array(), PackedInt32Array()]
## How much supply each region's tissue asks for, 0..1 against the neediest
## region of this animal — the density field, one number per region per network.
var density: Array = [PackedFloat32Array(), PackedFloat32Array()]

var _built_of: int = 0


## Rebuilds if — and only if — the lattice it describes changed. Cheap to ask.
func ensure(lat: AnatomyLattice) -> bool:
	if lat == null or lat.count == 0:
		return false
	var sig: int = hash([lat.count, lat._signature])
	if sig == _built_of:
		return false
	_built_of = sig
	_build_chains(lat)
	_build_supply(lat)
	return true


## Whether a chain is a hoop — drawn with a looser join, because its ring is
## sampled in sectors its cells do not fill evenly.
func chain_ringed(c: int) -> bool:
	var part: int = chain_part[c]
	return part == AnatomyLattice.PART_RIB or part == AnatomyLattice.PART_GIRDLE


# ------------------------------------------------------------------- chains ----

## Which chain a cell belongs to and where along it, or x = -1 for a cell that
## is not part of any continuous structure. x groups cells into one chain with
## y, z orders them along it.
func _chain_slot(lat: AnatomyLattice, i: int) -> Vector3i:
	var part: int = lat.part[i]
	var patch: int = lat.patch_of[i]
	var p: Vector3 = lat.pos[i]
	match part:
		AnatomyLattice.PART_VERTEBRA, AnatomyLattice.PART_CORD, \
		AnatomyLattice.PART_AORTA:
			# Axial runs: one chain apiece, bucketed by ledger column.
			return Vector3i(part, 0, lat.cell_of[i] / BodyPlan.BODY_ROWS)
		AnatomyLattice.PART_ARTERY:
			if patch == 0:
				return Vector3i(part, 0, lat.cell_of[i] / BodyPlan.BODY_ROWS)
			# The bundle's vessel, down the limb: bucketed by height.
			return Vector3i(part, patch, floori(p.z / AnatomyLattice.CELL))
		AnatomyLattice.PART_LIMB_BONE, AnatomyLattice.PART_NERVE_BRANCH:
			return Vector3i(part, patch, floori(p.z / AnatomyLattice.CELL))
		AnatomyLattice.PART_RIB, AnatomyLattice.PART_GIRDLE:
			# A hoop: its own chain per column, walked around its ring by angle.
			# The seam at ±PI lands on a flank the span rule already leaves open.
			var col: int = lat.cell_of[i] / BodyPlan.BODY_ROWS
			var ang: float = atan2(p.z, p.y)
			var sector: int = clampi(int((ang + PI) / TAU * float(HOOP_SECTORS)),
				0, HOOP_SECTORS - 1)
			return Vector3i(part, col + 16, sector)
	return Vector3i(-1, 0, 0)


static func _axis_of(part: int, patch: int) -> int:
	match part:
		AnatomyLattice.PART_RIB, AnatomyLattice.PART_GIRDLE:
			return AXIS_RING
		AnatomyLattice.PART_LIMB_BONE, AnatomyLattice.PART_NERVE_BRANCH:
			return AXIS_DOWN
		AnatomyLattice.PART_ARTERY:
			return AXIS_LONG if patch == 0 else AXIS_DOWN
	return AXIS_LONG


func _build_chains(lat: AnatomyLattice) -> void:
	sample_of = PackedInt32Array()
	sample_of.resize(lat.count)
	sample_of.fill(-1)

	# chain key -> bucket -> members. Plain containers; this runs once a build.
	var groups: Dictionary = {}
	for i in lat.count:
		var t: int = lat.kind[i]
		if t != AnatomyLattice.BONE and t != AnatomyLattice.NERVE \
				and t != AnatomyLattice.VESSEL:
			continue
		var slot: Vector3i = _chain_slot(lat, i)
		if slot.x < 0:
			continue
		var key: int = slot.x * 1000 + slot.y
		var chain = groups.get(key)
		if chain == null:
			chain = {}
			groups[key] = chain
		var members = chain.get(slot.z)
		if members == null:
			members = []
			chain[slot.z] = members
		members.append(i)

	s_patch = PackedByteArray()
	s_station = PackedFloat32Array()
	s_lat = PackedFloat32Array()
	s_fore = PackedFloat32Array()
	s_lift = PackedFloat32Array()
	s_radius = PackedFloat32Array()
	s_canon = PackedVector3Array()
	s_rep = PackedInt32Array()
	s_bucket = PackedInt32Array()
	s_members = PackedInt32Array()
	member_cells = PackedInt32Array()
	chain_from = PackedInt32Array()
	chain_kind = PackedByteArray()
	chain_part = PackedByteArray()
	sample_total = 0
	chain_count = 0

	var keys: Array = groups.keys()
	keys.sort()
	for key in keys:
		var chain: Dictionary = groups[key]
		var buckets: Array = chain.keys()
		buckets.sort()
		chain_from.append(sample_total)
		var first: int = chain[buckets[0]][0]
		chain_kind.append(lat.kind[first])
		chain_part.append(lat.part[first])
		chain_count += 1
		var axis: int = _axis_of(int(lat.part[first]), int(lat.patch_of[first]))
		for bucket in buckets:
			_emit_sample(lat, int(bucket), chain[bucket], axis)
	chain_from.append(sample_total)


func _emit_sample(lat: AnatomyLattice, bucket: int, members: Array, axis: int) -> void:
	var centre := Vector3.ZERO
	var st: float = 0.0
	var la: float = 0.0
	var fo: float = 0.0
	var li: float = 0.0
	for i in members:
		centre += lat.pos[i]
		st += lat.station[i]
		la += lat.lat[i]
		fo += lat.fore[i]
		li += lat.lift[i]
	var n: float = float(members.size())
	centre /= n
	# Thickness is the members' spread across the chain — the structure's own
	# girth. The spread *along* it is the width of the sampling bucket, which is
	# a fact about ledger columns rather than about the bone.
	var ring_r: float = Vector2(centre.y, centre.z).length()
	var spread: float = 0.0
	var rep: int = members[0]
	var nearest: float = INF
	for i in members:
		var p: Vector3 = lat.pos[i]
		var d: float
		match axis:
			AXIS_DOWN:
				d = Vector2(p.x - centre.x, p.y - centre.y).length()
			AXIS_RING:
				d = Vector2(p.x - centre.x,
					Vector2(p.y, p.z).length() - ring_r).length()
			_:
				d = Vector2(p.y - centre.y, p.z - centre.z).length()
		spread = maxf(spread, d)
		var off: float = (p - centre).length()
		if off < nearest:
			nearest = off
			rep = i
	s_patch.append(lat.patch_of[rep])
	s_station.append(st / n)
	s_lat.append(la / n)
	s_fore.append(fo / n)
	s_lift.append(li / n)
	s_radius.append(maxf(spread * 0.8 + RADIUS_PAD, AnatomyLattice.CELL * 0.6))
	s_canon.append(centre)
	s_rep.append(rep)
	s_bucket.append(bucket)
	s_members.append(member_cells.size())
	for i in members:
		member_cells.append(i)
		sample_of[i] = sample_total
	sample_total += 1


## Sample s owns member_cells[s_members[s] .. member_end(s)).
func member_end(s: int) -> int:
	return s_members[s + 1] if s + 1 < sample_total else member_cells.size()


## Share of one sample's cells the damage ledger has taken. 0 on a sound bone,
## 1 where the teeth went clean through — past BREAK_SHARE the chain shows a gap.
func sample_gone(lat: AnatomyLattice, s: int) -> float:
	var from: int = s_members[s]
	var to: int = member_end(s)
	if to <= from:
		return 0.0
	var gone: int = 0
	for j in range(from, to):
		if lat.gone[member_cells[j]] != 0:
			gone += 1
	return float(gone) / float(to - from)


# ------------------------------------------------------------------- supply ----

## Attractor sampling, density readings and the space-colonisation walk, for
## both networks in one strided pass over the animal. Locals throughout — packed
## arrays read out of containers are copies, so nothing here accumulates into one.
func _build_supply(lat: AnatomyLattice) -> void:
	var stride: int = maxi(1, lat.count / SAMPLE_BUDGET)
	var ask_n := PackedFloat32Array()
	var ask_v := PackedFloat32Array()
	ask_n.resize(BodyPlan.REGIONS)
	ask_v.resize(BodyPlan.REGIONS)
	var seen := PackedInt32Array()
	seen.resize(BodyPlan.REGIONS)
	var want_n: Array = []
	var want_v: Array = []
	for _r in BodyPlan.REGIONS:
		want_n.append([])
		want_v.append([])

	var i: int = 0
	while i < lat.count:
		if lat.gone[i] == 0:
			var reg: int = lat.region[i]
			var t: int = lat.kind[i]
			seen[reg] += 1
			var dn: float = NERVE_DEMAND[t]
			var dv: float = VESSEL_DEMAND[t]
			ask_n[reg] += dn
			ask_v[reg] += dv
			if dn >= ATTRACT_FLOOR:
				(want_n[reg] as Array).append(i)
			if dv >= ATTRACT_FLOOR:
				(want_v[reg] as Array).append(i)
		i += stride

	var dens_n := PackedFloat32Array()
	var dens_v := PackedFloat32Array()
	dens_n.resize(BodyPlan.REGIONS)
	dens_v.resize(BodyPlan.REGIONS)
	var top_n: float = 0.0
	var top_v: float = 0.0
	for reg in BodyPlan.REGIONS:
		ask_n[reg] /= maxf(float(seen[reg]), 1.0)
		ask_v[reg] /= maxf(float(seen[reg]), 1.0)
		top_n = maxf(top_n, ask_n[reg])
		top_v = maxf(top_v, ask_v[reg])
	for reg in BodyPlan.REGIONS:
		dens_n[reg] = ask_n[reg] / top_n if top_n > 0.0 else 0.0
		dens_v[reg] = ask_v[reg] / top_v if top_v > 0.0 else 0.0
	density = [dens_n, dens_v]

	# Seeds: the chain samples of each network's own tissue, by region — the cord
	# and bundles for nerve; the aorta, carotid and bundles for blood.
	var seeds_n: Array = []
	var seeds_v: Array = []
	for _r in BodyPlan.REGIONS:
		seeds_n.append([])
		seeds_v.append([])
	for c in chain_count:
		var kind: int = chain_kind[c]
		if kind != AnatomyLattice.NERVE and kind != AnatomyLattice.VESSEL:
			continue
		var into: Array = seeds_n if kind == AnatomyLattice.NERVE else seeds_v
		for s in range(chain_from[c], chain_from[c + 1]):
			var rep: int = s_rep[s]
			(into[lat.region[rep]] as Array).append(rep)

	branches = [[], []]
	var region_n := PackedInt32Array()
	var region_v := PackedInt32Array()
	var stem_n := PackedInt32Array()
	var stem_v := PackedInt32Array()
	for reg in BodyPlan.REGIONS:
		_grow_region(lat, branches[NERVES], region_n, stem_n, reg, seeds_n[reg], want_n[reg])
		_grow_region(lat, branches[VESSELS], region_v, stem_v, reg, seeds_v[reg], want_v[reg])
	branch_region = [region_n, region_v]
	branch_parent = [stem_n, stem_v]


## Space colonisation over the lattice graph, one region of one network: each
## attractor pulls a branch out of the nearest point of the tree — seed runs
## first, branches already grown after them — one neighbouring cell at a time.
## Every vertex is a cell, so the tree lives in the flesh it supplies.
func _grow_region(lat: AnatomyLattice, out: Array, out_region: PackedInt32Array,
		out_parent: PackedInt32Array, reg: int, seeds: Array, want: Array) -> void:
	if seeds.is_empty() or want.is_empty():
		return
	var per: int = maxi(1, want.size() / ATTRACTORS)
	var nodes: Array = seeds.duplicate()
	# Which branch each node of the growing tree belongs to, -1 for the seeds
	# that are the named run itself. Carried alongside rather than looked up
	# afterwards, because by then the walk has forgotten where it started.
	var stem: PackedInt32Array = PackedInt32Array()
	stem.resize(nodes.size())
	stem.fill(-1)
	var a: int = 0
	while a < want.size():
		var attractor: int = want[a]
		a += per
		var goal: Vector3 = lat.pos[attractor]
		# Nearest point of the whole tree so far.
		var from: int = nodes[0]
		var parent: int = stem[0]
		var best: float = INF
		for j in nodes.size():
			var d: float = (lat.pos[nodes[j]] - goal).length_squared()
			if d < best:
				best = d
				from = nodes[j]
				parent = stem[j]
		if best <= REACHED * REACHED:
			continue
		# Walk toward the attractor, cell to cell, staying out of the skeleton —
		# a vessel or nerve threads flesh, it does not tunnel bone.
		var path := PackedInt32Array([from])
		var cur: int = from
		var closing: float = sqrt(best)
		for _step in BRANCH_STEPS:
			var next: int = -1
			var nearer: float = closing
			var base: int = cur * 6
			for k in 6:
				var nb: int = lat.neighbor[base + k]
				if nb < 0 or lat.kind[nb] == AnatomyLattice.BONE:
					continue
				var d: float = (lat.pos[nb] - goal).length()
				if d < nearer:
					nearer = d
					next = nb
			if next < 0:
				break
			cur = next
			closing = nearer
			path.append(cur)
			nodes.append(cur)
			stem.append(out.size())
			if closing <= REACHED:
				break
		if path.size() >= 2:
			out.append(path)
			out_region.append(reg)
			out_parent.append(parent)
