## The three views of the moving body — the middle of the Physics HUD.
##
## Three projections of **one** posed armature, and that is the whole design of
## this file. There is no second skeleton, no separate pose for drawing and no
## geometry worked out here: the nodes the solver placed this tick are read once
## and thrown onto three planes.
##
##   * **Sagittal** — along the heading, height up. The animal from the side at
##     whatever bearing it happens to be walking, so a limb reads the same going
##     north as going east.
##   * **Plan** — the world's own XY, which is the view the game is played in.
##   * **Frontal** — across the heading, height up, mirrored so it reads head-on.
##     This is the only pane in which `Keel`'s heel, the lateral width of the
##     support and the righting the legs are spending are legible at all; it is
##     not decoration.
##
## Everything drawn over the skeleton is a number some system published, taken
## through `MotionReadout` — the anchors and their homes, the drift that will
## become a step, the predicted landing, the weight and the support it is or is
## not over, the demand and what was delivered of it. Nothing here decides
## anything and nothing here is smoothed: where a mark looks wrong, the mark is
## right and the loop is what needs looking at.
class_name MotionStage
extends Control

const PAPER := Color("f3f1ec")
const INK := Color("14140f")
## The one accent. Everything the body is *doing* — the press it is standing on,
## the step it is about to take, the edge it is going over — is in this ink.
const RED := Color("8e1b12")

## How much of the stage's height the sagittal band takes; the plan and the
## frontal share what is left.
const TOP_SHARE: float = 0.44
## ...and how much of the width the plan takes from the frontal. The plan is the
## wider because it is the only view with two horizontal axes in it.
## Both shares, and the air between the panes, are the handoff's own
## (`Physics HUD.dc.html`, `_draw`), opened up a little: every pane here fits on
## its *height*, so a point of height share is worth more than a point of width.
const PLAN_SHARE: float = 0.60
const GUTTER: float = 16.0

## Air kept around the animal inside a pane, as a share of the extent it is
## fitted to. Two of them, because the two axes are not the same problem: an
## animal walks along the pane and needs room ahead of and behind itself, and it
## only ever stands up in it. The height any pane is fitted to is a rearing worst
## case (`_fit`) that the posed body uses about two thirds of, so the air over it
## is thin on purpose.
const MARGIN: float = 1.24
const MARGIN_UP: float = 1.14
## How much of the body's own length the plan keeps across itself — turning room
## for the weight and its trail, since the animal in plan is barely wider than
## its own girdles.
const PLAN_LATERAL: float = 0.45
const SCALE_MIN: float = 0.5
const SCALE_MAX: float = 3.2

## The pane's own furniture: the title band across its head, and how far its
## ground line stands off its foot. Both are air the animal is never drawn into.
## The ground stands off by a share of a tall pane rather than a flat 26 px, so
## the animal sits in the middle of the paper it has been given instead of on the
## floor of it — a body pinned to the bottom edge of a deep pane is the whole of
## what made these views read as cramped.
const HEADER: float = 22.0
const BASELINE: float = 34.0
const BASELINE_SHARE: float = 0.15

## The trail's length, samples — a second and a half of weight at 60 Hz.
const TRAIL: int = 90

## Ground squares on the plan, world px.
const GRID: float = 24.0

## How long a footfall ring stands after the foot lands, seconds.
const RING_LIFE: float = 0.7

## Hairlines, beads and the alpha the far side of the body is drawn at.
const NEAR: float = 0.88
const FAR: float = 0.30
const BEAD: float = 2.3


var creature: Creature2
var readout: MotionReadout

## What is drawn. The three panes are toggled together with the hull and the
## trails from the drawer's own switches.
var show_sagittal: bool = true
var show_plan: bool = true
var show_frontal: bool = true
var show_hull: bool = true
var show_trails: bool = true

var _font: Font
## Where each pane stands and how the body is fitted into it, worked out once per
## resize rather than per stroke.
var _sag := Rect2()
var _plan := Rect2()
var _front := Rect2()
var _sag_scale: float = 1.0
var _plan_scale: float = 1.0
var _front_scale: float = 1.0
## The camera: the body's own middle, and the ground under it.
var _eye := Vector2.ZERO
var _floor: float = 0.0
var _fwd := Vector2.RIGHT
var _perp := Vector2.UP
var _no_steps: Array[MotionReadout.Step] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func set_ui_font(font: Font) -> void:
	_font = font


func _ready() -> void:
	resized.connect(_layout)
	_layout()


# ------------------------------------------------------------------- layout ----

func _layout() -> void:
	var top: float = maxf((size.y - GUTTER) * TOP_SHARE, 40.0)
	var low: float = maxf(size.y - GUTTER - top, 40.0)
	var wide: float = maxf((size.x - GUTTER) * PLAN_SHARE, 40.0)
	_sag = Rect2(0.0, 0.0, size.x, top)
	_plan = Rect2(0.0, top + GUTTER, wide, low)
	_front = Rect2(wide + GUTTER, top + GUTTER, maxf(size.x - wide - GUTTER, 40.0), low)
	queue_redraw()


## How many world px go to the screen px in each pane: the animal's own extent
## fitted to the paper, once, so the picture does not breathe as the body moves.
## Deliberately not re-fitted per frame — a view whose scale chases the pose is a
## view in which nothing can be compared with anything.
func _fit() -> void:
	if creature == null or creature.body == null:
		return
	var spec: BodySpec = creature.body
	var long: float = spec.trunk_length + spec.neck_length + spec.head_offset \
		+ spec.tail_length
	var tall: float = maxf(spec.stance_height(false), spec.stance_height(true)) \
		+ spec.neck_length + spec.skull_radius * 2.0
	var wide: float = maxf(creature.armature.fore_half, creature.armature.hind_half) \
		* 2.0 + maxf(spec.fore_leg_length, spec.hind_leg_length) * 0.6
	_sag_scale = _pick(_sag, long, tall, MARGIN_UP)
	_plan_scale = _pick(_plan, long, long * PLAN_LATERAL, MARGIN)
	_front_scale = _pick(_front, wide, tall, MARGIN_UP)


func _pick(pane: Rect2, along: float, up: float, up_air: float) -> float:
	return clampf(minf(pane.size.x / maxf(along * MARGIN, 1.0),
		pane.size.y / maxf(up * up_air, 1.0)), SCALE_MIN, SCALE_MAX)


## Where the ground runs in a pane the animal stands up in.
func _ground_y(pane: Rect2) -> float:
	return pane.end.y - maxf(BASELINE, pane.size.y * BASELINE_SHARE)


# ------------------------------------------------------------- projections ----
# The one place a world point becomes a screen point, three times over. Each
# takes the armature's own Vector3 — plan in XY, height in Z — because that is
# what every system in the body already speaks.

func _to_sag(p: Vector3) -> Vector2:
	var along: float = (Vector2(p.x, p.y) - _eye).dot(_fwd)
	return Vector2(_sag.position.x + _sag.size.x * 0.5 + along * _sag_scale,
		_ground_y(_sag) - (p.z - _floor) * _sag_scale)


func _to_plan(p: Vector3) -> Vector2:
	return _plan.get_center() + (Vector2(p.x, p.y) - _eye) * _plan_scale


func _to_front(p: Vector3) -> Vector2:
	var across: float = (Vector2(p.x, p.y) - _eye).dot(_perp)
	return Vector2(_front.position.x + _front.size.x * 0.5 - across * _front_scale,
		_ground_y(_front) - (p.z - _floor) * _front_scale)


func _at(i: int) -> Vector3:
	return creature.armature.pos[i]


# --------------------------------------------------------------------- draw ----

func _draw() -> void:
	if creature == null or creature.armature == null \
			or creature.armature.node_count() == 0:
		return
	readout = creature.motion_readout()
	var a: Armature = creature.armature
	# The middle of the *animal*, nose to tail tip — not the middle of its trunk.
	# A cat is most of a metre of tail behind its hips, and a view centred on the
	# girdles hangs all of it off the edge of the pane.
	var tail: Armature.Chain = a.chain(BodySchema.TAIL)
	_eye = (a.plan(a.head_index())
		+ a.plan(tail.nodes[tail.nodes.size() - 1])) * 0.5
	_floor = creature.ground_at(_eye)
	_fwd = Vector2.RIGHT.rotated(creature.heading)
	_perp = Vector2(-_fwd.y, _fwd.x)
	_fit()

	if show_sagittal:
		_frame(_sag, "SAGITTAL", "ALONG HEADING", _sag_scale)
		_draw_sagittal()
	if show_plan:
		_frame(_plan, "PLAN", "WORLD XY", _plan_scale)
		_draw_plan()
	if show_frontal:
		_frame(_front, "FRONTAL", "HEAD-ON", _front_scale)
		_draw_frontal()


## A pane's head: what the view is, which way it faces, and — hard against the
## far corner, where it is out of the picture's way — how magnified it is. Three
## short things rather than the handoff's sentence, because the ground line, the
## grid and the animal in the middle of it say the rest.
func _frame(pane: Rect2, label: String, facing: String, scale: float) -> void:
	draw_rect(pane, Color(INK, 0.13), false, 1.0)
	if _font == null:
		return
	draw_string(_font, pane.position + Vector2(12.0, 16.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color(INK, 0.72))
	var wide: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 10).x
	draw_string(_font, pane.position + Vector2(24.0 + wide, 16.0), facing,
		HORIZONTAL_ALIGNMENT_LEFT, pane.size.x - 90.0 - wide, 9, Color(INK, 0.30))
	draw_string(_font, Vector2(pane.end.x - 58.0, pane.position.y + 16.0),
		"×%.2f" % scale, HORIZONTAL_ALIGNMENT_RIGHT, 46.0, 9, Color(INK, 0.30))


# ----------------------------------------------------------------- sagittal ----

func _draw_sagittal() -> void:
	var a: Armature = creature.armature
	_ground_line(_sag, true)
	if show_trails:
		_trail(_to_sag, _sag)
	# The far side of the animal first and faint, then the near side over it —
	# the one thing that makes a diagonal pair legible as a diagonal pair.
	for limb in a.limbs:
		if limb.side > 0.0:
			_limb(limb, _to_sag, FAR)
	_axial(_to_sag, NEAR)
	for limb in a.limbs:
		if limb.side <= 0.0:
			_limb(limb, _to_sag, NEAR)
	for step in _steps():
		_footwork(step, _to_sag, true)
	_weight(_to_sag)
	_rise_ahead()
	# The one reading the panel round this stage has no other way of stating: how
	# high each girdle is being carried, which is the sagittal's own subject.
	_note(_sag, "CARRY  FORE %.1f  ·  HIND %.1f" % [
		a.fore_carry - _floor, a.hind_carry - _floor])


## The ground the animal is actually standing on, sampled across the pane — a
## profile in the sagittal, a level in the frontal, and in both the terrain's own
## answer rather than a line at zero.
func _ground_line(pane: Rect2, along: bool) -> void:
	var scale: float = _sag_scale if along else _front_scale
	var dir: Vector2 = _fwd if along else _perp
	var base: float = _ground_y(pane)
	var line := PackedVector2Array()
	var steps: int = int(pane.size.x / 6.0) + 1
	for i in steps + 1:
		var x: float = pane.position.x + float(i) * pane.size.x / float(steps)
		var off: float = (x - (pane.position.x + pane.size.x * 0.5)) / scale
		if not along:
			off = -off
		var z: float = creature.ground_at(_eye + dir * off)
		line.append(Vector2(x, base - (z - _floor) * scale))
	draw_polyline(line, Color(INK, 0.30), 1.0, true)
	# Travel ticks: hatches pinned to the world, so the ground visibly moves past
	# a body that is moving and stays put under one that is not.
	if not along:
		return
	var pitch: float = GRID * scale
	if pitch < 6.0:
		return
	var travel: float = fposmod(_eye.dot(_fwd) * scale, pitch)
	var x0: float = pane.position.x - travel
	while x0 < pane.end.x:
		if x0 > pane.position.x:
			draw_line(Vector2(x0, base + 4.0), Vector2(x0, base + 10.0),
				Color(INK, 0.13), 1.0)
		x0 += pitch


## The caret over the ground the leading girdle is about to cross, with what it
## rises by — `Outlook`'s prediction, which is the term the carries anticipate on
## and the one thing in the loop that happens before the body gets there.
func _rise_ahead() -> void:
	if readout == null or absf(readout.fore_rise) < 0.5:
		return
	var a: Armature = creature.armature
	var look: float = maxf(creature.body.trunk_length * 0.5,
		readout.speed * Outlook.HORIZON)
	var at: Vector2 = a.plan(a.withers_index()) + _fwd * look
	var q: Vector2 = _to_sag(Vector3(at.x, at.y, creature.ground_at(at)))
	draw_polyline(PackedVector2Array([q + Vector2(-4.0, -7.0), q + Vector2(0.0, -12.0),
		q + Vector2(4.0, -7.0)]), RED, 1.0, true)
	if _font != null:
		draw_string(_font, q + Vector2(-16.0, -16.0),
			"RISE +%.0f" % readout.fore_rise, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8,
			Color(RED, 0.8))


# --------------------------------------------------------------------- plan ----

func _draw_plan() -> void:
	var a: Armature = creature.armature
	_grid()
	if show_hull:
		_hull()
	_rings()
	if show_trails:
		_trail(_to_plan, _plan)
	_axial(_to_plan, NEAR)
	# The girdles, as the bars the sockets hang off: the plan is where a body
	# turning about its shoulders reads as one.
	for fore in [true, false]:
		var g: int = a.withers_index() if fore else a.pelvis_index()
		var out: Vector2 = a.perp[g] * (a.fore_half if fore else a.hind_half)
		var p: Vector2 = a.plan(g)
		draw_line(_to_plan(Vector3(p.x + out.x, p.y + out.y, 0.0)),
			_to_plan(Vector3(p.x - out.x, p.y - out.y, 0.0)), Color(INK, 0.5), 1.0, true)
	for limb in a.limbs:
		_limb(limb, _to_plan, 0.5)
	for step in _steps():
		_footwork(step, _to_plan, false)
		_foot_name(step)
	_weight(_to_plan)
	_vectors()


func _grid() -> void:
	var pitch: float = GRID * _plan_scale
	if pitch < 7.0:
		return
	var origin: Vector2 = _to_plan(Vector3.ZERO)
	var x: float = _plan.position.x + fposmod(origin.x - _plan.position.x, pitch)
	while x < _plan.end.x:
		var y: float = _plan.position.y + fposmod(origin.y - _plan.position.y, pitch)
		while y < _plan.end.y:
			draw_rect(Rect2(x, y, 1.0, 1.0), Color(INK, 0.14))
			y += pitch
		x += pitch


## The support: the planted prints, in the order `Poise` walks its own hull, with
## the wash that makes "inside" read as a place rather than as a number.
func _hull() -> void:
	if readout == null or readout.hull.size() < 2:
		return
	var ring := PackedVector2Array()
	for p in readout.hull:
		ring.append(_to_plan(Vector3(p.x, p.y, 0.0)))
	if ring.size() > 2:
		draw_colored_polygon(ring, Color(INK, 0.045))
	ring.append(ring[0])
	_dashed(ring, Color(INK, 0.45), 3.0)


## Where a foot has just come down: a ring that opens and fades. The footfall, as
## an event — the one thing in the picture that says *when*.
func _rings() -> void:
	for step in _steps():
		if step.swinging or step.since > RING_LIFE:
			continue
		var age: float = step.since / RING_LIFE
		draw_arc(_to_plan(step.anchor), (3.0 + age * 26.0) * _plan_scale * 0.5,
			0.0, TAU, 20, Color(RED, 0.5 * (1.0 - age)), 1.0, true)


## The three accelerations, from the weight: where the body is going, what the
## velocity error demanded, and what the feet delivered of it. Where the red is
## shorter than the dashes, the animal is being held back by its own mass.
func _vectors() -> void:
	if readout == null:
		return
	var at: Vector2 = _to_plan(_com())
	var v: float = 0.20 * _plan_scale
	var acc: float = 0.055 * _plan_scale
	draw_line(at, at + readout.velocity * v, Color(INK, 0.75), 1.6, true)
	_dashed(PackedVector2Array([at, at + readout.demanded * acc]),
		Color(INK, 0.35), 2.0)
	draw_line(at, at + readout.thrust * acc, RED, 1.8, true)


func _foot_name(step: MotionReadout.Step) -> void:
	if _font == null:
		return
	var q: Vector2 = _to_plan(step.anchor if not step.swinging else step.land)
	draw_string(_font, q + Vector2(7.0, -6.0), str(step.name),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(INK, 0.4))


# ------------------------------------------------------------------ frontal ----

func _draw_frontal() -> void:
	var a: Armature = creature.armature
	_ground_line(_front, false)
	_lateral_base()
	if show_trails:
		_trail(_to_front, _front)
	for limb in a.limbs:
		if not _is_fore(limb):
			_limb(limb, _to_front, FAR)
	# The two girdle bars are the whole of the heel in this view: level with both
	# sides down, tilted the instant `Keel` has the body over.
	for fore in [false, true]:
		var g: int = a.withers_index() if fore else a.pelvis_index()
		var out: float = a.fore_half if fore else a.hind_half
		var p: Vector2 = a.plan(g)
		var high: Vector3 = Vector3(p.x + a.perp[g].x * out * cos(a.roll),
			p.y + a.perp[g].y * out * cos(a.roll), a.pos[g].z - out * sin(a.roll))
		var low: Vector3 = Vector3(p.x - a.perp[g].x * out * cos(a.roll),
			p.y - a.perp[g].y * out * cos(a.roll), a.pos[g].z + out * sin(a.roll))
		draw_line(_to_front(high), _to_front(low),
			Color(INK, 0.85 if fore else 0.4), 2.0 if fore else 1.4, true)
		if _font != null:
			var mid: Vector2 = (_to_front(high) + _to_front(low)) * 0.5
			draw_string(_font, mid + Vector2(maxf(out, 6.0) * _front_scale + 5.0, 3.0),
				"F" if fore else "H", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8,
				Color(INK, 0.5 if fore else 0.3))
	_axial(_to_front, 0.55)
	for limb in a.limbs:
		if _is_fore(limb):
			_limb(limb, _to_front, NEAR)
	for step in _steps():
		_footwork(step, _to_front, false)
	_weight(_to_front)
	_lateral_margin()
	_righting()
	_dial()
	# ...and the frontal's own: how wide the feet stand *across* the animal, which
	# is the base a heel turns about and is a different number from the plan's.
	if readout != null:
		_note(_front, "LATERAL BASE %.0f PX  ·  MARGIN %s" % [
			_base_width(), _margin_word()])


## How wide the planted feet stand across the body — the base a heel turns about,
## which the plan cannot show and the sagittal has no axis for.
func _lateral_base() -> void:
	if readout == null or readout.hull.size() < 1:
		return
	var lo: float = INF
	var hi: float = -INF
	for p in readout.hull:
		var across: float = (p - _eye).dot(_perp)
		lo = minf(lo, across)
		hi = maxf(hi, across)
	var base: float = _ground_y(_front)
	var xa: float = _front.position.x + _front.size.x * 0.5 - hi * _front_scale
	var xb: float = _front.position.x + _front.size.x * 0.5 - lo * _front_scale
	draw_line(Vector2(xa, base + 9.0), Vector2(xb, base + 9.0), Color(RED, 0.4), 1.0)
	draw_line(Vector2(xa, base + 6.0), Vector2(xa, base + 12.0), Color(RED, 0.4), 1.0)
	draw_line(Vector2(xb, base + 6.0), Vector2(xb, base + 12.0), Color(RED, 0.4), 1.0)


## The plumb line against the nearer edge of that base — how far the weight is
## from going over the foot it would turn about.
func _lateral_margin() -> void:
	if readout == null or readout.hull.size() < 2:
		return
	var lo: float = INF
	var hi: float = -INF
	for p in readout.hull:
		var across: float = (p - _eye).dot(_perp)
		lo = minf(lo, across)
		hi = maxf(hi, across)
	var here: float = (Vector2(_com().x, _com().y) - _eye).dot(_perp)
	var edge: float = lo if (here - lo) < (hi - here) else hi
	var mid: float = _front.position.x + _front.size.x * 0.5
	var y: float = _ground_y(_front) + 16.0
	var margin: float = minf(here - lo, hi - here)
	var ink: Color = RED if margin < 0.0 else Color(INK, 0.35)
	draw_line(Vector2(mid - here * _front_scale, y),
		Vector2(mid - edge * _front_scale, y), ink, 1.0)


## What the legs are spending to hold the body level, against what they have —
## an arrow at the withers whose length is the demand and whose stub is the
## ceiling it is clamped to. Nothing beyond the stub is available at any price.
func _righting() -> void:
	if readout == null or absf(readout.righting) < 0.01:
		return
	var a: Armature = creature.armature
	var at: Vector2 = _to_front(a.pos[a.withers_index()]) + Vector2(0.0, -14.0)
	var full: float = maxf(readout.righting_ceiling, 0.0001)
	var share: float = clampf(readout.righting / full, -1.0, 1.0)
	var run: float = -signf(share) * (8.0 + absf(share) * 20.0)
	draw_line(at, at + Vector2(run, 0.0), Color(RED, 0.75), 1.6, true)
	draw_line(at + Vector2(run, 0.0), at + Vector2(run - signf(run) * 4.0, -3.0),
		Color(RED, 0.75), 1.6, true)


## The keel dial: how far over the body is, with what the legs are spending drawn
## against what they have. The outer arc is the whole of the righting the girdles
## can press — it is a ceiling, so it is always the full arc — and the red inside
## it is the share of that ceiling this tick's demand took. Red all the way round
## is `strained`: the muscle is beaten and only a step will do.
func _dial() -> void:
	if readout == null:
		return
	var r: float = clampf(_front.size.y * 0.07, 14.0, 24.0)
	var centre := Vector2(_front.end.x - r - 22.0, _front.position.y + HEADER + r + 12.0)
	var arc: float = 1.1
	draw_arc(centre, r, 0.0, TAU, 28, Color(INK, 0.22), 1.0, true)
	var lean := Vector2(cos(readout.roll), sin(readout.roll)) * r
	draw_line(centre - lean, centre + lean, Color(INK, 0.8), 1.4, true)
	draw_arc(centre, r + 4.0, -PI * 0.5 - arc, -PI * 0.5 + arc, 20,
		Color(INK, 0.25), 2.0, true)
	var spent: float = 0.0
	if readout.righting_ceiling > 0.0:
		spent = clampf(readout.righting / readout.righting_ceiling, -1.0, 1.0) * arc
	if absf(spent) > 0.01:
		draw_arc(centre, r + 4.0, minf(-PI * 0.5, -PI * 0.5 + spent),
			maxf(-PI * 0.5, -PI * 0.5 + spent), 16,
			RED if not readout.strained else Color(RED, 1.0), 2.0, true)
	# Just the word: the heel's own numbers are in the panel's readings, and a dial
	# that repeats its own readout is a dial that has to be read twice.
	if _font != null:
		draw_string(_font, Vector2(centre.x - r, centre.y + r + 13.0), "KEEL",
			HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 8, Color(INK, 0.4))


func _base_width() -> float:
	if readout == null or readout.hull.is_empty():
		return 0.0
	var lo: float = INF
	var hi: float = -INF
	for p in readout.hull:
		var across: float = (p - _eye).dot(_perp)
		lo = minf(lo, across)
		hi = maxf(hi, across)
	return hi - lo


func _margin_word() -> String:
	if readout == null or readout.hull.size() < 2:
		return "—"
	var lo: float = INF
	var hi: float = -INF
	for p in readout.hull:
		var across: float = (p - _eye).dot(_perp)
		lo = minf(lo, across)
		hi = maxf(hi, across)
	var here: float = (Vector2(_com().x, _com().y) - _eye).dot(_perp)
	return "%.1f PX" % minf(here - lo, hi - here)


# ------------------------------------------------------------ shared marks ----

## The axial line — tail through trunk through neck to the head — as sticks and
## beads, with a bead turned red wherever its joint has run out of room. A
## clamped joint is where stiffness comes from, so it is drawn per joint.
func _axial(proj: Callable, alpha: float) -> void:
	var a: Armature = creature.armature
	var line := PackedVector2Array()
	for i in a.axial:
		line.append(proj.call(_at(i)))
	draw_polyline(line, Color(INK, alpha), 1.7, true)
	for k in a.axial.size():
		var i: int = a.axial[k]
		var slack: float = a.joint_slack(i)
		var capped: bool = is_finite(slack) and slack <= MotionReadout.AT_CAP
		draw_circle(line[k], BEAD if not capped else BEAD + 0.8,
			RED if capped else Color(INK, alpha))
	var head: Vector2 = proj.call(_at(a.head_index()))
	draw_arc(head, maxf(creature.body.skull_radius * 0.8, 3.5), 0.0, TAU, 18,
		Color(INK, alpha), 1.3, true)


## One limb: socket, two joints and the toe, with a joint bead reddened where the
## leg is solving at full stretch — a leg with nothing left to fold is a leg that
## cannot absorb anything, and it is exactly what a stiff walk is made of.
func _limb(limb: Armature.Chain, proj: Callable, alpha: float) -> void:
	var a: Armature = creature.armature
	var line := PackedVector2Array()
	for i in limb.nodes:
		line.append(proj.call(_at(i)))
	draw_polyline(line, Color(INK, alpha), 2.0 if alpha > 0.5 else 1.5, true)
	if alpha <= 0.5:
		return
	for j in range(1, limb.nodes.size() - 1):
		var slack: float = a.joint_slack(limb.nodes[j])
		var capped: bool = is_finite(slack) and slack <= MotionReadout.AT_CAP
		draw_circle(line[j], 3.0 if capped else 2.2, RED if capped else Color(INK, alpha))
		if capped:
			draw_arc(line[j], 6.5, 0.0, TAU, 14, Color(RED, 0.55), 1.0, true)


## What a foot is doing, which is the answer to "why did that foot step".
##
##   * planted — a red bar at the world anchor it is standing on, the hollow
##     square where its body would rather it were, and the drift between them as
##     a dashed line that goes red as the step becomes due;
##   * swinging — a hollow bead on the arc and a dashed run out to the landing
##     it is re-aimed at every tick;
##   * torn off its footing — filled and thickened, because that foot is not
##     support any more whatever it looks like.
func _footwork(step: MotionReadout.Step, proj: Callable, sagittal: bool) -> void:
	var home := Vector3(step.home.x, step.home.y, step.anchor.z)
	if step.swinging:
		var toe: Vector3 = _at(_toe_of(step))
		var here: Vector2 = proj.call(toe)
		draw_arc(here, 3.4, 0.0, TAU, 14, Color(INK, 0.65), 1.2, true)
		var landing: Vector2 = proj.call(step.land)
		_dashed(PackedVector2Array([here, landing]), Color(RED, 0.7), 2.0)
		draw_line(landing + Vector2(-4.5, 0.0), landing + Vector2(4.5, 0.0),
			Color(RED, 0.7), 1.0)
		draw_line(landing + Vector2(0.0, -4.5), landing + Vector2(0.0, 4.5),
			Color(RED, 0.7), 1.0)
		return
	var at: Vector2 = proj.call(step.anchor)
	var ink: Color = RED if step.torn else Color(RED, 0.88)
	if sagittal:
		draw_line(at + Vector2(-6.0, 2.0), at + Vector2(9.0, 2.0), ink,
			3.0 if step.torn else 2.2)
	else:
		draw_circle(at, 4.0 if step.torn else 3.2, ink)
		draw_arc(at, 6.5, 0.0, TAU, 14, Color(RED, 0.35), 1.0, true)
	var want: Vector2 = proj.call(home)
	draw_rect(Rect2(want - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), Color(INK, 0.34),
		false, 1.0)
	if step.urgency > 0.35:
		_dashed(PackedVector2Array([at, want]),
			RED if step.urgency >= 1.0 else Color(INK, 0.34), 2.0)


## The weight: the centre of mass, its plumb line to the ground under it, and the
## cross that makes it findable in a picture full of hairlines.
func _weight(proj: Callable) -> void:
	if readout == null or not creature.poise.posed:
		return
	var com: Vector3 = _com()
	var here: Vector2 = proj.call(com)
	var ground: float = creature.ground_at(Vector2(com.x, com.y))
	var under: Vector2 = proj.call(Vector3(com.x, com.y, ground))
	if here.distance_squared_to(under) > 1.0:
		_dashed(PackedVector2Array([here, under]), Color(INK, 0.35), 2.0)
		draw_line(under - Vector2(4.0, 0.0), under + Vector2(4.0, 0.0), RED, 1.6)
	draw_circle(here, 4.0, INK)
	draw_line(here - Vector2(9.0, 0.0), here + Vector2(9.0, 0.0), Color(INK, 0.5), 1.0)
	draw_line(here - Vector2(0.0, 9.0), here + Vector2(0.0, 9.0), Color(INK, 0.5), 1.0)


## Where the weight has been — the same samples the timeline is drawn from, so
## the trail and the tells cannot disagree about a bob.
##
## The one thing drawn here that is not near the animal: a turn at cruise lays a
## second of weight in an arc wider than the pane, so the trail is cut at the
## pane's own edge and picked up again where it comes back. Cut rather than
## scaled down, because the pane's scale is what makes the three views
## comparable and a trail is not worth losing that for.
func _trail(proj: Callable, pane: Rect2) -> void:
	if readout == null or readout.samples() < 4:
		return
	var run := PackedVector2Array()
	var from: int = maxi(readout.samples() - TRAIL, 0)
	for k in range(from, readout.samples()):
		var q: Vector2 = proj.call(readout.sample_com(k))
		if pane.has_point(q):
			run.append(q)
			continue
		if run.size() > 1:
			draw_polyline(run, Color(INK, 0.17), 1.0, true)
		run.clear()
	if run.size() > 1:
		draw_polyline(run, Color(INK, 0.17), 1.0, true)


func _note(pane: Rect2, text: String) -> void:
	if _font == null:
		return
	draw_string(_font, Vector2(pane.position.x + 12.0, pane.end.y - 8.0),
		text, HORIZONTAL_ALIGNMENT_LEFT, pane.size.x - 22.0, 8, Color(INK, 0.34))


## A dashed run, for everything that is a prediction rather than a fact: a plumb
## line, a drift that has not become a step yet, a landing that is still being
## re-aimed.
func _dashed(points: PackedVector2Array, ink: Color, dash: float) -> void:
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var run: float = a.distance_to(b)
		if run < 0.001:
			continue
		var step: Vector2 = (b - a) / run
		var at: float = 0.0
		while at < run:
			var to: float = minf(at + dash, run)
			draw_line(a + step * at, a + step * to, ink, 1.0)
			at = to + dash


# ------------------------------------------------------------------ helpers ----

func _steps() -> Array[MotionReadout.Step]:
	return readout.steps if readout != null else _no_steps


func _com() -> Vector3:
	if readout == null:
		return Vector3.ZERO
	return Vector3(readout.com.x, readout.com.y, readout.com_height)


func _toe_of(step: MotionReadout.Step) -> int:
	for limb in creature.armature.limbs:
		if limb.name == step.name:
			return limb.nodes[limb.nodes.size() - 1]
	return 0


func _is_fore(limb: Armature.Chain) -> bool:
	return limb.parent_node != creature.armature.pelvis_index()
