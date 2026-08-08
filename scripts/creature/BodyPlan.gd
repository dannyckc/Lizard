## What kind of animal this is: where its structures sit in the lattice, what
## regions they group into, and how its nerves and vessels are plumbed.
##
## Every other file in the anatomy stack is a *mechanism* — erosion, connectivity,
## functional consequence, animation — and none of them names a body part. This
## is the only place that does. A creature with six legs, wings or no tail is a
## different plan and nothing else: the lattice still erodes the same way, the
## networks still flood the same way, and the gait still reads the same functional
## numbers off whatever regions the plan happens to declare.
##
## It owns the lattice's dimensions for the same reason. Grid layout, skeleton
## layout, fat distribution and organ sites are one description of one animal, and
## splitting them across two files is how they drift apart — a rib moved without
## the heart under it moving with it. TissueGrid aliases the dimensions it needs so
## the storage code reads naturally, but the numbers live here.
##
## Deliberately free of any tissue knowledge: it answers in *profiles* — is there
## bone here, how thick is the fat here, which organ is here — and TissueGrid
## decides what those cost in hit points. That is what lets a plan be authored
## without knowing how hard anything is to bite through.
class_name BodyPlan
extends RefCounted

# --- body patch layout ------------------------------------------------------
const BODY_KEY: String = "body"
## Cap columns tessellating the round snout, and the same for the tail tip.
## Their outer corners land exactly on the circle the cap would be drawn as.
const HEAD_COLS: int = 8
const TORSO_COLS: int = 20
const TAIL_COLS: int = 4
const BODY_COLS: int = HEAD_COLS + TORSO_COLS + TAIL_COLS
## Odd, so one row straddles the spine and can carry the vertebral column — and
## so the spinal cord inside it has a single unambiguous row to run down.
const BODY_ROWS: int = 7
## The row the vertebrae, and therefore the cord, occupy.
const SPINE_ROW: int = BODY_ROWS / 2

# --- limb patch layout ------------------------------------------------------
const LIMB_BONE_COLS: int = 6
const LIMB_FOOT_COLS: int = 4
const LIMB_COLS: int = LIMB_BONE_COLS + LIMB_FOOT_COLS
const LIMB_ROWS: int = 3
## The row the limb's bone core, and the neurovascular bundle beside it, run down.
const LIMB_CORE_ROW: int = LIMB_ROWS / 2
const LIMB_KEYS: Array[String] = ["FL", "FR", "RL", "RR"]

# --- skeleton layout --------------------------------------------------------
# A skull filling the head cap but not the cheeks; a vertebral column one cell
# wide running the whole length; a full-width girdle under each pair of limb
# sockets; ribs on alternating columns between them; a core down each limb. The
# sparseness is load-bearing — see the README — and so is the connectivity: a
# flood fill from the snout has to reach every bone cell.
const SKULL_SPAN: float = 0.72
const RIB_SPAN: float = 0.78
const GIRDLE_SPAN: float = 0.95
## Torso columns carrying the pectoral and pelvic girdles. TORSO_COLS spans the
## whole clipped spine, so a column index reads directly as a fraction of body
## length, and these mirror the *default* front_limb_t / rear_limb_t rather than
## tracking them live — the layout has to name the same cells after the tuning
## panel has restructured the spine underneath it.
const SHOULDER_COL: int = 3
const PELVIS_COL: int = 9

# --- regions ----------------------------------------------------------------
# The unit everything downstream is quoted in. A region is a piece of the animal
# that can lose function as a piece: it has muscle, it is on the end of a nerve
# and a vessel, and — for the limbs — it drives a joint the animator solves.
const HEAD: int = 0
const THORAX: int = 1
const LUMBAR: int = 2
const PELVIS: int = 3
const TAIL: int = 4
const FL: int = 5
const FR: int = 6
const RL: int = 7
const RR: int = 8
const REGIONS: int = 9

const REGION_NAMES: Array[String] = [
	"head", "thorax", "lumbar", "pelvis", "tail", "FL", "FR", "RL", "RR",
]
const AXIAL_REGIONS: Array[int] = [HEAD, THORAX, LUMBAR, PELVIS, TAIL]
const LIMB_REGIONS: Array[int] = [FL, FR, RL, RR]

## Torso column each axial region starts at, in torso-local columns. The head cap
## and the tail cap are handled either side of these.
const THORAX_COL: int = 0
const LUMBAR_COL: int = 7
const LOIN_COL: int = 12

# --- organs -----------------------------------------------------------------
const NO_ORGAN: int = 0
const BRAIN: int = 1
const HEART: int = 2
const ORGAN_NAMES: Array[String] = ["", "brain", "heart"]

## The braincase: the back of the skull cap, inboard of the cheeks. It is placed
## squarely inside bone rather than merely near it, because the whole claim being
## made is that the skull has to be broken through first — and the depth stack is
## what enforces that, so a brain cell with no bone over it is a brain lying in
## the open however central it looks.
const BRAIN_FROM_COL: int = 6
const BRAIN_TO_COL: int = HEAD_COLS
const BRAIN_FROM_ROW: int = 2
const BRAIN_TO_ROW: int = 5

## The heart, in the chest. Its column is a *rib* column, for exactly the reason
## above: the ribcage is what stands between a bite and it.
const HEART_COL: int = 5
const HEART_FROM_ROW: int = 2
const HEART_TO_ROW: int = 5

# --- fat --------------------------------------------------------------------
# Fat is a reserve laid over the trunk and thinning toward the extremities, which
# is where a body carries it and also what gives the silhouette its weight. Two
# profiles multiplied: along the body, and across it.
const FAT_ALONG: Array[float] = [0.30, 0.75, 1.0, 0.85, 0.25]
## How much of the flank's fat the midline carries. Fat sits over the flanks, not
## over the spine, so this is well under one.
const FAT_MIDLINE: float = 0.55
## Limbs and feet carry little — a leg is bone, muscle and skin.
const FAT_LIMB: float = 0.28
const FAT_FOOT: float = 0.12

# --- muscle groups ----------------------------------------------------------
## Which joint a muscle group acts across. Limb groups are actuators on the two
## IK joints; axial groups are the tone that holds a spine joint up.
const JOINT_AXIAL: int = 0
const JOINT_ROOT: int = 1
const JOINT_MID: int = 2


## One nerve or vessel run, and the cells it passes through.
##
## The node *is* a region — there is no separate graph vocabulary — so the tree
## below is one parent index per region and nothing else. Its integrity is read
## off the lattice rather than stored, which is what makes a severed nerve a
## consequence of the flesh that is missing rather than an injury flag somebody
## remembered to set.
class Conduit extends RefCounted:
	var region: int = 0
	## Region this one hangs off, or -1 at the root organ.
	var parent: int = -1
	## True where the run is inside bone — the spinal cord in its vertebrae. A
	## shielded conduit is read off the bone that encloses it, so it survives until
	## the bone itself is broken; an unshielded one is read off the muscle it lies
	## in and is cut when that flesh is taken.
	var shielded: bool = false
	var patch_key: String = BODY_KEY
	var cells: PackedInt32Array = PackedInt32Array()


## A block of muscle acting across a joint. Force is its surviving fibre times
## what the nerve delivers to it times what the blood does — see BodyState.
class MuscleGroup extends RefCounted:
	var key: String = ""
	var region: int = 0
	var joint: int = JOINT_AXIAL
	var patch_key: String = BODY_KEY
	var from_col: int = 0
	var to_col: int = 0


## Region each cell belongs to, per patch key.
var cell_region: Dictionary = {}
## Region index -> Conduit, one entry per region, for each network.
var nerves: Array[Conduit] = []
var vessels: Array[Conduit] = []
var muscles: Array[MuscleGroup] = []
## Where each network is fed from.
var nerve_root: int = HEAD
var vessel_root: int = THORAX
## Limb key -> its region, and the body column of the girdle it is slung from.
var limb_region: Dictionary = {}
var limb_socket_col: Dictionary = {}


func _init() -> void:
	_build_regions()
	_build_networks()
	_build_muscles()
	for key in LIMB_KEYS:
		limb_region[key] = _limb_region_of(key)
		limb_socket_col[key] = HEAD_COLS + (SHOULDER_COL if key.begins_with("F") else PELVIS_COL)


# ------------------------------------------------------------------ layout ----

## Whether the skeleton runs under a body cell. `v` is the row's lateral centre,
## -1 on one flank to +1 on the other.
func body_has_bone(col: int, v: float) -> bool:
	var lateral: float = absf(v)
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
	# reaches the muscle the ribs do not cover. A rib is never laid against a
	# girdle — two adjacent crossbars are one wide bar with no gap left to bite.
	return torso > SHOULDER_COL + 1 and torso < PELVIS_COL - 1 \
		and torso % 2 == 1 and lateral <= RIB_SPAN


## Limbs are a bone core running their whole length, with flesh either side.
func limb_has_bone(_col: int, v: float) -> bool:
	return absf(v) <= 1.0 / float(LIMB_ROWS)


func has_bone(patch_key: String, col: int, v: float) -> bool:
	return body_has_bone(col, v) if patch_key == BODY_KEY else limb_has_bone(col, v)


## How much fat a cell carries, as a multiple of the species' reserve. Zero to
## about one; TissueGrid decides what that costs to bite through.
func fat_at(patch_key: String, col: int, v: float) -> float:
	if patch_key != BODY_KEY:
		return FAT_FOOT if col >= LIMB_BONE_COLS else FAT_LIMB
	var across: float = lerpf(FAT_MIDLINE, 1.0, absf(v))
	return _fat_along(col) * across


## The trunk profile, sampled by region so it moves with the plan rather than
## having to be re-tuned against raw column indices.
func _fat_along(col: int) -> float:
	var region: int = _axial_region_of_column(col)
	if region == TAIL:
		# The tail tapers to nothing, so its fat has to taper with it or the tip
		# comes out better padded than the hips.
		var torso: int = col - HEAD_COLS
		var t: float = clampf(float(torso - LOIN_COL) / float(maxi(
			TORSO_COLS + TAIL_COLS - LOIN_COL, 1)), 0.0, 1.0)
		return lerpf(FAT_ALONG[PELVIS], FAT_ALONG[TAIL], t)
	return FAT_ALONG[region]


## Which organ, if any, occupies a body cell.
func organ_at(patch_key: String, col: int, row: int) -> int:
	if patch_key != BODY_KEY:
		return NO_ORGAN
	if col >= BRAIN_FROM_COL and col < BRAIN_TO_COL \
			and row >= BRAIN_FROM_ROW and row < BRAIN_TO_ROW:
		return BRAIN
	if col == HEAD_COLS + HEART_COL \
			and row >= HEART_FROM_ROW and row < HEART_TO_ROW:
		return HEART
	return NO_ORGAN


# ----------------------------------------------------------------- regions ----

func _build_regions() -> void:
	var body := PackedByteArray()
	body.resize(BODY_COLS * BODY_ROWS)
	for col in BODY_COLS:
		var region: int = _axial_region_of_column(col)
		for row in BODY_ROWS:
			body[col * BODY_ROWS + row] = region
	cell_region[BODY_KEY] = body

	for key in LIMB_KEYS:
		var limb := PackedByteArray()
		limb.resize(LIMB_COLS * LIMB_ROWS)
		limb.fill(_limb_region_of(key))
		cell_region[key] = limb


func _axial_region_of_column(col: int) -> int:
	if col < HEAD_COLS:
		return HEAD
	var torso: int = col - HEAD_COLS
	if torso < LUMBAR_COL:
		return THORAX
	if torso < PELVIS_COL:
		return LUMBAR
	if torso < LOIN_COL:
		return PELVIS
	return TAIL


func _limb_region_of(key: String) -> int:
	match key:
		"FL": return FL
		"FR": return FR
		"RL": return RL
		_: return RR


## Body column a fraction along the *clipped* spine falls in — the bridge between
## the animation rig's coordinates and the lattice's.
func torso_column(t: float) -> int:
	return HEAD_COLS + clampi(int(t * float(TORSO_COLS)), 0, TORSO_COLS - 1)


## The region a fraction along the clipped spine falls in.
func region_at(t: float) -> int:
	return _axial_region_of_column(torso_column(t))


# ---------------------------------------------------------------- networks ----

## Brain -> central nerves -> region nerves -> muscles, and heart -> major
## vessels -> regions -> tissues.
##
## One topology, two roots, and that difference is the whole of why the two
## networks fail differently. The cord runs forward to the brain, so a neck taken
## out silences the entire body while its heart goes on beating; the great vessels
## run out of the chest, so a chest taken out starves the entire body while its
## brain goes on issuing orders nothing can hear.
func _build_networks() -> void:
	# Parent chain shared by both: the trunk runs head-thorax-lumbar-pelvis-tail,
	# the forelimbs hang off the thorax and the hindlimbs off the pelvis.
	var parents: Array[int] = []
	parents.resize(REGIONS)
	parents[HEAD] = THORAX
	parents[THORAX] = HEAD
	parents[LUMBAR] = THORAX
	parents[PELVIS] = LUMBAR
	parents[TAIL] = PELVIS
	parents[FL] = THORAX
	parents[FR] = THORAX
	parents[RL] = PELVIS
	parents[RR] = PELVIS

	nerves = _build_network(parents, nerve_root, true)
	vessels = _build_network(parents, vessel_root, false)


## `axial_shielded` is the one structural difference between the two runs: the
## cord lies inside the vertebrae and the aorta lies against them.
func _build_network(parents: Array[int], root: int, axial_shielded: bool) -> Array[Conduit]:
	var out: Array[Conduit] = []
	out.resize(REGIONS)
	for region in REGIONS:
		var conduit := Conduit.new()
		conduit.region = region
		conduit.parent = -1 if region == root else parents[region]
		if region in LIMB_REGIONS:
			conduit.patch_key = REGION_NAMES[region]
			conduit.shielded = false
			conduit.cells = _limb_conduit_cells()
		else:
			conduit.patch_key = BODY_KEY
			conduit.shielded = axial_shielded
			conduit.cells = _axial_conduit_cells(region)
		out[region] = conduit
	return out


## The cord/aorta run through one axial region: the vertebral row across every
## column that region owns.
func _axial_conduit_cells(region: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for col in BODY_COLS:
		if _axial_region_of_column(col) == region:
			cells.append(col * BODY_ROWS + SPINE_ROW)
	return cells


## The neurovascular bundle down a limb: the core row, alongside the bone, over
## the two bone segments. It stops short of the foot — a foot bitten off does not
## denervate the leg above it.
func _limb_conduit_cells() -> PackedInt32Array:
	var cells := PackedInt32Array()
	for col in LIMB_BONE_COLS:
		cells.append(col * LIMB_ROWS + LIMB_CORE_ROW)
	return cells


# ----------------------------------------------------------------- muscles ----

func _build_muscles() -> void:
	muscles.clear()
	for region in AXIAL_REGIONS:
		var from_col: int = -1
		var to_col: int = 0
		for col in BODY_COLS:
			if _axial_region_of_column(col) != region:
				continue
			if from_col < 0:
				from_col = col
			to_col = col + 1
		if from_col < 0:
			continue
		muscles.append(_muscle(REGION_NAMES[region], region, JOINT_AXIAL,
			BODY_KEY, from_col, to_col))

	# Two actuators per limb, one across each IK joint. The upper block swings the
	# whole limb from the socket; the lower block works the elbow or knee. Which is
	# why a leg chewed at the shank still walks, badly, and one chewed at the
	# shoulder barely moves at all.
	var half: int = LIMB_BONE_COLS / 2
	for key in LIMB_KEYS:
		var region: int = _limb_region_of(key)
		muscles.append(_muscle("%s.upper" % key, region, JOINT_ROOT, key, 0, half))
		muscles.append(_muscle("%s.lower" % key, region, JOINT_MID, key, half,
			LIMB_BONE_COLS))


func _muscle(key: String, region: int, joint: int, patch_key: String,
		from_col: int, to_col: int) -> MuscleGroup:
	var group := MuscleGroup.new()
	group.key = key
	group.region = region
	group.joint = joint
	group.patch_key = patch_key
	group.from_col = from_col
	group.to_col = to_col
	return group


# ------------------------------------------------------------------ lookup ----

func region_name(region: int) -> String:
	return REGION_NAMES[region] if region >= 0 and region < REGIONS else "?"


func is_limb_region(region: int) -> bool:
	return region in LIMB_REGIONS


## The limb a region belongs to, or "" for an axial one.
func limb_key_of(region: int) -> String:
	return REGION_NAMES[region] if is_limb_region(region) else ""


## The body columns an axial region spans, as [from, to). Limb regions answer
## with their bone columns, since that is the span whose skeleton holds them up.
func region_columns(region: int) -> Vector2i:
	if is_limb_region(region):
		return Vector2i(0, LIMB_BONE_COLS)
	var from_col: int = -1
	var to_col: int = 0
	for col in BODY_COLS:
		if _axial_region_of_column(col) != region:
			continue
		if from_col < 0:
			from_col = col
		to_col = col + 1
	return Vector2i(maxi(from_col, 0), to_col)


## The region a limb's socket is anchored to — what its girdle belongs to, and so
## what has to still be there for the limb to be attached to anything.
func socket_region(key: String) -> int:
	return THORAX if key.begins_with("F") else PELVIS
