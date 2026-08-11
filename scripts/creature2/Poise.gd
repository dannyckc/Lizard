## Where the animal's weight actually is, and whether it is over its feet —
## Plumb's successor, reading the one census (docs/V2_DESIGN.md §7.2).
##
## v1's Plumb walked a quarter-million cartesian cells and reduced them to
## seventy-odd posed columns. v2's census is already small and already in
## body space, so the reduction is even shorter: the cells bake to a mass, a
## rise and a lean per *armature node* — thirty-five numbers — and posing the
## centre of mass each tick is one weighted mean of node positions the solver
## has just placed. A heavy head genuinely droops the neck chain, because the
## bake writes the same per-node masses the Z channel's droop walk reads: the
## census is the owner, the armature holds the baked copy.
##
## The bake is keyed to `Corpus.revision`, so an ordinary tick bakes nothing;
## a bite re-bakes once and the weight moves — a creature bitten hollow
## through one haunch carries its weight forward and to the other side,
## because the cells that were over there stopped weighing anything. That was
## the whole argument for counting weight off the census in v1, and it ports
## with the arithmetic.
##
## The support half is ported from Plumb outright: the convex hull of the
## planted feet grown by the foot's own patch of ground, the signed distance
## from the plumb line to its boundary, and deliberately *not* a pass/fail —
## a walking animal is out over its own edge several times a second, and the
## consumers decide what a distance is worth.
class_name Poise
extends RefCounted

## How much of its own support a body is expected to keep the line inside of
## before anything calls the stance implausible — a share of the support's
## own radius, so a wide stance earns its wider absolute margin. From Plumb,
## with its reason: a foot is placed once per step and travelled over for the
## whole stance.
const KEEP: float = 0.25

const MIN_MASS: float = 0.0001

## A toe this close to the surface is planted. The armature places standing
## feet exactly on it; the tolerance is for a body mid-drop.
const PLANT_EPSILON: float = 0.5


# -------------------------------------------------------- baked, per node ----

## Mass, mean vertical offset and mean lateral lean per armature node, plus
## the widest census girth mapped there (the droop walk's beam width). Baked
## by `bake`, valid for `_baked_rev`.
var node_mass: PackedFloat32Array = PackedFloat32Array()
var node_rise: PackedFloat32Array = PackedFloat32Array()
var node_side: PackedFloat32Array = PackedFloat32Array()
var node_width: PackedFloat32Array = PackedFloat32Array()
var _baked_rev: int = -1


# ----------------------------------------------------- posed, in the world ----

## The centre of mass on the ground plane, world px, and how high it hangs —
## the lever every topple turns through.
var centre: Vector2 = Vector2.ZERO
var height: float = 0.0
var posed: bool = false


# --------------------------------------------------------- against the feet ----

var base: Vector2 = Vector2.ZERO
## Signed px from the plumb line to the support boundary, positive inside.
var clearance: float = 0.0
## Which way and how far the body is out past its feet, zero when it is not.
var overhang: Vector2 = Vector2.ZERO
## Radius of the support about its own middle.
var span: float = 0.0
var feet: int = 0

var _prints: PackedVector2Array = PackedVector2Array()


# ------------------------------------------------------------------- bake ----

## Reduces the census to per-node moments and hands the armature its masses.
##
## Station moments come off the census's own derivation walk; each station's
## mass is split between the two armature nodes bracketing its arc position,
## linear in the split — which preserves the chain's first moment exactly, so
## the baked centre and the census centre agree by construction. A station
## ahead of a chain's first node brackets against the parent (a neck's first
## flesh is partly the withers'), which is where an attach stick's tissue
## belongs.
##
## Returns whether anything was baked — false is the ordinary tick.
func bake(corpus: Corpus, armature: Armature) -> bool:
	if corpus.revision == _baked_rev:
		return false
	_baked_rev = corpus.revision

	var n: int = armature.node_count()
	node_mass.resize(n)
	node_rise.resize(n)
	node_side.resize(n)
	node_width.resize(n)
	node_mass.fill(0.0)
	node_rise.fill(0.0)
	node_side.fill(0.0)
	node_width.fill(0.0)

	for census in corpus.chains:
		var moments: Corpus.CensusChain = corpus.station_moments(census.name)
		var chain: Armature.Chain = armature.chain(census.name)

		# Node ids and their arc coordinates in the census's own frame: 0 at
		# the attach point. A limb's census starts at its socket, so the
		# girdle-offset stick is skipped; an axial chain counts every stick.
		var ids := PackedInt32Array()
		var arcs := PackedFloat32Array()
		if chain.parent_node >= 0 and not chain.limb:
			ids.append(chain.parent_node)
			arcs.append(0.0)
		var run: float = 0.0
		for j in chain.nodes.size():
			if chain.parent_node >= 0:
				if j == 0 and chain.limb:
					ids.append(chain.nodes[0])
					arcs.append(0.0)
					continue
				run += armature.stick_bone[chain.sticks[j]]
			elif j > 0:
				run += armature.stick_bone[chain.sticks[j - 1]]
			ids.append(chain.nodes[j])
			arcs.append(run)

		for st in census.stations:
			var m: float = moments.st_mass[st]
			if m <= MIN_MASS:
				continue
			var at: float = census.arc[st]
			var k: int = ids.size() - 2
			for j in range(ids.size() - 1):
				if at <= arcs[j + 1]:
					k = j
					break
			var w: float = clampf((at - arcs[k])
				/ maxf(arcs[k + 1] - arcs[k], 0.001), 0.0, 1.0)
			var ia: int = ids[k]
			var ib: int = ids[k + 1]
			node_mass[ia] += m * (1.0 - w)
			node_mass[ib] += m * w
			node_rise[ia] += moments.st_rise[st] * m * (1.0 - w)
			node_rise[ib] += moments.st_rise[st] * m * w
			node_side[ia] += moments.st_side[st] * m * (1.0 - w)
			node_side[ib] += moments.st_side[st] * m * w
			var wide: float = corpus.girth(census.name, st)
			node_width[ia] = maxf(node_width[ia], wide)
			node_width[ib] = maxf(node_width[ib], wide)

	for i in n:
		if node_mass[i] > MIN_MASS:
			node_rise[i] /= node_mass[i]
			node_side[i] /= node_mass[i]

	# Hand the armature its weights: the droop walk and (from Phase 3) the
	# drive read these, and this assignment is the whole of "Corpus derives
	# mass → drives Armature".
	armature.mass = node_mass.duplicate()
	armature.flesh_r = node_width.duplicate()
	return true


# ------------------------------------------------------------------- pose ----

## Carries the baked moments into the world: one weighted mean over the nodes
## the solver just placed. The lateral lean rides each node's perp frame —
## zero-vectored on limb nodes, whose own lean is below caring — and the rise
## rides straight up, which is what 2.5D means.
func pose(armature: Armature) -> void:
	posed = false
	var flat := Vector2.ZERO
	var up: float = 0.0
	var total: float = 0.0
	for i in node_mass.size():
		var m: float = node_mass[i]
		if m <= MIN_MASS:
			continue
		var p: Vector3 = armature.pos[i]
		var lean: Vector2 = armature.perp[i] * node_side[i]
		flat += (Vector2(p.x, p.y) + lean) * m
		up += (p.z + node_rise[i]) * m
		total += m
	if total <= MIN_MASS:
		return
	centre = flat / total
	height = up / total
	posed = true


# ---------------------------------------------------------- over the feet ----

## The support: the convex hull of the planted toes, each a patch of ground
## the width of its own paw. Ported from Plumb.stand with the limb model
## swapped — a planted toe is a limb chain's last node on the surface —
## and the same deliberate refusal to call a distance a verdict.
func stand(armature: Armature, prop: Vector2 = Vector2.INF) -> void:
	_prints.clear()
	var pad: float = 0.0
	base = Vector2.ZERO
	for limb in armature.limbs:
		var toe: int = limb.nodes[limb.nodes.size() - 1]
		var p: Vector3 = armature.pos[toe]
		if p.z > PLANT_EPSILON:
			continue
		_prints.append(Vector2(p.x, p.y))
		pad = maxf(pad, node_width[toe] if toe < node_width.size() else 0.0)
	if prop.x < INF:
		_prints.append(prop)
	feet = _prints.size()
	if feet == 0:
		span = 0.0
		clearance = -INF
		overhang = Vector2.ZERO
		return
	for point in _prints:
		base += point
	base /= float(feet)
	span = 0.0
	for point in _prints:
		span = maxf(span, point.distance_to(base))
	span += pad
	clearance = _inside(centre if posed else base, pad)
	overhang = Vector2.ZERO
	if clearance < 0.0:
		var out: Vector2 = (centre if posed else base) - base
		if out.length_squared() > 0.000001:
			overhang = out.normalized() * -clearance


## How much of its own support the line is inside, as a share of the
## support's radius: 1 dead over the middle, 0 on the edge, negative going
## over. From Plumb, verbatim.
func steadiness() -> float:
	if feet == 0 or span <= 0.0001:
		return -1.0
	return clampf(clearance / span, -1.0, 1.0)


# ---------------------------------------------------- support geometry ----
# Ported from Plumb so Phase 7 can delete v1 without reaching back: the same
# three shapes for three counts of contact (disc, capsule, polygon), the same
# gift-wrapped hull with the collinear-contact rule, the same signed
# distances.

func _inside(point: Vector2, pad: float) -> float:
	if feet == 1:
		return pad - point.distance_to(_prints[0])
	if feet == 2:
		return pad - _to_segment(point, _prints[0], _prints[1])
	var hull: PackedVector2Array = _hull(_prints)
	if hull.size() < 3:
		var worst: float = INF
		for i in hull.size():
			worst = minf(worst, _to_segment(point, hull[i],
				hull[(i + 1) % hull.size()]))
		return pad - worst
	var least: float = INF
	for i in hull.size():
		var a: Vector2 = hull[i]
		var edge: Vector2 = hull[(i + 1) % hull.size()] - a
		var len: float = edge.length()
		if len < 0.0001:
			continue
		least = minf(least, (edge.x * (point.y - a.y) - edge.y * (point.x - a.x)) / len)
	return (0.0 if least == INF else least) + pad


static func _to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var edge: Vector2 = b - a
	var len2: float = edge.length_squared()
	if len2 < 0.000001:
		return point.distance_to(a)
	return point.distance_to(a + edge * clampf((point - a).dot(edge) / len2, 0.0, 1.0))


static func _hull(points: PackedVector2Array) -> PackedVector2Array:
	var n: int = points.size()
	var start: int = 0
	for i in n:
		if points[i].x < points[start].x \
				or (points[i].x == points[start].x and points[i].y < points[start].y):
			start = i
	var out := PackedVector2Array()
	var at: int = start
	for _step in n:
		out.append(points[at])
		var next: int = (at + 1) % n
		for c in n:
			if c == at:
				continue
			var side: float = _turn(points[at], points[next], points[c])
			if side < 0.0 or (side == 0.0
					and points[at].distance_squared_to(points[c])
						> points[at].distance_squared_to(points[next])):
				next = c
		at = next
		if at == start:
			break
	return out


static func _turn(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
