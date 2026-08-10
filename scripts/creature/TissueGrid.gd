## Voxel-like tissue: a lattice of body cells, each a depth stack of skin over
## fat over muscle over bone over whatever organ lies beneath.
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
## after the creation menu restructures the spine underneath it.
##
## Top-down means the tissues stack in *depth*, not sideways — you look down at
## skin, and only what a bite has already cleared away is visible beneath it. A
## bite therefore spends its penetration budget strictly outside-in, and bone
## absorbs at a reduced rate and then stops the bite dead.
##
## That last rule is what protects the organs, and it is the whole of what
## protects them: the brain and the heart are cells like any others, laid *under*
## bone in the same stack, so jaws reach them only by grinding through the skull
## or the ribs first. Nothing anywhere says an organ is hard to hit. It is hard to
## hit because it is behind something.
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
const FAT: int = 1
const MUSCLE: int = 2
const BONE: int = 3
const ORGAN: int = 4
const LAYERS: int = 5

## Skin is a rind, not armour: any bite worth the name strips it, and at the
## default depth one strips it across nearly the whole width of the jaws. It
## exists to be broken through, so what a bite reads as is *opening* the body
## rather than scratching it.
const SKIN_HP: float = 0.4
## Fat at a reserve of 1.0, on the fullest part of the trunk. Thin, because the
## default animal is a lean one — BodyPlan thins it further toward the head, the
## tail and the limbs, and `fat_reserve` scales the lot.
const FAT_HP: float = 0.5
## What fat is actually for. Every hit point of it spends FAT_ABSORB of a bite's
## penetration, so a padded animal is not merely carrying more tissue to chew
## through — the same jaws arrive at its muscle shallower. That is the difference
## between fat and simply thicker skin, and it is why the layer is worth having:
## a heavy creature is protected by its build rather than by a toughness number.
const FAT_ABSORB: float = 1.5
## Muscle is where a fight actually happens. Deep enough that the default bite
## takes several passes over the same spot to tear through — so a kill is either
## several bites or a stronger one, never a graze. It is also the layer whose
## *state* is worth reading, skin being a rind and bone a wall, so it has to
## survive long enough to be seen thinning.
const MUSCLE_HP: float = 5.5
## Bone is not merely thicker — it also yields at BONE_YIELD of the incoming
## depth and then consumes the rest of the bite, so a skeleton takes roughly an
## order of magnitude more work to breach than the flesh laid over it.
const BONE_HP: float = 6.0
const BONE_YIELD: float = 0.5
## Organs are soft. They are not protected by being tough — they are protected by
## the skull or the ribcage over them — so once a bite is actually reaching one,
## very little of it survives. That asymmetry is the point: the fight is over the
## bone, and what is behind it is decided the moment the bone gives.
const ORGAN_HP: float = 2.0
## Share of the tissue around a nerve or vessel that has to survive for the run
## through it to be intact. Above this the conduit is untouched; below it, it
## fails quickly. See `_conduit_at`.
const CONDUIT_FLOOR: float = 0.35

# --- lattice layout ---------------------------------------------------------
# Aliased from BodyPlan, which owns them, so the storage code below reads in its
# own terms while there is still exactly one description of the animal.
const BODY_KEY: String = BodyPlan.BODY_KEY
const HEAD_COLS: int = BodyPlan.HEAD_COLS
const TORSO_COLS: int = BodyPlan.TORSO_COLS
const TAIL_COLS: int = BodyPlan.TAIL_COLS
const BODY_COLS: int = BodyPlan.BODY_COLS
const BODY_ROWS: int = BodyPlan.BODY_ROWS
const LIMB_BONE_COLS: int = BodyPlan.LIMB_BONE_COLS
const LIMB_FOOT_COLS: int = BodyPlan.LIMB_FOOT_COLS
const LIMB_COLS: int = BodyPlan.LIMB_COLS
const LIMB_ROWS: int = BodyPlan.LIMB_ROWS
const LIMB_KEYS: Array[String] = BodyPlan.LIMB_KEYS
const SKULL_SPAN: float = BodyPlan.SKULL_SPAN
const RIB_SPAN: float = BodyPlan.RIB_SPAN
const GIRDLE_SPAN: float = BodyPlan.GIRDLE_SPAN
const SHOULDER_COL: int = BodyPlan.SHOULDER_COL
const PELVIS_COL: int = BodyPlan.PELVIS_COL

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


## One connected piece of an animal that is no longer joined to the rest of it.
##
## Not meat, and the distinction is the whole of why this class exists. A `Shed`
## chunk is tissue a bite destroyed and threw clear — it has already stopped being
## anatomy. This is anatomy that is merely somewhere else: every cell of it arrives
## with exactly the hit points it had a moment ago, still stacked skin over fat
## over muscle over bone, still holding whatever organ it grew around. A severed
## leg is a leg. What turns it into meat is the same thing that turns a living leg
## into meat, which is something biting it.
##
## Carried in the lattice's own terms and in world space, because that is all the
## lattice knows. What the world makes of it — where its centre is, what it weighs,
## how it lies on the ground — is the world's business.
class Piece extends RefCounted:
	var cells: int = 0
	## Four world corners per cell, wound as `Patch.corners_of` winds them: the
	## pose the tissue was standing in on the tick it came away.
	var corners: PackedVector2Array = PackedVector2Array()
	## Remaining hit points, `cell * LAYERS + layer` — the same depth stack the
	## body stored, handed over untouched rather than summarised.
	var hp: PackedFloat32Array = PackedFloat32Array()
	## Fat each cell was laid down with, so a piece off a well-padded animal still
	## reads as one once nothing is left to ask.
	var fat_full: PackedFloat32Array = PackedFloat32Array()
	## Which cells of the piece touch which, as a start index per cell into
	## `link_to`. Carried rather than re-derived because adjacency here is a fact
	## about the lattice these cells came out of, and once they have left it there
	## is nothing to ask.
	var link_start: PackedInt32Array = PackedInt32Array()
	var link_to: PackedInt32Array = PackedInt32Array()
	## Where in the animal each cell was. Kept for one purpose only: meat chewed off
	## the piece later has to join into chunks by the same adjacency a bite on a
	## living body joins by, and once the cells have left the lattice there is
	## nothing else to ask.
	var cell_key: PackedStringArray = PackedStringArray()
	var cell_col: PackedInt32Array = PackedInt32Array()
	var cell_row: PackedInt32Array = PackedInt32Array()
	## Tissue standing in it, and that as a fraction of the whole animal — which is
	## how much of the animal's weight walked off with it.
	var flesh: float = 0.0
	var share: float = 0.0
	## The height the tissue was standing at when it stopped being an animal, and
	## how thick it was there. Both absolute, in the same pixels as x and y.
	##
	## Carried for one reason, and it is the reason this axis exists at all: a leg
	## bitten off a standing creature has to fall from the shoulder. The lattice
	## already knew the height of every cell it took — see `Patch.height_of` — so
	## there is nothing to work out here and nothing to guess. Without it the world
	## would have to invent a height for the piece, and every honest invention comes
	## out as zero: a severed leg appearing on the floor under the animal, which is
	## the one thing that reads as a bug rather than as anatomy.
	var height: float = 0.0
	var thickness: float = 0.0


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

	## The third coordinate, rebuilt from the same pose on the same tick.
	##
	## A cell is not a tile on a floor — it is a box of flesh somewhere in the
	## air, and these two arrays are what say where. `mids` is the height of the
	## middle of each cross-section, one per station, because a body's centre line
	## does not move up and down across its own width: the neck rises, the back is
	## level, the leg runs down to the floor, and every corner of a given station
	## shares that. `halves` is how far the body reaches above and below it at each
	## corner, which *does* vary across the width, and by a great deal — a body is
	## round, so it is at its deepest over the spine and tapers to nothing at the
	## flank. Storing them apart is not a saving; it is the honest shape of the
	## fact, and it is why a cell out on the flank is the thin sliver it should be
	## rather than a full-depth slab.
	##
	## Together they give every cell an absolute height band, which is the whole
	## point: `band_of` below is what lets a bite reach a knee and miss the belly
	## a hand's breadth above it, and what lets a small animal walk through the
	## gap between the two.
	var mids: PackedFloat32Array = PackedFloat32Array()
	var halves: PackedFloat32Array = PackedFloat32Array()

	## Remaining hit points, indexed `cell * layers + layer`.
	var hp: PackedFloat32Array = PackedFloat32Array()
	## 1 where the skeleton runs under the cell. Cells without it open into a
	## hole clean through the body once their muscle is gone.
	var bone: PackedByteArray = PackedByteArray()
	## Which of the plan's regions each cell belongs to, and which organ — if any —
	## lies at the bottom of its stack. Both are fixed at build time: a cell cannot
	## change what part of the animal it is, only how much of it is left.
	var region: PackedByteArray = PackedByteArray()
	var organ: PackedByteArray = PackedByteArray()

	## Cells that have taken any damage. Kept so a query can walk the wounds
	## rather than the whole lattice.
	var touched: PackedByteArray = PackedByteArray()
	var damaged: PackedInt32Array = PackedInt32Array()

	## 1 where every layer is spent. A gone cell is a hole in the creature: the
	## renderer skips it, so the world behind shows through, and the collision
	## and hit-test queries below shrink away from it.
	var gone: PackedByteArray = PackedByteArray()
	var gone_count: int = 0

	## 1 where the cell is still joined to the rest of the animal by some unbroken
	## run of surviving tissue. Written only by `resolve_attachment`, and read as
	## the whole of what severance is: a cell that is standing but no longer
	## attached is a piece of meat that happens to still be lying where it grew.
	var attached: PackedByteArray = PackedByteArray()

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
	## The same rejection on the third axis: every height any cell of this patch
	## occupies. A patch is one structure, so this is usually a tight bound — a
	## leg's is the whole gap under the animal, a head's is a slab at the top of
	## it — and testing it first means a bite aimed under a belly walks no cells
	## of the body at all.
	var zlo: float = 0.0
	var zhi: float = 0.0

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
		mids.resize(cols + 1)
		halves.resize((cols + 1) * _stride)
		hp.resize(cells * layers)
		bone.resize(cells)
		region.resize(cells)
		organ.resize(cells)
		touched.resize(cells)
		gone.resize(cells)
		attached.resize(cells)
		solid.resize(cols * 2)

	func clear_damage() -> void:
		touched.fill(0)
		damaged.clear()
		gone.fill(0)
		gone_count = 0
		attached.fill(1)
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
	##
	## `mid` is how high off the ground the middle of this cross-section is and
	## `thickness` is how far the body reaches above and below it *at the midline*
	## — the two numbers that turn a ring of corners into a slice of a solid.
	##
	## The taper across the width is not a parameter and could not usefully be
	## one: a cross-section is an ellipse, so the depth at lateral fraction `u` is
	## the full depth times `sqrt(1 - u²)` and nothing gets to choose otherwise.
	## That single line is what makes the volume a volume rather than a slab with
	## a height written on it — the cells over the spine are deep, the cells on
	## the flank are thin, and a bite skimming the side of an animal takes the
	## sliver it actually met.
	func set_station(station: int, pos: Vector2, perp: Vector2, half: float,
			mid: float = 0.0, thickness: float = 0.0) -> void:
		var base: int = station * _stride
		var deep: float = absf(thickness)
		mids[station] = mid
		for r in range(_stride):
			var u: float = -1.0 + 2.0 * float(r) / float(rows)
			verts[base + r] = pos + perp * (half * u)
			halves[base + r] = deep * sqrt(maxf(1.0 - u * u, 0.0))
		# Squaring off the cross-section keeps the bounds conservative whatever
		# way `perp` points, for a fraction of the cost of scanning the corners.
		if station == 0:
			lo = Vector2(pos.x - half, pos.y - half)
			hi = Vector2(pos.x + half, pos.y + half)
			zlo = mid - deep
			zhi = mid + deep
		else:
			lo = Vector2(minf(lo.x, pos.x - half), minf(lo.y, pos.y - half))
			hi = Vector2(maxf(hi.x, pos.x + half), maxf(hi.y, pos.y + half))
			zlo = minf(zlo, mid - deep)
			zhi = maxf(zhi, mid + deep)

	func centre_of(cell: int) -> Vector2:
		var i: int = (cell / rows) * _stride + (cell % rows)
		return (verts[i] + verts[i + 1] + verts[i + _stride] + verts[i + _stride + 1]) * 0.25

	## The height of the cell's own centre line — the third coordinate of
	## `centre_of`, and so where whatever runs *inside* the body here lies: the cord
	## in its vertebrae, the great vessel beside them, an organ in the chest.
	func height_of(cell: int) -> float:
		var col: int = cell / rows
		return (mids[col] + mids[col + 1]) * 0.5

	## The heights of the cell's four corners, wound exactly as `corners_of` winds
	## them: `x` is the underside of the body there, `y` the top surface.
	##
	## The pair is what makes a cell a box rather than a tile — between them the two
	## calls place all eight of its corners, in the same pixels. `band_of` above
	## answers the same question flattened to one interval, which is all a bite needs
	## to know; anything drawing the cell as the piece of volume it is needs to know
	## where each corner of it actually stands.
	func surfaces_of(cell: int, out: PackedVector2Array) -> void:
		var col: int = cell / rows
		var i: int = col * _stride + (cell % rows)
		var near: float = mids[col]
		var far: float = mids[col + 1]
		out[0] = Vector2(near - halves[i], near + halves[i])
		out[1] = Vector2(near - halves[i + 1], near + halves[i + 1])
		out[2] = Vector2(far - halves[i + _stride + 1], far + halves[i + _stride + 1])
		out[3] = Vector2(far - halves[i + _stride], far + halves[i + _stride])

	## The heights this one cell occupies — the third coordinate of `centre_of`,
	## and the whole reason the two arrays above exist.
	##
	## The union over the cell's four corners rather than a value at its middle,
	## because a cell is a box and something has to clear all of it to pass. Taken
	## the other way round it would be possible to slip a leg through the corner
	## of a body, which is not a thing bodies allow.
	func band_of(cell: int) -> Vector2:
		var col: int = cell / rows
		var row: int = cell % rows
		var i: int = col * _stride + row
		var near: float = maxf(halves[i], halves[i + 1])
		var far: float = maxf(halves[i + _stride], halves[i + _stride + 1])
		return Vector2(
			minf(mids[col] - near, mids[col + 1] - far),
			maxf(mids[col] + near, mids[col + 1] + far))

	## The heights a run of columns occupies, as one band. What a consumer working
	## on the drawn primitives asks — a bone, a foot, the snout cap, one interval
	## of the torso — because those are runs of columns rather than single cells.
	##
	## `to_col` is exclusive, matching `span_solid`, so the two are always asked
	## about exactly the same piece of animal. What is actually walked is the
	## cross-sections bounding that range — stations `from_col` through `to_col`
	## inclusive — so passing one index twice asks about a single cross-section,
	## which is how to measure the animal's depth somewhere without a sloping cell
	## reporting the slope as thickness.
	func column_band(from_col: int, to_col: int) -> Vector2:
		var first: int = clampi(from_col, 0, cols)
		var last: int = clampi(to_col, first, cols)
		var band: Vector2 = Vector2(mids[first], mids[first])
		for s in range(first, last + 1):
			var base: int = s * _stride
			var deep: float = 0.0
			for r in range(_stride):
				deep = maxf(deep, halves[base + r])
			band.x = minf(band.x, mids[s] - deep)
			band.y = maxf(band.y, mids[s] + deep)
		return band

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
## What this animal is. Everything below reads its layout rather than deciding
## one, which is what lets a different creature be a different plan and nothing
## else.
var plan: BodyPlan = null
## How much fat this species lays down, as a multiple of the plan's profile.
var fat_reserve: float = 1.0

## Tissue standing per region and layer, indexed `region * LAYERS + layer`, and
## the same totals when whole. Maintained as damage lands rather than measured, so
## the functional layer can ask what a region is made of every tick without ever
## walking a cell.
var region_hp: PackedFloat32Array = PackedFloat32Array()
var region_full: PackedFloat32Array = PackedFloat32Array()
## The same stacks at a fat reserve of exactly 1.0 — the ordinary animal of this
## plan, whatever this species actually lays down. It is the ruler the census
## measures tissue volume with: the drawn silhouette is the reference-condition
## body, so hp is converted to volume against *this* stack, and a padded animal
## then genuinely carries more tissue than its silhouette while a lean one
## carries less. Normalising against `region_full` instead would quietly cancel
## the fat out of the weight, which is the one thing fat must not do.
var region_norm: PackedFloat32Array = PackedFloat32Array()
## Fat a `fat_reserve` of exactly 1.0 would lay on this plan. The padding a body
## actually carries is quoted against it, so 1.0 means "an ordinary animal" and
## every other build is a ratio — which is what lets fat move mass without any
## creature's default weight changing.
var fat_reference: float = 0.0
## The same for the two organs, which are single structures rather than regions.
var organ_hp: PackedFloat32Array = PackedFloat32Array()
var organ_full: PackedFloat32Array = PackedFloat32Array()
## Everything this animal was built out of. What a piece leaving is measured
## against, so how much of itself a body has lost is one division.
var full_hp: float = 0.0

## Bumped whenever any cell loses anything. The functional layer recomputes off
## this rather than per tick: an animal nobody has bitten is a body whose
## connectivity cannot have changed, and there is no reason to flood two networks
## to be told so.
var revision: int = 0

## Surviving cells that are no longer joined to the animal — tissue standing where
## it grew and attached to nothing. The cheap guard everything downstream asks
## first: a creature nobody has cut a piece off never walks a cell to be told so.
var detached_count: int = 0
## How much of each region is still joined on, and how much of it is still there
## at all — the two halves of `region_attachment`, accumulated by the same walk
## that decides attachment rather than measured again afterwards.
var _region_attached: PackedFloat32Array = PackedFloat32Array()
var _region_standing: PackedFloat32Array = PackedFloat32Array()

## One address space over the whole animal.
##
## Connectivity does not stop at a patch boundary — a limb's proximal cells and
## the girdle cells at its socket are neighbours — so the walk below needs a
## single index for any cell of any patch. `_patch_list` fixes the order,
## `_base` the first global index of each patch, `_patch_of` the way back.
var _patch_list: Array[Patch] = []
var _base: PackedInt32Array = PackedInt32Array()
var _patch_of: PackedInt32Array = PackedInt32Array()
var _cell_total: int = 0
## Neighbours that are not two cells side by side in the same lattice, by global
## index. Sparse: only the cells either side of a socket have any.
var _joins: Dictionary = {}
## Which piece of the animal each cell currently belongs to, and the revision the
## walk that decided it ran at. Held rather than allocated, because it is sized by
## the creature and a bite must not allocate per cell.
var _component: PackedInt32Array = PackedInt32Array()
var _attached_revision: int = -1
## Where each cell ended up in the piece currently being handed over, or -1. Held
## rather than allocated, for the same reason `_component` is.
var _piece_index: PackedInt32Array = PackedInt32Array()

## Reused corner buffer, so a bite allocates nothing per cell it tests.
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## What one closing took out of each layer of one cell, so erosion reports its
## working without returning an array per cell.
var _taken := PackedFloat32Array()


func _init(p_plan: BodyPlan = null, p_fat_reserve: float = 1.0) -> void:
	plan = p_plan if p_plan != null else BodyPlan.new()
	fat_reserve = maxf(p_fat_reserve, 0.0)
	var body := Patch.new()
	body.configure(BODY_KEY, BODY_COLS, BODY_ROWS, LAYERS)
	patches[BODY_KEY] = body
	for key in LIMB_KEYS:
		var limb := Patch.new()
		limb.configure(key, LIMB_COLS, LIMB_ROWS, LAYERS)
		patches[key] = limb
	region_hp.resize(BodyPlan.REGIONS * LAYERS)
	region_full.resize(BodyPlan.REGIONS * LAYERS)
	region_norm.resize(BodyPlan.REGIONS * LAYERS)
	organ_hp.resize(BodyPlan.ORGAN_NAMES.size())
	organ_full.resize(BodyPlan.ORGAN_NAMES.size())
	_region_attached.resize(BodyPlan.REGIONS)
	_region_standing.resize(BodyPlan.REGIONS)
	_taken.resize(LAYERS)
	# Before `reset`, which finishes by walking it: a lattice has to be able to say
	# what is joined to what from the moment it exists, or the first thing to ask
	# is told the animal is in pieces.
	_build_address_space()
	reset()


## Re-lays the fat without disturbing anything else. Reserve is a species trait
## read live off the params, exactly as the widths are, so moving the slider has
## to re-fill rather than wait for a structural rebuild.
func set_fat_reserve(value: float) -> void:
	if is_equal_approx(value, fat_reserve):
		return
	fat_reserve = maxf(value, 0.0)
	reset()


## Re-lays the lattice against a plan whose layout has changed underneath it —
## girdles moved to sit under the sockets, and therefore bone flags, organ sites
## and the sockets the limbs are welded through. Everything about *where* the
## animal's structures are is rebuilt; nothing about what the lattice is.
func rebuild_layout() -> void:
	_build_address_space()
	reset()


func reset() -> void:
	region_full.fill(0.0)
	region_norm.fill(0.0)
	organ_full.fill(0.0)
	fat_reference = 0.0
	full_hp = 0.0
	for key in patches:
		_fill(patches[key])
		full_hp += patches[key].full_hp
	region_hp = region_full.duplicate()
	organ_hp = organ_full.duplicate()
	revision += 1
	resolve_attachment()


func patch(key: String) -> Patch:
	return patches.get(key, null)


## Whole-creature integrity: 1.0 intact, down to 0.0 stripped to nothing.
func integrity() -> float:
	if full_hp <= 0.0:
		return 1.0
	var left: float = 0.0
	for key in patches:
		left += patches[key].remaining_hp
	return left / full_hp


func patch_integrity(key: String) -> float:
	var p: Patch = patch(key)
	if p == null or p.full_hp <= 0.0:
		return 1.0
	return p.remaining_hp / p.full_hp


## Restores every cell of a patch to intact tissue, laid out by the plan.
##
## This is the only place the plan's profiles are turned into hit points, and it
## is where the whole depth stack of an animal comes from: skin over as much fat
## as the species carries there, over muscle, over bone where there is a skeleton,
## over whichever organ the plan puts underneath.
func _fill(p: Patch) -> void:
	var region_map: PackedByteArray = plan.cell_region[p.key]
	p.full_hp = 0.0
	for c in p.cols:
		for r in p.rows:
			var cell: int = c * p.rows + r
			var lateral: float = p.row_centre(r)
			var solid: bool = plan.has_bone(p.key, c, lateral)
			var organ: int = plan.organ_at(p.key, c, r)
			p.bone[cell] = 1 if solid else 0
			p.region[cell] = region_map[cell]
			p.organ[cell] = organ
			var profile: float = plan.fat_at(p.key, c, lateral)
			var fat: float = FAT_HP * fat_reserve * profile
			fat_reference += FAT_HP * profile
			var base: int = cell * LAYERS
			p.hp[base + SKIN] = SKIN_HP
			p.hp[base + FAT] = fat
			p.hp[base + MUSCLE] = MUSCLE_HP
			p.hp[base + BONE] = BONE_HP if solid else 0.0
			p.hp[base + ORGAN] = ORGAN_HP if organ != BodyPlan.NO_ORGAN else 0.0
			var region_base: int = int(region_map[cell]) * LAYERS
			for layer in LAYERS:
				var have: float = p.hp[base + layer]
				p.full_hp += have
				region_full[region_base + layer] += have
				# The reference stack: fat at reserve 1.0, everything else as laid.
				region_norm[region_base + layer] += \
					FAT_HP * profile if layer == FAT else have
			if organ != BodyPlan.NO_ORGAN:
				organ_full[organ] += ORGAN_HP
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
	# The lattice is posed in three dimensions, so it needs the two things the
	# pose alone does not carry: how high off the ground this body is holding its
	# parts, and how deep it is for its width. Both come off the stature that was
	# solved from the same pose on the same tick — which is also the one the limbs
	# were drawn against, so the heights here cannot disagree with the positions.
	_update_body(creature.body, creature.spine, creature.stature,
		creature.posture.depth_ratio if creature.posture != null else 1.0,
		creature.droop, creature.params.front_limb_t)
	if creature.gait == null:
		return
	# Everything on a limb is quoted against the creature's own ground, so a body
	# in the air carries its legs up with it and this is the only place that has
	# to know.
	var lift: float = creature.stature.elevation if creature.stature != null else 0.0
	for limb in creature.gait.limbs:
		var p: Patch = patch(limb.key)
		if p != null:
			_update_limb(p, limb, creature.size_scale, lift)


## Least share of the trunk the neck may occupy, for a build whose forelimbs are
## carried right up under its jaw.
##
## The lattice runs one continuous strip from the snout to the tail tip, and
## somewhere along it the head's height becomes the back's. Where is not a blend
## factor and it is not a share of the animal: a neck runs from the skull to the
## *shoulder*, so it ends at the pectoral girdle and nowhere else — see
## `_update_body`, which reads it straight off `front_limb_t`.
##
## This is only the floor under that. A quarter of the trunk used to be the whole
## answer, and on a build carrying its shoulders further forward than that the
## girdle sat inside the ramp: the flesh at the shoulder was still on its way down
## off the head, so it was drawn and tessellated a good deal higher than the back
## the leg underneath was actually holding, and the socket ended up grazing the
## underside of its own chest.
const NECK_MIN: float = 0.08


func _update_body(body: BodyShape, spine: Spine, stature: Stature,
		depth_ratio: float, droop: Droop = null, shoulder_t: float = 0.25) -> void:
	var p: Patch = patches[BODY_KEY]
	var last: int = body.last_index
	if last < 2 or body.widths.size() <= last:
		return
	var station: int = 0

	# The two heights the strip runs between, absolute, with whatever the body is
	# doing about elevation already in them. Read rather than derived, because
	# Stature has already worked out what the legs are holding this animal at and
	# a second opinion here could only ever disagree with it.
	var back: float = 0.0
	var crown: float = 0.0
	if stature != null:
		back = stature.reference + stature.elevation
		crown = stature.head_height + stature.elevation

	# Snout cap. Spacing the stations by angle puts every outer corner exactly
	# on the drawn head circle, so the tessellation is inscribed in the
	# silhouette rather than approximating it from outside. A head is about as
	# deep as it is wide, so its thickness is its own radius and the cap is a
	# hemisphere rather than a disc.
	for k in HEAD_COLS:
		var a: float = PI * 0.5 * (float(k) / float(HEAD_COLS))
		p.set_station(station,
			body.head.pos + body.head.fwd * (body.head_radius * cos(a)),
			body.head.perp,
			body.head_radius * sin(a),
			crown,
			body.head_radius * sin(a))
		station += 1

	# Where the neck stops being neck: the pectoral girdle, because that is what a
	# shoulder is. Everything ahead of it is rising to meet the head and everything
	# behind it is back.
	var neck: float = maxf(shoulder_t, NECK_MIN)

	# Torso, at a fixed count of stations along the *clipped* spine, so the
	# lattice is independent of how many particles the chain happens to have.
	for k in range(TORSO_COLS + 1):
		var s: float = float(k) / float(TORSO_COLS) * float(last)
		var i: int = clampi(int(s), 0, last - 1)
		var f: float = s - float(i)
		var perp: Vector2 = spine.perps[i].lerp(spine.perps[i + 1], f)
		perp = perp.normalized() if perp.length_squared() > 0.000001 else spine.perps[i]
		var half: float = lerpf(body.widths[i], body.widths[i + 1], f)
		# Off the skeleton by however far something has hold of the flesh here —
		# see BodyShape.pull, and note that it is the flesh that moves and not the
		# spine. This is what keeps a set of jaws biting the tissue it is visibly
		# tenting up rather than the tissue that would have been there if nothing
		# were pulling on it. Zero on every station of a body nobody is holding,
		# so an animal that is not being bitten tessellates exactly as it did.
		var drawn: Vector2 = body.pull[i].lerp(body.pull[i + 1], f) \
			if body.pull.size() > i + 1 else Vector2.ZERO
		# Down off the head onto the back over the length of the neck, and then
		# along whatever the back is actually doing. Smoothstepped rather than
		# linear so the shoulder is a shoulder: a straight ramp puts a crease at
		# the end of the neck that every band test downstream would then read as a
		# step in the animal.
		#
		# The far end of that ramp is no longer a single number for the whole
		# animal. Between the girdles a back is level and `Droop` says so by
		# reporting exactly `back` there, so the neck arrives where it always did;
		# behind the hips there is nothing holding it up and `Droop` says that
		# instead. One expression covers both because it is one back.
		var along: float = float(k) / float(TORSO_COLS)
		var carried: float = droop.at(along) if droop != null else back
		var mid: float = lerpf(crown, carried, smoothstep(0.0, neck, along))
		p.set_station(station,
			spine.points[i].lerp(spine.points[i + 1], f) + drawn,
			perp, half, mid, half * depth_ratio)
		station += 1

	# Tail cap: the snout cap mirrored around the last cross-section — and at the
	# height the last cross-section actually reached, which on a long tail is a
	# good way below the back it started from.
	var behind: Vector2 = -spine.forwards[last]
	var tip_r: float = body.widths[last]
	var tail_pull: Vector2 = body.pull[last] if body.pull.size() > last else Vector2.ZERO
	var tip_height: float = droop.at(1.0) if droop != null else back
	for k in range(1, TAIL_COLS + 1):
		var a2: float = PI * 0.5 * (float(k) / float(TAIL_COLS))
		var tail_half: float = tip_r * cos(a2)
		p.set_station(station,
			spine.points[last] + tail_pull + behind * (tip_r * sin(a2)),
			spine.perps[last],
			tail_half, tip_height, tail_half * depth_ratio)
		station += 1

	p.live = true


func _update_limb(p: Patch, limb: Limb, scale: float, lift: float) -> void:
	# Mirrors the widths CreatureView strokes the bones with, so the lattice
	# covers exactly what is drawn.
	var upper_half: float = limb.girth(scale) * 0.5
	var lower_half: float = upper_half * 0.72
	var foot_r: float = limb.foot_radius(scale)

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

	# A limb is the one structure that spans the whole gap under an animal, and
	# these three numbers are that gap: the socket the body holds it by, the joint
	# halfway down, and the foot on the floor. Every station between them takes
	# the height its own position along the bone implies, so a leg's cells are a
	# genuine column of flesh from the shoulder to the ground rather than a shape
	# with one height stamped on it. That is what makes the middle of a leg
	# bitable by something that can reach neither the belly above it nor the foot
	# below.
	#
	# The chain is drawn foreshortened — `joints` is `plan` seen through the
	# perspective — but the heights are not projected at all. They are the real
	# ones, in the same pixels as x and y, which is exactly right: the picture is
	# allowed to be a picture, and the volume underneath it is not.
	var hip: float = limb.heights[0] + lift
	var knee: float = limb.heights[1] + lift
	var toe: float = limb.heights[2] + lift

	var span: int = LIMB_BONE_COLS / 2
	var station: int = 0
	for k in range(span):
		var t0: float = float(k) / float(span)
		p.set_station(station,
			limb.joints[0].lerp(limb.joints[1], t0), n0, upper_half,
			lerpf(hip, knee, t0), upper_half)
		station += 1
	var joint_half: float = lerpf(upper_half, lower_half, 0.5)
	p.set_station(station, limb.joints[1], joint_n, joint_half, knee, joint_half)
	station += 1
	# The lower bone flares out into the foot, so the ankle is continuous with
	# the foot circle instead of stepping into it.
	for k in range(1, span + 1):
		var t: float = float(k) / float(span)
		var shaft: float = lerpf(lower_half, foot_r, t)
		p.set_station(station,
			limb.joints[1].lerp(limb.joints[2], t), n1, shaft,
			lerpf(knee, toe, t), shaft)
		station += 1
	for k in range(1, LIMB_FOOT_COLS + 1):
		var a: float = PI * 0.5 * (float(k) / float(LIMB_FOOT_COLS))
		var cap: float = foot_r * cos(a)
		p.set_station(station, limb.joints[2] + d1 * (foot_r * sin(a)), n1, cap, toe, cap)
		station += 1

	p.live = true


# ----------------------------------------------------------------- damage ----

## Erodes every cell the bite mark covers, outside-in, and returns the total
## tissue removed.
##
## The mark is the whole of what a bite is here — a list of tooth contact
## patches with a penetration apiece — so damage lands in the shape of the
## mouth that made it rather than as a disc. A keen mouth leaves a row of deep
## punctures with intact skin between them; a blunt one leaves a broad shallow
## crush. Neither case is written anywhere: both are the same loop over the same
## patches, asked how deep they are over each cell.
##
## Cells are selected by testing their solved world geometry rather than by
## inverting the body-space mapping. That mapping is a curved, tapered, per-tick
## thing with no cheap inverse, whereas the direct test is exact, needs no
## special case at the caps or the elbow bisector, and costs a few hundred
## comparisons on the rare ticks a bite actually lands. Bites also cross
## structures — jaws closing on a flank catch the leg over it — which a query
## routed through a single hit region could not express.
##
## `shed` collects the chunks that broke off, for the world to scatter.
##
## The vertical half of the test is asked of each *cell* rather than of the
## animal, and it costs one comparison against a band the lattice already
## carries. Jaws closed at knee height on a tall animal take the cells of the leg
## that are at knee height: not the shoulder above them, not the foot below them,
## and not the belly the mark's footprint happens to lie under. Nothing here
## knows what a leg or a belly is — it is the same loop over the same cells,
## asked one more question about each. And because a body's own cells stand at
## different heights, a bite aimed over the back of a browsing animal takes its
## neck and leaves the trunk beneath, which no structure-wide band could express.
func bite(mark: BiteMark, shed: Array) -> float:
	if mark == null or mark.is_empty():
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
		if mark.hi.x < p.lo.x or mark.lo.x > p.hi.x \
				or mark.hi.y < p.lo.y or mark.lo.y > p.hi.y:
			continue
		# The same rejection on the third axis, and it is the cheap one: a whole
		# structure standing clear above or below the jaws is discarded for the
		# price of two comparisons, and no cell of it is ever visited.
		if not mark.reaches(Vector2(p.zlo, p.zhi)):
			continue
		for cell in p.cells:
			if not mark.reaches(p.band_of(cell)):
				continue
			var at: Vector2 = p.centre_of(cell)
			# Expanded by the cell's own size, because a tooth finer than the
			# flesh's grain still marks the cell it landed in — see
			# BiteMark.depth_over, which is what actually resolves that case.
			var grain: float = p.extent_of(cell)
			if at.x + grain < mark.lo.x or at.x - grain > mark.hi.x \
					or at.y + grain < mark.lo.y or at.y - grain > mark.hi.y:
				continue
			p.corners_of(cell, _quad)
			var depth: float = mark.depth_over(at, _quad)
			if depth <= 0.0:
				continue
			removed += _erode(p, cell, depth, at, loose)
	coalesce_shed(loose, shed)
	return removed


## Spends one closing's worth of penetration down one cell's depth stack, outside
## in, and reports what it took out of each layer in `taken`.
##
## Static, and given nothing but a run of hit points, because this is what flesh
## does under a bite rather than what a creature does. The same rule has to hold
## for a leg still on an animal and for that same leg once it is lying on the
## ground in somebody else's jaws, or a piece of meat would change its nature by
## coming off. Everything the two callers do differently — region totals, organs,
## which layers come away in pieces — they do with the answer rather than inside
## it.
static func erode_stack(hp: PackedFloat32Array, base: int, budget: float,
		taken: PackedFloat32Array) -> float:
	taken.fill(0.0)
	var removed: float = 0.0
	for layer in LAYERS:
		if budget <= 0.0:
			break
		var idx: int = base + layer
		var have: float = hp[idx]
		if have <= 0.0:
			continue
		var take: float = minf(budget, have)
		if layer == FAT:
			# Fat is a cushion, so it costs the bite more than it loses: every hit
			# point of it spends FAT_ABSORB of the penetration. That is the whole of
			# how padding protects — the layer under it is reached shallower, or not
			# reached at all — and it needs no rule anywhere about being hard to bite.
			take = minf(budget / FAT_ABSORB, have)
			budget -= take * FAT_ABSORB
		elif layer == BONE:
			take = minf(budget * BONE_YIELD, have)
			budget = 0.0  # nothing gets past bone until the bone itself is gone
		else:
			budget -= take
		hp[idx] = have - take
		taken[layer] = take
		removed += take
	return removed


## The chunk one destroyed soft layer of one cell throws clear.
##
## Soft tissue comes away in pieces; bone is ground down in place, and an organ is
## pulped where it lies rather than thrown clear of a body whose skull or ribcage a
## bite has only just got through. Shared with loose meat, which sheds by exactly
## the same rule for exactly the same reason `erode_stack` is shared.
static func shed_layer(layer: int, at: Vector2, extent: float, angle: float) -> Shed:
	if layer == BONE or layer == ORGAN:
		return null
	var chunk := Shed.new()
	chunk.pos = at
	chunk.layer = layer
	chunk.size = maxf(extent * 0.9, 1.5)
	chunk.mass = chunk.size * chunk.size
	chunk.angle = angle
	return chunk


func _erode(p: Patch, cell: int, budget: float, at: Vector2, shed: Array) -> float:
	var base: int = cell * LAYERS
	var removed: float = erode_stack(p.hp, base, budget, _taken)
	if removed <= 0.0:
		return 0.0
	var region_base: int = int(p.region[cell]) * LAYERS
	var organ: int = int(p.organ[cell])
	for layer in LAYERS:
		var take: float = _taken[layer]
		if take <= 0.0:
			continue
		region_hp[region_base + layer] = maxf(region_hp[region_base + layer] - take, 0.0)
		if layer == ORGAN and organ != BodyPlan.NO_ORGAN:
			organ_hp[organ] = maxf(organ_hp[organ] - take, 0.0)
		if p.hp[base + layer] > 0.0:
			continue
		var chunk: Shed = shed_layer(layer, at, p.extent_of(cell), p.angle_of(cell))
		if chunk != null:
			chunk.patch_key = p.key
			chunk.col = cell / p.rows
			chunk.row = cell % p.rows
			shed.append(chunk)

	revision += 1
	p.remaining_hp = maxf(p.remaining_hp - removed, 0.0)
	if p.touched[cell] == 0:
		p.touched[cell] = 1
		p.damaged.append(cell)
	if _cell_is_empty(p, base):
		p.retire(cell)
	return removed


## Whether a cell has nothing left in any layer. Written as a loop over the stack
## rather than a list of the layers that happened to exist when it was authored:
## adding a tissue and forgetting this test is how a body ends up with holes that
## still have something in them.
func _cell_is_empty(p: Patch, base: int) -> bool:
	for layer in LAYERS:
		if p.hp[base + layer] > 0.0:
			return false
	return true


# ------------------------------------------------------------ attachment ----
# What is still joined to what. Everything above answers questions about one
# place on the animal; this answers the only question that is about two — whether
# there is still any run of flesh between them.

## Lays out the one index space the walk below runs over, and the joins that are
## not simply two cells side by side in it. Built once: which cells touch which is
## a fact about the plan, and nothing a bite does can change it.
func _build_address_space() -> void:
	_patch_list.clear()
	_patch_list.append(patches[BODY_KEY])
	for key in LIMB_KEYS:
		_patch_list.append(patches[key])
	_base.resize(_patch_list.size())
	_cell_total = 0
	for index in _patch_list.size():
		_base[index] = _cell_total
		_cell_total += _patch_list[index].cells
	_patch_of.resize(_cell_total)
	for index in _patch_list.size():
		for cell in _patch_list[index].cells:
			_patch_of[_base[index] + cell] = index
	_component.resize(_cell_total)
	_piece_index.resize(_cell_total)

	# The sockets. A limb's proximal column is welded to the girdle cells the plan
	# says it hangs from, and that is the whole of what makes a limb part of the
	# animal rather than a separate lattice that happens to be drawn next to it.
	_joins.clear()
	for index in range(1, _patch_list.size()):
		var p: Patch = _patch_list[index]
		var socket: PackedInt32Array = plan.limb_socket_cells(p.key)
		for row in p.rows:
			for cell in socket:
				_link(_base[index] + row, _base[0] + cell)


func _link(a: int, b: int) -> void:
	_append_join(a, b)
	_append_join(b, a)


func _append_join(at: int, other: int) -> void:
	var links: PackedInt32Array = _joins.get(at, PackedInt32Array())
	links.append(other)
	_joins[at] = links


## Re-reads which cells are still joined to the animal, and what that adds up to
## per region.
##
## One flood fill over surviving tissue. A cell with anything left in any layer
## conducts, and a cell with nothing left does not — so skin, fat, muscle and bone
## are not four rules about what holds a part on but one, and a piece stays on the
## animal for exactly as long as *some* tissue still bridges the gap to it. Grind
## a leg's bone through and it hangs by its meat; take the meat as well and it
## hangs by its skin; take that too and it is off. Nothing anywhere had to be told
## that is how it works.
##
## The largest surviving piece is the animal and everything else has come off it.
## That is deliberately not a rule about where a body's centre is: with no
## privileged cell to be the creature, a bite through the neck leaves the trunk
## walking and drops the head, a bite through the waist keeps whichever half is
## more animal, and nothing can make a body disown itself by eating one lucky
## place in it.
##
## Guarded on the lattice revision, like every other cell walk here: an animal
## nobody has bitten never runs it.
func resolve_attachment() -> void:
	if _attached_revision == revision:
		return
	_attached_revision = revision
	_component.fill(-1)

	var weight := PackedFloat32Array()
	var best: int = -1
	var stack: Array[int] = []
	for start in _cell_total:
		if _component[start] >= 0 or _is_gone(start):
			continue
		var id: int = weight.size()
		var total: float = 0.0
		weight.append(0.0)
		_component[start] = id
		stack.append(start)
		while not stack.is_empty():
			var at: int = stack.pop_back()
			var index: int = _patch_of[at]
			var p: Patch = _patch_list[index]
			var local: int = at - _base[index]
			var row: int = local % p.rows
			total += _stack_hp(p, local * LAYERS)
			# The lattice is a sheet in plan view, so the flanks are its edges and
			# not each other's neighbours: row 0 and the last row do not wrap.
			if row > 0:
				_reach(at - 1, id, stack)
			if row < p.rows - 1:
				_reach(at + 1, id, stack)
			if local >= p.rows:
				_reach(at - p.rows, id, stack)
			if local < p.cells - p.rows:
				_reach(at + p.rows, id, stack)
			if _joins.has(at):
				for other in _joins[at] as PackedInt32Array:
					_reach(other, id, stack)
		weight[id] = total
		# Strictly greater, so an exact tie goes to whichever piece was found
		# first — and cells are walked in a fixed order from the snout, so a body
		# split into two identical halves never flickers between them.
		if best < 0 or total > weight[best]:
			best = id

	detached_count = 0
	_region_attached.fill(0.0)
	_region_standing.fill(0.0)
	for index in _patch_list.size():
		var p: Patch = _patch_list[index]
		var base: int = _base[index]
		p.attached.fill(0)
		for cell in p.cells:
			if p.gone[cell] != 0:
				continue
			var region: int = int(p.region[cell])
			var have: float = _stack_hp(p, cell * LAYERS)
			_region_standing[region] += have
			if _component[base + cell] != best:
				detached_count += 1
				continue
			p.attached[cell] = 1
			_region_attached[region] += have


func _is_gone(global: int) -> bool:
	var index: int = _patch_of[global]
	return _patch_list[index].gone[global - _base[index]] != 0


func _reach(cell: int, id: int, stack: Array[int]) -> void:
	if _component[cell] >= 0 or _is_gone(cell):
		return
	_component[cell] = id
	stack.append(cell)


## How much of a region is still joined to the animal, by the tissue standing in
## it: 1.0 wholly attached, 0.0 come away entirely.
##
## A region with nothing left in it reads as 0 rather than 1, and the distinction
## matters: a limb eaten down to bare grid is off the animal, not perfectly
## attached by the nothing that remains.
func region_attachment(region: int) -> float:
	if region < 0 or region >= _region_standing.size():
		return 0.0
	var standing: float = _region_standing[region]
	return _region_attached[region] / standing if standing > 0.0 else 0.0


## Hands the world every piece that has come away from the animal, and leaves the
## cells it came from empty.
##
## This is the whole of severance, and it is one loop over cells that are no
## longer joined to anything rather than a rule about limbs. A leg eaten through
## at the shoulder empties its entire patch; a foot eaten off at the ankle empties
## the ankle down and leaves the leg above it; a tail bitten through leaves with
## everything behind the cut; a head goes the same way. None of the four is a case
## here. They are the same cells failing the same test, which is the only reason
## the answer stays coherent for a body chewed in a way nobody anticipated.
##
## *Empty* is a state the rest of the system already understands completely — an
## empty cell is not drawn, does not collide, cannot be bitten and reports no
## reach — so a piece leaving needs nothing else written anywhere to stop existing
## everywhere at once.
##
## What leaves is a `Piece` and not a spray of `Shed` chunks, and that is the one
## substantive thing this says. Tissue that has been *destroyed* is meat; tissue
## that has merely stopped being joined on has had nothing done to it at all, and
## is handed over with every hit point it was standing with a moment ago — bone
## and organ included, because nothing here is grinding. The piece is not being
## destroyed, it is leaving.
##
## One piece per surviving component rather than one per severance: a bite that
## takes a leg off at the shoulder and knocks the end off a tail in the same
## closing has parted the animal into three, and grouping by the components the
## attachment walk already found is what makes those two separate things on the
## ground instead of one impossible object.
func take_detached(pieces: Array) -> float:
	if detached_count <= 0:
		return 0.0
	# Nothing has damaged the lattice since the walk ran, so its components are
	# still the answer to which loose cells are loose *together*.
	var groups: Dictionary = {}
	for index in _patch_list.size():
		var p: Patch = _patch_list[index]
		var base: int = _base[index]
		for cell in p.cells:
			if p.gone[cell] != 0 or p.attached[cell] != 0:
				continue
			var id: int = _component[base + cell]
			var members: PackedInt32Array = groups.get(id, PackedInt32Array())
			members.append(base + cell)
			groups[id] = members

	var removed: float = 0.0
	for id in groups:
		var piece: Piece = _take_piece(groups[id])
		if piece == null:
			continue
		removed += piece.flesh
		pieces.append(piece)
	# Everything that had come away has now gone, so nothing is left detached until
	# the next cut makes something so. The walk agrees on the following tick; this
	# is only what stops the loop above being re-run in the meantime.
	detached_count = 0
	if removed <= 0.0:
		return 0.0
	revision += 1
	return removed


## Lifts one component's worth of cells out of the lattice and into a piece.
##
## The cells are copied over whole and then emptied, in that order, so the piece
## carries the body's own numbers rather than a summary of them: what the animal
## loses is exactly what lands on the ground, down to the hit point.
func _take_piece(members: PackedInt32Array) -> Piece:
	var piece := Piece.new()
	piece.cells = members.size()
	if piece.cells <= 0:
		return null
	piece.corners.resize(piece.cells * 4)
	piece.hp.resize(piece.cells * LAYERS)
	piece.fat_full.resize(piece.cells)
	piece.link_start.resize(piece.cells + 1)
	piece.cell_key.resize(piece.cells)
	piece.cell_col.resize(piece.cells)
	piece.cell_row.resize(piece.cells)
	_piece_index.fill(-1)
	for i in piece.cells:
		_piece_index[members[i]] = i

	var links := PackedInt32Array()
	for i in piece.cells:
		var global: int = members[i]
		var index: int = _patch_of[global]
		var p: Patch = _patch_list[index]
		var cell: int = global - _base[index]
		var col: int = cell / p.rows
		var base: int = cell * LAYERS
		piece.cell_key[i] = p.key
		piece.cell_col[i] = col
		piece.cell_row[i] = cell % p.rows

		# The pose the tissue was standing in on the tick it stopped being part of
		# an animal. Nothing will rebuild these corners again — that is what having
		# come off *is* — so this is the shape the piece keeps.
		p.corners_of(cell, _quad)
		for k in 4:
			piece.corners[i * 4 + k] = _quad[k]
		# ...and the third coordinate of the same pose, which is where it falls
		# from. Averaged over the cells rather than taken off one, because a piece
		# is a whole structure and the height it drops from is the height of the
		# thing as a whole: a leg taken off at the shoulder starts its fall from
		# halfway down itself, not from the socket and not from the toe.
		var band: Vector2 = p.band_of(cell)
		piece.height += p.height_of(cell)
		piece.thickness += (band.y - band.x) * 0.5
		piece.fat_full[i] = FAT_HP * fat_reserve \
			* plan.fat_at(p.key, col, p.row_centre(cell % p.rows))

		var region_base: int = int(p.region[cell]) * LAYERS
		var organ: int = int(p.organ[cell])
		var lost: float = 0.0
		for layer in LAYERS:
			var have: float = p.hp[base + layer]
			piece.hp[i * LAYERS + layer] = have
			if have <= 0.0:
				continue
			p.hp[base + layer] = 0.0
			lost += have
			region_hp[region_base + layer] = maxf(region_hp[region_base + layer] - have, 0.0)
			if layer == ORGAN and organ != BodyPlan.NO_ORGAN:
				organ_hp[organ] = maxf(organ_hp[organ] - have, 0.0)
		piece.flesh += lost
		p.remaining_hp = maxf(p.remaining_hp - lost, 0.0)

		piece.link_start[i] = links.size()
		_append_piece_links(global, links)
		if p.touched[cell] == 0:
			p.touched[cell] = 1
			p.damaged.append(cell)
		p.retire(cell)

	piece.link_start[piece.cells] = links.size()
	piece.link_to = links
	piece.share = piece.flesh / full_hp if full_hp > 0.0 else 0.0
	piece.height /= float(piece.cells)
	piece.thickness /= float(piece.cells)
	return piece


## The neighbours of one cell that left in the same piece it did. Read off the
## same adjacency the attachment walk uses, sockets included, so a piece that took
## a shoulder and the leg hanging from it knows the two are joined.
func _append_piece_links(global: int, links: PackedInt32Array) -> void:
	var index: int = _patch_of[global]
	var p: Patch = _patch_list[index]
	var local: int = global - _base[index]
	var row: int = local % p.rows
	if row > 0:
		_append_member(global - 1, links)
	if row < p.rows - 1:
		_append_member(global + 1, links)
	if local >= p.rows:
		_append_member(global - p.rows, links)
	if local < p.cells - p.rows:
		_append_member(global + p.rows, links)
	if _joins.has(global):
		for other in _joins[global] as PackedInt32Array:
			_append_member(other, links)


func _append_member(global: int, links: PackedInt32Array) -> void:
	var at: int = _piece_index[global]
	if at >= 0:
		links.append(at)


## Joins orthogonally adjacent cells from the same tissue layer and anatomical
## patch into one torn piece. The lattice remains useful collision/damage data,
## but it no longer dictates the scale of the visible meat.
##
## Static, and shared with loose meat for the same reason `erode_stack` is: a
## mouthful chewed off a severed leg is a mouthful of leg, and it should arrive in
## the world at the same scale as one bitten off the animal that was still wearing
## it.
static func coalesce_shed(loose: Array, shed: Array) -> void:
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


# ------------------------------------------------------------------ heights ----
# The vertical counterparts of the three solidity queries above, addressed
# identically so a caller asking "how much of this is left" and "where is it"
# is always talking about the same piece of animal. Together they are how the
# rest of the game gets at the third axis without knowing a cell exists: a
# contact pass, a hit test and a limb router all work on drawn primitives, and
# these turn each primitive back into the band its cells actually occupy.
#
# Every one of them answers UNBOUNDED before the pose has been sampled. That is
# the fail-open the whole layer depends on: a band nobody has computed yet must
# never be allowed to *prevent* an interaction, or a creature would spend its
# first tick unable to touch anything.

## Heights the torso occupies at normalised position `t` along the clipped spine
## — the same address `body_solid` takes.
func body_band(t: float) -> Vector2:
	var p: Patch = patches[BODY_KEY]
	if not p.live:
		return Volume.UNBOUNDED
	var col: int = HEAD_COLS + clampi(int(t * float(TORSO_COLS)), 0, TORSO_COLS - 1)
	return p.column_band(col, col + 1)


## The same, for the snout cap the head is hit-tested as.
func head_band() -> Vector2:
	var p: Patch = patches[BODY_KEY]
	if not p.live:
		return Volume.UNBOUNDED
	return p.column_band(0, HEAD_COLS)


## The same, for one drawn limb primitive: 0 = upper bone, 1 = lower, 2 = foot.
func limb_band(key: String, segment: int) -> Vector2:
	var p: Patch = patch(key)
	if p == null or not p.live:
		return Volume.UNBOUNDED
	var half: int = LIMB_BONE_COLS / 2
	if segment == 0:
		return p.column_band(0, half)
	if segment == 1:
		return p.column_band(half, LIMB_BONE_COLS)
	return p.column_band(LIMB_BONE_COLS, LIMB_COLS)


## Every height any part of this animal stands in. The broad-phase answer, and
## the only one that is about the creature rather than about a place on it.
func whole_band() -> Vector2:
	var band: Vector2 = Volume.NOWHERE
	for key in patches:
		var p: Patch = patches[key]
		if p.live:
			band = Volume.union(band, Vector2(p.zlo, p.zhi))
	return Volume.UNBOUNDED if band.x > band.y else band


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
	return _stack_hp(p, _cell_base(p, col, lateral))


func _cell_base(p: Patch, col: int, lateral: float) -> int:
	var row: int = clampi(int((lateral + 1.0) * 0.5 * float(p.rows)), 0, p.rows - 1)
	return (clampi(col, 0, p.cols - 1) * p.rows + row) * LAYERS


## Everything still standing in one cell. Fat counts: it is tissue, and jaws
## closed on a well-padded flank have hold of more than jaws closed on a lean one.
func _stack_hp(p: Patch, base: int) -> float:
	var total: float = 0.0
	for layer in LAYERS:
		total += p.hp[base + layer]
	return total


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
	return _within(center, radius, false)


## The soft half of the same footprint: skin over fat, and nothing beneath them.
##
## A different question from the one above, asked by the one thing that cares
## which layer it has hold of. What a pull has to *part* is the whole stack —
## that is `flesh_within`, and it decides whether a mouthful comes away. What
## *gives*, long before anything parts, is only the skin and the fat: they are
## loose over the muscle and slide on it. So a set of jaws tents a well-padded
## flank a long way up and barely marks a lean one, and a body eaten down past
## its fat stops stretching, because what stretched is gone.
##
## Over the footprint rather than the one cell under the anchor, for exactly the
## reason given above: the jaws have just bitten through the skin they are
## holding, so the single cell at the bind reads as almost nothing while the
## mouthful around it is intact. What is being drawn out is the flesh in the
## mouth, not the puncture in the middle of it.
func soft_within(center: Vector2, radius: float) -> float:
	return _within(center, radius, true)


func _within(center: Vector2, radius: float, soft_only: bool) -> float:
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
			total += p.hp[base + SKIN] + p.hp[base + FAT] if soft_only \
				else _stack_hp(p, base)
	return total / float(count) if count > 0 else 0.0


# ------------------------------------------------------------- structures ----
# What the functional layer reads. Everything above answers questions about
# *tissue* — how far the body reaches, how much a set of jaws has hold of. These
# answer questions about *anatomy*: how much of a muscle is left, whether a nerve
# still runs, whether a bone is still continuous.
#
# None of them stores anything. A severed nerve is not a flag set by a bite; it
# is what the cells along that nerve's run add up to when something asks. That is
# the whole reason damage never has to be classified as it lands: a bite erodes
# cells, and what those cells were is read afterwards, by whoever cares.

## Fraction of one layer still standing across a whole region — its surviving
## muscle, its remaining fat, whatever it is asked for. O(1): the totals are
## carried as damage lands rather than measured here.
func region_layer(region: int, layer: int) -> float:
	var i: int = region * LAYERS + layer
	if i < 0 or i >= region_full.size() or region_full[i] <= 0.0:
		return 1.0
	return clampf(region_hp[i] / region_full[i], 0.0, 1.0)


## Fraction of one layer still standing over a span of columns — how much fibre a
## single muscle group has left, as opposed to how much its whole region has.
##
## Walked rather than accumulated, because a group is a slice of a region and
## there are only a handful of them. Called on the ticks the lattice changed.
func layer_span(patch_key: String, from_col: int, to_col: int, layer: int) -> float:
	var p: Patch = patch(patch_key)
	if p == null:
		return 1.0
	var left: float = 0.0
	var full: float = 0.0
	var reference: float = _layer_reference(layer)
	for col in range(maxi(from_col, 0), mini(to_col, p.cols)):
		for row in p.rows:
			var cell: int = col * p.rows + row
			full += reference
			if p.gone[cell] == 0:
				left += p.hp[cell * LAYERS + layer]
	return clampf(left / full, 0.0, 1.0) if full > 0.0 else 1.0


func _layer_reference(layer: int) -> float:
	match layer:
		SKIN: return SKIN_HP
		FAT: return FAT_HP * fat_reserve
		MUSCLE: return MUSCLE_HP
		BONE: return BONE_HP
		_: return ORGAN_HP


## How much fat one cell was *built* with — the plan's profile there, times this
## species' reserve.
##
## What a cell's surviving fat has to be quoted against, because the plan lays
## down more over a flank than over an ankle and both should read as full when
## they are. Lives here rather than in whoever is drawing, so a cell rendered on
## the creature, on a severed leg and in the anatomy panel is measured the same
## way in all three.
func fat_capacity(p: Patch, cell: int) -> float:
	if p == null:
		return FAT_HP * fat_reserve
	return FAT_HP * fat_reserve \
		* plan.fat_at(p.key, cell / p.rows, p.row_centre(cell % p.rows))


## Fraction of one layer still standing across the whole animal. O(1), off the
## same per-region totals the functional layer reads.
func layer_left(layer: int) -> float:
	var left: float = 0.0
	var full: float = 0.0
	for region in BodyPlan.REGIONS:
		var i: int = region * LAYERS + layer
		left += region_hp[i]
		full += region_full[i]
	return clampf(left / full, 0.0, 1.0) if full > 0.0 else 1.0


## What the animal is currently made *of*: the share of everything still standing
## in it that is in one layer, 0..1 across the whole depth stack.
##
## The sibling of `layer_left`, and the difference between the two is the
## difference between "how much of its muscle has this creature lost" and "how
## much of this creature is muscle". The first is a wound; the second is a build,
## and it moves when a species lays on fat or when a bite takes a limb off.
##
## Quoted in hit points because those are already the game's currency for weight:
## `Physique.mass` scales the drawn volume by `integrity()`, which is standing hit
## points over the hit points the body was built with — so a creature that has lost
## a third of its tissue weighs a third less, and this says which third. Giving
## each tissue a density of its own here would be a second notion of mass that
## nothing else in the game agreed with.
func layer_share(layer: int) -> float:
	var left: float = 0.0
	var total: float = 0.0
	for region in BodyPlan.REGIONS:
		var base: int = region * LAYERS
		for each in LAYERS:
			total += region_hp[base + each]
		left += region_hp[base + layer]
	return left / total if total > 0.0 else 0.0


## Cells the animal was built out of, and how many of them are now holes.
func cell_count() -> int:
	var total: int = 0
	for key in patches:
		total += (patches[key] as Patch).cells
	return total


func gone_count() -> int:
	var total: int = 0
	for key in patches:
		total += (patches[key] as Patch).gone_count
	return total


## How much padding the body is actually carrying, against an ordinary animal of
## the same plan. 1.0 is that animal, above is a well-fed one, and it falls as fat
## is bitten away — so a creature that has been opened up gets lighter for the
## same reason it gets weaker.
func fat_carried() -> float:
	if fat_reference <= 0.0:
		return 1.0
	var left: float = 0.0
	for region in BodyPlan.REGIONS:
		left += region_hp[region * LAYERS + FAT]
	return left / fat_reference


## How much of an organ is left, 1.0 whole to 0.0 destroyed.
func organ(which: int) -> float:
	if which <= 0 or which >= organ_full.size() or organ_full[which] <= 0.0:
		return 1.0
	return clampf(organ_hp[which] / organ_full[which], 0.0, 1.0)


## Whether a nerve or vessel still runs, 1.0 intact to 0.0 severed.
##
## A run is only as good as its worst point — a cord cut anywhere is cut — so
## this is the minimum along it and never an average. An average would let a long
## healthy nerve carry a signal through the place it had been severed.
##
## A shielded conduit is read off the bone enclosing it and an unshielded one off
## the muscle it lies in, which is the one structural difference between the two
## networks: the spinal cord survives inside its vertebrae until the vertebra
## itself is broken, while the great vessel lying against it is opened as soon as
## the flesh over it is taken.
func conduit(run: BodyPlan.Conduit) -> float:
	var p: Patch = patch(run.patch_key)
	if p == null or run.cells.is_empty():
		return 1.0
	var worst: float = 1.0
	# The crossing first, where there is one. A limb's run comes in over the
	# girdle from the vertebral column, and those cells are as much a part of it
	# as the ones down the leg — so a shoulder chewed to the bone cuts the nerve to
	# a limb that is otherwise untouched, which is the whole point of asking about
	# a run rather than about a place.
	var link: Patch = patch(run.link_key) if not run.link_key.is_empty() else null
	if link != null:
		for cell in run.link_cells:
			worst = minf(worst, _conduit_at(link, cell, run.shielded))
			if worst <= 0.0:
				return 0.0
	for cell in run.cells:
		worst = minf(worst, _conduit_at(p, cell, run.shielded))
		if worst <= 0.0:
			return 0.0
	return worst


func _conduit_at(p: Patch, cell: int, shielded: bool) -> float:
	if p.gone[cell] != 0:
		return 0.0
	var base: int = cell * LAYERS
	var around: float = p.hp[base + BONE] / BONE_HP if shielded and p.bone[cell] != 0 \
		else p.hp[base + MUSCLE] / MUSCLE_HP
	# A nerve is a thread through a cell, not a share of it. Scratching the
	# vertebra does not fray the cord inside it — what matters is whether the
	# thing enclosing it has substantially given, so the response is flat until
	# the tissue is most of the way gone and then falls off quickly. Read
	# proportionally instead, a body would go numb in exact step with how much of
	# it had been eaten, which is a second hit-point bar wearing a nerve's name.
	return clampf(around / CONDUIT_FLOOR, 0.0, 1.0)


## Whether the skeleton is still continuous across a span of columns, and how
## well — 1.0 sound, 0.0 broken clean through.
##
## Continuity, not quantity. Each column contributes the best bone still standing
## anywhere across it, and the span is the *worst* of those columns, because a
## frame is broken wherever it is broken and the sound bone either side of a break
## does not splint it. That is what makes bone damage structural rather than
## merely another pool: grinding one vertebra through costs the whole run.
func bone_span(patch_key: String, from_col: int, to_col: int) -> float:
	var p: Patch = patch(patch_key)
	if p == null:
		return 1.0
	var weakest: float = 1.0
	var found: bool = false
	for col in range(maxi(from_col, 0), mini(to_col, p.cols)):
		var best: float = 0.0
		var any: bool = false
		for row in p.rows:
			var cell: int = col * p.rows + row
			if p.bone[cell] == 0:
				continue
			any = true
			best = maxf(best, clampf(p.hp[cell * LAYERS + BONE] / BONE_HP, 0.0, 1.0))
		if not any:
			continue
		found = true
		weakest = minf(weakest, best)
	return weakest if found else 1.0


## The vertebra at a fraction along the clipped spine — what holds one joint of
## the animation rig up. This is the bridge between the rig's coordinates and the
## lattice's, and it is deliberately the only one: everything else the rig asks
## about the skeleton goes through a region or a limb key.
func vertebra_at(t: float) -> float:
	var col: int = plan.torso_column(clampf(t, 0.0, 1.0))
	return bone_span(BODY_KEY, col, col + 1)


## The girdle a limb is slung from. A socket whose girdle has been chewed away is
## a limb attached to the animal by meat alone.
func girdle_of(limb_key: String) -> float:
	var col: int = int(plan.limb_socket_col.get(limb_key, -1))
	if col < 0:
		return 1.0
	return bone_span(BODY_KEY, col, col + 1)


## Whether the skeleton still reaches a limb from the animal it hangs off — its
## own bones, and the girdle they are slung from.
##
## Separate from attachment on purpose, and the gap between the two is the case
## this whole layer exists to express: a leg whose bone has been ground through is
## still *on* the animal, held there by the flesh around the break, and is no
## longer held *out* by anything. Attached and unsupported are different answers,
## so they are different questions.
func limb_skeleton(limb_key: String) -> float:
	return minf(bone_span(limb_key, 0, LIMB_BONE_COLS), girdle_of(limb_key))
