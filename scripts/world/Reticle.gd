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

	## What was actually picked, in words. "limb:FL:foot" rather than "a creature",
	## because which part it is, is the point.
	func region() -> String:
		if hit != null:
			return hit.region_id
		if obstacle != null:
			return obstacle.kind
		return kind

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
		var girth: float = limb.girth(creature.size_scale)
		for segment in 3:
			var solid: float = tissue.limb_solid(limb.key, segment)
			if solid <= 0.0:
				continue
			var a: Vector2 = limb.joints[segment]
			var b: Vector2 = limb.joints[mini(segment + 1, 2)]
			var thickness: float = limb.foot_radius(creature.size_scale) if segment == 2 \
				else girth * (0.5 if segment == 0 else 0.36)
			var u: float = AnatomyState.segment_u(cursor, a, b)
			var score: float = cursor.distance_to(a.lerp(b, u)) - thickness * solid
			if score > 0.0 or (best != null and score >= best.score):
				continue
			best = AnatomyState.Hit.new()
			best.region_id = "limb:%s:%s" % [limb.key,
				["upper", "lower", "foot"][segment]]
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
