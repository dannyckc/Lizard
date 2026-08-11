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
## Which of the three a piece of the animal is drawn by is decided by what that
## piece *is*, and between them they have to cover the census: a tissue that is
## being shown and drawn by none of them is a hole in the picture that is not a
## hole in the animal, which is the one failure this file cannot be allowed. So a
## cell that belongs to a continuous structure is drawn by that structure's tube
## and left out of the skin; flesh is skinned into rings; and whatever is left —
## a place where the animal is two cells wide, a tissue too scattered to make a
## ring of, a bone the lattice has only a scrap of — is drawn as the cells it is.
##
## The depth stack and the two supply networks are shown on different terms, and
## the difference is what they are rather than a preference. Skin, fat, muscle,
## bone and organ are what the animal is built out of, so they stand in front of
## each other and the outermost one shown is the one seen. A vascular tree is not
## a layer of anything — it threads all five — so it is an overlay: switched on,
## it is drawn whole and over the top, because "what is still reaching this leg"
## is a fair question to ask of an animal with its hide on.
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
## lines threading the middle of it. Switching an overlay off is not one of the
## four: a hidden nerve does not bore a channel down the muscle it runs through.
##
## The specimen is presented upright, snout at the top, by rotating the whole
## body into the mean direction of its own spine — a rigid transform that
## re-orients without straightening, so the pose stays exactly the pose. And it
## can be walked around: the trackball seizes the point of the containing sphere
## under the pointer and carries it with the hand, and the wheel leans in on what
## is under it. `orient` is the whole of the eye's position; `spin`, `tilt` and
## `roll` are readings off it, and the guide in the corner is the animal's own
## three axes put through the same projection. Framing is the same sphere and
## therefore does not move while the specimen turns.
##
## It opens off the square, at DEFAULT_ORBIT — see `default_orbit`.
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
## The specimen's hide: the page's own black, the same ink the field draws a
## creature's silhouette in.
##
## Which makes the skin the darkest thing on the slab and every layer under it
## lighter than the wrap it came out of — peel the hide and the body brightens,
## which is the right way round for a dissection. It costs the one thing a black
## surface cannot do, which is take a light by being scaled: see `_bake_shades`,
## where a tissue this dark is lit toward a sheen instead so that the facets
## still read as planes rather than as one hole in the paper.
const COL_HIDE := Color("000000")
## What a tissue too dark to be lit by scaling is carried toward instead, and how
## far a fully lit facet of it gets. Low enough that the hide still reads as
## black beside anything else on the slab.
const SHEEN := Color("57514a")
const SHEEN_LIFT: float = 0.62
## Luminance a fully lit facet must reach before the scale is doing any work at
## all. Under it the sheen takes over.
const SHEEN_UNDER: float = 0.10
## What an opened wound is: the raw colour of flesh the teeth have just been
## through, which no intact tissue anywhere on the palette comes near.
const COL_RAW := Color("8e1b14")
## The bloodless tone a region drifts toward when nothing is reaching it.
const COL_PALE := Color("b9b2a4")

## Layer toggles, as a mask over the lattice's first five tissues. The nerve and
## vessel cells ride `show_nerves` / `show_vessels` beside it, exactly as the
## network overlays do.
const ALL_LAYERS: int = CreatureView.ALL_LAYERS

## Two rows past the lattice's own tissues, for the named organs. They are not
## tissues of their own — the census counts them as organ — but they are inked
## as the system they belong to: the brain wears the nerve overlay's blue and
## the heart the vessels' red, because that is the toggle each one rides.
const SHADE_BRAIN: int = AnatomyLattice.TISSUES
const SHADE_HEART: int = AnatomyLattice.TISSUES + 1
const SHADE_KINDS: int = AnatomyLattice.TISSUES + 2

## One ink per tissue, and the worn shade damage drags it toward — the same
## palette the field inks the creature and its meat with, with the two organ
## rows after them.
static var TISSUE_INK: PackedColorArray = PackedColorArray([
	COL_HIDE,
	CreatureView.COL_FAT,
	CreatureView.COL_MUSCLE,
	CreatureView.COL_BONE,
	CreatureView.COL_ORGAN,
	CreatureView.COL_DBG_NERVE,
	CreatureView.COL_DBG_VESSEL,
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
	Color("1b4054"),
	Color("5e1218"),
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
## How far the wheel may carry the specimen either side of the fit the stage
## worked out for it, and what one notch of the wheel is worth. The fit is still
## what decides the framing; this is leaning in and back from it.
const ZOOM_MIN: float = 0.55
const ZOOM_MAX: float = 3.2
const ZOOM_STEP: float = 1.09
## The orientation guide: how long an arm of it is at full length, how far in
## from the corner it stands, and how far a foreshortened arm has to fall before
## its letter is dropped as unreadable.
const AXIS_ARM: float = 19.0
const AXIS_INSET: float = 31.0
const AXIS_FAINT: float = 0.30
## Orbit under which the projection is the plain top-down one.
const FLAT: float = 0.002
## Where the eye stands before anybody has touched it, in the same three readings
## the drawer prints back: a three-quarter view from above and off the flank, with
## the specimen laid across the page rather than up it. Straight down was the
## honest default for a body drawn flat, and it is the wrong one for a body with a
## third axis in it — an overhead view is the one angle at which none of the depth
## the lattice carries can be seen at all. Degrees, because they are the units the
## readout names them in and the units anybody re-picking them would work in.
const DEFAULT_SPIN: float = 41.0
const DEFAULT_TILT: float = 48.0
const DEFAULT_ROLL: float = -125.0
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
## The skeleton's own outline: a dark rim laid just behind every stretch of bone
## tube, in page pixels, and how far behind its own bone it sorts. Bone is the
## palest thing on the slab and its tubes run against bone-coloured neighbours —
## vertebra against rib, carpal against carpal — so without a rim the skeleton
## reads as one pale mass; with it every element is its own outlined piece.
##
## The rim is a hairline, not a border: it shows as `BONE_RIM` of ink outside
## the tube, which is what a `BONE_EDGE`-width line centred on a mesh edge
## shows outside *its* facet — so a tube's outline and the skull's facet lines
## read as one and the same stroke.
const BONE_RIM: float = 0.3
const BONE_RIM_BACK: float = 0.6
const COL_BONE_RIM := Color(INK, 0.42)
## The hairline bone facets take instead of the ordinary one — the skull is
## skinned as mesh rather than as tubes, and it wants the same contrast the
## tubes get from their rim.
const BONE_EDGE := Color(INK, 0.42)

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
## The loose cells — flesh too thin at that station to be made a ring of. Most
## the pass will lay down before it starts thinning them, and the smallest half
## an edge of one may come out on the page.
##
## Each one is drawn as the box it is: the cell's own three half-edges posed
## through its station's affine, and the three faces turned toward the eye laid
## as facets, each lit by its own plane exactly as the mesh's are. A flat
## axis-aligned square — what this pass used to lay — has no plane to catch the
## light with and does not turn with the specimen, which is why a thinned-out
## tissue read as a scatter of screen pixels rather than as small pieces of the
## same low-poly solid as everything around them.
const LOOSE_MOST: int = 1500
const LOOSE_MIN: float = 0.6
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
## Pieces one span of a conduit or a branchlet is drawn in. Both are polylines
## between cell centres, and a cell centre is a place on a grid — see
## `_smooth_run`.
const SMOOTH_STEPS: int = 4

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
## How far the wheel has leaned in past the fit. Multiplies the scale and
## nothing else — the ball the eye turns and the ball the animal is measured
## against are both untouched, so leaning in cannot make the specimen drift or
## turn differently under the hand.
var zoom: float = 1.0

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
## How far each limb patch's posed frame was carried to land its top on the
## trunk's own socket — see `_close_seams`. Read again by the network overlay so
## a limb's conduit rides the same flesh it threads.
var _seam_page := PackedVector2Array()
var _seam_deep := PackedFloat32Array()

# Reused geometry: this redraws every frame, so the cell pass writes into these
# rather than allocating per cell.
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _depths := PackedVector2Array()
var _cell_page := PackedVector2Array()
var _cell_deep := PackedFloat32Array()
var _edge_lines := PackedVector2Array()
var _bone_edge_lines := PackedVector2Array()
var _lattice_lines := PackedVector2Array()
var _run := PackedVector2Array()
var _run_gone := PackedByteArray()
var _curve := PackedVector2Array()
var _curve_gone := PackedByteArray()
var _path := PackedVector2Array()
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
	orient = default_orbit()


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


## Puts the eye back where the drawer opens it — and back to the stage's own fit,
## because leaning in is part of where the eye is.
func reset_orbit() -> void:
	orient = default_orbit()
	set_zoom(1.0)


## The viewpoint the drawer opens at, built from the three readings it prints.
##
## Composed in the order the readouts are taken in, which is what makes the three
## constants mean what they say: the spin and the tilt aim the eye — see `_aim` —
## and the roll is a turn about the eye itself, so it lays the specimen across the
## page without disturbing where the page is being looked at from. Send this basis
## in and `spin`, `tilt` and `roll` read back the three numbers exactly.
static func default_orbit() -> Basis:
	return Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(DEFAULT_ROLL)) \
		* Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(DEFAULT_TILT)) \
		* Basis(Vector3(0.0, 1.0, 0.0), deg_to_rad(DEFAULT_SPIN))


## Whether the eye is still where the drawer opened it. What the panels ask before
## naming the angles: on an untouched specimen the three readings are the default
## rather than anything the player did, and printing them back would be reporting
## the file instead of the hand.
func at_default_orbit() -> bool:
	return orient.is_equal_approx(default_orbit()) and is_equal_approx(zoom, 1.0)


## Leans the eye in or back. The scale is re-derived here rather than waited for,
## so a wheel notch has landed by the time anything reads the view again.
func set_zoom(value: float) -> void:
	var want: float = clampf(value, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(want, zoom):
		return
	zoom = want
	if _fitted:
		_scale = _ball * zoom / _radius
		_reframe()
		queue_redraw()


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
	_scale = _ball * zoom / _radius
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


## What tissue a cell counts as *to the eye*, which is not always what it is
## made of — see `AnatomyLattice.sheathed`.
##
## Where the animal is thinner than the lattice can layer, the outermost cell
## carries the tissue it is mostly made of and wears its skin as a film the grid
## cannot hold a cell of. So while the skin is on the specimen, such a cell is
## skin: it is drawn in hide, it is what the silhouette is made of, and peeling
## the muscle off a lizard's leg does not strip the leg. Lift the skin and the
## same cell is the muscle or the bone it has always been, and shows as that —
## which is the whole of what peeling a layer is supposed to do.
##
## One rule, asked in the two places that decide the picture: what is on the
## surface, and what colour it is.
func _seen_as(lat: AnatomyLattice, i: int, skinned: bool) -> int:
	if skinned and lat.sheathed.size() == lat.count and lat.sheathed[i] != 0:
		return AnatomyLattice.SKIN
	return int(lat.kind[i])


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
		# The named organs are gated cell by cell on the overlays — see
		# `_shell_surface` — so the organ bit never joins the mask: a hidden
		# heart does not open the chest any more than a hidden vessel does.
		if t == AnatomyLattice.ORGAN:
			continue
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
	# ...and then the two supply networks, whole. They are overlays rather than
	# layers of the depth stack — see `_draw` — so every sample of a shown one is
	# on view whether or not the flesh over it happens to have been lifted. The
	# skeleton is pointedly not: a bone *is* part of the stack, and is seen when
	# the body over it is opened, like everything else in it.
	for c in _form.chain_count:
		var kind: int = int(_form.chain_kind[c])
		if kind != AnatomyLattice.NERVE and kind != AnatomyLattice.VESSEL:
			continue
		if not tissue_shown(kind):
			continue
		for s in range(_form.chain_from[c], _form.chain_from[c + 1]):
			_sample_vis[s] = 1
	_mesh.build(lat, _surfaces, _plane_cells, slice_axis, _form.sample_of,
		tissue_shown(AnatomyLattice.SKIN))


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
	# What counts as a way *in*, which is not the same list as what is being left
	# out. Switching an overlay off cannot open the flesh: a nerve is a thread
	# through the middle of a muscle, and a body with the nerves hidden is a whole
	# body rather than one with a channel bored down it — the muscle around that
	# thread is interior either way and has no business being drawn as surface.
	var opened: int = hidden & ~((1 << AnatomyLattice.NERVE) | (1 << AnatomyLattice.VESSEL))
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
	# A sheathed cell is skin while the skin is up — see `_seen_as`. Hoisted to a
	# flag and an array so the test inside the walk is one read and one compare.
	var sheath: PackedByteArray = lat.sheathed
	var skinned: bool = tissue_shown(AnatomyLattice.SKIN) \
		and sheath.size() == lat.count
	# A cell is in the plane when the plane passes through the cell itself: the
	# kept side, within one cell of the cut. That band is the cut face.
	var near_plane: float = plane - AnatomyLattice.CELL
	# The named organs ride the overlays rather than the layer stack: the brain
	# is shown with the nerves it crowns, the heart with the vessels it drives,
	# and neither answers the organ layer bit at all. Hidden, they no more open
	# the flesh around them than a switched-off network does.
	var organs: PackedByteArray = lat.organ_of
	for i in lat.count:
		var seen: int = AnatomyLattice.SKIN if skinned and sheath[i] != 0 \
			else int(kinds[i])
		if seen == AnatomyLattice.ORGAN:
			if not (show_nerves if organs[i] == BodyPlan.BRAIN else show_vessels):
				continue
		elif (hidden & (1 << seen)) != 0:
			continue
		if gone[i] != 0 or (sliced and where[i][slice_axis] > plane):
			lifted.append(i)
			continue
		present[i] = 1
		if outermost and sliced and where[i][slice_axis] > near_plane:
			_plane_cells.append(i)
		if outermost and xray and chained and chain_of[i] >= 0:
			_sample_vis[chain_of[i]] = 1
		if (int(neighbours[i]) & opened) == 0:
			continue
		listed[i] = 1
		surface.append(i)
		# A cell of a continuous structure — a bone, a cord, a vessel — has its
		# chain's tube drawn wherever the way in to it is open, and nowhere else.
		# The ring skin leaves those cells to their tubes; see SpecimenMesh.
		# A *sheathed* one is being worn as hide while the skin is on — it was
		# skinned into the mesh as skin, so its tube stays down; drawn anyway, an
		# ankle carries its own skeleton outside its skin.
		if chained and chain_of[i] >= 0 and outermost \
				and not (skinned and sheath[i] != 0):
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
	_close_seams()


## Carries each limb's posed frame onto the trunk's own socket, so the seam the
## carve joined stays joined on the page.
##
## The cells hang a limb off the flank — the socket the lattice states — but the
## ledger poses the limb patch from the girdle's own point on the spine, so a
## limb posed through its patch alone lands a flank's width inboard of the trunk
## cells it canonically touches, and from the side the leg floats free of the
## body. So the limb's station origins are shifted by exactly the disagreement —
## the posed socket less the posed girdle point — full at the shoulder and gone
## by the ankle, which puts the top of the leg in the trunk's own flank while the
## foot stays on the ground the gait put it on. Pose only: no cell moves in the
## census, and the ledger underneath is untouched.
func _close_seams() -> void:
	var patches: int = AnatomyLattice.PATCH_KEYS.size()
	if _seam_page.size() != patches:
		_seam_page.resize(patches)
		_seam_deep.resize(patches)
	_seam_page.fill(Vector2.ZERO)
	_seam_deep.fill(0.0)
	var lat: AnatomyLattice = lattice()
	if lat == null or lat.socket_station.size() != patches:
		return
	if _af_o.is_empty() or _af_o[0] == null:
		return
	var bo: PackedVector2Array = _af_o[0]
	var bs: PackedVector2Array = _af_s[0]
	var bl: PackedVector2Array = _af_l[0]
	var bod: PackedFloat32Array = _dp_o[0]
	var bsd: PackedFloat32Array = _dp_s[0]
	var bld: PackedFloat32Array = _dp_l[0]
	for pk in range(1, patches):
		if _af_o[pk] == null:
			continue
		# The socket, posed through the trunk's own affine.
		var st: float = clampf(lat.socket_station[pk], 0.0, float(bo.size() - 1))
		var c: int = mini(int(st), bo.size() - 1)
		var f: float = st - float(c)
		var side: float = lat.socket_lat[pk]
		var up: float = lat.socket_lift[pk]
		var page: Vector2 = bo[c] + bs[c] * f + bl[c] * side + _af_h * up
		var deep: float = bod[c] + bsd[c] * f + bld[c] * side + _dp_h * up
		# Locals, modified, written back: a packed array read out of an Array is
		# a copy of it.
		var o: PackedVector2Array = _af_o[pk]
		var s: PackedVector2Array = _af_s[pk]
		var od: PackedFloat32Array = _dp_o[pk]
		var sd: PackedFloat32Array = _dp_s[pk]
		var shift: Vector2 = page - o[0]
		var shift_d: float = deep - od[0]
		_seam_page[pk] = shift
		_seam_deep[pk] = shift_d
		for k in o.size():
			var fade: float = _seam_fade(float(k))
			var ahead: float = _seam_fade(float(mini(k + 1, o.size() - 1)))
			o[k] += shift * fade
			od[k] += shift_d * fade
			s[k] += shift * (ahead - fade)
			sd[k] += shift_d * (ahead - fade)
		_af_o[pk] = o
		_af_s[pk] = s
		_dp_o[pk] = od
		_dp_s[pk] = sd


## How much of the seam shift a limb station carries: all of it at the girdle,
## none from the ankle down, so the shoulder meets the flank and the foot stays
## put.
static func _seam_fade(station: float) -> float:
	return clampf(1.0 - station / float(BodyPlan.LIMB_BONE_COLS), 0.0, 1.0)


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
	# The two supply networks are overlays rather than layers of the depth stack,
	# and that is a statement about what they are. Skin, fat, muscle and bone are
	# things the animal is built out of, so they stand in front of each other and
	# the one on top is the one that is seen. A vascular tree is not a layer of
	# anything: it threads all four of them, and the question it answers — where
	# does the blood go, what is still reaching this leg — is worth asking of an
	# animal with its hide on. So a network draws wherever its own row is lit,
	# over the top of whatever the stack has settled on, complete from the trunk
	# to the branchlets, and the flesh goes on occluding itself underneath it.
	if show_vessels:
		_draw_network(grid, state.plan.vessels, state.vessels, COL_VESSEL, 3, 46.0, true,
			VESSEL_OFFSET)
		_draw_branches(lat, state.vessels, TissueForm.VESSELS, COL_VESSEL)
	if show_nerves:
		_draw_network(grid, state.plan.nerves, state.nerves, COL_NERVE, 2, 150.0, false, 0.0)
		_draw_branches(lat, state.nerves, TissueForm.NERVES, COL_NERVE)
	if show_vessels:
		_draw_organ_link(lat, BodyPlan.HEART, AnatomyLattice.PART_AORTA, COL_VESSEL)
		_draw_organ(grid, lat, BodyPlan.HEART, COL_VESSEL, "HEART", true)
	if show_nerves:
		_draw_organ_link(lat, BodyPlan.BRAIN, AnatomyLattice.PART_CORD, COL_NERVE)
		_draw_organ(grid, lat, BodyPlan.BRAIN, COL_NERVE, "BRAIN", false)
	_draw_axes()
	_draw_hover(lat)


## A guide to how the specimen is lying: the animal's own three axes — down the
## body, across it, and up out of its back — put through the very same projection
## the flesh is, so the guide turns with the body rather than describing it.
##
## The foreshortening is left in, and it is the whole point of drawing this
## rather than printing the two angles again: an arm pointing at the eye is a
## stub, and a stub is the one reading that says the specimen is being looked at
## down its own length. The letters are the lattice's own axes, so a cell named
## in the readout below can be found on the body above.
func _draw_axes() -> void:
	if _af_o.is_empty() or _af_o[0] == null or _scale <= 0.0:
		return
	var frame: PackedVector2Array = _af_o[0]
	if frame.is_empty():
		return
	# The middle of the trunk: one station of a bent animal is as good as
	# another for saying which way it is turned, and the middle is the one that
	# is never a neck or a tail tip.
	var mid: int = frame.size() / 2
	var at := Vector2(size.x - AXIS_INSET, size.y - AXIS_INSET)
	draw_arc(at, AXIS_ARM + 4.0, 0.0, TAU, 22, Color(INK, 0.09), 0.7, true)
	var arms: Array = [
		[(_af_f[0] as PackedVector2Array)[mid], (_dp_f[0] as PackedFloat32Array)[mid], "X"],
		[(_af_l[0] as PackedVector2Array)[mid], (_dp_l[0] as PackedFloat32Array)[mid], "Y"],
		[_af_h, _dp_h, "Z"],
	]
	for arm in arms:
		# Back out of the page scale: these are the unit axes already projected,
		# so dividing by it leaves exactly how much of each one the eye can see.
		var page: Vector2 = (arm[0] as Vector2) / _scale * AXIS_ARM
		var toward: bool = float(arm[1]) >= 0.0
		var ink := Color(INK, 0.55 if toward else 0.22)
		draw_line(at, at + page, ink, 1.0, true)
		var reach: float = page.length()
		if _mono == null or reach < AXIS_FAINT * AXIS_ARM:
			continue
		var text: String = str(arm[2])
		var wide: float = _mono.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
		var tip: Vector2 = at + page * (1.0 + 6.0 / reach)
		draw_string(_mono, tip - Vector2(wide * 0.5, -3.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, ink)


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
	# Twice the samples because a bone segment lays its rim as a quad of its own,
	# and three per loose cell because a box turned to the eye shows three faces.
	var room: int = faces + _form.sample_total * 2 + _loose_shown() * 3
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
	var sheath: PackedByteArray = lat.sheathed
	var organs: PackedByteArray = lat.organ_of
	var skinned: bool = tissue_shown(AnatomyLattice.SKIN) \
		and sheath.size() == lat.count
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
		# The tissue this facet is *seen* as, which on anything the lattice cannot
		# layer is the sheath rather than what is under it — see `_seen_as`.
		var t: int = AnatomyLattice.SKIN if skinned and sheath[cell] != 0 \
			else int(kinds[cell])
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
		# A named organ is inked as the system it belongs to — the brain in the
		# nerves' blue, the heart in the vessels' red — off the bank's two organ
		# rows; the wear still reads the organ layer it actually is.
		var shade_t: int = t
		if t == AnatomyLattice.ORGAN:
			shade_t = SHADE_BRAIN if organs[cell] == BodyPlan.BRAIN else SHADE_HEART
		var ink: Color = _shade[((shade_t * 2 + (0 if front else 1)) * SHADES) + band]
		# What is happening to this flesh, in the order it matters: what the
		# ledger has worn away, whether the facet stands on an open wound, and
		# what the region as a whole is doing.
		var wp = worn[patch_of[cell]]
		if wp != null:
			ink = _worn(lat, grid, wp, cell, ink, t, shade_t)
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
	n = _loose_pass(lat, n, true)
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
		_draw_facet_edges(lat, mesh_faces)
		if show_lattice:
			_draw_census(lat, mesh_faces)


## The hairline along each facet's own edges — what tells one plane from the next
## where two of them happen to catch the light alike. Only the facets turned
## toward the eye are outlined: the far half of the body is behind the near half
## and lining it would be drawing through the animal.
##
## Bone facets — the skull, mostly — take a darker line than the rest: the
## skeleton is the palest thing on the slab, its planes land on near-identical
## shades, and the stronger edge is what the chain tubes get from their own rim.
## A sheathed bone being worn as hide keeps the ordinary line; it is skin to the
## eye.
func _draw_facet_edges(lat: AnatomyLattice, faces: int) -> void:
	_edge_lines.resize(0)
	_bone_edge_lines.resize(0)
	var kinds: PackedByteArray = lat.kind
	var sheath: PackedByteArray = lat.sheathed
	var skinned: bool = tissue_shown(AnatomyLattice.SKIN) \
		and sheath.size() == lat.count
	for j in faces:
		if _shown_front[j] == 0:
			continue
		var cell: int = _shown[j]
		var bony: bool = kinds[cell] == AnatomyLattice.BONE \
			and not (skinned and sheath[cell] != 0)
		var v: int = j * 4
		var p0: Vector2 = _points[v]
		var p1: Vector2 = _points[v + 1]
		var p2: Vector2 = _points[v + 2]
		var p3: Vector2 = _points[v + 3]
		if bony:
			_bone_edge_lines.append(p0)
			_bone_edge_lines.append(p1)
			_bone_edge_lines.append(p1)
			_bone_edge_lines.append(p2)
			if p2 != p3:
				_bone_edge_lines.append(p2)
				_bone_edge_lines.append(p3)
			_bone_edge_lines.append(p3)
			_bone_edge_lines.append(p0)
		else:
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
	if _bone_edge_lines.size() >= 2:
		draw_multiline(_bone_edge_lines, BONE_EDGE, 0.6, true)


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
		# A network's own trunks ride over the flesh rather than through the
		# sort, because they are overlays and the whole of what an overlay means
		# here is "in front of whatever the depth stack settled on". Lifted by
		# the animal's own radius, so the lift cannot be confused with a depth on
		# a bigger creature and the tubes still sort correctly among themselves.
		var lift: float = _radius * 8.0 if t == AnatomyLattice.NERVE \
			or t == AnatomyLattice.VESSEL else 0.0
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
		# Whether the sample before this one is still waiting to be joined to
		# something. A chain with one sample in it — a lizard's whole femur is
		# two cells — and the far side of a gap the carve left are both real
		# pieces of the animal, and a rule that only draws what it can join to
		# something else is a rule that leaves them off the slab.
		var prev_lone: bool = false
		for s in range(form.chain_from[c], form.chain_from[c + 1]):
			# Four ways a sample is not on the specimen — nothing has opened the
			# way in to it, the section plane has carved past it, the teeth have
			# taken more than half of what it stands for, or its patch is not
			# posed — and one thing to do about any of them: the run stops here,
			# and whatever it was carrying is left as the piece it is.
			var pk: int = int(form.s_patch[s])
			var gone_frac: float = form.sample_gone(lat, s)
			var shown: bool = _sample_vis[s] != 0 \
				and not (sliced and form.s_canon[s][slice_axis] > plane) \
				and gone_frac < TissueForm.BREAK_SHARE \
				and pk < _af_o.size() and _af_o[pk] != null
			if not shown:
				if prev_lone:
					n = _tube_dot(prev_page, prev_r, t, base_band, prev_worn,
						prev_deep + lift, form.s_rep[prev], n, drawing)
				prev = -1
				prev_lone = false
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
			var joined: bool = prev >= 0 and form.s_bucket[s] - prev_bucket <= tol
			var span: float = page.distance_to(prev_page) if joined else 0.0
			if joined and span > 0.0001:
				var dir: Vector2 = (page - prev_page) / span
				var nrm := Vector2(-dir.y, dir.x)
				# Reached a little past both ends, so consecutive segments close
				# their elbows on a curved run.
				var ext: Vector2 = dir * minf(prev_r, span * 0.3)
				var v: int = n * 4
				_points[v] = prev_page - ext - nrm * prev_r
				_points[v + 1] = prev_page - ext + nrm * prev_r
				_points[v + 2] = page + ext + nrm * r
				_points[v + 3] = page + ext - nrm * r
				if drawing:
					var band: int = base_band
					if t == AnatomyLattice.BONE:
						band += TUBE_SEG if (form.s_bucket[s] & 1) == 0 else -TUBE_SEG
					var ink: Color = _tube_ink(t, band, maxf(gone_frac, prev_worn))
					_colors[v] = ink
					_colors[v + 1] = ink
					_colors[v + 2] = ink
					_colors[v + 3] = ink
					_depths[n] = Vector2((deep + prev_deep) * 0.5 + lift, float(n))
				_cell_page[n] = page
				_cell_deep[n] = deep
				_shown[n] = form.s_rep[s]
				# Not a facet of the mesh: the hover marks the cell rather than
				# outlining a polygon, and no hairline is drawn round a tube.
				_shown_face[n] = -1
				_shown_front[n] = 0
				n += 1
				if t == AnatomyLattice.BONE:
					n = _bone_rim(prev_page - ext, page + ext, nrm, prev_r, r,
						(deep + prev_deep) * 0.5 + lift, form.s_rep[s], n, drawing)
			elif prev_lone:
				n = _tube_dot(prev_page, prev_r, t, base_band, prev_worn,
					prev_deep + lift, form.s_rep[prev], n, drawing)
			prev = s
			prev_lone = not joined
			prev_bucket = form.s_bucket[s]
			prev_page = page
			prev_deep = deep
			prev_r = r
			prev_worn = gone_frac
		if prev_lone:
			n = _tube_dot(prev_page, prev_r, t, base_band, prev_worn,
				prev_deep + lift, form.s_rep[prev], n, drawing)
	return n


## What a stretch of a continuous structure is inked: the tissue's own shade at
## the band its material sits in, dragged toward the spent shade by whatever the
## teeth have taken out of it.
##
## The bank holds two sides per tissue — see `_bake_shades` — and a tube is
## always its own near face, so it reads the front half of the pair. Without that
## stride a bone came out inked as fat and a vessel as bone.
func _tube_ink(t: int, band: int, wear: float) -> Color:
	var ink: Color = _shade[(t * 2) * SHADES + clampi(band, 0, SHADES - 1)]
	if wear <= 0.0:
		return ink
	return ink.lerp(TISSUE_WORN[t], wear / TissueForm.BREAK_SHARE * 0.85)


## The dark rim one stretch of bone carries: the same quad as the tube it backs,
## grown by the rim's width at both ends and both sides, sorted just behind its
## own bone — so what shows of it is an outline, and one bone-coloured element
## reads as its own piece against the next. Subtle by construction: the rim is
## under a pixel wide everywhere the bone itself is drawn.
func _bone_rim(a: Vector2, b: Vector2, nrm: Vector2, ra: float, rb: float,
		deep: float, rep: int, n: int, drawing: bool) -> int:
	var dir: Vector2 = b - a
	var span: float = dir.length()
	dir = dir / span if span > 0.0001 else Vector2.RIGHT
	var ea: Vector2 = a - dir * BONE_RIM
	var eb: Vector2 = b + dir * BONE_RIM
	var v: int = n * 4
	_points[v] = ea - nrm * (ra + BONE_RIM)
	_points[v + 1] = ea + nrm * (ra + BONE_RIM)
	_points[v + 2] = eb + nrm * (rb + BONE_RIM)
	_points[v + 3] = eb - nrm * (rb + BONE_RIM)
	if drawing:
		_colors[v] = COL_BONE_RIM
		_colors[v + 1] = COL_BONE_RIM
		_colors[v + 2] = COL_BONE_RIM
		_colors[v + 3] = COL_BONE_RIM
		_depths[n] = Vector2(deep - BONE_RIM_BACK, float(n))
	_cell_page[n] = (ea + eb) * 0.5
	_cell_deep[n] = deep - BONE_RIM_BACK
	_shown[n] = rep
	_shown_face[n] = -1
	_shown_front[n] = 0
	return n + 1


## A sample of a chain that no segment reached: a one-sample structure, or the
## last piece before a gap. Laid as the block of solid it stands for, so a
## skeleton the lattice only has scraps of is still drawn as those scraps rather
## than as nothing at all. Bone lays its rim behind itself here too, so a lone
## carpal is outlined exactly as a whole femur is.
func _tube_dot(at: Vector2, r: float, t: int, band: int, wear: float, deep: float,
		rep: int, n: int, drawing: bool) -> int:
	if t == AnatomyLattice.BONE:
		var e: float = r + BONE_RIM
		var v0: int = n * 4
		_points[v0] = at + Vector2(-e, -e)
		_points[v0 + 1] = at + Vector2(e, -e)
		_points[v0 + 2] = at + Vector2(e, e)
		_points[v0 + 3] = at + Vector2(-e, e)
		if drawing:
			_colors[v0] = COL_BONE_RIM
			_colors[v0 + 1] = COL_BONE_RIM
			_colors[v0 + 2] = COL_BONE_RIM
			_colors[v0 + 3] = COL_BONE_RIM
			_depths[n] = Vector2(deep - BONE_RIM_BACK, float(n))
		_cell_page[n] = at
		_cell_deep[n] = deep - BONE_RIM_BACK
		_shown[n] = rep
		_shown_face[n] = -1
		_shown_front[n] = 0
		n += 1
	var v: int = n * 4
	_points[v] = at + Vector2(-r, -r)
	_points[v + 1] = at + Vector2(r, -r)
	_points[v + 2] = at + Vector2(r, r)
	_points[v + 3] = at + Vector2(-r, r)
	if drawing:
		# Asked for here rather than by the caller: the shade bank is baked by the
		# drawing pass, and a placement pass has no business reading it.
		var ink: Color = _tube_ink(t, band, wear)
		_colors[v] = ink
		_colors[v + 1] = ink
		_colors[v + 2] = ink
		_colors[v + 3] = ink
		_depths[n] = Vector2(deep, float(n))
	_cell_page[n] = at
	_cell_deep[n] = deep
	_shown[n] = rep
	_shown_face[n] = -1
	_shown_front[n] = 0
	return n + 1


## The flesh the ring skin could not make a surface of, drawn cell by cell.
##
## A ring needs most of its sectors before it can be closed into a hoop, and a
## place where the animal is two cells wide has not got them — a tail's last
## slice, the fat on a lean lizard, a stray shred of muscle beside a girdle. The
## old rule dropped those cells, and dropping them is why a tissue on its own
## came up full of holes: what was missing from the picture was not missing from
## the animal.
##
## So whatever is left over is drawn as what it is: a box of tissue, posed as a
## box. The cell's three half-edges go through its station's own affine and the
## three faces turned toward the eye are laid as facets, each lit by its own
## plane exactly as the mesh's are — so a loose cell is a small piece of the
## same low-poly solid as the surface beside it, turning with the specimen,
## rather than the flat screen-aligned square that used to read as a stray
## pixel. It carries its tissue's ink and its region's wash like any facet, it
## sorts with them, and it answers the pointer like them.
func _loose_pass(lat: AnatomyLattice, n: int, drawing: bool) -> int:
	var cells: PackedInt32Array = _mesh.loose
	var total: int = cells.size()
	if total == 0:
		return n
	# A body can in principle be nearly all fringe — a filter that leaves one
	# scattered tissue on a big animal — so the pass is bounded and thins itself
	# rather than growing without limit. It is the fringe: thinning it drops
	# detail from the places that had least of it to begin with.
	var step: int = _loose_step()
	var half: float = AnatomyLattice.CELL * 0.5
	# Blown up where the page cell is too small to survive as its own mark.
	var grow: float = maxf(1.0, LOOSE_MIN / maxf(AnatomyLattice.CELL * _scale * 0.5, 0.0001))
	var kinds: PackedByteArray = lat.kind
	var regions: PackedByteArray = lat.region
	var sheath: PackedByteArray = lat.sheathed
	var organs: PackedByteArray = lat.organ_of
	var skinned: bool = tissue_shown(AnatomyLattice.SKIN) \
		and sheath.size() == lat.count
	var i: int = 0
	while i < total:
		var cell: int = cells[i]
		i += step
		if lat.gone[cell] != 0:
			continue
		var pk: int = lat.patch_of[cell]
		if pk >= _af_o.size() or _af_o[pk] == null:
			continue
		var at: Vector3 = _cell_at(lat, cell)
		var mid := Vector2(at.x, at.y)
		var o: PackedVector2Array = _af_o[pk]
		var c: int = mini(int(clampf(lat.station[cell], 0.0, float(o.size() - 1))),
			o.size() - 1)
		# The box's three half-edges: along the patch, across it, and up, each
		# already on the page with its own share of depth.
		var ex: Vector2 = (_af_f[pk] as PackedVector2Array)[c] * (half * grow)
		var ey: Vector2 = (_af_l[pk] as PackedVector2Array)[c] * (half * grow)
		var ez: Vector2 = _af_h * (half * grow)
		var dx: float = (_dp_f[pk] as PackedFloat32Array)[c] * half
		var dy: float = (_dp_l[pk] as PackedFloat32Array)[c] * half
		var dz: float = _dp_h * half
		var reg: int = regions[cell]
		# The shade row this cell is inked from: the sheath while the skin is on,
		# a named organ as its own system's colour, the tissue itself otherwise.
		var shade_t: int = AnatomyLattice.SKIN if skinned and sheath[cell] != 0 \
			else int(kinds[cell])
		if shade_t == AnatomyLattice.ORGAN:
			shade_t = SHADE_BRAIN if organs[cell] == BodyPlan.BRAIN else SHADE_HEART
		# The three faces turned toward the eye. The corners go down either way:
		# the pointer is tested against the very quads that were laid, and a
		# hover arriving before the specimen has been painted has to be tested
		# against something real too.
		for m in 3:
			var p: Vector2
			var dp: float
			var q: Vector2
			var r: Vector2
			match m:
				0:
					p = ex
					dp = dx
					q = ey
					r = ez
				1:
					p = ey
					dp = dy
					q = ez
					r = ex
				_:
					p = ez
					dp = dz
					q = ex
					r = ey
			if dp < 0.0:
				p = -p
				dp = -dp
			var face: Vector2 = mid + p
			var v: int = n * 4
			_points[v] = face + q + r
			_points[v + 1] = face + q - r
			_points[v + 2] = face - q - r
			_points[v + 3] = face - q + r
			if drawing:
				# Lit by the face's own plane — its normal is the half-edge that
				# points out of it.
				var nz: float = dp * _scale
				var span: float = sqrt(p.x * p.x + p.y * p.y + nz * nz)
				var lam: float = 0.0 if span < 0.000001 \
					else maxf((p.x * LIGHT.x + p.y * LIGHT.y + nz * LIGHT.z) / span, 0.0)
				var lit: Color = _shade[(shade_t * 2) * SHADES
					+ clampi(int(lam * float(SHADES)), 0, SHADES - 1)]
				if _wash_amt[reg] > 0.0:
					lit = lit.lerp(_wash_col[reg], _wash_amt[reg])
				if xray:
					lit.a = XRAY_ALPHA
				_colors[v] = lit
				_colors[v + 1] = lit
				_colors[v + 2] = lit
				_colors[v + 3] = lit
				_depths[n] = Vector2(at.z, float(n))
			_reach_over(mid, _points[v], _points[v + 1], _points[v + 2], _points[v + 3])
			_cell_page[n] = mid
			_cell_deep[n] = at.z
			_shown[n] = cell
			# Not a facet of the mesh: the hover marks the cell itself, and no
			# hairline is drawn round a box.
			_shown_face[n] = -1
			_shown_front[n] = 0
			n += 1
	return n


## Every how-many-th loose cell the pass keeps, and how many that leaves — which
## is what the buffers have to have room for. Both answers come off the one
## division, so the count and the walk can never disagree.
func _loose_step() -> int:
	return maxi(1, int(ceil(float(_mesh.loose.size()) / float(LOOSE_MOST))))


func _loose_shown() -> int:
	var total: int = _mesh.loose.size()
	if total == 0:
		return 0
	var step: int = _loose_step()
	return (total + step - 1) / step


## Places every facet on the page without drawing it, for a hover test arriving
## before the specimen has been painted — which is every hover in a headless run,
## and the first one after a filter changes. The drawing pass does the same
## placement inline as part of the work it is already doing, so this is never run
## in the ordinary way of things.
func _place_marks(lat: AnatomyLattice) -> void:
	var faces: int = _mesh.count
	var room: int = faces + _form.sample_total * 2 + _loose_shown() * 3
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
	n = _loose_pass(lat, n, false)
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
	# about the light — so it is the only thing the key has to carry. Read off
	# the heart rather than off a flag: the specimen and the panel beside it are
	# describing one body and there is one place either of them asks.
	var dead: bool = is_instance_valid(creature) and creature.anatomy != null \
		and creature.anatomy.state.arrested
	var key: int = hash([dead])
	var want: int = SHADE_KINDS * 2 * SHADES
	if key == _shade_key and _shade.size() == want:
		return
	_shade_key = key
	if _shade.size() != want:
		_shade.resize(want)
	for t in SHADE_KINDS:
		var base: Color = TISSUE_INK[t]
		if dead:
			base = base.lerp(TISSUE_WORN[t], DEAD_DRAIN)
		var shade: Color = _scaled(base, FACET_FLOOR)
		var lit: Color = _scaled(base, FACET_FLOOR + FACET_GAIN)
		# A tissue inked at the black end of the page cannot be lit by scaling —
		# nothing times a gain is still nothing — so it is carried toward a sheen
		# instead. Which is the whole of how a black hide is a solid with planes
		# on it rather than a hole cut in the paper. Every other tissue lands on
		# exactly the ramp it always had: the lerp between these two *is* the
		# scale, written as its own two ends.
		if lit.get_luminance() < SHEEN_UNDER:
			lit = base.lerp(SHEEN, SHEEN_LIFT)
		for side in 2:
			# A facet turned away from the eye is the far wall of a crater or the
			# inside of an opened body, and is seen in that flesh's own shadow.
			var dim: float = FACET_BACK if side == 1 else 1.0
			for k in SHADES:
				var lam: float = (float(k) + 0.5) / float(SHADES)
				_shade[(t * 2 + side) * SHADES + k] = _scaled(shade.lerp(lit, lam), dim)


static func _scaled(ink: Color, by: float) -> Color:
	return Color(minf(ink.r * by, 1.0), minf(ink.g * by, 1.0), minf(ink.b * by, 1.0))


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
## been bitten — see the `worn` gate in the cell pass. `shade_t` is the palette
## row the cell is being inked from, which on a named organ is not the tissue
## the wear is read off.
func _worn(lat: AnatomyLattice, grid: TissueGrid, p: TissueGrid.Patch, i: int,
		ink: Color, t: int, shade_t: int = -1) -> Color:
	if t > AnatomyLattice.ORGAN:
		return ink
	var cell: int = lat.cell_of[i]
	if p.touched[cell] == 0:
		return ink
	var full: float = _layer_full(grid, p, cell, t)
	if full <= 0.0:
		return ink
	return ink.lerp(TISSUE_WORN[shade_t if shade_t >= 0 else t],
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
## sound run still fades out behind a cut upstream of it.
##
## Every run of the tree is drawn, trunk included. A network is only a network
## because it is joined up: a limb's run drawn without the body run that feeds it
## is four strokes lying near an animal, and the reading it exists to give — this
## leg is behind that cut — cannot be seen in it at all.
func _draw_network(grid: TissueGrid, runs: Array[BodyPlan.Conduit],
		network: AnatomyNetwork, tint: Color, pulses: int, speed: float,
		beat: bool, offset: float) -> void:
	for run in runs:
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
## it, started at the point where it actually meets that feeder, and smoothed.
func _gather_run(grid: TissueGrid, runs: Array[BodyPlan.Conduit],
		run: BodyPlan.Conduit, offset: float) -> void:
	var p: TissueGrid.Patch = grid.patch(run.patch_key)
	var count: int = run.cells.size()
	_run.resize(count)
	_run_gone.resize(count)
	# A limb's run rides the same seam shift its flesh does — see `_close_seams` —
	# or the vessel dives for the girdle point while the leg it feeds stands at
	# the flank.
	var pk: int = AnatomyLattice.PATCH_KEYS.find(run.patch_key)
	var seam: Vector2 = _seam_page[pk] if pk > 0 and pk < _seam_page.size() \
		else Vector2.ZERO
	for i in count:
		_run[i] = project(p.centre_of(run.cells[i]), p.height_of(run.cells[i]))
		if seam != Vector2.ZERO:
			_run[i] += seam * _seam_fade(float(run.cells[i] / BodyPlan.LIMB_ROWS))
		_run_gone[i] = p.gone[run.cells[i]]
	# Stepped aside before any reversal below, so which flank the vessel lies on
	# is a fact about the body rather than about which way the blood is going.
	if absf(offset) > 0.001 and count > 1:
		for i in count:
			var span: Vector2 = _run[mini(i + 1, count - 1)] - _run[maxi(i - 1, 0)]
			if span.length_squared() > 0.000001:
				_run[i] += Vector2(-span.y, span.x).normalized() * offset
	if run.parent >= 0:
		_join_upstream(grid, runs[run.parent])
	_smooth_run()


## Turns this run to flow away from the one that feeds it, and starts it *on*
## that run.
##
## The junction is the nearest point of the feeder rather than wherever its own
## cell list happens to end, because the two runs are laid through different
## patches and a limb's artery leaves the trunk at the shoulder rather than at
## the tail. Without this the tree is drawn as a set of separate strokes with
## gaps between them, and a gap in a supply network is the one thing on this
## panel that already means something else.
func _join_upstream(grid: TissueGrid, upstream: BodyPlan.Conduit) -> void:
	var feeder: TissueGrid.Patch = grid.patch(upstream.patch_key)
	if feeder == null or not feeder.live or upstream.cells.is_empty():
		return
	var last: int = _run.size() - 1
	var head: Vector2 = _run[0]
	var tail: Vector2 = _run[last]
	var joint: Vector2 = head
	var joint_gone: int = 0
	var nearest: float = INF
	for cell in upstream.cells:
		var at: Vector2 = project(feeder.centre_of(cell), feeder.height_of(cell))
		var span: float = minf(at.distance_squared_to(head), at.distance_squared_to(tail))
		if span >= nearest:
			continue
		nearest = span
		joint = at
		joint_gone = feeder.gone[cell]
	if joint.distance_squared_to(tail) < joint.distance_squared_to(head):
		_run.reverse()
		_run_gone.reverse()
	_run.insert(0, joint)
	_run_gone.insert(0, joint_gone)


## The same run as a curve.
##
## A conduit is drawn between the middles of the ledger cells it threads, and
## those are a staircase: a run of right angles at the resolution of the grid,
## which reads as a picture of the grid rather than of a vessel. Catmull-Rom
## through the very same points says the same thing with the corners taken off —
## no point is moved, none is invented between two that are not neighbours, and
## the pulses ride the smoothed path because after this it is the only path.
func _smooth_run() -> void:
	var n: int = _run.size()
	if n < 3:
		return
	_curve.resize(0)
	_curve_gone.resize(0)
	for i in range(n - 1):
		var p0: Vector2 = _run[maxi(i - 1, 0)]
		var p1: Vector2 = _run[i]
		var p2: Vector2 = _run[i + 1]
		var p3: Vector2 = _run[mini(i + 2, n - 1)]
		# A span either end of which the teeth have been through is a broken
		# span, however smooth the line across it.
		var gone: int = 1 if _run_gone[i] != 0 or _run_gone[i + 1] != 0 else 0
		for k in SMOOTH_STEPS:
			_curve.append(_spline(p0, p1, p2, p3, float(k) / float(SMOOTH_STEPS)))
			_curve_gone.append(gone)
	_curve.append(_run[n - 1])
	_curve_gone.append(_run_gone[n - 1])
	_run = _curve.duplicate()
	_run_gone = _curve_gone.duplicate()


## One point of a Catmull-Rom spline through p1 and p2.
static func _spline(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (p2 - p0) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (3.0 * p1 - 3.0 * p2 + p3 - p0) * t3)


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
## marks, so the tree bends with the flesh it supplies. Two rules keep it a tree
## rather than a scatter of twigs, and both are about what a *branch* is:
##
##   * It is drawn from where it starts, and it stops where the teeth have been
##     through it. A vertex whose cell is gone ends the branch — it does not skip
##     the hole and carry on, because what would carry on is a piece of vessel
##     joined to nothing.
##   * It is only drawn if the branch it grew out of was, all the way back to a
##     named run. Which is the same statement one level up, and between them
##     nothing on the specimen is a floating segment.
##
## The tissue filters are not among the rules. These are overlays: a supply tree
## is a thing threading the animal rather than a layer of it, and asking to see
## the vessels of a body with its hide on is a fair question.
func _draw_branches(lat: AnatomyLattice, network: AnatomyNetwork, net: int,
		tint: Color) -> void:
	var paths: Array = _form.branches[net]
	if paths.is_empty():
		return
	var owner: PackedInt32Array = _form.branch_region[net]
	var stem: PackedInt32Array = _form.branch_parent[net]
	var field: PackedFloat32Array = _form.density[net]
	if field.size() < BodyPlan.REGIONS or stem.size() != paths.size():
		return
	var sliced: bool = slice_axis >= 0
	var plane: float = slice_plane()
	var drawn := PackedByteArray()
	drawn.resize(paths.size())
	for reg in BodyPlan.REGIONS:
		_branch_lines.resize(0)
		for b in paths.size():
			if owner[b] != reg or (stem[b] >= 0 and drawn[stem[b]] == 0):
				continue
			var path: PackedInt32Array = paths[b]
			_path.resize(0)
			for idx in path:
				if lat.gone[idx] != 0 \
						or (sliced and lat.pos[idx][slice_axis] > plane):
					break
				var at: Vector3 = _cell_at(lat, idx)
				_path.append(Vector2(at.x, at.y))
			if _path.size() < 2:
				continue
			drawn[b] = 1
			_smooth_branch()
		if _branch_lines.size() < 2:
			continue
		var reach: float = clampf(network.delivery[reg], 0.0, 1.0)
		var alpha: float = (0.10 + 0.42 * reach) * (0.45 + 0.55 * field[reg])
		draw_multiline(_branch_lines, Color(tint, alpha), BRANCH_WIDTH, true)


## The branch standing in `_path`, as a curve, into the multiline buffer. Cell to
## cell over a lattice is a staircase of right angles — see `_smooth_run`, which
## does the same thing to the named runs and for the same reason.
func _smooth_branch() -> void:
	var n: int = _path.size()
	if n < 3:
		_branch_lines.append(_path[0])
		_branch_lines.append(_path[n - 1])
		return
	var at: Vector2 = _path[0]
	for i in range(n - 1):
		var p0: Vector2 = _path[maxi(i - 1, 0)]
		var p1: Vector2 = _path[i]
		var p2: Vector2 = _path[i + 1]
		var p3: Vector2 = _path[mini(i + 2, n - 1)]
		for k in range(1, SMOOTH_STEPS + 1):
			var to: Vector2 = _spline(p0, p1, p2, p3, float(k) / float(SMOOTH_STEPS))
			_branch_lines.append(at)
			_branch_lines.append(to)
			at = to


# ---------------------------------------------------------------- organs ----

## The stroke that joins a named organ to its own system: the heart to the
## aorta while the vessels are up, the brain to the spinal cord while the
## nerves are. Both ends are real cells — the organ's cell nearest the run, and
## the run's own nearest sample — posed through the same affines as everything
## else, so the join bends with the body and an organ the teeth have emptied
## has nothing to join from and draws nothing.
##
## Mostly the two already touch — the cord's forward end rises into the
## brainstem, the aorta leaves the heart's own column — and then the stroke is
## a few pixels long and disappears into the anatomy. It is drawn anyway
## because nothing guarantees the contact on a procedurally built body, and an
## organ floating beside its own supply line is the one reading this overlay
## must never give.
func _draw_organ_link(lat: AnatomyLattice, which: int, part: int, tint: Color) -> void:
	var mine: PackedInt32Array = lat.organ_cells(which)
	if mine.is_empty() or _form.sample_total == 0:
		return
	var centre := Vector3.ZERO
	var alive: int = 0
	for i in mine:
		if lat.gone[i] == 0:
			centre += lat.pos[i]
			alive += 1
	if alive == 0:
		return
	centre /= float(alive)
	var best: int = -1
	var nearest: float = INF
	for c in _form.chain_count:
		if int(_form.chain_part[c]) != part:
			continue
		for s in range(_form.chain_from[c], _form.chain_from[c + 1]):
			var d: float = (_form.s_canon[s] - centre).length_squared()
			if d < nearest:
				nearest = d
				best = s
	if best < 0:
		return
	var goal: Vector3 = _form.s_canon[best]
	var from: int = -1
	var near: float = INF
	for i in mine:
		if lat.gone[i] != 0:
			continue
		var d: float = (lat.pos[i] - goal).length_squared()
		if d < near:
			near = d
			from = i
	var a: Vector3 = _cell_at(lat, from)
	var b: Vector3 = _cell_at(lat, _form.s_rep[best])
	draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), Color(tint, 0.45), 1.6, true)


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
	# A heart beats while it is beating. The ring on a stopped one holds still —
	# read off the circulation rather than off anything about the creature, so it
	# is the same reading the panel prints STOPPED from.
	if beat and creature.anatomy.state.circulation > BodyState.COLLAPSE:
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
	# The wheel over the stage leans in on the specimen. Taken here rather than
	# on the drawer, so it is the thing under the pointer that answers — and
	# accepted either way, because a wheel that scrolls the panel out from under
	# the animal while the animal is being read is the wrong thing entirely.
	if click != null and click.pressed and (click.button_index == MOUSE_BUTTON_WHEEL_UP
			or click.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		set_zoom(zoom * (ZOOM_STEP if click.button_index == MOUSE_BUTTON_WHEEL_UP
			else 1.0 / ZOOM_STEP))
		accept_event()
		return
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
