## The Anatomy tab's specimen: one creature's own 3D cell lattice, drawn from
## the pose it is standing in right now.
##
## It is not an illustration of a lizard. Every facet on it stands on a cell of
## the creature's `AnatomyLattice` — a real box of one tissue with a place in the
## animal's own three axes — posed through the same per-station frames the
## damage ledger poses its columns with, and put through one rigid transform. So
## the silhouette is that creature's silhouette, the bend is the bend its spine
## is currently holding, a chewed flank is a crater of missing cells here too,
## and a limb that has come off is missing from both. The counts on the panel
## beside it are these same cells, because the physique weighed these same
## cells: there is no second anatomy anywhere.
##
## The flesh is drawn as a low-poly mesh skinned off those cells — see
## SpecimenMesh. Every facet is a real quad of the animal's own surface carrying
## the cell it was skinned off, so the silhouette is the real silhouette, peeling
## a tissue drops the surface onto the layer beneath it, and a bite is a crater
## in the geometry rather than a stain painted on top of it. The facets are lit
## flat against one fixed light, which is the whole of why a body reads as a
## solid: a plane's shade is a fact about which way that plane is turned, and
## twenty of them around a ribcage state the curve more plainly than any amount
## of per-cell shading did. Bone, the cord and the great vessels are continuous
## volumes drawn from their TissueForm chains — centreline plus thickness, never
## cell by cell — and the two supply networks carry their space-colonised branch
## trees, with everything finer living in the per-region density fields. One
## census underneath all of it, three representations on top.
##
## What is happening to the animal is said on the mesh itself rather than beside
## it. Flesh the ledger has worn down carries its tissue's spent shade; a facet
## standing against something the teeth took carries the raw colour of an open
## wound; a region losing cells right now flares and settles again, so a bite is
## legible as it lands; a region the blood has stopped reaching goes pale; and a
## dead animal's whole mesh drains toward ash. None of it is invented — every one
## is a reading off the ledger, the lattice or the functional layer.
##
## Four ways to look inside, and all four are subtractions rather than styles:
## a tissue toggled off has its cells lifted away and the surface settles onto
## whatever they were covering; X-ray skins the body once per layer of the depth
## stack and thins the lot, so the interior reads in place and at its own shape;
## a section plane carves the body at a station of its own frame and lays the
## cut cells flat on it; and the panel can isolate one tissue outright. What
## shows underneath is always the cells that were genuinely laid underneath —
## bone inside muscle inside fat inside skin, organs behind bone, the two supply
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
const COL_LATTICE := Color(INK, 0.22)
## The specimen's hide.
##
## In the field a creature's skin is drawn in the page's own ink, because there
## it is a silhouette on paper and a silhouette wants to be solid. On the slab it
## is a lit surface, and a surface inked at the darkest value the palette has
## cannot be lit: every facet of it comes back black and the animal reads as a
## hole rather than as a body. So the specimen's skin is the same ink brought up
## to a hide tone — the one value in this file that is about the light rather
## than about the animal.
const COL_HIDE := Color("8c7b69")
## What an opened wound is: the raw colour of flesh the teeth have just been
## through, which no intact tissue anywhere on the palette comes near.
const COL_RAW := Color("8e1b14")
## The bloodless tone a region drifts toward when nothing is reaching it.
const COL_PALE := Color("b9b2a4")

## Layer toggles, as a mask over the lattice's first five tissues. The nerve and
## vessel cells ride `show_nerves` / `show_vessels` beside it, exactly as the
## network overlays do.
const ALL_LAYERS: int = CreatureView.ALL_LAYERS

## One ink per tissue, and the worn shade damage drags it toward — the same
## palette the field inks the creature and its meat with.
static var TISSUE_INK: PackedColorArray = PackedColorArray([
	COL_HIDE,
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
## How far every shell of an X-ray is thinned to, so the body reads through.
const XRAY_ALPHA: float = 0.26

# --- the facets ---------------------------------------------------------------
## Where the light stands, in page axes: x right, y down, z toward the eye. Up and
## a little to the left, in front of the specimen — one fixed lamp on a slab,
## never the world's own sun, because the specimen is an object being examined
## rather than a creature standing outdoors.
const LIGHT := Vector3(-0.40, -0.68, 0.62)
## What the lamp does to a facet's own colour: darkest in full shade, brightest
## turned into the light. A *scale* on the tissue's ink rather than a slide toward
## the paper, because sliding toward the paper takes the colour out of the
## highlight and leaves every tissue trending to the same off-white — which is
## how a faceted body ends up reading as flat as the wash it replaced.
const FACET_FLOOR: float = 0.64
const FACET_GAIN: float = 0.66
## How far a facet turned away from the eye is dropped again. The mesh is left
## double-sided on purpose: where the teeth have taken a bite out of the animal
## the crater's far wall is genuinely on view, and culling it would show the
## paper straight through the body.
const FACET_BACK: float = 0.62
## Shades each tissue's ink is banked in, across the whole range of how a facet
## can be turned, front and back. Colour arithmetic is the most expensive thing
## that happens per facet and the cheapest thing to have already done.
const SHADES: int = 24
## The hairline along every facet's own edges. What tells one plane from the next
## where two of them happen to catch the light alike.
const FACET_EDGE := Color(INK, 0.15)
## The light a section's cut face is given. A cut is a plane put through the
## animal rather than a piece of its surface, so it is lit evenly rather than by
## its own turn — which is also what makes it read as the one flat thing on a
## faceted body. A little above the middle, so the cut is legibly the near face
## without washing the tissue out of it.
const CUT_LAM: float = 0.66
## Least radius a chain's tube may draw at, in page pixels: a nerve on a distant
## specimen is a thread and still has to be a visible one.
const TUBE_MIN: float = 0.6

# --- what is happening to it --------------------------------------------------
## How far a facet standing against flesh the teeth took is carried toward the
## raw colour of an open wound. Only ever the rim of a crater: the wound is where
## the tissue ends, and that is the one place it can be seen.
const WOUND_RIM: float = 0.55
## How long a region goes on flaring after it has lost cells, in seconds, and how
## far the flare carries its facets. This is the only thing on the specimen that
## is about *when* rather than about what: a bite lands, the flank flares, and it
## settles back to the crater it has left.
const FLARE_FOR: float = 1.1
const FLARE_LIFT: float = 0.72
## Beats a second the flare pulses at while it lasts.
const FLARE_BEAT: float = 3.0
## Delivery below which a region starts going pale, and how far it gets when
## nothing at all is arriving. Flesh with no blood in it is the reading that says
## a limb is being lost before any of it has actually gone.
const PALE_FROM: float = 0.70
const PALE_TO: float = 0.52
## How far a dead animal's whole mesh drains toward its own spent shades.
const DEAD_DRAIN: float = 0.55
## Page cells of the pick grid. The hover test walks one bucket instead of every
## facet on the specimen — see `_pick`.
const PICK_BUCKET: float = 14.0
## Page size of a cell below which the facet hairlines and the cell overlay stop
## being drawn — past that they are ink rather than information — and the size
## they come back at, apart so a fit easing onto the line does not flicker.
const FINE_CELL: float = 1.1
const FINE_BACK: float = 1.35
## The shade band a chain's tube is inked at — a mineralised matrix or a vessel
## wall is one material, not a heap of differently-lit boxes — and how far the
## band steps between segments, which is what makes vertebrae read as vertebrae.
const TUBE_BAND: int = 20
const TUBE_SEG: int = 2
## How quickly a supply run loses calibre per branching generation: the aorta is
## a tube, the run into a foot is a thread.
const CALIBRE_FALL: float = 0.45
## Width of the space-colonisation branchlets, which stand in for everything
## finer than the named runs. Everything finer than *them* is the density field.
const BRANCH_WIDTH: float = 0.7

var creature: Creature = null
## Which of the five tissue layers are still on the specimen.
var layers: int = ALL_LAYERS
var show_vessels: bool = true
var show_nerves: bool = true
## The census under the skin: a mark on every cell the mesh was actually skinned
## off. Off by default — the specimen is a body, and the cells are what it is
## made of rather than what it looks like — but the lattice is what the whole
## system is built on, and being able to see that the surface stands on real
## cells is worth having on demand.
var show_lattice: bool = false
## Every shell of the body at once, each thinned to a film, so the interior reads
## in place — see `_shell_masks`.
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

var _hover_voxel: int = -1
var _orbiting: bool = false
var _grab: Vector3 = Vector3(0.0, 0.0, 1.0)
var _grabbed: Basis = Basis()

# --- the surface census ------------------------------------------------------
## Which lattice cells stand on the boundary of what is being shown — the cells
## the mesh is skinned off. Rebuilt only when a filter, the section plane, the
## damage state or the lattice itself changes.
var _draw_list: PackedInt32Array = PackedInt32Array()
## The same, once per nested shell, for the X-ray. Outside this the list above is
## the only entry.
var _surfaces: Array = []
## Cells standing in the section plane, which are laid as the cut face itself.
var _plane_cells: PackedInt32Array = PackedInt32Array()
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
var _edge_lines := PackedVector2Array()
var _lattice_lines := PackedVector2Array()
var _run := PackedVector2Array()
var _run_gone := PackedByteArray()
var _order: Array[String] = []

# --- the mesh ------------------------------------------------------------------
## The specimen's own surface, skinned off the cells above. Rebuilt with the
## surface census and merely posed on the frames in between.
var _mesh := SpecimenMesh.new()
## Where every vertex of it landed on the page this frame, and how near the eye —
## the one place the station affines are read, once per vertex rather than once
## per corner of every facet.
var _v_page := PackedVector2Array()
var _v_deep := PackedFloat32Array()
## The tissues' derived form — bone centrelines, conduit splines, supply trees,
## density fields. Rebuilt only when the lattice is; see TissueForm.
var _form := TissueForm.new()
## Which chain samples are exposed under the current filters, rebuilt with the
## draw list. Bone, nerve and vessel cells are never marked one by one — their
## chains are drawn as continuous tubes wherever any of their cells would show.
var _sample_vis := PackedByteArray()
## Reused buffer for the supply branchlets.
var _branch_lines := PackedVector2Array()
## The facets laid down this frame: the cell each was skinned off, where its
## middle landed, and how near the eye it is. What the hover test reads.
var _shown := PackedInt32Array()
var _shown_count: int = 0
## Which facet of the mesh each of those was, so the hover can outline the actual
## polygon under the pointer, and whether it was turned toward the eye.
var _shown_face := PackedInt32Array()
var _shown_front := PackedByteArray()
## Page-space buckets over the facets drawn last frame, so the hover test looks
## at the handful under the pointer instead of all of them, and how far the
## widest of them reaches from its own middle — which is how far the search has
## to look, and is a fact about the mesh on this page rather than about the cells
## behind it.
var _pick_grid: Dictionary = {}
var _pick_origin: Vector2 = Vector2.ZERO
var _pick_reach: float = 0.0
## Every tissue at every turn of a facet — see SHADES — and what it was baked for.
var _shade := PackedColorArray()
var _shade_key: int = 0
## Whether the specimen is large enough on the page for its hairlines to be
## information rather than ink.
var _fine: bool = true
## Whether those buckets describe where the facets are *now*. Cleared as each
## frame begins and set by whichever of the drawing pass or the hover test placed
## them, so a pointer moving over a painted specimen reads the facets it can see
## rather than placing them all over again.
var _marks_fresh: bool = false

# --- what is happening to it ---------------------------------------------------
## How lately each region lost cells, 0..1, decayed every frame. Set by comparing
## the lattice's own standing census against what it read last time, so the flare
## is a fact about the animal changing rather than an event this view was told
## about — nothing has to remember to call it.
var _flare := PackedFloat32Array()
var _standing_was := PackedInt32Array()
var _census_of: int = -1
## The same readings resolved to one colour and one amount per region, so the
## facet pass asks a nine-entry table rather than the functional layer.
var _wash_col := PackedColorArray()
var _wash_amt := PackedFloat32Array()
## The hovered cell's own facet, for the outline.
var _hover_face: int = -1


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
		# ...and a drawer that is shut drops its census baseline, so an animal
		# chewed while nobody was looking at it does not flare the moment the
		# drawer opens. The flare is for damage happening in view.
		_census_of = -1
		return
	_clock += delta
	_marks_fresh = false
	_settle(delta)
	var lat: AnatomyLattice = lattice()
	if lat != null:
		lat.refresh_damage(tissue())
		_refresh_flares(lat, delta)
	queue_redraw()


## Forgets the settled presentation, so a different specimen arrives already
## upright and framed rather than easing across from where the last one sat.
func reset_fit() -> void:
	_fitted = false
	_hover_voxel = -1
	_hover_face = -1
	_draw_key = 0
	_census_of = -1


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


## The nested shells an X-ray lays down: the surface of the whole animal, then
## the surface with the skin lifted, then with the fat lifted too, and so on down
## the depth stack. Each is the same question the ordinary view asks once, and
## drawn together and thinned they are a body seen through — the interior in its
## own place, at its own shape, rather than a fog of translucent cells.
##
## Only tissues the panel is actually showing are peeled: an X-ray of a specimen
## with the muscle already off does not put it back to make a shell of it.
func _shell_masks() -> Array[int]:
	var base: int = AnatomyLattice.OPEN_BIT
	for t in AnatomyLattice.TISSUES:
		if not tissue_shown(t):
			base |= 1 << t
	var masks: Array[int] = [base]
	if not xray:
		return masks
	var mask: int = base
	for t in [AnatomyLattice.SKIN, AnatomyLattice.FAT, AnatomyLattice.MUSCLE]:
		if (mask & (1 << t)) != 0:
			continue
		mask |= 1 << t
		masks.append(mask)
	return masks


## Re-derives which cells the specimen's surface stands on, and skins the mesh
## over them. Runs only when something that decides membership changes; a frame
## where nothing did poses the mesh it already has.
func _refresh_draw_list(lat: AnatomyLattice, grid: TissueGrid) -> void:
	_form.ensure(lat)
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

	_plane_cells.resize(0)
	if _sample_vis.size() != _form.sample_total:
		_sample_vis.resize(_form.sample_total)
	_sample_vis.fill(0)
	# A shell apiece, outermost first. Built as locals and handed over whole,
	# because a packed array read back out of a container is a copy of it and
	# appending to that copy writes into nothing.
	var masks: Array[int] = _shell_masks()
	var built: Array = []
	for s in masks.size():
		built.append(_shell_surface(lat, masks[s], s == 0))
	_surfaces = built
	_draw_list = built[0]
	_mesh.build(lat, _surfaces, _plane_cells, slice_axis)


## The cells standing on the boundary of one shell: shown, standing, on the kept
## side of any section plane, and touching something that shell is not drawing.
## What a filter peels away exposes the faces beneath it, and that is the whole
## of how looking inside works.
##
## The outermost shell is also where the chains and the section's own cut face
## are decided, because those are questions about the specimen rather than about
## a shell of it.
func _shell_surface(lat: AnatomyLattice, hidden: int,
		outermost: bool) -> PackedInt32Array:
	var plane: float = slice_plane()
	var sliced: bool = slice_axis >= 0
	var surface := PackedInt32Array()
	var present := PackedByteArray()
	present.resize(lat.count)
	# Cells a filter took away for a reason the mask cannot see — eaten, or on the
	# far side of a section plane. Their neighbours are the only cells the mask can
	# be wrong about, and re-testing exactly those is what keeps the fast path
	# exact instead of approximate.
	var lifted := PackedInt32Array()
	var listed := PackedByteArray()
	listed.resize(lat.count)
	# One walk of the animal, not two. Whether a cell is on the surface of what is
	# being shown depends on the mask alone, so it can be answered in the same pass
	# that decides whether the cell is there at all. Hoisted into locals for the
	# same reason: a property read per cell per array is a hundred thousand
	# property reads.
	var kinds: PackedByteArray = lat.kind
	var gone: PackedByteArray = lat.gone
	var neighbours: PackedByteArray = lat.around
	var where: PackedVector3Array = lat.pos
	var chain_of: PackedInt32Array = _form.sample_of
	var chained: bool = chain_of.size() == lat.count
	# A cell is in the plane when the plane passes through the cell itself: the
	# kept side, within one cell of the cut. That band is the cut face.
	var near_plane: float = plane - AnatomyLattice.CELL
	for i in lat.count:
		if (hidden & (1 << int(kinds[i]))) != 0:
			continue
		if gone[i] != 0 or (sliced and where[i][slice_axis] > plane):
			lifted.append(i)
			continue
		present[i] = 1
		if outermost and sliced and where[i][slice_axis] > near_plane:
			_plane_cells.append(i)
		if outermost and xray and chained and chain_of[i] >= 0:
			_sample_vis[chain_of[i]] = 1
		if (int(neighbours[i]) & hidden) == 0:
			continue
		listed[i] = 1
		surface.append(i)
		# A cell of a continuous structure — a bone, a cord, a vessel — is skinned
		# over like any other, and its chain's tube is drawn inside the surface
		# that closed over it. Which is why the tube shows exactly where the way in
		# is open and nowhere else; see SpecimenMesh.
		if chained and chain_of[i] >= 0 and outermost:
			_sample_vis[chain_of[i]] = 1

	for i in lifted:
		var base: int = i * 6
		for k in 6:
			var n: int = lat.neighbor[base + k]
			if n < 0 or present[n] == 0 or listed[n] != 0:
				continue
			listed[n] = 1
			surface.append(n)
			if chained and chain_of[n] >= 0 and outermost:
				_sample_vis[chain_of[n]] = 1
	return surface


## What each region has lost since the specimen last looked, as a flare that
## fades. Read off the lattice's own standing census rather than off an event, so
## nothing anywhere has to remember to tell the view a bite has landed — and so a
## creature that walks into the drawer already wounded does not flash at being
## looked at.
func _refresh_flares(lat: AnatomyLattice, delta: float) -> void:
	if _flare.size() != BodyPlan.REGIONS:
		_flare.resize(BodyPlan.REGIONS)
		_standing_was.resize(BodyPlan.REGIONS)
		_census_of = -1
	var fade: float = delta / FLARE_FOR
	var fresh: bool = _census_of == lat.built_total
	for reg in BodyPlan.REGIONS:
		var now: int = lat.region_cells(reg)
		if fresh and now < _standing_was[reg]:
			_flare[reg] = 1.0
		else:
			_flare[reg] = maxf(_flare[reg] - fade, 0.0)
		_standing_was[reg] = now
	_census_of = lat.built_total


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
	# The supply overlays are things inside the animal, and they draw only when
	# the inside is genuinely open to view — peeled, cut or thinned — never as
	# lines through an intact wrap. The trunk runs lie against the spine under
	# the muscle, so they wait for the deep interior; the limb runs sit just
	# under the surface and show as soon as the skin is off.
	var opened: bool = xray or slice_axis >= 0 \
		or not (layer_shown(AnatomyLattice.SKIN) and layer_shown(AnatomyLattice.FAT))
	var deep_open: bool = opened and (xray or slice_axis >= 0 \
		or not (layer_shown(AnatomyLattice.MUSCLE) and layer_shown(AnatomyLattice.BONE)))
	if show_vessels and opened:
		_draw_network(grid, state.plan.vessels, state.vessels, COL_VESSEL, 3, 46.0, true,
			VESSEL_OFFSET, deep_open)
		_draw_branches(lat, state.vessels, TissueForm.VESSELS, COL_VESSEL)
	if show_nerves and opened:
		_draw_network(grid, state.plan.nerves, state.nerves, COL_NERVE, 2, 150.0, false, 0.0,
			deep_open)
		_draw_branches(lat, state.nerves, TissueForm.NERVES, COL_NERVE)
	if show_vessels and opened:
		_draw_organ(grid, lat, BodyPlan.HEART, COL_VESSEL, "HEART", true)
	if show_nerves and opened:
		_draw_organ(grid, lat, BodyPlan.BRAIN, COL_NERVE, "BRAIN", false)
	_draw_hover(lat)


func _draw_empty() -> void:
	if _mono == null:
		return
	var text: String = "NO SPECIMEN"
	var width: float = _mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
	draw_string(_mono, Vector2((size.x - width) * 0.5, size.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(INK, 0.30))


## Every vertex of the mesh, put on the page. The station affines are read here
## and nowhere else in the pass: a facet's four corners are four already-posed
## points, and the corners a facet shares with its neighbours are posed once
## between them rather than once each.
func _pose_mesh() -> void:
	var n: int = _mesh.v_count
	if _v_page.size() != n:
		_v_page.resize(n)
		_v_deep.resize(n)
	for v in n:
		var pk: int = _mesh.v_patch[v]
		if pk >= _af_o.size() or _af_o[pk] == null:
			_v_deep[v] = -INF
			continue
		var o: PackedVector2Array = _af_o[pk]
		var s: float = clampf(_mesh.v_station[v], 0.0, float(o.size() - 1))
		var c: int = mini(int(s), o.size() - 1)
		var f: float = s - float(c)
		var side: float = _mesh.v_lat[v]
		var ahead: float = _mesh.v_fore[v]
		var up: float = _mesh.v_lift[v]
		_v_page[v] = o[c] + (_af_s[pk] as PackedVector2Array)[c] * f \
			+ (_af_l[pk] as PackedVector2Array)[c] * side \
			+ (_af_f[pk] as PackedVector2Array)[c] * ahead + _af_h * up
		_v_deep[v] = (_dp_o[pk] as PackedFloat32Array)[c] \
			+ (_dp_s[pk] as PackedFloat32Array)[c] * f \
			+ (_dp_l[pk] as PackedFloat32Array)[c] * side \
			+ (_dp_f[pk] as PackedFloat32Array)[c] * ahead + _dp_h * up


## Whether the specimen is big enough on the page for its hairlines to be worth
## drawing. Hysteresis, so a fit easing onto the line does not flicker.
func _fine_enough() -> bool:
	var page: float = AnatomyLattice.CELL * _scale
	return page >= (FINE_CELL if _fine else FINE_BACK)


## The specimen, as its own low-poly surface: every facet posed, lit flat against
## one fixed light, tinted by what is happening to the flesh under it, and
## painter-sorted with the chains that run inside it.
##
## Three things follow from drawing a mesh rather than a mark per cell, and they
## are the whole of the change:
##
##   * **It is a solid.** A facet is a plane, its shade is a fact about which way
##     that plane is turned, and two neighbouring planes catching the light
##     differently is what a curved body looks like. There is no per-cell
##     shading to average out into a wash.
##   * **It is bounded.** A lizard and an elephant carve the same few hundred
##     facets. The old surface was one quad per exposed cell face and an elephant
##     paid for every one of its fifty thousand cells.
##   * **It is still the census.** Every facet carries the cell it was skinned
##     off. Hover reads that cell, its tissue inks the facet, its wear tints it,
##     and a bite is a dent in the geometry because the cell that used to hold
##     the surface out there is gone.
func _draw_cells(lat: AnatomyLattice, grid: TissueGrid) -> void:
	var faces: int = _mesh.count
	var room: int = faces + _form.sample_total
	if room == 0:
		_shown_count = 0
		return
	if _cell_page.size() != room:
		_cell_page.resize(room)
		_cell_deep.resize(room)
		_shown.resize(room)
		_shown_face.resize(room)
		_shown_front.resize(room)
	_points.resize(room * 4)
	_colors.resize(room * 4)
	_depths.resize(room)
	_fine = _fine_enough()
	_pick_reach = 0.0
	_pose_mesh()
	_bake_shades()
	_bake_wash()

	# The ledger patch each facet's wear is read off, taken once rather than
	# looked up by name for every facet — and only where there is wear to read.
	# On a sound body every facet takes its ink straight out of the bank.
	var worn: Array = []
	for pk in AnatomyLattice.PATCH_KEYS.size():
		var p: TissueGrid.Patch = grid.patch(AnatomyLattice.PATCH_KEYS[pk])
		worn.append(p if p != null and p.live and not p.damaged.is_empty() else null)

	var kinds: PackedByteArray = lat.kind
	var regions: PackedByteArray = lat.region
	var normals: PackedVector3Array = lat.normal
	var patch_of: PackedByteArray = lat.patch_of
	var station: PackedFloat32Array = lat.station
	var thin: bool = xray
	var n: int = 0
	for q in faces:
		var corner: int = q * 4
		var a: int = _mesh.f_v[corner]
		var deep_a: float = _v_deep[a]
		if deep_a == -INF:
			continue
		var b: int = _mesh.f_v[corner + 1]
		var c: int = _mesh.f_v[corner + 2]
		var d: int = _mesh.f_v[corner + 3]
		var pa: Vector2 = _v_page[a]
		var pb: Vector2 = _v_page[b]
		var pc: Vector2 = _v_page[c]
		var pd: Vector2 = _v_page[d]
		var deep: float = (deep_a + _v_deep[b] + _v_deep[c] + _v_deep[d]) * 0.25

		var cell: int = _mesh.f_cell[q]
		var t: int = kinds[cell]
		var cut: bool = _mesh.f_flat[q] != 0

		# Which way this facet is turned. Front or back comes off the source
		# cell's own carved outward direction — the one thing in the file that is
		# unambiguously outward — read through the station's frame so a bent
		# spine's flank faces where the bend actually put it.
		var lit: float = 1.0
		if not cut:
			var pk: int = patch_of[cell]
			if pk < _af_o.size() and _af_o[pk] != null:
				var o: PackedVector2Array = _af_o[pk]
				var s: float = clampf(station[cell], 0.0, float(o.size() - 1))
				var ci: int = mini(int(s), o.size() - 1)
				var out: Vector3 = normals[cell]
				lit = out.x * (_dp_f[pk] as PackedFloat32Array)[ci] \
					+ out.y * (_dp_l[pk] as PackedFloat32Array)[ci] + out.z * _dp_h
		var front: bool = lit > 0.0

		# ...and how much light it catches, which is the facet's *own* plane
		# rather than the cell's smoothed direction. That difference is the whole
		# low-poly reading: neighbouring facets of one curved shell land on
		# visibly different shades and the eye reads the planes.
		var lam: float = CUT_LAM
		if not cut:
			var uz: float = (_v_deep[b] - deep_a) * _scale
			var vz: float = (_v_deep[d] - deep_a) * _scale
			var ux: float = pb.x - pa.x
			var uy: float = pb.y - pa.y
			var vx: float = pd.x - pa.x
			var vy: float = pd.y - pa.y
			var nx: float = uy * vz - uz * vy
			var ny: float = uz * vx - ux * vz
			var nz: float = ux * vy - uy * vx
			var span: float = sqrt(nx * nx + ny * ny + nz * nz)
			if span < 0.000001:
				continue
			# Turned to face the eye whichever way it was wound, so a crater's far
			# wall is lit as the surface it is rather than as a hole.
			if nz < 0.0:
				span = -span
			lam = maxf((nx * LIGHT.x + ny * LIGHT.y + nz * LIGHT.z) / span, 0.0)

		var band: int = clampi(int(lam * float(SHADES)), 0, SHADES - 1)
		var ink: Color = _shade[((t * 2 + (0 if front else 1)) * SHADES) + band]
		# What is happening to this flesh, in the order it matters: what the
		# ledger has worn away, whether the facet stands on an open wound, and
		# what the region as a whole is doing.
		var wp = worn[patch_of[cell]]
		if wp != null:
			ink = _worn(lat, grid, wp, cell, ink, t)
		if _mesh.f_raw[q] != 0:
			ink = ink.lerp(COL_RAW, WOUND_RIM)
		var reg: int = regions[cell]
		if _wash_amt[reg] > 0.0:
			ink = ink.lerp(_wash_col[reg], _wash_amt[reg])
		if thin:
			ink.a = clampf(XRAY_ALPHA + 0.11 * float(_mesh.f_shell[q]), 0.0, 1.0)

		var v: int = n * 4
		_points[v] = pa
		_points[v + 1] = pb
		_points[v + 2] = pc
		_points[v + 3] = pd
		_colors[v] = ink
		_colors[v + 1] = ink
		_colors[v + 2] = ink
		_colors[v + 3] = ink
		var mid: Vector2 = (pa + pb + pc + pd) * 0.25
		_reach_over(mid, pa, pb, pc, pd)
		_cell_page[n] = mid
		_cell_deep[n] = deep
		_shown[n] = cell
		_shown_face[n] = q
		_shown_front[n] = 1 if front else 0
		_depths[n] = Vector2(deep, float(n))
		n += 1
	var mesh_faces: int = n
	n = _chain_pass(lat, n, true)
	_shown_count = n
	if n == 0:
		return

	# Far side of the animal first, or a rolled specimen shows its back through
	# its own belly.
	_depths.resize(n)
	_depths.sort()
	_indices.resize(n * 6)
	var at: int = 0
	for j in n:
		var v: int = int(_depths[j].y) * 4
		_indices[at] = v
		_indices[at + 1] = v + 1
		_indices[at + 2] = v + 2
		_indices[at + 3] = v
		_indices[at + 4] = v + 2
		_indices[at + 5] = v + 3
		at += 6
	_points.resize(n * 4)
	_colors.resize(n * 4)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _indices, _points, _colors)
	_index_marks()
	if _fine:
		_draw_facet_edges(mesh_faces)
		if show_lattice:
			_draw_census(lat, mesh_faces)


## The hairline along each facet's own edges — what tells one plane from the next
## where two of them happen to catch the light alike. Only the facets turned
## toward the eye are outlined: the far half of the body is behind the near half
## and lining it would be drawing through the animal.
func _draw_facet_edges(faces: int) -> void:
	_edge_lines.resize(0)
	for j in faces:
		if _shown_front[j] == 0:
			continue
		var v: int = j * 4
		var p0: Vector2 = _points[v]
		var p1: Vector2 = _points[v + 1]
		var p2: Vector2 = _points[v + 2]
		var p3: Vector2 = _points[v + 3]
		_edge_lines.append(p0)
		_edge_lines.append(p1)
		_edge_lines.append(p1)
		_edge_lines.append(p2)
		if p2 != p3:
			_edge_lines.append(p2)
			_edge_lines.append(p3)
		_edge_lines.append(p3)
		_edge_lines.append(p0)
	if _edge_lines.size() >= 2:
		draw_multiline(_edge_lines, FACET_EDGE, 0.6, true)


## The census under the skin: a mark on every cell the mesh was actually skinned
## off, so the surface can be seen standing on real cells rather than taken on
## trust. Asked for, never the default face of the animal.
func _draw_census(lat: AnatomyLattice, faces: int) -> void:
	var arm: float = maxf(AnatomyLattice.CELL * _scale * 0.34, 0.8)
	_lattice_lines.resize(0)
	for j in faces:
		var p: Vector3 = _cell_at(lat, _shown[j])
		var at := Vector2(p.x, p.y)
		_lattice_lines.append(at - Vector2(arm, 0.0))
		_lattice_lines.append(at + Vector2(arm, 0.0))
		_lattice_lines.append(at - Vector2(0.0, arm))
		_lattice_lines.append(at + Vector2(0.0, arm))
	if _lattice_lines.size() >= 2:
		draw_multiline(_lattice_lines, COL_LATTICE, 0.7, true)


## The chains, as continuous volumes: every internal structure whose cells are
## exposed under the current filters is drawn as a run of quads along its own
## centreline, as thick as the structure is thick — a bone is one solid on its
## axis, a major vessel or nerve is one pipe, and neither is a heap of boxes.
##
## Damage stays spatial: a stretch whose member cells the ledger has taken
## darkens toward the tissue's spent shade, and a sample more than half gone is
## a break in the run — a snapped femur shows its fracture as a gap in the bone,
## exactly where the teeth took it. The segments go into the same painter-sorted
## buffers as the marks, so a bone sits correctly among the flesh around it, and
## each segment registers for the hover test like any mark.
##
## `drawing` false places the segments for a hover test without painting them —
## the same arrangement `_place_marks` has with the cell pass.
func _chain_pass(lat: AnatomyLattice, n: int, drawing: bool) -> int:
	var form: TissueForm = _form
	if form.sample_total == 0 or _sample_vis.size() != form.sample_total:
		return n
	var sliced: bool = slice_axis >= 0
	var plane: float = slice_plane()
	var floor_r: float = TUBE_MIN
	for c in form.chain_count:
		var t: int = int(form.chain_kind[c])
		if not tissue_shown(t):
			continue
		var part: int = int(form.chain_part[c])
		# Ring chains sample their hoop in sectors the cells fill unevenly, so
		# their join reaches further; and bone banks a base band by part — a
		# girdle is denser stock than a rib, and both are one material along
		# their whole run rather than thirty differently-lit boxes.
		var tol: int = 3 if form.chain_ringed(c) else 1
		var base_band: int = TUBE_BAND
		if part == AnatomyLattice.PART_GIRDLE:
			base_band -= 3
		elif part == AnatomyLattice.PART_RIB:
			base_band += 1
		var prev: int = -1
		var prev_bucket: int = 0
		var prev_page := Vector2.ZERO
		var prev_deep: float = 0.0
		var prev_r: float = 0.0
		var prev_worn: float = 0.0
		for s in range(form.chain_from[c], form.chain_from[c + 1]):
			if _sample_vis[s] == 0 \
					or (sliced and form.s_canon[s][slice_axis] > plane):
				prev = -1
				continue
			var gone_frac: float = form.sample_gone(lat, s)
			if gone_frac >= TissueForm.BREAK_SHARE:
				prev = -1
				continue
			var pk: int = int(form.s_patch[s])
			if pk >= _af_o.size() or _af_o[pk] == null:
				prev = -1
				continue
			var o: PackedVector2Array = _af_o[pk]
			var st: float = clampf(form.s_station[s], 0.0, float(o.size() - 1))
			var ci: int = mini(int(st), o.size() - 1)
			var f: float = st - float(ci)
			var side: float = form.s_lat[s]
			var ahead: float = form.s_fore[s]
			var up: float = form.s_lift[s]
			var page: Vector2 = o[ci] + (_af_s[pk] as PackedVector2Array)[ci] * f \
				+ (_af_l[pk] as PackedVector2Array)[ci] * side \
				+ (_af_f[pk] as PackedVector2Array)[ci] * ahead + _af_h * up
			var deep: float = (_dp_o[pk] as PackedFloat32Array)[ci] \
				+ (_dp_s[pk] as PackedFloat32Array)[ci] * f \
				+ (_dp_l[pk] as PackedFloat32Array)[ci] * side \
				+ (_dp_f[pk] as PackedFloat32Array)[ci] * ahead + _dp_h * up
			var r: float = maxf(form.s_radius[s] * _scale, floor_r)
			if prev >= 0 and form.s_bucket[s] - prev_bucket <= tol:
				if drawing:
					var dir: Vector2 = page - prev_page
					var span: float = dir.length()
					if span > 0.0001:
						dir /= span
						var nrm := Vector2(-dir.y, dir.x)
						# Reached a little past both ends, so consecutive
						# segments close their elbows on a curved run.
						var ext: Vector2 = dir * minf(prev_r, span * 0.3)
						var band: int = base_band
						if t == AnatomyLattice.BONE:
							band += TUBE_SEG if (form.s_bucket[s] & 1) == 0 \
								else -TUBE_SEG
						var ink: Color = _shade[t * SHADES \
							+ clampi(band, 0, SHADES - 1)]
						var wear: float = maxf(gone_frac, prev_worn)
						if wear > 0.0:
							ink = ink.lerp(TISSUE_WORN[t],
								wear / TissueForm.BREAK_SHARE * 0.85)
						var v: int = n * 4
						_points[v] = prev_page - ext - nrm * prev_r
						_points[v + 1] = prev_page - ext + nrm * prev_r
						_points[v + 2] = page + ext + nrm * r
						_points[v + 3] = page + ext - nrm * r
						_colors[v] = ink
						_colors[v + 1] = ink
						_colors[v + 2] = ink
						_colors[v + 3] = ink
						_depths[n] = Vector2((deep + prev_deep) * 0.5, float(n))
						_cell_page[n] = page
						_cell_deep[n] = deep
						_shown[n] = form.s_rep[s]
						# Not a facet of the mesh: the hover marks the cell rather
						# than outlining a polygon, and no hairline is drawn round
						# a tube.
						_shown_face[n] = -1
						_shown_front[n] = 0
						n += 1
				else:
					_cell_page[n] = page
					_cell_deep[n] = deep
					_shown[n] = form.s_rep[s]
					_shown_face[n] = -1
					_shown_front[n] = 0
					n += 1
			prev = s
			prev_bucket = form.s_bucket[s]
			prev_page = page
			prev_deep = deep
			prev_r = r
			prev_worn = gone_frac
	return n


## Places every facet on the page without drawing it, for a hover test arriving
## before the specimen has been painted — which is every hover in a headless run,
## and the first one after a filter changes. The drawing pass does the same
## placement inline as part of the work it is already doing, so this is never run
## in the ordinary way of things.
func _place_marks(lat: AnatomyLattice) -> void:
	var faces: int = _mesh.count
	var room: int = faces + _form.sample_total
	if _cell_page.size() != room:
		_cell_page.resize(room)
		_cell_deep.resize(room)
		_shown.resize(room)
		_shown_face.resize(room)
		_shown_front.resize(room)
	if _points.size() < room * 4:
		_points.resize(room * 4)
	_pick_reach = 0.0
	_pose_mesh()
	var n: int = 0
	for q in faces:
		var corner: int = q * 4
		var a: int = _mesh.f_v[corner]
		if _v_deep[a] == -INF:
			continue
		var mid := Vector2.ZERO
		var deep: float = 0.0
		var v: int = n * 4
		for m in 4:
			var w: int = _mesh.f_v[corner + m]
			_points[v + m] = _v_page[w]
			mid += _v_page[w]
			deep += _v_deep[w]
		mid *= 0.25
		_reach_over(mid, _points[v], _points[v + 1], _points[v + 2], _points[v + 3])
		_cell_page[n] = mid
		_cell_deep[n] = deep * 0.25
		_shown[n] = _mesh.f_cell[q]
		_shown_face[n] = q
		_shown_front[n] = 1
		n += 1
	n = _chain_pass(lat, n, false)
	_shown_count = n
	_index_marks()


## How far one facet reaches from its own middle, kept as the widest seen this
## frame. The hover test searches that far and no further: a facet is bucketed by
## its middle, so a pointer inside a wide one can be a long way from the bucket it
## was filed under.
func _reach_over(mid: Vector2, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
	_pick_reach = maxf(_pick_reach, sqrt(maxf(maxf(
		mid.distance_squared_to(a), mid.distance_squared_to(b)),
		maxf(mid.distance_squared_to(c), mid.distance_squared_to(d)))))


## Buckets this frame's facets by where they landed, for the hover test.
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


## Every tissue at every turn of a facet, banked once a frame.
##
## The shade of a facet depends on two things and only two: which tissue it is
## and how much light its own plane catches, front or back. Both are small sets,
## so the whole range of answers is a table of a few hundred colours — and the
## facet pass then costs one array read where it would otherwise cost three
## colour lerps apiece.
func _bake_shades() -> void:
	# A dead animal's whole palette is drained toward its own spent shades, and
	# that is the only thing in the bank that is about the creature rather than
	# about the light — so it is the only thing the key has to carry.
	var dead: bool = is_instance_valid(creature) and not creature.alive
	var key: int = hash([dead])
	var want: int = AnatomyLattice.TISSUES * 2 * SHADES
	if key == _shade_key and _shade.size() == want:
		return
	_shade_key = key
	if _shade.size() != want:
		_shade.resize(want)
	for t in AnatomyLattice.TISSUES:
		var base: Color = TISSUE_INK[t]
		if dead:
			base = base.lerp(TISSUE_WORN[t], DEAD_DRAIN)
		for side in 2:
			# A facet turned away from the eye is the far wall of a crater or the
			# inside of an opened body, and is seen in that flesh's own shadow.
			var dim: float = FACET_BACK if side == 1 else 1.0
			for k in SHADES:
				var lam: float = (float(k) + 0.5) / float(SHADES)
				var f: float = (FACET_FLOOR + FACET_GAIN * lam) * dim
				_shade[(t * 2 + side) * SHADES + k] = Color(
					minf(base.r * f, 1.0), minf(base.g * f, 1.0), minf(base.b * f, 1.0))


## What each region of the animal is going through, as one colour and one amount
## per region — so the facet pass asks a nine-entry table rather than the
## functional layer.
##
## Two readings, and the louder one wins because they are saying the same thing
## at different speeds. A region that has just lost cells flares, and the flare
## pulses while it lasts: that is a bite landing, and it has to be visible in the
## moment it happens or the player learns about their own wounds by noticing a
## number later. A region the blood has stopped reaching goes pale and stays
## pale: that is flesh being lost slowly, and it is the reading that says a limb
## is dying before any of it has gone.
func _bake_wash() -> void:
	if _wash_amt.size() != BodyPlan.REGIONS:
		_wash_amt.resize(BodyPlan.REGIONS)
		_wash_col.resize(BodyPlan.REGIONS)
	var state: BodyState = creature.anatomy.state if is_instance_valid(creature) \
		and creature.anatomy != null else null
	var beat: float = 0.6 + 0.4 * (0.5 - 0.5 * cos(TAU * fposmod(_clock * FLARE_BEAT, 1.0)))
	for reg in BodyPlan.REGIONS:
		var pale: float = 0.0
		if state != null and reg < state.vessels.delivery.size():
			var reach: float = clampf(state.vessels.delivery[reg], 0.0, 1.0)
			pale = clampf((PALE_FROM - reach) / PALE_FROM, 0.0, 1.0) * PALE_TO
		var flare: float = (_flare[reg] if reg < _flare.size() else 0.0) * FLARE_LIFT * beat
		if flare >= pale:
			_wash_amt[reg] = flare
			_wash_col[reg] = COL_RAW
		else:
			_wash_amt[reg] = pale
			_wash_col[reg] = COL_PALE


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


# -------------------------------------------------------------- networks ----

## One supply network, laid along the ledger cells it actually passes through.
## Width and alpha carry what *arrives* rather than what survives locally, so a
## sound run still fades out behind a cut upstream of it. `deep_open` is whether
## the trunk's own interior is on view — the body runs lie under the muscle
## against the spine, and are skipped while that cover is intact.
func _draw_network(grid: TissueGrid, runs: Array[BodyPlan.Conduit],
		network: AnatomyNetwork, tint: Color, pulses: int, speed: float,
		beat: bool, offset: float, deep_open: bool) -> void:
	for run in runs:
		if not deep_open and run.patch_key == TissueGrid.BODY_KEY:
			continue
		var p: TissueGrid.Patch = grid.patch(run.patch_key)
		if p == null or not p.live or run.cells.size() < 2:
			continue
		_gather_run(grid, runs, run, offset)
		var reach: float = clampf(network.delivery[run.region], 0.0, 1.0)
		# Calibre falls with each branching generation: the trunk vessel out of
		# the chest is a tube, the run into a foot is a thread. Same for nerves.
		var calibre: float = 1.0 / (1.0 + CALIBRE_FALL * float(_depth_of(runs, run)))
		for i in range(_run.size() - 1):
			if _run_gone[i] != 0 or _run_gone[i + 1] != 0:
				draw_dashed_line(_run[i], _run[i + 1], Color(tint, 0.16), 0.9, 2.5, true)
				continue
			draw_line(_run[i], _run[i + 1], Color(tint, 0.18 + 0.62 * reach),
				(0.7 + 1.9 * calibre) * (0.55 + 0.45 * reach), true)
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


## The local supply trees: the branches space colonisation grew from each run
## toward the tissue that demands supply — see TissueForm. Everything finer than
## these is the density field, and the field shows here too: a region that asks
## little was grown few branches and inks the ones it has faintly, while the
## delivery term fades a starved or silenced region's whole tree.
##
## Every branch vertex is a lattice cell, posed through the same affine as the
## marks — the tree bends with the flesh it supplies, and a vertex whose cell
## has been eaten breaks the branch there. A vertex whose cell's tissue is
## filtered off breaks it the same way: a branch runs inside flesh, and where
## the flesh has been lifted away the branch is not left hanging in the air.
func _draw_branches(lat: AnatomyLattice, network: AnatomyNetwork, net: int,
		tint: Color) -> void:
	var paths: Array = _form.branches[net]
	if paths.is_empty():
		return
	var owner: PackedInt32Array = _form.branch_region[net]
	var field: PackedFloat32Array = _form.density[net]
	if field.size() < BodyPlan.REGIONS:
		return
	var hidden: int = 0
	for t in AnatomyLattice.TISSUES:
		if not tissue_shown(t):
			hidden |= 1 << t
	var sliced: bool = slice_axis >= 0
	var plane: float = slice_plane()
	for reg in BodyPlan.REGIONS:
		_branch_lines.resize(0)
		for b in paths.size():
			if owner[b] != reg:
				continue
			var path: PackedInt32Array = paths[b]
			var live: bool = false
			var prev := Vector2.ZERO
			for idx in path:
				if lat.gone[idx] != 0 or (hidden & (1 << int(lat.kind[idx]))) != 0 \
						or (sliced and lat.pos[idx][slice_axis] > plane):
					live = false
					continue
				var at3: Vector3 = _cell_at(lat, idx)
				var at := Vector2(at3.x, at3.y)
				if live:
					_branch_lines.append(prev)
					_branch_lines.append(at)
				prev = at
				live = true
		if _branch_lines.size() < 2:
			continue
		var reach: float = clampf(network.delivery[reg], 0.0, 1.0)
		var alpha: float = (0.08 + 0.34 * reach) * (0.45 + 0.55 * field[reg])
		draw_multiline(_branch_lines, Color(tint, alpha), BRANCH_WIDTH, true)


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
## The facet under the pointer, outlined. Its own polygon rather than a ring:
## what is under the cursor is a piece of the surface with a shape, and drawing
## that shape is what tells the player the mesh they are reading is made of the
## facets they can see.
func _draw_hover(lat: AnatomyLattice) -> void:
	if _hover_voxel < 0 or _hover_voxel >= lat.count:
		return
	# Against the cell it was picked for, not merely against the count: the facets
	# are laid down afresh every frame and an index alone could have come to mean
	# a different piece of the animal since the pointer last moved.
	if _hover_face >= 0 and _hover_face < _shown_count \
			and _shown[_hover_face] == _hover_voxel:
		var v: int = _hover_face * 4
		var p0: Vector2 = _points[v]
		var p1: Vector2 = _points[v + 1]
		var p2: Vector2 = _points[v + 2]
		var p3: Vector2 = _points[v + 3]
		var ring := PackedVector2Array([p0, p1, p1, p2, p2, p3, p3, p0])
		draw_multiline(ring, INK, 1.3, true)
		return
	# A chain segment, or a facet the pass has not laid down this frame: the cell
	# itself is still a place on the animal, so it is marked as one.
	var p: Vector3 = _cell_at(lat, _hover_voxel)
	draw_arc(Vector2(p.x, p.y), AnatomyLattice.CELL * _scale * 1.6 + 2.0, 0.0, TAU,
		14, INK, 1.3, true)


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
			_hover_face = -1
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
		_hover_face = -1
		cell_hovered.emit("", false)


## Which cell is under the cursor: the nearest facet whose own polygon covers the
## pointer, tested against the facets exactly as they were last drawn — so a
## rolled specimen's near leg beats the belly behind it, and a peeled or
## sectioned specimen picks what is actually showing.
##
## The polygon rather than a box around it, because a facet is the shape it is:
## a box would let a facet claim the paper beside it, and along a silhouette that
## is most of what the pointer is over.
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
	# Only the facets in the buckets the pointer's own reach covers. The reach is
	# the widest facet on the specimen, so a bucket walk cannot miss one that
	# genuinely covers the pointer from further off.
	var span: int = int(ceil(maxf(_pick_reach, PICK_BUCKET) / PICK_BUCKET))
	var home: Vector2 = (at - _pick_origin) / PICK_BUCKET
	var hx: int = int(floor(home.x))
	var hy: int = int(floor(home.y))
	var found: int = -1
	var face: int = -1
	var nearest: float = -INF
	for ox in range(hx - span, hx + span + 1):
		for oy in range(hy - span, hy + span + 1):
			var bucket = _pick_grid.get((ox << 20) ^ oy)
			if bucket == null:
				continue
			for j in bucket:
				if _cell_deep[j] <= nearest:
					continue
				if not _covers(j, at):
					continue
				nearest = _cell_deep[j]
				found = _shown[j]
				face = j
	if found >= 0:
		if _hover_voxel != found or _hover_face != face:
			_hover_voxel = found
			_hover_face = face
			cell_hovered.emit(_readout(lat, grid, found), lat.gone[found] != 0)
		return
	if _hover_voxel >= 0:
		_hover_voxel = -1
		_hover_face = -1
		cell_hovered.emit("", false)


## Whether one laid-down facet's own quad covers a point. Every quad here comes
## off a ring, so it is convex by construction and the winding test is four
## cross products — which is why the hover can afford to be exact.
func _covers(j: int, at: Vector2) -> bool:
	var v: int = j * 4
	var sign: int = 0
	for k in 4:
		var a: Vector2 = _points[v + k]
		var b: Vector2 = _points[v + (k + 1) % 4]
		var cross: float = (b.x - a.x) * (at.y - a.y) - (b.y - a.y) * (at.x - a.x)
		if is_zero_approx(cross):
			continue
		var side: int = 1 if cross > 0.0 else -1
		if sign == 0:
			sign = side
		elif side != sign:
			return false
	return sign != 0


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

	# The tissue's own properties, where it has ones worth quoting: the fibre
	# composition on muscle, the local supply-field density on the two networks.
	if t == AnatomyLattice.MUSCLE and creature.params != null:
		bits.append("FT %d%%" % int(round(creature.params.fast_twitch * 100.0)))
	elif t == AnatomyLattice.NERVE or t == AnatomyLattice.VESSEL:
		var net: int = TissueForm.NERVES if t == AnatomyLattice.NERVE \
			else TissueForm.VESSELS
		var field: PackedFloat32Array = _form.density[net]
		if field.size() > int(lat.region[i]):
			bits.append("FIELD %d%%" % int(round(field[lat.region[i]] * 100.0)))

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
