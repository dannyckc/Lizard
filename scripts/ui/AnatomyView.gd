## The Anatomy tab's specimen: one creature's own tissue lattice, drawn from the
## pose it is standing in right now.
##
## It is not an illustration of a lizard. Every quad on it is a cell of the
## creature's `TissueGrid`, taken in world space and put through one rigid
## transform — so the silhouette is that creature's silhouette, the bend is the
## bend its spine is currently holding, a chewed flank is chewed here too, and a
## limb that has come off is missing from both. Nothing is authored twice: the
## colours come from `CreatureView.tissue_color`, the same static that inks the
## creature in the field and the meat on the ground, and the networks come from
## the same conduits `BodyState` reads its delivery off.
##
## The one thing it does that the field view cannot is *peel*. A layer switched
## off is lifted off the specimen, and what shows underneath is whatever a bite
## that deep would have exposed — which is the same depth stack, queried with a
## mask, rather than a second way of drawing a body.
##
## The specimen is presented upright, snout at the top, by rotating the whole
## body into the mean direction of its own spine. That is a rigid transform and
## nothing else: it re-orients the animal on the page without straightening it,
## so the pose stays exactly the pose.
##
## And it can be walked around. The lattice is not a sheet — every cell is a box
## of flesh standing at a height the pose put it at, which is what the bite query
## has been reading all along to tell a knee from a belly — so this view takes the
## third coordinate the cells already carry and projects it, rather than throwing
## it away as the field's top-down camera does. Nothing about the creature moves.
## The specimen is the same pose of the same body seen from somewhere else, which
## is the only kind of rotation a reading of a creature is allowed to be.
##
## It is turned by its own sphere. The animal is framed by the ball that contains
## it, that ball is drawn at the stage's inscribed circle, and a drag seizes the
## point of it under the pointer and carries that point to wherever the pointer
## goes — so the specimen turns with the hand rather than along two named axes,
## and the surface under the cursor is the surface that follows. `orient` is the
## whole of the eye's position; `spin`, `tilt` and `roll` are readings off it, and
## setting either of the first two names a viewpoint without the third.
##
## Framing is the same sphere and therefore does not move: the scale is the ball's
## radius against the stage, which no rotation can change. A specimen being turned
## holds its size, where fitting the silhouette instead would have it swell and
## shrink through the drag as the outline it happened to present grew and narrowed.
class_name AnatomyView
extends Control

## The finished hover readout, and whether it is reporting something opened.
signal cell_hovered(readout: String, alarm: bool)

const PAPER := CreatureView.PAPER
const INK := CreatureView.INK
## An unselected body still has to read as a body, so every surviving cell gets
## the faintest wash whether or not a layer the viewer has left on is showing
## through it.
const COL_WASH := Color(INK, 0.05)
const COL_SHADOW := Color(INK, 0.05)
const COL_LATTICE := Color(INK, 0.085)
## A destroyed cell is drawn as an outline of the opening it left, never filled.
const COL_HOLE := Color(INK, 0.32)
## The two supply networks, in the inks the field's own anatomy overlay uses.
const COL_NERVE := CreatureView.COL_DBG_NERVE
const COL_VESSEL := CreatureView.COL_DBG_VESSEL

## Layer toggles, as a mask over TissueGrid's depth stack.
const ALL_LAYERS: int = CreatureView.ALL_LAYERS

## Neighbour across each of `corners_of`'s four edges, in its winding order.
const EDGE_COL: Array[int] = [-1, 0, 1, 0]
const EDGE_ROW: Array[int] = [0, 1, 0, -1]

const PAD_X: float = 26.0
const PAD_Y: float = 30.0
## How quickly the presentation settles. The specimen must not spin as the animal
## turns or breathe as it walks, so both the upright rotation and the fit are
## eased rather than taken raw.
const SETTLE: float = 5.0
## Beats a second for the heart, which is what the vessel pulses ride on.
const HEART_RATE: float = 1.15
## How far off the cord the vessel run is drawn, in page pixels.
##
## Purely a drawing convention, and the one place this view moves anything: the
## plan runs both networks through the same vertebral cells, so laid down
## literally they are one line with the second colour on top and the circulation
## is invisible. The offset puts the great vessel where the anatomy says it is —
## *beside* the vertebrae rather than inside them — and touches nothing but the
## polyline. Integrity is still read off the cells themselves.
const VESSEL_OFFSET: float = 2.6
## Page pixels of cell depth each muscle fibre needs, and the size below which a
## cell can no longer carry its own outline. Detail drawn under these fills a cell
## with ink instead of describing it: a limb is three rows across a few pixels
## where the torso is seven across forty, and the field view never draws either at
## this size.
const GRAIN_MIN_CELL: float = 3.2
const LATTICE_MIN_CELL: float = 3.0

## Where the trackball stops being a sphere and becomes the sheet that carries on
## from it. Inside this radius the pointer is on the ball proper, outside it the
## drag is a roll in the plane of the page — Bell's hyperbolic skirt, which is what
## keeps a drag past the edge of the sphere from dying against it.
const BALL_EDGE: float = 0.70710678
## Orbit under which the projection is the plain top-down one. Below it no height
## can separate anything on the page, so the volume is skipped entirely — which is
## the whole cost of the third axis on a specimen nobody has turned.
const FLAT: float = 0.002
## How much darker the underside of the shell is drawn than the top of it. Not a
## light model — it is the one mark that says which side of the animal is facing
## you once it has been rolled over.
const UNDERSIDE: float = 0.14
## How far a cell's ink is lifted or dropped by which way its own patch of body is
## turned, with the specimen fully side-on.
##
## The form is read off the cross-section's own ellipse — the same `sqrt(1 - u²)`
## the lattice is built out of, so the light lands on a body that is round because
## the body genuinely is round, and a flank that has been chewed flat stops
## catching it. Without this a turned specimen in an animal's own inks is a black
## shape rotating: the silhouette moves and nothing inside it does.
const RELIEF: float = 0.42

var creature: Creature = null
## Where the specimen is being looked at from, in the animal's own frame: the whole
## of the camera, and a camera is all it is — nothing here moves the creature.
##
## Held as an orientation rather than as angles because the ball it is turned by
## has no axes of its own. Two angles can only ever be composed in some order, and
## the order shows: whichever one is applied second stops answering the drag once
## the first has swung its axis away from the screen. A rotation carries no such
## order, so every drag turns the specimen the way the hand went.
var orient: Basis = Basis():
	set(value):
		# Re-squared on every turn. The orientation is accumulated from arbitrarily
		# many drags, and an orthonormal basis multiplied a few thousand times is no
		# longer one.
		orient = value.orthonormalized()
		_bake_orbit()
## How far the eye has been carried around the animal's long axis, from over the
## back through the flank to the belly. A reading off `orient`, and — assigned —
## a way to name that viewpoint, which puts the specimen back upright on the page
## because two angles cannot say anything about the third.
var spin: float:
	get:
		return atan2(-_eye.x, _eye.z)
	set(value):
		_aim(value, tilt)
## How far the eye has swung off straight-overhead toward the tail, the same way.
var tilt: float:
	get:
		return asin(clampf(_eye.y, -1.0, 1.0))
	set(value):
		_aim(spin, value)
## How far the animal's own length has been turned off vertical on the page. Read
## only: it is what a ball has that a pair of camera angles does not, and it comes
## out of the drag rather than being asked for.
var roll: float:
	get:
		var snout := Vector2(-_page_x.y, -_page_y.y)
		if snout.length_squared() < 0.000001:
			return 0.0
		return Vector2(0.0, -1.0).angle_to(snout)
## Which layers of the depth stack are still on the specimen.
var layers: int = ALL_LAYERS
var show_vessels: bool = true
var show_nerves: bool = true
## Cell outlines. The lattice is what the whole system is built on, so it is
## drawn rather than implied.
var show_lattice: bool = true

var _mono: Font = null
var _clock: float = 0.0

# --- presentation transform --------------------------------------------------
var _anchor: Vector2 = Vector2.ZERO
var _heading: float = 0.0
var _rot: float = 0.0
var _scale: float = 1.0
var _centre: Vector2 = Vector2.ZERO
var _origin: Vector2 = Vector2.ZERO
var _lo: Vector2 = Vector2.ZERO
var _hi: Vector2 = Vector2.ZERO
var _fitted: bool = false
## The ball that contains the specimen: its centre in the animal's own upright
## frame, and its radius there. Both are properties of the pose alone — no angle
## the eye is at appears in either, which is why turning the specimen cannot
## resize it.
var _centre3: Vector3 = Vector3.ZERO
var _radius: float = 1.0
## That same ball on the page, as a radius about the middle of the stage. What the
## fit puts there, and what a drag takes hold of.
var _ball: float = 1.0

# Baked orbit: the rows of `orient`, which is the only form of it anything below
# asks for. Two of them say where a point of the animal lands on the page and the
# third says how near the eye it is — so every projection in the file is three
# dot products, and the eye's own direction through the body is a row rather than
# something to be worked out.
var _page_x: Vector3 = Vector3(1.0, 0.0, 0.0)
var _page_y: Vector3 = Vector3(0.0, 1.0, 0.0)
var _eye: Vector3 = Vector3(0.0, 0.0, 1.0)
## Whether the eye is off the vertical far enough for heights to matter.
var _solid: bool = false
## How far off straight-overhead it is, as how much relief to draw. Nought looking
## down, so the specimen at rest is inked exactly as the field inks the creature,
## and the form fades in with the turn rather than switching on.
var _relief: float = 0.0

var _hover_key: String = ""
var _hover_cell: int = -1
var _orbiting: bool = false
## Where the ball was seized, and how the specimen stood at that moment. The turn
## is measured from the grab rather than accumulated from the frame before it, so
## the point under the pointer stays under the pointer for the length of the drag
## instead of creeping away from it a rounding at a time.
var _grab: Vector3 = Vector3(0.0, 0.0, 1.0)
var _grabbed: Basis = Basis()

# Reused geometry, on the same terms as CreatureView's: this redraws every frame,
# so the cell layer writes into these rather than allocating per cell.
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## The heights of those same four corners, as [underside, top surface].
var _band := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## The corners once turned into the upright presentation, before any height is
## folded in — held so a cell's two faces and its shadow share one rotation.
var _turned := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## The same four corners on the page, and the heights they were taken at, for the
## hit test.
var _face := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _heights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _flat := PackedColorArray([Color.TRANSPARENT])
## (depth, face) per drawn face, sorted to put the far side of the animal down
## first. A packed array of pairs rather than a custom comparator, because
## Vector2 already sorts on x and the sort is then native rather than a callable
## per comparison.
var _depths := PackedVector2Array()
var _shadow := PackedVector2Array()
var _shadow_indices := PackedInt32Array()
var _lattice := PackedVector2Array()
var _skin_lines := PackedVector2Array()
var _muscle_lines := PackedVector2Array()
var _run := PackedVector2Array()
var _run_gone := PackedByteArray()
var _order: Array[String] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)


func set_ui_font(mono: Font) -> void:
	_mono = mono


func _process(delta: float) -> void:
	# In the *tree*, not this node's own flag. The fit walks every cell of the
	# animal, and a stage inside a drawer that is shut is still a visible node —
	# so asking the cheap question was buying nothing. There are two of these
	# stages now, one in the anatomy drawer and one in the creation menu, and at
	# most one of them is ever being looked at.
	if not is_visible_in_tree():
		return
	_clock += delta
	_settle(delta)
	queue_redraw()


## Forgets the settled presentation, so a different specimen arrives already
## upright and framed rather than easing across from where the last one sat.
func reset_fit() -> void:
	_fitted = false
	_hover_key = ""
	_hover_cell = -1


## Puts the eye back over the animal's back, looking straight down — the view the
## field itself is drawn in, and so the one the specimen reads against.
func reset_orbit() -> void:
	orient = Basis()


## Names a viewpoint by where the eye stands, with the page left upright.
func _aim(new_spin: float, new_tilt: float) -> void:
	orient = Basis(Vector3(1.0, 0.0, 0.0), new_tilt) * Basis(Vector3(0.0, 1.0, 0.0), new_spin)


## The trackball on the page: a radius about the middle of the stage, which is the
## sphere the specimen is framed by drawn where the fit put it.
func ball_radius() -> float:
	return _ball


## Takes hold of the sphere under the pointer.
func grab_ball(at: Vector2) -> void:
	_grab = _on_ball(at)
	_grabbed = orient


## Carries the seized point of the sphere to where the pointer has got to, turning
## the specimen with it.
##
## The turn is the arc from one point of the ball to the other — the shortest
## rotation that takes the first to the second — applied to how the specimen stood
## when it was seized. That is the whole of the interaction: what was under the
## finger is still under the finger, and everything else on the animal comes round
## with it.
func turn_ball(at: Vector2) -> void:
	var to: Vector3 = _on_ball(at)
	var axis: Vector3 = _grab.cross(to)
	var span: float = axis.length()
	if span < 0.000001:
		orient = _grabbed
		return
	orient = Basis(axis / span, atan2(span, _grab.dot(to))) * _grabbed


## Where a place on the page sits on the trackball, in the eye's own frame — page
## x and y as they are drawn, and depth toward the viewer, so the near face of the
## sphere is the face being grabbed.
##
## The sphere proper only reaches so far across the stage. Past that the ball is
## continued by a sheet that falls away from it, so a drag off the edge keeps
## turning the specimen — as a roll, which is what taking hold of the rim of a real
## sphere and pulling sideways does — rather than sticking against the silhouette.
func _on_ball(at: Vector2) -> Vector3:
	var p: Vector2 = (at - size * 0.5) / maxf(_ball, 1.0)
	var d: float = p.length()
	var depth: float = sqrt(maxf(1.0 - d * d, 0.0)) if d <= BALL_EDGE else 0.5 / d
	return Vector3(p.x, p.y, depth).normalized()


## Whether the specimen is being seen as a volume rather than from overhead.
func orbited() -> bool:
	return _solid


func _bake_orbit() -> void:
	var ex: Vector3 = orient * Vector3(1.0, 0.0, 0.0)
	var ey: Vector3 = orient * Vector3(0.0, 1.0, 0.0)
	var ez: Vector3 = orient * Vector3(0.0, 0.0, 1.0)
	_page_x = Vector3(ex.x, ey.x, ez.x)
	_page_y = Vector3(ex.y, ey.y, ez.y)
	_eye = Vector3(ex.z, ey.z, ez.z)
	_solid = absf(_eye.x) > FLAT or absf(_eye.y) > FLAT
	_relief = sqrt(clampf(1.0 - _eye.z, 0.0, 1.0))
	# The page follows the turn in the same breath as the projection does. A drag
	# lands between one settle and the next, and re-centring on the next frame
	# instead would let the specimen swim a frame behind the hand.
	_reframe()


func layer_shown(layer: int) -> bool:
	return (layers & (1 << layer)) != 0


func set_layer_shown(layer: int, shown: bool) -> void:
	if shown:
		layers |= 1 << layer
	else:
		layers &= ~(1 << layer)


## The lattice this view is reading, or null while there is nothing to show.
func tissue() -> TissueGrid:
	if not is_instance_valid(creature) or creature.anatomy == null:
		return null
	var grid: TissueGrid = creature.anatomy.tissue
	var body: TissueGrid.Patch = grid.patch(TissueGrid.BODY_KEY)
	return grid if body != null and body.live else null


# ----------------------------------------------------------- presentation ----

## Re-derives the transform that puts the creature on the page: upright, centred
## and as large as the stage will take it.
##
## Everything is measured relative to the animal's own snout rather than to the
## world, so walking across the map moves the specimen not at all. What is left
## to ease is the bend of the body and the loss of a piece, both of which should
## be seen settling rather than snapping.
##
## The size is decided by the ball the animal fits inside and not by the outline it
## is presenting, which is the one thing that keeps a drag from being a zoom. A
## silhouette fit measures a body that is long, narrow and standing at an angle, so
## every degree of the turn hands it a different rectangle to fill and the specimen
## breathes in and out under the hand. The ball is the same ball from every side.
func _settle(delta: float) -> void:
	var grid: TissueGrid = tissue()
	if grid == null or creature.spine == null or creature.body == null:
		return
	if size.x < 8.0 or size.y < 8.0:
		return

	var spine: Spine = creature.spine
	var last: int = mini(creature.body.last_index, spine.forwards.size() - 1)
	var axis := Vector2.ZERO
	for i in range(last + 1):
		axis += spine.forwards[i]
	if axis.length_squared() < 0.000001:
		axis = spine.forwards[0]
	var target_heading: float = axis.angle()
	_heading = target_heading if not _fitted \
		else lerp_angle(_heading, target_heading, 1.0 - exp(-SETTLE * delta))
	# Snout to the top of the page: the mean body direction is turned onto -Y.
	_rot = -PI * 0.5 - _heading
	_anchor = creature.body.head.pos

	# The animal's own box, in the upright frame and in all three axes. No angle of
	# the eye appears in it, so it is the same box whichever way the specimen has
	# been turned — which is the whole of why the fit below holds still.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for cell in p.cells:
			if p.gone[cell] != 0:
				continue
			p.corners_of(cell, _quad)
			p.surfaces_of(cell, _band)
			for k in 4:
				var at: Vector2 = (_quad[k] - _anchor).rotated(_rot)
				# The corner at its lowest and its highest, and the floor as well: the
				# specimen's shadow is cast on the ground, so the ground is part of
				# what has to stay on the stage for an animal holding itself above it.
				lo = Vector3(minf(lo.x, at.x), minf(lo.y, at.y), minf(lo.z, _band[k].x))
				hi = Vector3(maxf(hi.x, at.x), maxf(hi.y, at.y), maxf(hi.z, _band[k].y))
	if lo.x > hi.x:
		return
	lo.z = minf(lo.z, 0.0)
	hi.z = maxf(hi.z, 0.0)

	var target_centre: Vector3 = (lo + hi) * 0.5
	# Corner to centre of that box: the radius of a ball that holds the animal from
	# every side. Loose by however much the body fails to fill its own corners, and
	# on a creature that is mostly length that is a fraction of a percent.
	var target_radius: float = maxf((hi - lo).length() * 0.5, 0.5)
	if _fitted:
		var ease: float = 1.0 - exp(-SETTLE * delta)
		_radius = lerpf(_radius, target_radius, ease)
		_centre3 = _centre3.lerp(target_centre, ease)
	else:
		_radius = target_radius
		_centre3 = target_centre
		_fitted = true

	# The ball drawn at the stage's inscribed circle, and the scale that follows
	# from it. Both survive the panel being resized; neither can see the orbit.
	var room: Vector2 = (size - Vector2(PAD_X * 2.0, PAD_Y * 2.0)).max(Vector2(1.0, 1.0))
	_ball = minf(room.x, room.y) * 0.5
	_scale = _ball / _radius
	_reframe()

	# What the animal actually covers on the page, for the labels that have to stand
	# clear of it. The eight corners of its box rather than every cell of it: this is
	# a margin for leader lines, and the box already bounds the body.
	_lo = Vector2(INF, INF)
	_hi = Vector2(-INF, -INF)
	for i in 8:
		var at: Vector2 = _origin + _flatten(
			Vector2(hi.x if (i & 1) != 0 else lo.x, hi.y if (i & 2) != 0 else lo.y),
			hi.z if (i & 4) != 0 else lo.z) * _scale
		_lo = _lo.min(at)
		_hi = _hi.max(at)


## Re-centres the stage on the ball. Called by the fit and again by every turn,
## because where the middle of the animal lands on the page depends on both.
func _reframe() -> void:
	if not _fitted:
		return
	_centre = _flatten(Vector2(_centre3.x, _centre3.y), _centre3.z)
	_origin = size * 0.5 - _centre * _scale


## Where a place on the animal lands on the page. The whole of the relationship
## between the specimen and the creature is this and `_flatten`: one rotation, one
## orbit, one scale, one offset, applied to coordinates the lattice already holds.
## There is no second geometry anywhere in this file.
func project(world: Vector2, height: float) -> Vector2:
	return _origin + _flatten((world - _anchor).rotated(_rot), height) * _scale


## The same for a place on the ground under the animal — where the shadow of it
## falls, and the address anything working in plan view alone asks in.
func to_panel(world: Vector2) -> Vector2:
	return project(world, 0.0)


## One point of the upright presentation, seen from wherever the eye currently is.
##
## `turned` is the body in plan, already rotated snout-up; `height` is how far off
## the ground that point stands. The two together are a place in the animal, and
## the two page rows of `orient` say where on the stage that place falls. At an
## orientation of nothing this is the identity on the plan and drops the height
## entirely, which is exactly the top-down reading the field is drawn in.
func _flatten(turned: Vector2, height: float) -> Vector2:
	return Vector2(
		turned.x * _page_x.x + turned.y * _page_x.y + height * _page_x.z,
		turned.x * _page_y.x + turned.y * _page_y.y + height * _page_y.z)


## How near the eye that same point is. The painter's-order key, and the only
## reason a rolled specimen reads as a solid animal rather than as a shell turned
## inside out.
func _towards(turned: Vector2, height: float) -> float:
	return turned.x * _eye.x + turned.y * _eye.y + height * _eye.z


## Whether the specimen has been framed yet. False for a creature whose lattice
## has not been posed, and for the frame after the slab changes hands.
func fitted() -> bool:
	return _fitted


## Limbs before the body, so the legs read as being underneath the torso exactly
## as they do in the field. Built once — every pass below walks it, and which
## structures an animal has is not something a frame can change.
func _patch_order() -> Array[String]:
	if _order.is_empty():
		_order = TissueGrid.LIMB_KEYS.duplicate()
		_order.append(TissueGrid.BODY_KEY)
	return _order


# --------------------------------------------------------------- drawing ----

func _draw() -> void:
	var grid: TissueGrid = tissue()
	if grid == null or not _fitted:
		_draw_empty()
		return
	_draw_cells(grid)
	_draw_grain(grid)
	_draw_holes(grid)
	if show_lattice:
		_draw_lattice(grid)

	var state: BodyState = creature.anatomy.state
	if show_vessels:
		_draw_network(grid, state.plan.vessels, state.vessels, COL_VESSEL, 3, 46.0, true,
			VESSEL_OFFSET)
	if show_nerves:
		_draw_network(grid, state.plan.nerves, state.nerves, COL_NERVE, 2, 150.0, false, 0.0)
	if show_vessels:
		_draw_organ(grid, BodyPlan.HEART, COL_VESSEL, "HEART", true)
	if show_nerves:
		_draw_organ(grid, BodyPlan.BRAIN, COL_NERVE, "BRAIN", false)
	_draw_hover(grid)


func _draw_empty() -> void:
	if _mono == null:
		return
	var text: String = "NO SPECIMEN"
	var width: float = _mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
	draw_string(_mono, Vector2((size.x - width) * 0.5, size.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(INK, 0.30))


## Every surviving cell, in the creature's own inks.
##
## One indexed triangle array for the whole animal, for the same reason the field
## renderer batches: a cell apiece is several hundred canvas commands a frame.
## Cells whose visible layer has been peeled away are still emitted, in the wash,
## so lifting the skin off a body leaves a body rather than a hole.
func _draw_cells(grid: TissueGrid) -> void:
	var standing: int = 0
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p != null and p.live:
			standing += p.cells - p.gone_count
	if standing <= 0:
		return
	# Two faces a cell once the eye is off the vertical: the top of the shell and
	# the underside of it. A body seen from anywhere but straight above is closed,
	# and a single surface would show the paper through its own flank.
	var faces: int = standing * 2 if _solid else standing
	if _points.size() != faces * 4:
		_points.resize(faces * 4)
		_colors.resize(faces * 4)
		_indices.resize(faces * 6)
		_depths.resize(faces)
	if _solid and _shadow.size() != standing * 4:
		_shadow.resize(standing * 4)
		_build_shadow_indices(standing)

	var v: int = 0
	var face: int = 0
	var s: int = 0
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for cell in p.cells:
			if p.gone[cell] != 0:
				continue
			p.corners_of(cell, _quad)
			p.surfaces_of(cell, _band)
			var base: int = cell * TissueGrid.LAYERS
			var color: Color = COL_WASH
			if CreatureView.top_layer(p.hp, base, layers) >= 0:
				color = CreatureView.tissue_color(
					p.hp, base, grid.fat_capacity(p, cell), layers)
			# One rotation per corner, shared by the cell's two faces and by the
			# patch of ground under it.
			for k in 4:
				_turned[k] = (_quad[k] - _anchor).rotated(_rot)

			# Where this cell sits around its own cross-section, and therefore which
			# way the two faces of it point. A cell over the spine faces the sky; one
			# out on the flank faces sideways; and the ellipse says by how much.
			var lateral: float = p.row_centre(cell % p.rows)
			var rise: float = sqrt(maxf(1.0 - lateral * lateral, 0.0))
			var over_ink: Color = _relieved(color, rise * _eye.z + lateral * _eye.x)

			var over: float = 0.0
			for k in 4:
				_points[v + k] = _origin + _flatten(_turned[k], _band[k].y) * _scale
				_colors[v + k] = over_ink
				over += _towards(_turned[k], _band[k].y)
			_depths[face] = Vector2(over * 0.25, float(face))
			v += 4
			face += 1
			if not _solid:
				continue

			var under: Color = _relieved(color.lerp(Color(INK, color.a), UNDERSIDE),
				-rise * _eye.z + lateral * _eye.x)
			var below: float = 0.0
			for k in 4:
				_points[v + k] = _origin + _flatten(_turned[k], _band[k].x) * _scale
				_colors[v + k] = under
				below += _towards(_turned[k], _band[k].x)
				_shadow[s + k] = _origin + _flatten(_turned[k], 0.0) * _scale
			_depths[face] = Vector2(below * 0.25, float(face))
			v += 4
			face += 1
			s += 4

	# Far side of the animal first. Without this the shell is drawn inside out and
	# a rolled specimen shows its own back through its belly.
	if _solid:
		_depths.sort()
	var t: int = 0
	for i in faces:
		var at: int = int(_depths[i].y) * 4
		_indices[t] = at
		_indices[t + 1] = at + 1
		_indices[t + 2] = at + 2
		_indices[t + 3] = at
		_indices[t + 4] = at + 2
		_indices[t + 5] = at + 3
		t += 6

	# The specimen's own shadow — so a hole in the creature is a hole in its
	# shadow, as it is in the field. Cast on the ground the lattice's heights are
	# measured from once there is an angle to see it from, and faked with a plain
	# offset from overhead, where the two would coincide exactly.
	_flat[0] = COL_SHADOW
	if _solid:
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), _shadow_indices, _shadow, _flat)
	else:
		draw_set_transform(Vector2(0.0, 5.0), 0.0, Vector2.ONE)
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), _indices, _points, _flat)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)


## A face's own colour with the form of the body on it: lifted toward the paper
## where it is turned toward the eye, dropped toward the ink where it is turned
## away. Alpha is carried across rather than lerped, so a peeled cell's wash stays
## a wash instead of the shaded side of it coming up solid.
func _relieved(color: Color, lit: float) -> Color:
	var lift: float = _relief * clampf(lit, -1.0, 1.0)
	if lift >= 0.0:
		return color.lerp(Color(PAPER, color.a), RELIEF * lift)
	return color.lerp(Color(INK, color.a), RELIEF * -lift)


## The shadow is one quad per standing cell in lattice order and never sorted —
## it is flat on the floor, so nothing about it can occlude anything else.
func _build_shadow_indices(cells: int) -> void:
	_shadow_indices.resize(cells * 6)
	for i in cells:
		var at: int = i * 4
		var t: int = i * 6
		_shadow_indices[t] = at
		_shadow_indices[t + 1] = at + 1
		_shadow_indices[t + 2] = at + 2
		_shadow_indices[t + 3] = at
		_shadow_indices[t + 4] = at + 2
		_shadow_indices[t + 5] = at + 3


## The face of a cell currently turned toward the eye: the top of the shell while
## the animal's back is to you, its underside once it has been rolled past its
## flank. Every pass that marks a *surface* rather than a volume asks this, so the
## grain, the lattice, a wound rim and the hit test all describe the side you are
## actually looking at.
func _facing(band: Vector2) -> float:
	return band.y if _eye.z >= 0.0 else band.x


## Whether that face is actually turned toward the eye rather than lying on the
## far side of the animal. `lateral` is where the cell sits across its own
## cross-section, so this is the ellipse's own normal against the eye.
##
## Asked by the passes that draw *lines*, and by none of the ones that draw fills.
## A fill is opaque and sorted, so the far side of the body is painted over by the
## near side and needs no test; a line is not painted over by anything, so without
## this the far flank's grain and lattice show straight through the near one and a
## rolled specimen comes out as a wireframe of itself. Nothing is culled while the
## eye is overhead — no cell of a body seen from above faces away from it.
func _shows(lateral: float) -> bool:
	if not _solid:
		return true
	var rise: float = sqrt(maxf(1.0 - lateral * lateral, 0.0))
	return (rise if _eye.z >= 0.0 else -rise) * _eye.z + lateral * _eye.x > 0.0


## Material grain, on the same rule the field uses: skin is read as one membrane
## through sparse tension lines, exposed muscle carries close fibres along the
## anatomy's grain, and fat has none of its own. Peeling a layer moves the grain
## with it, because both are asking the same question about the same cell.
##
## Suppressed on cells too small to hold it. The field draws this at world scale
## on a torso forty pixels across; the drawer draws the same three fibres on a
## limb cell two pixels deep, where they stop being a material and become a dark
## smear over the colour that was supposed to say what the material is.
func _draw_grain(grid: TissueGrid) -> void:
	_skin_lines.resize(0)
	_muscle_lines.resize(0)
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for cell in p.cells:
			if p.gone[cell] != 0:
				continue
			var top: int = CreatureView.top_layer(p.hp, cell * TissueGrid.LAYERS, layers)
			if top != TissueGrid.SKIN and top != TissueGrid.MUSCLE:
				continue
			if not _shows(p.row_centre(cell % p.rows)):
				continue
			p.corners_of(cell, _quad)
			p.surfaces_of(cell, _band)
			var strands: int = clampi(int(_cell_depth() / GRAIN_MIN_CELL), 0, 3)
			if strands <= 0:
				continue
			if top == TissueGrid.SKIN:
				if cell % p.rows % 2 == 1:
					_skin_lines.append(_across(0, 1, 0.5))
					_skin_lines.append(_across(3, 2, 0.5))
				continue
			# Fibres thin out with the cell rather than switching off at a size, so a
			# tapering tail loses its grain the way it loses its width instead of in
			# bands wherever a column happened to cross the threshold.
			for strand in range(1, strands + 1):
				var across: float = float(strand) / float(strands + 1)
				_muscle_lines.append(_across(0, 1, across))
				_muscle_lines.append(_across(3, 2, across))
	if not _skin_lines.is_empty():
		draw_multiline(_skin_lines, CreatureView.COL_SKIN_TENSION, 0.75, true)
	if not _muscle_lines.is_empty():
		draw_multiline(_muscle_lines, CreatureView.COL_MUSCLE_FIBRE, 0.9, true)


## Destroyed cells, as the openings they are. Outlined and never filled: the
## specimen has a hole there, and a patch of paper would be indistinguishable
## from a cell whose tissue happens to be pale.
##
## Only the *rim* of a wound is drawn — an edge with surviving tissue on the
## other side of it, or the edge of the structure. Outlining every destroyed cell
## would draw the grid of the hole rather than its shape, and a body chewed
## through would come out looking like a mesh instead of like an opening.
func _draw_holes(grid: TissueGrid) -> void:
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live or p.gone_count == 0:
			continue
		for cell in p.cells:
			if p.gone[cell] == 0 or not _shows(p.row_centre(cell % p.rows)):
				continue
			p.corners_of(cell, _quad)
			p.surfaces_of(cell, _band)
			var col: int = cell / p.rows
			var row: int = cell % p.rows
			for k in 4:
				if not _rim(p, col + EDGE_COL[k], row + EDGE_ROW[k]):
					continue
				draw_dashed_line(_corner(k), _corner((k + 1) % 4), COL_HOLE, 0.9, 2.2, true)


## Whether an edge is on the rim of a wound: off the end of the structure, or
## against a cell that still has something in it.
func _rim(p: TissueGrid.Patch, col: int, row: int) -> bool:
	if col < 0 or col >= p.cols or row < 0 or row >= p.rows:
		return true
	return p.gone[col * p.rows + row] == 0


func _draw_lattice(grid: TissueGrid) -> void:
	_lattice.resize(0)
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for cell in p.cells:
			if p.gone[cell] != 0 or not _shows(p.row_centre(cell % p.rows)):
				continue
			p.corners_of(cell, _quad)
			p.surfaces_of(cell, _band)
			if _cell_depth() < LATTICE_MIN_CELL:
				continue
			for k in 4:
				_lattice.append(_corner(k))
				_lattice.append(_corner((k + 1) % 4))
	if not _lattice.is_empty():
		draw_multiline(_lattice, COL_LATTICE, 0.5, true)


## A point part way along one edge of the cell in `_quad`, lifted onto the surface
## the edge's own two corners stand at. A body is round, so its skin is nowhere
## flat across a cell — taking one corner's height for the whole edge would float
## the grain off the flank exactly where the curvature is steepest.
func _across(from_corner: int, to_corner: int, along: float) -> Vector2:
	return project(_quad[from_corner].lerp(_quad[to_corner], along),
		lerpf(_facing(_band[from_corner]), _facing(_band[to_corner]), along))


## Corner `k` of that cell, on the face turned toward the eye.
func _corner(k: int) -> Vector2:
	return project(_quad[k], _facing(_band[k]))


## How deep the cell in `_quad` is across the body, on the page. The measure the
## two passes above decide by, because it is the direction their marks run
## across and therefore the one that runs out of room first.
##
## Measured on the page rather than in the world, so a cell foreshortened by the
## orbit loses its detail on the same rule a cell that is simply small does.
func _cell_depth() -> float:
	return _corner(0).distance_to(_corner(1))


# -------------------------------------------------------------- networks ----

## One supply network, laid along the cells it actually passes through.
##
## Width and alpha carry what *arrives* rather than what survives locally, so a
## sound run still fades out behind a cut upstream of it — the property the whole
## network exists to have. A run broken at a cell is drawn dashed from there,
## because that is where the flesh carrying it was taken.
func _draw_network(grid: TissueGrid, runs: Array[BodyPlan.Conduit],
		network: AnatomyNetwork, tint: Color, pulses: int, speed: float,
		beat: bool, offset: float) -> void:
	for run in runs:
		var p: TissueGrid.Patch = grid.patch(run.patch_key)
		if p == null or not p.live or run.cells.size() < 2:
			continue
		_gather_run(grid, runs, run, offset)
		var reach: float = clampf(network.delivery[run.region], 0.0, 1.0)
		for i in range(_run.size() - 1):
			if _run_gone[i] != 0 or _run_gone[i + 1] != 0:
				draw_dashed_line(_run[i], _run[i + 1], Color(tint, 0.16), 0.9, 2.5, true)
				continue
			draw_line(_run[i], _run[i + 1], Color(tint, 0.18 + 0.62 * reach),
				1.0 + 1.4 * reach, true)
		if reach > AnatomyNetwork.CUTOFF:
			_draw_pulses(runs, run, tint, reach, pulses, speed, beat)


## The run's cells in panel space, ordered so it flows away from whatever feeds
## it. The cord runs head-to-tail and the great vessels run out of the chest, so
## the same list of cells is travelled in opposite directions by the two networks
## and the direction has to be taken from the tree rather than from the lattice.
func _gather_run(grid: TissueGrid, runs: Array[BodyPlan.Conduit],
		run: BodyPlan.Conduit, offset: float) -> void:
	var p: TissueGrid.Patch = grid.patch(run.patch_key)
	var count: int = run.cells.size()
	_run.resize(count)
	_run_gone.resize(count)
	# At the cell's own centre line, which is where a conduit inside a body is: the
	# cord threads the vertebrae and the great vessel lies against them, so both run
	# through the middle of the animal rather than over its back.
	for i in count:
		_run[i] = project(p.centre_of(run.cells[i]), p.height_of(run.cells[i]))
		_run_gone[i] = p.gone[run.cells[i]]
	# Stepped aside before any reversal below, so which flank the vessel lies on
	# is a fact about the body rather than about which way the blood is going.
	if absf(offset) > 0.001 and count > 1:
		for i in count:
			var span: Vector2 = _run[mini(i + 1, count - 1)] - _run[maxi(i - 1, 0)]
			if span.length_squared() > 0.000001:
				_run[i] += Vector2(-span.y, span.x).normalized() * offset
	if run.parent < 0:
		return
	var upstream: BodyPlan.Conduit = runs[run.parent]
	var feeder: TissueGrid.Patch = grid.patch(upstream.patch_key)
	if feeder == null or upstream.cells.is_empty():
		return
	var joint: Vector2 = to_panel(feeder.centre_of(upstream.cells[upstream.cells.size() - 1]))
	if joint.distance_squared_to(_run[count - 1]) >= joint.distance_squared_to(_run[0]):
		return
	_run.reverse()
	_run_gone.reverse()


## What the network is carrying, moving. Nerves fire as quick dashes and blood
## arrives in beats, which is the one honest way to show at a glance that the two
## are different systems rather than two colours of the same line.
func _draw_pulses(runs: Array[BodyPlan.Conduit], run: BodyPlan.Conduit, tint: Color,
		reach: float, pulses: int, speed: float, beat: bool) -> void:
	var total: float = 0.0
	var stops := PackedFloat32Array()
	stops.resize(_run.size())
	stops[0] = 0.0
	var live: int = 1
	for i in range(_run.size() - 1):
		if _run_gone[i] != 0 or _run_gone[i + 1] != 0:
			break
		total += _run[i].distance_to(_run[i + 1])
		stops[i + 1] = total
		live = i + 2
	if total < 4.0:
		return

	# Every run is phase-shifted by how far down the tree it is, so a pulse reads
	# as having travelled out from the organ rather than starting everywhere.
	var depth: float = float(_depth_of(runs, run))
	for k in pulses:
		var phase: float = fposmod(
			_clock * speed / total + float(k) / float(pulses) - depth * 0.14, 1.0)
		if beat:
			var thump: float = 0.5 - 0.5 * cos(TAU * fposmod(
				_clock * HEART_RATE - depth * 0.08, 1.0))
			phase = fposmod(phase + 0.06 * thump, 1.0)
		var head: Vector2 = _along(stops, live, phase * total)
		var fade: float = sin(PI * phase) if beat else clampf((1.0 - phase) * 4.0, 0.0, 1.0)
		var alpha: float = reach * (0.45 + 0.55 * fade if beat else fade)
		if alpha <= 0.01:
			continue
		if beat:
			draw_circle(head, 2.1, Color(tint, alpha))
		else:
			draw_line(_along(stops, live, maxf(phase * total - 5.0, 0.0)), head,
				Color(tint, alpha), 1.8, true)


## A point at `distance` along the run's own arc length, so a pulse keeps pace
## through a bend instead of hurrying round the outside of it.
func _along(stops: PackedFloat32Array, live: int, distance: float) -> Vector2:
	for i in range(live - 1):
		if distance <= stops[i + 1]:
			var span: float = stops[i + 1] - stops[i]
			var u: float = (distance - stops[i]) / span if span > 0.0 else 0.0
			return _run[i].lerp(_run[i + 1], u)
	return _run[live - 1]


func _depth_of(runs: Array[BodyPlan.Conduit], run: BodyPlan.Conduit) -> int:
	var depth: int = 0
	var at: BodyPlan.Conduit = run
	while at.parent >= 0 and depth < BodyPlan.REGIONS:
		at = runs[at.parent]
		depth += 1
	return depth


# ---------------------------------------------------------------- organs ----

## An organ, at the cells it actually occupies, on a leader clear of the body.
##
## Drawn from surviving cells only: an organ that has been destroyed and taken
## with the tissue around it is not marked at all, because there is nothing there
## to mark. The ring carries how much of it is left, and the heart's own beat is
## the same clock the blood pulses ride on.
func _draw_organ(grid: TissueGrid, which: int, tint: Color, label: String,
		beat: bool) -> void:
	var p: TissueGrid.Patch = grid.patch(TissueGrid.BODY_KEY)
	if p == null or not p.live:
		return
	var centre := Vector2.ZERO
	var height: float = 0.0
	var found: int = 0
	for cell in p.cells:
		if int(p.organ[cell]) != which or p.gone[cell] != 0:
			continue
		centre += p.centre_of(cell)
		height += p.height_of(cell)
		found += 1
	if found == 0:
		return
	var at: Vector2 = project(centre / float(found), height / float(found))
	var health: float = grid.organ(which)

	var radius: float = 7.0
	if beat:
		var thump: float = 0.5 - 0.5 * cos(TAU * fposmod(_clock * HEART_RATE, 1.0))
		radius = 6.0 * (1.0 + 0.16 * thump)
	draw_circle(at, radius, Color(PAPER, 0.92))
	draw_arc(at, radius, 0.0, TAU, 24, Color(tint, 0.30 + 0.60 * health), 1.2, true)
	draw_circle(at, radius * 0.42, Color(tint, 0.25 + 0.65 * health))

	if _mono == null:
		return
	# The leader names the organ and nothing else. How much of it is left is on the
	# ring it is drawn on and read out in words in the drawer — a number here would
	# be a third statement of the same fact, and the one it spent most of its life
	# making was "100%".
	var width: float = _mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
	var edge: float = minf(maxf(_hi.x + 6.0, at.x + radius + 12.0), size.x - width - 12.0)
	draw_line(Vector2(at.x + radius + 2.0, at.y), Vector2(edge, at.y),
		Color(tint, 0.34), 0.7, true)
	draw_string(_mono, Vector2(edge + 4.0, at.y + 3.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(tint, 0.78))


# ------------------------------------------------------------- hit-test ----

func _draw_hover(grid: TissueGrid) -> void:
	if _hover_cell < 0:
		return
	var p: TissueGrid.Patch = grid.patch(_hover_key)
	if p == null or not p.live or _hover_cell >= p.cells:
		return
	p.corners_of(_hover_cell, _quad)
	p.surfaces_of(_hover_cell, _band)
	for k in 4:
		draw_line(_corner(k), _corner((k + 1) % 4), INK, 1.3, true)


## Dragging turns the specimen; moving over it reads a cell. Both are the pointer
## on the same stage, so which one is happening is decided by whether a button is
## down and nowhere else.
##
## A drag is on the ball and takes the pointer's position, not its displacement:
## the specimen goes where the hand goes because it is being held, rather than
## being nudged by however far the mouse reported having moved this frame.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.double_click:
			reset_orbit()
		_orbiting = click.pressed
		if click.pressed:
			grab_ball(click.position)
			_hover_key = ""
			_hover_cell = -1
			cell_hovered.emit("", false)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _orbiting:
		turn_ball(motion.position)
		accept_event()
		return
	_pick(motion.position)


func _on_mouse_exited() -> void:
	if _hover_cell >= 0:
		_hover_key = ""
		_hover_cell = -1
		cell_hovered.emit("", false)


## Which cell is under the cursor.
##
## Tested against the cells as they are drawn — each one's own face, projected —
## rather than by inverting the mapping, for the reason the bite query gives: it is
## curved, tapered, rebuilt every tick and now turned as well, so it has no cheap
## inverse, while the direct test is exact and costs a few hundred comparisons on
## the frames the pointer actually moves.
##
## The nearest cell wins rather than the first found, which is the whole difference
## a rotated specimen makes: from overhead the limbs are simply drawn under the
## torso, but tipped over, a leg genuinely stands between the eye and the belly and
## the pointer has to meet the leg.
func _pick(at: Vector2) -> void:
	var grid: TissueGrid = tissue()
	if grid == null or not _fitted:
		return
	var found_key: String = ""
	var found_cell: int = -1
	var nearest: float = -INF
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for cell in p.cells:
			p.corners_of(cell, _quad)
			p.surfaces_of(cell, _band)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for k in 4:
				# Inlined, on the same terms as the fit's own walk: this runs over
				# every cell of the animal on every frame the pointer moves.
				var turned: Vector2 = (_quad[k] - _anchor).rotated(_rot)
				var height: float = _facing(_band[k])
				_turned[k] = turned
				_heights[k] = height
				_face[k] = _origin + Vector2(
					turned.x * _page_x.x + turned.y * _page_x.y + height * _page_x.z,
					turned.x * _page_y.x + turned.y * _page_y.y + height * _page_y.z) * _scale
				lo = lo.min(_face[k])
				hi = hi.max(_face[k])
			# The cell's own box on the page first, which turns almost every cell
			# away for four comparisons instead of for a winding test apiece.
			if at.x < lo.x or at.x > hi.x or at.y < lo.y or at.y > hi.y:
				continue
			if not _inside(at, _face):
				continue
			var depth: float = 0.0
			for k in 4:
				depth += _towards(_turned[k], _heights[k])
			if depth <= nearest:
				continue
			nearest = depth
			found_key = key
			found_cell = cell
	if found_cell >= 0:
		if _hover_key != found_key or _hover_cell != found_cell:
			_hover_key = found_key
			_hover_cell = found_cell
			var p: TissueGrid.Patch = grid.patch(found_key)
			cell_hovered.emit(_readout(grid, p, found_cell), p.gone[found_cell] != 0)
		return
	if _hover_cell >= 0:
		_hover_key = ""
		_hover_cell = -1
		cell_hovered.emit("", false)


## Point in quad, by every edge crossing the same way round. The cells are convex
## whatever the spine is doing, so this holds through any bend.
static func _inside(point: Vector2, quad: PackedVector2Array) -> bool:
	var winding: float = 0.0
	for i in 4:
		var a: Vector2 = quad[i]
		var b: Vector2 = quad[(i + 1) % 4]
		var cross: float = (b - a).cross(point - a)
		if is_zero_approx(cross):
			continue
		if winding == 0.0:
			winding = signf(cross)
		elif signf(cross) != winding:
			return false
	return true


## What that cell is made of, layer by layer. Only the layers the cell was built
## with are listed — a cell with no bone under it never reports missing bone.
func _readout(grid: TissueGrid, p: TissueGrid.Patch, cell: int) -> String:
	var region: String = grid.plan.region_name(int(p.region[cell])).to_upper()
	if p.gone[cell] != 0:
		return "%s · HOLE THROUGH" % region
	var base: int = cell * TissueGrid.LAYERS
	var names: Array[String] = ["SKN", "FAT", "MSC", "BNE", "ORG"]
	var built: Array[float] = [
		TissueGrid.SKIN_HP,
		grid.fat_capacity(p, cell),
		TissueGrid.MUSCLE_HP,
		TissueGrid.BONE_HP if p.bone[cell] != 0 else 0.0,
		TissueGrid.ORGAN_HP if int(p.organ[cell]) != BodyPlan.NO_ORGAN else 0.0,
	]
	var bits: PackedStringArray = PackedStringArray()
	for layer in TissueGrid.LAYERS:
		if built[layer] <= 0.0:
			continue
		bits.append("%s %d" % [names[layer],
			int(round(100.0 * clampf(p.hp[base + layer] / built[layer], 0.0, 1.0)))])
	var organ: int = int(p.organ[cell])
	if organ != BodyPlan.NO_ORGAN:
		region = "%s · %s" % [region, BodyPlan.ORGAN_NAMES[organ].to_upper()]
	return "%s · %s" % [region, " ".join(bits)]
