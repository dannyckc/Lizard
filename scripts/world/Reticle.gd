## What the cursor is pointing at — including, for the first time, how high up it
## is and which piece of which animal it belongs to.
##
## A mouse gives two numbers and the world has three, so a click is ambiguous
## before anything resolves it: the pixel under the pointer is on the ground
## plane, on a rock standing on that ground, on the shoulder of an animal walking
## past, and on the belly of a taller one behind it, all at once. Something has to
## choose, and the choice cannot be made on the ground plane — that is precisely
## the axis that has been collapsed.
##
## So it is made in the picture. Everything in this game is drawn through one
## projection, `Posture.drop`, which carries a thing up the screen by however high
## it is; a cursor is a point in that projection, so the thing it is pointing at
## is whichever drawn primitive it lands on. Pick there and the height comes back
## for free: it is the height of whatever was hit. A click on the top face of a
## boulder answers with the top of the boulder, a click at its foot answers with
## the floor, and a click on an elephant's shoulder answers with the shoulder —
## not with the patch of ground a hundred pixels away that the shoulder happens
## to be drawn over.
##
## What comes back is one `Pick`, and it is deliberately the same shape whatever
## was found: a place on the ground plane, a height, a band, and — when the thing
## has anatomy — the exact structure of the exact creature, taken straight from
## the hit test that a bite would use. That last part is what makes damage land
## where it was aimed rather than merely near it, because the two questions are
## answered by one function.
class_name Reticle
extends RefCounted

## How much slack a cursor gets. A pointer is aimed by hand at a moving animal;
## demanding a pixel-exact landing on a shin would make the legs — the one thing
## a low predator can reach on a tall one — effectively unclickable.
const SLACK: float = 12.0

## How much of its own reach a marker brought in from beyond it is placed at.
## Just inside, so the point the player is offered is one the body then agrees it
## can get to rather than one sitting exactly on the boundary of the test.
const CLAMP_MARGIN: float = 0.99

## English for the four limb keys, so the readout names a leg the way a person
## would. Nothing branches on it.
const SIDES := {"FL": "front left", "FR": "front right",
	"RL": "rear left", "RR": "rear right"}
const BONES: Array[String] = ["upper", "lower", "foot"]


class Pick extends RefCounted:
	## "creature", "obstacle", "carrion", "forage" or "ground". Carried for the
	## HUD and for test failures; the caller never has to branch on it, because
	## every kind answers the same three questions below.
	var kind: String = "ground"
	## Where it is on the ground plane — what a foot would walk to and what a
	## bite's footprint is measured from.
	var at: Vector2 = Vector2.ZERO
	## Where it was found in the picture. The two differ by exactly the height,
	## which is the whole reason the pick is made in the second one.
	var drawn: Vector2 = Vector2.ZERO
	## How high up it is, and the band it fills. A mouth is asked to overlap the
	## band rather than to arrive at the height, because nothing is infinitely
	## thin and jaws close on a thickness.
	var height: float = 0.0
	var band: Vector2 = Vector2.ZERO
	## How squarely it was hit: negative inside the thing, positive short of it.
	## The same currency `AnatomyState.Hit` scores in, so the comparison across
	## kinds means something.
	var score: float = INF

	## Whichever of these the pick found. All null on open ground.
	var creature: Node = null
	var hit: AnatomyState.Hit = null
	var obstacle: Obstacle = null
	var part: CarrionField.Part = null

	## What the cursor was actually on, when this marker had to be brought in to
	## the limit of the animal's reach. Null on a marker sitting on the thing
	## itself, which is every pick that has not been through `resolve`.
	##
	## Kept rather than discarded because the two are different facts and the
	## player needs both: *this* is as far as you get, and *that* is what you were
	## pointing at. The drawing joins them with a line.
	var beyond: Pick = null

	## What was actually picked, in words. "limb:FL:foot" rather than "a creature",
	## because which part it is, is the point.
	func region() -> String:
		if hit != null:
			return hit.region_id
		if obstacle != null:
			return obstacle.kind
		return kind

	## The same, for a person: "front left foot" rather than "limb:FL:foot". Read
	## by the on-screen readout, which is the one place the region is shown to
	## somebody who has not read the source.
	func name_of() -> String:
		if hit == null:
			return obstacle.kind if obstacle != null else kind
		match hit.kind:
			AnatomyState.HEAD:
				return "head"
			AnatomyState.LIMB:
				var bone: String = BONES[clampi(hit.limb_segment, 0, 2)]
				var leg: String = SIDES.get(hit.limb_key, hit.limb_key)
				return "%s %s" % [leg, "foot" if bone == "foot" else "%s leg" % bone]
			_:
				# Where along the back, rather than which spine interval: the number
				# means nothing to anyone watching and the third of the animal it
				# lands in means everything.
				if hit.spine_t < 0.25:
					return "neck"
				return "flank" if hit.spine_t < 0.62 else "hindquarters"

	## What the cursor selected, whether or not the marker had to stop short of it.
	func selected() -> Pick:
		return beyond if beyond != null else self

	func describe() -> String:
		return "%s %s at %s" % [kind, region(), Volume.describe(band)]


## Resolves a cursor into one target.
##
## Every candidate is scored in the same currency — signed distance from the
## cursor to its drawn surface, negative when the cursor is inside it — and the
## deepest wins. That is the same rule `AnatomyState.hit_test` uses to choose
## between the structures of one animal, applied one level up to choose between
## the animals, the terrain and the meat; using one rule throughout is the only
## reason a shin can beat a boulder or lose to one on the merits.
##
## `ignore` is normally the creature doing the pointing: an animal aiming at
## something across the world should not keep selecting its own tail.
static func pick(tree: SceneTree, cursor: Vector2, radius: float = SLACK,
		ignore: Node = null) -> Pick:
	var best: Pick = _ground(cursor)
	if tree == null:
		return best

	for node in tree.get_nodes_in_group("creatures"):
		var candidate := node as Creature
		if candidate == null or candidate == ignore or candidate.anatomy == null:
			continue
		var found: Pick = _on_creature(candidate, cursor, radius)
		if found != null and found.score < best.score:
			best = found

	for node in tree.get_nodes_in_group("terrain"):
		var terrain := node as Terrain
		if terrain == null:
			continue
		var obstacle: Obstacle = terrain.pick(cursor, radius)
		if obstacle == null:
			continue
		var found := Pick.new()
		found.kind = "obstacle"
		found.obstacle = obstacle
		found.height = terrain.height_under(obstacle, cursor)
		found.at = obstacle.at
		found.drawn = obstacle.drawn(found.height)
		# The whole object rather than the point on it, because that is what a
		# mouth or a foot meets: a rock is solid from its base to its top and a
		# bite anywhere on the side of it lands on the same rock.
		found.band = obstacle.band
		found.score = cursor.distance_to(found.drawn) - obstacle.girth()
		if found.score < best.score:
			best = found

	for node in tree.get_nodes_in_group("carrion"):
		var carrion := node as CarrionField
		if carrion == null:
			continue
		var meat: CarrionField.Part = carrion.reach_of(cursor, radius)
		if meat == null:
			continue
		var found := Pick.new()
		found.kind = "carrion"
		found.part = meat
		found.at = meat.pos
		found.drawn = meat.pos
		found.band = Volume.ground()
		found.height = found.band.y * 0.5
		# Meat lying on the floor is scored by how deeply the cursor is into it,
		# which is what the field already reports and what the bite resolver
		# already compares against an anatomy hit.
		found.score = -carrion.depth_into(meat, cursor)
		if found.score < best.score:
			best = found

	for node in tree.get_nodes_in_group("forage"):
		var field := node as FoodField
		if field == null:
			continue
		var found: Pick = _on_forage(field, cursor, radius)
		if found != null and found.score < best.score:
			best = found

	return best


## The same pick, answered for the animal that is about to act on it.
##
## `pick` asks what is *there*, and deliberately knows nothing about who is
## looking: it is a question about the world. This is the second half of it — what
## would actually happen if that selection were acted on now — and it is a
## question about one body, which is why the two are separate calls and why every
## caller that only wants to know what is under a pointer still gets exactly what
## it always got.
##
## Two things change, and both of them are the marker being moved to somewhere
## truer than the pixel the cursor is on:
##
##   * onto the place the jaws will meet. A cursor lands on a silhouette; a mouth
##     arrives at a surface, on the near side of the thing, at whatever height in
##     its band the neck and the fold can bring the teeth to. Those are different
##     points on a deep-chested animal and the difference is most of a body — see
##     `_meet`.
##   * in to arm's length, when the selection is past it. The furthest place along
##     the aim line the animal can put its mouth, so a click aimed across the
##     paddock is a lunge in that direction rather than an input that does
##     nothing — see `_short_of`. What was selected is kept on `beyond`, because
##     "this is as far as you get" is only legible next to what was wanted.
##
## Nothing here refuses anything. A marker that could not be brought onto its
## target — too high, too low, behind a rock — comes back untouched and out of
## reach, which the drawing shows and the strike ignores.
static func resolve(found: Pick, actor: Creature) -> Pick:
	if found == null or actor == null or actor.body == null or actor.stature == null:
		return found
	var mouth: Vector2 = actor.jaw_point()
	_meet(found, actor, mouth)
	# Only the horizontal refusal is a distance along the aim line, so only it can
	# be answered by moving along one. Something directly overhead is not nearer
	# for being approached, and the honest answer there is the marker staying on
	# it and reading as unreachable.
	var reach: Reach = Reach.solve(actor, found.at, found.band, actor.terrain())
	if reach.possible or reach.refusal != "too far":
		return found
	return _short_of(found, actor, mouth)


## Moves a marker off the drawn silhouette and onto the place a mouth would
## actually close.
##
## Three corrections, and each of them is a fact the cursor cannot carry:
##
##   * the *side*. A pointer past the axis of a body selects the far flank, and a
##     bite does not arrive there — it arrives on the surface facing the animal
##     taking it. So the longitudinal station the player picked is kept, exactly
##     as picked, and only the way round the cross-section is decided here.
##   * the *height*. Which is what a mouth reaches on a band rather than the
##     middle of it — `Reach.meeting`, the same reading the reach test uses, so a
##     ring drawn at the top of a flank means the jaws are meeting the top of the
##     flank.
##   * and the *picture*, which follows from the other two through the one
##     projection everything in the game is drawn with.
##
## Things lying on the floor are left alone. A scrap, a pellet and bare earth are
## already at the height they are drawn at, and nudging them would put the marker
## somewhere other than under the cursor for no gain.
static func _meet(found: Pick, actor: Creature, mouth: Vector2) -> void:
	if found.obstacle != null:
		# A rock is met on its near side rather than at its middle, and the same
		# rule reads its height: jaws that clear the top are at the top, and jaws
		# that do not are on the face of it.
		found.height = Reach.meeting(actor, found.band)
		found.at = found.obstacle.at + _toward(mouth, found.obstacle.at) * found.obstacle.girth()
		found.drawn = found.at + Posture.drop(found.height, 0.0)
		return
	var target := found.creature as Creature
	if target == null or found.hit == null or target.body == null:
		return
	found.height = Reach.meeting(actor, found.band)
	match found.hit.kind:
		AnatomyState.HEAD:
			var skull: float = target.body.head_radius * target.anatomy.tissue.head_solid()
			found.at = target.body.head.pos + _toward(mouth, target.body.head.pos) * skull
		AnatomyState.LIMB:
			# Already the truest point on the animal: a leg is thin enough to have
			# no near side worth speaking of, and `pick` has put this one where the
			# limb *stands* rather than where it is drawn, which is the whole
			# correction being made everywhere else here.
			pass
		_:
			# The flank facing the mouth, at the station the cursor chose. `body_point`
			# is the same body-space reconstruction a grip is held by, so the marker
			# and the hold land on one surface.
			var frame: Spine.Frame = target.spine.sample(found.hit.spine_t)
			var side: float = signf((mouth - frame.pos).dot(frame.perp))
			found.at = target.body_point(Vector2(found.hit.spine_t,
				side if not is_zero_approx(side) else found.hit.lateral))
	found.drawn = found.at + Posture.drop(found.height, target.stature.reference)


## The furthest place along the aim line this animal can put its mouth.
##
## Not a refusal and not a nudge: it is the honest answer to "you have pointed
## past what you can reach", which is that the action happens toward the target
## and lands short of it. The point is on the floor because that is what is out
## there — the thing selected is somewhere else — and it carries the height of
## whatever the ground is doing at that distance, so an animal told to strike at
## a rise strikes at the rise rather than at the plane under it.
static func _short_of(found: Pick, actor: Creature, mouth: Vector2) -> Pick:
	var direction: Vector2 = _toward(found.at, mouth)
	# The arm onto the *floor*, not the level-ground span: the point being
	# offered is down there, and sweeping the mouth down to it costs the neck
	# part of its plan reach — Reach charges the strike the same way, and the two
	# have to agree or the marker would offer a place the body then declines.
	var limit: Pick = _ground(mouth + direction
		* (Reach.span_onto(actor, Volume.ground()) * CLAMP_MARGIN))
	var terrain: Terrain = actor.terrain()
	if terrain != null:
		limit.height = terrain.surface(limit.at, 0.0).x
		limit.band = Volume.lift(Volume.ground(), limit.height)
		limit.drawn = limit.at + Posture.drop(limit.height, 0.0)
	limit.beyond = found
	return limit


## The unit vector from `at` to `to`, or a stable fallback when they coincide.
static func _toward(to: Vector2, at: Vector2) -> Vector2:
	var delta: Vector2 = to - at
	return delta.normalized() if delta.length_squared() > 0.0001 else Vector2.RIGHT


## The exact structure of one animal under the cursor, and the band its own cells
## occupy.
##
## The hit test is the bite's, run unbounded — the question here is what is
## *there*, not what could be reached, and keeping those two apart is what lets
## the caller say "you have selected the foot, and you cannot reach it" rather
## than silently selecting something else instead.
static func _on_creature(creature: Creature, cursor: Vector2, radius: float) -> Pick:
	var hit: AnatomyState.Hit = creature.anatomy.hit_test(creature, cursor, radius)
	# ...and then the picture's own depth order laid over it, which is the one
	# thing the bite's hit test has no reason to know about and a cursor cannot do
	# without.
	#
	# The two are asking different questions. A bite happens in the world and takes
	# whatever its jaws are deepest into; a cursor happens on the screen and takes
	# whatever is drawn in front. Those disagree in exactly one place and it is a
	# place that matters: a limb hangs *below* the body it is attached to, so it is
	# drawn nearer the viewer, and on a deep-chested animal its whole length falls
	# inside the drawn silhouette of the torso. Scored by depth alone the torso
	# wins every time, and the legs — the one part of a tall animal a low predator
	# can reach — become unclickable.
	var leg: AnatomyState.Hit = _limb_in_front(creature, cursor)
	if leg != null:
		hit = leg
	if hit == null:
		return null
	var tissue: TissueGrid = creature.anatomy.tissue
	var found := Pick.new()
	found.kind = "creature"
	found.creature = creature
	found.hit = hit
	found.score = hit.score
	found.drawn = hit.world_point
	found.at = hit.world_point
	match hit.kind:
		AnatomyState.HEAD:
			found.band = tissue.head_band()
		AnatomyState.LIMB:
			found.band = tissue.limb_band(hit.limb_key, hit.limb_segment)
			# A limb is the one structure drawn somewhere other than where it is:
			# its bones hang below the body in the picture and stand underneath it
			# on the ground. So the plan position comes off the limb's own ground-
			# plane chain rather than off the drawn point the cursor landed on, or
			# a bite aimed at a foot would be thrown at the floor beneath the belly.
			var limb: Limb = creature._limb_by_key(hit.limb_key)
			if limb != null:
				var span: int = mini(hit.limb_segment + 1, 2)
				found.at = limb.plan[hit.limb_segment].lerp(limb.plan[span], hit.limb_u)
		_:
			found.band = tissue.body_band(hit.spine_t)
	found.height = (found.band.x + found.band.y) * 0.5
	return found


## The limb the cursor is genuinely inside, or null.
##
## Genuinely inside — not merely near — because that is what "drawn in front"
## licenses. A pointer somewhere in the neighbourhood of a leg has no claim on it
## over the flank behind it, and the ordinary depth score is the right answer
## there; a pointer on the leg itself is pointing at the leg, whatever is drawn
## behind it. So there is no slack here, and the only limbs it can return are the
## ones the pointer is actually over.
##
## Off the drawn chain, because the whole point is where the limb is in the
## picture. What comes back is the same `Hit` the bite would produce, bound the
## same way — so a click and a bite on the same leg name the same structure of the
## same animal, which is what makes damage land where it was aimed.
static func _limb_in_front(creature: Creature, cursor: Vector2) -> AnatomyState.Hit:
	if creature.gait == null:
		return null
	var tissue: TissueGrid = creature.anatomy.tissue
	var best: AnatomyState.Hit = null
	for limb in creature.gait.limbs:
		if limb.severed:
			continue
		for segment in 3:
			var solid: float = tissue.limb_solid(limb.key, segment)
			if solid <= 0.0:
				continue
			var a: Vector2 = limb.joints[segment]
			var b: Vector2 = limb.joints[mini(segment + 1, 2)]
			var thickness: float = limb.foot_radius(creature.size_scale) if segment == 2 \
				else limb.segment_girth(segment, creature.size_scale) * 0.5
			var u: float = AnatomyState.segment_u(cursor, a, b)
			var score: float = cursor.distance_to(a.lerp(b, u)) - thickness * solid
			if score > 0.0 or (best != null and score >= best.score):
				continue
			best = AnatomyState.Hit.new()
			best.region_id = "limb:%s:%s" % [limb.key, BONES[segment]]
			best.kind = AnatomyState.LIMB
			best.score = score
			best.world_point = a.lerp(b, u)
			best.limb_key = limb.key
			best.limb_segment = segment
			best.limb_u = 1.0 if segment == 2 else u
	return best


static func _on_forage(field: FoodField, cursor: Vector2, radius: float) -> Pick:
	var best: Pick = null
	for i in field.pellets.size():
		var at: Vector2 = field.pellets[i]
		var height: float = field.heights[i] if i < field.heights.size() else 0.0
		var drawn: Vector2 = at + Posture.drop(height, 0.0)
		var score: float = cursor.distance_to(drawn) - radius
		if score > 0.0 or (best != null and score >= best.score):
			continue
		best = Pick.new()
		best.kind = "forage"
		best.at = at
		best.drawn = drawn
		best.height = height
		best.band = Vector2(height, height + FoodField.PELLET_THICKNESS)
		best.score = score
	return best


## The floor, which is what a cursor is pointing at when it is pointing at
## nothing. A real answer rather than a null: clicking bare ground is how an
## animal is told to put its mouth down there, and the ground has a height and a
## thickness like everything else.
static func _ground(cursor: Vector2) -> Pick:
	var found := Pick.new()
	found.kind = "ground"
	found.at = cursor
	found.drawn = cursor
	found.band = Volume.ground()
	found.height = 0.0
	# Beaten by anything the cursor is genuinely inside, and by nothing else.
	found.score = 0.0
	return found
