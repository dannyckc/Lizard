## Draws the creature. Purely a consumer — it reads the solved state and never
## writes to it, so the simulation can be run headless or drawn differently
## without touching a line of the systems above.
##
## Draw order: limbs -> body -> feet -> debug overlay, so the legs read as being
## underneath the torso the way they do from above. Each structure's shadows go
## down immediately before it rather than in one pass up front, because both are
## the same mesh — see _build.
##
## The creature is drawn *as* its tissue lattice, not as a silhouette with the
## damage painted over it. That is the whole reason a wound can read as a hole:
## a cell with nothing left in it is simply not emitted, so the world behind it
## shows through by omission. The alternative — filling the silhouette and then
## stamping destroyed cells in the ground colour — cannot be made to work
## however carefully the colour is matched, because it is still ink on the
## canvas: it hides whatever is behind the creature, it never lines up over a
## second creature or a scrap, and nothing about the body's collision or hit
## testing knows the tissue is missing.
class_name CreatureView
extends Node2D

@export var debug: bool = false
## Canvas order is part of perception presentation: ambient creatures belong to
## the habitat below SightRenderer, while the controlled creature stays crisp
## above it. The view remains otherwise identical and simulation-independent.
@export var render_z_index: int = 10

const INK := Color("14140f")
const PAPER := Color("f3f1ec")
const COL_SHADOW_NEAR := Color(INK, 0.055)
const COL_SHADOW_MID := Color(INK, 0.035)
const COL_SHADOW_FAR := Color(INK, 0.020)
const COL_BODY_HEAD := INK
const COL_BODY_TAIL := INK
const COL_EYE := PAPER
# Tissue revealed by damage, in the order a bite uncovers it. Intact skin is
# just the body fill, so it needs no colour of its own.
## Fat, under the skin and over the muscle: pale and bloodless, so opening an
## animal reads as getting through the padding first and reaching the meat second.
## It is the one warm light tone on the creature, which is what keeps a fat body
## legibly different from a lean one the moment either is opened.
const COL_FAT := Color("e0cfa8")
const COL_FAT_DEEP := Color("c4ab7c")
const COL_MUSCLE := Color("9c3b26")
const COL_MUSCLE_DEEP := Color("5f2114")
## An organ, once the bone over it has given. Darker and wetter than muscle, and
## deliberately the only thing on the body this colour: seeing it at all means
## something has been opened that should not have been.
const COL_ORGAN := Color("6d1230")
const COL_ORGAN_SPENT := Color("35091a")
## Bone has to be a tone, not a highlight, and it has to darken as it is ground
## down rather than pale out: a cell eaten clean through shows the ground, and
## at anything close to paper the two states are indistinguishable — you could
## not tell a skeleton from a hole in one.
const COL_BONE := Color("c9bda0")
const COL_BONE_WORN := Color("a08d68")
## Material grain. Skin gets a few long, quiet tension lines; exposed muscle
## gets close dark fibres. Neither follows the cell boundaries.
const COL_SKIN_TENSION := Color(PAPER, 0.045)
const COL_MUSCLE_FIBRE := Color("3f160f", 0.62)
## Limbs sit close to the ground, so they get one tight shadow rather than the
## torso's three.
const COL_SHADOW_LIMB := Color(INK, 0.05)
## Every layer of the depth stack showing — what a body looks like from outside,
## and the only mask the game itself ever draws with. See `top_layer`.
const ALL_LAYERS: int = (1 << TissueGrid.LAYERS) - 1

## The open mouth: teeth in paper against the ink head, over the flesh colour of
## the gullet behind them. Nothing new is introduced to the palette — a mouth is
## the one place the creature's own tissue is visible without a wound.
const COL_TOOTH := PAPER
const COL_GULLET := Color("4a1a10")
## Quads across the gullet band. It is a shallow crescent, so this is plenty.
const MOUTH_FACETS: int = 14

const COL_DBG_SPINE := Color(INK, 0.55)
const COL_DBG_RANGE := Color(INK, 0.07)
const COL_DBG_BEND := Color(INK, 0.28)
const COL_DBG_ANCHOR := Color(INK, 0.62)
const COL_DBG_IDEAL := Color(INK, 0.58)
const COL_DBG_STRIDE := Color(INK, 0.12)
const COL_DBG_OUTLINE := Color(PAPER, 0.72)
const COL_DBG_LIMB := Color(INK, 0.72)
## The two supply networks. Cool for nerves, arterial for vessels — they run
## through the same body and have to be told apart at a glance.
const COL_DBG_NERVE := Color("2f6f8f")
const COL_DBG_VESSEL := Color("a8202a")

var creature: Creature

## Reused geometry buffers. _draw runs every frame for every creature, so the
## cell layer allocates nothing per frame — it writes into these instead.
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _skin_lines := PackedVector2Array()
var _muscle_lines := PackedVector2Array()
## Debug-only, but reused on the same terms as the rest: the anatomy overlay is
## wanted exactly when the creature it is drawn over is already expensive.
var _conduit_lines := PackedVector2Array()
var _mesh_points := PackedVector2Array()
var _mesh_colors := PackedColorArray()
var _mesh_indices := PackedInt32Array()
## Single-entry colour array. Godot broadcasts a one-colour array across a whole
## triangle array, which is what lets a shadow reuse the mesh already built for
## the tissue instead of refilling several hundred vertex colours to say one
## thing.
var _flat := PackedColorArray([Color.TRANSPARENT])
## Separate buffers for the jaws, so opening a mouth for a sixth of a second
## cannot make the cell mesh resize itself back and forth every frame.
var _jaw_points := PackedVector2Array()
var _jaw_colors := PackedColorArray()
var _jaw_indices := PackedInt32Array()


func _ready() -> void:
	creature = get_parent() as Creature
	z_index = render_z_index


func _physics_process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if creature == null or creature.body == null or creature.spine == null:
		return
	var body: BodyShape = creature.body
	if body.outline.size() < 3:
		return
	var tissue: TissueGrid = creature.anatomy.tissue
	var torso: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	if torso == null or not torso.live:
		# Nothing has posed the lattice yet, so there is no body to draw from.
		# The silhouette is the same shape the cells tessellate, so falling back
		# to it costs a frame of un-chewable creature rather than an invisible
		# one — and only ever on the frame a creature is built.
		_draw_body_fill(body, COL_BODY_HEAD, COL_BODY_TAIL, Vector2.ZERO)
		return

	var lift := Vector2(0.0, 5.0 * creature.size_scale)
	# How the whole animal sits above the ground, as a screen transform. Zero on
	# anything standing level on the floor, which is nearly everything nearly
	# always — and the only reason this is applied to the drawing rather than to
	# the simulation is that the simulation is the ground plane. See Stature.
	#
	# Two parts and both are measurements. The translation is how far off the
	# ground the body is; the shear is how far it is tipped, because four legs
	# holding four different heights are a body that is nose-down or rolled onto
	# one side. Neither is animated and neither is a lean — see Gait, which reads
	# both off the feet.
	var stature: Stature = creature.stature
	var aloft: Transform2D = _attitude(body, stature)
	var carried: Vector2 = aloft * body.head.pos - body.head.pos
	# Where the ground is, relative to the plane the torso is drawn on. A body
	# lying on the floor casts its shadow under itself; one held a leg's length
	# clear of it casts it well below, and the growing gap is the whole of how
	# height reads in a picture taken from above.
	var ground: Vector2 = stature.drop(0.0)

	# Limb bones, under the torso. Their shadow keeps the plain ambient offset it
	# always had: a leg is already drawn running down to the ground, so its own
	# geometry carries the height and the shadow has none of its own to add.
	for limb in creature.gait.limbs:
		var limb_patch: TissueGrid.Patch = tissue.patch(limb.key)
		if _build(limb_patch, 0, TissueGrid.LIMB_BONE_COLS) > 0:
			_flush_flat(Transform2D(0.0, lift), COL_SHADOW_LIMB)
			_flush_at(aloft)
			_draw_tissue_grain(limb_patch, 0, TissueGrid.LIMB_BONE_COLS, aloft)

	# Torso. Three restrained offset copies approximate the diffused editorial
	# shadow from the reference without a sprite or a blur texture; they are the
	# body's own mesh, so a hole in the creature is a hole in its shadow too.
	if _build(torso, 0, TissueGrid.BODY_COLS) > 0:
		_flush_flat(Transform2D(0.0, ground + Vector2(0.0, 12.0 * creature.size_scale)), COL_SHADOW_FAR)
		_flush_flat(Transform2D(0.0, ground + Vector2(0.0, 8.0 * creature.size_scale)), COL_SHADOW_MID)
		_flush_flat(Transform2D(0.0, ground + lift), COL_SHADOW_NEAR)
		_flush_at(aloft)
	_draw_tissue_grain(torso, 0, TissueGrid.BODY_COLS, aloft)
	# Under the eyes, so a lizard looking at you over its own open mouth still
	# has eyes to look with. Both ride with the head, so both take the same lift
	# off the ground the torso did — as a plain displacement rather than the whole
	# transform, because both are drawn about the head and a shear evaluated at the
	# point it is drawn about is a translation.
	_draw_jaws(body, carried)
	_draw_eyes(body, torso, carried)

	# Feet, over the torso — same reason the limb bones went under it.
	# A shadow is the one thing a stripped patch cannot suppress by being empty:
	# it is drawn from the limb's pose rather than from its cells, so a leg that
	# has come off would go on casting one.
	for limb in creature.gait.limbs:
		if limb.severed:
			continue
		_draw_foot_shadow(limb)
	for limb in creature.gait.limbs:
		var foot_patch: TissueGrid.Patch = tissue.patch(limb.key)
		if _build(foot_patch, TissueGrid.LIMB_BONE_COLS, TissueGrid.LIMB_COLS) > 0:
			_flush_flat(Transform2D(0.0, lift), COL_SHADOW_LIMB)
			_flush_at(aloft)
			_draw_tissue_grain(foot_patch, TissueGrid.LIMB_BONE_COLS, TissueGrid.LIMB_COLS, aloft)

	if debug:
		_draw_debug()


## Where and how this body is drawn: lifted by however far off the ground it is,
## and sheared by however far it is tipped.
##
## The tip turns about the middle of the four legs holding it, because that is the
## rectangle the heights were measured at the corners of — turn it about anything
## else and a body that is merely nose-down comes out translated as well. The
## animal's own axis is taken from the same four: shoulders to hips, which is the
## one line on a creature that does not swing when it looks at something.
func _attitude(body: BodyShape, stature: Stature) -> Transform2D:
	var base: Vector2 = stature.drop(stature.reference + stature.elevation)
	var gait: Gait = creature.gait
	if gait == null or not gait.measured or body.anchors.size() < 4:
		return Transform2D(0.0, base)
	var fore: Vector2 = ((body.anchors["FL"] as Spine.Frame).pos
		+ (body.anchors["FR"] as Spine.Frame).pos) * 0.5
	var rear: Vector2 = ((body.anchors["RL"] as Spine.Frame).pos
		+ (body.anchors["RR"] as Spine.Frame).pos) * 0.5
	var axis: Vector2 = fore - rear
	if axis.length_squared() < 0.0001:
		return Transform2D(0.0, base)
	return Posture.tip((fore + rear) * 0.5, axis.normalized(),
		gait.pitch, gait.roll, base)


# ------------------------------------------------------------------ body ----

## Fills the torso as a strip of quads between consecutive cross-sections.
## Quads are always convex, so this needs no polygon triangulation and cannot
## break however sharply the spine bends.
##
## Only the fallback for a creature whose lattice has not been posed yet. It
## cannot express a wound — it is the whole silhouette or none of it — which is
## exactly why the body is drawn from the cells instead.
func _draw_body_fill(body: BodyShape, col_head: Color, col_tail: Color, offset: Vector2) -> void:
	var last: int = body.last_index
	if last < 1:
		return
	var quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	for i in range(last):
		var t: float = float(i) / float(maxi(last, 1))
		quad[0] = body.flank_left[i] + offset
		quad[1] = body.flank_left[i + 1] + offset
		quad[2] = body.flank_right[i + 1] + offset
		quad[3] = body.flank_right[i] + offset
		draw_colored_polygon(quad, col_head.lerp(col_tail, t))
	# Round caps close off the snout and the tail tip.
	draw_circle(body.head.pos + offset, body.head_radius, col_head)
	draw_circle(creature.spine.points[last] + offset, body.widths[last], col_tail)


## Two paper pinpricks give the otherwise abstract ink silhouette its life —
## but only while there is still a head under them to belong to. An eye over an
## eaten-out skull would be the one thing left painting paper onto nothing.
func _draw_eyes(body: BodyShape, torso: TissueGrid.Patch, offset: Vector2 = Vector2.ZERO) -> void:
	if _cell_survives(torso, body.eye_left, 0, TissueGrid.HEAD_COLS):
		draw_circle(body.eye_left + offset, body.eye_radius * 0.82, COL_EYE)
	if _cell_survives(torso, body.eye_right, 0, TissueGrid.HEAD_COLS):
		draw_circle(body.eye_right + offset, body.eye_radius * 0.82, COL_EYE)


## Whether the cell nearest `at`, within a column range, still has tissue in it.
func _cell_survives(patch: TissueGrid.Patch, at: Vector2, from_col: int, to_col: int) -> bool:
	if patch.gone_count == 0:
		return true
	var best: int = -1
	var best_d: float = INF
	for cell in range(from_col * patch.rows, to_col * patch.rows):
		var d: float = at.distance_squared_to(patch.centre_of(cell))
		if d < best_d:
			best_d = d
			best = cell
	return best < 0 or patch.gone[best] == 0


# ------------------------------------------------------------------ jaws ----

## The teeth — but only while the jaws are open.
##
## A shut mouth seen from directly above is a head, which is why the silhouette
## has never had one cut into it and why the old world cue refused to draw one.
## An open mouth is a different object: the gullet shows between the two arches
## and the teeth stand clear of the gum. That is the one moment a dentition is
## worth looking at, and it is also the moment it is about to be used — the
## mouth is shut again on the frame the bite resolves.
##
## What goes down here is the generated teeth themselves, at the seats the arc
## puts them on. Counting them on screen counts what is about to bite, and a
## blunt mouth of stubby cusps looks like one because that is what it is.
func _draw_jaws(body: BodyShape, offset: Vector2 = Vector2.ZERO) -> void:
	var gape: float = creature.mouth_gape()
	var dentition: Dentition = creature.dentition
	if gape <= 0.02 or dentition == null or dentition.teeth.is_empty():
		return
	var axes: Vector2 = creature.jaw_axes()
	var reach: float = axes.x
	var width: float = axes.y
	var scale: float = Dentition.arc_scale(reach, width)
	var origin: Vector2 = body.head.pos + offset
	var fwd: Vector2 = body.head.fwd
	var perp: Vector2 = body.head.perp
	var span: float = dentition.span

	var teeth: int = dentition.teeth.size()
	var verts: int = MOUTH_FACETS * 4 + teeth * 3
	if _jaw_points.size() != verts:
		_jaw_points.resize(verts)
		_jaw_colors.resize(verts)
		_jaw_indices.resize(MOUTH_FACETS * 6 + teeth * 3)
	var v: int = 0
	var t: int = 0

	# The gullet, as the crescent it actually is: the gap between the lower
	# arch's tips and the upper arch's seats. Its geometry does not move as the
	# jaws part — only how much of it there is to see — because a mouth irising
	# open out of the middle of a face would swallow the eyes on its way.
	var inner: float = maxf(Dentition.LOWER_SEAT - dentition.mean_crown, 0.25)
	var gullet := Color(COL_GULLET, 0.88 * gape)
	for k in MOUTH_FACETS:
		var a0: float = lerpf(-span, span, float(k) / float(MOUTH_FACETS))
		var a1: float = lerpf(-span, span, float(k + 1) / float(MOUTH_FACETS))
		_jaw_points[v] = Dentition.arc_point(origin, fwd, perp, reach, width, a0, inner)
		_jaw_points[v + 1] = Dentition.arc_point(origin, fwd, perp, reach, width, a0, Dentition.UPPER_SEAT)
		_jaw_points[v + 2] = Dentition.arc_point(origin, fwd, perp, reach, width, a1, Dentition.UPPER_SEAT)
		_jaw_points[v + 3] = Dentition.arc_point(origin, fwd, perp, reach, width, a1, inner)
		for c in 4:
			_jaw_colors[v + c] = gullet
		_jaw_indices[t] = v
		_jaw_indices[t + 1] = v + 1
		_jaw_indices[t + 2] = v + 2
		_jaw_indices[t + 3] = v
		_jaw_indices[t + 4] = v + 2
		_jaw_indices[t + 5] = v + 3
		v += 4
		t += 6

	# One triangle per tooth: its base across the jaw line at its seat, its
	# point where the crown ends. Crowns grow out of the gum with the gape, so
	# the teeth emerge as the jaws part rather than snapping into existence.
	var enamel := Color(COL_TOOTH, 0.94 * gape)
	for tooth in dentition.teeth:
		var seat: Vector2 = Dentition.arc_point(
			origin, fwd, perp, reach, width, tooth.angle, tooth.seat)
		var tip_seat: float = maxf(tooth.seat - tooth.crown * gape, 0.05)
		var tangent: Vector2 = Dentition.arc_tangent(fwd, perp, reach, width, tooth.angle)
		var half: float = tooth.half_base * scale
		_jaw_points[v] = seat + tangent * half
		_jaw_points[v + 1] = Dentition.arc_point(
			origin, fwd, perp, reach, width, tooth.angle, tip_seat)
		_jaw_points[v + 2] = seat - tangent * half
		for c in 3:
			_jaw_colors[v + c] = enamel
		_jaw_indices[t] = v
		_jaw_indices[t + 1] = v + 1
		_jaw_indices[t + 2] = v + 2
		v += 3
		t += 3

	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _jaw_indices, _jaw_points, _jaw_colors)


# ------------------------------------------------------------------ limb ----

## Lift is communicated by the widening gap to a soft oval shadow, keeping the
## character strictly monochrome in both planted and airborne poses. The foot
## itself is lattice like everything else, and is drawn with the rest of it.
func _draw_foot_shadow(limb: Limb) -> void:
	var s: float = creature.size_scale
	var r: float = limb.foot_radius(s)
	# How far the foot has come up, against how far it comes up at the top of a
	# full step. The gap between foot and shadow is small in a view from directly
	# overhead however high the foot goes, so this is what actually reads as a
	# lift: the shadow shrinks and pales under a foot that has left the ground.
	var raised: float = clampf(limb.foot_height / maxf(r * 2.0, 1.0), 0.0, 1.0)
	var shadow_r: float = r * (1.0 - 0.35 * raised)
	# Under the foot where it really is, which on a tall animal is well below
	# where the leg is drawn — the same displacement the whole body is drawn
	# through, and the reason a shadow stays on the floor when a foot does not.
	draw_set_transform(limb.ground + Posture.drop(0.0, limb.reference) + Vector2(0.0, 5.0 * s),
		0.0, Vector2(1.05, 0.70))
	draw_circle(Vector2.ZERO, shadow_r, Color(INK, maxf(0.035, 0.13 - raised * 0.09)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------------- cells ----

## Builds the surviving cells of one patch, over a column range, into the shared
## mesh buffers. Returns how many cells were emitted, or 0 if there is nothing
## left to draw there.
##
## The whole lattice is walked rather than just the wounds, because the lattice
## is the body now — but the mesh built here is reused by every pass over that
## structure, so the walk happens once per structure per frame and not once per
## pass. That is what keeps the shadows free: three more copies of the torso
## cost three draw calls and no geometry.
##
## The cells go out as a single indexed triangle array rather than a polygon
## apiece. Godot issues one canvas command per `draw_colored_polygon`, and a
## chewed pair of creatures reached a few hundred of them a frame; measured,
## that alone cost ~5.5 ms/frame and took a 1280x760 window from 120 to 72 fps.
## Batched, a whole creature is a handful of commands.
func _build(patch: TissueGrid.Patch, from_col: int, to_col: int) -> int:
	if patch == null or not patch.live:
		return 0
	var count: int = (to_col - from_col) * patch.rows - _gone_in(patch, from_col, to_col)
	if count <= 0:
		return 0

	if _mesh_points.size() != count * 4:
		_mesh_points.resize(count * 4)
		_mesh_colors.resize(count * 4)
		_mesh_indices.resize(count * 6)
	var v: int = 0
	var t: int = 0
	for col in range(from_col, to_col):
		for row in patch.rows:
			var cell: int = col * patch.rows + row
			if patch.gone[cell] != 0:
				continue
			patch.corners_of(cell, _quad)
			var color: Color = _cell_color(patch, cell)
			for k in 4:
				_mesh_points[v + k] = _quad[k]
				_mesh_colors[v + k] = color
			_mesh_indices[t] = v
			_mesh_indices[t + 1] = v + 1
			_mesh_indices[t + 2] = v + 2
			_mesh_indices[t + 3] = v
			_mesh_indices[t + 4] = v + 2
			_mesh_indices[t + 5] = v + 3
			v += 4
			t += 6
	return count


## Destroyed cells inside a column range. Skipped outright while the patch is
## whole, so an unbitten creature never walks its own lattice to be told so.
func _gone_in(patch: TissueGrid.Patch, from_col: int, to_col: int) -> int:
	if patch.gone_count == 0:
		return 0
	var n: int = 0
	for cell in range(from_col * patch.rows, to_col * patch.rows):
		n += patch.gone[cell]
	return n


## Issues the built mesh in its own colours.
func _flush() -> void:
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _mesh_indices, _mesh_points, _mesh_colors)


## The same, lifted off the ground and tipped onto whatever its legs are holding
## it at. The identity on anything standing level on the floor, so a grounded
## creature goes down through the same path it always did.
func _flush_at(at: Transform2D) -> void:
	if at == Transform2D.IDENTITY:
		_flush()
		return
	draw_set_transform_matrix(at)
	_flush()
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Issues the built mesh again, displaced and in one flat colour — a shadow.
func _flush_flat(at: Transform2D, color: Color) -> void:
	_flat[0] = color
	draw_set_transform_matrix(at)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _mesh_indices, _mesh_points, _flat)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The colour of whatever layer is now uppermost in a cell.
##
## Each layer also darkens toward the one beneath as it thins, so a bite that
## has not yet broken through still shows how deep it got — penetration reads as
## a gradient, and breaching a layer as a step change.
##
## There is no case for an empty cell: those are never built, so what shows
## through a wound is whatever is actually behind the creature. Bone is the only
## thing that stops a bite reaching that state, which is what makes the frame
## legible — the ribs stay as pale bars spanning an open body cavity.
##
## Five layers now, and the order they are tested in is the order a bite goes
## through them, which is the whole reason no case here has to know anything about
## damage. A cell is drawn as whatever is currently on top of it.
func _cell_color(patch: TissueGrid.Patch, cell: int) -> Color:
	var tissue: TissueGrid = creature.anatomy.tissue
	return tissue_color(patch.hp, cell * TissueGrid.LAYERS, tissue.fat_capacity(patch, cell))


## The layer currently uppermost in a cell — the first one a bite has not yet
## spent, skipping any the caller has peeled away. -1 when nothing it can see is
## left there.
##
## `visible` exists for the anatomy panel, which is a dissection rather than a
## second renderer: switching a layer off there means lifting it off the specimen
## and reading what is underneath, so it goes through exactly the depth stack a
## bite would and produces the colours a bite that deep would have exposed.
static func top_layer(hp: PackedFloat32Array, base: int, visible: int = ALL_LAYERS) -> int:
	for layer in TissueGrid.LAYERS:
		if (visible & (1 << layer)) != 0 and hp[base + layer] > 0.0:
			return layer
	return -1


## The colour of that layer, off nothing but a depth stack and how much fat that
## particular cell was built with.
##
## Static because meat off a creature has to be drawn in the creature's own inks.
## A severed leg is not lit differently, coloured differently or abstracted once it
## is on the ground — it is the same tissue in the same state, and the one way to
## guarantee it keeps looking like it is to leave exactly one place that decides.
static func tissue_color(hp: PackedFloat32Array, base: int, fat_capacity: float,
		visible: int = ALL_LAYERS) -> Color:
	match top_layer(hp, base, visible):
		TissueGrid.SKIN:
			# Skin holds together as a membrane until it actually tears. A slight warm
			# shift communicates strain without dissolving it into fat cell by cell.
			return COL_BODY_HEAD.lerp(Color("2b211b"),
				(1.0 - hp[base + TissueGrid.SKIN] / TissueGrid.SKIN_HP) * 0.24)
		TissueGrid.FAT:
			# Measured against this cell's own fat rather than the global maximum: the
			# plan lays down more over the trunk than over a foot, and a full flank and
			# a full ankle should both read as full.
			return COL_FAT.lerp(COL_FAT_DEEP,
				1.0 - hp[base + TissueGrid.FAT] / maxf(fat_capacity, 0.0001))
		TissueGrid.MUSCLE:
			return COL_MUSCLE.lerp(COL_MUSCLE_DEEP,
				1.0 - hp[base + TissueGrid.MUSCLE] / TissueGrid.MUSCLE_HP)
		TissueGrid.BONE:
			return COL_BONE.lerp(COL_BONE_WORN,
				1.0 - hp[base + TissueGrid.BONE] / TissueGrid.BONE_HP)
	# The floor of the stack. A cell with nothing above the organ is drawn as the
	# organ, and one with nothing at all is retired before it ever reaches here.
	return COL_ORGAN.lerp(COL_ORGAN_SPENT,
		1.0 - hp[base + TissueGrid.ORGAN] / TissueGrid.ORGAN_HP)


## Material detail deliberately ignores cell boundaries. Intact skin is read as
## one continuous membrane through sparse longitudinal tension lines, while a
## revealed muscle cell carries several close fibres along the anatomy's grain.
func _draw_tissue_grain(patch: TissueGrid.Patch, from_col: int, to_col: int,
		at: Transform2D = Transform2D.IDENTITY) -> void:
	if patch == null or not patch.live:
		return
	_skin_lines.resize(0)
	_muscle_lines.resize(0)
	for col in range(from_col, to_col):
		for row in patch.rows:
			var cell: int = col * patch.rows + row
			if patch.gone[cell] != 0:
				continue
			var base: int = cell * TissueGrid.LAYERS
			patch.corners_of(cell, _quad)
			var skin: float = patch.hp[base + TissueGrid.SKIN]
			if skin > 0.0:
				# Only alternating rows carry a mark, so the surface reads as a few
				# stretched bands rather than the grid underneath it.
				if row % 2 == 1:
					_skin_lines.append(_quad[0].lerp(_quad[1], 0.5))
					_skin_lines.append(_quad[3].lerp(_quad[2], 0.5))
				continue
			# Fat is a smooth, structureless layer — it has no grain of its own, and
			# putting muscle's on it would draw fibres across a place where there
			# are none and the meat has not been reached yet.
			if patch.hp[base + TissueGrid.FAT] > 0.0 \
					or patch.hp[base + TissueGrid.MUSCLE] <= 0.0:
				continue
			for strand in range(1, 4):
				var across: float = float(strand) * 0.25
				_muscle_lines.append(_quad[0].lerp(_quad[1], across))
				_muscle_lines.append(_quad[3].lerp(_quad[2], across))
	if _skin_lines.is_empty() and _muscle_lines.is_empty():
		return
	if at != Transform2D.IDENTITY:
		draw_set_transform_matrix(at)
	if not _skin_lines.is_empty():
		draw_multiline(_skin_lines, COL_SKIN_TENSION, 0.75, true)
	if not _muscle_lines.is_empty():
		draw_multiline(_muscle_lines, COL_MUSCLE_FIBRE, 0.9, true)
	if at != Transform2D.IDENTITY:
		draw_set_transform_matrix(Transform2D.IDENTITY)


# ----------------------------------------------------------------- debug ----

func _draw_debug() -> void:
	var spine: Spine = creature.spine
	var body: BodyShape = creature.body
	var p: CreatureParams = creature.params
	var n: int = spine.size()
	var seg_len: float = p.segment_length * creature.size_scale
	var max_bend: float = deg_to_rad(p.max_bend_deg)

	# Body outline vertices — shows how the silhouette is sampled.
	for v in body.outline:
		draw_circle(v, 1.4, COL_DBG_OUTLINE)

	# Distance constraint: every point must live on this circle around its parent.
	for i in range(1, n):
		draw_arc(spine.points[i - 1], seg_len, 0.0, TAU, 28, COL_DBG_RANGE, 1.0, true)

	# Angle constraint: the wedge the next segment is allowed to leave through.
	for i in range(1, n - 1):
		var incoming: float = (spine.points[i] - spine.points[i - 1]).angle()
		var arm: float = seg_len * 0.75
		draw_line(spine.points[i], spine.points[i] + Vector2.RIGHT.rotated(incoming - max_bend) * arm, COL_DBG_BEND, 1.0, true)
		draw_line(spine.points[i], spine.points[i] + Vector2.RIGHT.rotated(incoming + max_bend) * arm, COL_DBG_BEND, 1.0, true)
		draw_arc(spine.points[i], arm, incoming - max_bend, incoming + max_bend, 12, COL_DBG_BEND, 1.0, true)

	# The spine chain itself.
	draw_polyline(spine.points, COL_DBG_SPINE, 1.5, true)
	for i in n:
		draw_circle(spine.points[i], 2.6, COL_DBG_SPINE)
		# Local basis used to build the body at this station.
		draw_line(spine.points[i], spine.points[i] + spine.perps[i] * 8.0, Color(INK, 0.24), 1.0, true)

	# Limb sockets and their frames.
	for key in body.anchors:
		var a: Spine.Frame = body.anchors[key]
		draw_circle(a.pos, 3.2, COL_DBG_ANCHOR)
		draw_line(a.pos, a.pos + a.fwd * 14.0, COL_DBG_ANCHOR, 1.0, true)

	# Gait: ideal target, the stride threshold around it, and how far the
	# planted foot has drifted. When the white line grows past the ring, the
	# foot picks up. Stride is per-limb now — read it off the limb rather than
	# recomputing, so the ring always shows the threshold actually being used.
	for limb in creature.gait.limbs:
		if limb.severed:
			continue
		draw_arc(limb.ideal, limb.stride, 0.0, TAU, 32, COL_DBG_STRIDE, 1.0, true)
		draw_arc(limb.ideal, 4.0, 0.0, TAU, 12, COL_DBG_IDEAL, 1.5, true)
		draw_line(limb.planted, limb.ideal, Color(INK, 0.28), 1.0, true)

		# The region the foot may be set down in, drawn on the ground plane where
		# it lives: the arc the leg reaches across and the fore-and-aft ends of the
		# line it walks along. Both are read off the limb rather than recomputed, so
		# the overlay can never disagree with the solver about where a foot may go.
		var a2: Spine.Frame = creature.body.anchors[limb.key]
		var out: Vector2 = a2.perp * limb.side
		var far: float = limb.plan_limit
		var rest: float = (out * limb.rest_lat + a2.fwd * limb.rest_fore).angle()
		draw_arc(a2.pos, far, rest - PI * 0.5, rest + PI * 0.5, 24, COL_DBG_RANGE, 1.0, true)
		for end in [limb.sweep_limit, -limb.sweep_limit]:
			var stop: Vector2 = a2.pos + out * limb.rest_lat \
				+ a2.fwd * (limb.rest_fore + end)
			draw_line(a2.pos, stop, Color(INK, 0.16), 1.0, true)

		# The IK chain, including the ground target the solver was given.
		draw_line(limb.joints[0], limb.joints[1], COL_DBG_LIMB, 1.0, true)
		draw_line(limb.joints[1], limb.joints[2], COL_DBG_LIMB, 1.0, true)
		draw_circle(limb.joints[1], 2.4, COL_DBG_LIMB)
		if limb.stepping:
			draw_line(limb.step_from, limb.step_to, COL_DBG_LIMB, 1.0, true)
			draw_arc(limb.step_to, 3.0, 0.0, TAU, 12, COL_DBG_LIMB, 1.5, true)
		# How far the drawn foot has been displaced from where it really is: down
		# the screen by the ground's own drop, back up by however high the step has
		# carried it. The line between them is the whole 2.5D projection, per foot.
		draw_line(limb.ground, limb.joints[2], Color(INK, 0.35), 1.0, true)

	# Heading and velocity of the head.
	draw_line(creature.head_pos, creature.head_pos + creature.move_dir * 34.0, Color(INK, 0.65), 1.5, true)

	_draw_anatomy_debug()
	_draw_grip_debug()


## The two supply networks, and what each limb can still do.
##
## Drawn because none of it is visible in the body otherwise, and the whole
## design rests on it: a leg that is weak because its muscle is gone and one that
## is weak because its nerve is cut look identical from outside, and the second is
## the case this system exists to make possible. The nerve run and the vessel run
## are laid along the cells they actually pass through, so a cut shows up exactly
## where the flesh was taken.
func _draw_anatomy_debug() -> void:
	var state: BodyState = creature.anatomy.state
	var tissue: TissueGrid = creature.anatomy.tissue
	_draw_conduits(tissue, state.plan.nerves, state.nerves, COL_DBG_NERVE)
	_draw_conduits(tissue, state.plan.vessels, state.vessels, COL_DBG_VESSEL)

	# The organs, which are otherwise sealed inside the skeleton and invisible
	# until something has already got through it.
	_draw_organ(tissue, BodyPlan.BRAIN)
	_draw_organ(tissue, BodyPlan.HEART)

	# One bar per limb: how much force it has, and how much of it the animal is
	# still in command of. When the two separate, the second is the interesting one.
	for limb in creature.gait.limbs:
		if limb.severed:
			continue
		var at: Vector2 = limb.joints[0]
		var axis: Vector2 = creature.body.anchors[limb.key].perp * limb.side * 9.0
		draw_line(at, at + axis * limb.drive, COL_MUSCLE, 2.0, true)
		draw_line(at + Vector2(0.0, 3.0), at + Vector2(0.0, 3.0) + axis * limb.command,
			COL_DBG_NERVE, 2.0, true)


## One `draw_multiline` per run rather than one `draw_line` per cell it passes
## through, for the same reason the tissue itself is one triangle array: a nerve
## laid down segment by segment is a couple of hundred canvas commands a frame,
## and this overlay is most wanted precisely when a chewed-up creature is already
## the most expensive thing on screen.
func _draw_conduits(tissue: TissueGrid, runs: Array[BodyPlan.Conduit],
		network: AnatomyNetwork, tint: Color) -> void:
	for run in runs:
		var patch: TissueGrid.Patch = tissue.patch(run.patch_key)
		if patch == null or not patch.live or run.cells.size() < 2:
			continue
		_conduit_lines.resize(0)
		var previous: Vector2 = patch.centre_of(run.cells[0])
		for index in range(1, run.cells.size()):
			var at: Vector2 = patch.centre_of(run.cells[index])
			if patch.gone[run.cells[index]] == 0:
				_conduit_lines.append(previous)
				_conduit_lines.append(at)
			previous = at
		if _conduit_lines.is_empty():
			continue
		# Alpha carries what arrives rather than what survives locally, so a run
		# that is itself intact still fades out behind a cut upstream of it — which
		# is the property the whole network exists to have.
		var reach: float = clampf(network.delivery[run.region], 0.0, 1.0)
		draw_multiline(_conduit_lines, Color(tint, 0.18 + 0.62 * reach),
			1.0 + 1.4 * reach, true)


func _draw_organ(tissue: TissueGrid, which: int) -> void:
	var patch: TissueGrid.Patch = tissue.patch(TissueGrid.BODY_KEY)
	if patch == null or not patch.live:
		return
	var left: float = tissue.organ(which)
	for cell in patch.cells:
		if patch.organ[cell] != which or patch.gone[cell] != 0:
			continue
		draw_circle(patch.centre_of(cell), 1.8,
			Color(COL_ORGAN, 0.30 + 0.60 * left))


## The tether a latched bite actually is: jaw point, the flesh it is bound to,
## and how close each of the two things holding it together is to failing.
## Drawn because none of it is visible in the pose otherwise — a grip about to
## fail and one that will never fail look identical until the moment it goes.
##
## Both failures get an arc, and the pair of them is the whole contest at a
## glance: whichever fills first is what is about to happen. The inner one is the
## jaws' own strain, and a full circle is them being pulled off. The outer is the
## flesh's, and a full circle is a mouthful of the victim coming away.
func _draw_grip_debug() -> void:
	var held: Grip = creature.grip
	if held == null or not held.is_alive():
		return
	var jaw: Vector2 = creature.jaw_point()
	var anchor: Vector2 = held.anchor()
	var strain: float = clampf(held.strain(), 0.0, 1.0)
	var stress: float = clampf(held.stress, 0.0, 1.0)
	draw_line(jaw, anchor, Color(INK, 0.30 + 0.55 * maxf(strain, stress)),
		1.0 + 1.6 * strain, true)
	draw_arc(anchor, 4.0, 0.0, TAU, 12, COL_DBG_LIMB, 1.5, true)
	draw_arc(jaw, 7.0, -PI * 0.5, -PI * 0.5 + TAU * strain, 20, COL_DBG_ANCHOR, 2.0, true)
	draw_arc(jaw, 10.0, -PI * 0.5, -PI * 0.5 + TAU * stress, 24, COL_MUSCLE, 2.0, true)
	# The play the tether allows before it pulls at all, including whatever the
	# flesh has already drawn out of the body — the ring grows as tissue yields.
	draw_arc(jaw, held.rest_length + held.stretch(), 0.0, TAU, 24, COL_DBG_RANGE, 1.0, true)
