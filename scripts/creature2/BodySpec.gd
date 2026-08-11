## The authoring file — one resource per creature, everything downstream derived.
##
## This is v2's answer to "properties adjustable from a single location"
## (docs/V2_DESIGN.md §7.5): the Creature Creator's sliders write here, the
## compile steps read here, and no physical behaviour is ever authored twice.
## Biology is data, physics is process — so this file holds lengths, radii,
## limits and carry angles, and holds *no* masses, strengths or speeds: those
## are derivations owned by Corpus and its consumers.
##
## The class defaults ARE the reference cat (the v1 lesson: the reference build
## is the class defaults, not a preset), so `CatBody.tres` is a plain instance
## overriding nothing and any probe that builds `BodySpec.new()` is measuring
## the pinned animal.
##
## Two of the five sections are real as of Phase 1 (chains, posture) plus the
## fibre scalars carried over from v1. Tissue knots and the feature table are
## Phase 2's compile inputs and are stubbed with their shape only.
class_name BodySpec
extends Resource

## One chain of the armature graph, fully resolved — what `chains()` compiles
## the exported knobs into. Root-first; sticks listed attach-first, so a chain
## of n nodes carries n sticks (the attach stick joins the parent node to
## node 0) and the root chain carries n − 1.
class ChainSpec extends RefCounted:
	var name: StringName
	var kind: StringName
	var node_count: int = 0
	## Per-stick bone length, px. These are the anatomical lengths — the plan
	## solver derives its own foreshortened rest lengths from the carry angle.
	var lengths: PackedFloat32Array = PackedFloat32Array()
	## Per-stick bone-core radius, px — the rigid core the census rings wrap.
	var radii: PackedFloat32Array = PackedFloat32Array()
	## Per-joint plan cone limit, degrees. One entry per interior vertex of the
	## chain's stick run (attachment joint included), so `lengths.size() - 1`.
	var bend_deg: PackedFloat32Array = PackedFloat32Array()
	var attach_chain: StringName = &""
	var attach_index: int = -1
	## Girdle compliance: 1.0 is rigid, below it the attach stick is a stiff
	## spring. The cat's scapula floats in muscle — no functional clavicle —
	## which is what makes its front end absorb landings.
	var attach_hold: float = 1.0
	## How the chain is carried off the horizontal at rest, degrees upward.
	## The Z channel raises the carry line at this slope and droop sags below
	## it; the plan solver forshortens rest lengths by its cosine.
	var carry_deg: float = 0.0
	var limb: bool = false
	## -1 left / +1 right, and 0 for axial chains.
	var side: float = 0.0
	## Plan fore-aft offset of the planted foot from its socket, px (+ahead).
	var foot_lead: float = 0.0


# ---------------------------------------------------------------- chains ----
# Node counts are functional stations, not vertebrae (§4.3): the chain is a
# controller, smoothness belongs to the ring sampler.

## Pelvis → sacrum → lumbar ×2 → thoracic ×3 → withers. Carries both girdles.
@export var trunk_nodes: int = 8
@export var trunk_length: float = 62.0
## Bone-core radius per trunk stick, pelvis end first. Stouter over the two
## girdle blocks, waisted between — the census puts flesh on top of this.
@export var trunk_radii := PackedFloat32Array([3.8, 3.4, 3.2, 3.2, 3.3, 3.5, 3.7])
@export var trunk_bend_deg: float = 26.0

## Four cervical stations and a head node carrying the jaw frame.
@export var neck_nodes: int = 4
@export var neck_length: float = 24.0
@export var neck_radius: float = 2.4
@export var neck_bend_deg: float = 30.0
@export var neck_carry_deg: float = 26.0
@export var head_offset: float = 7.0
@export var skull_radius: float = 4.5

@export var tail_nodes: int = 6
@export var tail_length: float = 78.0
@export var tail_base_radius: float = 2.0
@export var tail_tip_radius: float = 0.8
@export var tail_bend_deg: float = 26.0
@export var tail_carry_deg: float = -8.0

## Scapula-pivot → elbow → wrist → toe; the 4th node is the metacarpus/paw,
## which is what makes a digitigrade cat leg read right.
@export var fore_leg_length: float = 38.0
@export var fore_leg_shares := PackedFloat32Array([0.37, 0.34, 0.29])
@export var fore_leg_radius: float = 1.5
## Hip → knee → hock → toe; the hock sits high — the cat's "backwards knee".
@export var hind_leg_length: float = 47.0
@export var hind_leg_shares := PackedFloat32Array([0.36, 0.34, 0.30])
@export var hind_leg_radius: float = 1.7
## Lateral offset of a limb's pivot from the spine — half the stance width.
@export var girdle_offset: float = 7.0
## The fore girdle is muscle-slung, the hind girdle is bone on bone.
@export var fore_girdle_hold: float = 0.55
@export var hind_girdle_hold: float = 1.0

# --------------------------------------------------------------- posture ----
# How the limbs are carried, and what the joints between their bones do. The
# angle is the trait and every length is a projection of it (§7.5, and the v1
# lesson: a limb is a joint angle, per girdle — an authored "how extended it
# stands" fraction cannot express a column standing at 173°). Carriage owns the
# table these leanings are read through; what is authored here is this animal's
# own departure from its stance.

## Which row of Carriage.TABLE this body is built in.
@export var posture: int = 1
## How many stances up the table the girdles can re-carry their limbs. Zero is
## a build that stands one way; see Attitude.RULES, which spends it.
@export var stance_range: int = 0
## How wide the feet are set, as a multiple of what the stance asks for.
@export var stance_width: float = 0.85
## How much more flexed than its stance each girdle stands, degrees; negative is
## straighter. The cat carries a strut in front and a folded spring behind.
@export var fore_flex_deg: float = -16.0
@export var hind_flex_deg: float = 20.0
## How far each joint may close, against what its stance closes to. Over one is
## a joint that folds past its own stance — where a crouch and a leap come from.
@export var fore_fold_range: float = 0.92
@export var hind_fold_range: float = 1.25
## Half-angle of the fan each socket swings its whole limb through, degrees.
@export var fore_swing_deg: float = 58.0
@export var hind_swing_deg: float = 76.0
## How much of the foot is a toe to push off from. A digitigrade cat is already
## standing on its toes and there is real push there.
@export var toe_push: float = 0.50
## The angle a trunk with nothing under its shoulders is carried at, degrees.
## Zero on a quadruped, which has a second girdle and no question to answer.
@export var trunk_lift_deg: float = 0.0
## Where each pair's foot rests fore-and-aft, as a share of what is left of its
## own disc once the lateral stance is spent. Front a little forward, rear a
## little back — which is what puts the feet at the corners of the weight.
@export var front_foot_bias: float = 0.30
@export var rear_foot_bias: float = -0.25
## Rest fore-aft offset of the census's limb chord, px. Rest-pose data: it is
## where the standing foot sits in the built body the census is compiled from,
## and the live gait derives its own from the biases above.
@export var fore_foot_lead: float = 2.0
@export var hind_foot_lead: float = -2.0
## How far ahead of its rest point a foot is aimed, as a share of the stride.
@export var foot_lead: float = 0.45
## How readily a limb is pulled onto a beat its partner has just taken.
@export var beat_coupling: float = 0.55

# ---------------------------------------------------------------- travel ----
# What the animal asks for. Requests, not promises: the legs answer with a
# speed of their own and the lower of the two is what the body travels at.

@export var move_speed: float = 88.0
@export var sprint_multiplier: float = 1.85
@export var turn_speed_deg: float = 210.0
@export var turn_responsiveness: float = 14.0
@export var turn_speed_falloff: float = 0.50
@export var reverse_speed_factor: float = 0.60
## How far behind the head the body turns about, px.
@export var turn_pivot: float = 38.0

# ------------------------------------------------------------------ wave ----
# The travelling lateral undulation. Kinematic — it displaces the body, it
# never pushes it — and what a socket's own share of it comes to is measured
# off the socket rather than predicted, because it is what narrows the stance.

@export var body_wave: float = 4.5
@export var wave_frequency: float = 0.9
@export var wave_speed: float = 2.0

# ----------------------------------------------------------------- fibre ----
# Behavioural scalars kept from v1, consumed from Phase 3 on. Stored now so
# the authoring file's shape is complete and later phases add readers only.

@export var fast_twitch: float = 0.68
@export var hind_insertion: float = 0.27
@export var fore_insertion: float = 0.30
## How freely this back folds along its own length, against a body that could
## curl right round. Authored rather than counted off the chain's bend limits,
## because the chain is a controller with functional stations rather than a
## vertebral census — the total turn a real cat's twelve-odd vertebrae make is
## not the total eight nodes make at the same per-joint limit. One notch under
## Cadence.ROTARY_SPINE: a cat's gallop is transverse, and the dorsomobile
## specialist a step further on is what reverses its leads.
@export var spine_freedom: float = 0.79

# ---------------------------------------------------------------- solver ----

@export var spine_damping: float = 0.64
@export var spine_stiffness: float = 0.88
@export var constraint_iterations: int = 6

# ---------------------------------------------------------- tissue knots ----
# Sparse knots per chain group × layer — the §5.3 C authoring level, compiled
# knots → station ellipses → sector cells by Corpus. Each knot is
# [t, rx, rz, ventral]: t is arc position along the chain [0..1], rx/rz the
# layer's thickness in px at the flank and at the midline (an elliptical
# shell, so a deep chest is rz > rx), and ventral hangs extra thickness
# toward the belly (negative rides it up the back — the epaxial ridge and the
# scruff are authored as negative ventral). Between knots the station values
# are linear in t; past the ends they hold.
#
# Symmetric pairs author once: the four limbs are two groups (fore/hind), and
# the neck group runs withers → jaw tip with the head as its last reach of t,
# so the skull bulge and the masseter are neck knots near t = 1.
#
# The values below ARE the reference cat (§5.4): hindquarters dominant (the
# thigh columns are the deepest muscle on the body), epaxial ridge dorsal
# along the trunk, ribcage bone spanning the thoracic ring, belly and scruff
# fat pads, skin thicker and looser at the scruff, tail and distal limbs
# nearly muscle-free — tendon-operated, which is why legs are light and swing
# fast. The Creature Creator's sliders write multipliers over these lists.
@export var tissue_knots: Dictionary = {
	&"trunk": {
		BodySchema.Layer.BONE: [
			[0.00, 0.90, 0.90, 0.0], [0.16, 0.35, 0.35, 0.0],
			[0.50, 0.30, 0.30, 0.0], [0.60, 0.80, 0.85, 0.0],
			[0.90, 0.80, 0.85, 0.0], [1.00, 0.95, 0.95, 0.0],
		],
		BodySchema.Layer.MUSCLE: [
			[0.00, 3.00, 3.20, -0.9], [0.30, 2.20, 2.60, -1.0],
			[0.62, 2.30, 2.50, -0.6], [1.00, 2.80, 3.00, -0.4],
		],
		BodySchema.Layer.FAT: [
			[0.00, 0.50, 0.45, 0.3], [0.35, 0.80, 0.70, 1.2],
			[0.60, 0.60, 0.55, 0.8], [1.00, 0.35, 0.35, 0.1],
		],
		BodySchema.Layer.SKIN: [
			[0.00, 0.40, 0.40, 0.0], [1.00, 0.42, 0.42, 0.0],
		],
	},
	&"neck": {
		BodySchema.Layer.BONE: [
			[0.00, 0.50, 0.50, 0.0], [0.72, 0.40, 0.40, 0.0],
			[0.85, 1.60, 1.60, 0.0], [1.00, 1.80, 1.80, 0.0],
		],
		BodySchema.Layer.MUSCLE: [
			[0.00, 2.00, 2.00, -0.5], [0.60, 1.40, 1.40, -0.3],
			[0.80, 1.00, 1.00, 0.0], [0.92, 1.60, 1.50, 0.4],
			[1.00, 0.60, 0.60, 0.2],
		],
		BodySchema.Layer.FAT: [
			[0.00, 0.50, 0.45, -0.8], [0.55, 0.35, 0.35, -0.6],
			[0.80, 0.15, 0.15, 0.0], [1.00, 0.10, 0.10, 0.0],
		],
		BodySchema.Layer.SKIN: [
			[0.00, 0.60, 0.60, -0.3], [0.55, 0.50, 0.50, -0.2],
			[1.00, 0.35, 0.35, 0.0],
		],
	},
	&"tail": {
		BodySchema.Layer.BONE: [
			[0.00, 0.35, 0.35, 0.0], [1.00, 0.15, 0.15, 0.0],
		],
		BodySchema.Layer.MUSCLE: [
			[0.00, 0.80, 0.80, 0.0], [0.35, 0.30, 0.30, 0.0],
			[1.00, 0.04, 0.04, 0.0],
		],
		BodySchema.Layer.FAT: [
			[0.00, 0.30, 0.30, 0.0], [1.00, 0.08, 0.08, 0.0],
		],
		BodySchema.Layer.SKIN: [
			[0.00, 0.35, 0.35, 0.0], [1.00, 0.30, 0.30, 0.0],
		],
	},
	&"fore_limb": {
		BodySchema.Layer.BONE: [
			[0.00, 0.35, 0.35, 0.0], [1.00, 0.28, 0.28, 0.0],
		],
		BodySchema.Layer.MUSCLE: [
			[0.00, 2.30, 2.30, 0.3], [0.35, 1.10, 1.10, 0.2],
			[0.60, 0.35, 0.35, 0.0], [1.00, 0.04, 0.04, 0.0],
		],
		BodySchema.Layer.FAT: [
			[0.00, 0.35, 0.35, 0.0], [0.50, 0.12, 0.12, 0.0],
			[1.00, 0.06, 0.06, 0.0],
		],
		BodySchema.Layer.SKIN: [
			[0.00, 0.40, 0.40, 0.0], [1.00, 0.30, 0.30, 0.0],
		],
	},
	&"hind_limb": {
		BodySchema.Layer.BONE: [
			[0.00, 0.40, 0.40, 0.0], [1.00, 0.28, 0.28, 0.0],
		],
		BodySchema.Layer.MUSCLE: [
			[0.00, 3.40, 3.60, -0.2], [0.30, 1.90, 2.00, 0.0],
			[0.55, 0.45, 0.45, 0.0], [1.00, 0.04, 0.04, 0.0],
		],
		BodySchema.Layer.FAT: [
			[0.00, 0.45, 0.40, 0.2], [0.50, 0.12, 0.12, 0.0],
			[1.00, 0.06, 0.06, 0.0],
		],
		BodySchema.Layer.SKIN: [
			[0.00, 0.40, 0.40, 0.0], [1.00, 0.30, 0.30, 0.0],
		],
	},
}

# -------------------------------------------------------------- features ----
# Organs, vessels and nerves (§6): geometry in body coordinates, never cells.
# Coordinates use the census conventions — t along the chain (trunk runs
# pelvis 0 → withers 1, neck runs withers 0 → jaw tip 1), θ around the axis
# from dorsal (0 the back, π/2 the right flank, π the belly, 3π/2 the left),
# and depth as a fraction of the local flesh depth from the surface inward
# (0 at the skin, 1 at the bone core) so a physique retune moves the flesh
# and the features stay where the flesh is.
#
# Organs carry a t range, an angular centre + spread, a depth band and an
# effect. Vessels are polylines of [t, θ, depth] with a radius and a flow
# rate (bleed on breach); nerves are polylines with the region they serve
# (function loss on cut). The placements encode the anatomy the combat rules
# would otherwise have had to special-case: the heart is ventral-thoracic
# inside the rib ring, the carotids are shallow in the throat — which is why
# throat bites kill, as geometry rather than as a rule — and the spinal cord
# is dorsal at full depth, protected until the vertebra is breached.
@export var features: Array[Dictionary] = [
	{"feature": "organ", "name": "heart", "chain": &"trunk",
		"t_range": Vector2(0.80, 0.88), "theta": PI, "spread": 0.5,
		"depth": Vector2(0.75, 1.0), "hp": 1.0, "effect": "arrest"},
	{"feature": "organ", "name": "lung_left", "chain": &"trunk",
		"t_range": Vector2(0.72, 0.95), "theta": 4.712389, "spread": 0.8,
		"depth": Vector2(0.7, 1.0), "hp": 1.0, "effect": "aerobic"},
	{"feature": "organ", "name": "lung_right", "chain": &"trunk",
		"t_range": Vector2(0.72, 0.95), "theta": 1.570796, "spread": 0.8,
		"depth": Vector2(0.7, 1.0), "hp": 1.0, "effect": "aerobic"},
	{"feature": "organ", "name": "liver", "chain": &"trunk",
		"t_range": Vector2(0.62, 0.72), "theta": 2.5, "spread": 0.7,
		"depth": Vector2(0.6, 1.0), "hp": 1.0, "effect": "filter"},
	{"feature": "organ", "name": "stomach", "chain": &"trunk",
		"t_range": Vector2(0.35, 0.60), "theta": PI, "spread": 0.9,
		"depth": Vector2(0.6, 1.0), "hp": 1.0, "effect": "digest"},
	{"feature": "organ", "name": "kidney_left", "chain": &"trunk",
		"t_range": Vector2(0.45, 0.55), "theta": 5.88, "spread": 0.4,
		"depth": Vector2(0.65, 1.0), "hp": 1.0, "effect": "filter"},
	{"feature": "organ", "name": "kidney_right", "chain": &"trunk",
		"t_range": Vector2(0.45, 0.55), "theta": 0.4, "spread": 0.4,
		"depth": Vector2(0.65, 1.0), "hp": 1.0, "effect": "filter"},
	{"feature": "organ", "name": "brain", "chain": &"neck",
		"t_range": Vector2(0.92, 1.0), "theta": 0.0, "spread": PI,
		"depth": Vector2(0.8, 1.0), "hp": 1.0, "effect": "collapse"},
	{"feature": "vessel", "name": "aorta", "chain": &"trunk",
		"path": [[0.05, 0.0, 0.9], [0.50, 0.0, 0.9], [0.95, 0.0, 0.9]],
		"radius": 0.8, "flow": 3.0},
	{"feature": "vessel", "name": "carotid_left", "chain": &"neck",
		"path": [[0.05, 4.2, 0.3], [0.75, 4.2, 0.3]],
		"radius": 0.5, "flow": 2.5},
	{"feature": "vessel", "name": "carotid_right", "chain": &"neck",
		"path": [[0.05, 2.1, 0.3], [0.75, 2.1, 0.3]],
		"radius": 0.5, "flow": 2.5},
	{"feature": "vessel", "name": "femoral_left", "chain": &"HL",
		"path": [[0.02, 1.570796, 0.5], [0.30, 1.3, 0.4]],
		"radius": 0.4, "flow": 1.8},
	{"feature": "vessel", "name": "femoral_right", "chain": &"HR",
		"path": [[0.02, 4.712389, 0.5], [0.30, 4.9, 0.4]],
		"radius": 0.4, "flow": 1.8},
	{"feature": "nerve", "name": "spinal_cord", "chain": &"trunk",
		"path": [[0.0, 0.0, 1.0], [1.0, 0.0, 1.0]], "serves": "body"},
	{"feature": "nerve", "name": "spinal_cord_neck", "chain": &"neck",
		"path": [[0.0, 0.0, 1.0], [0.95, 0.0, 1.0]], "serves": "body"},
	{"feature": "nerve", "name": "sciatic_left", "chain": &"HL",
		"path": [[0.0, PI, 0.8], [0.5, PI, 0.7]], "serves": "HL"},
	{"feature": "nerve", "name": "sciatic_right", "chain": &"HR",
		"path": [[0.0, PI, 0.8], [0.5, PI, 0.7]], "serves": "HR"},
]


## The compiled chain graph for the armature — six chains, ~35 nodes.
## Assembly is structure (which stations exist and where they attach, §4.2);
## the numbers in it are the exported knobs above. Nothing here is pose.
func chains() -> Array[ChainSpec]:
	var out: Array[ChainSpec] = []

	var trunk := ChainSpec.new()
	trunk.name = BodySchema.TRUNK
	trunk.kind = BodySchema.TRUNK
	trunk.node_count = maxi(trunk_nodes, 2)
	var trunk_sticks: int = trunk.node_count - 1
	trunk.lengths = _spread(trunk_length, trunk_sticks)
	trunk.radii = _resample(trunk_radii, trunk_sticks)
	trunk.bend_deg = _fill(trunk_bend_deg, trunk_sticks - 1)
	out.append(trunk)

	# The neck chain owns its cervical stations plus the head node, so its
	# stick run is: attach (withers → C0), the cervical spans, then the head
	# stick whose radius is the skull — the bulge the head's mass derives from.
	var neck := ChainSpec.new()
	neck.name = BodySchema.NECK
	neck.kind = BodySchema.NECK
	neck.node_count = maxi(neck_nodes, 2) + 1
	var cervical: int = neck.node_count - 1
	neck.lengths = _spread(neck_length, cervical)
	neck.lengths.append(head_offset)
	neck.radii = _fill(neck_radius, cervical)
	neck.radii.append(skull_radius)
	neck.bend_deg = _fill(neck_bend_deg, neck.node_count - 1)
	neck.attach_chain = BodySchema.TRUNK
	neck.attach_index = trunk.node_count - 1
	neck.carry_deg = neck_carry_deg
	out.append(neck)

	var tail := ChainSpec.new()
	tail.name = BodySchema.TAIL
	tail.kind = BodySchema.TAIL
	tail.node_count = maxi(tail_nodes, 2)
	tail.lengths = _spread(tail_length, tail.node_count)
	tail.radii = _taper(tail_base_radius, tail_tip_radius, tail.node_count)
	tail.bend_deg = _fill(tail_bend_deg, tail.node_count - 1)
	tail.attach_chain = BodySchema.TRUNK
	tail.attach_index = 0
	tail.carry_deg = tail_carry_deg
	out.append(tail)

	# Fore limbs hang one station behind the withers, hind limbs off the
	# pelvis — the same stations the girdle frames live on.
	for limb_name: StringName in [&"FL", &"FR", &"HL", &"HR"]:
		var fore: bool = limb_name in [&"FL", &"FR"]
		var limb := ChainSpec.new()
		limb.name = limb_name
		limb.kind = BodySchema.LIMB
		limb.limb = true
		limb.side = -1.0 if limb_name in [&"FL", &"HL"] else 1.0
		limb.node_count = 4
		var total: float = fore_leg_length if fore else hind_leg_length
		var shares: PackedFloat32Array = fore_leg_shares if fore else hind_leg_shares
		limb.lengths = PackedFloat32Array([girdle_offset])
		for share in shares:
			limb.lengths.append(total * share)
		limb.radii = _fill(fore_leg_radius if fore else hind_leg_radius, 4)
		limb.bend_deg = _fill(0.0, 3)
		limb.attach_chain = BodySchema.TRUNK
		limb.attach_index = trunk.node_count - 2 if fore else 0
		limb.attach_hold = fore_girdle_hold if fore else hind_girdle_hold
		limb.foot_lead = fore_foot_lead if fore else hind_foot_lead
		out.append(limb)

	return out


## What the legs deliver as a standing height at a girdle, px above the
## surface — the rest-pose datum the census is compiled in.
##
## A claim, not a pose, and one arithmetic rather than two: the limb spans what
## its joint angle makes it span, its foot rests where the stance and the bias
## put it, and the height is the third side of that triangle. Everything live
## reads the same closed form off the *active* carriage (see
## Carriage.stance_clearance); this asks it of the stance the animal is built
## in, which is the one the census may read — an animal re-carrying its limbs
## does not re-grow its tissue.
func stance_height(fore: bool) -> float:
	var rest := Carriage.new(self, posture)
	var joint: Carriage.Joint = rest.of(fore)
	return rest.stance_clearance(limb_length(fore), joint.stand, stance_width,
		front_foot_bias if fore else rear_foot_bias)


## The anatomical length of one pair's limb — the three bones the chain is
## solved with, the girdle-offset stick being trunk rather than leg.
func limb_length(fore: bool) -> float:
	return fore_leg_length if fore else hind_leg_length


## How the limb's length divides either side of the joint the stance is quoted
## at. The paw is walked flat and folds with the shank, so the chain is two
## levers for this purpose: the proximal bone, and everything below it.
func upper_share(fore: bool) -> float:
	var shares: PackedFloat32Array = fore_leg_shares if fore else hind_leg_shares
	var total: float = 0.0
	for s in shares:
		total += s
	return shares[0] / maxf(total, 0.0001)


func _spread(total: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(count, 1))
	out.fill(total / float(maxi(count, 1)))
	return out


func _fill(value: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(count, 0))
	out.fill(value)
	return out


func _taper(from: float, to: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(count, 1))
	for i in out.size():
		out[i] = lerpf(from, to, float(i) / float(maxi(out.size() - 1, 1)))
	return out


## Resamples an authored per-stick profile onto however many sticks the chain
## actually has, so retuning the node count never invalidates the radii.
func _resample(profile: PackedFloat32Array, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(count, 1))
	if profile.is_empty():
		out.fill(1.0)
		return out
	if profile.size() == 1:
		out.fill(profile[0])
		return out
	for i in out.size():
		var s: float = float(i) / float(maxi(out.size() - 1, 1)) * float(profile.size() - 1)
		var j: int = clampi(int(s), 0, profile.size() - 2)
		out[i] = lerpf(profile[j], profile[j + 1], s - float(j))
	return out
