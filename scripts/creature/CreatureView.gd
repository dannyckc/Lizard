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
const COL_FLESH := Color("a64b36")

const COL_DBG_SPINE := Color(INK, 0.55)
const COL_DBG_RANGE := Color(INK, 0.07)
const COL_DBG_BEND := Color(INK, 0.28)
const COL_DBG_ANCHOR := Color(INK, 0.62)
const COL_DBG_IDEAL := Color(INK, 0.58)
const COL_DBG_STRIDE := Color(INK, 0.12)
const COL_DBG_OUTLINE := Color(PAPER, 0.72)
const COL_DBG_LIMB := Color(INK, 0.72)

var creature: Creature


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

	for limb in creature.gait.limbs:
		_draw_limb(limb)
	_draw_limb_wounds(false)

	_draw_body_fill(body, COL_BODY_HEAD, COL_BODY_TAIL, Vector2.ZERO)
	_draw_head(body)
	_draw_body_wounds()

	for limb in creature.gait.limbs:
		_draw_foot(limb)
	_draw_limb_wounds(true)

	_draw_bite_feedback()

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


# ---------------------------------------------------------------- wounds ----

func _draw_body_wounds() -> void:
	for wound in creature.anatomy.wounds:
		if wound.kind == AnatomyState.LIMB:
			continue
		var pos: Vector2
		if wound.kind == AnatomyState.HEAD:
			var head: Spine.Frame = creature.body.head
			pos = head.pos \
				+ head.fwd * (wound.local_forward * creature.body.head_radius) \
				+ head.perp * (wound.lateral * creature.body.head_radius)
		else:
			var frame: Spine.Frame = creature.spine.sample(wound.spine_t)
			var idx: int = clampi(
				int(round(wound.spine_t * float(creature.spine.size() - 1))),
				0,
				creature.body.widths.size() - 1
			)
			pos = frame.pos + frame.perp * (wound.lateral * creature.body.widths[idx])
		_draw_wound_mark(pos, wound.radius * creature.size_scale)


## Draws either bone wounds or foot wounds. Feet have to be cut after their
## filled circles are rendered, while bone wounds belong below the torso.
func _draw_limb_wounds(feet_only: bool) -> void:
	for wound in creature.anatomy.wounds:
		if wound.kind != AnatomyState.LIMB:
			continue
		var is_foot: bool = wound.limb_segment == 2
		if is_foot != feet_only:
			continue
		var limb: Limb = _find_limb(wound.limb_key)
		if limb == null:
			continue
		var pos: Vector2
		if is_foot:
			pos = limb.joints[2]
		else:
			pos = limb.joints[wound.limb_segment].lerp(
				limb.joints[wound.limb_segment + 1], wound.limb_u)
		_draw_wound_mark(pos, wound.radius * creature.size_scale)


func _draw_wound_mark(pos: Vector2, radius: float) -> void:
	var r: float = maxf(radius, 1.5)
	# A restrained rust rim keeps the editorial palette while the paper centre
	# reads as flesh that is genuinely absent rather than a decal on top.
	draw_circle(pos, r, COL_FLESH)
	draw_circle(pos, r * 0.72, PAPER)


func _find_limb(key: String) -> Limb:
	for limb in creature.gait.limbs:
		if limb.key == key:
			return limb
	return null


func _draw_bite_feedback() -> void:
	if creature.bite_feedback_remaining <= 0.0:
		return
	var fade: float = clampf(creature.bite_feedback_remaining / 0.14, 0.0, 1.0)
	var color: Color = Color(COL_FLESH if creature.bite_connected else INK, 0.18 + fade * 0.52)
	draw_arc(creature.bite_feedback_center, creature.bite_feedback_radius,
		0.0, TAU, 28, color, 1.6, true)


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
