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
## Their outer corners land exactly on the drawn cap circles.
const HEAD_COLS: int = 4
const TORSO_COLS: int = 20
const TAIL_COLS: int = 2
const BODY_COLS: int = HEAD_COLS + TORSO_COLS + TAIL_COLS
## Odd, so one row straddles the spine and can carry the vertebral column.
const BODY_ROWS: int = 7

# --- limb patch layout ------------------------------------------------------
## Upper bone, lower bone, then a cap over the outer half of the foot circle,
## so the drawn foot is part of the lattice instead of floating unbitable on it.
const LIMB_BONE_COLS: int = 6
const LIMB_FOOT_COLS: int = 2
const LIMB_COLS: int = LIMB_BONE_COLS + LIMB_FOOT_COLS
const LIMB_ROWS: int = 3
const LIMB_KEYS: Array[String] = ["FL", "FR", "RL", "RR"]

# --- skeleton layout --------------------------------------------------------
# The skeleton is a *frame*, not a plate: a skull, a vertebral column one cell
# wide running neck to tail tip, a girdle under each pair of limb sockets, and
# ribs on alternating columns between them. Everywhere else the body is flesh
# over nothing, and a bite that gets through it opens a hole clean to the ground
# — which is the whole point of laying the skeleton out sparsely. If bone sat
# under most of the body there would be no such thing as eating through it, and
# every wound would bottom out on the same pale surface.
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
## length: 2/20 and 10/20 land within one cell of the default shoulder
## (front_limb_t 0.16) and hip (rear_limb_t 0.46) sockets. Both are even, which
## is what leaves a clear column of flesh between each girdle and the nearest
## rib instead of the two fusing into one wide bar.
const SHOULDER_COL: int = 2
const PELVIS_COL: int = 10


## One chunk of tissue a bite knocked loose, in world space.
class Shed extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var layer: int = 0
	var size: float = 3.0


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

	## Cells that have taken any damage, so drawing costs what the damage costs
	## rather than what the lattice costs.
	var touched: PackedByteArray = PackedByteArray()
	var damaged: PackedInt32Array = PackedInt32Array()

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

	func clear_damage() -> void:
		touched.fill(0)
		damaged.clear()
		remaining_hp = full_hp

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
			removed += _erode(p, cell, depth * (1.0 - d2 / r2), at, shed)
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
			shed.append(chunk)

	if removed <= 0.0:
		return 0.0
	p.remaining_hp = maxf(p.remaining_hp - removed, 0.0)
	if p.touched[cell] == 0:
		p.touched[cell] = 1
		p.damaged.append(cell)
	return removed


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
	# the cage read as structure instead of as one plate over the chest.
	return torso > SHOULDER_COL and torso < PELVIS_COL \
		and torso % 2 == 0 and lateral <= RIB_SPAN


## Limbs are a bone core running their whole length, with flesh either side.
func _limb_has_bone(_col: int, v: float) -> bool:
	return absf(v) <= 1.0 / float(LIMB_ROWS)
