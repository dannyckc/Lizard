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

var creature: Creature = null
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

var _hover_key: String = ""
var _hover_cell: int = -1

# Reused geometry, on the same terms as CreatureView's: this redraws every frame,
# so the cell layer writes into these rather than allocating per cell.
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _flat := PackedColorArray([Color.TRANSPARENT])
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
	if not visible:
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

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for cell in p.cells:
			if p.gone[cell] != 0:
				continue
			p.corners_of(cell, _quad)
			for k in 4:
				var at: Vector2 = (_quad[k] - _anchor).rotated(_rot)
				lo = lo.min(at)
				hi = hi.max(at)
	if lo.x > hi.x:
		return

	var span: Vector2 = (hi - lo).max(Vector2(1.0, 1.0))
	var room: Vector2 = (size - Vector2(PAD_X * 2.0, PAD_Y * 2.0)).max(Vector2(1.0, 1.0))
	var target_scale: float = minf(room.x / span.x, room.y / span.y)
	var target_centre: Vector2 = (lo + hi) * 0.5
	if _fitted:
		var ease: float = 1.0 - exp(-SETTLE * delta)
		_scale = lerpf(_scale, target_scale, ease)
		_centre = _centre.lerp(target_centre, ease)
	else:
		_scale = target_scale
		_centre = target_centre
		_fitted = true
	_origin = size * 0.5 - _centre * _scale
	_lo = _origin + lo * _scale
	_hi = _origin + hi * _scale


## Where a place on the animal lands on the page, and back. The whole of the
## relationship between the specimen and the creature is these two lines: one
## rotation, one scale, one offset, applied to world coordinates the lattice
## already holds. There is no second geometry anywhere in this file.
func to_panel(world: Vector2) -> Vector2:
	return _origin + (world - _anchor).rotated(_rot) * _scale


func to_world(panel: Vector2) -> Vector2:
	return _anchor + ((panel - _origin) / maxf(_scale, 0.0001)).rotated(-_rot)


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
	if _points.size() != standing * 4:
		_points.resize(standing * 4)
		_colors.resize(standing * 4)
		_indices.resize(standing * 6)

	var v: int = 0
	var t: int = 0
	for key in _patch_order():
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		for cell in p.cells:
			if p.gone[cell] != 0:
				continue
			p.corners_of(cell, _quad)
			var base: int = cell * TissueGrid.LAYERS
			var color: Color = COL_WASH
			if CreatureView.top_layer(p.hp, base, layers) >= 0:
				color = CreatureView.tissue_color(
					p.hp, base, grid.fat_capacity(p, cell), layers)
			for k in 4:
				_points[v + k] = to_panel(_quad[k])
				_colors[v + k] = color
			_indices[t] = v
			_indices[t + 1] = v + 1
			_indices[t + 2] = v + 2
			_indices[t + 3] = v
			_indices[t + 4] = v + 2
			_indices[t + 5] = v + 3
			v += 4
			t += 6

	# The specimen's own shadow, offset off the same mesh — so a hole in the
	# creature is a hole in its shadow, as it is in the field.
	_flat[0] = COL_SHADOW
	draw_set_transform(Vector2(0.0, 5.0), 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _flat)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)


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
			p.corners_of(cell, _quad)
			var strands: int = clampi(int(_cell_depth() / GRAIN_MIN_CELL), 0, 3)
			if strands <= 0:
				continue
			if top == TissueGrid.SKIN:
				if cell % p.rows % 2 == 1:
					_skin_lines.append(to_panel(_quad[0].lerp(_quad[1], 0.5)))
					_skin_lines.append(to_panel(_quad[3].lerp(_quad[2], 0.5)))
				continue
			# Fibres thin out with the cell rather than switching off at a size, so a
			# tapering tail loses its grain the way it loses its width instead of in
			# bands wherever a column happened to cross the threshold.
			for strand in range(1, strands + 1):
				var across: float = float(strand) / float(strands + 1)
				_muscle_lines.append(to_panel(_quad[0].lerp(_quad[1], across)))
				_muscle_lines.append(to_panel(_quad[3].lerp(_quad[2], across)))
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
			if p.gone[cell] == 0:
				continue
			p.corners_of(cell, _quad)
			var col: int = cell / p.rows
			var row: int = cell % p.rows
			for k in 4:
				if not _rim(p, col + EDGE_COL[k], row + EDGE_ROW[k]):
					continue
				draw_dashed_line(to_panel(_quad[k]), to_panel(_quad[(k + 1) % 4]),
					COL_HOLE, 0.9, 2.2, true)


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
			if p.gone[cell] != 0:
				continue
			p.corners_of(cell, _quad)
			if _cell_depth() < LATTICE_MIN_CELL:
				continue
			for k in 4:
				_lattice.append(to_panel(_quad[k]))
				_lattice.append(to_panel(_quad[(k + 1) % 4]))
	if not _lattice.is_empty():
		draw_multiline(_lattice, COL_LATTICE, 0.5, true)


## How deep the cell in `_quad` is across the body, on the page. The measure the
## two passes above decide by, because it is the direction their marks run
## across and therefore the one that runs out of room first.
func _cell_depth() -> float:
	return _quad[0].distance_to(_quad[1]) * _scale


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
	for i in count:
		_run[i] = to_panel(p.centre_of(run.cells[i]))
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
	var found: int = 0
	for cell in p.cells:
		if int(p.organ[cell]) != which or p.gone[cell] != 0:
			continue
		centre += p.centre_of(cell)
		found += 1
	if found == 0:
		return
	var at: Vector2 = to_panel(centre / float(found))
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
	var text: String = "%s %d%%" % [label, int(round(health * 100.0))]
	var width: float = _mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
	var edge: float = minf(maxf(_hi.x + 6.0, at.x + radius + 12.0), size.x - width - 12.0)
	draw_line(Vector2(at.x + radius + 2.0, at.y), Vector2(edge, at.y),
		Color(tint, 0.34), 0.7, true)
	draw_string(_mono, Vector2(edge + 4.0, at.y + 3.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(tint, 0.78))


# ------------------------------------------------------------- hit-test ----

func _draw_hover(grid: TissueGrid) -> void:
	if _hover_cell < 0:
		return
	var p: TissueGrid.Patch = grid.patch(_hover_key)
	if p == null or not p.live or _hover_cell >= p.cells:
		return
	p.corners_of(_hover_cell, _quad)
	for k in 4:
		draw_line(to_panel(_quad[k]), to_panel(_quad[(k + 1) % 4]), INK, 1.3, true)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	_pick(motion.position)


func _on_mouse_exited() -> void:
	if _hover_cell >= 0:
		_hover_key = ""
		_hover_cell = -1
		cell_hovered.emit("", false)


## Which cell is under the cursor. Tested against the solved quads in world space
## rather than by inverting the body-space mapping, for the reason the bite query
## gives: that mapping is curved, tapered and rebuilt every tick, and has no
## cheap inverse — while the direct test is exact and costs a few hundred
## comparisons on the frames the pointer actually moves.
func _pick(at: Vector2) -> void:
	var grid: TissueGrid = tissue()
	if grid == null or not _fitted:
		return
	var world: Vector2 = to_world(at)
	var order: Array[String] = _patch_order()
	order.reverse()
	for key in order:
		var p: TissueGrid.Patch = grid.patch(key)
		if p == null or not p.live:
			continue
		if world.x < p.lo.x or world.x > p.hi.x or world.y < p.lo.y or world.y > p.hi.y:
			continue
		for cell in p.cells:
			p.corners_of(cell, _quad)
			if not _inside(world, _quad):
				continue
			if _hover_key != key or _hover_cell != cell:
				_hover_key = key
				_hover_cell = cell
				cell_hovered.emit(_readout(grid, p, cell), p.gone[cell] != 0)
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
