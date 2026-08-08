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
const COL_MUSCLE := Color("9c3b26")
const COL_MUSCLE_DEEP := Color("5f2114")
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
var _skin_lines := PackedVector2Array()
var _muscle_lines := PackedVector2Array()
var _mesh_points := PackedVector2Array()
var _mesh_colors := PackedColorArray()
var _mesh_indices := PackedInt32Array()
## Single-entry colour array. Godot broadcasts a one-colour array across a whole
## triangle array, which is what lets a shadow reuse the mesh already built for
## the tissue instead of refilling several hundred vertex colours to say one
## thing.
var _flat := PackedColorArray([Color.TRANSPARENT])


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

	# Limb bones, under the torso.
	for limb in creature.gait.limbs:
		var limb_patch: TissueGrid.Patch = tissue.patch(limb.key)
		if _build(limb_patch, 0, TissueGrid.LIMB_BONE_COLS) > 0:
			_flush_flat(lift, COL_SHADOW_LIMB)
			_flush()
			_draw_tissue_grain(limb_patch, 0, TissueGrid.LIMB_BONE_COLS)

	# Torso. Three restrained offset copies approximate the diffused editorial
	# shadow from the reference without a sprite or a blur texture; they are the
	# body's own mesh, so a hole in the creature is a hole in its shadow too.
	if _build(torso, 0, TissueGrid.BODY_COLS) > 0:
		_flush_flat(Vector2(0.0, 12.0 * creature.size_scale), COL_SHADOW_FAR)
		_flush_flat(Vector2(0.0, 8.0 * creature.size_scale), COL_SHADOW_MID)
		_flush_flat(lift, COL_SHADOW_NEAR)
		_flush()
	_draw_tissue_grain(torso, 0, TissueGrid.BODY_COLS)
	_draw_eyes(body, torso)

	# Feet, over the torso — same reason the limb bones went under it.
	for limb in creature.gait.limbs:
		_draw_foot_shadow(limb)
	for limb in creature.gait.limbs:
		var foot_patch: TissueGrid.Patch = tissue.patch(limb.key)
		if _build(foot_patch, TissueGrid.LIMB_BONE_COLS, TissueGrid.LIMB_COLS) > 0:
			_flush_flat(lift, COL_SHADOW_LIMB)
			_flush()
			_draw_tissue_grain(foot_patch, TissueGrid.LIMB_BONE_COLS, TissueGrid.LIMB_COLS)

	if debug:
		_draw_debug()


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
func _draw_eyes(body: BodyShape, torso: TissueGrid.Patch) -> void:
	if _cell_survives(torso, body.eye_left, 0, TissueGrid.HEAD_COLS):
		draw_circle(body.eye_left, body.eye_radius * 0.82, COL_EYE)
	if _cell_survives(torso, body.eye_right, 0, TissueGrid.HEAD_COLS):
		draw_circle(body.eye_right, body.eye_radius * 0.82, COL_EYE)


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


# ------------------------------------------------------------------ limb ----

## Lift is communicated by the widening gap to a soft oval shadow, keeping the
## character strictly monochrome in both planted and airborne poses. The foot
## itself is lattice like everything else, and is drawn with the rest of it.
func _draw_foot_shadow(limb: Limb) -> void:
	var s: float = creature.size_scale
	var r: float = maxf(limb.total_length * 0.10, 3.0 * s)
	var shadow_r: float = r * (1.0 - 0.35 * clampf(limb.lift / maxf(r * 3.0, 1.0), 0.0, 1.0))
	draw_set_transform(limb.ground + Vector2(0.0, 5.0 * s), 0.0, Vector2(1.05, 0.70))
	draw_circle(Vector2.ZERO, shadow_r, Color(INK, maxf(0.035, 0.13 - limb.lift * 0.004)))
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


## Issues the built mesh again, offset and in one flat colour — a shadow.
func _flush_flat(offset: Vector2, color: Color) -> void:
	_flat[0] = color
	draw_set_transform(offset, 0.0, Vector2.ONE)
	RenderingServer.canvas_item_add_triangle_array(
		get_canvas_item(), _mesh_indices, _mesh_points, _flat)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
func _cell_color(patch: TissueGrid.Patch, cell: int) -> Color:
	var base: int = cell * TissueGrid.LAYERS
	var skin: float = patch.hp[base + TissueGrid.SKIN]
	if skin > 0.0:
		# Skin holds together as a membrane until it actually tears. A slight warm
		# shift communicates strain without dissolving it into muscle cell by cell.
		return COL_BODY_HEAD.lerp(Color("2b211b"), (1.0 - skin / TissueGrid.SKIN_HP) * 0.24)
	var muscle: float = patch.hp[base + TissueGrid.MUSCLE]
	if muscle > 0.0:
		return COL_MUSCLE.lerp(COL_MUSCLE_DEEP, 1.0 - muscle / TissueGrid.MUSCLE_HP)
	return COL_BONE.lerp(COL_BONE_WORN, 1.0 - patch.hp[base + TissueGrid.BONE] / TissueGrid.BONE_HP)


## Material detail deliberately ignores cell boundaries. Intact skin is read as
## one continuous membrane through sparse longitudinal tension lines, while a
## revealed muscle cell carries several close fibres along the anatomy's grain.
func _draw_tissue_grain(patch: TissueGrid.Patch, from_col: int, to_col: int) -> void:
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
			if patch.hp[base + TissueGrid.MUSCLE] <= 0.0:
				continue
			for strand in range(1, 4):
				var across: float = float(strand) * 0.25
				_muscle_lines.append(_quad[0].lerp(_quad[1], across))
				_muscle_lines.append(_quad[3].lerp(_quad[2], across))
	if not _skin_lines.is_empty():
		draw_multiline(_skin_lines, COL_SKIN_TENSION, 0.75, true)
	if not _muscle_lines.is_empty():
		draw_multiline(_muscle_lines, COL_MUSCLE_FIBRE, 0.9, true)


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

	_draw_grip_debug()


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
