## Voxel-like tissue: a lattice of body cells, each a depth stack of skin over
## muscle over bone.
##
## The pose is rebuilt from the spine every physics tick, so nothing can be
## stored in world space. The lattice is therefore defined in *body* space — a
## fixed grid of (station, lateral) cells — and only its corner positions are
## re-derived each tick from the current pose. Damage lives in the body-space
## cells, so it stays welded to the anatomy through any bend or procedural
## rebuild.
##
## Grid dimensions are deliberately constants rather than functions of
## `segment_count`: the cell a bite destroyed has to still be the same cell
## after the tuning panel restructures the spine underneath it.
##
## Top-down means the three tissues stack in *depth*, not sideways — you look
## down at skin, and only what a bite has already cleared away is visible
## beneath it. A bite therefore spends its penetration budget strictly
## outside-in, and bone both absorbs at a reduced rate and stops the bite dead,
## because there is nothing behind it to reach.
##
## A cell with nothing left in any layer is *gone*, and gone means gone: it is
## not drawn, not bitten and not collided with. Nothing paints the ground colour
## over a hole to fake it, which is the only way a wound can read as an opening
## rather than as a pale patch — paper over ink still stops a body walking
## through, and still hides whatever is behind it.
class_name TissueGrid
extends RefCounted

# --- layers, outermost first ------------------------------------------------
const SKIN: int = 0
const MUSCLE: int = 1
const BONE: int = 2
const LAYERS: int = 3

## Skin is a rind, not armour: any bite worth the name strips it, and at the
## default depth one strips it across nearly the whole width of the jaws. It
## exists to be broken through, so what a bite reads as is *opening* the body
## rather than scratching it.
const SKIN_HP: float = 0.4
## Muscle is where a fight actually happens. Deep enough that the default bite
## takes three passes over the same spot to tear through — so a kill is either
## several bites or a stronger one, never a graze. It is also the only layer
## whose *state* is worth reading, skin being a rind and bone a wall, so it has
## to survive long enough to be seen thinning.
const MUSCLE_HP: float = 5.5
## Bone is not merely thicker — it also yields at BONE_YIELD of the incoming
## depth and then consumes the rest of the bite, so a skeleton takes roughly an
## order of magnitude more work to breach than the flesh laid over it.
const BONE_HP: float = 6.0
const BONE_YIELD: float = 0.5

# --- body patch layout ------------------------------------------------------
const BODY_KEY: String = "body"
## Cap columns tessellating the round snout, and the same for the tail tip.
## Their outer corners land exactly on the circle the cap would be drawn as.
##
## The lattice *is* the silhouette now rather than an overlay on one, so these
## counts set how round the two ends look: four columns over the snout's quarter
## turn was fine when a `draw_circle` sat underneath covering the facets, and is
## a visible octagon without it.
const HEAD_COLS: int = 8
const TORSO_COLS: int = 20
const TAIL_COLS: int = 4
const BODY_COLS: int = HEAD_COLS + TORSO_COLS + TAIL_COLS
## Odd, so one row straddles the spine and can carry the vertebral column.
const BODY_ROWS: int = 7

# --- limb patch layout ------------------------------------------------------
## Upper bone, lower bone, then a cap over the outer half of the foot circle,
## so the drawn foot is part of the lattice instead of floating unbitable on it.
const LIMB_BONE_COLS: int = 6
## Four rather than two for the same reason the snout cap grew: the foot is the
## lattice's own outline now, not a tessellation hidden under a drawn circle.
const LIMB_FOOT_COLS: int = 4
const LIMB_COLS: int = LIMB_BONE_COLS + LIMB_FOOT_COLS
const LIMB_ROWS: int = 3
const LIMB_KEYS: Array[String] = ["FL", "FR", "RL", "RR"]

# --- skeleton layout --------------------------------------------------------
# The skeleton is a *frame*, not a plate: a skull, a vertebral column one cell
# wide running neck to tail tip, a girdle under each pair of limb sockets, and
# ribs on alternating columns between them. Everywhere else the body is flesh
# over nothing, and a bite that gets through it opens a hole clean through the
# creature — which is the whole point of laying the skeleton out sparsely. If
# bone sat under most of the body there would be no such thing as eating through
# it, and every wound would bottom out on the same pale surface.
#
# It also has to be one *connected* piece. Flesh is what a bite takes first, so
# a skeleton whose parts meet only through muscle comes apart into floating
# fragments at exactly the moment it is the whole of what is left to look at.
#
# Like the grid dimensions, the layout is fixed in body space rather than read
# from the params: it has to name the same cells after the tuning panel has
# restructured the spine underneath it. The girdle columns therefore mirror the
# *default* front_limb_t / rear_limb_t instead of tracking them live.

## The skull fills the head cap out to here, as a fraction of half-width, so the
## cheeks stay flesh and the head is not one solid disc of bone.
const SKULL_SPAN: float = 0.72
## Ribs reach this far out from the midline, over the chest.
const RIB_SPAN: float = 0.78
## Girdles run the full width — they are what the limb bones hang off, so they
## have to reach the flank the sockets sit on.
const GIRDLE_SPAN: float = 0.95
## Torso columns carrying the pectoral and pelvic girdles. TORSO_COLS spans the
## whole clipped spine, so a column index reads directly as a fraction of body
## length: column c covers c/20 to (c+1)/20, which puts the default shoulder
## (front_limb_t 0.16) in column 3 and the default hip (rear_limb_t 0.46) in
## column 9. The girdle has to be the column the socket is *in*, not the one
## next to it — a limb bone rooted at a socket with no girdle under it is a limb
## joined to the skeleton by flesh alone, and it comes adrift the moment that
## flesh is eaten.
const SHOULDER_COL: int = 3
const PELVIS_COL: int = 9


## One chunk of tissue a bite knocked loose, in world space.
class Shed extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var layer: int = 0
	var size: float = 3.0
	## Approximate plan-view area. Loose tissue uses this as inertia so a broad
	## torn flap lands with weight instead of moving like a single cell.
	var mass: float = 9.0
	## Major-axis direction and elongation retained from the tissue it occupied.
	## The world renderer uses these to make an organic piece rather than a tile.
	var angle: float = 0.0
	var aspect: float = 1.2
	## Temporary topology carried only until one bite has joined neighbouring
	## destroyed cells into cohesive pieces.
	var patch_key: String = ""
	var col: int = 0
	var row: int = 0


## A rectangular cell lattice over one anatomical structure.
##
## Cells are addressed `col * rows + row`. Corners are shared between
## neighbours and so stored once, as `station * (rows + 1) + row`. Damage is
## expected to stay sparse, so `damaged` keeps the indices worth drawing and the
## renderer never has to walk the full lattice.
##
## Deliberately free of any tissue knowledge — it owns geometry and raw storage,
## and TissueGrid owns what the numbers in it mean.
class Patch extends RefCounted:
	var key: String = ""
	var cols: int = 0
	var rows: int = 0
	var cells: int = 0
	var layers: int = 0

	## World positions of every cell corner, rebuilt each tick from the pose.
	var verts: PackedVector2Array = PackedVector2Array()
	## Remaining hit points, indexed `cell * layers + layer`.
	var hp: PackedFloat32Array = PackedFloat32Array()
	## 1 where the skeleton runs under the cell. Cells without it open into a
	## hole clean through the body once their muscle is gone.
	var bone: PackedByteArray = PackedByteArray()

	## Cells that have taken any damage. Kept so a query can walk the wounds
	## rather than the whole lattice.
	var touched: PackedByteArray = PackedByteArray()
	var damaged: PackedInt32Array = PackedInt32Array()

	## 1 where every layer is spent. A gone cell is a hole in the creature: the
	## renderer skips it, so the world behind shows through, and the collision
	## and hit-test queries below shrink away from it.
	var gone: PackedByteArray = PackedByteArray()
	var gone_count: int = 0

	## How far tissue still reaches out from the midline in each column, as a
	## fraction of that column's local half-width — `[col * 2]` on the -perp
	## side, `[col * 2 + 1]` on the +perp side. This is what makes a hole
	## genuinely empty to walk into rather than merely invisible: the capsules
	## the body is collided and hit-tested with are narrowed to it, and a column
	## eaten clean through reports 0 and stops colliding altogether.
	##
	## Maintained on destruction rather than per frame, so an undamaged creature
	## pays nothing and a chewed one pays once per cell it loses.
	var solid: PackedFloat32Array = PackedFloat32Array()

	## False until the pose has been sampled — the renderer and the bite query
	## both refuse to touch a patch whose corners are still stale.
	var live: bool = false
	## Conservative world bounds, for rejecting a bite without a cell walk.
	var lo: Vector2 = Vector2.ZERO
	var hi: Vector2 = Vector2.ZERO

	var full_hp: float = 0.0
	var remaining_hp: float = 0.0

	## Corners per station, cached because every index below multiplies by it.
	var _stride: int = 0

	func configure(p_key: String, p_cols: int, p_rows: int, p_layers: int) -> void:
		key = p_key
		cols = p_cols
		rows = p_rows
		layers = p_layers
		cells = cols * rows
		_stride = rows + 1
		verts.resize((cols + 1) * _stride)
		hp.resize(cells * layers)
		bone.resize(cells)
		touched.resize(cells)
		gone.resize(cells)
		solid.resize(cols * 2)

	func clear_damage() -> void:
		touched.fill(0)
		damaged.clear()
		gone.fill(0)
		gone_count = 0
		solid.fill(1.0)
		remaining_hp = full_hp

	## Marks a cell as having nothing left in it and re-derives its column's
	## surviving reach. Called once per cell, on the tick it is destroyed.
	func retire(cell: int) -> void:
		if gone[cell] != 0:
			return
		gone[cell] = 1
		gone_count += 1
		var col: int = cell / rows
		var minus: float = 0.0
		var plus: float = 0.0
		for r in rows:
			if gone[col * rows + r] != 0:
				continue
			# The reach of a surviving row is its *outer* edge, so a hole bitten
			# out of the middle of a flank does not pull the surface in past the
			# tissue still standing outside it.
			minus = maxf(minus, 1.0 - 2.0 * float(r) / float(rows))
			plus = maxf(plus, -1.0 + 2.0 * float(r + 1) / float(rows))
		solid[col * 2] = minus
		solid[col * 2 + 1] = plus

	## Surviving reach of one column on one side, 0..1 of the local half-width.
	## `side` is the sign of the offset along the cross-section's perpendicular.
	func side_solid(col: int, side: float) -> float:
		if col < 0 or col >= cols:
			return 0.0
		return solid[col * 2 + (1 if side >= 0.0 else 0)]

	## The widest reach anywhere in a column range, either side. Used where the
	## drawn primitive is a circle or a capsule rather than a flank — a foot, a
	## limb bone, the head cap — and so has only one radius to narrow.
	func span_solid(from_col: int, to_col: int) -> float:
		var widest: float = 0.0
		for c in range(maxi(from_col, 0), mini(to_col, cols)):
			widest = maxf(widest, maxf(solid[c * 2], solid[c * 2 + 1]))
		return widest

	## One shared cell corner, by the grid line it sits on.
	func vert(col: int, row: int) -> Vector2:
		return verts[col * _stride + row]

	## Lateral position of a row's centre, -1 on one flank to +1 on the other.
	func row_centre(row: int) -> float:
		return -1.0 + 2.0 * (float(row) + 0.5) / float(rows)

	## Writes the corners of one cross-section. `half` is the local half-width,
	## so row 0 lands on one flank and row `rows` on the other.
	func set_station(station: int, pos: Vector2, perp: Vector2, half: float) -> void:
		var base: int = station * _stride
		for r in range(_stride):
			verts[base + r] = pos + perp * (half * (-1.0 + 2.0 * float(r) / float(rows)))
		# Squaring off the cross-section keeps the bounds conservative whatever
		# way `perp` points, for a fraction of the cost of scanning the corners.
		if station == 0:
			lo = Vector2(pos.x - half, pos.y - half)
			hi = Vector2(pos.x + half, pos.y + half)
		else:
			lo = Vector2(minf(lo.x, pos.x - half), minf(lo.y, pos.y - half))
			hi = Vector2(maxf(hi.x, pos.x + half), maxf(hi.y, pos.y + half))

	func centre_of(cell: int) -> Vector2:
		var i: int = (cell / rows) * _stride + (cell % rows)
		return (verts[i] + verts[i + 1] + verts[i + _stride] + verts[i + _stride + 1]) * 0.25

	## Nominal side length of a cell — what a chunk shed from it should measure.
	func extent_of(cell: int) -> float:
		var i: int = (cell / rows) * _stride + (cell % rows)
		return (verts[i].distance_to(verts[i + _stride + 1])
			+ verts[i + 1].distance_to(verts[i + _stride])) * 0.25

	## Long axis of a cell in the solved pose. A severed piece keeps this grain,
	## which is especially important for muscle: it should read as fibres torn
	## across a body, not as a square ejected from a grid.
	func angle_of(cell: int) -> float:
		var i: int = (cell / rows) * _stride + (cell % rows)
		var a: Vector2 = (verts[i] + verts[i + 1]) * 0.5
		var b: Vector2 = (verts[i + _stride] + verts[i + _stride + 1]) * 0.5
		return (b - a).angle()

	## Fills `out` with the cell's four corners, wound consistently. Takes the
	## buffer rather than returning one so a redraw allocates nothing.
	func corners_of(cell: int, out: PackedVector2Array) -> void:
		var i: int = (cell / rows) * _stride + (cell % rows)
		out[0] = verts[i]
		out[1] = verts[i + 1]
		out[2] = verts[i + _stride + 1]
		out[3] = verts[i + _stride]


var patches: Dictionary = {}


func _init() -> void:
	var body := Patch.new()
	body.configure(BODY_KEY, BODY_COLS, BODY_ROWS, LAYERS)
	patches[BODY_KEY] = body
	for key in LIMB_KEYS:
		var limb := Patch.new()
		limb.configure(key, LIMB_COLS, LIMB_ROWS, LAYERS)
		patches[key] = limb
	reset()


func reset() -> void:
	_fill(patches[BODY_KEY], _body_has_bone)
	for key in LIMB_KEYS:
		_fill(patches[key], _limb_has_bone)


func patch(key: String) -> Patch:
	return patches.get(key, null)


## Whole-creature integrity: 1.0 intact, down to 0.0 stripped to nothing.
func integrity() -> float:
	var full: float = 0.0
	var left: float = 0.0
	for key in patches:
		var p: Patch = patches[key]
		full += p.full_hp
		left += p.remaining_hp
	return left / full if full > 0.0 else 1.0


func patch_integrity(key: String) -> float:
	var p: Patch = patch(key)
	if p == null or p.full_hp <= 0.0:
		return 1.0
	return p.remaining_hp / p.full_hp


## Restores every cell to intact tissue. `has_bone(col, lateral) -> bool`
## decides which of them sit over the skeleton.
func _fill(p: Patch, has_bone: Callable) -> void:
	p.full_hp = 0.0
	for c in p.cols:
		for r in p.rows:
			var cell: int = c * p.rows + r
			var solid: bool = has_bone.call(c, p.row_centre(r))
			p.bone[cell] = 1 if solid else 0
			var base: int = cell * LAYERS
			p.hp[base + SKIN] = SKIN_HP
			p.hp[base + MUSCLE] = MUSCLE_HP
			p.hp[base + BONE] = BONE_HP if solid else 0.0
			p.full_hp += SKIN_HP + MUSCLE_HP + (BONE_HP if solid else 0.0)
	p.clear_damage()


# ----------------------------------------------------------------- posing ----

## Re-derives every cell corner from the pose solved this tick.
##
## This is the only per-tick cost the lattice carries, and it is deliberately
## per-*station* rather than per-cell: about sixty cross-sections for a whole
## creature. Everything priced per cell — erosion and drawing — is deferred to
## the ticks a bite lands on and to the handful of cells actually damaged.
func update(creature: Node) -> void:
	if creature == null or creature.body == null or creature.spine == null:
		return
	_update_body(creature.body, creature.spine)
	if creature.gait == null:
		return
	for limb in creature.gait.limbs:
		var p: Patch = patch(limb.key)
		if p != null:
			_update_limb(p, limb, creature.size_scale)


func _update_body(body: BodyShape, spine: Spine) -> void:
	var p: Patch = patches[BODY_KEY]
	var last: int = body.last_index
	if last < 2 or body.widths.size() <= last:
		return
	var station: int = 0

	# Snout cap. Spacing the stations by angle puts every outer corner exactly
	# on the drawn head circle, so the tessellation is inscribed in the
	# silhouette rather than approximating it from outside.
	for k in HEAD_COLS:
		var a: float = PI * 0.5 * (float(k) / float(HEAD_COLS))
		p.set_station(station,
			body.head.pos + body.head.fwd * (body.head_radius * cos(a)),
			body.head.perp,
			body.head_radius * sin(a))
		station += 1

	# Torso, at a fixed count of stations along the *clipped* spine, so the
	# lattice is independent of how many particles the chain happens to have.
	for k in range(TORSO_COLS + 1):
		var s: float = float(k) / float(TORSO_COLS) * float(last)
		var i: int = clampi(int(s), 0, last - 1)
		var f: float = s - float(i)
		var perp: Vector2 = spine.perps[i].lerp(spine.perps[i + 1], f)
		perp = perp.normalized() if perp.length_squared() > 0.000001 else spine.perps[i]
		p.set_station(station,
			spine.points[i].lerp(spine.points[i + 1], f),
			perp,
			lerpf(body.widths[i], body.widths[i + 1], f))
		station += 1

	# Tail cap: the snout cap mirrored around the last cross-section.
	var back: Vector2 = -spine.forwards[last]
	var tip_r: float = body.widths[last]
	for k in range(1, TAIL_COLS + 1):
		var a2: float = PI * 0.5 * (float(k) / float(TAIL_COLS))
		p.set_station(station,
			spine.points[last] + back * (tip_r * sin(a2)),
			spine.perps[last],
			tip_r * cos(a2))
		station += 1

	p.live = true


func _update_limb(p: Patch, limb: Limb, scale: float) -> void:
	# Mirrors the widths CreatureView strokes the bones with, so the lattice
	# covers exactly what is drawn.
	var upper_half: float = maxf(limb.total_length * 0.16, 2.5 * scale) * 0.5
	var lower_half: float = upper_half * 0.72
	var foot_r: float = maxf(limb.total_length * 0.10, 3.0 * scale)

	var d0: Vector2 = limb.joints[1] - limb.joints[0]
	var d1: Vector2 = limb.joints[2] - limb.joints[1]
	d0 = d0.normalized() if d0.length_squared() > 0.000001 else Vector2.RIGHT
	d1 = d1.normalized() if d1.length_squared() > 0.000001 else d0
	var n0 := Vector2(-d0.y, d0.x)
	var n1 := Vector2(-d1.y, d1.x)
	# The elbow is one cross-section shared by two differently angled bones, so
	# it takes the bisector — with either bone's own normal the two halves of
	# the limb would tear apart at the joint.
	var joint_n: Vector2 = n0 + n1
	joint_n = joint_n.normalized() if joint_n.length_squared() > 0.000001 else n0

	var span: int = LIMB_BONE_COLS / 2
	var station: int = 0
	for k in range(span):
		p.set_station(station,
			limb.joints[0].lerp(limb.joints[1], float(k) / float(span)), n0, upper_half)
		station += 1
	p.set_station(station, limb.joints[1], joint_n, lerpf(upper_half, lower_half, 0.5))
	station += 1
	# The lower bone flares out into the foot, so the ankle is continuous with
	# the foot circle instead of stepping into it.
	for k in range(1, span + 1):
		var t: float = float(k) / float(span)
		p.set_station(station,
			limb.joints[1].lerp(limb.joints[2], t), n1, lerpf(lower_half, foot_r, t))
		station += 1
	for k in range(1, LIMB_FOOT_COLS + 1):
		var a: float = PI * 0.5 * (float(k) / float(LIMB_FOOT_COLS))
		p.set_station(station, limb.joints[2] + d1 * (foot_r * sin(a)), n1, foot_r * cos(a))
		station += 1

	p.live = true


# ----------------------------------------------------------------- damage ----

## Erodes every cell whose centre falls inside the bite circle, outside-in, and
## returns the total tissue removed.
##
## Cells are selected by testing their solved world centres rather than by
## inverting the body-space mapping. That mapping is a curved, tapered, per-tick
## thing with no cheap inverse, whereas the direct test is exact, needs no
## special case at the caps or the elbow bisector, and costs a few hundred
## squared distances on the rare ticks a bite actually lands. Bites also cross
## structures — jaws closing on a flank catch the leg over it — which a query
## routed through a single hit region could not express.
##
## `shed` collects the chunks that broke off, for the world to scatter.
func bite(center: Vector2, radius: float, depth: float, shed: Array) -> float:
	var r2: float = radius * radius
	if r2 <= 0.0 or depth <= 0.0:
		return 0.0
	var removed: float = 0.0
	# Destruction is still resolved at cell precision, but loose tissue is not.
	# Hold the cells from this strike locally and join adjacent ones below before
	# the world ever sees them.
	var loose: Array = []
	for key in patches:
		var p: Patch = patches[key]
		if not p.live:
			continue
		if center.x + radius < p.lo.x or center.x - radius > p.hi.x \
				or center.y + radius < p.lo.y or center.y - radius > p.hi.y:
			continue
		for cell in p.cells:
			var at: Vector2 = p.centre_of(cell)
			var d2: float = center.distance_squared_to(at)
			if d2 >= r2:
				continue
			# Rounded falloff: full depth at the centre of the jaws tapering to
			# a graze at the rim, which is what makes damage read as landing
			# where the bite landed rather than as a uniform stamp.
			removed += _erode(p, cell, depth * (1.0 - d2 / r2), at, loose)
	_coalesce_shed(loose, shed)
	return removed


func _erode(p: Patch, cell: int, budget: float, at: Vector2, shed: Array) -> float:
	var base: int = cell * LAYERS
	var removed: float = 0.0
	for layer in LAYERS:
		if budget <= 0.0:
			break
		var idx: int = base + layer
		var have: float = p.hp[idx]
		if have <= 0.0:
			continue
		var take: float = minf(budget, have)
		if layer == BONE:
			take = minf(budget * BONE_YIELD, have)
			budget = 0.0  # nothing behind bone, so it stops the bite outright
		else:
			budget -= take
		p.hp[idx] = have - take
		removed += take
		# Skin and muscle come away in pieces; bone is ground down in place.
		if p.hp[idx] <= 0.0 and layer != BONE:
			var chunk := Shed.new()
			chunk.pos = at
			chunk.layer = layer
			chunk.size = maxf(p.extent_of(cell) * 0.9, 1.5)
			chunk.mass = chunk.size * chunk.size
			chunk.angle = p.angle_of(cell)
			chunk.patch_key = p.key
			chunk.col = cell / p.rows
			chunk.row = cell % p.rows
			shed.append(chunk)

	if removed <= 0.0:
		return 0.0
	p.remaining_hp = maxf(p.remaining_hp - removed, 0.0)
	if p.touched[cell] == 0:
		p.touched[cell] = 1
		p.damaged.append(cell)
	if p.hp[base + SKIN] <= 0.0 and p.hp[base + MUSCLE] <= 0.0 and p.hp[base + BONE] <= 0.0:
		p.retire(cell)
	return removed


## Joins orthogonally adjacent cells from the same tissue layer and anatomical
## patch into one torn piece. The lattice remains useful collision/damage data,
## but it no longer dictates the scale of the visible meat.
func _coalesce_shed(loose: Array, shed: Array) -> void:
	if loose.is_empty():
		return
	var joined := PackedByteArray()
	joined.resize(loose.size())
	joined.fill(0)

	for start in loose.size():
		if joined[start] != 0:
			continue
		var seed: Shed = loose[start]
		var pending: Array[int] = [start]
		joined[start] = 1
		var members: Array[int] = []
		while not pending.is_empty():
			var current: int = pending.pop_back()
			members.append(current)
			var a: Shed = loose[current]
			for candidate in loose.size():
				if joined[candidate] != 0:
					continue
				var b: Shed = loose[candidate]
				if b.layer != seed.layer or b.patch_key != seed.patch_key:
					continue
				if absi(a.col - b.col) + absi(a.row - b.row) != 1:
					continue
				joined[candidate] = 1
				pending.append(candidate)

		var piece := Shed.new()
		piece.layer = seed.layer
		piece.patch_key = seed.patch_key
		var weighted_pos := Vector2.ZERO
		var grain := Vector2.ZERO
		var area: float = 0.0
		for member in members:
			var cell_piece: Shed = loose[member]
			area += cell_piece.mass
			weighted_pos += cell_piece.pos * cell_piece.mass
			# Double-angle averaging treats an axis as an axis: left-to-right and
			# right-to-left fibres are the same grain rather than opposites.
			grain += Vector2(cos(cell_piece.angle * 2.0), sin(cell_piece.angle * 2.0)) \
				* cell_piece.mass
		piece.mass = area
		piece.pos = weighted_pos / maxf(area, 0.001)
		piece.angle = grain.angle() * 0.5 if grain.length_squared() > 0.0001 else seed.angle
		piece.size = maxf(sqrt(area) * 1.08, seed.size)
		var count_stretch: float = sqrt(float(members.size())) * 0.12
		piece.aspect = clampf((1.45 if piece.layer == SKIN else 1.25) + count_stretch, 1.2, 2.15)
		shed.append(piece)


# ----------------------------------------------------------------- voids ----

## How much of the body is still there at `t` along the clipped spine, on the
## given side, as a fraction of the width the silhouette would have had.
##
## The collision and hit-test capsules are scaled by this, which is what makes a
## hole something a creature can genuinely walk into instead of a light patch
## painted on a solid body. 0 means that column has been eaten clean through and
## nothing there collides at all.
func body_solid(t: float, side: float) -> float:
	var p: Patch = patches[BODY_KEY]
	if not p.live or p.gone_count == 0:
		return 1.0
	return p.side_solid(HEAD_COLS + clampi(int(t * float(TORSO_COLS)), 0, TORSO_COLS - 1), side)


## The same, for the snout cap the head is hit-tested as.
func head_solid() -> float:
	var p: Patch = patches[BODY_KEY]
	if not p.live or p.gone_count == 0:
		return 1.0
	return p.span_solid(0, HEAD_COLS)


## The same, for one drawn limb primitive: 0 = upper bone, 1 = lower, 2 = foot.
func limb_solid(key: String, segment: int) -> float:
	var p: Patch = patch(key)
	if p == null or not p.live or p.gone_count == 0:
		return 1.0
	var half: int = LIMB_BONE_COLS / 2
	if segment == 0:
		return p.span_solid(0, half)
	if segment == 1:
		return p.span_solid(half, LIMB_BONE_COLS)
	return p.span_solid(LIMB_BONE_COLS, LIMB_COLS)


# ------------------------------------------------------------- tenacity ----
# The solidity queries above answer *how far the body still reaches* — which is
# what a bite, a contact and the renderer need. These answer *how much is left
# exactly where something has hold*, which is what decides whether a piece of the
# creature can be pulled off it.

## Hit points still standing in the one torso cell a body-space position falls
## in, summed over its layers. Addressed the same way `body_solid` is.
func body_hp(t: float, lateral: float) -> float:
	return _cell_hp(patches[BODY_KEY],
		HEAD_COLS + clampi(int(t * float(TORSO_COLS)), 0, TORSO_COLS - 1), lateral)


## The same for the snout cap, sampled at the middle of it. Jaws closed on a head
## have hold of the skull, not of one facet of the outline drawn around it.
func head_hp(lateral: float) -> float:
	return _cell_hp(patches[BODY_KEY], HEAD_COLS / 2, lateral)


func _cell_hp(p: Patch, col: int, lateral: float) -> float:
	var row: int = clampi(int((lateral + 1.0) * 0.5 * float(p.rows)), 0, p.rows - 1)
	var base: int = (clampi(col, 0, p.cols - 1) * p.rows + row) * LAYERS
	return p.hp[base + SKIN] + p.hp[base + MUSCLE] + p.hp[base + BONE]


## Average hit points per cell over everything inside a circle — how much tissue
## a set of jaws of that footprint actually has hold of.
##
## Destroyed cells count as the nothing they are, so a region already half eaten
## comes out at half strength rather than dropping out of the average. That is
## the whole reason this is an average over the footprint and not the one cell
## under the anchor: a single cell chewed thin reads as almost no tissue at all,
## and jaws pulling on it would part it again every tick without ever removing
## anything, which is a hold vibrating rather than a wound deepening.
##
## Walks cells, so it is priced like a bite rather than like a per-frame query —
## but unlike a bite it runs every tick, and so is only ever called for a set of
## jaws that is actually holding something.
func flesh_within(center: Vector2, radius: float) -> float:
	var r2: float = radius * radius
	if r2 <= 0.0:
		return 0.0
	var total: float = 0.0
	var count: int = 0
	for key in patches:
		var p: Patch = patches[key]
		if not p.live:
			continue
		if center.x + radius < p.lo.x or center.x - radius > p.hi.x \
				or center.y + radius < p.lo.y or center.y - radius > p.hi.y:
			continue
		for cell in p.cells:
			if center.distance_squared_to(p.centre_of(cell)) >= r2:
				continue
			count += 1
			if p.gone[cell] != 0:
				continue
			var base: int = cell * LAYERS
			total += p.hp[base + SKIN] + p.hp[base + MUSCLE] + p.hp[base + BONE]
	return total / float(count) if count > 0 else 0.0


# -------------------------------------------------------------- skeletons ----

## Skull, vertebral column, two limb girdles and a ribcage between them — see
## the skeleton layout constants above for why it is this sparse.
func _body_has_bone(col: int, v: float) -> bool:
	var lateral: float = absf(v)
	# Skull: the head cap, with a margin of flesh left at the cheeks.
	if col < HEAD_COLS:
		return lateral <= SKULL_SPAN
	# Vertebrae run the midline the whole way, neck to tail tip. Only the row
	# straddling the spine has its centre at zero, which is why BODY_ROWS is odd.
	if lateral <= 1.0 / float(BODY_ROWS):
		return true
	var torso: int = col - HEAD_COLS
	# Past the torso is tail: vertebrae and nothing else.
	if torso >= TORSO_COLS:
		return false
	# Girdles: full-width bars under the limb sockets, so the limb bones read as
	# attached to the axial skeleton rather than floating alongside it.
	if torso == SHOULDER_COL or torso == PELVIS_COL:
		return lateral <= GIRDLE_SPAN
	# Ribs: alternating columns between the girdles, so a bite landing in a gap
	# reaches the muscle the ribs do not cover. That alternation is what makes
	# the cage read as structure instead of as one plate over the chest, and it
	# is why a rib is never laid against a girdle — two adjacent crossbars are
	# one wide bar, and there is no gap left to bite into.
	return torso > SHOULDER_COL + 1 and torso < PELVIS_COL - 1 \
		and torso % 2 == 1 and lateral <= RIB_SPAN


## Limbs are a bone core running their whole length, with flesh either side.
func _limb_has_bone(_col: int, v: float) -> bool:
	return absf(v) <= 1.0 / float(LIMB_ROWS)
