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
	## Provisional flesh multiplier on the bone radius, per chain — stands in
	## for the census until the Phase-2 knot compiler owns tissue thickness.
	## Only the armature's provisional node masses read it. See Armature.
	var flesh_scale: float = 1.0
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
@export var head_flesh_scale: float = 1.3

@export var tail_nodes: int = 6
@export var tail_length: float = 78.0
@export var tail_base_radius: float = 2.0
@export var tail_tip_radius: float = 0.8
@export var tail_bend_deg: float = 26.0
@export var tail_carry_deg: float = -8.0
@export var tail_flesh_scale: float = 1.3

## Scapula-pivot → elbow → wrist → toe; the 4th node is the metacarpus/paw,
## which is what makes a digitigrade cat leg read right.
@export var fore_leg_length: float = 38.0
@export var fore_leg_shares := PackedFloat32Array([0.37, 0.34, 0.29])
@export var fore_leg_radius: float = 1.5
## Hip → knee → hock → toe; the hock sits high — the cat's "backwards knee".
@export var hind_leg_length: float = 47.0
@export var hind_leg_shares := PackedFloat32Array([0.36, 0.34, 0.30])
@export var hind_leg_radius: float = 1.7
@export var limb_flesh_scale: float = 1.3
## Lateral offset of a limb's pivot from the spine — half the stance width.
@export var girdle_offset: float = 7.0
## The fore girdle is muscle-slung, the hind girdle is bone on bone.
@export var fore_girdle_hold: float = 0.55
@export var hind_girdle_hold: float = 1.0

@export var neck_flesh_scale: float = 1.8
@export var trunk_flesh_scale: float = 2.0

# --------------------------------------------------------------- posture ----

## How much of full leg extension a standing cat uses. Below 1 because a cat
## stands crouched on bent joints, never locked out; the stance heights every
## consumer reads are what the legs deliver at this fraction.
@export var stance_factor: float = 0.80
@export var fore_foot_lead: float = 2.0
@export var hind_foot_lead: float = -2.0

# ----------------------------------------------------------------- fibre ----
# Behavioural scalars kept from v1, consumed from Phase 3 on. Stored now so
# the authoring file's shape is complete and later phases add readers only.

@export var fast_twitch: float = 0.68
@export var hind_insertion: float = 0.27
@export var fore_insertion: float = 0.30
@export var spine_freedom: float = 0.85

# ---------------------------------------------------------------- solver ----

@export var spine_damping: float = 0.64
@export var spine_stiffness: float = 0.88
@export var constraint_iterations: int = 6

# ---------------------------------------------- tissue knots (Phase 2) ------
# Sparse knots per chain × layer, compiled knots → station ellipses → sector
# cells (§5.3 C). Empty until the knot compiler lands; shape declared so the
# Creator's sliders have an address to write to.
@export var tissue_knots: Dictionary = {}

# -------------------------------------------------- features (Phase 2) ------
# Organ/vessel/nerve table (§6): geometry in body coordinates, not cells.
@export var features: Array[Dictionary] = []


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
	trunk.flesh_scale = trunk_flesh_scale
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
	neck.flesh_scale = neck_flesh_scale
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
	tail.flesh_scale = tail_flesh_scale
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
		limb.flesh_scale = limb_flesh_scale
		limb.attach_chain = BodySchema.TRUNK
		limb.attach_index = trunk.node_count - 2 if fore else 0
		limb.attach_hold = fore_girdle_hold if fore else hind_girdle_hold
		limb.foot_lead = fore_foot_lead if fore else hind_foot_lead
		out.append(limb)

	return out


## What the legs deliver as a standing height at a girdle, px above the
## surface. A claim, not a pose: it can never exceed the leg's own length, so
## an animal authored to stand taller than its legs simply stands at full
## stretch. The paw stick is walked flat on a digitigrade foot, so delivery is
## the two proximal bones plus a share of the paw's lift.
func stance_height(fore: bool) -> float:
	var total: float = fore_leg_length if fore else hind_leg_length
	var shares: PackedFloat32Array = fore_leg_shares if fore else hind_leg_shares
	var reach: float = total * (shares[0] + shares[1] + shares[2] * 0.4)
	return reach * clampf(stance_factor, 0.0, 1.0)


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
