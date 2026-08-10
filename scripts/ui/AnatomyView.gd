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
const SPLAT_GROW: float = 1.22

var creature: Creature = null
## Which of the five tissue layers are still on the specimen.
var layers: int = ALL_LAYERS
var show_vessels: bool = true
var show_nerves: bool = true
## Cell outlines: the lattice is what the whole system is built on, so it can be
## drawn rather than implied.
var show_lattice: bool = true
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
	var key: int = hash([layers, show_nerves, show_vessels, xray, slice_axis,
		snappedf(slice_at, 0.002), grid.revision, lat.count])
	if key == _draw_key:
		return
	_draw_key = key

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
	# and on the kept side of the section plane.
	var present := PackedByteArray()
	present.resize(lat.count)
	var shown := PackedByteArray()
	shown.resize(AnatomyLattice.TISSUES)
	for t in AnatomyLattice.TISSUES:
		shown[t] = 1 if tissue_shown(t) else 0
	for i in lat.count:
		if shown[lat.kind[i]] == 0 or lat.gone[i] != 0:
			continue
		if sliced and lat.pos[i][slice_axis] > plane:
			continue
		present[i] = 1

	_draw_list.resize(0)
	for i in lat.count:
		if present[i] == 0:
			continue
		if xray:
			_draw_list.append(i)
			continue
		# The surface of the visible solid: a cell with any exposed face. What a
		# filter peels away exposes the faces beneath it, which is the whole of
		# how looking inside works.
		for k in 6:
			var n: int = lat.neighbor[i * 6 + k]
			if n < 0 or present[n] == 0:
				_draw_list.append(i)
				break


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


## One cell's posed place in the world, and its height. The pose bends the
## lattice; it cannot create or destroy cells.
func _voxel_world(lat: AnatomyLattice, i: int) -> Vector3:
	var pk: int = lat.patch_of[i]
	if _st_pos[pk] == null:
		return Vector3.ZERO
	var pos: PackedVector2Array = _st_pos[pk]
	var s: float = clampf(lat.station[i], 0.0, float(pos.size() - 1))
	var c: int = mini(int(s), pos.size() - 2)
	var f: float = s - float(c)
	var at: Vector2 = pos[c].lerp(pos[c + 1], f) \
		+ (_st_perp[pk] as PackedVector2Array)[c] * lat.lat[i] \
		+ (_st_dir[pk] as PackedVector2Array)[c] * lat.fore[i]
	var mids: PackedFloat32Array = _st_mid[pk]
	return Vector3(at.x, at.y, lerpf(mids[c], mids[c + 1], f) + lat.lift[i])


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


## Every cell on the specimen, painter-sorted, one quad apiece.
##
## A cell is drawn as a page-aligned square the size of the cell itself — the
## honest mark for a lattice whose whole claim is "this volume is made of these
## boxes" — shaded by which way its own face points and worn toward the tissue's
## spent shade by whatever the damage ledger says its column has lost.
func _draw_cells(lat: AnatomyLattice, grid: TissueGrid) -> void:
	var n: int = _draw_list.size()
	if n == 0:
		return
	if _points.size() != n * 4:
		_points.resize(n * 4)
		_colors.resize(n * 4)
		_indices.resize(n * 6)
		_depths.resize(n)
		_cell_page.resize(n)
		_cell_deep.resize(n)

	var half: float = AnatomyLattice.CELL * 0.5 * _scale * SPLAT_GROW
	var alpha: float = XRAY_ALPHA if xray else 1.0
	for j in n:
		var i: int = _draw_list[j]
		var w: Vector3 = _voxel_world(lat, i)
		var turned: Vector2 = (Vector2(w.x, w.y) - _anchor).rotated(_rot)
		var page: Vector2 = _origin + _flatten(turned, w.z) * _scale
		_cell_page[j] = page
		var deep: float = _towards(turned, w.z)
		_cell_deep[j] = deep
		_depths[j] = Vector2(deep, float(j))

		var ink: Color = _cell_ink(lat, grid, i)
		# The cell's own face against the eye, read in the upright presentation:
		# page x is the body's lateral, page y its length reversed, height its
		# own z — the same axes the canonical normals are stored in.
		var nrm: Vector3 = lat.normal[i]
		var lit: float = nrm.y * _eye.x - nrm.x * _eye.y + nrm.z * _eye.z
		ink = _relieved(ink, lit)
		ink.a = alpha
		var v: int = j * 4
		_points[v] = page + Vector2(-half, -half)
		_points[v + 1] = page + Vector2(half, -half)
		_points[v + 2] = page + Vector2(half, half)
		_points[v + 3] = page + Vector2(-half, half)
		_colors[v] = ink
		_colors[v + 1] = ink
		_colors[v + 2] = ink
		_colors[v + 3] = ink

	# Far side of the animal first, or a rolled specimen shows its back through
	# its own belly.
	_depths.sort()
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
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)

	if show_lattice and not xray and n <= LATTICE_MOST \
			and half * 2.0 >= LATTICE_MIN_CELL:
		_lattice_lines.resize(0)
		for j in n:
			var page: Vector2 = _cell_page[j]
			var a: Vector2 = page + Vector2(-half, -half)
			var b: Vector2 = page + Vector2(half, -half)
			var c: Vector2 = page + Vector2(half, half)
			var d: Vector2 = page + Vector2(-half, half)
			_lattice_lines.append_array([a, b, b, c, c, d, d, a])
		draw_multiline(_lattice_lines, COL_LATTICE, 0.5, true)


## One cell's ink: its tissue's own colour, worn toward the spent shade by how
## much of that tissue its ledger column has lost.
func _cell_ink(lat: AnatomyLattice, grid: TissueGrid, i: int) -> Color:
	var t: int = lat.kind[i]
	var ink: Color = TISSUE_INK[t]
	if t > AnatomyLattice.ORGAN:
		return ink
	var p: TissueGrid.Patch = grid.patch(AnatomyLattice.PATCH_KEYS[lat.patch_of[i]])
	if p == null or not p.live:
		return ink
	var cell: int = lat.cell_of[i]
	if p.touched[cell] == 0:
		return ink
	var base: int = cell * TissueGrid.LAYERS
	var full: float = _layer_full(grid, p, cell, t)
	if full <= 0.0:
		return ink
	return ink.lerp(TISSUE_WORN[t],
		clampf(1.0 - p.hp[base + t] / full, 0.0, 1.0) * 0.85)


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
	var centre := Vector3.ZERO
	var found: int = 0
	for i in lat.count:
		if int(lat.organ_of[i]) != which or lat.gone[i] != 0:
			continue
		centre += _voxel_world(lat, i)
		found += 1
	if found == 0:
		return
	centre /= float(found)
	var at: Vector2 = project(Vector2(centre.x, centre.y), centre.z)
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
	var w: Vector3 = _voxel_world(lat, _hover_voxel)
	var page: Vector2 = project(Vector2(w.x, w.y), w.z)
	var half: float = AnatomyLattice.CELL * 0.5 * _scale * SPLAT_GROW
	draw_rect(Rect2(page - Vector2(half, half), Vector2(half, half) * 2.0),
		INK, false, 1.3)


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
	var half: float = maxf(AnatomyLattice.CELL * 0.5 * _scale * SPLAT_GROW, 2.0)
	var found: int = -1
	var nearest: float = -INF
	for j in _draw_list.size():
		var i: int = _draw_list[j]
		var w: Vector3 = _voxel_world(lat, i)
		var turned: Vector2 = (Vector2(w.x, w.y) - _anchor).rotated(_rot)
		var page: Vector2 = _origin + _flatten(turned, w.z) * _scale
		if absf(page.x - at.x) > half or absf(page.y - at.y) > half:
			continue
		var deep: float = _towards(turned, w.z)
		if deep <= nearest:
			continue
		nearest = deep
		found = i
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
