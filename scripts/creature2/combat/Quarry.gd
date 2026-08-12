## What the cursor has hold of — v1's `Reticle`, re-expressed against the one
## census.
##
## v1 picked among drawn primitives it had to reconstruct (a capsule per bone, a
## circle for the head, a band per structure) and then had to keep that
## reconstruction in step with both the painter and the hit test. v2 has neither
## problem: `Contour.locate_seen` reads the same posed rings the painter reads,
## in the same projection it paints them in, so what the pointer selects is what
## the pointer is looking at, by construction rather than by discipline. What is
## left for this file is the part that is genuinely about the world and not
## about any one body: **which** of the several things under one pixel was meant.
##
## Which is why it is two calls, exactly as v1's was. `pick` asks what is there
## and knows nothing about who is looking. `resolve` asks what would happen if
## that selection were acted on by *this* animal — whether the jaws can be got
## onto it, and where the mark has to stop when they cannot. Every caller that
## only wants to know what is under a pointer still gets exactly that.
##
## Nothing here refuses anything. A target out of reach comes back marked out of
## reach; the strike is still thrown, and what it meets is decided in the world.
class_name Quarry
extends RefCounted

## How much slack a cursor gets, px. A pointer is aimed by hand at a moving
## animal; demanding a pixel-exact landing on a shin would make the legs — the
## one thing a low predator can reach on a tall one — effectively unclickable.
const SLACK: float = 12.0

## How much of its own reach a marker brought in from beyond it is placed at.
## Just inside, so the point the player is offered is one the body then agrees
## it can get to rather than one sitting exactly on the boundary of the test.
const CLAMP_MARGIN: float = 0.99

## English for the four limb keys, so a readout names a leg the way a person
## would. Nothing branches on it.
const SIDES := {&"FL": "front left", &"FR": "front right",
	&"HL": "rear left", &"HR": "rear right"}


class Pick extends RefCounted:
	## "creature" or "ground". Carried for the readout; no caller has to branch
	## on it, because both kinds answer the same three questions below.
	var kind: String = "ground"
	## Which animal, and the body address on it — `Contour.locate_seen`'s
	## dictionary, which is the same address a bite wounds through.
	var creature: Creature2 = null
	var contact: Dictionary = {}
	## Where it is on the ground plane — where a mouth is sent — and where it is
	## in the picture, which is where a mark on it has to be drawn. The two
	## differ by exactly the height, which is the whole reason the pick is made
	## in the second one.
	var at: Vector2 = Vector2.ZERO
	var seen: Vector2 = Vector2.ZERO
	var height: float = 0.0
	## How squarely it was hit: negative inside the thing, positive short of it.
	## One currency across every kind, which is the only reason comparing them
	## means anything.
	var score: float = 0.0

	## What the cursor was actually on, when this marker had to be brought in to
	## the limit of the animal's reach. Null on a marker sitting on the thing
	## itself, which is every pick that has not been through `resolve`.
	##
	## Kept rather than discarded because the two are different facts and the
	## player needs both: *this* is as far as you get, and *that* is what you
	## were pointing at.
	var beyond: Pick = null

	## What was selected, whether or not the marker had to stop short of it.
	func selected() -> Pick:
		return beyond if beyond != null else self

	## The same, for a person: "rear left leg" rather than "limb HL". Read by the
	## on-screen readout, which is the one place this is shown to somebody who
	## has not read the source.
	func name_of() -> String:
		if creature == null or contact.is_empty():
			return kind
		var band: StringName = contact["band"]
		match band:
			BodySchema.TRUNK:
				# Which third of the back, rather than which station: the number
				# means nothing to anyone watching and the third means everything.
				var t: float = float(contact["t"])
				if t > 0.72:
					return "withers"
				return "hindquarters" if t < 0.35 else "flank"
			BodySchema.NECK:
				return "head" if float(contact["t"]) > 0.78 else "neck"
			BodySchema.TAIL:
				return "tail"
			_:
				return "%s leg" % SIDES.get(band, String(band))


## Resolves a cursor into one target.
##
## Every candidate is scored in the same currency — how far the cursor is past
## its drawn surface, negative when the cursor is inside it — and the deepest
## wins. Bare ground scores zero, so anything the pointer is genuinely on beats
## it and nothing else does.
##
## `ignore` is the creature doing the pointing: an animal aiming at something
## across the paddock should not keep selecting its own tail.
static func pick(tree: SceneTree, cursor: Vector2, actor: Creature2 = null,
		slack: float = SLACK) -> Pick:
	var best: Pick = _ground(cursor, actor)
	if tree == null:
		return best
	for node in tree.get_nodes_in_group("creatures2"):
		var candidate := node as Creature2
		if candidate == null or candidate == actor or candidate.contour == null:
			continue
		var found: Dictionary = candidate.contour.locate_seen(cursor)
		if found.is_empty():
			continue
		# The slack is what makes a leg clickable: it widens every drawn wedge by
		# the same handful of pixels, so a pointer near a shin has hold of the
		# shin and a pointer nowhere near anything still has hold of the floor.
		var score: float = -(float(found["depth"]) + slack)
		if score >= best.score:
			continue
		var flesh: Vector3 = found["at"]
		best = Pick.new()
		best.kind = "creature"
		best.creature = candidate
		best.contact = found
		best.at = Vector2(flesh.x, flesh.y)
		best.seen = found["seen"]
		best.height = flesh.z
		best.score = score
	return best


## The same pick, answered for the animal about to act on it: can these jaws be
## got onto that, and if they cannot get that far, how far do they get?
##
## Only the horizontal refusal is a distance along the aim line, so only it can
## be answered by moving along one. Something directly overhead is not nearer
## for being approached, and the honest answer there is the marker staying on it
## and reading as out of reach.
static func resolve(found: Pick, actor: Creature2) -> Pick:
	if found == null or actor == null or actor.maw == null:
		return found
	if found.creature != null:
		var reach: Dictionary = actor.maw.aim(found.creature, found.at)
		if bool(reach.get("ok", false)) or String(reach.get("why", "")) != "far":
			return found
		return _short_of(found, actor)
	# Bare ground is asked the same question by the same purse — a place on the
	# floor inside the arc is a place the mouth can be put, and one beyond it is
	# a lunge in that direction that lands short.
	var root: Vector2 = actor.armature.plan(actor.armature.withers_index())
	if root.distance_to(found.at) <= actor.maw.plan_reach(found.height):
		return found
	return _short_of(found, actor)


## The furthest place along the aim line this animal can put its mouth.
##
## Not a refusal and not a nudge: it is the honest answer to "you have pointed
## past what you can reach", which is that the action happens toward the target
## and lands short of it. The point is on the floor because that is what is out
## there — the thing selected is somewhere else — and it carries the height of
## whatever the ground is doing at that distance, so an animal told to strike at
## a rise strikes at the rise rather than at the plane under it.
##
## The arc it is placed on is the maw's own purse, centred where the purse is
## centred (the withers the neck pivots on) rather than at the mouth, so the
## place the player is offered and the place the strike agrees to go are read
## off one number.
static func _short_of(found: Pick, actor: Creature2) -> Pick:
	var a: Armature = actor.armature
	var root: Vector2 = a.plan(a.withers_index())
	var toward: Vector2 = found.at - root
	if toward.length_squared() < 0.0001:
		return found
	var ground: float = actor.ground_at(found.at)
	var limit: Pick = _ground(root + toward.normalized()
		* (actor.maw.plan_reach(ground) * CLAMP_MARGIN), actor)
	limit.beyond = found
	return limit


## The floor, which is what a cursor is pointing at when it is pointing at
## nothing. A real answer rather than a null: clicking bare ground is how an
## animal is told to put its mouth down there, and the ground has a height like
## everything else.
static func _ground(cursor: Vector2, actor: Creature2) -> Pick:
	var found := Pick.new()
	found.kind = "ground"
	found.at = cursor
	found.height = actor.ground_at(cursor) if actor != null else 0.0
	found.seen = Contour.seen(Vector3(cursor.x, cursor.y, found.height))
	# Beaten by anything the cursor is genuinely inside, and by nothing else.
	found.score = 0.0
	return found
