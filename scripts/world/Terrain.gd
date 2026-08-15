## The world's third axis, for everything that is not an animal.
##
## Creatures already carry their heights on their own tissue: every cell of the
## lattice knows what band it fills, so a bite finds a knee and a walk finds a
## planted foot. This is the same layer for the ground itself — the rocks, logs,
## ledges and overhangs a body has to get over, under or around — and it is
## deliberately the same three numbers rather than a second geometry system. An
## obstacle is a footprint and a band, a leg is a footprint and a band, and the
## queries below are the ones Volume already answers.
##
## Three questions are asked of this field and nothing else is:
##
##   * **what is under my foot** — `surface`, which is how a gait stops assuming
##     the floor is at zero. It answers with a height and with how much room a
##     foot of that size has up there, because a foothold you are half off is a
##     different answer from one you are on.
##   * **what is in my way** — `push_disc` and `push_capsule`, gated on height
##     exactly as the creature-to-creature pass is, so a body shorter than an
##     overhang's underside walks beneath it and nobody wrote a doorway.
##   * **what is between me and that** — `obstruction`, which is the same band
##     test asked along a line, and the whole of what stops a bite reaching
##     through a boulder.
##
## Nothing here decides whether an obstacle can be crossed. That is a question
## about the animal asking — its legs, its posture, how high it carries its
## shoulder — and it belongs to `Traversal`, which reads this field's answers and
## the body's own dimensions and has no idea what a rock is either.
class_name Terrain
extends Node2D

const INK := Color("14140f")
## The ground's own colour, which is also every object's: see `_draw`.
const PAPER := Color("f3f1ec")
## The tone a raised surface carries over the floor. Kept as a blendable tint
## rather than a finished colour because v1's view blends it to tell a body
## standing on something from a body standing on the floor.
const FACE := Color(0.078, 0.078, 0.059, 0.10)
const RING_SEGMENTS: int = 26

## Where the light is, as the direction its shadows are thrown in — down the
## screen and a little east, so the picture has one sun and every object in it
## agrees about where. `Likeness` throws the animals' shadows straight down the
## screen at the same low contrast; this is that light given a height, because a
## rock's shadow has to say how tall the rock is and an animal's does not.
const SUN := Vector2(0.28, 1.0)
## Shadow length per pixel of height. Under one: a high sun keeps the picture
## legible where a low one would have every boulder painting the floor black.
const SHADOW_RUN: float = 0.80
## The three offset copies a soft edge is made of, and what each one costs the
## floor. They stack, so the darkest part of a shadow is where all three overlap
## — at the foot of the thing casting it, which is where contact reads.
const SHADOW_STEPS: Array[float] = [0.30, 0.65, 1.0]
const SHADOW_INK: float = 0.045

## How much of the floor's brightness a raised top face keeps. Over one by a
## hair: the same colour as the ground, caught a little more squarely by the
## light, which is the whole of why a step is visible at all.
const LIT_GAIN: float = 0.045
## ...and how far up that goes, px of height. Past a low kerb the extra light
## stops meaning anything and the shadow is doing the talking.
const LIT_FULL: float = 40.0

## The visible wall of an object, darkest where it faces the camera squarely and
## fading out at the silhouette edges where the surface turns back toward the
## sky. Shade as a share of the floor's own value.
const WALL_DEEP: float = 0.16
const WALL_EDGE: float = 0.04
## The hairline where a top face meets the floor behind it — the one place the
## silhouette has no wall and no shadow to separate it from the ground.
const CONTOUR := Color(INK, 0.16)
## ...and where the object meets the floor it stands on.
const CONTACT := Color(INK, 0.20)

## Everything in the field. Small and walked linearly: the habitat holds a few
## dozen objects, and a broad phase over that costs more than the test it saves.
var obstacles: Array[Obstacle] = []

var _ring: PackedVector2Array = PackedVector2Array()
## The order the field is painted in — south last, so a near object overdraws
## the one behind it. Rebuilt only when the field changes.
var _order: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	add_to_group("terrain")
	# Under the creatures and over Main's registration grid, which is the order
	# the picture reads in: the ground, the things standing on it, the animals
	# walking between them.
	z_index = 1
	_ring.resize(RING_SEGMENTS)
	for k in RING_SEGMENTS:
		var angle: float = TAU * float(k) / float(RING_SEGMENTS)
		_ring[k] = Vector2(cos(angle), sin(angle))


## Puts one object in the world. `base` above zero is an overhang — something
## with room underneath it — and nothing else about it differs.
func add(at: Vector2, radius: float, height: float, base: float = 0.0,
		kind: String = "rock") -> Obstacle:
	var made := Obstacle.new(at, radius, Vector2(base, base + maxf(height, 0.0)), kind)
	obstacles.append(made)
	_reorder()
	queue_redraw()
	return made


func clear() -> void:
	obstacles.clear()
	_order.clear()
	queue_redraw()


## Painting order: north to south, so a near object overdraws the one standing
## behind it, and low to high where two of them stand at the same distance —
## which is what a flight of steps is, and the higher surface is the one you can
## see. Only `at` and the band decide it and neither moves, so this is settled
## when the field changes rather than every frame.
func _reorder() -> void:
	var by_y: Array[int] = []
	for i in obstacles.size():
		by_y.append(i)
	by_y.sort_custom(func(a: int, b: int) -> bool:
		var first: Obstacle = obstacles[a]
		var second: Obstacle = obstacles[b]
		if absf(first.at.y - second.at.y) > 0.001:
			return first.at.y < second.at.y
		return first.top() < second.top())
	_order = PackedInt32Array(by_y)


# ------------------------------------------------------------- underfoot ----

## What a foot of `foot_radius` put down at `where` would be standing on.
##
## Returns `(height, foothold)`: how far off the world's ground plane the surface
## is, and how much room the foot has on it — negative when it is hanging off the
## edge, and `INF` on the open floor, which has no edge to hang off.
##
## `ceiling` is how high this particular foot can be placed at all, and it is the
## caller's business rather than this field's: a leg reaches as high as the joint
## carrying it and no higher, and that number belongs to the animal. Anything
## whose top is above it is not a surface for *this* foot, so the query walks
## past it and answers with whatever is underneath — which is exactly the
## difference between stepping onto a ledge and walking into a wall.
##
## Objects with room beneath them are skipped the same way and for the same
## reason: a foot cannot stand on the underside of a branch. It stands on the
## floor below it, and the branch becomes a collision for whatever is tall
## enough to meet it.
func surface(where: Vector2, foot_radius: float, ceiling: float = INF) -> Vector2:
	var height: float = 0.0
	var room: float = INF
	for obstacle in obstacles:
		if obstacle.gone() or obstacle.top() > ceiling or obstacle.top() <= height:
			continue
		# Its underside has to be reachable from where the foot already is, or
		# the object is overhead rather than underfoot.
		if obstacle.base() > height:
			continue
		var margin: float = obstacle.foothold(where, foot_radius)
		if margin <= -foot_radius:
			continue
		height = obstacle.top()
		room = margin
	return Vector2(height, room)


# ----------------------------------------------------------------- solid ----

## The displacement that lifts a disc clear of everything in the field. The
## deepest single push rather than the sum: neighbouring objects overlap, and
## adding their corrections would fire a body out of a cluster at several times
## the depth it was actually in.
func push_disc(where: Vector2, radius: float, band: Vector2 = Volume.UNBOUNDED) -> Vector2:
	var deepest: Vector2 = Vector2.ZERO
	for obstacle in obstacles:
		var push: Vector2 = obstacle.push_disc(where, radius, band)
		if push.length_squared() > deepest.length_squared():
			deepest = push
	return deepest


func push_capsule(a: Vector2, b: Vector2, radius: float,
		band: Vector2 = Volume.UNBOUNDED) -> Vector2:
	var deepest: Vector2 = Vector2.ZERO
	for obstacle in obstacles:
		var push: Vector2 = obstacle.push_capsule(a, b, radius, band)
		if push.length_squared() > deepest.length_squared():
			deepest = push
	return deepest


## What stands between `from` and `to` at the heights in `band`, or null when the
## way is clear. A set of jaws asks this before it is allowed to close on
## something on the far side of a rock — and it is the same test the collision
## pass runs, asked along a line instead of about a body.
func obstruction(from: Vector2, to: Vector2, band: Vector2 = Volume.UNBOUNDED) -> Obstacle:
	for obstacle in obstacles:
		if obstacle.blocks(from, to, band):
			return obstacle
	return null


# ---------------------------------------------------------------- cursor ----

## The object under a cursor, picked in the picture rather than on the ground
## plane — because that is where the cursor is. An object's top is drawn lifted
## up the screen by its own height, so a click on the top face of a tall rock
## lands nowhere near the ground the rock is standing on, and a pick that
## compared footprints would answer with whatever is *behind* it instead.
##
## Both faces are offered to the test, so clicking the base of a boulder and
## clicking its top both find the boulder — with different heights, which is the
## point: `Reticle` reads the height back off which face was hit.
func pick(cursor: Vector2, radius: float = 0.0) -> Obstacle:
	var found: Obstacle = null
	var best: float = INF
	for obstacle in obstacles:
		if obstacle.gone():
			continue
		for height in [obstacle.top(), obstacle.base()]:
			var score: float = cursor.distance_to(obstacle.drawn(height)) \
				- obstacle.girth() - radius
			if score < best:
				best = score
				found = obstacle
	return found if best <= 0.0 else null


## Which height on `obstacle` a cursor is pointing at: its top face if the cursor
## is up there, its base if it is down at the foot of it, and somewhere along the
## side between the two.
func height_under(obstacle: Obstacle, cursor: Vector2) -> float:
	if obstacle == null:
		return 0.0
	var top: float = cursor.distance_to(obstacle.drawn(obstacle.top()))
	var base: float = cursor.distance_to(obstacle.drawn(obstacle.base()))
	var total: float = top + base
	if total <= 0.0001:
		return obstacle.top()
	return lerpf(obstacle.top(), obstacle.base(), top / total)


# ------------------------------------------------------------------ draw ----

## Everything in the field is the colour of the floor it stands on, and is
## visible anyway — through its shadow, its shaded wall and the hairline where
## its top face meets the ground behind it.
##
## That is a deliberate choice and not a stylistic one. A step tinted a darker
## grey would be legible without saying anything true: the picture would be
## announcing "obstacle" rather than showing a shape, and a step whose height
## the eye cannot read is a step the player cannot judge. Light is the honest
## channel — a shadow's length *is* the object's height, thrown by the one sun
## in `SUN`, so a 7 px kerb and a 46 px boulder are told apart by looking rather
## than by being coloured differently.
##
## Three marks make an object, painted north to south so a near one overdraws
## the one behind it:
##
##   * **the shadow**, swept from the footprint along the sun by the object's
##     own height — detached from the footprint entirely when the object has
##     room underneath it, which is how an overhang reads as overhead;
##   * **the wall**, the visible south skirt between the base ring and the same
##     ring carried up the screen by its height, shaded deepest where it faces
##     the camera squarely and fading at the silhouette edges;
##   * **the top face**, the floor's own colour with the light it catches for
##     being nearer the sun, closed by a contact line at its foot and a contour
##     where it meets the ground behind it.
##
## The projection is the one everything else in the picture uses — `Carriage.drop`
## and nothing else — so a rock, a foot and a belly all read at one scale.
func _draw() -> void:
	# Anything that reached `obstacles` without going through `add` — a test
	# pushing one on directly — would otherwise be invisible rather than wrong,
	# which is the worst way for this to fail.
	if _order.size() != obstacles.size():
		_reorder()
	for i in _order:
		var obstacle: Obstacle = obstacles[i]
		if not obstacle.gone():
			_cast(obstacle)
	for i in _order:
		var obstacle: Obstacle = obstacles[i]
		if not obstacle.gone():
			_raise(obstacle)


## What the object takes out of the floor. The shadow of a cylinder is its
## footprint swept along the sun by its height — so the length of it is the
## height, read straight off the ground. An object with room underneath sweeps
## from its underside instead of from the floor, and its shadow lifts away from
## its own footprint: the gap in the picture is the gap a body walks through.
func _cast(obstacle: Obstacle) -> void:
	var girth: float = obstacle.girth()
	var sun: Vector2 = SUN.normalized() * SHADOW_RUN
	var near: Vector2 = obstacle.at + sun * obstacle.base()
	var far: Vector2 = obstacle.at + sun * obstacle.top()
	var ink := Color(INK, SHADOW_INK)
	# Three lengths of the same sweep rather than a blur: they overlap most at
	# the foot of the object, which is exactly where contact should read darkest.
	for reach in SHADOW_STEPS:
		draw_colored_polygon(_sweep(near, near.lerp(far, reach), girth), ink)


## The object itself: its wall, its top face, and the two lines that say where
## each of them meets the floor.
func _raise(obstacle: Obstacle) -> void:
	var girth: float = obstacle.girth()
	var low: Vector2 = obstacle.drawn(obstacle.base())
	var high: Vector2 = obstacle.drawn(obstacle.top())

	# The wall, one strip per ring segment and only where a strip faces the
	# camera at all: the north half of a cylinder is behind its own top face.
	# `facing` is 1 for the strip pointing straight at the viewer and 0 at the
	# silhouette edges, where the surface is turning back up toward the sun.
	var quad := PackedVector2Array()
	quad.resize(4)
	for k in RING_SEGMENTS:
		var a: Vector2 = _ring[k]
		var b: Vector2 = _ring[(k + 1) % RING_SEGMENTS]
		var facing: float = (a.y + b.y) * 0.5
		if facing <= 0.0:
			continue
		quad[0] = low + a * girth
		quad[1] = low + b * girth
		quad[2] = high + b * girth
		quad[3] = high + a * girth
		var shade: float = lerpf(WALL_EDGE, WALL_DEEP, facing)
		draw_colored_polygon(quad, PAPER.darkened(shade))

	# The top face: the floor's colour, with the extra light a surface held up
	# closer to the sun catches. Subtle by design — the shadow is what carries
	# the height, and a top face that announced itself would be a colour code.
	var face := PackedVector2Array()
	face.resize(RING_SEGMENTS)
	for k in RING_SEGMENTS:
		face[k] = high + _ring[k] * girth
	draw_colored_polygon(face, PAPER.lightened(
		LIT_GAIN * clampf(obstacle.top() / LIT_FULL, 0.0, 1.0)))

	# ...and the edges the shading cannot make on its own. The rim closes the top
	# face all the way round — most of it is the crease where the face meets its
	# own wall, and it is what keeps the outline from breaking at the flanks
	# where the wall runs out.
	var rim := PackedVector2Array(face)
	rim.append(face[0])
	draw_polyline(rim, Color(INK, 0.07), 1.0, true)
	# Then the contour, where the top face is silhouetted against the ground
	# behind it — there is no wall on that side and both are the same colour —
	# and the contact where the object meets the floor it is standing on, which
	# an overhang does not.
	_edge(high, girth, -1.0, CONTOUR, 1.0)
	if obstacle.base() <= 0.001:
		_edge(low, girth, 1.0, CONTACT, 1.2)
	else:
		_edge(low, girth, 1.0, Color(INK, 0.10), 1.0)


## Half a ring, as a line: the north half for `side` negative, the south half for
## positive. Drawn open rather than closed, because each half is an edge against
## something different and only one of them is ever wanted at a time.
func _edge(centre: Vector2, girth: float, side: float, ink: Color,
		width: float) -> void:
	var arc := PackedVector2Array()
	# Twice round, because the wanted half is contiguous on the ring but not
	# necessarily on the array: whichever vertex the run starts at, one lap from
	# there covers it.
	for k in RING_SEGMENTS * 2:
		var n: Vector2 = _ring[k % RING_SEGMENTS]
		if n.y * side >= 0.0:
			arc.append(centre + n * girth)
			if arc.size() > RING_SEGMENTS:
				break
		elif arc.size() > 1:
			break
		else:
			arc.clear()
	if arc.size() > 1:
		draw_polyline(arc, ink, width, true)


## The outline of a disc dragged from `a` to `b` — a circle when the two are the
## same point and a stadium when they are not. Built in ring order, taking each
## vertex from whichever end of the sweep it leads, so the result is one simple
## polygon and not a hull search.
func _sweep(a: Vector2, b: Vector2, girth: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	poly.resize(RING_SEGMENTS)
	var run: Vector2 = b - a
	for k in RING_SEGMENTS:
		var n: Vector2 = _ring[k]
		poly[k] = (b if n.dot(run) > 0.0 else a) + n * girth
	return poly
