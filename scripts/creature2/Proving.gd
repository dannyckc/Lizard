## The proving ground — one marked-off corner of the lab with something to walk
## over, something to walk into, something to walk under, and two other animals
## standing in it.
##
## The lab's floor is otherwise empty on purpose (`V2Lab`), and an empty floor is
## the right place to read a gait against. But almost everything the locomotion
## loop claims is a claim about *contact*: a step is climbed by feet landing on
## the higher surface, a wall is braked for, a brink is balked at, an overhang is
## walked under, a body knocked off balance steps to catch itself. None of that
## can be seen on a plain. So the furniture lives here, in one place, laid out in
## two lanes — the course along the north, the specimen bays along the south —
## rather than scattered across the world where it would also be underfoot every
## time somebody wanted a plain to walk on.
##
## Everything in the zone is placed relative to `at`, so the whole area moves as
## one, and it is placed **clear of the corridor the probes drive down**: they
## walk the lab's own creature east from the origin, and this sits south of that
## by more than a body length. `MotionProbe` clears the field outright; nothing
## else has to know the zone exists.
##
## What is in it:
##
##   * **the steps** — a flight up and back down, each tread well inside what a
##     fore leg can climb in stride, with a landing at the top wide enough for
##     the whole animal to stand on;
##   * **the boulder** and **the post** — both taller than a leg can climb, so
##     both are solids: one broad enough to slide along, one narrow enough to
##     catch a shoulder and spin the body;
##   * **the overhang** — based above the animal's back, so a walk passes under
##     it and only the height gate says why;
##   * **the resident** — a living animal with nothing asked of it, keeping its
##     balance and its post (`Repose`);
##   * **the carcass** — the same animal collapsed and left to settle.
##
## Nothing here is a system. It is a room with things in it, and every one of
## them is expressed in the terms the world already had: `Terrain.add` for the
## furniture, a plain `Creature2` for each animal, `Impetus`'s shove seam for the
## resident's restlessness. The zone owns no rules — if it did, what it was
## testing would be itself.
class_name Proving
extends Node2D

const INK := Color("14140f")
const MARK := Color(INK, 0.30)
const LABEL := Color(INK, 0.45)
const CAPTION := Color(INK, 0.30)

## Half the zone's extent, px. The boundary is drawn on it and everything inside
## is placed against it.
const HALF := Vector2(330.0, 250.0)
## How long each corner bracket's arms are.
const CORNER: float = 34.0

## The two lanes, as offsets from the zone's centre: the course to the north, the
## specimen bays to the south.
const COURSE: float = -120.0
const BAYS: float = 120.0
## One caption baseline per lane, clear of the longest shadow the lane throws.
const COURSE_CAPTION: float = COURSE + 140.0
const BAYS_CAPTION: float = BAYS + 78.0

## How much each tread rises, px. Kept well inside `Outlook.CLIMB_SHARE` of the
## shorter (fore) leg — a step a leg cannot make is a wall, and there is already
## a wall in the zone.
const TREAD: float = 7.0
## The flight, as the radius of each tread from the ground up. Concentric rather
## than in a rank: `surface` answers with the highest thing a foot is over, so
## nested discs *are* a flight of stairs and there is no stair anywhere in the
## code — and a mound reads as one in the picture where a rank of discs reads as
## a rank of discs, because the treads nest inside each other's outlines instead
## of hiding behind them.
##
## Walked through the middle the profile is 7 → 14 → 21 → 14 → 7, so one crossing
## is a climb *and* a descent, and the top tread is wide enough for the whole
## animal to stand on rather than to teeter across.
const TREADS: Array[float] = [104.0, 72.0, 44.0]
const STEPS_AT: float = -190.0


@export var at: Vector2 = Vector2(20.0, 400.0)
## Built on `_ready`. Off, the zone is an empty marked rectangle — which is what
## a probe that wants the plain back should ask for, rather than clearing the
## terrain from underneath it.
@export var furnished: bool = true

var terrain: Terrain
## The two animals standing in the bays. Neither is driven by anything.
var resident: Creature2
var carcass: Creature2

var _idle: Repose = Repose.new()
var _captions: Array[Dictionary] = []
var _font: Font


func _ready() -> void:
	terrain = get_tree().get_first_node_in_group("terrain") as Terrain
	_font = load("res://assets/fonts/IBMPlexMono-Regular.ttf") as Font
	# On the floor: the zone is a marking painted on the ground, so the terrain
	# standing on it and every animal walking over it are both above.
	z_index = 0
	if not furnished:
		return
	_build_course()
	_build_bays()


## The north lane: everything the ground itself does.
func _build_course() -> void:
	if terrain == null:
		return
	# The flight, widest tread first so each one stands on the last. The bottom
	# tread on its own is the single rise the carry's anticipation is easiest to
	# read on: the fore quarters lift before any fore foot has reached it.
	for k in TREADS.size():
		terrain.add(_spot(STEPS_AT, COURSE), TREADS[k], TREAD * float(k + 1),
			0.0, "step")
	terrain.add(_spot(55.0, COURSE), 26.0, 46.0, 0.0, "boulder")
	terrain.add(_spot(140.0, COURSE), 8.0, 30.0, 0.0, "post")
	# Based above the back of a standing cat, which is the whole of why it is an
	# overhang: nobody wrote a doorway, there is simply a base a body is shorter
	# than.
	terrain.add(_spot(240.0, COURSE), 34.0, 16.0, 44.0, "overhang")

	_caption(STEPS_AT, COURSE_CAPTION, "STEPS  7 · 14 · 21")
	_caption(55.0, COURSE_CAPTION, "BOULDER  46")
	_caption(140.0, COURSE_CAPTION, "POST  30")
	_caption(240.0, COURSE_CAPTION, "OVERHANG  44")


## The south lane: the two animals, standing in a row facing the way the lab's
## own creature spawns facing, so the three read against each other.
func _build_bays() -> void:
	resident = _stand(_spot(-175.0, BAYS), 0.0, "Resident")
	_idle.attach(resident, 1.9)

	carcass = _stand(_spot(155.0, BAYS), 0.22, "Carcass")
	# Dead, and dead before the scene opens: collapsed, then run forward on its
	# own clock until the body has finished arriving. A carcass that settles in
	# front of the player is a creature dying, which is a different picture.
	carcass.toggle_collapsed()
	carcass.simulate(2.5)

	_caption(-168.0, BAYS_CAPTION, "RESIDENT  ALIVE, IDLE")
	_caption(162.0, BAYS_CAPTION, "CARCASS  COLLAPSED")


## One animal in a bay: a plain `Creature2` with its own skin, built where it is
## put. Nothing is attached to it that the lab's own creature does not have.
func _stand(where: Vector2, heading: float, name_of: String) -> Creature2:
	var made := Creature2.new()
	made.name = name_of
	made.spawn_position = where
	made.spawn_heading = heading
	var skin := Likeness.new()
	skin.name = "Likeness"
	skin.show_behind_parent = true
	made.add_child(skin)
	add_child(made)
	return made


func _spot(x: float, y: float) -> Vector2:
	return at + Vector2(x, y)


func _caption(x: float, y: float, text: String) -> void:
	_captions.append({"at": _spot(x, y), "text": text})


func _physics_process(delta: float) -> void:
	# The resident's whole behaviour, and it is one line into the physics seam.
	_idle.tick(delta)


# ------------------------------------------------------------------ draw ----

## The zone, marked the way a floor is marked: corner brackets, a hairline
## boundary and small type. Deliberately not a filled plate — the steps in here
## are the colour of the floor on purpose (`Terrain._draw`), and a coloured floor
## under them would take that away.
func _draw() -> void:
	var rect := Rect2(at - HALF, HALF * 2.0)
	draw_rect(rect, Color(INK, 0.05), false, 1.0)
	for corner in [Vector2(-1.0, -1.0), Vector2(1.0, -1.0),
			Vector2(-1.0, 1.0), Vector2(1.0, 1.0)]:
		var p: Vector2 = at + HALF * corner
		draw_line(p, p - Vector2(CORNER * corner.x, 0.0), MARK, 1.4, true)
		draw_line(p, p - Vector2(0.0, CORNER * corner.y), MARK, 1.4, true)

	if _font == null:
		return
	# Outside the boundary rather than inside it: the floor of the zone belongs
	# to what is being tested, and a title laid across the first obstacle is a
	# title in the way.
	draw_string(_font, at + Vector2(-HALF.x, -HALF.y - 18.0),
		"PROVING GROUND", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, LABEL)
	draw_string(_font, at + Vector2(-HALF.x, -HALF.y - 6.0),
		"v2 locomotion · contact · carriage", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 9, CAPTION)
	for caption in _captions:
		var spot: Vector2 = caption["at"]
		draw_string(_font, spot - Vector2(110.0, 0.0), caption["text"],
			HORIZONTAL_ALIGNMENT_CENTER, 220.0, 9, CAPTION)
