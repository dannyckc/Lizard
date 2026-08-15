## The anatomy layer of the armature — every joint named, bounded and solved.
##
## The armature stores the skeleton (explicit points joined by rigid sticks);
## what it never had is the claim that node 21 is an *elbow* — a hinge with a
## fold direction, a range it works in, and stops it may not pass. This file is
## that claim, for the erect quadrupedal class with the cat as its reference
## animal, and it is consulted at exactly three seams:
##
##   * `axial_limits` — per-vertex lateral cones for the spine, graded by
##     anatomical region (lumbar folds, cranial thorax does not) instead of by
##     stick radius alone.
##   * `solve_limb` — the constrained limb solve that replaced the free FABRIK:
##     deterministic, symmetric, digitigrade, and stopped at the joints' own
##     range of motion, so an anatomically impossible pose is unreachable
##     rather than merely unlikely.
##   * `arch_profile` / head-righting constants — the sagittal and torsional
##     shape of the axial line, expressed by the Z channel.
##
## Anatomy is quoted from veterinary and biomechanics literature; every number
## is tagged FACT (measured, cited) or APPROX (our modelling choice, with the
## reasoning). Angles are *interior* angles at a joint — 180° is a straight
## limb — matching goniometric convention (Jaeger et al. 2007, AJVR 68:822).
##
## The class is reusable: the tables are the erect row; a columnar or sprawled
## class supplies its own profile tables and the seams do not change. Nothing
## here is a pose — the rig bounds poses, the motion layer asks for them.
class_name Rig
extends RefCounted

# ------------------------------------------------------------- the spine ----
# Lateral (plan) cone limits per station, degrees, scaled by the authored
# per-chain scalar against the reference cat's (so BodySpec stays the single
# authoring seam). Regional grading is the anatomy:
#
# FACT — the feline vertebral column is C7 T13 L7 S3 Cd18–23; the lumbar spine
# is the mobile engine, mobility rises caudal to the anticlinal vertebra
# (~T11), the cranial thorax is stiffened by the rib cage, and the
# lumbosacral junction is the largest single mover (7–22° sagittal in
# asymmetric gaits, against 1–9° per joint elsewhere) — Schilling & Hackert
# 2006, J Exp Biol 209:3925; IMAIOS vet-anatomy; Veterian Key "Spine".
#
# APPROX — eight trunk stations stand in for 20 presacral vertebrae, so each
# profile entry aggregates ~3 vertebrae; the entries are chosen to keep the
# measured regional ratios and to leave the chain's total sweep within a few
# percent of the tuned build (back_sweep ~236° -> ~230°, neck_sweep 166.4°
# preserved exactly), because the turn and gaze behaviours are calibrated
# against those totals.
#
# Trunk entries run pelvis-first: sacrum/Cd-junction, lumbosacral, mid-lumbar,
# anticlinal (T13), T11, T8, T4, T1/withers-junction.
const TRUNK_LATERAL: Array[float] = [40.0, 45.0, 42.0, 38.0, 32.0, 22.0, 17.0, 30.0]
const TRUNK_LATERAL_REF: float = 26.0
# Neck entries run withers-first: C7/T1 base, C5, C3, atlantoaxial+atlanto-
# occipital (the largest — FACT: the atlantoaxial joint carries most cervical
# axial rotation; IMAIOS vet-anatomy).
const NECK_LATERAL: Array[float] = [30.4, 40.0, 45.0, 51.0]
const NECK_LATERAL_REF: float = 30.0
# Tail entries run base-first. FACT: caudal mobility increases toward the tip
# (per-joint ranges grow as the vertebrae shrink); the tail is an active
# inertial counterweight (Walker et al. 1998, Behav Brain Res 91:41).
const TAIL_LATERAL: Array[float] = [34.0, 36.0, 38.2, 41.0, 46.0]
const TAIL_LATERAL_REF: float = 26.0

# Sagittal arch shares per trunk station, pelvis-first — the shape of a
# gathering back. FACT: sagittal bending in asymmetric gaits involves ~7
# presacral joints with the lumbosacral junction dominant (Schilling & Hackert
# 2006); the profile peaks over the lumbar run and dies at both girdles, which
# stand at what the legs deliver. APPROX: the rise is expressed as a bump on
# the carried heights (the Z channel's law: assigned, never integrated).
const TRUNK_ARCH: Array[float] = [0.0, 0.55, 0.95, 1.0, 0.75, 0.45, 0.18, 0.0]
## Peak arch rise at full crouch, as a share of trunk length.
const ARCH_RISE: float = 0.10

# ------------------------------------------------------------- the limbs ----
# Interior-angle stops, degrees. These are *passive* anatomical stops — what
# the joint itself allows — distinct from Carriage's stand/lock/fold, which is
# where the muscle *holds* the limb per posture. The solve clamps at anatomy;
# the carriage shapes the stance upstream through the reach quotes.
#
# FACT — passive goniometry in healthy cats (Lascelles et al. 2012, BMC Vet
# Res 8:10, n=100: total arcs shoulder 136°, elbow 144°, carpus 184°, hip
# 122°, stifle 146°, tarsus 147°; Jaeger et al. 2007 validated the endpoint
# method; feline shoulder endpoints 32°/164°, Veterian Key "The Shoulder").
# APPROX — endpoint pairs placed so each arc matches the Lascelles mean and
# brackets the walking ranges measured by Rahmati et al. 2025 (J Physiol,
# swing minima: shoulder 86.8°, elbow 78.5°; carpus hyperextends past 230° in
# stance) and the 3D hindlimb ranges of PLOS One 2018 13:e0197837.
const ELBOW_ROM := Vector2(22.0, 166.0)
const CARPUS_ROM := Vector2(70.0, 245.0)
const STIFLE_ROM := Vector2(24.0, 170.0)
const TARSUS_ROM := Vector2(21.0, 168.0)
## Documented for the record and enforced upstream: the proximal fan a limb
## swings through is Carriage's `swing`, and the excursion disc every foot
## target is capped to is derived from it — so the ball joints' range is a
## constraint on where feet may be asked to go, not a clamp inside the solve.
const SHOULDER_ROM := Vector2(32.0, 164.0)
const HIP_ROM := Vector2(40.0, 162.0)

# FACT — the cat has no functional clavicle: the scapula floats in muscle and
# is functionally the first segment of the forelimb, its retraction a large
# share of forelimb stride (Fischer & Blickhan 2006, the tri-segmented limb;
# Boczek-Funcke et al. 1996 X-ray kinematics: scapula ~40° off horizontal in
# late swing, 45°±7° at touchdown). APPROX — modelled as a fore-aft glide of
# the glenoid: the socket follows the working foot by SCAP_FOLLOW of its
# fore-aft excursion, capped to SCAP_TRAVEL of the scapula's own length.
## How much of the foot's fore-aft excursion the shoulder socket follows.
const SCAP_FOLLOW: float = 0.35
## Cap on that glide, as a share of scapula length either way.
const SCAP_TRAVEL: float = 0.45

# FACT — cats stabilise the head against trunk motion (vestibular righting;
# the beam-perturbation work that shows the trunk organising itself around a
# level head — Walker et al. 1998 and the righting literature). APPROX — the
# neck counter-rotates a share of the body's heel, graded from the withers to
# the head and capped: a cat at a full 90° heel does not hold a level head.
const HEAD_RIGHT_MAX: float = 0.6

## How much of the standing pastern angle a swinging paw keeps — a lifted paw
## folds toward the shank (FACT: the carpus is most plantarflexed in early-to-
## mid swing, Rahmati et al. 2025; value APPROX).
const PAW_SWING_SHARE: float = 0.45

## Solver guard: nearest the wrist may stand to the socket, px.
const NEAR_MIN: float = 0.5


## One named joint of the skeleton — an explicit point (an armature node) with
## an identity, a kind, and its bounds. The census of these is the rig; the
## solve and the Z channel read the tables above through it.
class JointSpec extends RefCounted:
	var name: StringName
	## The armature node this joint lives at.
	var node: int = -1
	## &"ball", &"hinge", &"compound" (carpus/tarsus rows), &"pivot" (the
	## scapular glide), or &"station" (an axial vertex under a lateral cone).
	var kind: StringName = &"station"
	## Lateral plan cone, radians — axial stations only.
	var lateral: float = 0.0
	## Interior-angle stops, radians — limb joints only.
	var rom: Vector2 = Vector2.ZERO
	## Sagittal arch share — trunk stations only.
	var arch: float = 0.0


var spec: BodySpec
## Whether the last standing solve ran out of joints — the stop-correction
## could not bring the low joint legal inside the middle joint's own annulus.
## The anatomy's way of saying the planted toe can no longer be held: read by
## the armature into the limb, and spent by the gait as the emergency it is.
var cramped: bool = false
## The active posture — rest at build, re-pointed by the creature every tick
## (Attitude owns the blend). Read for the stand preferences, never written.
var carriage: Carriage
## The joint census, in armature node order where a node carries a joint.
var joints: Array[JointSpec] = []

# Cached per-limb solve tables, radians.
var _elbow: Vector2
var _carpus: Vector2
var _stifle: Vector2
var _tarsus: Vector2
var _fore_pastern: float
var _hind_pastern: float


func build(p_spec: BodySpec) -> void:
	spec = p_spec
	carriage = Carriage.new(spec, spec.posture)
	_elbow = Vector2(deg_to_rad(ELBOW_ROM.x), deg_to_rad(ELBOW_ROM.y))
	_carpus = Vector2(deg_to_rad(CARPUS_ROM.x), deg_to_rad(CARPUS_ROM.y))
	_stifle = Vector2(deg_to_rad(STIFLE_ROM.x), deg_to_rad(STIFLE_ROM.y))
	_tarsus = Vector2(deg_to_rad(TARSUS_ROM.x), deg_to_rad(TARSUS_ROM.y))
	_fore_pastern = deg_to_rad(spec.fore_pastern_deg)
	_hind_pastern = deg_to_rad(spec.hind_pastern_deg)


## Names the skeleton: one JointSpec per armature node that is a joint. Called
## by the armature once its chains exist, so the census matches the graph that
## was actually built whatever the authored node counts are.
func name_joints(armature: Armature) -> void:
	joints.clear()
	var trunk: Armature.Chain = armature.chain(BodySchema.TRUNK)
	var neck: Armature.Chain = armature.chain(BodySchema.NECK)
	var tail: Armature.Chain = armature.chain(BodySchema.TAIL)
	var trunk_names: Array[StringName] = [&"sacrum", &"lumbosacral", &"L4",
		&"T13", &"T11", &"T8", &"T4", &"withers"]
	var neck_names: Array[StringName] = [&"C7", &"C5", &"C3", &"atlas", &"head"]
	var arch_shares: PackedFloat32Array = _resample(TRUNK_ARCH, trunk.nodes.size())
	var trunk_lat: PackedFloat32Array = _profile(TRUNK_LATERAL,
		TRUNK_LATERAL_REF, spec.trunk_bend_deg, trunk.nodes.size())
	for j in trunk.nodes.size():
		var s := JointSpec.new()
		s.name = trunk_names[j] if j < trunk_names.size() else StringName("T%d" % j)
		s.node = trunk.nodes[j]
		s.lateral = trunk_lat[j]
		s.arch = arch_shares[j]
		joints.append(s)
	var neck_lat: PackedFloat32Array = _profile(NECK_LATERAL, NECK_LATERAL_REF,
		spec.neck_bend_deg, neck.nodes.size() - 1)
	for j in neck.nodes.size():
		var s := JointSpec.new()
		s.name = neck_names[j] if j < neck_names.size() else StringName("C%d" % j)
		s.node = neck.nodes[j]
		s.lateral = neck_lat[j] if j < neck_lat.size() else 0.0
		joints.append(s)
	var tail_lat: PackedFloat32Array = _profile(TAIL_LATERAL, TAIL_LATERAL_REF,
		spec.tail_bend_deg, tail.nodes.size() - 1)
	for j in tail.nodes.size():
		var s := JointSpec.new()
		s.name = StringName("Cd%d" % (j + 1))
		s.node = tail.nodes[j]
		s.lateral = tail_lat[j] if j < tail_lat.size() else 0.0
		joints.append(s)
	for limb in armature.limbs:
		var fore: bool = limb.parent_node != trunk.nodes[0]
		var names: Array[StringName]
		var roms: Array[Vector2]
		if fore:
			names = [&"shoulder", &"elbow", &"carpus", &"fore_toe"]
			roms = [SHOULDER_ROM, ELBOW_ROM, CARPUS_ROM, Vector2.ZERO]
		else:
			names = [&"hip", &"stifle", &"tarsus", &"hind_toe"]
			roms = [HIP_ROM, STIFLE_ROM, TARSUS_ROM, Vector2.ZERO]
		var kinds: Array[StringName] = [&"ball", &"hinge", &"compound", &"station"]
		for j in limb.nodes.size():
			var s := JointSpec.new()
			s.name = StringName("%s_%s" % [limb.name, names[j]])
			s.node = limb.nodes[j]
			s.kind = kinds[j]
			s.rom = Vector2(deg_to_rad(roms[j].x), deg_to_rad(roms[j].y))
			joints.append(s)


## The per-vertex lateral cones for the armature's axial line, in solve order —
## what `_build_axial` holds instead of the radius-graded uniform cone. A
## junction vertex (pelvis, withers) takes the stricter of the two chains
## meeting there, exactly as before; the values inside a chain are the regional
## profile scaled by the animal's own authored scalar.
func axial_limits(armature: Armature) -> PackedFloat32Array:
	var trunk: Armature.Chain = armature.chain(BodySchema.TRUNK)
	var neck: Armature.Chain = armature.chain(BodySchema.NECK)
	var tail: Armature.Chain = armature.chain(BodySchema.TAIL)
	var trunk_lat: PackedFloat32Array = _profile(TRUNK_LATERAL,
		TRUNK_LATERAL_REF, spec.trunk_bend_deg, trunk.nodes.size())
	var neck_lat: PackedFloat32Array = _profile(NECK_LATERAL, NECK_LATERAL_REF,
		spec.neck_bend_deg, neck.nodes.size() - 1)
	var tail_lat: PackedFloat32Array = _profile(TAIL_LATERAL, TAIL_LATERAL_REF,
		spec.tail_bend_deg, tail.nodes.size() - 1)

	var at: Dictionary = {}
	for j in trunk.nodes.size():
		at[trunk.nodes[j]] = trunk_lat[j]
	for j in mini(neck_lat.size(), neck.nodes.size()):
		at[neck.nodes[j]] = neck_lat[j]
	for j in mini(tail_lat.size(), tail.nodes.size()):
		at[tail.nodes[j]] = tail_lat[j]
	# The junctions: the pelvis vertex sits between the last tail stick and the
	# first trunk stick, the withers vertex between trunk and neck. Stricter
	# neighbour wins, so a chain may not fold at a junction further than the
	# stiffer of the two anatomies meeting there.
	at[trunk.nodes[0]] = minf(trunk_lat[0], tail_lat[0])
	var withers: int = trunk.nodes[trunk.nodes.size() - 1]
	at[withers] = minf(trunk_lat[trunk_lat.size() - 1], neck_lat[0])

	var out := PackedFloat32Array()
	for k in range(1, armature.axial.size() - 1):
		out.append(at.get(armature.axial[k], deg_to_rad(30.0)))
	return out


## The sagittal arch shares per trunk node, resampled to the built chain.
func arch_profile(count: int) -> PackedFloat32Array:
	return _resample(TRUNK_ARCH, count)


## How far the fore socket glides fore-aft along the body for a foot working
## at `foot_along` px ahead (+) of its rest lead — the scapula expressed. Zero
## at the rest stance by construction, so the census datum never moves.
func scapula_shift(foot_along: float) -> float:
	var cap: float = SCAP_TRAVEL * spec.scapula_len
	return clampf(foot_along * SCAP_FOLLOW, -cap, cap)


## The constrained limb solve, in the limb's own vertical plane. `bones` are
## the in-plane bone lengths (the armature pre-shrinks them for the lateral
## bow so 3D lengths stay exact), `socket_z` the solved socket height, `target`
## the toe in plane coordinates (x along the plane's axis from the socket,
## y world height), `lead` which way the animal's forward points along x,
## `standing` whether the paw is bearing (a planted paw stands at its pastern
## angle; a swinging one folds toward the shank).
##
## Deterministic and symmetric: the same inputs give the same limb, left and
## right, tick after tick — no seed, no history. Angular stops are the
## anatomy tables; the fold directions (elbow caudal, stifle cranial, hock
## caudal) are hard properties of the joint, not seeds. A planted toe is
## placed exactly (support is not negotiable); what the stops bound is the
## folding above it. Beyond total anatomical reach the chain lays out
## straight toward the target and arrives short — the tear-off rule upstream
## is what owns that honesty.
func solve_limb(bones: PackedFloat32Array, socket_z: float, target: Vector2,
		lead: float, fore: bool, standing: bool) -> PackedVector2Array:
	cramped = false
	var u: float = bones[0]
	var l: float = bones[1]
	var p: float = bones[2]
	var s := Vector2(0.0, socket_z)
	var rom_mid: Vector2 = _elbow if fore else _stifle
	var rom_low: Vector2 = _carpus if fore else _tarsus
	var pastern: float = _fore_pastern if fore else _hind_pastern
	var phi: float = pastern if standing else pastern * PAW_SWING_SHARE

	# The wrist (or hock) the paw prefers: behind the toe by the pastern's
	# plan share, above it by the pastern's rise — the digitigrade stand.
	var wrist := Vector2(target.x - lead * p * cos(phi), target.y + p * sin(phi))

	# Which side of the socket-wrist line this joint folds to — elbows fold
	# caudally, stifles cranially. The side is the joint's nature: a straight
	# limb has not forgotten it, so a drop that straightens a leg re-folds it
	# the right way without a re-seed.
	var side: float = (-1.0 if fore else 1.0) * (lead if lead != 0.0 else 1.0)

	# The reach annulus the middle joint's stops allow the wrist to stand in.
	var d_lo: float = _span(u, l, rom_mid.x)
	var d_hi: float = _span(u, l, minf(rom_mid.y, PI))
	var d: float = s.distance_to(wrist)

	if d > d_hi:
		# Too far for the joint: the wrist walks the paw circle toward the
		# socket until the stop is satisfied — or the whole limb is simply out
		# of reach and lays toward the target at its own extension stop,
		# arriving short. Never geometrically straight: full stretch on this
		# skeleton is the joint's stop, not 180°.
		var met: Array = _circle_circle(s, d_hi, target, p)
		if met.is_empty():
			return _extended(s, target, u, l, p, d_hi, side)
		wrist = _pick(met, wrist)
		d = d_hi
	elif d < maxf(d_lo, NEAR_MIN):
		var floor_d: float = maxf(d_lo, NEAR_MIN)
		var met: Array = _circle_circle(s, floor_d, target, p)
		if met.is_empty():
			# The toe is being asked inside the folded limb's own core — hold
			# the wrist at the stop along the asked direction and let the paw
			# arrive where it can. A crush, and it reads as one.
			var dir: Vector2 = (wrist - s).normalized() if d > 0.001 \
				else Vector2(-lead, 0.0)
			wrist = s + dir * floor_d
		else:
			wrist = _pick(met, wrist)
		d = floor_d

	# The middle joint: interior angle from the cosine rule (already legal by
	# the clamp above), placed on its own anatomical side of the socket-wrist
	# line.
	var gamma: float = acos(clampf((u * u + d * d - l * l) / (2.0 * u * d),
		-1.0, 1.0))
	var mid: Vector2 = s + (wrist - s).normalized().rotated(side * gamma) * u

	# The lower joint's own stop, checked on the solved pose and held for every
	# paw — differently per case, because what may move differs. A swinging paw
	# folds to its nearest stop about the wrist: the toe is in the air. A
	# planted paw's toe is support and may not be moved from here — what gives
	# instead is the *pastern preference*: the hock lifts, the wrist rotating
	# about the planted toe until the joint is back inside its own stop, spent
	# against the middle joint's spare fold. That is what a real trailing leg
	# does — the heel comes up long before the toe lets go — and it is why a
	# gait that holds a foot one beat too long gets a lifted hock rather than a
	# paw laid flat past its own tarsus. If the middle joint has no room left
	# either, the pose stands as near as it got and the tear-off upstream owns
	# the honesty a tick later.
	var shank: Vector2 = wrist - mid
	var paw: Vector2 = target - wrist
	if shank.length_squared() > 0.000001 and paw.length_squared() > 0.000001:
		var interior: float = PI - absf(wrapf(paw.angle() - shank.angle(), -PI, PI))
		var legal: float = clampf(interior, rom_low.x, rom_low.y)
		if absf(legal - interior) > 0.001:
			if not standing:
				var swing_dir: float = signf(wrapf(paw.angle() - shank.angle(), -PI, PI))
				target = wrist + paw.rotated(swing_dir * (interior - legal))
			else:
				for _fix in 3:
					var w: float = wrapf(paw.angle() - shank.angle(), -PI, PI)
					# As much of the lift as the middle joint's own annulus
					# will take — a full correction when there is room, half
					# and half again when the stops are crowding each other.
					var turn: float = -signf(w) * (interior - legal)
					var spun: Vector2 = wrist
					var d2: float = d
					var placed: bool = false
					for _sub in 4:
						spun = target + (wrist - target).rotated(turn)
						d2 = s.distance_to(spun)
						if d2 <= d_hi + 0.001 \
								and d2 >= maxf(d_lo, NEAR_MIN) - 0.001:
							placed = true
							break
						turn *= 0.5
					if not placed:
						break
					wrist = spun
					d = d2
					gamma = acos(clampf((u * u + d * d - l * l) / (2.0 * u * d),
						-1.0, 1.0))
					mid = s + (wrist - s).normalized().rotated(side * gamma) * u
					shank = wrist - mid
					paw = target - wrist
					interior = PI - absf(wrapf(paw.angle() - shank.angle(),
						-PI, PI))
					legal = clampf(interior, rom_low.x, rom_low.y)
					if absf(legal - interior) <= 0.001:
						break
				# Still illegal after everything the annulus allowed: the leg
				# has no pose left that holds both stops and the toe. Say so —
				# and hold the stop anyway, the paw folding to it about the
				# wrist with the toe arriving short, exactly as an
				# out-of-reach limb lays at its stops and arrives short. The
				# gait reads `cramped` and tears the anchor next tick; what it
				# may not read is a paw standing outside its own anatomy for
				# even the one tick in between.
				cramped = absf(legal - interior) > 0.01
				if cramped:
					var give: float = signf(wrapf(paw.angle() - shank.angle(),
						-PI, PI))
					target = wrist + paw.rotated(give * (interior - legal))

	var out := PackedVector2Array()
	out.resize(4)
	out[0] = s
	out[1] = mid
	out[2] = wrist
	out[3] = target
	return out


## The longest a limb can actually stand, at its own extension stops, as a
## share of its summed bones. Geometric straight is not anatomy: the stifle
## stops at 170° and the tarsus at 168°, so a hind leg's true maximum reach is
## a few percent short of its bone length — and an anchor held past it is an
## anchor the joints have already let go, whatever the ruler says. The gait's
## tear-off quotes this instead of a share of ideal length, which is what
## keeps a trailing paw's last legal pose exactly at the stops rather than
## laid flat beyond them.
func reach_share(fore: bool) -> float:
	var shares: PackedFloat32Array = spec.fore_leg_shares if fore \
		else spec.hind_leg_shares
	var total: float = shares[0] + shares[1] + shares[2]
	var mid_gap: float = PI - (_elbow.y if fore else _stifle.y)
	# The carpus hyperextends past geometric straight (245°): a gap below zero
	# is a paw that can lay fully along the reach.
	var low_gap: float = maxf(PI - (_carpus.y if fore else _tarsus.y), 0.0)
	return (shares[0] + shares[1] * cos(mid_gap)
		+ shares[2] * cos(mid_gap + low_gap)) / maxf(total, 0.0001)


## The middle joint's stops (elbow or stifle), radians of interior angle.
func mid_rom(fore: bool) -> Vector2:
	return _elbow if fore else _stifle


## The lower joint's stops (carpus or tarsus), radians of interior angle.
func low_rom(fore: bool) -> Vector2:
	return _carpus if fore else _tarsus


## What the two levers measure end to end at an interior angle.
static func _span(u: float, l: float, interior: float) -> float:
	return sqrt(maxf(u * u + l * l - 2.0 * u * l * cos(interior), 0.0))


## Full anatomical stretch toward an unreachable target: the middle joint at
## its own extension stop, the paw laid along the reach, the toe arriving
## short — which the gait's tear-off reads as the honesty it is. Never a
## straight rod: a real leg at full stretch is a leg at its stops.
static func _extended(s: Vector2, target: Vector2, u: float, l: float,
		p: float, d_hi: float, side: float) -> PackedVector2Array:
	var dir: Vector2 = (target - s)
	dir = dir.normalized() if dir.length_squared() > 0.000001 else Vector2.DOWN
	var gamma: float = acos(clampf((u * u + d_hi * d_hi - l * l)
		/ (2.0 * u * d_hi), -1.0, 1.0))
	var out := PackedVector2Array()
	out.resize(4)
	out[0] = s
	out[1] = s + dir.rotated(side * gamma) * u
	out[2] = s + dir * d_hi
	out[3] = out[2] + dir * p
	return out


## Both intersections of two circles, or nothing if they do not meet.
static func _circle_circle(c0: Vector2, r0: float, c1: Vector2,
		r1: float) -> Array:
	var span: Vector2 = c1 - c0
	var d: float = span.length()
	if d < 0.000001 or d > r0 + r1 or d < absf(r0 - r1):
		return []
	var a: float = (r0 * r0 - r1 * r1 + d * d) / (2.0 * d)
	var h: float = sqrt(maxf(r0 * r0 - a * a, 0.0))
	var m: Vector2 = c0 + span * (a / d)
	var n: Vector2 = Vector2(-span.y, span.x) / d
	return [m + n * h, m - n * h]


## The wrist candidate nearest where the paw wanted it, ties to the higher one
## — a hock pulls up under the body, it does not fold through the floor.
static func _pick(candidates: Array, prefer: Vector2) -> Vector2:
	var a: Vector2 = candidates[0]
	var b: Vector2 = candidates[1]
	var da: float = a.distance_squared_to(prefer)
	var db: float = b.distance_squared_to(prefer)
	if absf(da - db) < 0.01:
		return a if a.y >= b.y else b
	return a if da < db else b


## A profile resampled onto the built station count and scaled by the animal's
## own authored scalar against the reference cat's, radians out.
static func _profile(profile: Array[float], reference: float, authored: float,
		count: int) -> PackedFloat32Array:
	var shares: PackedFloat32Array = _resample(profile, count)
	var scale: float = authored / maxf(reference, 0.001)
	for i in shares.size():
		shares[i] = deg_to_rad(shares[i] * scale)
	return shares


static func _resample(profile: Array[float], count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(count, 1))
	if profile.is_empty():
		return out
	if profile.size() == 1 or out.size() == 1:
		out.fill(profile[0])
		return out
	for i in out.size():
		var t: float = float(i) / float(out.size() - 1) * float(profile.size() - 1)
		var j: int = clampi(int(t), 0, profile.size() - 2)
		out[i] = lerpf(profile[j], profile[j + 1], t - float(j))
	return out
