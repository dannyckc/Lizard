## The Anatomy tab's specimen: one creature's own 3D cell lattice, drawn from
## the pose it is standing in right now.
##
## It is not an illustration of a lizard. Every mark on it is a cell of the
## creature's `AnatomyLattice` — a real box of one tissue with a place in the
## animal's own three axes — posed through the same per-station frames the
## damage ledger poses its columns with, and put through one rigid transform. So
## the silhouette is that creature's silhouette, the bend is the bend its spine
## is currently holding, a chewed flank is a crater of missing cells here too,
## and a limb that has come off is missing from both. The counts on the panel
## beside it are these same cells, because the physique weighed these same
## cells: there is no second anatomy anywhere.
##
## Four ways to look inside, and all four are subtractions rather than styles:
## a tissue toggled off has its cells lifted away and whatever they enclosed is
## simply visible; X-ray thins every cell to a film so the interior reads in
## place; a section plane carves the body at a station of its own frame and
## shows the cut face; and the panel can isolate one tissue outright. What shows
## underneath is always the cells that were genuinely laid underneath — bone
## inside muscle inside fat inside skin, organs behind bone, the two supply
## lines threading the middle of it.
##
## The specimen is presented upright, snout at the top, by rotating the whole
## body into the mean direction of its own spine — a rigid transform that
## re-orients without straightening, so the pose stays exactly the pose. And it
## can be walked around: the trackball seizes the point of the containing sphere
## under the pointer and carries it with the hand. `orient` is the whole of the
## eye's position; `spin`, `tilt` and `roll` are readings off it. Framing is the
## same sphere and therefore does not move while the specimen turns.
class_name AnatomyView
extends Control

## The finished hover readout, and whether it is reporting something opened.
signal cell_hovered(readout: String, alarm: bool)

const PAPER := CreatureView.PAPER
const INK := CreatureView.INK
## The two supply networks, in the inks the field's own anatomy overlay uses.
const COL_NERVE := CreatureView.COL_DBG_NERVE
const COL_VESSEL := CreatureView.COL_DBG_VESSEL
const COL_LATTICE := Color(INK, 0.10)

## Layer toggles, as a mask over the lattice's first five tissues. The nerve and
## vessel cells ride `show_nerves` / `show_vessels` beside it, exactly as the
## network overlays do.
const ALL_LAYERS: int = CreatureView.ALL_LAYERS

## One ink per tissue, and the worn shade damage drags it toward — the same
## palette the field inks the creature and its meat with.
static var TISSUE_INK: PackedColorArray = PackedColorArray([
	CreatureView.COL_BODY_HEAD,
	CreatureView.COL_FAT,
	CreatureView.COL_MUSCLE,
	CreatureView.COL_BONE,
	CreatureView.COL_ORGAN,
	CreatureView.COL_DBG_NERVE,
	CreatureView.COL_DBG_VESSEL,
])
static var TISSUE_WORN: PackedColorArray = PackedColorArray([
	Color("2b211b"),
	CreatureView.COL_FAT_DEEP,
	CreatureView.COL_MUSCLE_DEEP,
	CreatureView.COL_BONE_WORN,
	CreatureView.COL_ORGAN_SPENT,
	CreatureView.COL_DBG_NERVE,
	CreatureView.COL_DBG_VESSEL,
])

## No section plane; or one per canonical axis of the lattice.
const SLICE_OFF: int = -1
const SLICE_LONG: int = 0
const SLICE_SIDE: int = 1
const SLICE_FLAT: int = 2

const PAD_X: float = 26.0
const PAD_Y: float = 30.0
## How quickly the presentation settles. The specimen must not spin as the
## animal turns or breathe as it walks, so both the upright rotation and the fit
## are eased rather than taken raw.
const SETTLE: float = 5.0
## Beats a second for the heart, which is what the vessel pulses ride on.
const HEART_RATE: float = 1.15
## How far off the cord the vessel overlay is drawn, in page pixels — see the
## note on `_draw_network`.
const VESSEL_OFFSET: float = 2.6
## Where the trackball stops being a sphere and becomes the sheet that carries
## on from it — Bell's hyperbolic skirt.
const BALL_EDGE: float = 0.70710678
## Orbit under which the projection is the plain top-down one.
const FLAT: float = 0.002
## How far a cell's ink is lifted or dropped by which way its own face points.
const RELIEF: float = 0.42
## How the cells thin out in X-ray, and the least a face may keep.
const XRAY_ALPHA: float = 0.30
## Page size below which cell outlines stop being drawn, and the most cells the
## outline pass will take on at all — past that the lattice is drawn by its own
## density and a wireframe over it is ink, not information.
const LATTICE_MIN_CELL: float = 3.4
const LATTICE_MOST: int = 9000
## How much a splat is grown past its own cell so a curved shell stays closed.
##
## A cell is marked with a patch of its own *surface* — a quad lying in the plane
## the cell's outward normal defines — rather than with a square stamped flat on
## the page. That is the whole of why the specimen no longer reads as a heap of
## boxes: a mark that lies along the body turns as the body turns, foreshortens
## where the surface rolls away, and meets its neighbours edge to edge because
## they are all patches of one surface. The grow is what closes the last of it:
## neighbouring patches overlap slightly, so a shell curving through a right
## angle has no seam to show the fat under it through.
const SPLAT_GROW: float = 1.45
## Least a patch may shrink to on the page however far its surface has rolled
## away from the eye, in page pixels. Without it the ring of cells right at the
## silhouette — every one of them very nearly edge-on — thins to nothing and
## leaves the body drawn with a bitten rim.
const SPLAT_MIN: float = 1.15
## How far past edge-on a surface has to face before its patch is dropped. A
## closed solid hides its own back, so half of every specimen is behind the rest
## of it and need never be drawn at all — this is the single largest saving in
## the pass and it costs one dot product. Slightly past zero so the ring exactly
## at the silhouette is kept and the outline stays closed.
const FACING_CUT: float = -0.22
## How much the ink darkens toward the silhouette, where the surface is rolling
## away from the eye. A curved body reads as curved because of this and the
## smooth normals together.
const RIM: float = 0.30
## Page cells of the pick grid. The hover test walks one bucket instead of every
## mark on the specimen — see `_pick`.
const PICK_BUCKET: float = 12.0
## Page size of a cell below which the specimen halves its marks — see `_lod_step`
## — the size it has to grow back past before they all come back, and how much
## each surviving mark grows to cover for the ones that went. The two sizes are
## apart so a specimen easing to a fit that lands on the line does not rebuild
## its whole draw list every frame deciding which side of it to be on.
const LOD_CELL: float = 2.2
const LOD_BACK: float = 2.6
const LOD_GROW: float = 1.42
## Most marks an X-ray will lay down before it starts taking one cell in every
## few — see the sieve in `_refresh_draw_list`.
const XRAY_MOST: int = 6000
## Shades each tissue's ink is banked in, across the whole range of how a surface
## can be turned. Colour arithmetic is the most expensive thing that used to
## happen per cell and the cheapest thing to have already done: thirty-two steps
## is finer than the eye reads on a two-pixel mark, and it turns four Color
## operations per cell into one array read.
const SHADES: int = 32

var creature: Creature = null
## Which of the five tissue layers are still on the specimen.
var layers: int = ALL_LAYERS
var show_vessels: bool = true
var show_nerves: bool = true
## Cell outlines. Off: the specimen is a body, and a wireframe over every cell of
## it is what made the thing read as masonry. It stays available because the
## lattice is what the whole system is built on and being able to see the actual
## cells is worth having — but as something asked for, not as the default face of
## the animal.
var show_lattice: bool = false
## Every cell thinned to a film, so the interior reads in place.
var xray: bool = false
## The section plane: which canonical axis it cuts across, and where along the
## body's own bounds it stands.
var slice_axis: int = SLICE_OFF
var slice_at: float = 1.0

## Where the specimen is being looked at from, in the animal's own frame.
var orient: Basis = Basis():
	set(value):
		orient = value.orthonormalized()
		_bake_orbit()
var spin: float:
	get:
		return atan2(-_eye.x, _eye.z)
	set(value):
		_aim(value, tilt)
var tilt: float:
	get:
		return asin(clampf(_eye.y, -1.0, 1.0))
	set(value):
		_aim(spin, value)
var roll: float:
	get:
		var snout := Vector2(-_page_x.y, -_page_y.y)
		if snout.length_squared() < 0.000001:
			return 0.0
		return Vector2(0.0, -1.0).angle_to(snout)

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
var _centre3: Vector3 = Vector3.ZERO
var _radius: float = 1.0
var _ball: float = 1.0

# Baked orbit: the rows of `orient`.
var _page_x: Vector3 = Vector3(1.0, 0.0, 0.0)
var _page_y: Vector3 = Vector3(0.0, 1.0, 0.0)
var _eye: Vector3 = Vector3(0.0, 0.0, 1.0)
var _solid: bool = false
var _relief: float = 0.0

var _hover_voxel: int = -1
var _orbiting: bool = false
var _grab: Vector3 = Vector3(0.0, 0.0, 1.0)
var _grabbed: Basis = Basis()

# --- the cell pass -----------------------------------------------------------
## Which lattice cells are currently on the specimen, rebuilt only when a filter,
## the section plane, the damage state or the lattice itself changes.
var _draw_list: PackedInt32Array = PackedInt32Array()
var _draw_key: int = 0
## The lattice's own bounds, for placing the section plane.
var _canon_lo: Vector3 = Vector3.ZERO
var _canon_hi: Vector3 = Vector3.ONE
var _canon_of: int = -1

## Posed station frames per patch, refreshed each frame from the ledger's own
## stations: centre, perpendicular, long-axis direction, mid height.
var _st_pos: Array = []
var _st_perp: Array = []
var _st_dir: Array = []
var _st_mid: Array = []

# --- the posed frame, as an affine map straight to the page --------------------
# Placing a cell used to be: pose it into the world, subtract the anchor, rotate,
# orbit, scale, offset. Six steps, per cell, per frame, on a body that can be
# fifty thousand cells.
#
# All six are linear in the cell's own four coordinates, and the coefficients
# depend only on which *station* the cell rides — of which there are a few dozen
# on the whole animal. So they are worked out once per station per frame and
# every cell after that is four multiply-adds. The same is done for the painter's
# depth, which is the same map read through the eye instead of the page.
#
# It is not an approximation: the pose is a lerp between two station frames plus
# two perpendicular offsets, which is affine within a station interval by
# construction. This is that fact spent rather than recomputed.
var _af_o: Array = []
var _af_s: Array = []
var _af_l: Array = []
var _af_f: Array = []
var _dp_o: Array = []
var _dp_s: Array = []
var _dp_l: Array = []
var _dp_f: Array = []
## The height axis, which no station changes: page offset and depth per world
## pixel above the station's own mid.
var _af_h: Vector2 = Vector2.ZERO
var _dp_h: float = 1.0

# Reused geometry: this redraws every frame, so the cell pass writes into these
# rather than allocating per cell.
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _depths := PackedVector2Array()
var _cell_page := PackedVector2Array()
var _cell_deep := PackedFloat32Array()
var _lattice_lines := PackedVector2Array()
var _run := PackedVector2Array()
var _run_gone := PackedByteArray()
var _order: Array[String] = []
## The two in-surface directions of each drawn cell, in the body's own axes.
## Fixed for as long as the draw list is, because a cell's surface direction is a
## fact about the animal rather than about where it is being looked at from.
var _tan_a := PackedVector3Array()
var _tan_b := PackedVector3Array()
## Which of the drawn cells survived the facing cut this frame, and how many.
var _shown := PackedInt32Array()
var _shown_count: int = 0
## Page-space buckets over the marks drawn last frame, so the hover test looks at
## the handful of cells under the pointer instead of all of them.
var _pick_grid: Dictionary = {}
var _pick_origin: Vector2 = Vector2.ZERO
## Every tissue at every shade — see SHADES — and what it was baked for.
var _shade := PackedColorArray()
var _shade_key: int = 0
## How many cells the draw list is stepping over, and what it was baked at.
var _lod: int = 1
## ...and how coarsely an X-ray is sieving the body, for the alpha to answer to.
var _sieve: int = 1
## Whether those buckets describe where the marks are *now*. Cleared as each
## frame begins and set by whichever of the drawing pass or the hover test placed
## them, so a pointer moving over a painted specimen reads the marks it can see
## rather than placing them all over again.
var _marks_fresh: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)


func set_ui_font(mono: Font) -> void:
	_mono = mono


func _process(delta: float) -> void:
	# In the *tree*, not this node's own flag: a stage inside a drawer that is
	# shut is still a visible node, and there are two of these stages.
	if not is_visible_in_tree():
		return
	_clock += delta
	_marks_fresh = false
	_settle(delta)
	queue_redraw()


## Forgets the settled presentation, so a different specimen arrives already
## upright and framed rather than easing across from where the last one sat.
func reset_fit() -> void:
	_fitted = false
	_hover_voxel = -1
	_draw_key = 0


## Puts the eye back over the animal's back, looking straight down.
func reset_orbit() -> void:
	orient = Basis()


func _aim(new_spin: float, new_tilt: float) -> void:
	orient = Basis(Vector3(1.0, 0.0, 0.0), new_tilt) * Basis(Vector3(0.0, 1.0, 0.0), new_spin)


func ball_radius() -> float:
	return _ball


func grab_ball(at: Vector2) -> void:
	_grab = _on_ball(at)
	_grabbed = orient


func turn_ball(at: Vector2) -> void:
	var to: Vector3 = _on_ball(at)
	var axis: Vector3 = _grab.cross(to)
	var span: float = axis.length()
	if span < 0.000001:
		orient = _grabbed
		return
	orient = Basis(axis / span, atan2(span, _grab.dot(to))) * _grabbed


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
	_reframe()


func layer_shown(layer: int) -> bool:
	return (layers & (1 << layer)) != 0


func set_layer_shown(layer: int, shown: bool) -> void:
	if shown:
		layers |= 1 << layer
	else:
		layers &= ~(1 << layer)


## The damage ledger this view reads wounds off, or null while there is nothing
## to show.
func tissue() -> TissueGrid:
	if not is_instance_valid(creature) or creature.anatomy == null:
		return null
	var grid: TissueGrid = creature.anatomy.tissue
	var body: TissueGrid.Patch = grid.patch(TissueGrid.BODY_KEY)
	return grid if body != null and body.live else null


## The cell lattice on the slab — the same one the physique counted.
func lattice() -> AnatomyLattice:
	var grid: TissueGrid = tissue()
	if grid == null or grid.lattice == null:
		return null
	var lat: AnatomyLattice = grid.lattice
	return lat if lat.count > 0 else null


# ----------------------------------------------------------- presentation ----

## Re-derives the transform that puts the creature on the page: upright, centred
## and as large as the stage will take it. The size is decided by the ball the
## animal fits inside, which is the one thing that keeps a drag from being a
## zoom — see the header.
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
	_rot = -PI * 0.5 - _heading
	_anchor = creature.body.head.pos

	# The animal's own box, in the upright frame and in all three axes, walked
	# over the ledger's stations — the same posed geometry the cells ride.
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for c in range(p.cols + 1):
			var a: Vector2 = (p.vert(c, 0) - _anchor).rotated(_rot)
			var b: Vector2 = (p.vert(c, p.rows) - _anchor).rotated(_rot)
			var deep: float = 0.0
			var base: int = c * (p.rows + 1)
			for r in range(p.rows + 1):
				deep = maxf(deep, p.halves[base + r])
			lo = Vector3(minf(lo.x, minf(a.x, b.x)), minf(lo.y, minf(a.y, b.y)),
				minf(lo.z, p.mids[c] - deep))
			hi = Vector3(maxf(hi.x, maxf(a.x, b.x)), maxf(hi.y, maxf(a.y, b.y)),
				maxf(hi.z, p.mids[c] + deep))
	if lo.x > hi.x:
		return
	lo.z = minf(lo.z, 0.0)
	hi.z = maxf(hi.z, 0.0)

	var target_centre: Vector3 = (lo + hi) * 0.5
	var target_radius: float = maxf((hi - lo).length() * 0.5, 0.5)
	if _fitted:
		var ease: float = 1.0 - exp(-SETTLE * delta)
		_radius = lerpf(_radius, target_radius, ease)
		_centre3 = _centre3.lerp(target_centre, ease)
	else:
		_radius = target_radius
		_centre3 = target_centre
		_fitted = true

	var room: Vector2 = (size - Vector2(PAD_X * 2.0, PAD_Y * 2.0)).max(Vector2(1.0, 1.0))
	_ball = minf(room.x, room.y) * 0.5
	_scale = _ball / _radius
	_reframe()

	# What the animal actually covers on the page, for the organ leader lines.
	_lo = Vector2(INF, INF)
	_hi = Vector2(-INF, -INF)
	for i in 8:
		var at: Vector2 = _origin + _flatten(
			Vector2(hi.x if (i & 1) != 0 else lo.x, hi.y if (i & 2) != 0 else lo.y),
			hi.z if (i & 4) != 0 else lo.z) * _scale
		_lo = _lo.min(at)
		_hi = _hi.max(at)


func _reframe() -> void:
	if not _fitted:
		return
	_centre = _flatten(Vector2(_centre3.x, _centre3.y), _centre3.z)
	_origin = size * 0.5 - _centre * _scale


## Where a place on the animal lands on the page. The whole of the relationship
## between the specimen and the creature is this and `_flatten`: one rotation,
## one orbit, one scale, one offset. There is no second geometry in this file.
func project(world: Vector2, height: float) -> Vector2:
	return _origin + _flatten((world - _anchor).rotated(_rot), height) * _scale


## The same for a place on the ground under the animal.
func to_panel(world: Vector2) -> Vector2:
	return project(world, 0.0)


func _flatten(turned: Vector2, height: float) -> Vector2:
	return Vector2(
		turned.x * _page_x.x + turned.y * _page_x.y + height * _page_x.z,
		turned.x * _page_y.x + turned.y * _page_y.y + height * _page_y.z)


## How near the eye a point is — the painter's-order key.
func _towards(turned: Vector2, height: float) -> float:
	return turned.x * _eye.x + turned.y * _eye.y + height * _eye.z


func fitted() -> bool:
	return _fitted


## Limbs before the body, so the legs read as being underneath the torso exactly
## as they do in the field.
func _patch_order() -> Array[String]:
	if _order.is_empty():
		_order = TissueGrid.LIMB_KEYS.duplicate()
		_order.append(TissueGrid.BODY_KEY)
	return _order


# --------------------------------------------------------------- the cells ----

## Whether a tissue's cells are currently on the specimen.
func tissue_shown(t: int) -> bool:
	if t == AnatomyLattice.NERVE:
		return show_nerves
	if t == AnatomyLattice.VESSEL:
		return show_vessels
	return layer_shown(t)


## Where the section plane currently stands, in the lattice's own frame.
func slice_plane() -> float:
	if slice_axis < 0:
		return INF
	var lo: float = _canon_lo[slice_axis] - AnatomyLattice.CELL
	var hi: float = _canon_hi[slice_axis] + AnatomyLattice.CELL
	return lerpf(lo, hi, clampf(slice_at, 0.0, 1.0))


## Re-derives which cells are on the specimen. Runs only when something that
## decides membership changes; a frame where nothing did reuses the list.
func _refresh_draw_list(lat: AnatomyLattice, grid: TissueGrid) -> void:
	var step: int = _lod_step()
	var key: int = hash([layers, show_nerves, show_vessels, xray, slice_axis,
		snappedf(slice_at, 0.002), grid.revision, lat.count, step])
	if key == _draw_key:
		return
	_draw_key = key
	_lod = step

	if _canon_of != lat.count:
		_canon_of = lat.count
		_canon_lo = Vector3(INF, INF, INF)
		_canon_hi = Vector3(-INF, -INF, -INF)
		for i in lat.count:
			_canon_lo = _canon_lo.min(lat.pos[i])
			_canon_hi = _canon_hi.max(lat.pos[i])

	var plane: float = slice_plane()
	var sliced: bool = slice_axis >= 0
	# Which cells count as present, for the surface test below: shown, standing,
	# and on the kept side of the section plane. `hidden` is the same statement
	# said as a bitmask, so the surface test can be one AND per cell.
	var present := PackedByteArray()
	present.resize(lat.count)
	var hidden: int = AnatomyLattice.OPEN_BIT
	for t in AnatomyLattice.TISSUES:
		if not tissue_shown(t):
			hidden |= 1 << t
	# Cells a filter took away for a reason the mask cannot see — eaten, or on the
	# far side of a section plane. Their neighbours are the only cells the mask can
	# be wrong about, and re-testing exactly those is what keeps the fast path
	# exact instead of approximate.
	var lifted := PackedInt32Array()
	var listed := PackedByteArray()
	listed.resize(lat.count)
	_draw_list.resize(0)
	# One walk of the animal, not two. Whether a cell is on the surface of what is
	# being shown depends on the mask alone, so it can be answered in the same
	# pass that decides whether the cell is there at all — and on a body of fifty
	# thousand cells the second walk was the whole cost of changing a filter.
	# Hoisted into locals for the same reason: a property read per cell per array
	# is a hundred thousand property reads.
	var kinds: PackedByteArray = lat.kind
	var gone: PackedByteArray = lat.gone
	var neighbours: PackedByteArray = lat.around
	var odd: PackedByteArray = lat.parity
	var where: PackedVector3Array = lat.pos
	var thin: bool = step > 1
	# X-ray is the one view with no surface to it — every cell of the body is a
	# mark, so a big animal asks for the whole census at once and gets tens of
	# thousands of films stacked on the same pixel. Past a budget it takes one
	# cell in every few instead, which on something already translucent reads as
	# the same body seen through and costs a sixth of it.
	var sieve: int = maxi(1, int(ceil(float(lat.count) / float(XRAY_MOST)))) if xray else 1
	_sieve = sieve
	for i in lat.count:
		if (hidden & (1 << int(kinds[i]))) != 0:
			continue
		if gone[i] != 0 or (sliced and where[i][slice_axis] > plane):
			lifted.append(i)
			continue
		present[i] = 1
		if sieve > 1 and i % sieve != 0:
			continue
		if thin and not xray and odd[i] != 0:
			continue
		# The surface of the visible solid: a cell that touches something not
		# being drawn. What a filter peels away exposes the faces beneath it,
		# which is the whole of how looking inside works.
		if xray or (int(neighbours[i]) & hidden) != 0:
			listed[i] = 1
			_draw_list.append(i)
	if xray:
		_bake_tangents(lat)
		return

	for i in lifted:
		var base: int = i * 6
		for k in 6:
			var n: int = lat.neighbor[base + k]
			if n < 0 or present[n] == 0 or listed[n] != 0:
				continue
			if step > 1 and lat.parity[n] != 0:
				continue
			listed[n] = 1
			_draw_list.append(n)
	_bake_tangents(lat)


## Half the size of one mark, on the page. One statement, so the marks, the ring
## under the pointer and the reach the hover test searches cannot disagree.
func _mark_half() -> float:
	return AnatomyLattice.CELL * 0.5 * _scale * SPLAT_GROW \
		* (LOD_GROW if _lod > 1 else 1.0)


## How many cells the specimen skips over between marks.
##
## Below a couple of page pixels a cell is smaller than the mark that can honestly
## be made for it, and drawing every one is spending the frame on marks that land
## on top of each other. Past that line the specimen takes every other cell — a
## checkerboard through the solid, so any surface through it thins evenly — and
## grows what is left to cover the gap. It is the only place the specimen is ever
## less than every cell, it only happens on bodies too big to resolve anyway, and
## it is a statement about the page rather than about the animal.
func _lod_step() -> int:
	var page: float = AnatomyLattice.CELL * _scale
	if _lod > 1:
		return 1 if page >= LOD_BACK else 2
	return 1 if page >= LOD_CELL else 2


## The plane each drawn cell's mark lies in.
##
## A cell is marked with a patch of the surface it stands on, so the mark needs
## two directions across that surface. They come off the cell's own outward
## direction — which the carve worked out from the shape of the animal, not from
## the shape of the grid — so the marks lie along the body and turn with it, and
## the specimen reads as a skin rather than as a pile of cubes.
##
## Baked with the draw list rather than per frame: which way a piece of an animal
## faces is a fact about the animal, and turning the specimen does not change it.
func _bake_tangents(lat: AnatomyLattice) -> void:
	var n: int = _draw_list.size()
	_tan_a.resize(n)
	_tan_b.resize(n)
	for j in n:
		var out: Vector3 = lat.normal[_draw_list[j]]
		# Any direction not along the normal will do to start; the pair that comes
		# out is orthonormal either way, and which of the infinitely many rotations
		# of the patch about its own normal is used cannot be seen.
		var seed := Vector3(0.0, 0.0, 1.0) if absf(out.z) < 0.9 else Vector3(1.0, 0.0, 0.0)
		var a: Vector3 = seed.cross(out)
		if a.length_squared() < 0.000001:
			a = Vector3(0.0, 1.0, 0.0)
		a = a.normalized()
		_tan_a[j] = a
		_tan_b[j] = out.cross(a).normalized()


## Refreshes the posed station frames the cells ride, once per frame.
func _refresh_stations(grid: TissueGrid) -> void:
	if _st_pos.size() != AnatomyLattice.PATCH_KEYS.size():
		_st_pos.resize(AnatomyLattice.PATCH_KEYS.size())
		_st_perp.resize(AnatomyLattice.PATCH_KEYS.size())
		_st_dir.resize(AnatomyLattice.PATCH_KEYS.size())
		_st_mid.resize(AnatomyLattice.PATCH_KEYS.size())
	for pk in AnatomyLattice.PATCH_KEYS.size():
		var p: TissueGrid.Patch = grid.patch(AnatomyLattice.PATCH_KEYS[pk])
		if p == null or not p.live:
			_st_pos[pk] = null
			continue
		var stations: int = p.cols + 1
		var pos: PackedVector2Array = _st_pos[pk] if _st_pos[pk] != null \
			else PackedVector2Array()
		var perp: PackedVector2Array = _st_perp[pk] if _st_perp[pk] != null \
			else PackedVector2Array()
		var dir: PackedVector2Array = _st_dir[pk] if _st_dir[pk] != null \
			else PackedVector2Array()
		var mid: PackedFloat32Array = _st_mid[pk] if _st_mid[pk] != null \
			else PackedFloat32Array()
		pos.resize(stations)
		perp.resize(stations)
		dir.resize(stations)
		mid.resize(stations)
		for c in stations:
			var a: Vector2 = p.vert(c, 0)
			var b: Vector2 = p.vert(c, p.rows)
			pos[c] = (a + b) * 0.5
			var across: Vector2 = b - a
			perp[c] = across.normalized() if across.length_squared() > 0.000001 \
				else Vector2.RIGHT
			mid[c] = p.mids[c]
		for c in stations:
			var ahead: Vector2 = pos[mini(c + 1, stations - 1)] - pos[maxi(c - 1, 0)]
			dir[c] = ahead.normalized() if ahead.length_squared() > 0.000001 \
				else Vector2(-perp[c].y, perp[c].x)
		_st_pos[pk] = pos
		_st_perp[pk] = perp
		_st_dir[pk] = dir
		_st_mid[pk] = mid
	_bake_frames()


## Turns the posed stations into the per-station affine the cell pass reads —
## see the note on `_af_o`. Everything here is done a few dozen times a frame so
## that nothing has to be done tens of thousands of times.
func _bake_frames() -> void:
	var patches: int = AnatomyLattice.PATCH_KEYS.size()
	if _af_o.size() != patches:
		_af_o.resize(patches)
		_af_s.resize(patches)
		_af_l.resize(patches)
		_af_f.resize(patches)
		_dp_o.resize(patches)
		_dp_s.resize(patches)
		_dp_l.resize(patches)
		_dp_f.resize(patches)
	_af_h = Vector2(_page_x.z, _page_y.z) * _scale
	_dp_h = _eye.z
	for pk in patches:
		if _st_pos[pk] == null:
			_af_o[pk] = null
			continue
		var pos: PackedVector2Array = _st_pos[pk]
		var perp: PackedVector2Array = _st_perp[pk]
		var dir: PackedVector2Array = _st_dir[pk]
		var mids: PackedFloat32Array = _st_mid[pk]
		var stations: int = pos.size()
		var o := PackedVector2Array()
		var s := PackedVector2Array()
		var l := PackedVector2Array()
		var f := PackedVector2Array()
		var od := PackedFloat32Array()
		var sd := PackedFloat32Array()
		var ld := PackedFloat32Array()
		var fd := PackedFloat32Array()
		o.resize(stations)
		s.resize(stations)
		l.resize(stations)
		f.resize(stations)
		od.resize(stations)
		sd.resize(stations)
		ld.resize(stations)
		fd.resize(stations)
		for c in stations:
			var here: Vector2 = (pos[c] - _anchor).rotated(_rot)
			o[c] = _origin + _flatten(here, mids[c]) * _scale
			od[c] = _towards(here, mids[c])
			var across: Vector2 = perp[c].rotated(_rot)
			l[c] = _flatten(across, 0.0) * _scale
			ld[c] = _towards(across, 0.0)
			var along: Vector2 = dir[c].rotated(_rot)
			f[c] = _flatten(along, 0.0) * _scale
			fd[c] = _towards(along, 0.0)
			var next: int = mini(c + 1, stations - 1)
			var step: Vector2 = (pos[next] - pos[c]).rotated(_rot)
			var rise: float = mids[next] - mids[c]
			s[c] = _flatten(step, rise) * _scale
			sd[c] = _towards(step, rise)
		_af_o[pk] = o
		_af_s[pk] = s
		_af_l[pk] = l
		_af_f[pk] = f
		_dp_o[pk] = od
		_dp_s[pk] = sd
		_dp_l[pk] = ld
		_dp_f[pk] = fd


## One cell's place on the page, and how near the eye it is — the same posing as
## `_voxel_world` with the whole chain of transforms already folded into the
## station's own affine. Four multiply-adds, and it is what the cell pass runs on.
func _cell_at(lat: AnatomyLattice, i: int) -> Vector3:
	var pk: int = lat.patch_of[i]
	if pk >= _af_o.size() or _af_o[pk] == null:
		return Vector3.ZERO
	var o: PackedVector2Array = _af_o[pk]
	var s: float = clampf(lat.station[i], 0.0, float(o.size() - 1))
	var c: int = mini(int(s), o.size() - 1)
	var f: float = s - float(c)
	var side: float = lat.lat[i]
	var ahead: float = lat.fore[i]
	var up: float = lat.lift[i]
	var page: Vector2 = o[c] + (_af_s[pk] as PackedVector2Array)[c] * f \
		+ (_af_l[pk] as PackedVector2Array)[c] * side \
		+ (_af_f[pk] as PackedVector2Array)[c] * ahead + _af_h * up
	var deep: float = (_dp_o[pk] as PackedFloat32Array)[c] \
		+ (_dp_s[pk] as PackedFloat32Array)[c] * f \
		+ (_dp_l[pk] as PackedFloat32Array)[c] * side \
		+ (_dp_f[pk] as PackedFloat32Array)[c] * ahead + _dp_h * up
	return Vector3(page.x, page.y, deep)


# --------------------------------------------------------------- drawing ----

func _draw() -> void:
	var grid: TissueGrid = tissue()
	var lat: AnatomyLattice = lattice()
	if grid == null or lat == null or not _fitted:
		_draw_empty()
		return
	lat.refresh_damage(grid)
	_refresh_stations(grid)
	_refresh_draw_list(lat, grid)
	_draw_cells(lat, grid)

	var state: BodyState = creature.anatomy.state
	if show_vessels:
		_draw_network(grid, state.plan.vessels, state.vessels, COL_VESSEL, 3, 46.0, true,
			VESSEL_OFFSET)
	if show_nerves:
		_draw_network(grid, state.plan.nerves, state.nerves, COL_NERVE, 2, 150.0, false, 0.0)
	if show_vessels:
		_draw_organ(grid, lat, BodyPlan.HEART, COL_VESSEL, "HEART", true)
	if show_nerves:
		_draw_organ(grid, lat, BodyPlan.BRAIN, COL_NERVE, "BRAIN", false)
	_draw_hover(lat)


func _draw_empty() -> void:
	if _mono == null:
		return
	var text: String = "NO SPECIMEN"
	var width: float = _mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
	draw_string(_mono, Vector2((size.x - width) * 0.5, size.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(INK, 0.30))


## Every cell on the specimen, painter-sorted, one patch of surface apiece.
##
## A cell is marked with a quad lying in the plane its own outward direction
## defines, at the cell's own place, grown just past its own size. Three things
## follow from that and they are the whole difference between this and a heap of
## boxes:
##
##   * **It is seamless.** Neighbouring cells on a shell are neighbouring patches
##     of one surface, so their marks meet and overlap rather than tiling the page
##     with squares that come apart wherever the surface is not facing the eye.
##     The holes the skin used to show the fat through were exactly that failure.
##   * **It is curved.** The direction is the one the carve took off the shape of
##     the animal — the ellipse's own outward normal — rather than off the face of
##     a cube, so the marks roll around the body and the shading is a smooth
##     gradient over a solid instead of six flat greys.
##   * **It is cheaper.** A closed body hides its own back, so every mark facing
##     away is dropped for the price of one dot product, and the half that
##     remains is the half that could be seen.
##
## Every cell is still exactly where it is. Nothing here moves a cell, resamples
## it or smooths it away: the mark is centred on the cell's own posed position
## and is the size of the cell. What changed is the shape of the mark.
func _draw_cells(lat: AnatomyLattice, grid: TissueGrid) -> void:
	var listed: int = _draw_list.size()
	if listed == 0:
		_shown_count = 0
		return
	if _cell_page.size() != listed:
		_cell_page.resize(listed)
		_cell_deep.resize(listed)
		_shown.resize(listed)
	# Grown to the whole draw list and cut back to what survived the facing test
	# before the upload, so a frame that hides half the body uploads half of one.
	_points.resize(listed * 4)
	_colors.resize(listed * 4)
	_depths.resize(listed)

	# In world pixels: the three axis vectors below already carry the page scale,
	# because they are page offsets per world pixel of the body.
	var half: float = AnatomyLattice.CELL * 0.5 * SPLAT_GROW \
		* (LOD_GROW if _lod > 1 else 1.0)
	var floor_page: float = SPLAT_MIN * 0.5
	var alpha: float = 1.0
	if xray:
		# Thinner marks, but fewer of them where the sieve has been at work, so
		# the body reads through at about the same weight either way.
		alpha = clampf(XRAY_ALPHA * sqrt(float(maxi(_sieve, 1))), XRAY_ALPHA, 0.75)
	_bake_shades(alpha)
	# The ledger patch each cell's wear is read off, taken once rather than looked
	# up by name for every cell on the animal — and only where there is wear to
	# read. On a sound body every cell takes its ink straight out of the bank.
	var worn: Array = []
	for pk in AnatomyLattice.PATCH_KEYS.size():
		var p: TissueGrid.Patch = grid.patch(AnatomyLattice.PATCH_KEYS[pk])
		worn.append(p if p != null and p.live and not p.damaged.is_empty() else null)
	# X-ray is the one view with nothing solid in it, so there is no back for the
	# body to hide and every mark has to be kept.
	var cut: float = -2.0 if xray else FACING_CUT
	var n: int = 0
	for j in listed:
		var i: int = _draw_list[j]
		var pk: int = lat.patch_of[i]
		if pk >= _af_o.size() or _af_o[pk] == null:
			continue
		var out: Vector3 = lat.normal[i]
		# The body's own three axes as this station has them: `f` is snout-to-tail,
		# `l` flank-to-flank, and the height is the same everywhere. A cell's
		# stored outward direction is quoted in exactly those three, which is what
		# lets it be turned into a patch of surface with three multiplies.
		var xd: PackedFloat32Array = _dp_f[pk]
		var yd: PackedFloat32Array = _dp_l[pk]
		var o: PackedVector2Array = _af_o[pk]
		var s: float = clampf(lat.station[i], 0.0, float(o.size() - 1))
		var c: int = mini(int(s), o.size() - 1)
		# Which way this piece of surface is turned, against the eye. Read through
		# the station's own frame, so a bent spine's flank faces where the bend
		# actually put it rather than where a straight animal's would be.
		var lit: float = out.x * xd[c] + out.y * yd[c] + out.z * _dp_h
		if lit < cut:
			continue

		var f: float = s - float(c)
		var side: float = lat.lat[i]
		var ahead: float = lat.fore[i]
		var up: float = lat.lift[i]
		var ax: Vector2 = (_af_f[pk] as PackedVector2Array)[c]
		var ay: Vector2 = (_af_l[pk] as PackedVector2Array)[c]
		var page: Vector2 = o[c] + (_af_s[pk] as PackedVector2Array)[c] * f \
			+ ay * side + ax * ahead + _af_h * up
		var deep: float = (_dp_o[pk] as PackedFloat32Array)[c] \
			+ (_dp_s[pk] as PackedFloat32Array)[c] * f \
			+ yd[c] * side + xd[c] * ahead + _dp_h * up
		_cell_page[n] = page
		_cell_deep[n] = deep
		_shown[n] = i
		_depths[n] = Vector2(deep, float(n))

		# The two in-surface directions, carried onto the page through the same
		# three axes. A patch rolling away from the eye foreshortens because these
		# do, which is what makes the body read as a volume.
		var ta: Vector3 = _tan_a[j]
		var tb: Vector3 = _tan_b[j]
		var ea: Vector2 = (ax * ta.x + ay * ta.y + _af_h * ta.z) * half
		var eb: Vector2 = (ax * tb.x + ay * tb.y + _af_h * tb.z) * half
		# ...but never to nothing. The ring of cells at the silhouette is very
		# nearly edge-on and would otherwise vanish, taking the outline with it.
		ea = _at_least(ea, eb, floor_page)
		eb = _at_least(eb, ea, floor_page)

		var t: int = lat.kind[i]
		var band: int = clampi(int((lit + 1.0) * (0.5 * float(SHADES))), 0, SHADES - 1)
		var ink: Color = _shade[t * SHADES + band]
		if worn[pk] != null:
			ink = _worn(lat, grid, worn[pk], i, ink, t)
		var v: int = n * 4
		_points[v] = page - ea - eb
		_points[v + 1] = page + ea - eb
		_points[v + 2] = page + ea + eb
		_points[v + 3] = page - ea + eb
		_colors[v] = ink
		_colors[v + 1] = ink
		_colors[v + 2] = ink
		_colors[v + 3] = ink
		n += 1
	_shown_count = n
	if n == 0:
		return

	# Far side of the animal first, or a rolled specimen shows its back through
	# its own belly.
	_depths.resize(n)
	_depths.sort()
	_indices.resize(n * 6)
	var t: int = 0
	for j in n:
		var at: int = int(_depths[j].y) * 4
		_indices[t] = at
		_indices[t + 1] = at + 1
		_indices[t + 2] = at + 2
		_indices[t + 3] = at
		_indices[t + 4] = at + 2
		_indices[t + 5] = at + 3
		t += 6
	_points.resize(n * 4)
	_colors.resize(n * 4)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)
	_index_marks()

	if show_lattice and not xray and n <= LATTICE_MOST \
			and AnatomyLattice.CELL * _scale >= LATTICE_MIN_CELL:
		_lattice_lines.resize(0)
		for j in n:
			var v: int = j * 4
			_lattice_lines.append_array([
				_points[v], _points[v + 1], _points[v + 1], _points[v + 2],
				_points[v + 2], _points[v + 3], _points[v + 3], _points[v]])
		draw_multiline(_lattice_lines, COL_LATTICE, 0.5, true)


## Keeps a patch from collapsing as its surface turns edge-on, by widening it
## across the direction it still has. Only ever grows a mark, and only the ones
## at the very rim.
static func _at_least(edge: Vector2, other: Vector2, least: float) -> Vector2:
	var span: float = edge.length()
	if span >= least:
		return edge
	if span > 0.0001:
		return edge * (least / span)
	# Perfectly edge-on: there is no direction left in the mark itself, so it
	# takes one across its partner.
	var across: Vector2 = other.normalized() if other.length_squared() > 0.000001 \
		else Vector2.RIGHT
	return Vector2(-across.y, across.x) * least


## Places every drawn cell on the page without drawing it, for a hover test
## arriving before the specimen has been painted — which is every hover in a
## headless run, and the first one after a filter changes. The drawing pass does
## the same placement inline as part of the work it is already doing, so this is
## never run in the ordinary way of things.
func _place_marks(lat: AnatomyLattice) -> void:
	var listed: int = _draw_list.size()
	if _cell_page.size() != listed:
		_cell_page.resize(listed)
		_cell_deep.resize(listed)
		_shown.resize(listed)
	var cut: float = -2.0 if xray else FACING_CUT
	var n: int = 0
	for j in listed:
		var i: int = _draw_list[j]
		var pk: int = lat.patch_of[i]
		if pk >= _af_o.size() or _af_o[pk] == null:
			continue
		var out: Vector3 = lat.normal[i]
		var xd: PackedFloat32Array = _dp_f[pk]
		var yd: PackedFloat32Array = _dp_l[pk]
		var o: PackedVector2Array = _af_o[pk]
		var s: float = clampf(lat.station[i], 0.0, float(o.size() - 1))
		var c: int = mini(int(s), o.size() - 1)
		if out.x * xd[c] + out.y * yd[c] + out.z * _dp_h < cut:
			continue
		var f: float = s - float(c)
		var side: float = lat.lat[i]
		var ahead: float = lat.fore[i]
		var up: float = lat.lift[i]
		_cell_page[n] = o[c] + (_af_s[pk] as PackedVector2Array)[c] * f \
			+ (_af_l[pk] as PackedVector2Array)[c] * side \
			+ (_af_f[pk] as PackedVector2Array)[c] * ahead + _af_h * up
		_cell_deep[n] = (_dp_o[pk] as PackedFloat32Array)[c] \
			+ (_dp_s[pk] as PackedFloat32Array)[c] * f \
			+ yd[c] * side + xd[c] * ahead + _dp_h * up
		_shown[n] = i
		n += 1
	_shown_count = n
	_index_marks()


## Buckets this frame's marks by where they landed, for the hover test.
func _index_marks() -> void:
	_marks_fresh = true
	_pick_grid.clear()
	if _shown_count == 0:
		return
	_pick_origin = _cell_page[0]
	for j in _shown_count:
		var at: Vector2 = (_cell_page[j] - _pick_origin) / PICK_BUCKET
		# A plain Array, not a packed one: packed arrays inside a container copy
		# on every read, which would make indexing cost more than the walk it is
		# here to avoid.
		var key: int = (int(floor(at.x)) << 20) ^ int(floor(at.y))
		var bucket = _pick_grid.get(key)
		if bucket == null:
			bucket = []
			_pick_grid[key] = bucket
		bucket.append(j)


## Every tissue at every turn of the surface, banked once a frame.
##
## The shade of a mark depends on two things and only two: which tissue it is and
## how far its surface is turned from the eye. Both are small sets, so the whole
## range of answers is a table of a couple of hundred colours — and the cell pass
## then costs one array read where it used to cost a relief lerp, a rim lerp and
## an alpha write per cell, on tens of thousands of cells.
func _bake_shades(alpha: float) -> void:
	# Nothing in the bank depends on the frame except the alpha and how far the
	# eye has come off the vertical, so a frame that changed neither reuses it.
	var key: int = hash([snappedf(alpha, 0.005), snappedf(_relief, 0.01)])
	if key == _shade_key and _shade.size() == AnatomyLattice.TISSUES * SHADES:
		return
	_shade_key = key
	var want: int = AnatomyLattice.TISSUES * SHADES
	if _shade.size() != want:
		_shade.resize(want)
	for t in AnatomyLattice.TISSUES:
		for k in SHADES:
			var lit: float = -1.0 + 2.0 * (float(k) + 0.5) / float(SHADES)
			# Toward the rim the surface is turning away, and darkening it there
			# is most of what makes a drawn body look round.
			var ink: Color = _relieved(TISSUE_INK[t], lit)
			ink = ink.lerp(Color(INK, 1.0), RIM * (1.0 - absf(lit)))
			ink.a = alpha
			_shade[t * SHADES + k] = ink


## The same ink, dragged toward the tissue's spent shade by how much of it this
## cell's ledger column has lost. Only ever asked of a column that has actually
## been bitten — see the `worn` gate in the cell pass.
func _worn(lat: AnatomyLattice, grid: TissueGrid, p: TissueGrid.Patch, i: int,
		ink: Color, t: int) -> Color:
	if t > AnatomyLattice.ORGAN:
		return ink
	var cell: int = lat.cell_of[i]
	if p.touched[cell] == 0:
		return ink
	var full: float = _layer_full(grid, p, cell, t)
	if full <= 0.0:
		return ink
	return ink.lerp(TISSUE_WORN[t],
		clampf(1.0 - p.hp[cell * TissueGrid.LAYERS + t] / full, 0.0, 1.0) * 0.85)


func _layer_full(grid: TissueGrid, p: TissueGrid.Patch, cell: int, layer: int) -> float:
	match layer:
		AnatomyLattice.SKIN:
			return TissueGrid.SKIN_HP
		AnatomyLattice.FAT:
			return grid.fat_capacity(p, cell)
		AnatomyLattice.MUSCLE:
			return TissueGrid.MUSCLE_HP
		AnatomyLattice.BONE:
			return TissueGrid.BONE_HP if p.bone[cell] != 0 else 0.0
		_:
			return TissueGrid.ORGAN_HP if int(p.organ[cell]) != BodyPlan.NO_ORGAN else 0.0


## A face's own colour with the form of the body on it: lifted toward the paper
## where it is turned toward the eye, dropped toward the ink where away.
func _relieved(color: Color, lit: float) -> Color:
	var lift: float = (0.25 + 0.75 * _relief) * RELIEF * clampf(lit, -1.0, 1.0)
	if lift >= 0.0:
		return color.lerp(Color(PAPER, color.a), lift)
	return color.lerp(Color(INK, color.a), -lift)


# -------------------------------------------------------------- networks ----

## One supply network, laid along the ledger cells it actually passes through.
## Width and alpha carry what *arrives* rather than what survives locally, so a
## sound run still fades out behind a cut upstream of it.
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
## it.
func _gather_run(grid: TissueGrid, runs: Array[BodyPlan.Conduit],
		run: BodyPlan.Conduit, offset: float) -> void:
	var p: TissueGrid.Patch = grid.patch(run.patch_key)
	var count: int = run.cells.size()
	_run.resize(count)
	_run_gone.resize(count)
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
## arrives in beats.
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

## An organ, at the lattice cells it actually occupies, on a leader clear of the
## body. Drawn from surviving cells only; the ring carries how much of it is
## left, and the heart's own beat is the same clock the blood pulses ride on.
func _draw_organ(grid: TissueGrid, lat: AnatomyLattice, which: int, tint: Color,
		label: String, beat: bool) -> void:
	# Off the organ's own cells, gathered when the lattice was built. It used to
	# be a walk of the whole animal, twice a frame, to find a hundred cells in
	# fifty thousand.
	var mine: PackedInt32Array = lat.organ_cells(which)
	var at := Vector2.ZERO
	var found: int = 0
	for i in mine:
		if lat.gone[i] != 0:
			continue
		var p: Vector3 = _cell_at(lat, i)
		at += Vector2(p.x, p.y)
		found += 1
	if found == 0:
		return
	at /= float(found)
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
	var width: float = _mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
	var edge: float = minf(maxf(_hi.x + 6.0, at.x + radius + 12.0), size.x - width - 12.0)
	draw_line(Vector2(at.x + radius + 2.0, at.y), Vector2(edge, at.y),
		Color(tint, 0.34), 0.7, true)
	draw_string(_mono, Vector2(edge + 4.0, at.y + 3.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(tint, 0.78))


# ------------------------------------------------------------- hit-test ----

func _draw_hover(lat: AnatomyLattice) -> void:
	if _hover_voxel < 0 or _hover_voxel >= lat.count:
		return
	var p: Vector3 = _cell_at(lat, _hover_voxel)
	# A ring rather than a box, for the same reason the marks are patches rather
	# than squares: what is under the pointer is a piece of a surface.
	draw_arc(Vector2(p.x, p.y), _mark_half() * 1.6, 0.0, TAU, 14, INK, 1.3, true)


## Dragging turns the specimen; moving over it reads a cell. Which one is
## happening is decided by whether a button is down and nowhere else.
func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT:
		if click.double_click:
			reset_orbit()
		_orbiting = click.pressed
		if click.pressed:
			grab_ball(click.position)
			_hover_voxel = -1
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
	if _hover_voxel >= 0:
		_hover_voxel = -1
		cell_hovered.emit("", false)


## Which cell is under the cursor: the nearest drawn cell whose mark covers the
## pointer, tested against the cells exactly as they were last drawn — so a
## rolled specimen's near leg beats the belly behind it, and a peeled or
## sectioned specimen picks what is actually showing.
func _pick(at: Vector2) -> void:
	var lat: AnatomyLattice = lattice()
	var grid: TissueGrid = tissue()
	if lat == null or grid == null or not _fitted:
		return
	_refresh_stations(grid)
	_refresh_draw_list(lat, grid)
	if not _marks_fresh:
		_place_marks(lat)
	if _shown_count == 0:
		return
	var half: float = maxf(_mark_half(), 2.0)
	var found: int = -1
	var nearest: float = -INF
	# Only the marks in the buckets the pointer's own reach covers, against the
	# positions they were actually drawn at. What is picked is therefore exactly
	# what is showing — a rolled specimen's near leg beats the belly behind it,
	# and a peeled or sectioned one picks what a filter left standing.
	var span: int = int(ceil(half / PICK_BUCKET))
	var home: Vector2 = (at - _pick_origin) / PICK_BUCKET
	var hx: int = int(floor(home.x))
	var hy: int = int(floor(home.y))
	for ox in range(hx - span, hx + span + 1):
		for oy in range(hy - span, hy + span + 1):
			var bucket = _pick_grid.get((ox << 20) ^ oy)
			if bucket == null:
				continue
			for j in bucket:
				var page: Vector2 = _cell_page[j]
				if absf(page.x - at.x) > half or absf(page.y - at.y) > half:
					continue
				if _cell_deep[j] <= nearest:
					continue
				nearest = _cell_deep[j]
				found = _shown[j]
	if found >= 0:
		if _hover_voxel != found:
			_hover_voxel = found
			cell_hovered.emit(_readout(lat, grid, found), lat.gone[found] != 0)
		return
	if _hover_voxel >= 0:
		_hover_voxel = -1
		cell_hovered.emit("", false)


## What that cell is: where it is in the animal, what tissue it is, which named
## structure it belongs to, and how much of its column's tissue still stands.
func _readout(lat: AnatomyLattice, grid: TissueGrid, i: int) -> String:
	var region: String = grid.plan.region_name(int(lat.region[i])).to_upper()
	var bits: PackedStringArray = PackedStringArray()
	bits.append(region)
	var named: int = int(lat.part[i])
	var t: int = lat.kind[i]
	if named != AnatomyLattice.PART_NONE:
		bits.append(AnatomyLattice.PART_NAMES[named].to_upper())
	elif int(lat.organ_of[i]) != BodyPlan.NO_ORGAN:
		bits.append(BodyPlan.ORGAN_NAMES[lat.organ_of[i]].to_upper())
	else:
		bits.append(AnatomyLattice.TISSUE_NAMES[t].to_upper())

	var p: TissueGrid.Patch = grid.patch(AnatomyLattice.PATCH_KEYS[lat.patch_of[i]])
	if p != null and p.live:
		var cell: int = lat.cell_of[i]
		if p.gone[cell] != 0:
			bits.append("HOLE THROUGH")
		elif t <= AnatomyLattice.ORGAN:
			var full: float = _layer_full(grid, p, cell, t)
			if full > 0.0:
				bits.append("%d%%" % int(round(100.0 * clampf(
					p.hp[cell * TissueGrid.LAYERS + t] / full, 0.0, 1.0))))
	var c: Vector3 = lat.pos[i]
	bits.append("CELL %d·%d·%d" % [int(round(c.x / AnatomyLattice.CELL)),
		int(round(c.y / AnatomyLattice.CELL)), int(round(c.z / AnatomyLattice.CELL))])
	return " · ".join(bits)
