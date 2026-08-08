## What the body can still *do*, derived entirely from what it is still made of.
##
##     anatomy  ->  functional body state  ->  procedural animation
##                  ^^^^^^^^^^^^^^^^^^^^^
##
## This is the middle term, and its whole purpose is that the two ends never meet.
## Nothing upstream knows what a stride is; nothing downstream knows what a wound
## is. The gait asks a limb how strong it is and how well it is controlled, and
## gets a number — it never asks which cells are missing, and there is no list of
## injuries anywhere for it to consult. That is what makes limping, dragging,
## weakness, instability and collapse *emergent* rather than authored: none of
## them is a state anything switches into. They are what the ordinary gait does
## when the numbers it reads every tick are no longer all 1.0.
##
## Every quantity here is read fresh from the lattice and the two networks. None
## of them is written by damage. A bite erodes cells; the consequences are worked
## out afterwards, by this, from the cells that survived. So a body chewed in a
## way nobody anticipated still produces a coherent answer, and the one thing that
## can never happen is the functional state disagreeing with the anatomy.
##
## Structure is re-read only when the lattice says it changed. What runs every
## tick is the supply — blood arriving, tissue slowly failing without it — because
## those move continuously while the body does not.
class_name BodyState
extends RefCounted

# --- supply dynamics --------------------------------------------------------
## How quickly blood arriving at a region follows the vessels that feed it. Fast:
## this is flow, not healing.
const PERFUSION_RESPONSE: float = 1.6
## How quickly tissue's own viability follows the blood reaching it. Slow, and
## deliberately the slowest constant here — it is the whole of what makes vessel
## damage *progressive* rather than instant. A limb whose artery is cut does not
## stop working; it weakens over the following several seconds, which is the one
## behaviour a damage-number model cannot produce at all.
const VITALITY_FADE: float = 0.20
## Recovery is slower than failure, so a limb starved and then re-supplied comes
## back over a longer span than it went.
const VITALITY_RECOVER: float = 0.07

# --- blood ------------------------------------------------------------------
## How fast an open body loses blood, per unit of tissue missing. Any wound
## bleeds a little.
const WOUND_BLEED: float = 0.055
## And per unit of opened vascular tree. A cut major vessel is an order of
## magnitude worse than the same area of ordinary flesh, which is why the vessel
## network is worth having as a network rather than as another pool.
const VESSEL_BLEED: float = 0.34
## Below this rate of loss a wound seals and the animal slowly makes it back.
const CLOT_THRESHOLD: float = 0.02
const CLOT_RECOVERY: float = 0.018

# --- consciousness ----------------------------------------------------------
## Share of normal head supply below which the animal is out. Above it,
## consciousness tracks the brain's own integrity.
const FAINT_FLOOR: float = 0.22
## Consciousness at or under which the body stops holding itself up at all.
const COLLAPSE: float = 0.02

# --- functional shaping -----------------------------------------------------
## What a limb keeps of its passive range when its muscle and joint are gone. Not
## zero: a wrecked leg still swings, it just cannot be placed.
const RANGE_FLOOR: float = 0.34
const RANGE_JOINT_FLOOR: float = 0.45
## Share of load-bearing that survives with the bone sound but the flesh gone,
## and with the flesh sound but the nerve cut. A limb is held up by its skeleton,
## braced by its muscle and steadied by its nerve, and losing any of the three
## costs it.
const LOAD_MUSCLE_FLOOR: float = 0.20
const LOAD_CONTROL_FLOOR: float = 0.30
## Load-bearing at which a limb can still be stood on. Under it the limb folds
## and the gait stops asking it to carry anything.
const SUPPORT_MIN: float = 0.30
## Attachment under which a limb is off — not weak, gone.
const ATTACHED_MIN: float = 0.02
## How sharply losing limbs costs travel. Above one, so a creature down to three
## working legs is worse off than three quarters.
const DRIVE_EXPONENT: float = 1.4


## One region's functional state. Every field is a 0..1 capability, and the
## animator is expected to read them and nothing else.
class Region extends RefCounted:
	var index: int = 0
	var name: String = ""

	## Surviving contractile fibre.
	var muscle: float = 1.0
	## What the nervous system delivers here — how much of this region the animal
	## still commands. Nothing to do with whether the flesh is intact.
	var control: float = 1.0
	## Blood arriving now, and how far the tissue itself has followed it. The
	## second lags the first, which is where "progressive" lives.
	var perfusion: float = 1.0
	var vitality: float = 1.0

	## Force this region can actually generate: fibre, times command, times
	## whether that fibre is still being kept alive. The three-term product the
	## whole muscle model comes down to.
	var strength: float = 1.0
	## Whether the skeleton here is still continuous.
	var stability: float = 1.0
	## What it can carry. A broken bone takes this to nothing however strong the
	## muscle around it.
	var load: float = 1.0
	## How far it can still be moved through.
	var motion_range: float = 1.0
	## What it can sustain rather than what it can produce once.
	var stamina: float = 1.0

	## Limbs only: whether the thing is still joined to the animal.
	var attached: float = 1.0
	var severed: bool = false


var plan: BodyPlan = null
var nerves := AnatomyNetwork.new()
var vessels := AnatomyNetwork.new()
var regions: Array[Region] = []
## Force each of the plan's muscle groups can put out, in the same 0..1 currency
## as everything else. Indexed alongside `plan.muscles`.
##
## A region's `strength` is the whole of it; these are the individual actuators
## inside it, so a leg chewed at the shank and a leg chewed at the shoulder are
## not the same leg with the same number. `_fibre` is the surviving tissue half,
## re-read only when the lattice changes.
var actuators: PackedFloat32Array = PackedFloat32Array()
var _fibre: PackedFloat32Array = PackedFloat32Array()
## (region, joint) -> index into the two arrays above, so the gait's per-limb
## lookup is a hash rather than a walk over every muscle in the animal.
var _actuator_index: Dictionary = {}

# --- whole-animal state -----------------------------------------------------
## The brain's output, faded by whether it is still being supplied. Everything
## the animal commands is scaled by this, because it is what the nerve network is
## fed from.
var consciousness: float = 1.0
## The heart's output, times how much blood there is left to move.
var circulation: float = 1.0
var blood: float = 1.0
## Rate blood is currently being lost at, for the HUD and the tests.
var bleeding: float = 0.0
## What fraction of its top speed the body can still produce, and how accurately
## it can still be steered.
var locomotion: float = 1.0
var coordination: float = 1.0
## Limbs that can still be stood on.
var support: int = 4
## True once the animal can no longer hold itself up. The creature reads this and
## collapses; nothing here does anything about it.
var collapsed: bool = false
## False while every number here is still nominal.
##
## Not an optimisation so much as a promise: an animal nobody has touched must
## animate bit for bit as it did before any of this existed, and the cheapest way
## to guarantee that is for the whole consuming layer to be skipped rather than
## multiplied by ones. It also means a healthy creature pays nothing for carrying
## an anatomy.
var impaired: bool = false
## What counts as nominal. Perfusion eases toward its target asymptotically, so an
## exact comparison against 1.0 would leave a healthy animal permanently "impaired"
## by a millionth.
const NOMINAL: float = 0.998

## Lattice revision the structural half was last read at, and the brain reading
## taken with it — the organ is structure, so it is re-read on the same terms as
## the bone and the muscle rather than every tick.
var _revision: int = -1
var _brain: float = 1.0


func configure(p_plan: BodyPlan) -> void:
	plan = p_plan
	nerves.configure(plan.nerves, plan.nerve_root)
	vessels.configure(plan.vessels, plan.vessel_root)
	regions.clear()
	for index in BodyPlan.REGIONS:
		var region := Region.new()
		region.index = index
		region.name = plan.region_name(index)
		regions.append(region)
	actuators.resize(plan.muscles.size())
	actuators.fill(1.0)
	_fibre = actuators.duplicate()
	_actuator_index.clear()
	for index in plan.muscles.size():
		var group: BodyPlan.MuscleGroup = plan.muscles[index]
		_actuator_index[_actuator_key(group.region, group.joint)] = index
	_revision = -1


## Puts the body back to whole. Called with the lattice's own reset, so a creature
## restored to full tissue is not left with a limb still ischaemic from last run.
func reset() -> void:
	consciousness = 1.0
	circulation = 1.0
	blood = 1.0
	bleeding = 0.0
	locomotion = 1.0
	coordination = 1.0
	support = BodyPlan.LIMB_REGIONS.size()
	collapsed = false
	for region in regions:
		region.muscle = 1.0
		region.control = 1.0
		region.perfusion = 1.0
		region.vitality = 1.0
		region.strength = 1.0
		region.stability = 1.0
		region.load = 1.0
		region.motion_range = 1.0
		region.stamina = 1.0
		region.attached = 1.0
		region.severed = false
	actuators.fill(1.0)
	_fibre.fill(1.0)
	_revision = -1


func region(index: int) -> Region:
	return regions[index] if index >= 0 and index < regions.size() else null


func limb(key: String) -> Region:
	return region(int(plan.limb_region.get(key, -1))) if plan != null else null


## Whether a limb can still be asked to do anything: on the animal, able to carry
## itself, and with a nerve still reaching it.
func limb_usable(key: String) -> bool:
	var region: Region = limb(key)
	if region == null:
		return false
	return not region.severed and region.load >= SUPPORT_MIN and region.control > 0.05


## The actuator across one joint of one region. JOINT_ROOT swings a limb from its
## socket, JOINT_MID works its elbow or knee, JOINT_AXIAL is the tone holding a
## stretch of back up.
##
## Keyed by region rather than by patch, so an axial group is as findable as a
## limb one — the two are the same kind of thing and a lookup that only worked for
## limbs would be the place a second, limb-shaped concept crept back in.
func actuator(region_index: int, joint: int) -> float:
	var index: int = int(_actuator_index.get(_actuator_key(region_index, joint), -1))
	return actuators[index] if index >= 0 else 1.0


static func _actuator_key(region_index: int, joint: int) -> int:
	return region_index * 8 + joint


## The region a fraction along the clipped spine falls in — how the rig asks about
## the piece of body one of its joints is actually in.
func axial_at(t: float) -> Region:
	return region(plan.region_at(t)) if plan != null else null


## Re-derives everything from the tissue standing this tick.
##
## Order is the whole argument. Structure first, because it is what everything
## else is measured against. Then blood, which depends only on the heart and on
## how open the body is. Then the nerves, whose source is a brain that has to
## already know whether it is being supplied. Then, and only then, the functional
## numbers the animator reads. Nothing in that chain runs backwards, which is why
## none of it has to iterate to a fixed point.
func update(tissue: TissueGrid, delta: float) -> void:
	if plan == null or tissue == null:
		return
	if tissue.revision != _revision:
		_revision = tissue.revision
		_read_structure(tissue)

	_advance_blood(tissue, delta)
	_advance_supply(delta)
	_derive_function()


# --------------------------------------------------------------- structure ----

## The half that walks the lattice: how much muscle a region still has, whether
## its skeleton is continuous, whether a limb is still on, and how intact every
## nerve and vessel run is.
func _read_structure(tissue: TissueGrid) -> void:
	nerves.read(tissue)
	vessels.read(tissue)
	_brain = tissue.organ(BodyPlan.BRAIN)
	for index in plan.muscles.size():
		var group: BodyPlan.MuscleGroup = plan.muscles[index]
		_fibre[index] = tissue.layer_span(
			group.patch_key, group.from_col, group.to_col, TissueGrid.MUSCLE)
	for region in regions:
		region.muscle = tissue.region_layer(region.index, TissueGrid.MUSCLE)
		var span: Vector2i = plan.region_columns(region.index)
		if plan.is_limb_region(region.index):
			var key: String = plan.limb_key_of(region.index)
			# A limb stands on two skeletons: its own bones, and the girdle it is
			# slung from. Either one broken and the leg is no longer transmitting
			# anything to the ground, which is why the socket is read here rather
			# than being left as a separate special case in the gait.
			region.stability = minf(tissue.bone_span(key, span.x, span.y),
				tissue.girdle_of(key))
			region.attached = tissue.limb_attachment(key)
			region.severed = region.attached <= ATTACHED_MIN
		else:
			region.stability = tissue.bone_span(BodyPlan.BODY_KEY, span.x, span.y)
			region.attached = 1.0
			region.severed = false


# ------------------------------------------------------------------- blood ----

## How much blood there is, and therefore how much circulation a sound heart can
## actually produce.
##
## Two sources of loss, because there are two ways to bleed and they are worth
## different amounts: any open wound seeps, and a severed vessel pours. A body
## losing only the first stops on its own and slowly makes it up; one losing the
## second does not, and runs out. That is the whole of bleeding to death, and it
## needs no timer and no injury class.
func _advance_blood(tissue: TissueGrid, delta: float) -> void:
	var wounds: float = 1.0 - clampf(tissue.integrity(), 0.0, 1.0)
	bleeding = WOUND_BLEED * wounds + VESSEL_BLEED * vessels.openness()
	if bleeding > CLOT_THRESHOLD:
		blood = maxf(blood - bleeding * delta, 0.0)
	else:
		blood = minf(blood + CLOT_RECOVERY * delta, 1.0)
	circulation = tissue.organ(BodyPlan.HEART) * blood


## Blood reaching each region, and how far the tissue there has followed it.
##
## Perfusion is flow and moves quickly; vitality is the tissue's own condition and
## moves slowly, and asymmetrically — it fails faster than it recovers. A limb cut
## off from its supply therefore weakens over seconds rather than switching off,
## and one re-supplied takes longer than that to come back.
func _advance_supply(delta: float) -> void:
	vessels.propagate(circulation)
	for region in regions:
		var target: float = vessels.delivery[region.index]
		if region.severed:
			target = 0.0
		region.perfusion = _ease(region.perfusion, target, PERFUSION_RESPONSE, delta)
		var rate: float = VITALITY_FADE if region.perfusion < region.vitality \
			else VITALITY_RECOVER
		region.vitality = _ease(region.vitality, region.perfusion, rate, delta)

	# The brain is an organ with a blood supply like any other tissue, so it goes
	# out when its head is starved even though nothing has touched it. Below the
	# floor the animal is unconscious; above it, what it has left is however much
	# brain is still there.
	var head: Region = regions[BodyPlan.HEAD]
	var supplied: float = clampf(
		(head.vitality - FAINT_FLOOR) / maxf(1.0 - FAINT_FLOOR, 0.0001), 0.0, 1.0)
	consciousness = _brain * supplied
	collapsed = consciousness <= COLLAPSE


static func _ease(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * delta))


# ---------------------------------------------------------------- function ----

## The numbers the animator actually reads.
##
## Muscle force is the three-term product the design comes down to: surviving
## fibre, times whether the nerve reaches it, times whether the blood is keeping
## it alive. Take away any one and the limb is weak; take away the nerve alone and
## the limb is intact, perfectly healthy, and does nothing — which is exactly the
## behaviour that separates this from a hit-point model.
func _derive_function() -> void:
	nerves.propagate(consciousness)
	var drive: float = 0.0
	support = 0
	impaired = collapsed or consciousness < NOMINAL or circulation < NOMINAL

	for region in regions:
		if region.severed:
			impaired = true
			region.control = 0.0
			region.strength = 0.0
			region.load = 0.0
			region.motion_range = 0.0
			region.stamina = 0.0
			continue

		region.control = nerves.delivery[region.index]
		region.strength = region.muscle * region.control * region.vitality
		region.stamina = region.perfusion
		# Range of motion is passive: it is what the joint and the flesh around it
		# physically allow, whether or not anything is driving them. So it reads
		# muscle and bone and pointedly not control — a denervated limb has its
		# full range and simply nothing to move it with.
		region.motion_range = lerpf(RANGE_FLOOR, 1.0, region.muscle) \
			* lerpf(RANGE_JOINT_FLOOR, 1.0, region.stability)
		# Load-bearing is the skeleton first: a broken bone carries nothing however
		# strong the muscle on it. Muscle and nerve then decide how much of what
		# the bone could carry is actually braced.
		region.load = region.stability \
			* lerpf(LOAD_MUSCLE_FLOOR, 1.0, region.muscle) \
			* lerpf(LOAD_CONTROL_FLOOR, 1.0, region.control)
		if region.strength < NOMINAL or region.stability < NOMINAL \
				or region.motion_range < NOMINAL:
			impaired = true

		if plan.is_limb_region(region.index):
			if region.load >= SUPPORT_MIN:
				support += 1
			drive += minf(region.strength, region.load)

	var limbs: int = maxi(BodyPlan.LIMB_REGIONS.size(), 1)
	drive /= float(limbs)
	# A body pushes off the ground through its own back. However good the legs
	# are, a spine broken between them transmits nothing, so the trunk gates the
	# lot rather than being averaged in with it.
	var trunk: float = minf(minf(regions[BodyPlan.THORAX].stability,
		regions[BodyPlan.LUMBAR].stability), regions[BodyPlan.PELVIS].stability)
	locomotion = clampf(trunk * pow(drive, DRIVE_EXPONENT), 0.0, 1.0)

	var steering: float = 0.0
	for index in BodyPlan.LIMB_REGIONS:
		steering += regions[index].control
	coordination = clampf(steering / float(limbs), 0.0, 1.0)

	# Each actuator gets its region's command and blood, but its own fibre. That
	# is the whole of what makes a muscle a muscle here rather than a share of a
	# regional pool: two blocks on the same nerve and the same artery still pull
	# differently, because different amounts of them are left.
	for index in plan.muscles.size():
		var group: BodyPlan.MuscleGroup = plan.muscles[index]
		var owner: Region = regions[group.region]
		actuators[index] = 0.0 if owner.severed \
			else _fibre[index] * owner.control * owner.vitality
