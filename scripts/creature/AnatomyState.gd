## The creature's anatomy, and what it is currently capable of.
##
## Three jobs, kept apart because they answer different questions:
##
##   * `hit_test()` asks *what did those jaws close on* — which creature, and
##     which anatomical structure of it — by querying the same procedural
##     primitives the view draws. The world uses it to pick a single target when
##     several bodies overlap one bite volume.
##   * `tissue` is the voxel-like lattice that then actually loses material, in
##     body-space cells that survive the pose being rebuilt each tick.
##   * `state` is what that surviving material adds up to: how strong each part of
##     the animal is, how well it is controlled, what it can carry. It is the only
##     thing the animation ever reads.
##
## The order is the architecture. Damage lands in cells; the cells are read as
## structures; the structures are read as capability; the animator reads
## capability. Nothing skips a step, and in particular nothing between a bite and
## a stride ever mentions the other.
##
## Damage is applied through the lattice by *position*, not through the region
## the hit test named: a hit region identifies a target, while a bite covers an
## area that can straddle several structures at once.
class_name AnatomyState
extends RefCounted

const HEAD: int = 0
const TORSO: int = 1
const LIMB: int = 2


class Hit extends RefCounted:
	var region_id: String = ""
	var kind: int = TORSO
	## Signed distance from the bite centre to the region's surface. The most
	## negative candidate is the deepest overlap and therefore wins.
	var score: float = INF
	var world_point: Vector2 = Vector2.ZERO

	# Body binding. HEAD uses both local coordinates; TORSO uses spine_t and
	# lateral, because spine_t already owns the longitudinal coordinate.
	var spine_t: float = 0.0
	var local_forward: float = 0.0
	var lateral: float = 0.0

	# Limb binding. Segment 0 = upper, 1 = lower, 2 = foot.
	var limb_key: String = ""
	var limb_segment: int = -1
	var limb_u: float = 0.0


## What kind of animal this is. Shared by the lattice that stores its tissue and
## the functional state that reads it, so the two can never describe different
## creatures.
var plan: BodyPlan = BodyPlan.new()
var tissue: TissueGrid = null
var state: BodyState = BodyState.new()


func _init() -> void:
	tissue = TissueGrid.new(plan)
	state.configure(plan)


func reset() -> void:
	tissue.reset()
	state.reset()


## Moves the girdles under wherever this species hangs its limbs, and rebuilds
## everything laid out against them.
##
## The pairing is the same one `set_fat_reserve` makes and for the same reason: a
## skeleton re-laid under a lattice that still has the old one's bone flags in it
## is an animal with two skeletons. So the plan answers whether anything moved,
## and only then is the tissue re-laid and the functional state read off it again.
## A slider that leaves the girdles where they were costs one integer comparison.
func set_girdles(front: float, rear: float) -> void:
	if not plan.set_girdles(front, rear):
		return
	tissue.rebuild_layout()
	state.configure(plan)
	state.reset()


## Re-lays this species' fat, and the functional state that was read off the old
## body with it.
##
## The pairing is the point. Re-laying fat restores the lattice, and a restored
## lattice with a stale functional state on top of it is a whole creature that is
## still bleeding out of wounds it no longer has. The two halves are one body and
## are put back together as one.
func set_fat_reserve(value: float) -> void:
	if is_equal_approx(tissue.fat_reserve, value):
		return
	tissue.set_fat_reserve(value)
	state.reset()


## Re-derives the lattice's world geometry from the pose solved this tick, what is
## still joined to what, and then what the body made of it can do. Must run after
## the body and limbs are rebuilt and before anything bites.
##
## The three are in that order and never any other. The functional state is read
## off tissue, and tissue whose corners are a tick stale is a body that was
## somewhere else. Connectivity sits between them because it is the one reading
## that is about the lattice as a whole rather than about any place on it, and
## because everything the functional layer says about a severed part is downstream
## of it — a limb cannot be told what it can still do before the body has worked
## out whether it is still there.
func update(creature: Node, delta: float = 0.0) -> void:
	tissue.update(creature)
	tissue.resolve_attachment()
	state.update(tissue, delta)


## Finds the anatomical region overlapped most deeply by a circular bite.
## Broad-phase creature selection can be added later; for the current small
## creature count this direct procedural query is both cheaper and more exact
## than rebuilding CollisionPolygon2D nodes every tick.
##
## `reach` is the height band the jaws can bring to bear, and every primitive
## below is tested against the band its own cells occupy rather than against one
## band for the whole animal. That distinction is the difference between "can I
## reach this creature's legs" and "can I reach *this part of this leg*": a low
## predator's jaws clear a tall animal's belly, meet the middle of its legs, and
## pass under the foot it has picked up, and all three answers come out of the
## same one-line test asked of three different pieces. The horizontal test is
## untouched by any of it — this is a second `and`, never a replacement.
func hit_test(creature: Node, bite_center: Vector2, bite_radius: float,
		reach: Vector2 = Stature.UNBOUNDED) -> Hit:
	if creature == null or creature.body == null or creature.spine == null or creature.gait == null:
		return null

	var best: Hit = null
	var body: BodyShape = creature.body
	var spine: Spine = creature.spine
	# One cheap rejection for the whole animal before any of the per-part work,
	# for the same reason the broad phase exists horizontally: something standing
	# entirely above or below these jaws is not worth walking.
	if not Volume.overlaps(reach, tissue.whole_band()):
		return null
	var reach_head: bool = Volume.overlaps(reach, tissue.head_band())

	# Every primitive below is narrowed to the tissue still standing on it, so
	# jaws closing on a place a previous bite already emptied find nothing there
	# and the strike reads as a miss. A structure eaten clean through drops out
	# of the query entirely rather than answering as a target with no substance.
	# Every candidate's score below is its *penetration*: how deep the jaw centre
	# stands inside the structure, negated. The plan view gives one reading of
	# that and the height band gives another — jaws overlapping a structure's
	# band by two pixels are two pixels into it however far past its outline the
	# picture puts them — and the honest depth is the lesser of the two, so each
	# score is floored at minus the band overlap. That single cap is what stops a
	# graze along the underside of a tall animal outranking the leg the same jaws
	# are closing around: the belly's plan-view capsule is enormous, and the two
	# pixels of band the jaws actually share with it now say so.
	# --- head: the same circle CreatureView draws --------------------------
	var head_radius: float = body.head_radius * tissue.head_solid()
	var head_delta: Vector2 = bite_center - body.head.pos
	var head_distance: float = head_delta.length()
	var head_score: float = maxf(head_distance - head_radius,
		-Volume.shared(reach, tissue.head_band()))
	if reach_head and head_radius > 0.0 and head_score <= bite_radius:
		var head_dir: Vector2 = head_delta / head_distance if head_distance > 0.0001 else body.head.fwd
		var head_hit := Hit.new()
		head_hit.region_id = "head"
		head_hit.kind = HEAD
		head_hit.score = head_score
		head_hit.world_point = body.head.pos + head_dir * minf(head_distance, head_radius)
		head_hit.local_forward = head_dir.dot(body.head.fwd)
		head_hit.lateral = head_dir.dot(body.head.perp)
		best = head_hit

	# --- torso: one variable-radius capsule per spine interval -------------
	# Start at interval 1 because interval 0 sits beneath the explicit head cap.
	var last: int = mini(body.last_index, spine.points.size() - 1)
	for i in range(1, last):
		var a: Vector2 = spine.points[i]
		var b: Vector2 = spine.points[i + 1]
		var u: float = segment_u(bite_center, a, b)
		var axis: Vector2 = a.lerp(b, u)
		var radial: Vector2 = bite_center - axis
		var along: float = (float(i) + u) / float(maxi(last, 1))
		# Per interval, because a trunk is not level: the neck rises to the head
		# over the front of it, so jaws that can reach a browsing animal's throat
		# genuinely cannot reach the back three segments behind it.
		var band: Vector2 = tissue.body_band(along)
		if not Volume.overlaps(reach, band):
			continue
		var solid: float = tissue.body_solid(along, radial.dot(spine.perps[i]))
		if solid <= 0.0:
			continue
		var tissue_radius: float = lerpf(body.widths[i], body.widths[i + 1], u) * solid
		var radial_distance: float = radial.length()
		var score: float = maxf(radial_distance - tissue_radius,
			-Volume.shared(reach, band))
		if score > bite_radius or (best != null and score >= best.score):
			continue

		var radial_dir: Vector2 = radial / radial_distance if radial_distance > 0.0001 else spine.perps[i]
		var torso_hit := Hit.new()
		torso_hit.region_id = "torso:%02d" % i
		torso_hit.kind = TORSO
		torso_hit.score = score
		torso_hit.spine_t = (float(i) + u) / float(maxi(spine.points.size() - 1, 1))
		# Where the jaws actually met flesh. From outside, that is the silhouette;
		# from *inside* the capsule — jaws under a tall animal's belly, which is a
		# place low jaws genuinely reach — it is the jaws' own position, because
		# the flesh there is directly overhead rather than out at the far flank.
		# Projecting outward regardless handed the grip an anchor most of a body
		# away from the mouth that bit, and the tether then measured itself
		# against a point nobody's teeth had touched.
		torso_hit.world_point = axis + radial_dir * minf(radial_distance, tissue_radius)
		var frame: Spine.Frame = spine.sample(torso_hit.spine_t)
		torso_hit.lateral = clampf((torso_hit.world_point - frame.pos).dot(frame.perp) / maxf(tissue_radius, 0.001), -1.0, 1.0)
		best = torso_hit

	# --- limbs: the two drawn bone capsules and circular foot --------------
	for limb in creature.gait.limbs:
		var widths: Vector2 = _limb_widths(limb, creature.size_scale)
		for segment in 2:
			# A leg is the one structure that spans the whole gap under an animal,
			# so asking about it as a whole throws away everything interesting: the
			# upper bone is up at the shoulder and the lower is down at the floor.
			# Asked per bone, low jaws take the shin of an animal whose hip they
			# could never have got near.
			var bone_band: Vector2 = tissue.limb_band(limb.key, segment)
			if not Volume.overlaps(reach, bone_band):
				continue
			var limb_solid: float = tissue.limb_solid(limb.key, segment)
			if limb_solid <= 0.0:
				continue
			var la: Vector2 = limb.joints[segment]
			var lb: Vector2 = limb.joints[segment + 1]
			var limb_u: float = segment_u(bite_center, la, lb)
			var limb_axis: Vector2 = la.lerp(lb, limb_u)
			var limb_radius: float = (widths.x if segment == 0 else widths.y) * 0.5 * limb_solid
			var limb_score: float = maxf(bite_center.distance_to(limb_axis) - limb_radius,
				-Volume.shared(reach, bone_band))
			if limb_score > bite_radius or (best != null and limb_score >= best.score):
				continue
			var limb_hit := Hit.new()
			limb_hit.region_id = "limb:%s:%s" % [limb.key, "upper" if segment == 0 else "lower"]
			limb_hit.kind = LIMB
			limb_hit.score = limb_score
			limb_hit.world_point = limb_axis
			limb_hit.limb_key = limb.key
			limb_hit.limb_segment = segment
			limb_hit.limb_u = limb_u
			best = limb_hit

		# The foot is its own band and it is the lowest thing on the animal: a foot
		# on the floor is reachable by anything that can reach the floor, and the
		# same foot at the top of a step is not reachable at all.
		var foot_band: Vector2 = tissue.limb_band(limb.key, 2)
		var foot_reached: bool = Volume.overlaps(reach, foot_band)
		var foot_radius: float = limb.foot_radius(creature.size_scale) \
			* tissue.limb_solid(limb.key, 2)
		var foot_score: float = maxf(bite_center.distance_to(limb.joints[2]) - foot_radius,
			-Volume.shared(reach, foot_band))
		if foot_reached and foot_radius > 0.0 and foot_score <= bite_radius \
				and (best == null or foot_score < best.score):
			var foot_hit := Hit.new()
			foot_hit.region_id = "limb:%s:foot" % limb.key
			foot_hit.kind = LIMB
			foot_hit.score = foot_score
			foot_hit.world_point = limb.joints[2]
			foot_hit.limb_key = limb.key
			foot_hit.limb_segment = 2
			foot_hit.limb_u = 1.0
			best = foot_hit

	return best


## Erodes every cell the bite mark covers, outside-in. Returns the tissue
## actually removed, and appends whatever broke off to `shed`.
##
## The mark carries how high the jaws that made it could reach, and every cell
## in the lattice knows what height it stands at, so the vertical gate resolves
## itself down there with no third party involved. It belongs at cell level
## rather than here because a bite covers an area and can straddle several
## structures at once — the same reason damage was already resolved by position
## instead of through the region the hit test named.
func apply_bite(mark: BiteMark, shed: Array) -> float:
	return tissue.bite(mark, shed)


## Where along `a`->`b` the closest point to `point` lies, clamped to the
## segment. Shared with Creature's body-contact query, which walks the same
## spine capsules this hit test does.
static func segment_u(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_squared: float = ab.length_squared()
	if length_squared < 0.000001:
		return 0.0
	return clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)


static func _limb_widths(limb: Limb, scale: float) -> Vector2:
	return Vector2(limb.segment_girth(0, scale), limb.segment_girth(1, scale))
