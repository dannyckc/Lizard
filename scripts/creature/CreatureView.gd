## Draws the creature. Purely a consumer — it reads the solved state and never
## writes to it, so the simulation can be run headless or drawn differently
## without touching a line of the systems above.
##
## Draw order: ground shadows -> limbs -> body -> feet -> debug overlay, so the
## legs read as being underneath the torso the way they do from above.
class_name CreatureView
extends Node2D

@export var debug: bool = false

const COL_SHADOW := Color(0.043, 0.055, 0.066)          # opaque: flat ground
const COL_BODY_HEAD := Color(0.322, 0.549, 0.361)
const COL_BODY_TAIL := Color(0.216, 0.400, 0.286)
const COL_OUTLINE := Color(0.086, 0.161, 0.118)
const COL_STRIPE := Color(0.451, 0.678, 0.427, 0.55)
const COL_LIMB := Color(0.259, 0.443, 0.298)
const COL_LIMB_EDGE := Color(0.114, 0.208, 0.153)
const COL_FOOT_PLANTED := Color(0.949, 0.749, 0.349)
const COL_FOOT_STEPPING := Color(0.376, 0.851, 0.949)
const COL_EYE := Color(0.94, 0.96, 0.92)
const COL_PUPIL := Color(0.08, 0.10, 0.09)

const COL_DBG_SPINE := Color(1.0, 0.35, 0.55)
const COL_DBG_RANGE := Color(1.0, 1.0, 1.0, 0.07)
const COL_DBG_BEND := Color(1.0, 0.80, 0.25, 0.45)
const COL_DBG_ANCHOR := Color(0.40, 0.70, 1.0)
const COL_DBG_IDEAL := Color(0.45, 1.0, 0.60)
const COL_DBG_STRIDE := Color(0.45, 1.0, 0.60, 0.16)
const COL_DBG_OUTLINE := Color(1.0, 1.0, 1.0, 0.30)
const COL_DBG_LIMB := Color(1.0, 0.55, 0.20)

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

	var shadow_offset := Vector2(0.0, 5.0 * creature.size_scale)

	_draw_body_fill(body, COL_SHADOW, COL_SHADOW, shadow_offset)
	for limb in creature.gait.limbs:
		_draw_limb_shadow(limb, shadow_offset)

	for limb in creature.gait.limbs:
		_draw_limb(limb)

	_draw_body_fill(body, COL_BODY_HEAD, COL_BODY_TAIL, Vector2.ZERO)
	_draw_outline(body)
	_draw_dorsal_stripe(body)
	_draw_head(body)

	for limb in creature.gait.limbs:
		_draw_foot(limb)

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


func _draw_outline(body: BodyShape) -> void:
	# Corner-cut for the stroke only; the fill above uses the raw cross-sections.
	var smooth: PackedVector2Array = BodyShape.smooth_closed(body.outline, 1)
	smooth.append(smooth[0])
	draw_polyline(smooth, COL_OUTLINE, 2.0 * creature.size_scale, true)


func _draw_dorsal_stripe(body: BodyShape) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(body.last_index + 1):
		pts.append(creature.spine.points[i])
	if pts.size() >= 2:
		draw_polyline(pts, COL_STRIPE, 2.5 * creature.size_scale, true)


func _draw_head(body: BodyShape) -> void:
	draw_circle(body.eye_left, body.eye_radius, COL_EYE)
	draw_circle(body.eye_right, body.eye_radius, COL_EYE)
	var gaze: Vector2 = body.head.fwd * (body.eye_radius * 0.35)
	draw_circle(body.eye_left + gaze, body.eye_radius * 0.5, COL_PUPIL)
	draw_circle(body.eye_right + gaze, body.eye_radius * 0.5, COL_PUPIL)


# ------------------------------------------------------------------ limb ----

func _limb_widths(limb: Limb) -> Vector2:
	var s: float = creature.size_scale
	var upper: float = maxf(limb.total_length * 0.16, 2.5 * s)
	return Vector2(upper, upper * 0.72)


func _draw_limb_shadow(limb: Limb, offset: Vector2) -> void:
	var w: Vector2 = _limb_widths(limb)
	draw_line(limb.joints[0] + offset, limb.joints[1] + offset, COL_SHADOW, w.x + 1.5, true)
	draw_line(limb.joints[1] + offset, limb.joints[2] + offset, COL_SHADOW, w.y + 1.5, true)


func _draw_limb(limb: Limb) -> void:
	var w: Vector2 = _limb_widths(limb)
	# Cheap outline: a slightly fatter dark line under a lighter one.
	draw_line(limb.joints[0], limb.joints[1], COL_LIMB_EDGE, w.x + 2.0, true)
	draw_line(limb.joints[1], limb.joints[2], COL_LIMB_EDGE, w.y + 2.0, true)
	draw_line(limb.joints[0], limb.joints[1], COL_LIMB, w.x, true)
	draw_line(limb.joints[1], limb.joints[2], COL_LIMB, w.y, true)


## Planted and stepping feet are deliberately easy to tell apart: a planted foot
## is a filled amber disc sitting on its shadow, a stepping one is a hollow cyan
## ring lifted away from a shrinking shadow.
func _draw_foot(limb: Limb) -> void:
	var s: float = creature.size_scale
	var r: float = maxf(limb.total_length * 0.13, 3.0 * s)
	var lifted: Vector2 = limb.joints[2]

	var shadow_r: float = r * (1.0 - 0.35 * clampf(limb.lift / maxf(r * 3.0, 1.0), 0.0, 1.0))
	draw_circle(limb.ground + Vector2(0.0, 5.0 * s), shadow_r, COL_SHADOW)

	if limb.stepping:
		draw_circle(lifted, r, COL_LIMB_EDGE)
		draw_arc(lifted, r * 0.92, 0.0, TAU, 18, COL_FOOT_STEPPING, 2.0 * s, true)
	else:
		draw_circle(lifted, r, COL_FOOT_PLANTED)
		draw_arc(lifted, r, 0.0, TAU, 18, COL_LIMB_EDGE, 1.5 * s, true)


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
		draw_line(spine.points[i], spine.points[i] + spine.perps[i] * 8.0, Color(0.4, 0.7, 1.0, 0.35), 1.0, true)

	# Limb sockets and their frames.
	for key in body.anchors:
		var a: Spine.Frame = body.anchors[key]
		draw_circle(a.pos, 3.2, COL_DBG_ANCHOR)
		draw_line(a.pos, a.pos + a.fwd * 14.0, COL_DBG_ANCHOR, 1.0, true)

	# Gait: ideal target, the stride threshold around it, and how far the
	# planted foot has drifted. When the white line grows past the ring, the
	# foot picks up.
	var stride: float = p.stride_distance * creature.size_scale * (0.45 + 0.55 * creature.speed_norm)
	for limb in creature.gait.limbs:
		draw_arc(limb.ideal, stride, 0.0, TAU, 32, COL_DBG_STRIDE, 1.0, true)
		draw_arc(limb.ideal, 4.0, 0.0, TAU, 12, COL_DBG_IDEAL, 1.5, true)
		draw_line(limb.planted, limb.ideal, Color(1, 1, 1, 0.28), 1.0, true)

		# The IK chain, including the ground target the solver was given.
		draw_line(limb.joints[0], limb.joints[1], COL_DBG_LIMB, 1.0, true)
		draw_line(limb.joints[1], limb.joints[2], COL_DBG_LIMB, 1.0, true)
		draw_circle(limb.joints[1], 2.4, COL_DBG_LIMB)
		if limb.stepping:
			draw_line(limb.step_from, limb.step_to, COL_FOOT_STEPPING, 1.0, true)
			draw_arc(limb.step_to, 3.0, 0.0, TAU, 12, COL_FOOT_STEPPING, 1.5, true)
			# Lift is fake height, drawn as the gap between foot and shadow.
			draw_line(limb.ground, limb.joints[2], Color(1, 1, 1, 0.35), 1.0, true)

	# Heading and velocity of the head.
	draw_line(creature.head_pos, creature.head_pos + creature.move_dir * 34.0, Color(1, 0.9, 0.3, 0.7), 1.5, true)
