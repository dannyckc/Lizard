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

	## Whether the cursor has left the bite zone — outside the arc's sweep, past
	## its radius, or above or below the band the mouth can be carried through.
	##
	## Set by `resolve` and by nothing else, and it is the *only* thing that
	## survives being out there: the target itself is dropped on the spot (see
	## `_outside`), so nothing downstream is holding a body it has been told the
	## jaws cannot get to. What is left is a position and this flag, which is
	## exactly enough for the mark to say "not from here" and no more.
	var outside: bool = false

	## The same, for a person: "rear left leg" rather than "limb HL". Read by the
	## on-screen readout, which is the one place this is shown to somebody who
	## has not read the source.
	func name_of() -> String:
		if creature == null or contact.is_empty():
			return "out of reach" if outside else kind
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


## The same pick, answered for the animal about to act on it: are these jaws
## something that can be got onto that at all?
##
## One question with one answer, and the answer is the bite zone — `Maw.window`
## for the sweep and `Maw.plan_reach` for the radius, which is the same pair the
## arc on screen is drawn from. Inside it the pick stands; outside it the pick is
## stripped down to a position and a refusal.
##
## Dropping the target rather than keeping it is the point, and it is a reversal
## of what this used to do. It used to bring the marker in to the edge of the
## purse and keep what had been pointed at hanging off it on a dotted line — the
## correct *fact* ("that is what you wanted, this is as far as you get") offered
## as a target the player then had every reason to think was selected. It was
## not: the strike does not go to that flesh, the highlight was tracing a body
## the jaws could not touch, and the line between the two was the game showing a
## relationship it had no intention of honouring. A target you cannot bite is not
## a target. It goes.
static func resolve(found: Pick, actor: Creature2) -> Pick:
	if found == null or actor == null or actor.maw == null:
		return found
	if found.creature != null:
		# Asked of the flesh that was picked, address and all — the same question
		# the click will ask, so the mark cannot promise a surface the strike then
		# declines to address.
		if bool(actor.maw.aim(found.creature, found.at, found.contact)
				.get("ok", false)):
			return found
		return _outside(found)
	# Bare ground is asked the same question by the same zone — a place on the
	# floor inside the arc is a place the mouth can be put.
	var toward: Vector2 = found.at - actor.maw.purse_root()
	if toward.length() <= actor.maw.plan_reach(found.height) \
			and (toward.length() <= 0.5 or actor.maw.addressable(toward.angle())):
		return found
	return _outside(found)


## The same place, with the target taken off it.
##
## Left exactly where the cursor is rather than snapped anywhere: the player is
## pointing at a spot, and the honest thing to say about that spot is that it is
## out of the animal's reach — said *there*, on the thing they are pointing at,
## rather than by a marker that has wandered off somewhere else. What is gone is
## the selection: no body, no address on it, so no highlight traced round flesh
## that cannot be bitten and nothing for a line to be drawn to.
static func _outside(found: Pick) -> Pick:
	var bare := Pick.new()
	bare.kind = found.kind
	bare.at = found.at
	bare.seen = found.seen
	bare.height = found.height
	bare.outside = true
	return bare


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
