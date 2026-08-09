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
const FACE := Color(0.078, 0.078, 0.059, 0.10)
const OUTLINE := Color(0.078, 0.078, 0.059, 0.55)
const RIM := Color(0.078, 0.078, 0.059, 0.30)
const RING_SEGMENTS: int = 26

## Everything in the field. Small and walked linearly: the habitat holds a few
## dozen objects, and a broad phase over that costs more than the test it saves.
var obstacles: Array[Obstacle] = []

var _ring: PackedVector2Array = PackedVector2Array()


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
	queue_redraw()
	return made


func clear() -> void:
	obstacles.clear()
	queue_redraw()


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

## Two outlines and the side between them: the footprint where the object meets
## the ground, the same ring carried up the screen by its own height, and struts
## joining the pair. It is the same projection everything else in the picture
## uses — `Posture.drop` and nothing else — so a rock, a foot and a belly all
## read at one scale, and a tall object leans away from the camera exactly as far
## as a tall animal does.
func _draw() -> void:
	for obstacle in obstacles:
		if obstacle.gone():
			continue
		var girth: float = obstacle.girth()
		var low: Vector2 = obstacle.drawn(obstacle.base())
		var high: Vector2 = obstacle.drawn(obstacle.top())
		var face := PackedVector2Array()
		face.resize(RING_SEGMENTS)
		var floor_ring := PackedVector2Array()
		floor_ring.resize(RING_SEGMENTS + 1)
		for k in RING_SEGMENTS:
			face[k] = high + _ring[k] * girth
			floor_ring[k] = low + _ring[k] * girth
		floor_ring[RING_SEGMENTS] = floor_ring[0]

		# The side, drawn only where it is actually visible: the two struts at the
		# widest points of the ring, which is where the silhouette of a cylinder
		# is. Drawing the whole skirt would read as a barrel rather than as
		# something standing on the floor.
		draw_polyline(floor_ring, RIM, 1.0, true)
		draw_line(floor_ring[0], face[0], OUTLINE, 1.0, true)
		draw_line(floor_ring[RING_SEGMENTS / 2], face[RING_SEGMENTS / 2],
			OUTLINE, 1.0, true)
		draw_colored_polygon(face, FACE)
		var lid := PackedVector2Array(face)
		lid.append(face[0])
		draw_polyline(lid, OUTLINE, 1.2, true)
