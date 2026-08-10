## The parts of animals lying in the world: a leg bitten off at the shoulder, a
## tail cut through at its root, a head.
##
## Kept separate from ScrapField because the two are different *kinds* of thing
## rather than two sizes of the same one. A scrap is meat — tissue a bite already
## destroyed and threw clear, with no structure left to lose, which is why it can
## be swallowed by walking over it. A part is anatomy that merely stopped being
## joined to an animal: it arrives with every hit point it was standing with, skin
## over fat over muscle over bone, and it is bitten, chewed and eroded through
## exactly the code the body it came off is. It becomes scraps the only way
## anything becomes scraps, which is by something biting it.
##
## So the rule this field exists to enforce is a rule about nothing: a severed part
## is not converted into anything, and nobody has to remember not to convert it.
## The conversion happens when a mouth does it.
##
## The world owns these rather than the creature they came off, and for the same
## reason it owns scraps — tissue that has come away is no longer part of anybody's
## anatomy, and it has to outlive both participants walking away.
class_name CarrionField
extends Node2D

## Hard ceiling on loose parts. Far lower than the scrap ceiling because each of
## these is a whole limb rather than a fleck, and because nothing produces them
## except an animal actually coming apart.
const MAX_PARTS: int = 16
## Velocity retained per second while a part is still moving. Heavier than a
## scrap's: a leg does not skitter.
const DRAG: float = 6.0
const SETTLE_SPEED: float = 4.0
const SETTLE_SPIN: float = 0.35

## How completely a set of jaws commands a piece it can easily lift, per second.
## What actually reaches the meat is this times the creature's grasp of it, so the
## number that decides between carrying and dragging is mass and never this.
const LIFT_RESPONSE: float = 22.0
## How far past the jaws' own reach a lagging piece may trail before the tether
## stops being soft. Beyond this the meat is simply in the mouth, because it is.
const TETHER_SLACK: float = 6.0

## Tissue one unit of food is worth — an intact cell's soft stack, which is the
## same mouthful a scrap represents. Swallowing is therefore priced in the same
## currency as scavenging, and a big piece feeds more because there is more of it.
const FOOD_PER_UNIT: float = TissueGrid.SKIN_HP + TissueGrid.FAT_HP + TissueGrid.MUSCLE_HP

## The height the thinnest possible part occupies once it has come to rest — the
## floor's own band, and what `Part.band` reduces to when a piece is down and has
## no thickness worth speaking of.
##
## It used to be the band of *every* part, on the grounds that meat is flat and on
## the floor. Meat is flat and on the floor once it gets there, and a leg bitten
## off a standing animal is neither for as long as it is falling — see `Part.fall`,
## which is where a part's height actually comes from now. What survives here is
## the floor case, kept because it is the one another field has to agree with: a
## scrap of the same animal lying beside a part has to be exactly as reachable, and
## two descriptions of "on the floor" is two things a set of jaws could disagree
## about.
const GROUND_BAND := Vector2(0.0, Volume.GROUND_THICKNESS)

const COL_SHADOW := Color("14140f", 0.055)
const COL_SKIN_TENSION := Color("f3f1ec", 0.045)
const COL_MUSCLE_FIBRE := Color("3f160f", 0.62)


## One severed part.
##
## A rigid body carrying a bag of tissue cells. The cells keep the shape they were
## posed in at the moment they stopped being an animal — nothing will ever rebuild
## those corners again, which is what having come off *is* — so the part is a
## frozen pose plus a position and an angle, and every world query on it goes
## through the one transform.
class Part extends RefCounted:
	## Centroid of the tissue as it came away, and the frame the cells are held in.
	var pos: Vector2 = Vector2.ZERO
	var angle: float = 0.0
	var vel: Vector2 = Vector2.ZERO
	var spin: float = 0.0
	var settled: bool = false

	var cells: int = 0
	## Four corners per cell in the part's own frame, wound as the lattice winds
	## them.
	var local: PackedVector2Array = PackedVector2Array()
	## Remaining hit points, `cell * LAYERS + layer`. The same storage a patch
	## uses, so the same erosion runs over it.
	var hp: PackedFloat32Array = PackedFloat32Array()
	var fat_full: PackedFloat32Array = PackedFloat32Array()
	## 1 where every layer is spent. Gone means gone here too: not drawn, not
	## bitten, and no longer joining what is either side of it.
	var gone: PackedByteArray = PackedByteArray()
	var gone_count: int = 0
	## Which cells touch which, as a start index per cell into `link_to`. What
	## decides whether chewing a piece in half leaves one piece or two.
	var link_start: PackedInt32Array = PackedInt32Array()
	var link_to: PackedInt32Array = PackedInt32Array()
	## Where each cell was in the animal. Carried only so that meat chewed off this
	## part joins into pieces by the same adjacency a bite on a living body does.
	var cell_key: PackedStringArray = PackedStringArray()
	var cell_col: PackedInt32Array = PackedInt32Array()
	var cell_row: PackedInt32Array = PackedInt32Array()

	## Tissue standing, and what it was standing with when it came off.
	var flesh: float = 0.0
	var full_flesh: float = 0.0
	## Weight, in the same Lizard units every mass in the simulation is quoted in:
	## the fraction of the animal that left, times what that animal weighed. So an
	## Elephant's thigh is a serious thing to drag and a Cat's whole tail is not,
	## without either being written down.
	var full_mass: float = 0.0
	## Radius of gyration about the centroid. Decides how much of a pull on the part
	## becomes a swing rather than a shove — see `CarrionField.carry`.
	var gyradius: float = 1.0
	## Instance id of the creature it came off, held as an id rather than a
	## reference so a part outlives its former owner. Meat off this animal is the
	## one meat that animal may not eat.
	var source_id: int = 0
	## The jaws currently holding it, or null. A part with a carrier is *placed*,
	## by whatever is holding it; a part without one is *integrated*, by the field.
	## The same division the rig already makes between a limb the gait is striding
	## and a limb nothing is holding out.
	var carrier: Node = null

	## Where it is in the one direction the picture does not have, and what is
	## happening to it there. A part comes off an animal at the height the tissue
	## was standing at and falls from there, under the same pull as everything else
	## — see Gravity, which owns both halves of that sentence.
	##
	## This is the whole of why the field no longer quotes a constant band at zero.
	## A leg lying on the floor is on the floor because it *arrived* there, and for
	## the fraction of a second before it does, jaws at floor level cannot reach it
	## and jaws at shoulder level can. Nothing had to be told that: it is one band
	## derived from one height, tested by the same `overlaps` every other pair of
	## things in the world is tested by.
	var fall: Gravity.Fall = Gravity.Fall.new()
	## How thick the piece is, so the band it occupies is the volume of a real
	## object rather than a plane. Carried off the lattice with the height.
	var thickness: float = Volume.GROUND_THICKNESS * 0.5

	## The heights this part occupies right now.
	##
	## In the air it is a slab about wherever it has fallen to; on the ground it is
	## `GROUND_BAND`, and that is not a special case but the same expression with
	## the height at zero — a thing resting on the floor is a thing whose underside
	## is the floor. Held to at least that band's own thickness so a piece of meat
	## worn down to a sliver is still something a mouth can close on.
	func band() -> Vector2:
		var half: float = maxf(thickness, Volume.GROUND_THICKNESS * 0.5)
		return Vector2(fall.height, fall.height + half * 2.0)

	func to_world(at: Vector2) -> Vector2:
		return pos + at.rotated(angle)

	func to_local(at: Vector2) -> Vector2:
		return (at - pos).rotated(-angle)

	func local_centre_of(cell: int) -> Vector2:
		var i: int = cell * 4
		return (local[i] + local[i + 1] + local[i + 2] + local[i + 3]) * 0.25

	func centre_of(cell: int) -> Vector2:
		return to_world(local_centre_of(cell))

	func corners_of(cell: int, out: PackedVector2Array) -> void:
		var i: int = cell * 4
		for k in 4:
			out[k] = to_world(local[i + k])

	## Nominal side length of a cell, off its diagonals — the same measure the
	## lattice takes, so a chunk shed here is the size a chunk shed there is.
	func extent_of(cell: int) -> float:
		var i: int = cell * 4
		return (local[i].distance_to(local[i + 2])
			+ local[i + 1].distance_to(local[i + 3])) * 0.25

	## Long axis of a cell, in world space. Meat keeps the grain it had in the body.
	func angle_of(cell: int) -> float:
		var i: int = cell * 4
		var a: Vector2 = (local[i] + local[i + 1]) * 0.5
		var b: Vector2 = (local[i + 3] + local[i + 2]) * 0.5
		return (b - a).angle() + angle

	## What is left of it, as a fraction of what came off.
	func condition() -> float:
		return flesh / full_flesh if full_flesh > 0.0 else 0.0

	## Weight now. A piece chewed half away is half the drag it was, because there
	## is half of it.
	func mass() -> float:
		return full_mass * condition()

	## How far this part reaches from a point on it — the distance the furthest
	## surviving corner is from there.
	##
	## This is the whole of "will it go down". Measured from the hold rather than
	## from the centre because what goes in first is whatever the jaws have, so a
	## long piece taken by the middle passes a mouth that the same piece taken by
	## one end will not. Food size, food shape and where it was bitten, in one read.
	func reach_from(at: Vector2) -> float:
		var far: float = 0.0
		for cell in cells:
			if gone[cell] != 0:
				continue
			var i: int = cell * 4
			for k in 4:
				far = maxf(far, at.distance_to(local[i + k]))
		return far

	func retire(cell: int) -> void:
		if gone[cell] != 0:
			return
		gone[cell] = 1
		gone_count += 1

	## Nothing left of it at all. Chewed through rather than eaten: whatever was in
	## it went into the world as scraps and there is no longer a piece here.
	func is_spent() -> bool:
		return gone_count >= cells

	func hold_by(jaws: Node) -> void:
		carrier = jaws
		settled = false

	## Lets go. The piece keeps whatever it was moving with, so meat dropped by a
	## running animal is thrown forward and meat put down is put down.
	##
	## And it keeps the height it was let go at, with no upward speed, which is the
	## whole of what dropping something is: jaws that open at head height leave a leg
	## falling from head height. Nothing had to say so — the fall simply resumes from
	## wherever the carrying stopped placing it.
	func release() -> void:
		carrier = null
		settled = false
		fall.start(fall.height, 0.0, fall.floor_height)

	## Moves this part so the place a set of jaws has hold of arrives at the jaws.
	##
	## `grasp` is how completely the creature commands the piece — its strength
	## against the piece's weight — and it is the only thing separating carrying
	## from dragging. There is no second path and no threshold: a light piece is at
	## the mouth within a tick and rides wherever the head goes, while a heavy one
	## is always behind where it was asked to be, and being always behind *is*
	## being dragged.
	##
	## The pull is split between shifting the piece and turning it exactly as a rigid
	## body splits an impulse applied off its centre of mass, and the split is not
	## the same in both directions. A pull straight down the arm from the hold to
	## the centre is pure translation — there is no way to rotate a thing toward
	## yourself — so all of it moves the piece. A pull across the arm mostly swings
	## it, and the further out the jaws have hold, the more mostly.
	##
	## That asymmetry is where bite position enters the animation without anything
	## animating it: a leg taken by the ankle is hauled bodily along its own length
	## and swings freely across it, so it trails and slews after the animal; a leg
	## taken across its middle has no lever to speak of and is carried level. Neither
	## was posed, and there is no case here for either.
	## `jaw_height` is where those jaws are in the vertical, and the piece is lifted
	## toward it by the same `grasp` that carries it horizontally — which is the
	## whole of the difference between a creature carrying a leg and a creature
	## dragging one. Nothing here decides which: a light piece arrives at the mouth
	## and rides at mouth height, a heavy one never gets there and stays scraping
	## along whatever is under it, and the only number separating them is the mass in
	## the divisor. It cannot go below the ground it is being hauled over, because
	## dragging is a thing done *along* a surface.
	func carry(hold: Vector2, jaw: Vector2, grasp: float, reach: float, delta: float,
			jaw_height: float = 0.0, surface: float = 0.0) -> void:
		if delta <= 0.0:
			return
		var was: Vector2 = pos
		var was_angle: float = angle
		var arm: Vector2 = hold.rotated(angle)
		var error: Vector2 = jaw - (pos + arm)
		var take: float = 1.0 - exp(-LIFT_RESPONSE * clampf(grasp, 0.0, 1.0) * delta)
		var lever: float = arm.length_squared()
		if lever > 0.0001:
			var swing: float = lever / (lever + gyradius * gyradius)
			var out: Vector2 = arm / sqrt(lever)
			var along: Vector2 = out * error.dot(out)
			pos += (along + (error - along) * (1.0 - swing)) * take
			angle += (arm.x * error.y - arm.y * error.x) / lever * take * swing
		else:
			pos += error * take

		# ...and then the tether, which is not soft. However badly overmatched the
		# jaws are, what is in them is in them: a piece that has lagged further than
		# the mouth can reach is hauled up to that distance and no further, which is
		# what stops a dragged limb being left behind by a sprint.
		arm = hold.rotated(angle)
		var slack: Vector2 = jaw - (pos + arm)
		var over: float = slack.length() - reach
		if over > 0.0:
			pos += slack.normalized() * over
		# And the same haul in the vertical. `take` is the identical response, so a
		# piece that is being carried level is also being carried up, and one that is
		# only being dragged is only being dragged.
		fall.rest_on(maxf(lerpf(fall.height, jaw_height, take), surface))
		# Kept rather than zeroed, so a piece put down by a running animal is thrown
		# and one released mid-swing goes on swinging. Motion is measured off where
		# it actually went, which is the only honest source for it.
		vel = (pos - was) / delta
		spin = angle_difference(was_angle, angle) / delta


var parts: Array[Part] = []

## What a falling part lands on. Optional — with nothing here everything comes to
## rest at zero, which is exactly the flat habitat every headless test runs in —
## and set by the world, which is the only thing that knows both fields exist.
var terrain: Terrain = null

var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _taken := PackedFloat32Array()
## Reused geometry, so drawing a settled field allocates nothing per frame.
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _flat := PackedColorArray([COL_SHADOW])
var _skin_lines := PackedVector2Array()
var _muscle_lines := PackedVector2Array()
## Which runs of the drawn mesh belong to parts that are off the ground, and how
## far off. Only ever filled while something is actually falling, so a habitat
## whose meat has all landed pays one empty loop for it.
var _aloft_span := PackedInt32Array()
var _aloft_lift := PackedFloat32Array()
## Whether the drawn field is stale: set by anything that adds, removes, erodes
## or moves a part, and held true while any part is still in motion. A habitat
## of settled meat re-walks no cells and issues no draw at all — the last frame
## drawn is still the truth, and that is what a canvas item already shows.
var _dirty: bool = true


func _ready() -> void:
	# Over the scraps and the pellets, under the creatures: a leg lying on the
	# ground is a bigger thing than a fleck of meat and a smaller one than an
	# animal standing on it.
	z_index = 3
	# Findable by anything resolving a cursor into a target, on the same terms the
	# creatures are — meat competes for a click exactly as it already competes for
	# a bite, and by the same score.
	add_to_group("carrion")


func _init() -> void:
	_taken.resize(TissueGrid.LAYERS)


# ------------------------------------------------------------------ arrival ----

## Takes the pieces an animal has just come apart into.
##
## `source` is the creature they left, read for two things it is the only one that
## knows: what it weighed while they were still part of it, and who it is — so that
## meat off an animal stays meat that animal may not eat, however many hands it
## passes through afterwards.
func receive(pieces: Array, source: Node) -> void:
	var source_mass: float = 1.0
	var source_id: int = 0
	if source != null:
		source_mass = source.physique.mass
		source_id = source.get_instance_id()
	for piece in pieces:
		var part: Part = _build(piece, source_mass, source_id)
		if part != null:
			parts.append(part)
	_cull()
	_dirty = true


## Turns one piece of lattice into a body lying in the world.
##
## The only real work is choosing a frame: the cells arrive in world space, and a
## part has to be able to move, so they are re-expressed about their own centroid.
## Nothing else about them changes, which is the point.
func _build(piece: TissueGrid.Piece, source_mass: float, source_id: int) -> Part:
	if piece == null or piece.cells <= 0 or piece.flesh <= 0.0:
		return null
	var part := Part.new()
	part.cells = piece.cells
	part.hp = piece.hp
	part.fat_full = piece.fat_full
	part.link_start = piece.link_start
	part.link_to = piece.link_to
	part.cell_key = piece.cell_key
	part.cell_col = piece.cell_col
	part.cell_row = piece.cell_row
	part.gone.resize(piece.cells)
	part.flesh = piece.flesh
	part.full_flesh = piece.flesh
	part.full_mass = source_mass * piece.share
	part.source_id = source_id
	part.thickness = maxf(piece.thickness, Volume.GROUND_THICKNESS * 0.5)

	var centre := Vector2.ZERO
	for cell in piece.cells:
		var i: int = cell * 4
		centre += (piece.corners[i] + piece.corners[i + 1]
			+ piece.corners[i + 2] + piece.corners[i + 3]) * 0.25
	part.pos = centre / float(piece.cells)

	part.local.resize(piece.cells * 4)
	var spread: float = 0.0
	for cell in piece.cells:
		var i: int = cell * 4
		for k in 4:
			part.local[i + k] = piece.corners[i + k] - part.pos
		spread += part.local_centre_of(cell).length_squared()
	part.gyradius = maxf(sqrt(spread / float(piece.cells)), 0.5)
	# And the drop. The piece knows the height its cells were standing at, so this
	# is the one line that turns a severed part into a physical object: it starts
	# where the tissue was and falls from there, with no velocity of its own,
	# because nothing threw it — what took it off was a set of jaws, and whatever
	# they imparted is the shove the caller applies to `vel`.
	#
	# Measured down to the piece's own underside rather than to its centre line, so
	# a leg that comes off already lying on the floor is already lying on the floor
	# and does not drop by half its own thickness first.
	part.fall.start(maxf(piece.height - part.thickness, 0.0), 0.0,
		_surface_at(part.pos))
	return part


## What is underneath a point. Zero over open ground, and the top of whatever is
## there otherwise — a part dropped onto a rock lies on the rock, for the same
## reason and through the same query a foot set down on one stands on it.
##
## Null-safe because the field is perfectly capable of running without terrain,
## and every headless test that has no obstacles in it does.
func _surface_at(where: Vector2) -> float:
	if terrain == null:
		return 0.0
	return terrain.surface(where, 0.0).x


## Drops the oldest loose parts once there are too many. A part in somebody's jaws
## is never the one culled — it is the one being interacted with.
func _cull() -> void:
	var excess: int = parts.size() - MAX_PARTS
	var i: int = 0
	while excess > 0 and i < parts.size():
		if parts[i].carrier == null:
			parts.remove_at(i)
			excess -= 1
		else:
			i += 1


func clear() -> void:
	parts.clear()
	_dirty = true


# ------------------------------------------------------------------- biting ----

## The part a bite of this footprint reaches deepest into, or null.
##
## Scored the way the anatomy query scores a creature — signed distance from the
## bite's centre to the surface, so the most negative is the deepest overlap — for
## the one reason that matters: the world compares this against the creatures in
## the same volume and bites whichever it reached furthest into. A leg lying across
## an animal's flank has to be able to win that comparison, and a leg the jaws only
## grazed has to be able to lose it.
## `reach` is the height band the jaws asking can bring to bear. A part lying on
## the ground is a flat thing on the floor, so anything standing on that floor
## reaches it and anything in the air does not — which is the whole of why a
## flier has to come down for carrion. A part somebody is already carrying is at
## that mouth's height by definition and is never height-gated.
func reach_of(center: Vector2, radius: float, reach: Vector2 = Stature.UNBOUNDED) -> Part:
	var best: Part = null
	var best_score: float = radius
	for part in parts:
		if part.carrier == null and not Stature.overlaps(reach, part.band()):
			continue
		var score: float = depth_into(part, center)
		if score <= best_score:
			best_score = score
			best = part
	return best


## Signed distance from a point to a part's surface: negative inside it, and more
## negative the deeper in. The same measure the anatomy query reports, so the world
## can compare a piece of meat against a living body without either being favoured.
func depth_into(part: Part, center: Vector2) -> float:
	var best: float = INF
	for cell in part.cells:
		if part.gone[cell] != 0:
			continue
		var grain: float = part.extent_of(cell) * 0.5
		best = minf(best, center.distance_to(part.centre_of(cell)) - grain)
	return best


## Erodes a part wherever the mark covers it, and hands back whatever came loose
## as meat.
##
## The same walk `TissueGrid.bite` makes, over the same kind of storage, spending
## the same penetration by the same rule — a severed leg has skin to get through,
## fat that cushions, muscle under that and bone that stops a bite dead, because it
## is a leg. What it does not have is regions, organs or a body to report to, which
## is the whole of the difference.
##
## This is the one and only way a part becomes scraps.
func bite(part: Part, mark: BiteMark, shed: Array) -> float:
	if part == null or mark == null or mark.is_empty():
		return 0.0
	var loose: Array = []
	var removed: float = 0.0
	for cell in part.cells:
		if part.gone[cell] != 0:
			continue
		var at: Vector2 = part.centre_of(cell)
		var grain: float = part.extent_of(cell)
		if at.x + grain < mark.lo.x or at.x - grain > mark.hi.x \
				or at.y + grain < mark.lo.y or at.y - grain > mark.hi.y:
			continue
		part.corners_of(cell, _quad)
		var depth: float = mark.depth_over(at, _quad)
		if depth <= 0.0:
			continue
		removed += _erode(part, cell, depth, at, loose)
	if removed <= 0.0:
		return 0.0
	part.flesh = maxf(part.flesh - removed, 0.0)
	TissueGrid.coalesce_shed(loose, shed)
	_dirty = true
	return removed


func _erode(part: Part, cell: int, budget: float, at: Vector2, loose: Array) -> float:
	var base: int = cell * TissueGrid.LAYERS
	var removed: float = TissueGrid.erode_stack(part.hp, base, budget, _taken)
	if removed <= 0.0:
		return 0.0
	for layer in TissueGrid.LAYERS:
		if _taken[layer] <= 0.0 or part.hp[base + layer] > 0.0:
			continue
		var chunk: TissueGrid.Shed = TissueGrid.shed_layer(
			layer, at, part.extent_of(cell), part.angle_of(cell))
		if chunk == null:
			continue
		chunk.patch_key = part.cell_key[cell]
		chunk.col = part.cell_col[cell]
		chunk.row = part.cell_row[cell]
		loose.append(chunk)
	if _is_empty(part, base):
		part.retire(cell)
	return removed


func _is_empty(part: Part, base: int) -> bool:
	for layer in TissueGrid.LAYERS:
		if part.hp[base + layer] > 0.0:
			return false
	return true


# ------------------------------------------------------------- coming apart ----

## Splits a part that chewing has cut in two, keeping whichever piece the given
## point is in and appending the rest to the field.
##
## The same rule that made this part in the first place, one level down: cells
## still joined to each other by surviving tissue are one thing, and cells that are
## not are another. Nothing here knows what it is cutting. A leg chewed through at
## the ankle drops its foot for the identical reason the animal dropped the leg,
## and a piece worked at from the middle comes apart into two ends.
##
## `keep` is in the part's own frame — the mouthful the jaws still have. What they
## are holding stays theirs; what has fallen off falls off.
func split(part: Part, keep: Vector2) -> Array[Part]:
	var made: Array[Part] = []
	if part == null or part.gone_count == 0:
		return made
	var component := PackedInt32Array()
	component.resize(part.cells)
	component.fill(-1)
	var groups: Array[PackedInt32Array] = []
	var stack: Array[int] = []
	for start in part.cells:
		if component[start] >= 0 or part.gone[start] != 0:
			continue
		var id: int = groups.size()
		var members := PackedInt32Array()
		component[start] = id
		stack.append(start)
		while not stack.is_empty():
			var at: int = stack.pop_back()
			members.append(at)
			for k in range(part.link_start[at], part.link_start[at + 1]):
				var other: int = part.link_to[k]
				if component[other] >= 0 or part.gone[other] != 0:
					continue
				component[other] = id
				stack.append(other)
		groups.append(members)
	if groups.size() < 2:
		return made

	# Whichever piece the hold is nearest stays the part the jaws are holding; every
	# other piece becomes a part of its own, lying where it was when it came off.
	var held: int = _nearest_group(part, groups, keep)
	for id in groups.size():
		if id == held:
			continue
		var piece: Part = _extract(part, groups[id])
		if piece != null:
			made.append(piece)
			parts.append(piece)
	_keep_only(part, groups[held])
	_dirty = true
	# Not culled: dividing a piece adds no tissue to the world, and the ceiling is
	# on how many animals have come apart rather than on how finely.
	return made


func _nearest_group(part: Part, groups: Array[PackedInt32Array], keep: Vector2) -> int:
	var best: int = 0
	var best_distance: float = INF
	for id in groups.size():
		for cell in groups[id]:
			var d: float = keep.distance_squared_to(part.local_centre_of(cell))
			if d < best_distance:
				best_distance = d
				best = id
	return best


## Builds a new part out of a subset of another's cells, in the same world pose it
## is standing in — so a piece coming apart does not move, it merely stops being
## one thing.
func _extract(part: Part, members: PackedInt32Array) -> Part:
	var piece := Part.new()
	piece.cells = members.size()
	if piece.cells <= 0:
		return null
	piece.local.resize(piece.cells * 4)
	piece.hp.resize(piece.cells * TissueGrid.LAYERS)
	piece.fat_full.resize(piece.cells)
	piece.gone.resize(piece.cells)
	piece.cell_key.resize(piece.cells)
	piece.cell_col.resize(piece.cells)
	piece.cell_row.resize(piece.cells)
	piece.link_start.resize(piece.cells + 1)
	piece.angle = part.angle
	piece.source_id = part.source_id
	piece.vel = part.vel
	piece.spin = part.spin
	# Both halves of the thing it was torn out of: a piece bitten off a leg that is
	# still in the air is still in the air, at the same height and going the same
	# way. Chewing something in half is not a reason for either half to teleport to
	# the floor.
	piece.thickness = part.thickness
	piece.fall.start(part.fall.height, part.fall.rate, part.fall.floor_height)

	var index := PackedInt32Array()
	index.resize(part.cells)
	index.fill(-1)
	for i in piece.cells:
		index[members[i]] = i

	var centre := Vector2.ZERO
	for i in piece.cells:
		centre += part.local_centre_of(members[i])
	centre /= float(piece.cells)
	piece.pos = part.to_world(centre)

	var links := PackedInt32Array()
	for i in piece.cells:
		var cell: int = members[i]
		for k in 4:
			piece.local[i * 4 + k] = part.local[cell * 4 + k] - centre
		for layer in TissueGrid.LAYERS:
			var have: float = part.hp[cell * TissueGrid.LAYERS + layer]
			piece.hp[i * TissueGrid.LAYERS + layer] = have
			piece.flesh += have
		piece.fat_full[i] = part.fat_full[cell]
		piece.cell_key[i] = part.cell_key[cell]
		piece.cell_col[i] = part.cell_col[cell]
		piece.cell_row[i] = part.cell_row[cell]
		piece.link_start[i] = links.size()
		for k in range(part.link_start[cell], part.link_start[cell + 1]):
			var at: int = index[part.link_to[k]]
			if at >= 0:
				links.append(at)
	piece.link_start[piece.cells] = links.size()
	piece.link_to = links

	# Weight and condition come across in proportion, so two halves of a leg weigh
	# what the leg did and a piece never gains by being divided.
	var carried: float = piece.flesh / maxf(part.flesh, 0.0001)
	piece.full_flesh = part.full_flesh * carried
	piece.full_mass = part.full_mass * carried
	var spread: float = 0.0
	for cell in piece.cells:
		spread += piece.local_centre_of(cell).length_squared()
	piece.gyradius = maxf(sqrt(spread / float(piece.cells)), 0.5)
	return piece


## Empties everything in a part that is not in the group it kept. The cells stay
## where they are and simply have nothing in them, which is what the rest of this
## file already understands an absent cell to be.
func _keep_only(part: Part, members: PackedInt32Array) -> void:
	var keep := PackedByteArray()
	keep.resize(part.cells)
	for cell in members:
		keep[cell] = 1
	for cell in part.cells:
		if keep[cell] != 0 or part.gone[cell] != 0:
			continue
		var base: int = cell * TissueGrid.LAYERS
		for layer in TissueGrid.LAYERS:
			part.flesh = maxf(part.flesh - part.hp[base + layer], 0.0)
			part.hp[base + layer] = 0.0
		part.retire(cell)


# ------------------------------------------------------------------- eating ----

## Takes a part out of the world and reports what it was worth to eat.
##
## Priced by the tissue actually in it, against the same mouthful a scrap is, so
## nothing about swallowing needs to know what it swallowed. A part chewed most of
## the way down feeds less than a whole one because there is less of it left.
func swallow(part: Part) -> int:
	if part == null:
		return 0
	parts.erase(part)
	part.carrier = null
	_dirty = true
	return maxi(1, int(round(part.flesh / FOOD_PER_UNIT)))


# ------------------------------------------------------------------ settling ----

func _process(delta: float) -> void:
	settle(delta)
	# A redraw re-walks every cell of every part, so it is issued only while the
	# picture can differ from the one already on screen: something moving,
	# falling or carried, or the set itself just changed. `_dirty` stays up one
	# frame past the last motion so the final resting pose is what gets drawn.
	var live: bool = false
	for part in parts:
		if part.carrier != null or not part.settled or not part.fall.resting:
			live = true
			break
	if live or _dirty:
		queue_redraw()
	_dirty = live


## The fall, then ground friction on everything nothing is holding, and the sweep
## for pieces that no longer exist. Exponential decay rather than a linear step, so
## the settle looks the same whatever the frame rate — and a part at rest falls out
## of the maths entirely.
##
## The two halves are in that order and gated against each other, because friction
## is a thing the ground does. A part still in the air is slowed by nothing: it
## keeps every bit of the speed the jaws let go of it with, and it keeps travelling
## while it drops, which is what makes a leg thrown off a running animal land
## somewhere rather than directly below where it came apart. The moment it arrives
## the drag starts, and what was a throw becomes a skid.
func settle(delta: float) -> void:
	var keep: float = exp(-DRAG * delta)
	for i in range(parts.size() - 1, -1, -1):
		var part: Part = parts[i]
		# A piece chewed clean through has already left, one scrap at a time. There
		# is no event for that and there should not be: it is simply a part with
		# nothing in it, and nothing in the world has anything to draw or bite.
		if part.is_spent():
			parts.remove_at(i)
			_dirty = true
			continue
		# Something with hold of it is not falling. Jaws carry a piece of meat at the
		# height of the jaws, which is what they are doing when they lift it — see
		# `carry`, which places the part in all three directions rather than
		# integrating it in any of them.
		if part.carrier != null:
			continue
		if not part.fall.resting:
			part.fall.advance(delta, _surface_at(part.pos))
			# Still going somewhere horizontally while it does. A part in the air is
			# not settled however slowly it is travelling, so the test at the bottom
			# is skipped and it cannot go to sleep mid-drop.
			part.pos += part.vel * delta
			part.angle += part.spin * delta
			continue
		# On the ground, and the ground may have moved out from under it — a part
		# that has been dragged off the top of an obstacle starts falling again, and
		# nothing had to notice. `advance` returns immediately when the surface is
		# still where it was, so a field of settled meat pays a comparison per part.
		var surface: float = _surface_at(part.pos)
		if part.fall.height > surface + Gravity.TOUCHDOWN:
			part.fall.advance(delta, surface)
			part.settled = false
			continue
		part.fall.rest_on(surface)
		if part.settled:
			continue
		part.pos += part.vel * delta
		part.angle += part.spin * delta
		part.vel *= keep
		part.spin *= keep
		if part.vel.length_squared() < SETTLE_SPEED * SETTLE_SPEED \
				and absf(part.spin) < SETTLE_SPIN:
			part.vel = Vector2.ZERO
			part.spin = 0.0
			part.settled = true


# ------------------------------------------------------------------ drawing ----

## Drawn as the tissue it is, in the creature's own inks and through the creature's
## own colour reading — a severed leg is not restyled by having come off, and the
## cut face across it shows fat, meat and bone in the order a bite reached them.
func _draw() -> void:
	var count: int = 0
	for part in parts:
		count += part.cells - part.gone_count
	if count <= 0:
		return
	if _points.size() != count * 4:
		_points.resize(count * 4)
		_colors.resize(count * 4)
		_indices.resize(count * 6)
	var v: int = 0
	var t: int = 0
	# Where each part that is off the ground begins in the buffer, and how far up it
	# is. Empty in the ordinary case — meat lies on the floor — which is what keeps
	# the second pass below free for a field of settled parts.
	_aloft_span.resize(0)
	_aloft_lift.resize(0)
	for part in parts:
		var from: int = v
		for cell in part.cells:
			if part.gone[cell] != 0:
				continue
			part.corners_of(cell, _quad)
			var color: Color = CreatureView.tissue_color(
				part.hp, cell * TissueGrid.LAYERS, part.fat_full[cell])
			for k in 4:
				_points[v + k] = _quad[k]
				_colors[v + k] = color
			_indices[t] = v
			_indices[t + 1] = v + 1
			_indices[t + 2] = v + 2
			_indices[t + 3] = v
			_indices[t + 4] = v + 2
			_indices[t + 5] = v + 3
			v += 4
			t += 6
		if v > from and part.fall.is_airborne():
			_aloft_span.append(from)
			_aloft_span.append(v)
			_aloft_lift.append(part.fall.height)

	# The shadow goes on the ground, because that is where shadows are. It is drawn
	# from the positions before the lift is applied, so the gap between a falling
	# part and its own shadow is exactly how far it still has to fall — the same
	# reading, through the same constant, that says how high a creature is holding
	# its body.
	draw_set_transform(Vector2(0.0, 5.0), 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _flat)
	for i in _aloft_lift.size():
		var lift := Vector2(0.0, -_aloft_lift[i] * Posture.PERSPECTIVE)
		for k in range(_aloft_span[i * 2], _aloft_span[i * 2 + 1]):
			_points[k] += lift
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)
	_draw_grain()


## The same material detail the body carries, for the same reason: intact skin
## reads as one stretched membrane and exposed muscle as fibres along the grain,
## neither of them along the cell boundaries. Both go out as one call apiece.
func _draw_grain() -> void:
	_skin_lines.resize(0)
	_muscle_lines.resize(0)
	for part in parts:
		# Grain is drawn *on* the meat, so it goes wherever the meat went. Taken off
		# the same height through the same constant as the cells themselves — two
		# readings of one fall would be skin sliding off a leg on the way down.
		var lift := Vector2(0.0, -part.fall.height * Posture.PERSPECTIVE)
		for cell in part.cells:
			if part.gone[cell] != 0:
				continue
			var base: int = cell * TissueGrid.LAYERS
			part.corners_of(cell, _quad)
			if part.hp[base + TissueGrid.SKIN] > 0.0:
				if part.cell_row[cell] % 2 == 1:
					_skin_lines.append(_quad[0].lerp(_quad[1], 0.5) + lift)
					_skin_lines.append(_quad[3].lerp(_quad[2], 0.5) + lift)
				continue
			if part.hp[base + TissueGrid.FAT] > 0.0 \
					or part.hp[base + TissueGrid.MUSCLE] <= 0.0:
				continue
			for strand in range(1, 4):
				var across: float = float(strand) * 0.25
				_muscle_lines.append(_quad[0].lerp(_quad[1], across) + lift)
				_muscle_lines.append(_quad[3].lerp(_quad[2], across) + lift)
	if not _skin_lines.is_empty():
		draw_multiline(_skin_lines, COL_SKIN_TENSION, 0.75, true)
	if not _muscle_lines.is_empty():
		draw_multiline(_muscle_lines, COL_MUSCLE_FIBRE, 0.9, true)
