## The creature's anatomy as a true 3D lattice of constant-sized cells.
##
## Every cell here is a real box of tissue with a position in the animal's own
## three-dimensional frame: x runs snout to tail tip, y runs flank to flank, z
## runs belly to back. A cell is one tissue and nothing else — skin is only ever
## the outermost shell, fat is a real layer of cells under it, muscle is the bulk
## between the fat and the skeleton, bone is an *internal* frame of skull,
## vertebrae, ribs, girdles and limb cores, organs are distinct volumes locked
## inside the bone that guards them, and the two supply lines are threads of
## their own cells running through everything. Nothing is an overlay: peel the
## skin cells off and the fat cells are physically underneath, because they are
## laid out underneath.
##
## The cell size never changes. A bigger animal is *more* cells; a fatter one
## grows extra shells of fat cells (and genuinely swells for it); a leg built to
## carry a heavy trunk is thicker in muscle cells laid around its own bone. That
## is the whole accounting: the census counted off these cells is what the
## physique weighs, what the anatomy panel prints, and what its specimen view
## draws — one lattice, three readers, no second description anywhere.
##
## The lattice is structure, not damage. Wounds still land in TissueGrid, which
## remains the game's damage ledger; every cell here knows which of that grid's
## columns it stands in, and `refresh_damage` mirrors the ledger onto the cells
## outside-in — so a bite that took half a column's muscle has taken the *outer*
## half of these muscle cells, and the specimen shows the crater where it is.
##
## Built in canonical body space (the animal standing straight) precisely so the
## cells survive the pose being rebuilt every tick: bending a spine moves cells,
## it does not create or destroy them. The HUD poses them through the same
## per-station frames TissueGrid poses its own columns with.
class_name AnatomyLattice
extends RefCounted

# --- the one size ------------------------------------------------------------
## Edge of one cell, in world pixels. Constant for every creature and every
## build: anatomy changes the number and placement of cells, never their size.
const CELL: float = 2.5
const CELL_VOLUME: float = CELL * CELL * CELL

# --- tissues -----------------------------------------------------------------
# The first five index-match TissueGrid's depth layers, which is what lets a
# lattice cell find its own damage in the ledger without a translation table.
const SKIN: int = 0
const FAT: int = 1
const MUSCLE: int = 2
const BONE: int = 3
const ORGAN: int = 4
const NERVE: int = 5
const VESSEL: int = 6
const TISSUES: int = 7

const TISSUE_NAMES: Array[String] = [
	"skin", "fat", "muscle", "bone", "organ", "nerve", "vessel",
]

## What one cell of each tissue weighs, relative to water — the same table the
## old census used for its first five, extended to the two conduit tissues.
const DENSITY: Array[float] = [1.10, 0.92, 1.06, 1.80, 1.05, 1.04, 1.06]

# --- anatomical parts --------------------------------------------------------
# Which named structure a cell belongs to, where it belongs to one at all. Bone
# cells are a skeleton of parts, organ cells have substructures, conduit cells
# know which run they are. Purely descriptive — the census and the damage mirror
# never read it — but it is what makes the specimen inspectable.
const PART_NONE: int = 0
const PART_SKULL: int = 1
const PART_VERTEBRA: int = 2
const PART_RIB: int = 3
const PART_GIRDLE: int = 4
const PART_LIMB_BONE: int = 5
const PART_CEREBRUM: int = 6
const PART_BRAINSTEM: int = 7
const PART_ATRIUM: int = 8
const PART_VENTRICLE: int = 9
const PART_CORD: int = 10
const PART_NERVE_BRANCH: int = 11
const PART_AORTA: int = 12
const PART_ARTERY: int = 13

const PART_NAMES: Array[String] = [
	"", "skull", "vertebra", "rib", "girdle", "limb bone",
	"cerebrum", "brainstem", "atrium", "ventricle",
	"spinal cord", "nerve", "aorta", "artery",
]

# --- layer proportions --------------------------------------------------------
# Layer depths are *shares of the local section*, with small pixel floors, so an
# animal scaled isometrically keeps its composition — a body 1.5x as big in every
# direction is ~3.4x the cells of the same tissues, which is the claim the whole
# census makes — while an elephant's skin still comes out genuinely thicker than
# a lizard's in pixels.
## Depth of the skin shell, as a share of the local radius, and its floor.
const SKIN_SHARE: float = 0.12
const SKIN_MIN: float = 1.1
## Fat depth as a share of the local radius, per unit of the plan's profile at a
## reserve of exactly 1.0 — the fifth of the body's depth the old census already
## claimed for it. The actual shell is this times the profile times the species'
## reserve, so a padded animal carries visibly more shells of fat cells exactly
## where the plan says a body stores it.
const FAT_SHARE: float = 0.20
## How much of the fat laid beyond an ordinary reserve swells the body outward
## rather than packing inward. This is what makes extra fat extra volume: the
## outline the cells fill grows with the reserve, so the cells are additional
## rather than replacements.
const FAT_SWELL: float = 0.7
## Radii of the axial skeleton and its passengers, as shares of the local
## half-depth with pixel floors. The vertebral ring encloses the cord; the aorta
## lies beneath the vertebrae.
const VERT_SHARE: float = 0.30
const VERT_MIN: float = 2.6
const CORD_SHARE: float = 0.13
const CORD_MIN: float = 1.5
const AORTA_SHARE: float = 0.13
const AORTA_MIN: float = 1.8
## How far up the cross-section the vertebral axis rides, as a fraction of the
## local half-depth. A spine is dorsal.
const SPINE_RISE: float = 0.30
## Shell thickness of the hooped bone, as a share of the local radius with a
## floor: ribs are a thin cage, girdle bars are stouter.
const RIB_SHARE: float = 0.14
const RIB_MIN: float = 2.2
const GIRDLE_SHARE: float = 0.22
const GIRDLE_MIN: float = 2.8
## Fraction of the head's radius that is braincase cavity rather than skull.
const BRAIN_RHO: float = 0.55
## The skull is a case, not a filling: a shell of this share of the head's
## radius (with a floor) laid under the skin and fat, with the jaw's own muscle
## working inside it and the brain in the cavity at the back.
const SKULL_SHARE: float = 0.18
const SKULL_MIN: float = 2.4
## The heart's ellipsoid: its long radius as a share of the chest's half-width
## (with a floor), its cross radii as fractions of the local section, and how
## far below the section's midline it hangs.
const HEART_RX_SHARE: float = 0.45
const HEART_RX_MIN: float = 4.6
const HEART_RY: float = 0.40
const HEART_RZ: float = 0.44
const HEART_DROP: float = 0.18
## A limb's bone core, as a share of the limb's radius with a floor, and the
## neurovascular bundle beside it.
const LIMB_BONE_MIN: float = 1.9
const LIMB_BONE_SHARE: float = 0.30
const BUNDLE_R: float = 1.6
## Cells of cover an internal structure needs over it before it is laid at all —
## what makes the skeleton internal *by construction* rather than by assertion.
## A member too slim to bury a bone under its own skin gets no bone cells there;
## the damage ledger still carries the bone, so nothing about combat or support
## changes, but no cell of skeleton ever faces open air.
const BURY: float = 0.75
## Fraction of surviving enclosure below which a conduit cell is cut — the same
## floor TissueGrid reads its conduits with.
const CONDUIT_CUT: float = TissueGrid.CONDUIT_FLOOR
## Cells a structure needs before it is worth insisting it has an inside, and
## how much of such a structure the insistence gives back — see `_keep_a_core`.
const CORE_MIN: int = 4
const CORE_SHARE: float = 0.25

## Patch order: index-stable addressing for `patch_of`.
const PATCH_KEYS: Array[String] = ["body", "FL", "FR", "RL", "RR"]

# --- per-cell storage, parallel arrays ---------------------------------------
## Canonical cell-centre positions, px, in the body's own frame.
var pos: PackedVector3Array = PackedVector3Array()
## Tissue standing in the cell — one tissue per cell, that is the point.
var kind: PackedByteArray = PackedByteArray()
var region: PackedByteArray = PackedByteArray()
var part: PackedByteArray = PackedByteArray()
var organ_of: PackedByteArray = PackedByteArray()
## Where the cell lives in the damage ledger: which patch, which of its cells.
var patch_of: PackedByteArray = PackedByteArray()
var cell_of: PackedInt32Array = PackedInt32Array()
## Posing coordinates: fractional station along the patch, px along the posed
## perpendicular, px along the posed long axis, px above the station's own mid.
var station: PackedFloat32Array = PackedFloat32Array()
var lat: PackedFloat32Array = PackedFloat32Array()
var fore: PackedFloat32Array = PackedFloat32Array()
var lift: PackedFloat32Array = PackedFloat32Array()
## Outward surface direction in the canonical frame, for the specimen's shading.
var normal: PackedVector3Array = PackedVector3Array()
## Outside-in order within the cell's own (ledger cell, tissue) group: 0.0 is
## the outermost cell of the group and the first to go.
var rank: PackedFloat32Array = PackedFloat32Array()
## Six neighbours per cell (-x +x -y +y -z +z), -1 where the body ends.
var neighbor: PackedInt32Array = PackedInt32Array()
## What stands around each cell, as a bitmask: one bit per tissue found among its
## six neighbours, and OPEN_BIT where one of those neighbours is open air.
##
## The question "is this cell on the surface of what is currently being shown" is
## asked of every cell of the animal whenever a filter moves, and asked the
## direct way it is six array reads and six comparisons apiece — which on an
## elephant is a third of a million of them and a visible stall. Asked of this it
## is one read and one AND, because a cell is exposed exactly when something it
## touches is not being drawn.
var around: PackedByteArray = PackedByteArray()
const OPEN_BIT: int = 1 << 7
## Whether the cell's own grid site is odd, summed over the three axes. A
## checkerboard over the whole solid, and therefore a checkerboard over any
## surface through it — which is what lets the specimen drop to half its marks
## when a cell is too small on the page to be worth its own, without the halving
## showing as stripes.
var parity: PackedByteArray = PackedByteArray()
## 1 where the damage ledger says this cell's tissue has been taken.
var gone: PackedByteArray = PackedByteArray()
## 1 where a bite took *this* cell — the actual box of flesh the teeth closed on,
## chosen by where the jaws were rather than worked back out of a column total.
##
## The ledger still says how much of a column's tissue is missing, and it is
## still the only thing that says so. What this adds is where: a bite along the
## top of a back and a bite into the belly under it can take the same amount out
## of the same column of the ledger, and they are not the same wound. The mirror
## below reconciles the two — the ledger's count decides how many cells go, this
## decides which — so nothing about how much damage a bite does has changed and
## everything about where it lands has.
var bitten: PackedByteArray = PackedByteArray()

var count: int = 0

# --- census ------------------------------------------------------------------
## Cells built and cells still standing, indexed `region * TISSUES + tissue`.
var built: PackedInt32Array = PackedInt32Array()
var standing: PackedInt32Array = PackedInt32Array()
var built_total: int = 0
var standing_total: int = 0
## The same, density-weighted — the mass numerator.
var built_units: float = 0.0
var standing_units: float = 0.0
## Density-weighted axial (trunk) census, intact: what sizes the limbs.
var axial_units: float = 0.0

## What the lattice was built from, so `ensure` can tell a redundant call from a
## body that actually changed.
var _signature: int = 0
## The ledger revision the damage mirror was last synced to.
var _synced: int = -2
## Ledger cell -> the lattice cells standing in it, per patch index: an Array of
## plain int Arrays, because packed arrays nested in containers copy on read.
var _cell_index: Array = []
## The cells of each named organ, gathered once at build. Small, fixed, and the
## difference between the specimen finding its heart in a hundred cells and
## finding it by walking every cell in an elephant twice a frame.
var _organ_cells: Array = []
## Canonical grid position -> cell index, kept from the build for neighbour and
## point queries.
var _grid: Dictionary = {}


# ------------------------------------------------------------------- build ----

## Rebuilds if — and only if — the body's description changed. Returns whether a
## rebuild ran. `depth_ratio` is the posture's, `load` the per-girdle mass each
## limb is built to hold (x fore, y hind), both quoted exactly as Physique quotes
## them so the lattice and the physique describe one animal.
func ensure(plan: BodyPlan, p: CreatureParams, scale: float, depth_ratio: float,
		fat_reserve: float, load: Vector2) -> bool:
	var sig: int = _describe(plan, p, scale, depth_ratio, fat_reserve, load)
	if sig == _signature and count > 0:
		return false
	_signature = sig
	_build(plan, p, scale, depth_ratio, fat_reserve, load)
	return true


func _describe(plan: BodyPlan, p: CreatureParams, scale: float, depth_ratio: float,
		fat_reserve: float, load: Vector2) -> int:
	return hash([
		p.segment_count, snappedf(p.segment_length, 0.01), snappedf(scale, 0.001),
		snappedf(p.body_width, 0.001), snappedf(p.head_width, 0.01),
		snappedf(p.chest_width, 0.01), snappedf(p.waist_width, 0.01),
		snappedf(p.hip_width, 0.01), snappedf(p.tail_tip_width, 0.01),
		p.tail_enabled, snappedf(p.front_limb_t, 0.001), snappedf(p.rear_limb_t, 0.001),
		snappedf(p.arm_length, 0.01), snappedf(p.leg_length, 0.01),
		snappedf(p.fore_upper_share, 0.001), snappedf(p.hind_upper_share, 0.001),
		snappedf(p.fore_swing_deg, 0.1), snappedf(p.hind_swing_deg, 0.1),
		snappedf(p.fore_fold_range, 0.005), snappedf(p.hind_fold_range, 0.005),
		snappedf(depth_ratio, 0.001), snappedf(fat_reserve, 0.001),
		snappedf(load.x, 0.005), snappedf(load.y, 0.005),
		plan.shoulder_col, plan.pelvis_col,
	])


func _build(plan: BodyPlan, p: CreatureParams, scale: float, depth_ratio: float,
		fat_reserve: float, load: Vector2) -> void:
	pos = PackedVector3Array()
	kind = PackedByteArray()
	region = PackedByteArray()
	part = PackedByteArray()
	organ_of = PackedByteArray()
	patch_of = PackedByteArray()
	cell_of = PackedInt32Array()
	station = PackedFloat32Array()
	lat = PackedFloat32Array()
	fore = PackedFloat32Array()
	lift = PackedFloat32Array()
	normal = PackedVector3Array()
	rank = PackedFloat32Array()
	_grid.clear()
	count = 0

	# The same width profile the silhouette is drawn from — one description of
	# the animal, sampled rather than restated.
	var n: int = maxi(p.segment_count, 2)
	var profile := PackedFloat32Array()
	profile.resize(n)
	BodyShape.section_profile(p, scale, profile)
	var full_len: float = float(n - 1) * p.segment_length * scale
	var clip: float = 1.0 if p.tail_enabled else BodyPlan.tail_t(p.rear_limb_t)
	var length: float = full_len * clip

	_carve_body(plan, profile, clip, length, depth_ratio, fat_reserve)
	for key in BodyPlan.LIMB_KEYS:
		_carve_limb(plan, p, key, profile, clip, length, depth_ratio, scale,
			fat_reserve, load)
	_finish(plan)


## The trunk, the head cap and the tail cap: one continuous solid of cells laid
## slice by slice along the long axis, exactly the run of cross-sections
## TissueGrid tessellates — so every cell lands in a ledger column that exists.
func _carve_body(plan: BodyPlan, profile: PackedFloat32Array, clip: float,
		length: float, depth_ratio: float, fat_reserve: float) -> void:
	var head_r: float = profile[0]
	var tip_r: float = maxf(_profile_at(profile, clip), 0.8)
	var x0: int = floori(-head_r / CELL)
	var x1: int = ceili((length + tip_r) / CELL)
	for ix in range(x0, x1 + 1):
		var x: float = (float(ix) + 0.5) * CELL
		# Half-width, half-depth and the fractional ledger station of this slice.
		var a: float = 0.0
		var b: float = 0.0
		var s: float = 0.0
		var in_head: bool = x < 0.0
		var in_tail_cap: bool = x > length
		if in_head:
			var q: float = clampf(-x / head_r, 0.0, 1.0)
			if q >= 0.999:
				continue
			a = head_r * sqrt(1.0 - q * q)
			# A head is about as deep as it is wide — the cap is a hemisphere.
			b = a
			s = acos(q) / (PI * 0.5) * float(BodyPlan.HEAD_COLS)
		elif not in_tail_cap:
			var f: float = x / maxf(length, 0.001)
			a = _profile_at(profile, f * clip)
			b = a * depth_ratio
			s = float(BodyPlan.HEAD_COLS) + f * float(BodyPlan.TORSO_COLS)
		else:
			var u: float = clampf((x - length) / tip_r, 0.0, 1.0)
			if u >= 0.999:
				continue
			a = tip_r * sqrt(1.0 - u * u)
			b = a * depth_ratio
			s = float(BodyPlan.HEAD_COLS + BodyPlan.TORSO_COLS) \
				+ asin(u) / (PI * 0.5) * float(BodyPlan.TAIL_COLS)
		if a < CELL * 0.35:
			continue

		var col: int = clampi(int(s), 0, BodyPlan.BODY_COLS - 1)
		var torso: int = col - BodyPlan.HEAD_COLS
		# Which hooped bone, if any, crosses this slice.
		var hoop: int = PART_NONE
		if torso == plan.shoulder_col or torso == plan.pelvis_col:
			hoop = PART_GIRDLE
		elif torso > plan.shoulder_col + 1 and torso < plan.pelvis_col - 1 \
				and torso % 2 == 1:
			hoop = PART_RIB
		var spine_z: float = b * SPINE_RISE
		var reg: int = BodyPlan.HEAD if in_head \
			else (BodyPlan.TAIL if in_tail_cap \
			else plan.region_at(x / maxf(length, 0.001)))
		# Extra reserve swells the outline outward; a lean animal shrinks within
		# its own silhouette. At a reserve of exactly 1.0 the cells fill the
		# silhouette and nothing else.
		var section_r: float = sqrt(maxf(a * b, 0.0001))
		var swell: float = FAT_SHARE * section_r \
			* plan.fat_at(BodyPlan.BODY_KEY, col, 1.0) \
			* (fat_reserve - 1.0) * FAT_SWELL
		var oa: float = maxf(a + swell, a * 0.55)
		var ob: float = maxf(b + swell * depth_ratio, b * 0.55)
		var mean_r: float = sqrt(maxf(oa * ob, 0.0001))
		var skin_t: float = maxf(SKIN_MIN, mean_r * SKIN_SHARE)
		var vert_r: float = maxf(VERT_MIN, b * VERT_SHARE)
		var cord_r: float = maxf(CORD_MIN, b * CORD_SHARE)
		var aorta_r: float = maxf(AORTA_MIN, b * AORTA_SHARE)
		var aorta_z: float = spine_z - vert_r - aorta_r * 0.8
		var hoop_t: float = maxf(GIRDLE_MIN, mean_r * GIRDLE_SHARE) \
			if hoop == PART_GIRDLE else maxf(RIB_MIN, mean_r * RIB_SHARE)
		var heart_rx: float = maxf(HEART_RX_MIN, a * HEART_RX_SHARE)
		# The depth at which a structure is genuinely *inside* the body: deep
		# enough that a whole cell of flesh stands between it and the air. The
		# skeleton, the organs and the conduits all require it — a vertebra the
		# section is too shallow to bury is not laid, because a skeleton is
		# internal or it is not a skeleton. Toward the tail tip this thins the
		# frame out of the lattice along with everything else, exactly as the
		# flesh itself runs out.
		var buried: float = skin_t + CELL * BURY

		var y_span: int = ceili(oa / CELL)
		var z_span: int = ceili(ob / CELL)
		for iy in range(-y_span, y_span):
			var y: float = (float(iy) + 0.5) * CELL
			for iz in range(-z_span, z_span):
				var z: float = (float(iz) + 0.5) * CELL
				var e: float = (y / oa) * (y / oa) + (z / ob) * (z / ob)
				if e > 1.0:
					continue
				var rho: float = sqrt(e)
				var radial: float = sqrt(y * y + z * z)
				var reach: float = radial / maxf(rho, 0.0001) if rho > 0.0001 \
					else minf(oa, ob)
				var depth: float = (1.0 - rho) * reach
				var u_lat: float = clampf(y / oa, -1.0, 1.0)
				var row: int = clampi(int((u_lat + 1.0) * 0.5 * float(BodyPlan.BODY_ROWS)),
					0, BodyPlan.BODY_ROWS - 1)
				var fat_here: float = FAT_SHARE * mean_r \
					* plan.fat_at(BodyPlan.BODY_KEY, col, u_lat) * fat_reserve
				var organ_here: int = plan.organ_at(BodyPlan.BODY_KEY, col, row)
				var off_spine: float = Vector2(y, z - spine_z).length()

				var deep_enough: bool = depth >= buried
				var t: int = MUSCLE
				var pt: int = PART_NONE
				var org: int = BodyPlan.NO_ORGAN
				if in_head and organ_here == BodyPlan.BRAIN and rho < BRAIN_RHO:
					# The braincase cavity: the brain at the back of the skull,
					# inboard of the case that has to be broken to reach it.
					t = ORGAN
					org = BodyPlan.BRAIN
					pt = PART_CEREBRUM if x < -head_r * 0.19 else PART_BRAINSTEM
				elif in_head and x > -head_r * 0.30 and radial <= cord_r \
						and deep_enough:
					# The cord's forward end, rising into the brainstem.
					t = NERVE
					pt = PART_CORD
				elif not in_head and off_spine <= cord_r and deep_enough:
					t = NERVE
					pt = PART_CORD
				elif depth < skin_t:
					t = SKIN
				elif in_head and absf(u_lat) <= BodyPlan.SKULL_SPAN \
						and deep_enough and depth >= skin_t + fat_here \
						and depth < maxf(skin_t + fat_here, buried) \
							+ maxf(SKULL_MIN, head_r * SKULL_SHARE):
					t = BONE
					pt = PART_SKULL
				elif not in_head and off_spine <= vert_r and deep_enough:
					t = BONE
					pt = PART_VERTEBRA
				elif not in_head and not in_tail_cap and deep_enough \
						and Vector2(y, z - aorta_z).length() <= aorta_r:
					t = VESSEL
					pt = PART_AORTA
				elif in_head and x > -head_r * 0.8 and deep_enough \
						and Vector2(y, z + b * 0.25).length() <= aorta_r:
					# The carotid run, forward under the skull toward the jaw.
					t = VESSEL
					pt = PART_ARTERY
				elif organ_here == BodyPlan.HEART and deep_enough \
						and _in_heart(x, y, z, length, heart_rx, a, b):
					t = ORGAN
					org = BodyPlan.HEART
					pt = PART_ATRIUM if z > -b * HEART_DROP else PART_VENTRICLE
				elif hoop != PART_NONE and absf(u_lat) <= (BodyPlan.GIRDLE_SPAN \
						if hoop == PART_GIRDLE else BodyPlan.RIB_SPAN) \
						and deep_enough and depth >= skin_t + fat_here \
						and depth < maxf(skin_t + fat_here, buried) + hoop_t:
					# Hooped bone: a shell under the fat, wrapped around the
					# chest's contents — which is exactly what a ribcage is.
					t = BONE
					pt = hoop
				elif depth < skin_t + fat_here:
					t = FAT

				var out_n := Vector3(0.0, y, z)
				out_n = out_n.normalized() if radial > 0.001 else Vector3(0.0, 0.0, 1.0)
				if in_head and x < -head_r * 0.5:
					out_n = Vector3(x / head_r, y / head_r, z / head_r).normalized()
				elif in_tail_cap:
					out_n = Vector3((x - length) / tip_r, y / tip_r, z / tip_r).normalized()
				_emit(Vector3i(ix, iy, iz), Vector3(x, y, z), t, reg, pt, org,
					0, col * BodyPlan.BODY_ROWS + row, s, y, 0.0, z, rho, out_n)


## Whether a point is inside the heart's ellipsoid. The heart hangs in the chest
## at the plan's own heart column, a little below the section's midline, sized to
## the chest that holds it.
func _in_heart(x: float, y: float, z: float, length: float, rx: float,
		a: float, b: float) -> bool:
	var cx: float = (float(BodyPlan.HEART_COL) + 0.5) / float(BodyPlan.TORSO_COLS) * length
	var dx: float = (x - cx) / maxf(rx, 0.001)
	var dy: float = y / maxf(a * HEART_RY, 0.001)
	var dz: float = (z + b * HEART_DROP) / maxf(b * HEART_RZ, 0.001)
	return dx * dx + dy * dy + dz * dz <= 1.0


## One limb: a column of cells from the socket to the floor, in the same
## canonical frame, with its own internal bone core, the muscle wrapped round
## it, and the neurovascular bundle running beside the bone.
func _carve_limb(plan: BodyPlan, p: CreatureParams, key: String,
		profile: PackedFloat32Array, clip: float, length: float,
		depth_ratio: float, scale: float, fat_reserve: float, load: Vector2) -> void:
	var front: bool = key.begins_with("F")
	var bone_len: float = (p.arm_length if front else p.leg_length) * scale
	var girth: float = Limb.girth_of(bone_len, scale, load.x if front else load.y)
	var half: float = girth * 0.5
	# The same taper the ledger poses its stations with, so the cells fill exactly
	# the leg that is drawn — see Limb.shape_at. This is what gives a limb an
	# inside: the belly at the girdle is several cells across, so there is room to
	# lay muscle around a bone under a skin that is genuinely on the outside of
	# both, where a uniform shaft of two cells could only ever be all surface.
	var belly: float = Limb.belly_of(
		deg_to_rad(p.fore_swing_deg if front else p.hind_swing_deg),
		p.fore_fold_range if front else p.hind_fold_range)
	var foot_r: float = Limb.foot_of(bone_len, scale)
	var side: float = BodyPlan.limb_side(key)
	var patch_i: int = PATCH_KEYS.find(key)
	var reg: int = int(plan.limb_region[key])
	var upper_share: float = p.fore_upper_share if front else p.hind_upper_share

	var socket_col: int = int(plan.limb_socket_col[key])
	var f_s: float = (float(socket_col - BodyPlan.HEAD_COLS) + 0.5) \
		/ float(BodyPlan.TORSO_COLS)
	var a_s: float = _profile_at(profile, f_s * clip)
	var sx: float = f_s * length
	var sy: float = side * a_s * 0.72
	var sz: float = -a_s * depth_ratio * 0.15
	var upper_len: float = bone_len * upper_share
	var lower_len: float = bone_len - upper_len
	var toe_z: float = sz - bone_len
	var span: float = float(BodyPlan.LIMB_BONE_COLS / 2)
	# The bone core is sized off the *slender* end of the limb rather than the
	# belly: a femur does not thicken because the thigh around it did. Which is
	# what leaves the belly's extra cells to muscle, where they belong.
	var bone_r: float = maxf(LIMB_BONE_MIN,
		half * Limb.shape_at(upper_share, belly, upper_share) * LIMB_BONE_SHARE)

	# The shaft, sliced along its own length.
	for iz in range(ceili((toe_z - CELL) / CELL), floori(sz / CELL) + 1):
		var z: float = (float(iz) + 0.5) * CELL
		var down: float = sz - z
		if down < 0.0 or down > bone_len:
			continue
		var u: float = down / maxf(bone_len, 0.001)
		var r: float = half * Limb.shape_at(u, belly, upper_share)
		var s: float = 0.0
		if down <= upper_len:
			s = (down / maxf(upper_len, 0.001)) * span
		else:
			var tl: float = (down - upper_len) / maxf(lower_len, 0.001)
			# The lower bone flares out into the foot, exactly as the ledger's
			# own stations do.
			r = lerpf(r, foot_r, tl * tl)
			s = span + tl * span
		if r < CELL * 0.35:
			continue
		_carve_limb_slice(patch_i, reg, sx, sy, z, r, s, bone_r,
			FAT_SHARE * r * BodyPlan.FAT_LIMB * fat_reserve, down < bone_len * 0.92)

	# The foot: a pad of cells around the toe, no bone — the plan gives feet
	# none — mapped onto the ledger's foot cap columns.
	var pad: float = foot_r
	var fcx: float = sx + foot_r * 0.30
	for ixf in range(floori((fcx - pad) / CELL), ceili((fcx + pad) / CELL) + 1):
		var x: float = (float(ixf) + 0.5) * CELL
		for iyf in range(floori((sy - pad) / CELL), ceili((sy + pad) / CELL) + 1):
			var y: float = (float(iyf) + 0.5) * CELL
			for izf in range(floori((toe_z - pad * 0.6) / CELL),
					ceili((toe_z + pad * 0.6) / CELL) + 1):
				var z: float = (float(izf) + 0.5) * CELL
				var dx: float = x - fcx
				var dy: float = y - sy
				var dzf: float = (z - toe_z) / 0.6
				var d: float = sqrt(dx * dx + dy * dy + dzf * dzf)
				if d > foot_r:
					continue
				var rho: float = d / maxf(foot_r, 0.001)
				var forward: float = clampf(dx / foot_r, -1.0, 1.0)
				var s_f: float = float(BodyPlan.LIMB_BONE_COLS) \
					+ asin(maxf(forward, 0.0)) / (PI * 0.5) * float(BodyPlan.LIMB_FOOT_COLS)
				var u_row: float = clampf(dy / foot_r, -1.0, 1.0)
				var row_f: int = clampi(int((u_row + 1.0) * 0.5 * float(BodyPlan.LIMB_ROWS)),
					0, BodyPlan.LIMB_ROWS - 1)
				var col_f: int = clampi(int(s_f), BodyPlan.LIMB_BONE_COLS,
					BodyPlan.LIMB_COLS - 1)
				var foot_skin: float = maxf(SKIN_MIN * 0.8, foot_r * SKIN_SHARE)
				var t: int = MUSCLE
				if (1.0 - rho) * foot_r < foot_skin:
					t = SKIN
				elif (1.0 - rho) * foot_r < foot_skin \
						+ FAT_SHARE * foot_r * BodyPlan.FAT_FOOT * fat_reserve:
					t = FAT
				_emit(Vector3i(ixf, iyf, izf), Vector3(x, y, z), t, reg, PART_NONE,
					BodyPlan.NO_ORGAN, patch_i, col_f * BodyPlan.LIMB_ROWS + row_f,
					s_f, dy, dx, z - toe_z, rho,
					Vector3(dx, dy, dzf).normalized() if d > 0.001 else Vector3(0, 0, -1))


func _carve_limb_slice(patch_i: int, reg: int, sx: float, sy: float, z: float,
		r: float, s: float, bone_r: float, fat_t: float, boned: bool) -> void:
	var reach: int = ceili(r / CELL)
	var col: int = clampi(int(s), 0, BodyPlan.LIMB_BONE_COLS - 1)
	var iz: int = floori(z / CELL)
	var skin_t: float = maxf(SKIN_MIN * 0.8, r * SKIN_SHARE)
	# The bone core is laid only where the limb is thick enough to bury it — a
	# leg two cells across is skin and muscle with its bone carried by the
	# ledger alone, because a skeleton that shows on the surface is not inside
	# the animal. A full cell of flesh over the core is what guarantees the
	# covering cell actually exists on the grid.
	var deep_bone: bool = boned and r - bone_r >= CELL
	# Whether there is room for the neurovascular bundle to be cells of its own;
	# on a thin limb the conduits run inside the muscle it does have.
	var roomy: bool = r >= bone_r + BUNDLE_R * 2.0 + skin_t
	for ix in range(floori(sx / CELL) - reach, floori(sx / CELL) + reach + 1):
		var x: float = (float(ix) + 0.5) * CELL
		for iy in range(floori(sy / CELL) - reach, floori(sy / CELL) + reach + 1):
			var y: float = (float(iy) + 0.5) * CELL
			var dx: float = x - sx
			var dy: float = y - sy
			var radial: float = sqrt(dx * dx + dy * dy)
			if radial > r:
				continue
			var depth: float = r - radial
			var u_row: float = clampf(dy / r, -1.0, 1.0)
			var row: int = clampi(int((u_row + 1.0) * 0.5 * float(BodyPlan.LIMB_ROWS)),
				0, BodyPlan.LIMB_ROWS - 1)
			var t: int = MUSCLE
			var pt: int = PART_NONE
			if deep_bone and radial <= bone_r:
				t = BONE
				pt = PART_LIMB_BONE
			elif roomy and boned \
					and Vector2(dx - (bone_r + BUNDLE_R), dy).length() <= BUNDLE_R * 0.75:
				# The neurovascular bundle runs down the limb beside the bone —
				# nerve forward of the vessel, both stopping at the ankle
				# exactly as the plan's conduits do.
				t = NERVE
				pt = PART_NERVE_BRANCH
			elif roomy and boned \
					and Vector2(dx + (bone_r + BUNDLE_R), dy).length() <= BUNDLE_R * 0.75:
				t = VESSEL
				pt = PART_ARTERY
			elif depth < skin_t:
				t = SKIN
			elif depth < skin_t + fat_t:
				t = FAT
			_emit(Vector3i(ix, iy, iz), Vector3(x, y, z), t, reg, pt,
				BodyPlan.NO_ORGAN, patch_i, col * BodyPlan.LIMB_ROWS + row,
				s, dy, dx, 0.0, radial / maxf(r, 0.001),
				Vector3(dx, dy, 0.0).normalized() if radial > 0.001 else Vector3(0, 1, 0))


func _emit(at: Vector3i, p: Vector3, t: int, reg: int, pt: int, org: int,
		patch_i: int, ledger_cell: int, s: float, p_lat: float, p_fore: float,
		p_lift: float, rho: float, out_n: Vector3) -> void:
	# One cell per grid site: where structures meet — a limb root inside the
	# body's flank — the first carve wins and the lattice stays a solid.
	if _grid.has(at):
		return
	_grid[at] = count
	pos.append(p)
	kind.append(t)
	region.append(reg)
	part.append(pt)
	organ_of.append(org)
	patch_of.append(patch_i)
	cell_of.append(ledger_cell)
	station.append(s)
	lat.append(p_lat)
	fore.append(p_fore)
	lift.append(p_lift)
	normal.append(out_n)
	# `rank` is finalised in `_finish`; park the raw outside-in measure here.
	rank.append(rho)
	count += 1


## Neighbourhood, hull skin, outside-in ranks and the census — everything that
## needs the whole solid to exist before it can be said.
func _finish(plan: BodyPlan) -> void:
	neighbor = PackedInt32Array()
	neighbor.resize(count * 6)
	gone = PackedByteArray()
	gone.resize(count)
	bitten = PackedByteArray()
	bitten.resize(count)

	# Six neighbours per cell, through the shared grid — patch seams included,
	# which is what keeps a limb continuous with the flank it hangs from.
	var offsets: Array[Vector3i] = [
		Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0),
		Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1),
	]
	for at in _grid:
		var i: int = _grid[at]
		for k in 6:
			var other = _grid.get(at + offsets[k])
			neighbor[i * 6 + k] = other if other != null else -1

	# The hull is skin: skin is the outer boundary of the animal, and no cell of
	# any other tissue may face open air. That is what makes the skin a genuine
	# closed wrap — every exposed face on the whole solid belongs to a skin cell,
	# so there is no seam anywhere for the fat and muscle under it to show
	# through, at any filter and from any angle.
	var carved: PackedByteArray = kind.duplicate()
	for i in count:
		if kind[i] == SKIN:
			continue
		for k in 6:
			if neighbor[i * 6 + k] < 0:
				kind[i] = SKIN
				part[i] = PART_NONE
				organ_of[i] = BodyPlan.NO_ORGAN
				break
	_keep_a_core(carved)

	# What each cell touches, now that every cell knows what it is. Written once
	# and read by everything that has to decide what is on the surface of a
	# partly-peeled body — see `around`.
	around = PackedByteArray()
	around.resize(count)
	parity = PackedByteArray()
	parity.resize(count)
	for i in count:
		var mask: int = 0
		var base: int = i * 6
		for k in 6:
			var n: int = neighbor[base + k]
			mask |= OPEN_BIT if n < 0 else (1 << int(kind[n]))
		around[i] = mask
		var p: Vector3 = pos[i]
		parity[i] = (floori(p.x / CELL) + floori(p.y / CELL) + floori(p.z / CELL)) & 1

	# Outside-in ranks, per (patch, ledger cell, tissue) group: the ledger says
	# how much of a column's layer is left, and the rank decides *which* of the
	# lattice cells that maps to — always the outermost first, because that is
	# the way a bite eats.
	var groups: Dictionary = {}
	for i in count:
		var g: int = (int(patch_of[i]) << 28) | (cell_of[i] << 3) | int(kind[i])
		var members = groups.get(g)
		if members == null:
			members = []
			groups[g] = members
		members.append(Vector2(rank[i], float(i)))
	for g in groups:
		var members: Array = groups[g]
		members.sort()
		var m: int = members.size()
		for j in m:
			# Ascending by the outside-in measure: the deepest cell of the group
			# ranks toward 1.0, the outermost toward 0.0 — first taken.
			rank[int(members[j].y)] = 1.0 - (float(j) + 0.5) / float(m)

	# The ledger index, for the damage mirror to walk wounded columns only.
	_cell_index = []
	for pk in PATCH_KEYS.size():
		var cells_here: int = BodyPlan.BODY_COLS * BodyPlan.BODY_ROWS if pk == 0 \
			else BodyPlan.LIMB_COLS * BodyPlan.LIMB_ROWS
		var index: Array = []
		index.resize(cells_here)
		_cell_index.append(index)
	_organ_cells = []
	for _o in BodyPlan.ORGAN_NAMES.size():
		_organ_cells.append(PackedInt32Array())
	for i in count:
		var index: Array = _cell_index[int(patch_of[i])]
		var members = index[cell_of[i]]
		if members == null:
			members = []
			index[cell_of[i]] = members
		members.append(i)
		var org: int = int(organ_of[i])
		if org != BodyPlan.NO_ORGAN and org < _organ_cells.size():
			(_organ_cells[org] as PackedInt32Array).append(i)

	# The census: what the animal is built out of, region by region, tissue by
	# tissue — the numbers everything else reads.
	built = PackedInt32Array()
	built.resize(BodyPlan.REGIONS * TISSUES)
	built_units = 0.0
	axial_units = 0.0
	for i in count:
		built[int(region[i]) * TISSUES + int(kind[i])] += 1
		var unit: float = DENSITY[kind[i]]
		built_units += unit
		if not plan.is_limb_region(int(region[i])):
			axial_units += unit
	built_total = count
	standing = built.duplicate()
	standing_total = built_total
	standing_units = built_units
	_synced = -2


## Nothing on an animal is made of skin all the way through.
##
## The hull rule above is right about every structure thick enough to have an
## inside, and wrong about the ones that are not: a vestigial forelimb three
## pixels across is every one of it its own boundary, so the rule takes the last
## of its bone and leaves a stick of integument. This puts the core back — the
## cells nearest the structure's own axis keep the tissue the carve gave them —
## for any part the conversion emptied outright.
##
## It runs per patch rather than per column because a limb is the thing that is
## too thin, and a limb is a patch. On everything thick enough to be hollow it
## does nothing at all, which is every animal in the file above the smallest
## arms.
func _keep_a_core(carved: PackedByteArray) -> void:
	for pk in PATCH_KEYS.size():
		var mine: Array[int] = []
		var solid: bool = false
		for i in count:
			if int(patch_of[i]) != pk:
				continue
			if kind[i] != SKIN:
				solid = true
				break
			mine.append(i)
		if solid or mine.size() < CORE_MIN:
			continue
		# Deepest first — `rank` still holds the raw outside-in measure here, which
		# is 0 on the axis and 1 at the surface.
		var order: Array[Vector2] = []
		for i in mine:
			order.append(Vector2(rank[i], float(i)))
		order.sort()
		for j in maxi(int(float(mine.size()) * CORE_SHARE), 1):
			var i: int = int(order[j].y)
			kind[i] = carved[i]


static func _profile_at(profile: PackedFloat32Array, t: float) -> float:
	var n: int = profile.size()
	if n == 0:
		return 0.0
	var s: float = clampf(t, 0.0, 1.0) * float(n - 1)
	var i: int = clampi(int(s), 0, n - 2)
	return lerpf(profile[i], profile[i + 1], s - float(i))


# ------------------------------------------------------------------ damage ----

## Takes the cells one closing of the jaws actually got to, out of one column.
##
## `share` is the fraction of that column's layer the bite is asking for and
## `reach` the height band the jaws could bring to bear. The teeth can only
## destroy flesh they can reach, so what comes back is the share they were
## actually able to take — never more than the reachable cells of that tissue
## still standing there — and the caller refunds the difference to the ledger.
## That is what makes a bite along the top of a back a wound along the top of a
## back rather than a hole through the whole animal.
##
## The cells go outside-in among the reachable ones, because that is the order a
## bite eats in. Only ever called for a column a strike has just covered, so it
## walks a handful of cells on the rare tick a bite lands and nothing otherwise.
func take(patch_index: int, ledger_cell: int, layer: int, lost: float,
		reach: Vector2, p: TissueGrid.Patch) -> float:
	if count == 0 or lost <= 0.0 or patch_index >= _cell_index.size():
		return lost
	var index: Array = _cell_index[patch_index]
	if ledger_cell >= index.size():
		return lost
	var members = index[ledger_cell]
	if members == null:
		return lost
	# `rank` is 1.0 at the axis and 0.0 at the surface, so ascending is outside-in.
	var here: int = 0
	var pick: Array[Vector2] = []
	for i in members:
		if int(kind[i]) != layer:
			continue
		here += 1
		if Stature.overlaps(reach, cell_band(p, i)):
			pick.append(Vector2(rank[i], float(i)))
	if here == 0:
		# The ledger carries a layer the carve laid no cells of — a bone too slim
		# to bury, out at a tail tip. Nothing here can say anything about it, so
		# it answers for itself exactly as it did before there was a lattice.
		return lost
	# A column can lose the flesh the jaws can reach and no more, however many
	# times they close on it. Quoted against the running total rather than
	# against this one bite, so a mouth that covers the whole column is capped at
	# everything — which is to say, not capped at all, and every bite that was
	# ever going to eat clean through one still does.
	var allowed: float = minf(lost, float(pick.size()) / float(here))
	var wanted: int = clampi(int(round(allowed * float(here))), 0, pick.size())
	if wanted > 0:
		pick.sort()
		for j in wanted:
			bitten[int(pick[j].y)] = 1
	return allowed


## The slice of height one cell stands in, in the world the patch is posed in —
## the column's own mid at this cell's station, plus however far up the cell sits
## in it, and a cell's thickness either side.
func cell_band(p: TissueGrid.Patch, i: int) -> Vector2:
	var mids: PackedFloat32Array = p.mids
	var s: float = clampf(station[i], 0.0, float(mids.size() - 1))
	var c: int = mini(int(s), mids.size() - 2)
	var here: float = lerpf(mids[c], mids[c + 1], s - float(c)) + lift[i]
	return Vector2(here - CELL * 0.5, here + CELL * 0.5)


## Mirrors the damage ledger onto the lattice: for every wounded ledger column,
## the surviving fraction of each layer decides how many of the mapped cells
## still stand — the ones a bite actually closed on first, and the outermost of
## the rest after them. Costs nothing on an unwounded animal and nothing at all
## when the ledger has not changed since the last ask.
##
## The ledger is still the only thing that says how much is missing. All the
## lattice adds is which cells that is, and `bitten` is what makes the answer the
## place the teeth were rather than a ring worked out from a column total.
func refresh_damage(grid: TissueGrid) -> void:
	if grid == null or grid.revision == _synced or count == 0:
		return
	_synced = grid.revision
	gone.fill(0)
	standing = built.duplicate()
	standing_total = built_total
	standing_units = built_units
	for pk in PATCH_KEYS.size():
		var p: TissueGrid.Patch = grid.patch(PATCH_KEYS[pk])
		if p == null or p.damaged.is_empty():
			continue
		var index: Array = _cell_index[pk]
		for ledger_cell in p.damaged:
			var members = index[ledger_cell]
			if members == null:
				continue
			if p.gone[ledger_cell] != 0:
				for i in members:
					_retire(i)
				continue
			_reconcile(grid, p, ledger_cell, members)


## Which of one column's cells are standing, given what the ledger says is left
## of each of its layers and which of them the teeth took.
##
## The count comes from the ledger and the choice comes from the bite: the cells
## a strike actually closed on are gone, and if the ledger says more than that is
## missing the rest comes off outside-in, which is the only sensible thing to say
## about tissue nobody watched being removed.
func _reconcile(grid: TissueGrid, p: TissueGrid.Patch, ledger_cell: int,
		members: Array) -> void:
	var base: int = ledger_cell * TissueGrid.LAYERS
	var order: Array[Vector2] = []
	for t in TISSUES:
		order.clear()
		var here: int = 0
		for i in members:
			if int(kind[i]) != t:
				continue
			here += 1
			# Bitten cells sort ahead of everything, then outside-in.
			order.append(Vector2(rank[i] - (2.0 if bitten[i] != 0 else 0.0), float(i)))
		if here == 0:
			continue
		if t == NERVE or t == VESSEL:
			# A conduit is cut or it is not; there is no fraction of a thread.
			for entry in order:
				if not _conducts(p, base, int(entry.y)):
					_retire(int(entry.y))
			continue
		var full: float = _layer_built(grid, p, ledger_cell, t)
		var alive: float = 1.0 if full <= 0.0 \
			else clampf(p.hp[base + t] / full, 0.0, 1.0)
		var doomed: int = here - int(round(alive * float(here)))
		if doomed <= 0:
			continue
		order.sort()
		for j in doomed:
			_retire(int(order[j].y))


func _retire(i: int) -> void:
	if gone[i] != 0:
		return
	gone[i] = 1
	standing[int(region[i]) * TISSUES + int(kind[i])] -= 1
	standing_total -= 1
	standing_units -= DENSITY[kind[i]]


## Whether a conduit cell still carries. A conduit is a thread through the tissue
## enclosing it: shielded where it runs inside bone, cut when its enclosure is
## mostly gone — the same floor the functional layer reads its conduits with.
func _conducts(p: TissueGrid.Patch, base: int, i: int) -> bool:
	var cell: int = base / TissueGrid.LAYERS
	var around: float
	if p.bone[cell] != 0 and part[i] == PART_CORD:
		around = p.hp[base + TissueGrid.BONE] / TissueGrid.BONE_HP
	else:
		around = p.hp[base + TissueGrid.MUSCLE] / TissueGrid.MUSCLE_HP
	return around >= CONDUIT_CUT


func _layer_built(grid: TissueGrid, p: TissueGrid.Patch, cell: int, layer: int) -> float:
	match layer:
		SKIN:
			return TissueGrid.SKIN_HP
		FAT:
			return grid.fat_capacity(p, cell)
		MUSCLE:
			return TissueGrid.MUSCLE_HP
		BONE:
			return TissueGrid.BONE_HP if p.bone[cell] != 0 else 0.0
		_:
			return TissueGrid.ORGAN_HP if int(p.organ[cell]) != BodyPlan.NO_ORGAN else 0.0


# ------------------------------------------------------------------ census ----

## Cells standing in one region, all tissues.
func region_cells(reg: int) -> int:
	var total: int = 0
	var base: int = reg * TISSUES
	for t in TISSUES:
		total += standing[base + t]
	return total


## Cells of one tissue still standing across the whole animal.
func tissue_cells(t: int) -> int:
	var total: int = 0
	for reg in BodyPlan.REGIONS:
		total += standing[reg * TISSUES + t]
	return total


func tissue_built(t: int) -> int:
	var total: int = 0
	for reg in BodyPlan.REGIONS:
		total += built[reg * TISSUES + t]
	return total


## Share of the standing body's mass that is one tissue — what the composition
## bar stripes, quoted off the same cells the scales weigh.
func mass_share(t: int) -> float:
	if standing_units <= 0.0:
		return 0.0
	return float(tissue_cells(t)) * DENSITY[t] / standing_units


## Cells of one tissue standing in one region — "how much muscle is on the hind
## leg" is this, asked with (RL, MUSCLE).
func region_tissue(reg: int, t: int) -> int:
	return standing[reg * TISSUES + t]


func region_tissue_built(reg: int, t: int) -> int:
	return built[reg * TISSUES + t]


## Physical volume of the standing animal, px³ — the cells times the one cell
## size, which is the whole point of counting in constant cells.
func volume() -> float:
	return float(standing_total) * CELL_VOLUME


## The cells one named organ occupies, gathered at build. Empty for an organ this
## body's plan does not place.
func organ_cells(which: int) -> PackedInt32Array:
	if which < 0 or which >= _organ_cells.size():
		return PackedInt32Array()
	return _organ_cells[which]


## The lattice cell nearest a canonical-frame point, or -1. Test scaffolding
## mostly; the HUD picks against the posed cells instead.
func cell_at(p: Vector3) -> int:
	var key := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
	var found = _grid.get(key)
	return found if found != null else -1
