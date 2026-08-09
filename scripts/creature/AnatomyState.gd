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
## `reach` is the height band the jaws can bring to bear. A structure is a
## candidate only if what it occupies vertically overlaps that — and because the
## three kinds of structure stand at three different heights, the gate answers
## the interesting question by itself: a low predator's reach clears a tall
## animal's legs and not its body, so the legs are all the query can return. The
## horizontal test below is untouched by any of it.
func hit_test(creature: Node, bite_center: Vector2, bite_radius: float,
		reach: Vector2 = Stature.UNBOUNDED) -> Hit:
	if creature == null or creature.body == null or creature.spine == null or creature.gait == null:
		return null

	var best: Hit = null
	var body: BodyShape = creature.body
	var spine: Spine = creature.spine
	var stature: Stature = creature.stature
	var reach_head: bool = stature == null or Stature.overlaps(reach, stature.head)
	var reach_torso: bool = stature == null or Stature.overlaps(reach, stature.torso)
	var reach_limbs: bool = stature == null or Stature.overlaps(reach, stature.limbs)

	# Every primitive below is narrowed to the tissue still standing on it, so
	# jaws closing on a place a previous bite already emptied find nothing there
	# and the strike reads as a miss. A structure eaten clean through drops out
	# of the query entirely rather than answering as a target with no substance.
	# --- head: the same circle CreatureView draws --------------------------
	var head_radius: float = body.head_radius * tissue.head_solid()
	var head_delta: Vector2 = bite_center - body.head.pos
	var head_distance: float = head_delta.length()
	var head_score: float = head_distance - head_radius
	if reach_head and head_radius > 0.0 and head_score <= bite_radius:
		var head_dir: Vector2 = head_delta / head_distance if head_distance > 0.0001 else body.head.fwd
		var head_hit := Hit.new()
		head_hit.region_id = "head"
		head_hit.kind = HEAD
		head_hit.score = head_score
		head_hit.world_point = body.head.pos + head_dir * head_radius
		head_hit.local_forward = head_dir.dot(body.head.fwd)
		head_hit.lateral = head_dir.dot(body.head.perp)
		best = head_hit

	# --- torso: one variable-radius capsule per spine interval -------------
	# Start at interval 1 because interval 0 sits beneath the explicit head cap.
	var last: int = mini(body.last_index, spine.points.size() - 1)
	for i in range(1, last if reach_torso else 1):
		var a: Vector2 = spine.points[i]
		var b: Vector2 = spine.points[i + 1]
		var u: float = segment_u(bite_center, a, b)
		var axis: Vector2 = a.lerp(b, u)
		var radial: Vector2 = bite_center - axis
		var solid: float = tissue.body_solid(
			(float(i) + u) / float(maxi(last, 1)), radial.dot(spine.perps[i]))
		if solid <= 0.0:
			continue
		var tissue_radius: float = lerpf(body.widths[i], body.widths[i + 1], u) * solid
		var radial_distance: float = radial.length()
		var score: float = radial_distance - tissue_radius
		if score > bite_radius or (best != null and score >= best.score):
			continue

		var radial_dir: Vector2 = radial / radial_distance if radial_distance > 0.0001 else spine.perps[i]
		var torso_hit := Hit.new()
		torso_hit.region_id = "torso:%02d" % i
		torso_hit.kind = TORSO
		torso_hit.score = score
		torso_hit.spine_t = (float(i) + u) / float(maxi(spine.points.size() - 1, 1))
		torso_hit.world_point = axis + radial_dir * tissue_radius
		var frame: Spine.Frame = spine.sample(torso_hit.spine_t)
		torso_hit.lateral = clampf((torso_hit.world_point - frame.pos).dot(frame.perp) / maxf(tissue_radius, 0.001), -1.0, 1.0)
		best = torso_hit

	# --- limbs: the two drawn bone capsules and circular foot --------------
	if not reach_limbs:
		return best
	for limb in creature.gait.limbs:
		var widths: Vector2 = _limb_widths(limb, creature.size_scale)
		for segment in 2:
			var limb_solid: float = tissue.limb_solid(limb.key, segment)
			if limb_solid <= 0.0:
				continue
			var la: Vector2 = limb.joints[segment]
			var lb: Vector2 = limb.joints[segment + 1]
			var limb_u: float = segment_u(bite_center, la, lb)
			var limb_axis: Vector2 = la.lerp(lb, limb_u)
			var limb_radius: float = (widths.x if segment == 0 else widths.y) * 0.5 * limb_solid
			var limb_score: float = bite_center.distance_to(limb_axis) - limb_radius
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

		var foot_radius: float = limb.foot_radius(creature.size_scale) \
			* tissue.limb_solid(limb.key, 2)
		var foot_score: float = bite_center.distance_to(limb.joints[2]) - foot_radius
		if foot_radius > 0.0 and foot_score <= bite_radius and (best == null or foot_score < best.score):
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
## `stature` is this body's own heights, so the lattice can refuse cells the
## jaws never reached. The gate belongs down there rather than here because a
## bite covers an area and can straddle several structures at once — the same
## reason damage was already resolved by position instead of through the region
## the hit test named.
func apply_bite(mark: BiteMark, shed: Array, stature: Stature = null) -> float:
	return tissue.bite(mark, shed, stature)


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
	var upper: float = limb.girth(scale)
	return Vector2(upper, upper * 0.72)
