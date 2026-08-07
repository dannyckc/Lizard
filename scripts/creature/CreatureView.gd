## Draws the creature. Purely a consumer — it reads the solved state and never
## writes to it, so the simulation can be run headless or drawn differently
## without touching a line of the systems above.
##
## Draw order: ground shadows -> limbs -> body -> feet -> debug overlay, so the
## legs read as being underneath the torso the way they do from above.
class_name CreatureView
extends Node2D

@export var debug: bool = false

const INK := Color("14140f")
const PAPER := Color("f3f1ec")
const COL_SHADOW_NEAR := Color(INK, 0.055)
const COL_SHADOW_MID := Color(INK, 0.035)
const COL_SHADOW_FAR := Color(INK, 0.020)
const COL_BODY_HEAD := INK
const COL_BODY_TAIL := INK
const COL_LIMB := INK
const COL_EYE := PAPER
# Tissue revealed by damage, in the order a bite uncovers it. Intact skin is
# just the body fill, so it needs no colour of its own.
const COL_MUSCLE := Color("9c3b26")
const COL_MUSCLE_DEEP := Color("5f2114")
## Bone has to be a tone, not a highlight, and it has to darken as it is ground
## down rather than pale out: a cell eaten clean through shows the ground, and
## at anything close to paper the two states are indistinguishable — you could
## not tell a skeleton from a hole in one.
const COL_BONE := Color("c9bda0")
const COL_BONE_WORN := Color("a08d68")
## A cell with nothing left in it is a hole, so it is drawn as the paper the
## world is drawn on. Where the skeleton runs there is bone to stop the bite;
## everywhere else flesh is all there is, and eating it opens the body.
const COL_GROUND := PAPER
## Cell seams, faint enough to read as scale texture rather than as a grid.
const COL_SEAM := Color(PAPER, 0.085)

const COL_DBG_SPINE := Color(INK, 0.55)
const COL_DBG_RANGE := Color(INK, 0.07)
const COL_DBG_BEND := Color(INK, 0.28)
const COL_DBG_ANCHOR := Color(INK, 0.62)
const COL_DBG_IDEAL := Color(INK, 0.58)
const COL_DBG_STRIDE := Color(INK, 0.12)
const COL_DBG_OUTLINE := Color(PAPER, 0.72)
const COL_DBG_LIMB := Color(INK, 0.72)

var creature: Creature

## Reused geometry buffers. _draw runs every frame for every creature, so the
## cell layer allocates nothing per frame — it writes into these instead.
var _quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _seams := PackedVector2Array()
var _mesh_points := PackedVector2Array()
var _mesh_colors := PackedColorArray()
var _mesh_indices := PackedInt32Array()


func _ready() -> void:
	creature = get_parent() as Creature
	z_index = 10


func _physics_process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if creature == null or creature.body == null or creature.spine == null:
		return
	var body: BodyShape = creature.body
	if body.outline.size() < 3:
		return

	# Three restrained offset silhouettes approximate the diffused editorial
	# shadow from the reference without introducing a sprite or blur texture.
	_draw_body_fill(body, COL_SHADOW_FAR, COL_SHADOW_FAR, Vector2(0.0, 12.0 * creature.size_scale))
	_draw_body_fill(body, COL_SHADOW_MID, COL_SHADOW_MID, Vector2(0.0, 8.0 * creature.size_scale))
	_draw_body_fill(body, COL_SHADOW_NEAR, COL_SHADOW_NEAR, Vector2(0.0, 5.0 * creature.size_scale))
	for limb in creature.gait.limbs:
		_draw_limb_shadow(limb, Vector2(0.0, 5.0 * creature.size_scale))

	var tissue: TissueGrid = creature.anatomy.tissue

	for limb in creature.gait.limbs:
		_draw_limb(limb)
	# Bone damage belongs under the torso, foot damage over it — same reason the
	# limbs themselves are split around the body fill.
	_draw_limb_cells(tissue, 0, TissueGrid.LIMB_BONE_COLS)

	_draw_body_fill(body, COL_BODY_HEAD, COL_BODY_TAIL, Vector2.ZERO)
	_draw_head(body)
	_draw_cells(tissue.patch(TissueGrid.BODY_KEY), 0, TissueGrid.BODY_COLS)
	_draw_seams(tissue.patch(TissueGrid.BODY_KEY))

	for limb in creature.gait.limbs:
		_draw_foot(limb)
	_draw_limb_cells(tissue, TissueGrid.LIMB_BONE_COLS, TissueGrid.LIMB_COLS)

	_draw_jaw(body)

	if debug:
		_draw_debug()


# ------------------------------------------------------------------ body ----

## Fills the torso as a strip of quads between consecutive cross-sections.
## Quads are always convex, so this needs no polygon triangulation and cannot
## break however sharply the spine bends.
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


func _draw_head(body: BodyShape) -> void:
	# Two paper pinpricks give the otherwise abstract ink silhouette its life.
	draw_circle(body.eye_left, body.eye_radius * 0.82, COL_EYE)
	draw_circle(body.eye_right, body.eye_radius * 0.82, COL_EYE)


# ------------------------------------------------------------------ limb ----

func _limb_widths(limb: Limb) -> Vector2:
	var s: float = creature.size_scale
	var upper: float = maxf(limb.total_length * 0.16, 2.5 * s)
	return Vector2(upper, upper * 0.72)


func _draw_limb_shadow(limb: Limb, offset: Vector2) -> void:
	var w: Vector2 = _limb_widths(limb)
	draw_line(limb.joints[0] + offset, limb.joints[1] + offset, Color(INK, 0.05), w.x + 1.5, true)
	draw_line(limb.joints[1] + offset, limb.joints[2] + offset, Color(INK, 0.05), w.y + 1.5, true)


func _draw_limb(limb: Limb) -> void:
	var w: Vector2 = _limb_widths(limb)
	draw_line(limb.joints[0], limb.joints[1], COL_LIMB, w.x, true)
	draw_line(limb.joints[1], limb.joints[2], COL_LIMB, w.y, true)


## Lift is communicated by the widening gap to a soft oval shadow, keeping the
## character strictly monochrome in both planted and airborne poses.
func _draw_foot(limb: Limb) -> void:
	var s: float = creature.size_scale
	var r: float = maxf(limb.total_length * 0.10, 3.0 * s)
	var lifted: Vector2 = limb.joints[2]

	var shadow_r: float = r * (1.0 - 0.35 * clampf(limb.lift / maxf(r * 3.0, 1.0), 0.0, 1.0))
	draw_set_transform(limb.ground + Vector2(0.0, 5.0 * s), 0.0, Vector2(1.05, 0.70))
	draw_circle(Vector2.ZERO, shadow_r, Color(INK, maxf(0.035, 0.13 - limb.lift * 0.004)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(lifted, r, INK)


# ----------------------------------------------------------------- cells ----

## Draws the damaged cells of one patch, restricted to a column range.
##
## Two things keep this cheap, and both are load-bearing.
##
## Intact skin is already on screen as the body fill, so the lattice is drawn
## purely as an overlay of what has been *lost* — cost tracks the damage, not
## the ~180-cell lattice, and an untouched creature costs one early return.
##
## The cells that do draw go out as a single indexed triangle array rather than
## a polygon apiece. Godot issues one canvas command per `draw_colored_polygon`,
## and a badly chewed pair of creatures reaches a few hundred of them a frame;
## measured, that alone cost ~5.5 ms/frame and took a 1280x760 window from 120
## to 72 fps. Batched, the same cells are four commands for the whole world.
func _draw_cells(patch: TissueGrid.Patch, from_col: int, to_col: int) -> void:
	if patch == null or not patch.live or patch.damaged.is_empty():
		return
	var count: int = 0
	for cell in patch.damaged:
		var col: int = cell / patch.rows
		if col >= from_col and col < to_col:
			count += 1
	if count == 0:
		return

	if _mesh_points.size() != count * 4:
		_mesh_points.resize(count * 4)
		_mesh_colors.resize(count * 4)
		_mesh_indices.resize(count * 6)
	var v: int = 0
	var t: int = 0
	for cell in patch.damaged:
		var col: int = cell / patch.rows
		if col < from_col or col >= to_col:
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
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _mesh_indices, _mesh_points, _mesh_colors)


func _draw_limb_cells(tissue: TissueGrid, from_col: int, to_col: int) -> void:
	for limb in creature.gait.limbs:
		_draw_cells(tissue.patch(limb.key), from_col, to_col)


## The colour of whatever layer is now uppermost in a cell.
##
## Each layer also darkens toward the one beneath as it thins, so a bite that
## has not yet broken through still shows how deep it got — penetration reads as
## a gradient, and breaching a layer as a step change.
##
## The last case is the one that carries the skeleton: a cell with no bone under
## it has nothing left once its muscle is gone, so it falls straight through to
## the ground. Bone is the only thing that stops that, which is what makes the
## frame legible — the ribs stay as pale bars across an open body cavity.
func _cell_color(patch: TissueGrid.Patch, cell: int) -> Color:
	var base: int = cell * TissueGrid.LAYERS
	var skin: float = patch.hp[base + TissueGrid.SKIN]
	if skin > 0.0:
		return COL_BODY_HEAD.lerp(COL_MUSCLE, 1.0 - skin / TissueGrid.SKIN_HP)
	var muscle: float = patch.hp[base + TissueGrid.MUSCLE]
	if muscle > 0.0:
		return COL_MUSCLE.lerp(COL_MUSCLE_DEEP, 1.0 - muscle / TissueGrid.MUSCLE_HP)
	var bone: float = patch.hp[base + TissueGrid.BONE]
	if bone > 0.0:
		return COL_BONE.lerp(COL_BONE_WORN, 1.0 - bone / TissueGrid.BONE_HP)
	return COL_GROUND


## The cell seams, as one batched multiline over the whole body.
##
## Drawing the lattice cell by cell would cost ~180 polygons a frame per
## creature to say something a single line primitive says just as well, so the
## interior seams are emitted into one reused buffer and issued in one call. The
## silhouette's own boundary rows and columns are skipped — the fill already
## draws that edge, and stroking it again only fattens it.
func _draw_seams(patch: TissueGrid.Patch) -> void:
	if patch == null or not patch.live:
		return
	var needed: int = 2 * (patch.cols * (patch.rows - 1) + (patch.cols - 1) * patch.rows)
	if _seams.size() != needed:
		_seams.resize(needed)
	var i: int = 0
	for c in patch.cols:
		for r in range(1, patch.rows):
			_seams[i] = patch.vert(c, r)
			_seams[i + 1] = patch.vert(c + 1, r)
			i += 2
	for c in range(1, patch.cols):
		for r in patch.rows:
			_seams[i] = patch.vert(c, r)
			_seams[i + 1] = patch.vert(c, r + 1)
			i += 2
	draw_multiline(_seams, COL_SEAM, 1.0, true)


# ------------------------------------------------------------------ bite ----

## The gape, cut into the snout as a paper wedge.
##
## Direction is carried by the lunge itself — the head is genuinely thrown
## forward — so this only has to state the timing: it opens through the wind-up,
## holds through the throw, and vanishes on the frame the bite resolves.
func _draw_jaw(body: BodyShape) -> void:
	var open: float = creature.jaw_open()
	if open <= 0.001:
		return
	var half: float = deg_to_rad(34.0) * open
	var radius: float = body.head_radius * 1.3
	var base: float = body.head.fwd.angle()
	# Hinged behind the head's centre, so the wedge bites into the silhouette
	# rather than sitting on the front of it.
	var wedge := PackedVector2Array([body.head.pos - body.head.fwd * (body.head_radius * 0.3)])
	for k in range(7):
		wedge.append(body.head.pos
			+ Vector2.RIGHT.rotated(base - half + 2.0 * half * (float(k) / 6.0)) * radius)
	draw_colored_polygon(wedge, PAPER)


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
		draw_arc(limb.ideal, limb.stride, 0.0, TAU, 32, COL_DBG_STRIDE, 1.0, true)
		draw_arc(limb.ideal, 4.0, 0.0, TAU, 12, COL_DBG_IDEAL, 1.5, true)
		draw_line(limb.planted, limb.ideal, Color(INK, 0.28), 1.0, true)

		# The envelope the foot is confined to: the fan it may swing through and
		# the reach limit it skids along when the body outruns it.
		var a2: Spine.Frame = creature.body.anchors[limb.key]
		var swing: float = deg_to_rad(p.limb_swing_deg)
		var rest: float = limb.rest_dir.angle()
		draw_arc(a2.pos, limb.total_length * p.limb_max_reach, rest - swing, rest + swing,
			20, COL_DBG_RANGE, 1.0, true)

		# The IK chain, including the ground target the solver was given.
		draw_line(limb.joints[0], limb.joints[1], COL_DBG_LIMB, 1.0, true)
		draw_line(limb.joints[1], limb.joints[2], COL_DBG_LIMB, 1.0, true)
		draw_circle(limb.joints[1], 2.4, COL_DBG_LIMB)
		if limb.stepping:
			draw_line(limb.step_from, limb.step_to, COL_DBG_LIMB, 1.0, true)
			draw_arc(limb.step_to, 3.0, 0.0, TAU, 12, COL_DBG_LIMB, 1.5, true)
			# Lift is fake height, drawn as the gap between foot and shadow.
			draw_line(limb.ground, limb.joints[2], Color(INK, 0.35), 1.0, true)

	# Heading and velocity of the head.
	draw_line(creature.head_pos, creature.head_pos + creature.move_dir * 34.0, Color(INK, 0.65), 1.5, true)
