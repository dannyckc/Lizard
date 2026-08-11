## Where the animal's weight actually is, and whether it is over its feet.
##
## The one thing the simulation had never asked. Mass was a total — `Physique`
## counts every cell in the body and says how much there is of it — and *where*
## it was got answered, when it was answered at all, by a chain of discs down the
## drawn silhouette: `Physique.centroid`, which knew nothing about bone being
## twice the density of fat, nothing about the legs, nothing about which half of
## the animal had been eaten, and nothing at all about height. It was a picture's
## middle standing in for a body's centre of gravity, and every consequence in
## the game that should have followed from weight followed from an outline
## instead.
##
## This is the real one, and it is counted off the same cells everything else is.
## Every cell in `AnatomyLattice` is a box of one tissue at a known place in the
## animal's own three-dimensional frame; a centre of gravity is that census with
## each cell weighted by where it sits as well as by what it weighs. So:
##
##   * **bone is heavy and fat is not.** A skull is denser than the cheek around
##     it, so a big head pulls the centre forward further than its size alone
##     would say. Nothing had to be told this — it is `AnatomyLattice.DENSITY`,
##     the same table the scales already weigh through.
##   * **the legs are part of the animal.** Four limbs are a serious fraction of
##     a body, they hang below it, and they are the reason the centre of gravity
##     of a standing creature is lower than the middle of its chest.
##   * **damage moves it.** A creature bitten hollow through one haunch carries
##     its weight forward and to the other side, because the cells that were
##     over there are gone. The silhouette centroid could never say this: the
##     outline of a half-eaten animal is the outline it always had.
##   * **it has a height.** Which is the whole of what makes a body tip rather
##     than slide, and the term the old reading did not have at all.
##
## Two readings come out, and they are deliberately different questions:
##
##   * `body` is the centre in the animal's own frame — where the weight sits in
##     the *build*. It does not move when the creature walks, and that is what
##     makes it the thing generation is constrained against: `along` is where the
##     weight is down the length of the animal, in exactly the units the girdles
##     are placed in, so "are this creature's legs under its weight" is one
##     subtraction.
##   * `centre` and `height` are the same point posed into the world, which does
##     move — with the spine's bend, with the tail's droop, with wherever the
##     gait has just put the feet. That is what the live questions are asked of.
##
## The cost is a single walk of the cells, and only when the census has actually
## changed — a build or a bite. What the world reads every tick is the reduction:
## a mass per posed column of the body and of each limb, seventy-odd numbers on
## any animal, posed through geometry `TissueGrid` has already solved. An
## elephant is a quarter of a million cells and none of them are touched on an
## ordinary tick.
class_name Plumb
extends RefCounted

## How much of its own support a body is expected to keep the line inside of
## before anything calls the stance implausible. Not zero, and not a taste: a
## foot is placed once per step and the body travels over it for the whole of the
## stance, so a stance with the line exactly on the boundary is one that is out
## over its own edge for half of every stride. Quoted as a share of the support's
## own radius, so a wide-standing animal is allowed the wider absolute margin it
## has actually earned.
const KEEP: float = 0.25

## Cells whose tissue is gone still occupy the animal; they simply weigh nothing.
## Nothing in the file needs a floor under the total except the division at the
## end of it, and this is that floor.
const MIN_UNITS: float = 0.0001


# ------------------------------------------------------- the build's weight ----

## The centre of gravity in the animal's own frame, px: x runs snout to tail tip,
## y flank to flank, z belly to back — the frame `AnatomyLattice` carves in, so
## this is literally the mean of the cells.
var body: Vector3 = Vector3.ZERO
## Where that is down the length of the animal, as a fraction of the clipped body
## the girdles are placed in. 0 is the snout, 1 the tail tip, and `rear_limb_t`
## is directly comparable to it — which is the whole reason it is quoted this way
## rather than in pixels.
var along: float = 0.5
## The same, on the animal as it was built: what the species weighs like before
## anything has been taken out of it. Kept because a constraint on *generation*
## is a statement about the build and must not drift as the creature is eaten —
## a body does not regrow its legs in a better place because something bit it.
var built: Vector3 = Vector3.ZERO
var built_along: float = 0.5
## Density-weighted cells standing, and as built. The same units
## `AnatomyLattice.standing_units` is in, which is what makes this a centre of
## *gravity* rather than a centre of volume.
var units: float = 0.0
var built_units: float = 0.0


# --------------------------------------------------------- posed, in the world ----

## The centre of gravity on the ground plane, world px — where the plumb line
## comes down.
var centre: Vector2 = Vector2.ZERO
## And how high above the ground it hangs. The lever every topple turns through.
var height: float = 0.0
## Whether the two above were posed from real geometry this tick. False on a body
## whose patches have not been solved yet, and the signal to every consumer that
## it should use the build's own reading instead of a stale world one.
var posed: bool = false


# ------------------------------------------------------------ against the feet ----

## The middle of whatever is holding the animal up, on the ground plane.
var base: Vector2 = Vector2.ZERO
## How far inside its own support the line falls, in px. Negative is a line
## outside the feet, which is a body that is going over.
var clearance: float = 0.0
## From the support's edge out to the line, when the line is outside it. The
## direction a body topples, and zero-length when it is not toppling.
var overhang: Vector2 = Vector2.ZERO
## How big the support is — the radius of the feet about their own middle. What
## `clearance` is worth is relative to this, and both are kept because a margin
## quoted only as a ratio hides which of the two moved.
var span: float = 0.0
## How many contacts are holding the animal up. Two is a biped or a quadruped
## mid-trot; one is a body on the way down.
var feet: int = 0


# ------------------------------------------------------------------ internals ----

## Density units standing in each posed column, and where in that column they
## are: mean lateral row (-1 one flank, +1 the other) and mean height above the
## column's own midline, px. Indexed `patch * COLS + column` — see `_slot`.
var _mass: PackedFloat32Array = PackedFloat32Array()
var _row: PackedFloat32Array = PackedFloat32Array()
var _rise: PackedFloat32Array = PackedFloat32Array()
## The census this reduction was taken of, so a tick that changed nothing walks
## no cells.
var _revision: int = -1
var _damage: int = -1
var _resync: int = -1
## Columns per patch, and the stride between patches in the arrays above. The
## body's is the larger of the two, so one stride covers both.
const COLS: int = BodyPlan.BODY_COLS
const PATCHES: int = 5

## Scratch for the support hull. Held rather than allocated because it is
## refilled every tick and never grows past five points.
var _prints: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_mass.resize(PATCHES * COLS)
	_row.resize(PATCHES * COLS)
	_rise.resize(PATCHES * COLS)


func reset() -> void:
	_revision = -1
	_damage = -1
	_resync = -1
	posed = false
	overhang = Vector2.ZERO
	clearance = 0.0


# ------------------------------------------------------------------ measuring ----

## Walks the cells and reduces them to a centre and a per-column profile.
##
## The one expensive thing in the file, and it runs when the animal's own
## description changes or when something has bitten a piece out of it — never on
## an ordinary tick. Returns whether it did any work, which is what lets a caller
## avoid re-posing a profile that has not moved.
##
## `built` is taken on the same walk rather than on a second one: a cell's
## contribution to the intact animal is what it would weigh if it were standing,
## and every cell is either standing or not. So the two centres come out of one
## pass over one array, and they agree by construction — which matters, because
## the difference between them is exactly what a wound did to the balance.
func measure(lattice: AnatomyLattice, grid: TissueGrid) -> bool:
	if lattice == null or lattice.count == 0:
		return false
	var rev: int = lattice.revision
	var dmg: int = grid.revision if grid != null else 0
	var res: int = grid.resync if grid != null else 0
	if rev == _revision and dmg == _damage and res == _resync:
		return false
	_revision = rev
	_damage = dmg
	_resync = res

	_mass.fill(0.0)
	_row.fill(0.0)
	_rise.fill(0.0)
	var sum := Vector3.ZERO
	var total: float = 0.0
	var whole := Vector3.ZERO
	var whole_total: float = 0.0

	# Hoisted out of the loop for the same reason every other per-cell walk in
	# the game hoists them: a packed array read through a member lookup is two
	# indirections a cell, and there are a great many cells.
	var positions: PackedVector3Array = lattice.pos
	var tissue: PackedByteArray = lattice.kind
	var missing: PackedByteArray = lattice.gone
	var patch_of: PackedByteArray = lattice.patch_of
	var cell_of: PackedInt32Array = lattice.cell_of
	var lift: PackedFloat32Array = lattice.lift
	var density: Array[float] = AnatomyLattice.DENSITY

	for i in lattice.count:
		var rho: float = density[tissue[i]]
		var at: Vector3 = positions[i]
		whole += at * rho
		whole_total += rho
		if missing[i] != 0:
			continue
		sum += at * rho
		total += rho
		# Which posed column this cell will be carried by, and where it sits
		# across and up that column. The ledger cell already answers both: it is
		# `column * rows + row` by construction, and the row is what says which
		# side of the midline the flesh is on.
		var patch: int = patch_of[i]
		var rows: int = BodyPlan.BODY_ROWS if patch == 0 else BodyPlan.LIMB_ROWS
		var cell: int = cell_of[i]
		var slot: int = patch * COLS + (cell / rows)
		if slot < 0 or slot >= _mass.size():
			continue
		_mass[slot] += rho
		_row[slot] += rho * (-1.0 + 2.0 * (float(cell % rows) + 0.5) / float(rows))
		_rise[slot] += rho * lift[i]

	for slot in _mass.size():
		var m: float = _mass[slot]
		if m <= MIN_UNITS:
			_row[slot] = 0.0
			_rise[slot] = 0.0
			continue
		_row[slot] /= m
		_rise[slot] /= m

	units = total
	built_units = whole_total
	body = sum / maxf(total, MIN_UNITS)
	built = whole / maxf(whole_total, MIN_UNITS)
	var length: float = maxf(lattice.axis_length, 0.001)
	along = body.x / length
	built_along = built.x / length
	return true


# --------------------------------------------------------------------- posing ----

## Carries the profile into the world.
##
## Every column of the animal has already been posed this tick — `TissueGrid`
## puts real world corners and a real world height on each cross-section of the
## body and of every limb, because the bite tests need them — so posing a centre
## of gravity is a weighted mean of geometry that already exists. That is the
## whole reason this is affordable per tick: nothing here solves anything, it
## adds up seventy-two points that were solved for another reason.
##
## It also means the answer is honest about things nothing here mentions. A tail
## drooping under its own weight lowers the centre because `Droop` lowered the
## columns it is made of; a spine curled hard to one side carries the weight over
## there because the columns went with it; a leg lifted through a stride takes
## its own mass up with it, because the chain it is posed along is the one the
## gait has just solved.
##
## Everything here is on the **ground plane**, which is the one thing that had to
## be got right and the one thing the obvious implementation gets wrong. A limb's
## patch is posed through `Limb.joints`, and those are the drawn chain — the real
## one with the view's foreshortening already added to it — because what fills a
## leg with tissue is drawing it. A centre of gravity taken off that would be a
## point in the picture, and it would then be compared against feet that are
## nailed to the world. So the limbs are posed off `Limb.plan` instead, which is
## the same chain before the projection, and the heights come off the patch,
## which never had a projection in it at all.
func pose(grid: TissueGrid, limbs: Array[Limb]) -> void:
	posed = false
	if grid == null or units <= MIN_UNITS:
		return
	var flat := Vector2.ZERO
	var up: float = 0.0
	var total: float = 0.0
	# Hoisted for the same reason the census walk hoists its own: a packed array
	# reached through a member lookup is an indirection per read, and this runs on
	# every creature on every tick.
	var mass: PackedFloat32Array = _mass
	var row: PackedFloat32Array = _row
	var rise: PackedFloat32Array = _rise

	var trunk: TissueGrid.Patch = grid.patch(BodyPlan.BODY_KEY)
	if trunk != null and trunk.live:
		var rows: int = trunk.rows
		for col in mini(trunk.cols, COLS):
			var m: float = mass[col]
			if m <= MIN_UNITS:
				continue
			# The column's centre line, and then across it by however far the
			# surviving flesh actually leans. On an intact animal the second term
			# is nothing at all — a body is symmetric and the two flanks cancel —
			# and on one chewed open down one side it is the whole point.
			var near: Vector2 = trunk.vert(col, 0)
			var far: Vector2 = trunk.vert(col, rows)
			flat += ((near + far) * 0.5 + (far - near) * (0.5 * row[col])) * m
			up += ((trunk.mids[col] + trunk.mids[col + 1]) * 0.5 + rise[col]) * m
			total += m

	for limb in limbs:
		var patch: int = AnatomyLattice.PATCH_KEYS.find(limb.key)
		if patch <= 0:
			continue
		var p: TissueGrid.Patch = grid.patch(limb.key)
		if p == null or not p.live:
			continue
		var base_slot: int = patch * COLS
		for col in mini(p.cols, COLS):
			var m: float = mass[base_slot + col]
			if m <= MIN_UNITS:
				continue
			flat += _along_limb(limb, float(col) + 0.5) * m
			up += ((p.mids[col] + p.mids[col + 1]) * 0.5 + rise[base_slot + col]) * m
			total += m

	if total <= MIN_UNITS:
		return
	centre = flat / total
	height = up / total
	posed = true


## Where one of a limb's posed columns sits on the ground plane.
##
## The stations are laid out exactly as `TissueGrid._update_limb` lays them —
## three up the humerus, the elbow, three down the forearm, then the foot cap
## swung out ahead of the toe — because they are the same stations. What differs
## is only which chain they are read off: `plan` rather than `joints`, so the
## answer is where the leg is rather than where it is drawn.
##
## The across-the-limb offset is deliberately not carried. A leg is a few pixels
## wide against an animal that is hundreds long, and the frame it would have to
## be carried in is the one this function exists to avoid.
static func _along_limb(limb: Limb, station: float) -> Vector2:
	var span: float = float(BodyPlan.LIMB_BONE_COLS / 2)
	if station <= span:
		return limb.plan[0].lerp(limb.plan[1], station / span)
	if station <= span * 2.0:
		return limb.plan[1].lerp(limb.plan[2], (station - span) / span)
	# The foot, which is a cap swung forward off the toe along the lower bone.
	var down: Vector2 = limb.plan[2] - limb.plan[1]
	if down.length_squared() < 0.000001:
		return limb.plan[2]
	var out: float = (station - span * 2.0) / float(BodyPlan.LIMB_FOOT_COLS)
	return limb.plan[2] + down.normalized() * (limb.foot_size * sin(PI * 0.5 * out))


# ------------------------------------------------------------- over the feet ----

## Where the animal is being held up, and whether the line comes down inside it.
##
## The support is the convex hull of whatever is actually on the ground: the feet
## that are planted and bearing, and — on a biped slow enough to be leaning on it
## — the tail. Each contact is a patch of ground rather than a point, because a
## foot is, so the hull is grown by the foot's own radius before anything is
## measured against it.
##
## `clearance` is the signed distance from the line to that boundary, positive
## inside. It is deliberately *not* a pass/fail: a walking animal is out over the
## edge of its own feet several times a second — see `Balance`, which is the file
## that had to learn this the hard way — so what this reports is a distance, and
## the consumers decide what a distance is worth. What it is worth to a stance
## being generated and what it is worth to an animal mid-stride are not the same
## number, and neither of them belongs here.
func stand(limbs: Array[Limb], scale: float, prop: Vector2 = Vector2.INF) -> void:
	_prints.clear()
	var pad: float = 0.0
	base = Vector2.ZERO
	for limb in limbs:
		if limb.severed or limb.carried or not limb.bearing or limb.stepping:
			continue
		if limb.carry < 0.0001:
			continue
		_prints.append(limb.planted)
		pad = maxf(pad, limb.foot_radius(scale))
	# A tail a biped is genuinely resting on is a fifth foot, and the support it
	# adds is the reason a kangaroo can stand still at all. It arrives as a point
	# like any other because that is what it is — see Locomotion.tail_prop, which
	# is the only thing that decides whether there is one.
	if prop.x < INF:
		_prints.append(prop)
	feet = _prints.size()
	if feet == 0:
		span = 0.0
		clearance = -INF
		overhang = Vector2.ZERO
		return
	for point in _prints:
		base += point
	base /= float(feet)
	span = 0.0
	for point in _prints:
		span = maxf(span, point.distance_to(base))
	span += pad
	clearance = _inside(centre if posed else base, pad)
	overhang = Vector2.ZERO
	if clearance < 0.0:
		var out: Vector2 = (centre if posed else base) - base
		if out.length_squared() > 0.000001:
			overhang = out.normalized() * -clearance


## Signed distance from a point to the support, positive inside.
##
## Three cases and they are three different shapes, because a support genuinely
## is: one contact is a disc, two are a capsule, three or more are a polygon. The
## middle one is what a biped stands on and what every quadruped passes through
## twice a stride, so it is not a degenerate case to be tidied away — a body on
## two feet has no support *across* the line between them beyond the width of the
## feet themselves, and that is exactly why it has to keep moving.
func _inside(point: Vector2, pad: float) -> float:
	if feet == 1:
		return pad - point.distance_to(_prints[0])
	if feet == 2:
		return pad - _to_segment(point, _prints[0], _prints[1])
	var hull: PackedVector2Array = _hull(_prints)
	if hull.size() < 3:
		var worst: float = INF
		for i in hull.size():
			worst = minf(worst, _to_segment(point, hull[i],
				hull[(i + 1) % hull.size()]))
		return pad - worst
	# The hull comes back counter-clockwise, so the cross product of an edge with
	# the vector to the point is positive on the inside of every edge at once.
	# Whichever edge is nearest to failing that is how much support is left.
	var least: float = INF
	for i in hull.size():
		var a: Vector2 = hull[i]
		var edge: Vector2 = hull[(i + 1) % hull.size()] - a
		var len: float = edge.length()
		if len < 0.0001:
			continue
		least = minf(least, (edge.x * (point.y - a.y) - edge.y * (point.x - a.x)) / len)
	return (0.0 if least == INF else least) + pad


static func _to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var edge: Vector2 = b - a
	var len2: float = edge.length_squared()
	if len2 < 0.000001:
		return point.distance_to(a)
	return point.distance_to(a + edge * clampf((point - a).dot(edge) / len2, 0.0, 1.0))


## The convex hull of the contacts, wound so the inside of every edge is the
## left of it — which is what lets `_inside` be one cross product per edge.
##
## Gift-wrapping, because there are five points at the very most and this is the
## version that can be read and believed: start at the leftmost contact, and
## repeatedly take the one contact that leaves every other on its left. A sorted
## chain is asymptotically better and there is nothing here to be asymptotic
## about.
static func _hull(points: PackedVector2Array) -> PackedVector2Array:
	var n: int = points.size()
	var start: int = 0
	for i in n:
		if points[i].x < points[start].x \
				or (points[i].x == points[start].x and points[i].y < points[start].y):
			start = i
	var out := PackedVector2Array()
	var at: int = start
	for _step in n:
		out.append(points[at])
		var next: int = (at + 1) % n
		for c in n:
			if c == at:
				continue
			var side: float = _turn(points[at], points[next], points[c])
			# Strictly to the right: that candidate wraps tighter. Exactly on the
			# line: take the further one, or a collinear contact nearer the middle
			# would clip the one beyond it off the hull entirely.
			if side < 0.0 or (side == 0.0
					and points[at].distance_squared_to(points[c])
						> points[at].distance_squared_to(points[next])):
				next = c
		at = next
		if at == start:
			break
	return out


static func _turn(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


# ------------------------------------------------------ what the build must do ----

## The least angle a trunk with nothing under its shoulders has to be carried at
## for the animal to be standing rather than falling forward.
##
## A two-legged body is one beam over one fulcrum. Everything in front of the hip
## — the trunk, the neck, the head, the arms — hangs off one end of it, and
## everything behind — the tail — off the other; the hip is the only thing
## holding either up. Where the weight of the whole comes out along that beam is
## `along`, and the distance from the hip to it is the lever the animal is
## standing against.
##
## Rearing is what shortens that lever, and the geometry is the entire argument:
## a beam pitched by θ reaches `cos θ` as far forward as it did lying level. It
## cannot move the centre to the *other* side of the hip and nothing here pretends
## it can — what it does is bring it in, and at ninety degrees it brings it in
## all the way. So the angle a biped must carry is the one at which the overhang
## has shrunk to something the feet can be placed under, and it falls out of one
## inverse cosine.
##
## Which is why nothing in the file names a species. A tyrannosaur's tail very
## nearly balances the rest of it, so the lever is short, and it stands with its
## back level because it can. A kangaroo's trunk is much the heavier end, so the
## lever is long, and it has to rear until the arithmetic lets it stop. The
## difference between the two animals is where their mass is, which is the one
## thing this file measures.
##
## `hip` is the hind girdle's station in the same units as `along`, `length` the
## clipped body in px, and `ahead` how far in front of that girdle a hind foot
## can actually be planted. Returned in degrees, to sit beside the trait it is a
## floor under.
##
## `along` runs snout to tail, so a centre of gravity *ahead* of the hip is one
## with the smaller number — which is the ordinary case and the whole reason a
## biped has to lean back at all.
func carriage_deg(hip: float, length: float, ahead: float) -> float:
	var lever: float = (hip - built_along) * length
	if lever <= 0.0 or ahead >= lever:
		return 0.0
	return rad_to_deg(acos(clampf(ahead / maxf(lever, 0.0001), 0.0, 1.0)))


## Where a girdle standing on its own has to put its feet: under the weight,
## every time, as a fraction of the fore-and-aft reach they are placed out of.
##
## This is the one place the fore/aft bias is derived outright rather than held
## to a floor, and the reason is that there is nothing to negotiate with. A
## quadruped's two girdles each keep one side of the weight and the species picks
## how the pair of them bracket it; a two-legged animal has one pair of feet and
## one centre of gravity, and statics puts the first under the second. There is no
## style left in it — a biped standing with its feet behind its own weight is not
## making a choice, it is beginning to fall, and it was drawn doing exactly that
## for as long as the stance was an authored number.
##
## `carried` is the angle the trunk is actually held at, because a reared body is
## a foreshortened one: the weight comes down `cos` of the way along the beam it
## would if the animal were lying level, which is the same cosine `carriage_deg`
## inverts and has to be the same one or the two would disagree about the animal
## they are describing.
func stand_under(hip: float, length: float, reach: float, carried: float) -> float:
	if reach <= 0.0001:
		return 0.0
	return clampf((hip - built_along) * length * cos(carried) / reach, -1.0, 1.0)


## The least a girdle's resting feet have to be placed out from their own sockets
## for the weight to be inside them — as a fraction of the fore-and-aft reach
## they are placed out of, which is the unit the foot bias is already quoted in.
##
## That bias is where a species chooses to stand: a little forward at the
## shoulder, a little back at the hip, which is what puts a quadruped's feet at
## the four corners of its own weight. It is a choice, and it is allowed to be —
## right up to the point where it leaves every foot on one side of the centre of
## gravity, which is not a stance but a fall in progress.
##
## So this is a floor and never a replacement. On any build whose centre already
## sits between its girdles — which is every quadruped, and every preset in the
## file — the weight is behind the shoulder and in front of the hip, both answers
## are zero, and not one foot moves. It bites on exactly the builds it should: a
## creature carrying its whole mass out in front of its shoulders has to reach its
## forefeet past its own head to stand up, and one that is all tail has to plant
## its hind feet behind the weight. Neither is a rule about a species; both are
## the same subtraction.
##
## `girdle` is that pair's station along the body in the same units as `along`,
## `length` the clipped body in px, `reach` the fore-and-aft radius the foot is
## placed out of, and `ahead` which side of itself this girdle is responsible
## for — the fore pair keeps the weight behind it, the hind pair keeps it in
## front, and neither is ever asked to fix the other's end of the animal.
func bias_floor(girdle: float, length: float, reach: float, ahead: bool) -> float:
	if reach <= 0.0001:
		return 0.0
	# How far past this girdle the line falls, on the side there is nothing else
	# to hold it. Zero or less and the other girdle has it.
	var past: float = (girdle - built_along) * length if ahead \
		else (built_along - girdle) * length
	if past <= 0.0:
		return 0.0
	# The foot has to get out past it, and then past it by the margin a stance is
	# expected to keep in hand — see KEEP, which is a share of the reach the foot
	# is placed out of and so is already this animal's own margin rather than a
	# distance somebody chose.
	return past / reach + KEEP


## How much of its own support the line is inside, as a share of the support's
## radius: one is a body dead over the middle of its feet, zero is one on the
## edge, negative is one going over. The normalised form of `clearance`, for the
## consumers that want a fraction rather than a distance.
func steadiness() -> float:
	if feet == 0 or span <= 0.0001:
		return -1.0
	return clampf(clearance / span, -1.0, 1.0)
