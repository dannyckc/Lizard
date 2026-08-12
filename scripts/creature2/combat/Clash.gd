## Two bodies pressing on each other — creature–creature contact (§9.1).
##
## Capsule against capsule on posed sticks: every stick of the armature,
## wrapped at the flesh radius the census baked onto its nodes, against every
## stick of the other body — ~28 capsules a creature, behind a broad phase, so
## most pairs never measure anything (the v1 lesson: bound the overlap first —
## and with the polar census there is not one cell lookup behind any of it).
##
## The measurement is fully 2.5D: capsule distance is taken in all three
## dimensions off the posed nodes, so two trunks meet at their real heights —
## a leaping body sails over the carcass a walking one is pressed around, a
## raised head passes over a low back, and nothing anywhere compares flat
## silhouettes. The *response* is plan-dominant, as every v2 correction is:
## the push out is horizontal, because the vertical belongs to the carries and
## the fall.
##
## Nothing here is a second physics. An intrusion changes the state through
## the same seams a wall uses — the armature is shifted whole (feet not moved:
## the support drift is how the legs learn), the velocity into the other body
## dies through `deflect` while the slide keeps, and the impact that died is
## handed to the other body as the shove it physically was. A charge is
## nothing special: a fast body arriving is a deep intrusion with a large
## velocity to lose, and both animals stagger by exactly their shares of it.
##
## Softness is a material property, not a dynamics (§7.5): the correction is
## scaled by the compliance of the flesh actually touched, so a fat flank
## *gives* — resolves over a few ticks, denting meanwhile — where bone on
## bone resolves at once.
##
## Each creature presses itself off the others on its own tick and takes only
## its own mass share of the separation, so a pair resolves symmetrically
## without anyone owning both bodies, and a probe ticking one creature by hand
## gets honest contact against a world it did not tick.
class_name Clash
extends RefCounted

## Broad-phase slack past the two bodies' half-lengths, px.
const REACH_MARGIN: float = 24.0

## How much of its correction a contact with compliance zero takes per tick.
## The compliance divides into it: fat spreads the push over more ticks.
const STIFF: float = 0.85

## The most turn rate a glancing press may put into a body in one tick, rad/s
## — the same cap the terrain contact holds (Travel.GLANCE_MAX's twin).
const GLANCE_MAX: float = 2.0

## Below this plan component a press is vertical (one body over another) and
## the plan solve has nothing to say about it.
const FLAT_MIN: float = 0.001


## Presses `me` out of every other creature standing in the world. Called
## from the creature's own tick, in the contact stage, right beside the
## terrain's solids — the world's solid half and the world's living half are
## the same stage of the loop.
static func press(me: Creature2) -> void:
	if not me.is_inside_tree():
		return
	for node in me.get_tree().get_nodes_in_group("creatures2"):
		var other := node as Creature2
		if other == null or other == me or other.armature == null:
			continue
		_press_pair(me, other)


static func _press_pair(me: Creature2, other: Creature2) -> void:
	# The broad phase: two centres further apart than the bodies could reach.
	var span: float = (me.armature.body_length + other.armature.body_length) \
		* 0.5 + REACH_MARGIN
	if me.centre().distance_squared_to(other.centre()) > span * span:
		return

	# The deepest contact, capsule against capsule in 3D.
	var deepest: float = 0.0
	var dir := Vector2.ZERO
	var at := Vector3.ZERO
	var a: Armature = me.armature
	var b: Armature = other.armature
	for s in a.stick_count():
		var p0: Vector3 = a.pos[a.stick_a[s]]
		var p1: Vector3 = a.pos[a.stick_b[s]]
		var ra: float = maxf((a.flesh_r[a.stick_a[s]] + a.flesh_r[a.stick_b[s]])
			* 0.5, a.stick_radius[s])
		for z in b.stick_count():
			var q0: Vector3 = b.pos[b.stick_a[z]]
			var q1: Vector3 = b.pos[b.stick_b[z]]
			var rb: float = maxf((b.flesh_r[b.stick_a[z]] + b.flesh_r[b.stick_b[z]])
				* 0.5, b.stick_radius[z])
			var near: Array = _segment_gap(p0, p1, q0, q1)
			var overlap: float = ra + rb - float(near[0])
			if overlap <= deepest:
				continue
			var out: Vector3 = (near[1] as Vector3) - (near[2] as Vector3)
			var flat := Vector2(out.x, out.y)
			if flat.length_squared() < FLAT_MIN:
				# One body directly over the other: the plan has no push to
				# offer, and the vertical is the carries' business.
				continue
			deepest = overlap
			dir = flat.normalized()
			at = near[1]
	if deepest <= 0.0:
		return

	# My share of the separation: the other body's weight over both. The other
	# takes its own share on its own tick, so the pair parts by the whole
	# overlap without either owning both bodies.
	var mine: float = me.corpus.mass()
	var theirs: float = other.corpus.mass()
	var share: float = theirs / maxf(mine + theirs, Corpus.MIN_MASS)

	# Softness: what was touched decides how fast it stops giving. The flesh
	# at my side of the contact is asked through the same rings that draw it.
	var give: float = STIFF
	var touched: Dictionary = me.contour.locate(at)
	if not touched.is_empty():
		give = STIFF / (1.0 + me.corpus.compliance(touched["band"],
			touched["station"], touched["sector"]))

	var push: Vector2 = dir * (deepest * share * give)
	a.shift(push)
	if not a.collapsed:
		me.head_pos += push
		# The velocity into the other body dies; the slide keeps; and what
		# died arrives in the other body as the shove it physically was.
		var impact: float = me.travel.impetus.deflect(dir)
		if impact > 0.0:
			if not other.armature.collapsed:
				other.shove(-dir * (impact * (1.0 - share)))
			# A press off the body's middle swings it — the same glancing
			# lever the terrain contact turns.
			var lever: Vector2 = Vector2(at.x, at.y) - me.centre()
			var torque: float = lever.x * dir.y - lever.y * dir.x
			me.spin(clampf(torque * impact / maxf(lever.length_squared(), 1.0),
				-GLANCE_MAX, GLANCE_MAX))


## Closest approach of two 3D segments: [distance, point on a, point on b].
## The standard clamped two-parameter solve, degenerate ends handled.
static func _segment_gap(p0: Vector3, p1: Vector3, q0: Vector3,
		q1: Vector3) -> Array:
	var d1: Vector3 = p1 - p0
	var d2: Vector3 = q1 - q0
	var r: Vector3 = p0 - q0
	var a: float = d1.length_squared()
	var e: float = d2.length_squared()
	var f: float = d2.dot(r)
	var s: float = 0.0
	var t: float = 0.0
	if a <= 0.000001 and e <= 0.000001:
		return [r.length(), p0, q0]
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2)
			var denom: float = a * e - b * b
			if denom > 0.000001:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var pa: Vector3 = p0 + d1 * s
	var pb: Vector3 = q0 + d2 * t
	return [pa.distance_to(pb), pa, pb]
